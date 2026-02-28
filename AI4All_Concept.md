# AI4All – Decentralized AI Network for Everyone

> **Vision:** A community-operated AI infrastructure where every user gains access to powerful AI by sharing their computing resources – no central providers, no dependencies, no gatekeepers.

---

## 1. Core Principles

| Principle | Description |
|---|---|
| **Decentralization** | No central server. Every node is equal. |
| **Fairness** | Token system ensures: those who contribute, benefit. |
| **Privacy** | Requests are split, encrypted, and never fully exposed to a single node. |
| **Common Good** | Open source, non-profit, community governance. |
| **Legal Compliance** | GDPR-compliant, no personal data stored on third-party devices. |

---

## 2. System Architecture (Overview)

```
┌─────────────────────────────────────────────────────────────┐
│                      AI4All Network                          │
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │  Node A  │◄──►│  Node B  │◄──►│  Node C  │  ...        │
│  │(Raspberry│    │ (Windows │    │  (Linux  │              │
│  │   Pi)    │    │  PC)     │    │  Server) │              │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘              │
│       │               │               │                     │
│       └───────────────┴───────────────┘                     │
│                    P2P Mesh                                  │
│              (libp2p / WebRTC)                               │
└──────────────────────┬──────────────────────────────────────┘
                       │
         ┌─────────────┴──────────────┐
         │                            │
   ┌─────▼──────┐              ┌──────▼─────┐
   │   Web UI   │              │    API     │
   │(OpenWebUI- │              │  (REST /   │
   │  based)    │              │ GraphQL)   │
   └─────────────┘              └────────────┘
```

---

## 3. Components in Detail

### 3.1 AI4All Node (Client)

The client is the heart of the system. It runs on the user's device and fulfills multiple roles simultaneously.

**Platform Support:**
- Windows (Electron app or native binary)
- Linux (AppImage / Snap / deb / rpm)
- macOS (Universal Binary for Intel + Apple Silicon)
- Android (background service, restricted mode)
- Raspberry Pi / ARM devices (lightweight mode)

**Node Technology Stack:**
```
┌─────────────────────────────────┐
│         AI4All Node             │
├─────────────────────────────────┤
│  Inference Engine               │
│  → llama.cpp (CPU/GPU/Metal)    │
│  → ONNX Runtime                 │
│  → MLC-LLM (mobile)             │
├─────────────────────────────────┤
│  Model Sharding Layer           │
│  → Tensor Slicing per Layer     │
│  → Pipeline Parallelism         │
├─────────────────────────────────┤
│  P2P Network Layer              │
│  → libp2p (Go/Rust)             │
│  → Kademlia DHT                 │
├─────────────────────────────────┤
│  Token Accounting               │
│  → local wallet                 │
│  → signed transactions          │
├─────────────────────────────────┤
│  Security Sandbox               │
│  → WASM Isolation               │
│  → Resource Limits              │
└─────────────────────────────────┘
```

### 3.2 Model Sharding (Distributed Memory)

The core technical challenge: LLMs are too large for individual devices.

**Solution – Pipeline Parallelism:**
```
Model (e.g. LLaMA 70B, ~40GB)
│
├── Layers  0–20  ──►  Node A (16 GB RAM)
├── Layers 21–40  ──►  Node B  (8 GB RAM)
└── Layers 41–80  ──►  Node C (16 GB RAM)

Activations are encrypted and passed between nodes.
```

**Technical Approach:**
- Inspired by **Petals** (BitTorrent for LLMs) – already proven in practice
- Nodes only store parts of a model (layer chunks)
- Activations (not the prompt itself) travel through the layer chain
- The prompt is encrypted and only decrypted at the first layer

**Alternative Approach – Tensor Parallelism:**
- Width-based splitting (weight matrices are partitioned)
- Higher communication overhead, but better suited for homogeneous networks

### 3.3 Token System (Fairness Mechanism)

The token system is not blockchain-based (too energy-intensive), but relies on a **signed reputation ledger**:

