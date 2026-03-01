"""
AI4All API Gateway – OpenAI-compatible REST API
Routes requests to local Ollama or the P2P network.

Start:  uvicorn main:app --host 0.0.0.0 --port 8000
Docs:   http://localhost:8000/docs
"""

from __future__ import annotations
import asyncio, json, time, uuid
from contextlib import asynccontextmanager
from typing import AsyncIterator, Literal, Optional

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


# ── Settings ──────────────────────────────────────────────────────────────

class Settings(BaseSettings):
    ollama_url:    str  = "http://localhost:11434"
    node_api_url:  str  = "http://127.0.0.1:7070"
    cors_origins:  list[str] = ["*"]
    log_level:     str  = "info"

    model_config = SettingsConfigDict(env_prefix="AI4ALL_")

settings = Settings()

# Model registry: maps AI4All model names → Ollama model tags
MODEL_REGISTRY: dict[str, dict] = {
    "ai4all/llama3":        {"ollama": "llama3",         "category": "general",  "description": "General purpose – LLaMA 3 8B"},
    "ai4all/llama3:70b":    {"ollama": "llama3:70b",     "category": "general",  "description": "General purpose – LLaMA 3 70B (distributed)"},
    "ai4all/codellama":     {"ollama": "codellama",      "category": "code",     "description": "Code generation – CodeLlama 7B"},
    "ai4all/codellama:34b": {"ollama": "codellama:34b",  "category": "code",     "description": "Code generation – CodeLlama 34B (distributed)"},
    "ai4all/mistral":       {"ollama": "mistral",        "category": "general",  "description": "Mistral 7B – fast and capable"},
    "ai4all/moondream":     {"ollama": "moondream",      "category": "vision",   "description": "Vision – image analysis"},
    "ai4all/phi3":          {"ollama": "phi3",           "category": "general",  "description": "Microsoft Phi-3 – efficient reasoning"},
    "ai4all/gemma2":        {"ollama": "gemma2",         "category": "general",  "description": "Google Gemma 2 9B"},
}

# ── Lifespan ───────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.http = httpx.AsyncClient(timeout=300.0)
    yield
    await app.state.http.aclose()

