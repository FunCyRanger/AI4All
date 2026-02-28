mod config;
mod network;
mod tokens;
mod api;

use anyhow::Result;
use clap::Parser;
use tracing::info;

/// AI4All Node – Decentralized AI inference network
#[derive(Parser, Debug)]
#[command(name = "ai4all", version, about)]
struct Cli {
    #[arg(short, long, default_value = "config.toml", env = "AI4ALL_CONFIG")]
    config: String,
    #[arg(long, env = "AI4ALL_LOG_LEVEL", default_value = "info")]
    log_level: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    tracing_subscriber::fmt().with_env_filter(&cli.log_level).init();
    info!("🚀 Starting AI4All Node v{}", env!("CARGO_PKG_VERSION"));

    let cfg = config::NodeConfig::load(&cli.config)?;
    info!(node_id = %cfg.node_id, mode = %cfg.mode, "Configuration loaded");

    let wallet = tokens::Wallet::load_or_create(&cfg.wallet_path).await?;
    info!(balance = wallet.balance(), "Token wallet ready");

    let (network_handle, cmd_tx) = network::P2PNetwork::start(&cfg).await?;
    info!("P2P network started – listening on {}", cfg.listen_addr);

    let api_handle = api::start(cfg.api_port, cmd_tx, wallet).await?;
    info!(port = cfg.api_port, "Local API server ready at http://127.0.0.1:{}", cfg.api_port);

    tokio::select! {
        _ = network_handle => tracing::warn!("P2P network stopped"),
        _ = tokio::signal::ctrl_c() => info!("Shutting down..."),
    }

    api_handle.abort();
    info!("Goodbye 👋");
    Ok(())
}
