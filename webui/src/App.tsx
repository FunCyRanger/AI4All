import { useState, useEffect, useRef, useCallback } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import {
  Send, Bot, User, Cpu, Coins, Globe, Code2,
  Eye, FlaskConical, Loader2, ChevronDown, Settings, RefreshCw
} from 'lucide-react'
import {
  fetchModels, fetchTokenBalance, fetchNodeStatus, fetchGpuStatus,
  streamChat, Model, Message, TokenBalance, NodeStatus, GpuStatus
} from './api'

// ── Category icons ────────────────────────────────────────────────────────
const CATEGORY_ICONS: Record<string, React.ReactNode> = {
  general: <Globe  className="w-4 h-4" />,
  code:    <Code2  className="w-4 h-4" />,
  vision:  <Eye    className="w-4 h-4" />,
  science: <FlaskConical className="w-4 h-4" />,
}

const CATEGORY_COLORS: Record<string, string> = {
  general: 'bg-blue-900/40 text-blue-300 border-blue-700',
  code:    'bg-green-900/40 text-green-300 border-green-700',
  vision:  'bg-purple-900/40 text-purple-300 border-purple-700',
  science: 'bg-orange-900/40 text-orange-300 border-orange-700',
}

// ── Chat message component ────────────────────────────────────────────────
function ChatMessage({ msg }: { msg: Message & { loading?: boolean } }) {
  const isUser = msg.role === 'user'
  return (
    <div className={`flex gap-3 ${isUser ? 'flex-row-reverse' : 'flex-row'} mb-6`}>
      <div className={`flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center
        ${isUser ? 'bg-blue-600' : 'bg-gray-700'}`}>
        {isUser ? <User className="w-4 h-4" /> : <Bot className="w-4 h-4" />}
      </div>
      <div className={`max-w-[80%] rounded-2xl px-4 py-3 text-sm
        ${isUser
          ? 'bg-blue-600 text-white rounded-tr-sm'
          : 'bg-gray-800 text-gray-100 rounded-tl-sm'}`}>
        {msg.loading ? (
          <span className="flex items-center gap-2 text-gray-400">
            <Loader2 className="w-3 h-3 animate-spin" /> Thinking…
          </span>
        ) : isUser ? (
          <p className="whitespace-pre-wrap">{msg.content}</p>
        ) : (
          <ReactMarkdown
            remarkPlugins={[remarkGfm]}
            components={{
              code({ node, className, children, ...props }: any) {
                const inline = !className
                return inline
                  ? <code className="bg-gray-900 px-1 py-0.5 rounded text-blue-300 text-xs" {...props}>{children}</code>
                  : <pre className="bg-gray-900 rounded-lg p-3 overflow-x-auto my-2">
                      <code className="text-xs text-gray-200">{children}</code>
                    </pre>
              },
              p: ({ children }) => <p className="mb-2 last:mb-0">{children}</p>,
              ul: ({ children }) => <ul className="list-disc list-inside mb-2 space-y-1">{children}</ul>,
              ol: ({ children }) => <ol className="list-decimal list-inside mb-2 space-y-1">{children}</ol>,
            }}
          >{msg.content}</ReactMarkdown>
        )}
      </div>
    </div>
  )
}