app = FastAPI(
    title="AI4All API",
    description="OpenAI-compatible gateway for the AI4All decentralized AI network.",
    version="0.1.0",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Schemas ────────────────────────────────────────────────────────────────

class Message(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str

class ChatRequest(BaseModel):
    model: str = "ai4all/llama3"
    messages: list[Message]
    stream: bool = False
    temperature: float = Field(0.7, ge=0.0, le=2.0)
    max_tokens: int = Field(2048, gt=0, le=32768)

class ModelInfo(BaseModel):
    id: str
    object: str = "model"
    owned_by: str = "ai4all-community"
    category: str = "general"
    description: str = ""
    created: int = Field(default_factory=lambda: int(time.time()))

# ── Helpers ────────────────────────────────────────────────────────────────

def resolve_model(ai4all_model: str) -> str:
    """Map AI4All model name → Ollama model name."""
    entry = MODEL_REGISTRY.get(ai4all_model)
    if entry:
        return entry["ollama"]
    # Allow passing Ollama model names directly
    return ai4all_model

def count_tokens(text: str) -> int:
    return max(1, len(text.split()))

def messages_to_ollama(messages: list[Message]) -> tuple[str, list[dict]]:
    """Convert OpenAI-style messages to Ollama format."""
    system = ""
    chat_messages = []
    for m in messages:
        if m.role == "system":
            system = m.content
        else:
            chat_messages.append({"role": m.role, "content": m.content})
    return system, chat_messages

async def track_tokens(request: Request, prompt_tokens: int, completion_tokens: int, model: str) -> None:
    """Deduct tokens for a request (async, fire-and-forget)."""
    cost = max(1, (prompt_tokens + completion_tokens) // 100)
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            await client.post(
                f"{settings.node_api_url}/v1/tokens/spend",
                json={"amount": cost, "memo": f"inference:{model}:{prompt_tokens}p+{completion_tokens}c"},
            )
    except Exception:
        pass  # Token accounting is best-effort

# ── Routes ─────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    # Ping node daemon
    node_ok = False
    try:
        async with httpx.AsyncClient(timeout=1.0) as c:
            r = await c.get(f"{settings.node_api_url}/health")
            node_ok = r.status_code == 200
    except Exception:
        pass
    return {"status": "ok", "version": "0.1.0", "node_daemon": node_ok}


@app.get("/v1/models")
async def list_models(request: Request):
    """Return available models. Merges static registry with live Ollama list."""
    available = set()
    try:
        r = await request.app.state.http.get(f"{settings.ollama_url}/api/tags")
        if r.status_code == 200:
            for m in r.json().get("models", []):
                available.add(m["name"].split(":")[0])  # base name
    except Exception:
        pass

    models = []
    for ai4all_id, info in MODEL_REGISTRY.items():
        ollama_base = info["ollama"].split(":")[0]
        models.append(ModelInfo(
            id=ai4all_id,
            category=info["category"],
            description=info["description"],
        ).model_dump())

    return {"object": "list", "data": models}


@app.get("/v1/node/status")
async def node_status(request: Request):
    try:
        r = await request.app.state.http.get(f"{settings.node_api_url}/v1/node/status")
        return r.json()
    except Exception:
        return {"error": "Node daemon not reachable"}


@app.get("/v1/tokens/balance")
async def token_balance(request: Request):
    try:
        r = await request.app.state.http.get(f"{settings.node_api_url}/v1/tokens")
        return r.json()
    except Exception:
        return {"balance": 0, "error": "Node daemon not reachable"}


@app.post("/v1/chat/completions")
async def chat_completions(body: ChatRequest, request: Request):
    """
    OpenAI-compatible chat completions endpoint.
    Routes to local Ollama for Phase 1 MVP.
    Phase 2 will route large models through the P2P network.
    """
    ollama_model = resolve_model(body.model)
    system, messages = messages_to_ollama(body.messages)
    request_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"
    prompt_tokens = sum(count_tokens(m.content) for m in body.messages)

    payload = {
        "model":   ollama_model,
        "messages": messages,
        "stream":  body.stream,
        "options": {
            "temperature": body.temperature,
            "num_predict": body.max_tokens,
        },
    }
    if system:
        payload["system"] = system

    ollama_endpoint = f"{settings.ollama_url}/api/chat"

    if body.stream:
        return StreamingResponse(
            _stream_ollama(request, ollama_endpoint, payload, request_id, body.model, prompt_tokens),
            media_type="text/event-stream",
            headers={"X-Request-Id": request_id},
        )

    # Non-streaming
    try:
        r = await request.app.state.http.post(ollama_endpoint, json=payload)
        r.raise_for_status()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=502, detail=f"Ollama error: {e.response.text}")
    except httpx.ConnectError:
        raise HTTPException(status_code=503, detail=(
            "Cannot reach Ollama. Is it running? Start with: ollama serve"
        ))

    data = r.json()
    content = data.get("message", {}).get("content", "")
    completion_tokens = count_tokens(content)

    asyncio.create_task(
        track_tokens(request, prompt_tokens, completion_tokens, body.model)
    )

    return {
        "id": request_id,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": body.model,
        "choices": [{
            "index": 0,
            "message": {"role": "assistant", "content": content},
            "finish_reason": "stop",
        }],
        "usage": {
            "prompt_tokens":     prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens":      prompt_tokens + completion_tokens,
        },
    }


async def _stream_ollama(
    request: Request,
    endpoint: str,
    payload: dict,
    request_id: str,
    model: str,
    prompt_tokens: int,
):
    """Stream Ollama response as OpenAI SSE chunks."""
    completion_tokens = 0
    try:
        async with request.app.state.http.stream("POST", endpoint, json=payload) as r:
            async for line in r.aiter_lines():
                if not line.strip():
                    continue
                try:
                    chunk = json.loads(line)
                except json.JSONDecodeError:
                    continue

                token = chunk.get("message", {}).get("content", "")
                done  = chunk.get("done", False)
                completion_tokens += count_tokens(token)

                sse_chunk = {
                    "id": request_id,
                    "object": "chat.completion.chunk",
                    "created": int(time.time()),
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "delta": {"content": token} if not done else {},
                        "finish_reason": "stop" if done else None,
                    }],
                }
                yield f"data: {json.dumps(sse_chunk)}\n\n"

                if done:
                    break

    except httpx.ConnectError:
        error_chunk = {"error": {"message": "Cannot reach Ollama. Run: ollama serve", "type": "connection_error"}}
        yield f"data: {json.dumps(error_chunk)}\n\n"

    yield "data: [DONE]\n\n"
    asyncio.create_task(
        track_tokens(request, prompt_tokens, completion_tokens, model)
    )


# ── GPU Info endpoint ──────────────────────────────────────────────────────

class GpuDevice(BaseModel):
    index:    int
    vendor:   str
    name:     str
    vram_gb:  int
    vram_free_gb: int
    utilization_pct: Optional[int] = None
    compute_capability: Optional[str] = None

class GpuStatus(BaseModel):
    backend:   str
    available: bool
    devices:   list[GpuDevice]

@app.get("/v1/gpu", response_model=GpuStatus)
async def gpu_info(request: Request) -> GpuStatus:
    """Return GPU status from the local node daemon."""
    try:
        r = await request.app.state.http.get(f"{settings.node_api_url}/v1/gpu")
        data = r.json()
        return GpuStatus(**data)
    except Exception:
        # Fallback: query nvidia-smi / rocm-smi directly if node daemon is not running
        return _gpu_fallback()

