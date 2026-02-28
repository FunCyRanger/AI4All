const BASE = '/v1'

export interface Model { id: string; category: string; description: string }
export interface Message { role: 'user' | 'assistant' | 'system'; content: string }
export interface TokenBalance { node_id: string; balance: number; earned_total: number; spent_total: number }
export interface NodeStatus { version: string; peer_count: number; node_id: string; balance: number }
export interface GpuDevice { index: number; vendor: string; name: string; vram_gb: number; vram_free_gb: number; utilization_pct?: number; compute_capability?: string }
export interface GpuStatus { backend: string; available: boolean; devices: GpuDevice[] }

export async function fetchModels(): Promise<Model[]> {
  const r = await fetch(`${BASE}/models`); const d = await r.json(); return d.data ?? []
}
export async function fetchTokenBalance(): Promise<TokenBalance> {
  return fetch(`${BASE}/tokens/balance`).then(r => r.json())
}
export async function fetchNodeStatus(): Promise<NodeStatus> {
  return fetch(`${BASE}/node/status`).then(r => r.json())
}
export async function fetchGpuStatus(): Promise<GpuStatus> {
  return fetch(`${BASE}/gpu`).then(r => r.json())
}
export async function* streamChat(model: string, messages: Message[], temperature = 0.7): AsyncGenerator<string> {
  const r = await fetch(`${BASE}/chat/completions`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages, stream: true, temperature }),
  })
  if (!r.ok) { const e = await r.json().catch(() => ({ detail: r.statusText })); throw new Error(e.detail ?? 'Request failed') }
  const reader = r.body!.getReader(); const decoder = new TextDecoder()
  while (true) {
    const { done, value } = await reader.read(); if (done) break
    for (const line of decoder.decode(value).split('\n')) {
      if (!line.startsWith('data: ')) continue
      const p = line.slice(6).trim(); if (p === '[DONE]') return
      try { const t = JSON.parse(p)?.choices?.[0]?.delta?.content; if (t) yield t } catch {}
    }
  }
}
