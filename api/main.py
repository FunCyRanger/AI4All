"""
AI4All API Gateway – OpenAI-compatible REST API
"""
from __future__ import annotations

import asyncio
import json
import subprocess
import time
import uuid
from contextlib import asynccontextmanager
from typing import AsyncIterator, Literal, Optional

import httpx
import psutil
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


# ── Settings ───────────────────────────────────────────────────────────────
class Settings(BaseSettings):
    ollama_url:   str       = "http://localhost:11434"
    node_api_url: str       = "http://127.0.0.1:7070"
    cors_origins: list[str] = ["*"]
    model_config = SettingsConfigDict(env_prefix="AI4ALL_")

settings = Settings()

MODEL_REGISTRY: dict[str, dict] = {
    "ai4all/llama3":        {"ollama": "llama3",        "category": "general", "description": "General purpose – LLaMA 3 8B"},
    "ai4all/llama3:70b":    {"ollama": "llama3:70b",    "category": "general", "description": "General purpose – LLaMA 3 70B"},
    "ai4all/codellama":     {"ollama": "codellama",     "category": "code",    "description": "Code generation – CodeLlama 7B"},
    "ai4all/codellama:34b": {"ollama": "codellama:34b", "category": "code",    "description": "Code generation – CodeLlama 34B"},
    "ai4all/mistral":       {"ollama": "mistral",       "category": "general", "description": "Mistral 7B – fast and capable"},
    "ai4all/moondream":     {"ollama": "moondream",     "category": "vision",  "description": "Vision – image analysis"},
    "ai4all/phi3":          {"ollama": "phi3",          "category": "general", "description": "Microsoft Phi-3 – efficient reasoning"},
    "ai4all/gemma2":        {"ollama": "gemma2",        "category": "general", "description": "Google Gemma 2 9B"},
}

_granted_sessions: set[str] = set()

# ── Lifespan ───────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # Warm up cpu_percent so first call returns a real value (not 0.0)
    psutil.cpu_percent(interval=None)
    app.state.http = httpx.AsyncClient(timeout=300.0)
    yield
    await app.state.http.aclose()

app = FastAPI(title="AI4All API", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True,
                   allow_methods=["*"], allow_headers=["*"])

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
    id: str; object: str = "model"; owned_by: str = "ai4all-community"
    category: str = "general"; description: str = ""
    created: int = Field(default_factory=lambda: int(time.time()))

class GpuDevice(BaseModel):
    index: int; vendor: str; name: str
    vram_gb: int; vram_free_gb: int
    utilization_pct: Optional[int] = None
    compute_capability: Optional[str] = None

class GpuStatus(BaseModel):
    backend: str; available: bool; devices: list[GpuDevice]

class StarterGrantRequest(BaseModel):
    session_id: str

# ── Helpers ────────────────────────────────────────────────────────────────
def resolve_model(m: str) -> str:
    return MODEL_REGISTRY.get(m, {}).get("ollama", m)

def count_tokens(text: str) -> int:
    return max(1, len(text.split()))

def messages_to_ollama(msgs: list[Message]) -> tuple[str, list[dict]]:
    system = ""
    chat: list[dict] = []
    for m in msgs:
        if m.role == "system": system = m.content
        else: chat.append({"role": m.role, "content": m.content})
    return system, chat

async def track_tokens(amount: int, model: str) -> None:
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            await c.post(f"{settings.node_api_url}/v1/tokens/spend",
                         json={"amount": amount, "memo": f"inference:{model}"})
    except Exception:
        pass

def _run_cmd(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)

# ── Sync workers (run in thread pool via asyncio.to_thread) ────────────────
def _gpu_status_sync() -> GpuStatus:
    devices: list[GpuDevice] = []
    try:
        out = _run_cmd(["nvidia-smi",
            "--query-gpu=index,name,memory.total,memory.free,utilization.gpu,compute_cap",
            "--format=csv,noheader,nounits"])
        for line in out.strip().splitlines():
            p = [x.strip() for x in line.split(",")]
            if len(p) >= 6:
                devices.append(GpuDevice(
                    index=int(p[0]), vendor="Nvidia", name=p[1],
                    vram_gb=int(p[2]) // 1024, vram_free_gb=int(p[3]) // 1024,
                    utilization_pct=int(p[4]) if p[4].isdigit() else None,
                    compute_capability=p[5]))
    except Exception:
        pass
    if not devices:
        try:
            _run_cmd(["rocm-smi", "--version"])
            devices.append(GpuDevice(index=0, vendor="Amd", name="AMD GPU (ROCm)",
                                     vram_gb=0, vram_free_gb=0))
        except Exception:
            pass
    backend = "None"
    if devices:
        v = {d.vendor for d in devices}
        backend = "Mixed" if len(v) > 1 else ("Cuda" if "Nvidia" in v else "Rocm")
    return GpuStatus(backend=backend, available=bool(devices), devices=devices)


