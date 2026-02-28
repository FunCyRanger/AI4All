//! P2P network layer using libp2p.
//! Handles peer discovery (mDNS + Kademlia) and message routing (Gossipsub).

use anyhow::Result;
use futures::StreamExt;
use libp2p::{
    gossipsub, identify, kad, mdns, noise, ping,
    swarm::{NetworkBehaviour, SwarmEvent},
    tcp, yamux, Multiaddr, PeerId, SwarmBuilder,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashSet,
    hash::{DefaultHasher, Hash, Hasher},
    time::Duration,
};
use tokio::sync::mpsc;
use tracing::{debug, info, warn};

use crate::config::NodeConfig;

// ── Commands sent to the network from the API ──────────────────────────────

#[derive(Debug)]
pub enum NetworkCommand {
    /// Broadcast node capabilities to the network
    AnnounceCapabilities(NodeCapabilities),
    /// Request inference from the best available peer
    RouteInference {
        model:      String,
        payload:    Vec<u8>,
        reply_tx:   tokio::sync::oneshot::Sender<Result<Vec<u8>>>,
    },
    /// Get connected peer count
    PeerCount(tokio::sync::oneshot::Sender<usize>),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeCapabilities {
    pub node_id:      String,
    pub models:       Vec<String>,
    pub memory_gb:    f32,
    pub layer_ranges: Vec<(String, usize, usize)>, // (model, start, end)
}

// ── libp2p behaviour ──────────────────────────────────────────────────────

#[derive(NetworkBehaviour)]
struct Behaviour {
    gossipsub: gossipsub::Behaviour,
    kademlia:  kad::Behaviour<kad::store::MemoryStore>,
    mdns:      mdns::tokio::Behaviour,
    identify:  identify::Behaviour,
    ping:      ping::Behaviour,
}

// ── Public handle ─────────────────────────────────────────────────────────

pub struct P2PNetwork;

impl P2PNetwork {
    pub async fn start(cfg: &NodeConfig) -> Result<(tokio::task::JoinHandle<()>, mpsc::Sender<NetworkCommand>)> {
        let (cmd_tx, cmd_rx) = mpsc::channel::<NetworkCommand>(64);

        let listen_addr: Multiaddr = cfg.listen_addr.parse()?;
        let seed_peers: Vec<Multiaddr> = cfg.seed_peers
            .iter()
            .filter_map(|s| s.parse().ok())
            .collect();

        let handle = tokio::spawn(run_network(listen_addr, seed_peers, cmd_rx));
        Ok((handle, cmd_tx))
    }
}

async fn run_network(
    listen_addr: Multiaddr,
    seed_peers: Vec<Multiaddr>,
    mut cmd_rx: mpsc::Receiver<NetworkCommand>,
) {
    let mut swarm = SwarmBuilder::with_new_identity()
        .with_tokio()
        .with_tcp(
            tcp::Config::default(),
            noise::Config::new,
            yamux::Config::default,
        )
        .expect("TCP transport")
        .with_behaviour(|key| {
            // Gossipsub
            let msg_id_fn = |message: &gossipsub::Message| {
                let mut s = DefaultHasher::new();
                message.data.hash(&mut s);
                gossipsub::MessageId::from(s.finish().to_string())
            };
            let gossipsub_config = gossipsub::ConfigBuilder::default()
                .heartbeat_interval(Duration::from_secs(10))
                .validation_mode(gossipsub::ValidationMode::Strict)
                .message_id_fn(msg_id_fn)
                .build()
                .expect("gossipsub config");

            let gossipsub = gossipsub::Behaviour::new(
                gossipsub::MessageAuthenticity::Signed(key.clone()),
                gossipsub_config,
            )
            .expect("gossipsub");

            // Kademlia
            let kademlia = kad::Behaviour::new(
                key.public().to_peer_id(),
                kad::store::MemoryStore::new(key.public().to_peer_id()),
            );

            // mDNS (local discovery)
            let mdns = mdns::tokio::Behaviour::new(
                mdns::Config::default(),
                key.public().to_peer_id(),
            )
            .expect("mdns");

            // Identify
            let identify = identify::Behaviour::new(identify::Config::new(
                "/ai4all/1.0.0".to_string(),
                key.public(),
            ));

            let ping = ping::Behaviour::new(ping::Config::new());

            Ok(Behaviour { gossipsub, kademlia, mdns, identify, ping })
        })
        .expect("behaviour")
        .with_swarm_config(|c| c.with_idle_connection_timeout(Duration::from_secs(60)))
        .build();

    // Subscribe to AI4All topics
    let caps_topic = gossipsub::IdentTopic::new("ai4all/capabilities");
    let inf_topic  = gossipsub::IdentTopic::new("ai4all/inference");
    swarm.behaviour_mut().gossipsub.subscribe(&caps_topic).ok();
    swarm.behaviour_mut().gossipsub.subscribe(&inf_topic).ok();

    // Listen
    swarm.listen_on(listen_addr.clone()).expect("listen");
    info!(addr = %listen_addr, "P2P listening");

    // Connect to seed peers
    for addr in &seed_peers {
        swarm.dial(addr.clone()).ok();
        info!(peer = %addr, "Dialing seed peer");
    }

    let mut connected_peers: HashSet<PeerId> = HashSet::new();

    loop {
        tokio::select! {
            // Handle commands from the API
            cmd = cmd_rx.recv() => {
                match cmd {
                    None => break,
                    Some(NetworkCommand::PeerCount(tx)) => {
                        tx.send(connected_peers.len()).ok();
                    }
                    Some(NetworkCommand::AnnounceCapabilities(caps)) => {
                        if let Ok(data) = serde_json::to_vec(&caps) {
                            swarm.behaviour_mut().gossipsub
                                .publish(caps_topic.clone(), data).ok();
                        }
                    }
                    Some(NetworkCommand::RouteInference { model, payload, reply_tx }) => {
                        // Phase 1: local inference only (via Ollama)
                        // Phase 2: route to best peer based on model registry
                        warn!("Distributed inference routing not yet implemented – use local Ollama");
                        reply_tx.send(Err(anyhow::anyhow!("Not yet routed"))).ok();
                    }
                }
            }

            // Handle swarm events
            event = swarm.select_next_some() => {
                match event {
                    SwarmEvent::NewListenAddr { address, .. } => {
                        info!(%address, "New listen address");
                    }
                    SwarmEvent::ConnectionEstablished { peer_id, .. } => {
                        info!(%peer_id, "Peer connected");
                        connected_peers.insert(peer_id);
                        swarm.behaviour_mut().kademlia.add_address(&peer_id, listen_addr.clone());
                    }
                    SwarmEvent::ConnectionClosed { peer_id, .. } => {
                        debug!(%peer_id, "Peer disconnected");
                        connected_peers.remove(&peer_id);
                    }
                    SwarmEvent::Behaviour(BehaviourEvent::Mdns(mdns::Event::Discovered(peers))) => {
                        for (peer, addr) in peers {
                            info!(%peer, %addr, "mDNS discovered local peer");
                            swarm.dial(addr).ok();
                        }
                    }
                    SwarmEvent::Behaviour(BehaviourEvent::Gossipsub(
                        gossipsub::Event::Message { message, .. }
                    )) => {
                        if let Ok(caps) = serde_json::from_slice::<NodeCapabilities>(&message.data) {
                            info!(node_id = %caps.node_id, models = ?caps.models, "Peer capabilities received");
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}
