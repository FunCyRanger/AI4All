import { useState, useEffect, useRef, useCallback } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import {
  Send, Bot, User, Cpu, Coins, Globe, Code2, Eye,
  FlaskConical, Loader2, ChevronDown, RefreshCw,
  Activity, MemoryStick, Thermometer, Zap, Gift, X, ChevronUp
} from 'lucide-react'
import {
  fetchModels, fetchTokenBalance, fetchNodeStatus, fetchGpuStatus,
  streamChat, Model, Message, TokenBalance, NodeStatus, GpuStatus
} from './api'

// ── Types ──────────────────────────────────────────────────────────────────

interface SystemStats {
  cpu_pct: number
  ram_pct: number
  ram_used_gb: number
  ram_total_gb: number
  gpu: Array<{
    index: number; name: string; vendor: string
    util_pct: number; vram_used: number; vram_total: number; temp_c: number | null
  }>
}

interface InferenceState {
  active: boolean
  model: string
  tokensGenerated: number
  tokensPerSec: number
  elapsedSec: number
  phase: 'loading' | 'thinking' | 'generating'
}

// ── Constants ─────────────────────────────────────────────────────────────

const CATEGORY_ICONS: Record<string, React.ReactNode> = {
  general: <Globe className="w-4 h-4" />,
  code:    <Code2 className="w-4 h-4" />,
  vision:  <Eye className="w-4 h-4" />,
  science: <FlaskConical className="w-4 h-4" />,
}

const PHASE_LABELS: Record<string, string> = {
  loading:    'Modell wird geladen …',
  thinking:   'Analysiert Anfrage …',
  generating: 'Generiert Antwort',
}

const PHASE_COLORS: Record<string, string> = {
  loading:    'text-yellow-400',
  thinking:   'text-blue-400',
  generating: 'text-green-400',
}

// ── Helpers ────────────────────────────────────────────────────────────────

function getSessionId(): string {
  let id = sessionStorage.getItem('ai4all_session')
  if (!id) { id = crypto.randomUUID(); sessionStorage.setItem('ai4all_session', id) }
  return id
}

async function fetchSystemStats(): Promise<SystemStats> {
  const r = await fetch('/v1/system/stats')
  return r.json()
}

async function claimStarterTokens(sessionId: string) {
  const r = await fetch('/v1/tokens/starter', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session_id: sessionId }),
  })
  return r.json()
}

// ── Mini progress bar ─────────────────────────────────────────────────────

function Bar({ value, color = 'bg-blue-500', label }: { value: number; color?: string; label?: string }) {
  return (
    <div className="flex items-center gap-2">
      {label && <span className="w-8 text-right text-gray-500 text-xs">{label}</span>}
      <div className="flex-1 h-1.5 bg-gray-800 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-700 ${color}`}
          style={{ width: `${Math.min(100, value)}%` }}
        />
      </div>
      <span className="w-9 text-xs text-right tabular-nums text-gray-400">{value.toFixed(0)}%</span>
    </div>
  )
}

// ── System Stats Panel ────────────────────────────────────────────────────