```
┌────────────────────────────────────────────┐
│           AI4All Token System              │
├────────────────────────────────────────────┤
│                                            │
│  Providing compute resources               │
│  → +tokens per processed inference unit   │
│  → bonus for high availability (uptime)    │
│  → bonus for hosting rare model layers     │
│                                            │
│  Consuming compute resources               │
│  → -tokens per request (by complexity)     │
│  → lower cost for higher contributors      │
│                                            │
│  Fairness Rules                            │
│  → maximum token accumulation is capped   │
│  → new users receive starter tokens        │
│  → inactive nodes do not lose tokens       │
│    (they just stop earning new ones)       │
│                                            │
└────────────────────────────────────────────┘
```

**Ledger Technology:** No full blockchain overhead required. Instead:
- **Signed receipts** between nodes (similar to IOTA / Directed Acyclic Graphs)
- Periodic consensus rounds via a gossip protocol
- Decentralized validator nodes (elected from long-standing community members)

### 3.4 Privacy & Security

**Core challenge:** How do we prevent a node from reading another user's prompt?

**Solutions:**

1. **Prompt Fragmentation:** The prompt is split into fragments processed by different nodes – no single node ever knows the full context.

2. **Homomorphic Encryption (long-term):** Computation on encrypted data – still too slow for production use, but an active research area.

3. **Trusted Execution Environments (TEE):** AMD SEV or Intel TDX – computations happen inside an isolated enclave that cannot be read from outside.

4. **Differential Privacy:** Activations passed between nodes are slightly noised in a way that does not distort the result but prevents reverse-engineering.

5. **WASM Sandbox for Node Code:** Every computation task runs inside an isolated WebAssembly sandbox – no access to the host system.

**Additional Safeguards:**
- Nodes only see their own layer activations, never the plaintext prompt
- No storage of requests on third-party devices
- Resource sharing is always opt-in – users retain full control
- Rate limiting to prevent abuse
- Reputation system: misbehaving nodes are excluded from the network

### 3.5 P2P Network

**Technology:** libp2p (the same foundation as IPFS and Ethereum)

```
Discovery:
  → Kademlia DHT for node discovery
  → mDNS for local networks (LAN boost)

Transport:
  → QUIC (primary, NAT-traversal capable)
  → WebRTC (browser compatibility)
  → TCP (fallback)

Routing:
  → Requests are routed to nodes
    that hold the required model layers
  → Latency-optimized routing
    (geographic proximity preferred)
```

---

## 4. Model Categories & Specializations

```
AI4All Model Registry (decentralized, via IPFS / Arweave)

├── 🖼️  Vision & Media
│   ├── LLaVA / Moondream (image analysis)
│   ├── VideoLLaMA (video analysis)
│   └── Whisper (audio transcription)
│
├── 💻  Code & Development
│   ├── CodeLlama 34B
│   ├── DeepSeek Coder
│   └── Qwen2.5-Coder
│
├── 🔬  Science & Knowledge
│   ├── LLaMA 3.1 70B (general purpose)
│   ├── Meditron (medicine / health)
│   └── LegalBERT derivatives (law)
│
├── 🌐  Research & Web
│   ├── Model + integrated web search agent
│   └── RAG pipeline over SearXNG (self-hosted)
│
└── 🗣️  Multilingual
    ├── BLOOM derivatives
    └── Aya (Cohere, 100+ languages)
```

---

## 5. Web UI & API

### Web UI (Based on Open WebUI)

Open WebUI is the ideal foundation because:
- Already fully compatible with Ollama
- Supports multi-model selection out of the box
- Active community, MIT license
- Extensible via plugins and custom functions

**AI4All-specific extensions:**
```
Open WebUI
├── + Token balance display (header)
├── + Node status dashboard
├── + Model category selection (icons)
├── + Privacy indicator per request
├── + Network contribution settings
└── + Community models (from decentralized registry)
```

### REST API

```yaml
# Compatible with OpenAI API schema
POST /v1/chat/completions
  → model: "ai4all/codellama-34b"
  → messages: [...]
  → response: streaming SSE

GET /v1/models
  → list of all available community models

GET /v1/tokens/balance
  → current token balance

GET /v1/node/status
  → own contribution, uptime, active layers
```

---

## 6. Technology Stack Summary