def _gpu_fallback() -> GpuStatus:
    """Direct GPU detection without the Rust daemon."""
    import subprocess

    devices: list[GpuDevice] = []

    # Try NVIDIA
    try:
        out = subprocess.check_output([
            "nvidia-smi",
            "--query-gpu=index,name,memory.total,memory.free,utilization.gpu,compute_cap",
            "--format=csv,noheader,nounits",
        ], text=True, stderr=subprocess.DEVNULL)
        for line in out.strip().splitlines():
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 6:
                devices.append(GpuDevice(
                    index=int(parts[0]),
                    vendor="Nvidia",
                    name=parts[1],
                    vram_gb=int(parts[2]) // 1024,
                    vram_free_gb=int(parts[3]) // 1024,
                    utilization_pct=int(parts[4]) if parts[4].isdigit() else None,
                    compute_capability=parts[5],
                ))
    except Exception:
        pass

    # Try AMD
    if not devices:
        try:
            subprocess.check_call(["rocm-smi", "--version"],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            devices.append(GpuDevice(
                index=0, vendor="Amd", name="AMD GPU (ROCm)", vram_gb=0, vram_free_gb=0
            ))
        except Exception:
            pass

    backend = "None"
    if devices:
        vendors = {d.vendor for d in devices}
        if "Nvidia" in vendors and "Amd" in vendors: backend = "Mixed"
        elif "Nvidia" in vendors: backend = "Cuda"
        elif "Amd" in vendors: backend = "Rocm"

    return GpuStatus(backend=backend, available=bool(devices), devices=devices)


# ── System Stats ───────────────────────────────────────────────────────────
import psutil, subprocess

@app.get("/v1/system/stats")
async def system_stats():
    """CPU, RAM, GPU utilization for the dashboard."""
    cpu_pct  = psutil.cpu_percent(interval=0.2)
    mem      = psutil.virtual_memory()
    ram_pct  = mem.percent
    ram_used = mem.used  // (1024**3)
    ram_total= mem.total // (1024**3)

    gpu_stats = []

    # NVIDIA
    try:
        out = subprocess.check_output([
            "nvidia-smi",
            "--query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu",
            "--format=csv,noheader,nounits"
        ], text=True, stderr=subprocess.DEVNULL)
        for line in out.strip().splitlines():
            p = [x.strip() for x in line.split(",")]
            if len(p) >= 6:
                gpu_stats.append({
                    "index":     int(p[0]),
                    "name":      p[1],
                    "vendor":    "NVIDIA",
                    "util_pct":  int(p[2]) if p[2].isdigit() else 0,
                    "vram_used": int(p[3]) if p[3].isdigit() else 0,
                    "vram_total":int(p[4]) if p[4].isdigit() else 0,
                    "temp_c":    int(p[5]) if p[5].isdigit() else None,
                })
    except Exception:
        pass

    # AMD
    if not gpu_stats:
        try:
            out = subprocess.check_output(
                ["rocm-smi", "--showuse", "--showmeminfo", "vram", "--showtemp", "--csv"],
                text=True, stderr=subprocess.DEVNULL
            )
            lines = [l for l in out.strip().splitlines() if l and not l.startswith("#")]
            if len(lines) >= 2:
                headers = [h.lower() for h in lines[0].split(",")]
                for row in lines[1:]:
                    vals = row.split(",")
                    def get(kw):
                        i = next((i for i,h in enumerate(headers) if kw in h), None)
                        return vals[i].strip() if i is not None and i < len(vals) else "0"
                    vram_total = int(get("total memory") or 0) // (1024*1024)
                    vram_used  = int(get("used memory")  or 0) // (1024*1024)
                    gpu_stats.append({
                        "index":      0,
                        "name":       "AMD GPU",
                        "vendor":     "AMD",
                        "util_pct":   int(float(get("gpu use").rstrip("%") or 0)),
                        "vram_used":  vram_used,
                        "vram_total": vram_total,
                        "temp_c":     int(float(get("temperature").rstrip("c").rstrip("°") or 0)) or None,
                    })
        except Exception:
            pass

    return {
        "cpu_pct":   round(cpu_pct, 1),
        "ram_pct":   round(ram_pct, 1),
        "ram_used_gb":  ram_used,
        "ram_total_gb": ram_total,
        "gpu":       gpu_stats,
    }


# ── Starter token grant ────────────────────────────────────────────────────

_granted_sessions: set[str] = set()

class StarterGrantRequest(BaseModel):
    session_id: str

@app.post("/v1/tokens/starter")
async def grant_starter_tokens(body: StarterGrantRequest):
    """Grant 10 starter tokens to a new session (one-time per session)."""
    if body.session_id in _granted_sessions:
        return {"granted": False, "reason": "already_granted", "amount": 0}
    _granted_sessions.add(body.session_id)
    # Try to credit via node daemon
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            await c.post(f"{settings.node_api_url}/v1/tokens/earn",
                         json={"amount": 10, "memo": "welcome_bonus"})
    except Exception:
        pass  # best-effort
    return {"granted": True, "amount": 10, "message": "Willkommen! Du erhältst 10 Starter-Tokens."}