// ── Model selector ────────────────────────────────────────────────────────
function ModelSelector({ models, selected, onSelect }: {
  models: Model[], selected: string, onSelect: (id: string) => void
}) {
  const [open, setOpen] = useState(false)
  const current = models.find(m => m.id === selected)

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-2 bg-gray-800 hover:bg-gray-700 border border-gray-600
          rounded-xl px-3 py-2 text-sm transition-colors"
      >
        <span>{CATEGORY_ICONS[current?.category ?? 'general']}</span>
        <span className="max-w-[160px] truncate">{current?.id ?? selected}</span>
        <ChevronDown className={`w-3 h-3 transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>

      {open && (
        <div className="absolute top-full left-0 mt-1 w-80 bg-gray-800 border border-gray-600
          rounded-xl shadow-2xl z-50 overflow-hidden">
          {/* Group by category */}
          {['general', 'code', 'vision', 'science'].map(cat => {
            const catModels = models.filter(m => m.category === cat)
            if (!catModels.length) return null
            return (
              <div key={cat}>
                <div className="px-3 py-1.5 text-xs text-gray-500 uppercase tracking-wider border-b border-gray-700">
                  {cat}
                </div>
                {catModels.map(m => (
                  <button
                    key={m.id}
                    onClick={() => { onSelect(m.id); setOpen(false) }}
                    className={`w-full text-left px-3 py-2.5 hover:bg-gray-700 transition-colors
                      ${selected === m.id ? 'bg-gray-700' : ''}`}
                  >
                    <div className="flex items-center gap-2">
                      <span>{CATEGORY_ICONS[cat]}</span>
                      <div>
                        <div className="text-sm font-medium text-gray-100">{m.id}</div>
                        <div className="text-xs text-gray-400">{m.description}</div>
                      </div>
                    </div>
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

// ── Status bar ────────────────────────────────────────────────────────────
function StatusBar({ status, tokens, gpu }: { status: NodeStatus | null, tokens: TokenBalance | null, gpu: GpuStatus | null }) {
  return (
    <div className="flex items-center gap-4 px-4 py-2 bg-gray-900 border-b border-gray-800 text-xs text-gray-400">
      <div className="flex items-center gap-1.5">
        <div className={`w-2 h-2 rounded-full ${status ? 'bg-green-400' : 'bg-red-400'}`} />
        <span>{status ? 'Node online' : 'Node offline'}</span>
      </div>
      {status && (
        <div className="flex items-center gap-1">
          <Globe className="w-3 h-3" />
          <span>{status.peer_count} peer{status.peer_count !== 1 ? 's' : ''}</span>
        </div>
      )}
      {tokens && (
        <div className="flex items-center gap-1 text-yellow-400">
          <Coins className="w-3 h-3" />
          <span>{tokens.balance.toLocaleString()} tokens</span>
        </div>
      )}
      {gpu?.available && (
        <div className="flex items-center gap-1 text-purple-400">
          <Cpu className="w-3 h-3" />
          <span>{gpu.backend} · {gpu.devices.map(d => d.name.replace(/NVIDIA |AMD /gi, '')).join(', ')}</span>
          {gpu.devices[0]?.vram_gb > 0 && (
            <span className="text-purple-500">({gpu.devices.reduce((s,d) => s+d.vram_gb,0)} GB VRAM)</span>
          )}
        </div>
      )}
      <div className="ml-auto text-gray-600 flex items-center gap-1">
        <Cpu className="w-3 h-3" />
        AI4All v0.1.0
      </div>
    </div>
  )
}

// ── Main App ──────────────────────────────────────────────────────────────
export default function App() {
  const [models,    setModels]   = useState<Model[]>([])
  const [model,     setModel]    = useState('ai4all/llama3')
  const [messages,  setMessages] = useState<(Message & { loading?: boolean })[]>([])
  const [input,     setInput]    = useState('')
  const [streaming, setStreaming] = useState(false)
  const [status,    setStatus]   = useState<NodeStatus | null>(null)
  const [tokens,    setTokens]   = useState<TokenBalance | null>(null)
  const [gpu,       setGpu]      = useState<GpuStatus | null>(null)
  const [temp,      setTemp]     = useState(0.7)
  const bottomRef   = useRef<HTMLDivElement>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  // Initial load
  useEffect(() => {
    fetchModels().then(ms => { setModels(ms); if (ms.length) setModel(ms[0].id) }).catch(() => {})
    refreshStatus()
    const iv = setInterval(refreshStatus, 15_000)
    return () => clearInterval(iv)
  }, [])

  const refreshStatus = () => {
    fetchNodeStatus().then(setStatus).catch(() => setStatus(null))
    fetchTokenBalance().then(setTokens).catch(() => {})
    fetchGpuStatus().then(setGpu).catch(() => {})
  }

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const sendMessage = useCallback(async () => {
    const text = input.trim()
    if (!text || streaming) return

    const userMsg: Message = { role: 'user', content: text }
    const placeholder = { role: 'assistant' as const, content: '', loading: true }

    setMessages(prev => [...prev, userMsg, placeholder])
    setInput('')
    setStreaming(true)

    const history: Message[] = [...messages, userMsg]

    try {
      let fullContent = ''
      for await (const token of streamChat(model, history, temp)) {
        fullContent += token
        setMessages(prev => {
          const next = [...prev]
          next[next.length - 1] = { role: 'assistant', content: fullContent, loading: false }
          return next
        })
      }
    } catch (err: any) {
      setMessages(prev => {
        const next = [...prev]
        next[next.length - 1] = {
          role: 'assistant',
          content: `❌ **Error:** ${err.message}\n\nMake sure Ollama is running: \`ollama serve\``,
          loading: false,
        }
        return next
      })
    } finally {
      setStreaming(false)
      textareaRef.current?.focus()
    }
  }, [input, messages, model, streaming, temp])

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage() }
  }

  const clearChat = () => setMessages([])

  return (
    <div className="flex flex-col h-screen bg-gray-950">
      {/* Header */}
      <header className="flex items-center justify-between px-6 py-3 bg-gray-900 border-b border-gray-800">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center font-bold text-sm">
            A
          </div>
          <div>
            <h1 className="font-semibold text-white">AI4All</h1>
            <p className="text-xs text-gray-400">Decentralized AI for Everyone</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={refreshStatus}
            className="p-2 hover:bg-gray-800 rounded-lg transition-colors text-gray-400 hover:text-white"
            title="Refresh status"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
          <button
            onClick={clearChat}
            className="px-3 py-1.5 text-xs text-gray-400 hover:text-white hover:bg-gray-800
              rounded-lg transition-colors border border-gray-700"
          >
            New chat
          </button>
        </div>
      </header>

      {/* Status bar */}
      <StatusBar status={status} tokens={tokens} gpu={gpu} />

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="max-w-3xl mx-auto">
          {messages.length === 0 && (
            <div className="flex flex-col items-center justify-center h-full min-h-[400px] text-center">
              <div className="w-16 h-16 bg-blue-600/20 rounded-2xl flex items-center justify-center mb-4">
                <Bot className="w-8 h-8 text-blue-400" />
              </div>
              <h2 className="text-xl font-semibold text-white mb-2">How can I help you?</h2>
              <p className="text-gray-400 text-sm max-w-sm">
                AI4All runs AI models across a decentralized network.
                Choose a model and start chatting.
              </p>
              <div className="mt-6 grid grid-cols-2 gap-2 max-w-sm w-full">
                {[
                  '✍️ Write a Python function to parse JSON',
                  '🔬 Explain quantum entanglement simply',
                  '💡 Give me ideas for a side project',
                  '🔍 What are the latest AI frameworks?',
                ].map(suggestion => (
                  <button
                    key={suggestion}
                    onClick={() => setInput(suggestion.slice(3))}
                    className="text-left px-3 py-2 bg-gray-800 hover:bg-gray-700 rounded-xl
                      text-xs text-gray-300 transition-colors border border-gray-700"
                  >
                    {suggestion}
                  </button>
                ))}
              </div>
            </div>
          )}

          {messages.map((msg, i) => (
            <ChatMessage key={i} msg={msg} />
          ))}
          <div ref={bottomRef} />
        </div>
      </div>

      {/* Input area */}
      <div className="border-t border-gray-800 bg-gray-900 px-4 py-4">
        <div className="max-w-3xl mx-auto">
          {/* Toolbar */}
          <div className="flex items-center gap-2 mb-3">
            <ModelSelector models={models} selected={model} onSelect={setModel} />
            <div className="flex items-center gap-2 ml-auto text-xs text-gray-500">
              <span>Temp</span>
              <input
                type="range" min="0" max="2" step="0.1" value={temp}
                onChange={e => setTemp(parseFloat(e.target.value))}
                className="w-20 accent-blue-500"
              />
              <span className="w-6 text-gray-300">{temp.toFixed(1)}</span>
            </div>
          </div>

          {/* Textarea + Send */}
          <div className="flex gap-2 items-end">
            <textarea
              ref={textareaRef}
              value={input}
              onChange={e => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Message AI4All… (Enter to send, Shift+Enter for newline)"
              rows={1}
              style={{ resize: 'none' }}
              className="flex-1 bg-gray-800 border border-gray-700 rounded-xl px-4 py-3
                text-sm text-white placeholder-gray-500 focus:outline-none focus:border-blue-500
                transition-colors min-h-[48px] max-h-48 overflow-y-auto"
              onInput={e => {
                const el = e.currentTarget
                el.style.height = 'auto'
                el.style.height = Math.min(el.scrollHeight, 192) + 'px'
              }}
            />
            <button
              onClick={sendMessage}
              disabled={!input.trim() || streaming}
              className="flex-shrink-0 w-10 h-10 bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700
                disabled:cursor-not-allowed rounded-xl flex items-center justify-center transition-colors"
            >
              {streaming
                ? <Loader2 className="w-4 h-4 animate-spin" />
                : <Send className="w-4 h-4" />
              }
            </button>
          </div>
          <p className="text-xs text-gray-600 mt-2 text-center">
            AI4All is open source and community-operated. Responses may be inaccurate.
          </p>
        </div>
      </div>
    </div>
  )
}