function StatsPanel({ stats, open, onToggle }: {
  stats: SystemStats | null; open: boolean; onToggle: () => void
}) {
  const cpuColor  = (stats?.cpu_pct ?? 0) > 80 ? 'bg-red-500' : (stats?.cpu_pct ?? 0) > 50 ? 'bg-yellow-500' : 'bg-blue-500'
  const ramColor  = (stats?.ram_pct ?? 0) > 80 ? 'bg-red-500' : (stats?.ram_pct ?? 0) > 60 ? 'bg-yellow-500' : 'bg-emerald-500'

  return (
    <div className="border-b border-gray-800 bg-gray-900/80 backdrop-blur-sm">
      {/* Toggle row */}
      <button
        onClick={onToggle}
        className="w-full flex items-center gap-3 px-4 py-2 hover:bg-gray-800/50 transition-colors text-xs text-gray-500"
      >
        <Activity className="w-3 h-3" />
        <span className="font-medium tracking-wide uppercase">Systemauslastung</span>

        {/* Inline summary when collapsed */}
        {!open && stats && (
          <div className="flex items-center gap-3 ml-2 text-gray-600">
            <span>CPU {stats.cpu_pct.toFixed(0)}%</span>
            <span>RAM {stats.ram_pct.toFixed(0)}%</span>
            {stats.gpu[0] && <span>GPU {stats.gpu[0].util_pct}%</span>}
          </div>
        )}
        <div className="ml-auto">
          {open ? <ChevronUp className="w-3 h-3" /> : <ChevronDown className="w-3 h-3" />}
        </div>
      </button>

      {/* Expanded panel */}
      {open && (
        <div className="px-4 pb-3 grid grid-cols-1 sm:grid-cols-3 gap-4">
          {/* CPU */}
          <div className="space-y-1">
            <div className="flex items-center gap-1.5 mb-2">
              <Cpu className="w-3.5 h-3.5 text-blue-400" />
              <span className="text-xs font-medium text-gray-300">CPU</span>
            </div>
            <Bar value={stats?.cpu_pct ?? 0} color={cpuColor} />
            <div className="text-xs text-gray-600 pl-10">
              {navigator.hardwareConcurrency} Cores
            </div>
          </div>

          {/* RAM */}
          <div className="space-y-1">
            <div className="flex items-center gap-1.5 mb-2">
              <MemoryStick className="w-3.5 h-3.5 text-emerald-400" />
              <span className="text-xs font-medium text-gray-300">RAM</span>
            </div>
            <Bar value={stats?.ram_pct ?? 0} color={ramColor} />
            <div className="text-xs text-gray-600 pl-10">
              {stats?.ram_used_gb ?? 0} / {stats?.ram_total_gb ?? 0} GB
            </div>
          </div>

          {/* GPU(s) */}
          {(stats?.gpu?.length ?? 0) > 0 ? (
            <div className="space-y-2">
              <div className="flex items-center gap-1.5 mb-2">
                <Zap className="w-3.5 h-3.5 text-purple-400" />
                <span className="text-xs font-medium text-gray-300">GPU</span>
              </div>
              {stats!.gpu.map(g => {
                const vramPct = g.vram_total > 0 ? (g.vram_used / g.vram_total) * 100 : 0
                const gpuColor = g.util_pct > 80 ? 'bg-red-500' : 'bg-purple-500'
                return (
                  <div key={g.index} className="space-y-1">
                    <div className="flex items-center justify-between">
                      <span className="text-xs text-gray-500 truncate max-w-[120px]">
                        {g.name.replace('NVIDIA GeForce ', '').replace('AMD Radeon ', '')}
                      </span>
                      {g.temp_c && (
                        <span className={`text-xs flex items-center gap-0.5 ${g.temp_c > 80 ? 'text-red-400' : 'text-gray-500'}`}>
                          <Thermometer className="w-3 h-3" />{g.temp_c}°C
                        </span>
                      )}
                    </div>
                    <Bar value={g.util_pct} color={gpuColor} label="Kern" />
                    <Bar value={vramPct} color="bg-violet-600" label="VRAM" />
                    <div className="text-xs text-gray-600 pl-10">
                      {(g.vram_used / 1024).toFixed(1)} / {(g.vram_total / 1024).toFixed(1)} GB
                    </div>
                  </div>
                )
              })}
            </div>
          ) : (
            <div className="flex items-center gap-2 text-xs text-gray-600">
              <Zap className="w-3.5 h-3.5" />
              Kein GPU erkannt – CPU-Modus
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ── Inference Live Ticker ─────────────────────────────────────────────────

function InferenceTicker({ state }: { state: InferenceState }) {
  if (!state.active) return null
  return (
    <div className="flex items-center gap-3 px-4 py-1.5 bg-gray-900/90 border-b border-gray-800 text-xs">
      <Loader2 className="w-3 h-3 animate-spin text-blue-400 flex-shrink-0" />
      <span className={`font-medium ${PHASE_COLORS[state.phase]}`}>
        {PHASE_LABELS[state.phase]}
      </span>
      <span className="text-gray-600">{state.model.replace('ai4all/', '')}</span>
      {state.tokensGenerated > 0 && (
        <>
          <span className="text-gray-700">·</span>
          <span className="tabular-nums text-gray-500">
            {state.tokensGenerated} Token
          </span>
          {state.tokensPerSec > 0 && (
            <>
              <span className="text-gray-700">·</span>
              <span className="tabular-nums text-emerald-600 font-medium">
                {state.tokensPerSec.toFixed(1)} tok/s
              </span>
            </>
          )}
          <span className="text-gray-700">·</span>
          <span className="tabular-nums text-gray-600">
            {state.elapsedSec.toFixed(1)}s
          </span>
        </>
      )}
    </div>
  )
}

// ── Welcome / Token Modal ─────────────────────────────────────────────────

function WelcomeModal({ onClose }: { onClose: () => void }) {
  return (
    <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-gray-900 border border-gray-700 rounded-2xl p-6 max-w-sm w-full shadow-2xl">
        <div className="flex justify-between items-start mb-4">
          <div className="w-10 h-10 bg-yellow-500/20 rounded-xl flex items-center justify-center">
            <Gift className="w-5 h-5 text-yellow-400" />
          </div>
          <button onClick={onClose} className="text-gray-600 hover:text-gray-300 transition-colors">
            <X className="w-4 h-4" />
          </button>
        </div>
        <h2 className="text-lg font-semibold text-white mb-1">Willkommen bei AI4All!</h2>
        <p className="text-sm text-gray-400 mb-4">
          Als Starter-Bonus bekommst du <span className="text-yellow-400 font-bold">10 Tokens</span> geschenkt.
          Mit Tokens bezahlst du Anfragen – je mehr du zum Netzwerk beiträgst, desto mehr verdienst du zurück.
        </p>
        <div className="bg-gray-800 rounded-xl p-3 mb-4 flex items-center gap-3">
          <Coins className="w-5 h-5 text-yellow-400 flex-shrink-0" />
          <div>
            <div className="text-white font-bold text-lg leading-none">+10 Tokens</div>
            <div className="text-xs text-gray-500 mt-0.5">Einmaliger Willkommensbonus</div>
          </div>
        </div>
        <button
          onClick={onClose}
          className="w-full bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium py-2.5 rounded-xl transition-colors"
        >
          Los geht's!
        </button>
      </div>
    </div>
  )
}

// ── Status Bar ────────────────────────────────────────────────────────────

function StatusBar({ status, tokens, gpu }: {
  status: NodeStatus | null; tokens: TokenBalance | null; gpu: GpuStatus | null
}) {
  return (
    <div className="flex items-center gap-4 px-4 py-2 bg-gray-900 border-b border-gray-800 text-xs text-gray-400 overflow-x-auto">
      <div className="flex items-center gap-1.5 flex-shrink-0">
        <div className={`w-2 h-2 rounded-full ${status ? 'bg-green-400 shadow-[0_0_6px_rgba(74,222,128,0.6)]' : 'bg-red-400'}`} />
        <span>{status ? 'Node online' : 'Node offline'}</span>
      </div>
      {status && (
        <div className="flex items-center gap-1 flex-shrink-0">
          <Globe className="w-3 h-3" />
          <span>{status.peer_count} Peer{status.peer_count !== 1 ? 's' : ''}</span>
        </div>
      )}
      {tokens && (
        <div className="flex items-center gap-1 text-yellow-400 flex-shrink-0">
          <Coins className="w-3 h-3" />
          <span className="tabular-nums font-medium">{tokens.balance.toLocaleString()}</span>
          <span className="text-yellow-600">Tokens</span>
        </div>
      )}
      {gpu?.available && gpu.devices[0] && (
        <div className="flex items-center gap-1.5 text-purple-400 flex-shrink-0">
          <Zap className="w-3 h-3" />
          <span>{gpu.backend}</span>
          <span className="text-purple-600">·</span>
          <span className="text-purple-500">{gpu.devices.map(d => d.name.replace(/NVIDIA GeForce |AMD Radeon /gi, '')).join(', ')}</span>
        </div>
      )}
      <div className="ml-auto text-gray-700 flex items-center gap-1 flex-shrink-0">
        AI4All v0.1.0
      </div>
    </div>
  )
}

// ── Chat Message ──────────────────────────────────────────────────────────

function ChatMessage({ msg, meta }: {
  msg: Message & { loading?: boolean }
  meta?: { tokensGenerated?: number; tokensPerSec?: number; elapsedSec?: number; model?: string }
}) {
  const isUser = msg.role === 'user'
  return (
    <div className={`flex gap-3 ${isUser ? 'flex-row-reverse' : 'flex-row'} mb-5 group`}>
      <div className={`flex-shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-xs
        ${isUser ? 'bg-blue-600' : 'bg-gray-700'}`}>
        {isUser ? <User className="w-3.5 h-3.5" /> : <Bot className="w-3.5 h-3.5" />}
      </div>
      <div className="max-w-[82%] flex flex-col gap-1">
        <div className={`rounded-2xl px-4 py-3 text-sm leading-relaxed
          ${isUser
            ? 'bg-blue-600 text-white rounded-tr-sm'
            : 'bg-gray-800/80 text-gray-100 rounded-tl-sm border border-gray-700/50'}`}>
          {msg.loading ? (
            <span className="flex items-center gap-2 text-gray-400">
              <span className="flex gap-1">
                {[0,1,2].map(i => (
                  <span key={i} className="w-1.5 h-1.5 bg-gray-500 rounded-full animate-bounce"
                    style={{ animationDelay: `${i * 0.15}s` }} />
                ))}
              </span>
              <span className="text-gray-500">Denkt nach …</span>
            </span>
          ) : isUser ? (
            <p className="whitespace-pre-wrap">{msg.content}</p>
          ) : (
            <ReactMarkdown
              remarkPlugins={[remarkGfm]}
              components={{
                code({ className, children, ...props }: any) {
                  const inline = !className
                  return inline
                    ? <code className="bg-gray-900 px-1.5 py-0.5 rounded text-blue-300 text-xs font-mono" {...props}>{children}</code>
                    : <pre className="bg-gray-950 border border-gray-700 rounded-xl p-4 overflow-x-auto my-3">
                        <code className="text-xs text-gray-200 font-mono">{children}</code>
                      </pre>
                },
                p: ({ children }) => <p className="mb-2 last:mb-0">{children}</p>,
                ul: ({ children }) => <ul className="list-disc list-inside mb-2 space-y-1 text-gray-200">{children}</ul>,
                ol: ({ children }) => <ol className="list-decimal list-inside mb-2 space-y-1 text-gray-200">{children}</ol>,
                h1: ({ children }) => <h1 className="text-lg font-bold mb-2 text-white">{children}</h1>,
                h2: ({ children }) => <h2 className="text-base font-semibold mb-2 text-white">{children}</h2>,
                h3: ({ children }) => <h3 className="text-sm font-semibold mb-1 text-gray-200">{children}</h3>,
                blockquote: ({ children }) => <blockquote className="border-l-2 border-gray-600 pl-3 text-gray-400 my-2">{children}</blockquote>,
              }}
            >{msg.content}</ReactMarkdown>
          )}
        </div>
        {/* Token meta below assistant messages */}
        {!isUser && !msg.loading && meta && meta.tokensGenerated && meta.tokensGenerated > 0 && (
          <div className="flex items-center gap-2 px-1 text-xs text-gray-700 opacity-0 group-hover:opacity-100 transition-opacity">
            <span>{meta.tokensGenerated} Tokens</span>
            {meta.tokensPerSec && meta.tokensPerSec > 0 && (
              <><span>·</span><span className="text-gray-600">{meta.tokensPerSec.toFixed(1)} tok/s</span></>
            )}
            {meta.elapsedSec && (
              <><span>·</span><span>{meta.elapsedSec.toFixed(1)}s</span></>
            )}
            {meta.model && (
              <><span>·</span><span className="text-gray-700">{meta.model.replace('ai4all/', '')}</span></>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

// ── Model Selector ────────────────────────────────────────────────────────

function ModelSelector({ models, selected, onSelect }: {
  models: Model[]; selected: string; onSelect: (id: string) => void
}) {
  const [open, setOpen] = useState(false)
  const current = models.find(m => m.id === selected)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handler = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false) }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  return (
    <div className="relative" ref={ref}>
      <button onClick={() => setOpen(!open)}
        className="flex items-center gap-2 bg-gray-800 hover:bg-gray-700 border border-gray-700 rounded-xl px-3 py-2 text-sm transition-colors">
        <span className="text-gray-400">{CATEGORY_ICONS[current?.category ?? 'general']}</span>
        <span className="max-w-[140px] truncate text-gray-200">{current?.id?.replace('ai4all/', '') ?? selected}</span>
        <ChevronDown className={`w-3 h-3 text-gray-500 transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && (
        <div className="absolute top-full left-0 mt-1 w-72 bg-gray-850 bg-gray-900 border border-gray-700 rounded-xl shadow-2xl z-50 overflow-hidden">
          {['general', 'code', 'vision'].map(cat => {
            const catModels = models.filter(m => m.category === cat)
            if (!catModels.length) return null
            return (
              <div key={cat}>
                <div className="px-3 py-1.5 text-xs text-gray-600 uppercase tracking-widest border-b border-gray-800 bg-gray-900/50">
                  {cat === 'general' ? 'Allgemein' : cat === 'code' ? 'Code' : 'Vision'}
                </div>
                {catModels.map(m => (
                  <button key={m.id} onClick={() => { onSelect(m.id); setOpen(false) }}
                    className={`w-full text-left px-3 py-2.5 hover:bg-gray-800 transition-colors flex items-center gap-3
                      ${selected === m.id ? 'bg-gray-800/60' : ''}`}>
                    <span className="text-gray-500">{CATEGORY_ICONS[cat]}</span>
                    <div className="min-w-0">
                      <div className="text-sm text-gray-100 font-medium">{m.id.replace('ai4all/', '')}</div>
                      <div className="text-xs text-gray-600 truncate">{m.description}</div>
                    </div>
                    {selected === m.id && <div className="ml-auto w-1.5 h-1.5 rounded-full bg-blue-500 flex-shrink-0" />}
                  </button>
                ))}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── Main App ──────────────────────────────────────────────────────────────

type MsgWithMeta = Message & {
  loading?: boolean
  meta?: { tokensGenerated: number; tokensPerSec: number; elapsedSec: number; model: string }
}

export default function App() {
  const [models,    setModels]   = useState<Model[]>([])
  const [model,     setModel]    = useState('ai4all/llama3')
  const [messages,  setMessages] = useState<MsgWithMeta[]>([])
  const [input,     setInput]    = useState('')
  const [streaming, setStreaming] = useState(false)
  const [status,    setStatus]   = useState<NodeStatus | null>(null)
  const [tokens,    setTokens]   = useState<TokenBalance | null>(null)
  const [gpu,       setGpu]      = useState<GpuStatus | null>(null)
  const [stats,     setStats]    = useState<SystemStats | null>(null)
  const [statsOpen, setStatsOpen] = useState(false)
  const [temp,      setTemp]     = useState(0.7)
  const [showWelcome, setShowWelcome] = useState(false)
  const [inference, setInference] = useState<InferenceState>({
    active: false, model: '', tokensGenerated: 0, tokensPerSec: 0, elapsedSec: 0, phase: 'loading'
  })

  const bottomRef   = useRef<HTMLDivElement>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const startTimeRef = useRef<number>(0)
  const tokenCountRef = useRef<number>(0)

  // Initial setup
  useEffect(() => {
    fetchModels().then(ms => { setModels(ms); if (ms.length) setModel(ms[0].id) }).catch(() => {})
    refreshStatus()
    const iv = setInterval(refreshStatus, 15_000)

    // Starter tokens for new sessions
    const sessionId = getSessionId()
    const alreadyClaimed = localStorage.getItem('ai4all_tokens_claimed')
    if (!alreadyClaimed) {
      claimStarterTokens(sessionId).then(res => {
        if (res.granted) {
          localStorage.setItem('ai4all_tokens_claimed', '1')
          setShowWelcome(true)
          setTimeout(refreshStatus, 500) // refresh balance after grant
        }
      }).catch(() => {})
    }

    return () => clearInterval(iv)
  }, [])

  // System stats polling (more frequent when stats panel open)
  useEffect(() => {
    const poll = () => fetchSystemStats().then(setStats).catch(() => {})
    poll()
    const iv = setInterval(poll, statsOpen ? 2000 : 8000)
    return () => clearInterval(iv)
  }, [statsOpen])

  const refreshStatus = () => {
    fetchNodeStatus().then(setStatus).catch(() => setStatus(null))
    fetchTokenBalance().then(setTokens).catch(() => {})
    fetchGpuStatus().then(setGpu).catch(() => {})
  }

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  // Live elapsed-time ticker during streaming
  useEffect(() => {
    if (!streaming) return
    const iv = setInterval(() => {
      setInference(prev => {
        if (!prev.active) return prev
        const elapsed = (Date.now() - startTimeRef.current) / 1000
        const tps = elapsed > 0 ? tokenCountRef.current / elapsed : 0
        return { ...prev, elapsedSec: elapsed, tokensPerSec: tps }
      })
    }, 200)
    return () => clearInterval(iv)
  }, [streaming])

  const sendMessage = useCallback(async () => {
    const text = input.trim()
    if (!text || streaming) return

    const userMsg: MsgWithMeta = { role: 'user', content: text }
    const placeholder: MsgWithMeta = { role: 'assistant', content: '', loading: true }

    setMessages(prev => [...prev, userMsg, placeholder])
    setInput('')
    setStreaming(true)
    startTimeRef.current = Date.now()
    tokenCountRef.current = 0

    setInference({ active: true, model, tokensGenerated: 0, tokensPerSec: 0, elapsedSec: 0, phase: 'loading' })

    const history: Message[] = [...messages, userMsg]
    let fullContent = ''
    let firstToken = true

    try {
      for await (const token of streamChat(model, history, temp)) {
        fullContent += token
        tokenCountRef.current++

        if (firstToken) {
          firstToken = false
          setInference(prev => ({ ...prev, phase: 'generating' }))
        }

        const elapsed = (Date.now() - startTimeRef.current) / 1000
        const tps = elapsed > 0 ? tokenCountRef.current / elapsed : 0

        setInference(prev => ({
          ...prev,
          active: true,
          tokensGenerated: tokenCountRef.current,
          tokensPerSec: tps,
          elapsedSec: elapsed,
          phase: tokenCountRef.current < 3 ? 'thinking' : 'generating',
        }))

        setMessages(prev => {
          const next = [...prev]
          next[next.length - 1] = { role: 'assistant', content: fullContent, loading: false }
          return next
        })
      }

      // Finalize with meta stats
      const elapsed = (Date.now() - startTimeRef.current) / 1000
      const tps = elapsed > 0 ? tokenCountRef.current / elapsed : 0

      setMessages(prev => {
        const next = [...prev]
        next[next.length - 1] = {
          role: 'assistant',
          content: fullContent,
          loading: false,
          meta: { tokensGenerated: tokenCountRef.current, tokensPerSec: tps, elapsedSec: elapsed, model },
        }
        return next
      })

    } catch (err: any) {
      setMessages(prev => {
        const next = [...prev]
        next[next.length - 1] = {
          role: 'assistant',
          content: `❌ **Fehler:** ${err.message}\n\nStelle sicher, dass Ollama läuft: \`ollama serve\``,
          loading: false,
        }
        return next
      })
    } finally {
      setStreaming(false)
      setInference(prev => ({ ...prev, active: false }))
      textareaRef.current?.focus()
      setTimeout(refreshStatus, 1000)
    }
  }, [input, messages, model, streaming, temp])

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage() }
  }

  return (
    <div className="flex flex-col h-screen bg-gray-950">
      {showWelcome && <WelcomeModal onClose={() => setShowWelcome(false)} />}

      {/* Header */}
      <header className="flex items-center justify-between px-5 py-3 bg-gray-900 border-b border-gray-800">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-gradient-to-br from-blue-500 to-blue-700 rounded-xl flex items-center justify-center font-bold text-sm shadow-lg">
            A
          </div>
          <div>
            <h1 className="font-semibold text-white tracking-tight">AI4All</h1>
            <p className="text-xs text-gray-500">Decentralized AI for Everyone</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={refreshStatus}
            className="p-2 hover:bg-gray-800 rounded-lg transition-colors text-gray-500 hover:text-gray-300" title="Status aktualisieren">
            <RefreshCw className="w-3.5 h-3.5" />
          </button>
          <button onClick={() => setMessages([])}
            className="px-3 py-1.5 text-xs text-gray-500 hover:text-gray-200 hover:bg-gray-800 rounded-lg transition-colors border border-gray-800">
            Neuer Chat
          </button>
        </div>
      </header>

      <StatusBar status={status} tokens={tokens} gpu={gpu} />
      <StatsPanel stats={stats} open={statsOpen} onToggle={() => setStatsOpen(o => !o)} />
      <InferenceTicker state={inference} />

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="max-w-3xl mx-auto">
          {messages.length === 0 && (
            <div className="flex flex-col items-center justify-center h-full min-h-[380px] text-center">
              <div className="w-14 h-14 bg-blue-600/15 border border-blue-500/20 rounded-2xl flex items-center justify-center mb-4">
                <Bot className="w-7 h-7 text-blue-400" />
              </div>
              <h2 className="text-xl font-semibold text-white mb-2">Wie kann ich helfen?</h2>
              <p className="text-gray-500 text-sm max-w-xs mb-6">
                AI4All verteilt KI-Modelle über ein dezentrales Netzwerk. Wähle ein Modell und starte.
              </p>
              <div className="grid grid-cols-2 gap-2 max-w-sm w-full">
                {[
                  ['✍️', 'Python-Funktion zum JSON-Parsen schreiben'],
                  ['🔬', 'Quantenverschränkung einfach erklären'],
                  ['💡', 'Side-Project-Ideen generieren'],
                  ['🛠️', 'Docker Compose Datei optimieren'],
                ].map(([emoji, text]) => (
                  <button key={text} onClick={() => setInput(text)}
                    className="text-left px-3 py-2.5 bg-gray-900 hover:bg-gray-800 rounded-xl
                      text-xs text-gray-400 hover:text-gray-200 transition-colors border border-gray-800 hover:border-gray-700">
                    <span className="mr-1.5">{emoji}</span>{text}
                  </button>
                ))}
              </div>
            </div>
          )}
          {messages.map((msg, i) => (
            <ChatMessage key={i} msg={msg} meta={msg.meta} />
          ))}
          <div ref={bottomRef} />
        </div>
      </div>

      {/* Input */}
      <div className="border-t border-gray-800 bg-gray-900/95 backdrop-blur-sm px-4 py-3">
        <div className="max-w-3xl mx-auto space-y-2">
          <div className="flex items-center gap-2">
            <ModelSelector models={models} selected={model} onSelect={setModel} />
            <div className="flex items-center gap-2 ml-auto text-xs text-gray-600">
              <span>Temperatur</span>
              <input type="range" min="0" max="2" step="0.1" value={temp}
                onChange={e => setTemp(parseFloat(e.target.value))}
                className="w-20 accent-blue-500 cursor-pointer" />
              <span className="w-7 text-right text-gray-400 tabular-nums">{temp.toFixed(1)}</span>
            </div>
          </div>
          <div className="flex gap-2 items-end">
            <textarea ref={textareaRef} value={input}
              onChange={e => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Nachricht eingeben … (Enter senden, Shift+Enter neue Zeile)"
              rows={1}
              style={{ resize: 'none' }}
              className="flex-1 bg-gray-800 border border-gray-700 rounded-xl px-4 py-3
                text-sm text-white placeholder-gray-600 focus:outline-none focus:border-blue-600
                transition-colors min-h-[48px] max-h-44 overflow-y-auto leading-relaxed"
              onInput={e => {
                const el = e.currentTarget
                el.style.height = 'auto'
                el.style.height = Math.min(el.scrollHeight, 176) + 'px'
              }}
            />
            <button onClick={sendMessage} disabled={!input.trim() || streaming}
              className="flex-shrink-0 w-10 h-10 bg-blue-600 hover:bg-blue-500 disabled:bg-gray-800
                disabled:text-gray-600 rounded-xl flex items-center justify-center transition-colors">
              {streaming
                ? <Loader2 className="w-4 h-4 animate-spin" />
                : <Send className="w-4 h-4" />
              }
            </button>
          </div>
          <p className="text-xs text-gray-700 text-center">
            AI4All ist open source und community-betrieben · Antworten können ungenau sein
          </p>
        </div>
      </div>
    </div>
  )
}