| Layer | Technology | Reason |
|---|---|---|
| Inference | llama.cpp, MLC-LLM | CPU/GPU/Metal, all platforms |
| Model Sharding | Petals concept (custom impl.) | Proven, open source |
| P2P Network | libp2p (Go or Rust) | Industry standard, IPFS-proven |
| Node Client | Rust (core) + Electron (GUI) | Performance + cross-platform |
| Web UI | Open WebUI (fork) | Feature-rich, active community |
| API | FastAPI (Python) or Axum (Rust) | Simple, performant |
| Token Ledger | DAG + Gossip (custom) | No blockchain overhead |
| Model Registry | IPFS + Arweave | Decentralized, immutable |
| Security | WASM Sandbox, TEE (optional) | Battle-tested, extensible |
| Authentication | DID (Decentralized Identity) | No central login required |

---

## 7. Development Roadmap

### Phase 1 – MVP (Months 0–6)
- [ ] Node client for Linux & Windows
- [ ] Basic P2P network (libp2p)
- [ ] Single model (LLaMA 3.1 8B) distributed across 2–4 nodes
- [ ] Simple token system (without consensus)
- [ ] Open WebUI integration
- [ ] GitHub repository + documentation

### Phase 2 – Community Beta (Months 6–12)
- [ ] Model sharding for models up to 70B
- [ ] macOS & Android client
- [ ] Token consensus mechanism
- [ ] Model registry (IPFS)
- [ ] Specialized model categories
- [ ] Privacy layer (prompt fragmentation)

### Phase 3 – Stabilization (Months 12–24)
- [ ] TEE integration (AMD SEV)
- [ ] Web search agent (SearXNG)
- [ ] Community governance (model voting)
- [ ] Mobile-optimized light node
- [ ] Security audit

---

## 8. Comparison with Existing Projects

| Project | Approach | AI4All Difference |
|---|---|---|
| **Petals** | Layer sharing for LLMs | Our main inspiration – extended with token system, UI, broader platform support |
| **Bittensor** | Blockchain-based | Too complex, high energy overhead from consensus |
| **Ollama** | Local, no P2P | No community aspect |
| **Golem** | General computing | Not AI-specific, complex setup |
| **IPFS** | File sharing | Storage only, no inference |

**AI4All is closest to Petals** – but focused on:
- User-friendliness (GUI, WebUI)
- Fairness mechanism (tokens)
- Privacy by design
- Broad platform support

---

## 9. GitHub Repository Structure

```
AI4All/
├── core/                  # Rust: P2P, inference, token logic
│   ├── node/              # Node daemon
│   ├── inference/         # llama.cpp bindings
│   ├── network/           # libp2p integration
│   └── tokens/            # Token accounting
├── clients/
│   ├── desktop/           # Electron app
│   ├── android/           # Android service
│   └── cli/               # Command line interface
├── api/                   # FastAPI gateway
├── webui/                 # Open WebUI fork
├── registry/              # Decentralized model registry
├── docs/                  # Documentation
└── scripts/               # Setup & deployment
```

---

## 10. Open Challenges

**Latency:** Pipeline parallelism introduces network overhead. Realistic response times for 70B models are 5–30 seconds. Acceptable for many use cases, but worth communicating clearly to users.

**Node availability:** The network needs a critical mass of roughly 100+ active nodes to be reliable. Community building is crucial – a small number of dedicated seed servers at launch would help bootstrap this.

**Model updates:** When a model is updated, all nodes storing its layers need to synchronize. A coordinated rolling update mechanism is required.

**Licensing:** Model licenses (e.g. LLaMA Community License) restrict commercial use. AI4All must be explicitly positioned as non-commercial to remain compliant.

**Abuse prevention:** The token system must resist Sybil attacks (many fake nodes). A lightweight proof-of-contribution or human verification step will be necessary.

---

## 11. Contributing

AI4All is built by and for the community. All contributions are welcome:

- **Developers:** Pick up issues on GitHub, improve the core node, or extend the Web UI
- **Node operators:** Run a node and help grow the network
- **Researchers:** Improve privacy mechanisms, sharding efficiency, or consensus design
- **Translators:** Help make the documentation accessible in more languages
- **Advocates:** Spread the word and help build the community

Please read `CONTRIBUTING.md` before submitting your first pull request.

---

*AI4All – AI belongs to everyone.*
*License: Apache 2.0 | Governance: Community DAO*
