// API client for the AI4All gateway

const BASE = '/v1'

export interface Model {
  id: string
  category: string
  description: string
}

export interface Message {
  role: 'user' | 'assistant' | 'system'
  content: string
}

export interface TokenBalance {
  node_id: string
  balance: number
  earned_total: number
  spent_total: number
}

export interface NodeStatus {
  version: string
  peer_count: number
  node_id: string
  balance: number
}

export async function fetchModels(): Promise<Model[]> {
  const r = await fetch(`${BASE}/models`)
  const data = await r.json()
  return data.data ?? []
}

export async function fetchTokenBalance(): Promise<TokenBalance> {
  const r = await fetch(`${BASE}/tokens/balance`)
  return r.json()
}

export async function fetchNodeStatus(): Promise<NodeStatus> {
  const r = await fetch(`${BASE}/node/status`)
  return r.json()
}

export async function* streamChat(
  model: string,
  messages: Message[],
  temperature = 0.7,
): AsyncGenerator<string> {
  const r = await fetch(`${BASE}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages, stream: true, temperature }),
  })

  if (!r.ok) {
    const err = await r.json().catch(() => ({ detail: r.statusText }))
    throw new Error(err.detail ?? 'Request failed')
  }

  const reader = r.body!.getReader()
  const decoder = new TextDecoder()

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    const text = decoder.decode(value)
    for (const line of text.split('\n')) {
      if (!line.startsWith('data: ')) continue
      const payload = line.slice(6).trim()
      if (payload === '[DONE]') return
      try {
        const chunk = JSON.parse(payload)
        const token = chunk?.choices?.[0]?.delta?.content
        if (token) yield token
      } catch {}
    }
  }
}