def _system_stats_sync() -> dict:
    # interval=None → non-blocking, uses last measured interval
    cpu = psutil.cpu_percent(interval=None)
    mem = psutil.virtual_memory()
    gpu_stats: list[dict] = []

    try:
        out = _run_cmd(["nvidia-smi",
            "--query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu",
            "--format=csv,noheader,nounits"])
        for line in out.strip().splitlines():
            p = [x.strip() for x in line.split(",")]
            if len(p) >= 6:
                gpu_stats.append({
                    "index": int(p[0]), "name": p[1], "vendor": "NVIDIA",
                    "util_pct":   int(p[2]) if p[2].isdigit() else 0,
                    "vram_used":  int(p[3]) if p[3].isdigit() else 0,
                    "vram_total": int(p[4]) if p[4].isdigit() else 0,
                    "temp_c":     int(p[5]) if p[5].isdigit() else None,
                })
    except Exception:
        pass

    return {
        "cpu_pct":      round(cpu, 1),
        "ram_pct":      round(mem.percent, 1),
        "ram_used_gb":  mem.used  // (1024 ** 3),
        "ram_total_gb": mem.total // (1024 ** 3),
        "gpu":          gpu_stats,
    }

# ── Routes ─────────────────────────────────────────────────────────────────
@app.get("/health")
async def health():
    return {"status": "ok", "version": "0.1.0"}

@app.get("/v1/models")
async def list_models():
    return {"object": "list", "data": [
        ModelInfo(id=k, category=v["category"], description=v["description"]).model_dump()
        for k, v in MODEL_REGISTRY.items()
    ]}

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
        return {"balance": 0}

@app.get("/v1/gpu")
async def gpu_info():
    return await asyncio.to_thread(_gpu_status_sync)

@app.get("/v1/system/stats")
async def system_stats():
    return await asyncio.to_thread(_system_stats_sync)

@app.post("/v1/tokens/starter")
async def grant_starter_tokens(body: StarterGrantRequest):
    if body.session_id in _granted_sessions:
        return {"granted": False, "reason": "already_granted", "amount": 0}
    _granted_sessions.add(body.session_id)
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            await c.post(f"{settings.node_api_url}/v1/tokens/earn",
                         json={"amount": 10, "memo": "welcome_bonus"})
    except Exception:
        pass
    return {"granted": True, "amount": 10, "message": "Willkommen! Du erhältst 10 Starter-Tokens."}

@app.post("/v1/chat/completions")
async def chat_completions(body: ChatRequest, request: Request):
    ollama_model = resolve_model(body.model)
    system, msgs = messages_to_ollama(body.messages)
    req_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"
    prompt_tokens = sum(count_tokens(m.content) for m in body.messages)

    payload: dict = {
        "model": ollama_model, "messages": msgs, "stream": body.stream,
        "options": {"temperature": body.temperature, "num_predict": body.max_tokens},
    }
    if system:
        payload["system"] = system

    endpoint = f"{settings.ollama_url}/api/chat"

    if body.stream:
        return StreamingResponse(
            _stream_ollama(request, endpoint, payload, req_id, body.model, prompt_tokens),
            media_type="text/event-stream", headers={"X-Request-Id": req_id})

    try:
        r = await request.app.state.http.post(endpoint, json=payload)
        r.raise_for_status()
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=502, detail=f"Ollama error: {e.response.text}")
    except httpx.ConnectError:
        raise HTTPException(status_code=503, detail="Cannot reach Ollama. Run: ollama serve")

    content = r.json().get("message", {}).get("content", "")
    comp_tokens = count_tokens(content)
    asyncio.create_task(track_tokens(max(1, (prompt_tokens + comp_tokens) // 100), body.model))

    return {
        "id": req_id, "object": "chat.completion", "created": int(time.time()), "model": body.model,
        "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
        "usage": {"prompt_tokens": prompt_tokens, "completion_tokens": comp_tokens, "total_tokens": prompt_tokens + comp_tokens},
    }

async def _stream_ollama(request: Request, endpoint: str, payload: dict,
                          req_id: str, model: str, prompt_tokens: int):
    comp_tokens = 0
    try:
        async with request.app.state.http.stream("POST", endpoint, json=payload) as r:
            async for line in r.aiter_lines():
                if not line.strip(): continue
                try: chunk = json.loads(line)
                except json.JSONDecodeError: continue
                token = chunk.get("message", {}).get("content", "")
                done  = chunk.get("done", False)
                comp_tokens += count_tokens(token) if token else 0
                sse = {"id": req_id, "object": "chat.completion.chunk", "created": int(time.time()),
                       "model": model,
                       "choices": [{"index": 0, "delta": {"content": token} if not done else {},
                                    "finish_reason": "stop" if done else None}]}
                yield f"data: {json.dumps(sse)}\n\n"
                if done: break
    except httpx.ConnectError:
        yield f'data: {{"error": {{"message": "Cannot reach Ollama", "type": "connection_error"}}}}\n\n'
    yield "data: [DONE]\n\n"
    asyncio.create_task(track_tokens(max(1, (prompt_tokens + comp_tokens) // 100), model))
