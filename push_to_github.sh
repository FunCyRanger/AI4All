#!/usr/bin/env bash
# AI4All – Vollständiger Push zu GitHub via SSH
# Schreibt ALLE Projektdateien und pusht sie zu FunCyRanger/AI4All
#
# Verwendung (aus dem AI4All-Verzeichnis):
#   bash push_to_github.sh

set -e
REPO="git@github.com:FunCyRanger/AI4All.git"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}ℹ  ${NC}$*"; }
success() { echo -e "${GREEN}✓  ${NC}$*"; }
warn()    { echo -e "${YELLOW}⚠  ${NC}$*"; }
error()   { echo -e "${RED}✗  ${NC}$*"; exit 1; }

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║  AI4All – Push alle Dateien zu GitHub║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""

# Immer aus dem Verzeichnis des Scripts arbeiten
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
info "Arbeitsverzeichnis: $SCRIPT_DIR"

# Git prüfen
command -v git &>/dev/null || error "git ist nicht installiert."

# SSH prüfen
info "Teste SSH-Verbindung zu GitHub..."
SSH_OUT=$(ssh -T git@github.com 2>&1 || true)
if echo "$SSH_OUT" | grep -q "successfully authenticated"; then
  success "SSH OK – $(echo "$SSH_OUT" | head -1)"
else
  echo ""
  warn "SSH-Key nicht autorisiert. Lösung:"
  echo ""
  # Key generieren falls keiner vorhanden
  if [ ! -f "$HOME/.ssh/id_ed25519.pub" ] && [ ! -f "$HOME/.ssh/id_rsa.pub" ]; then
    info "Generiere neuen SSH-Key..."
    ssh-keygen -t ed25519 -C "AI4All GitHub" -f "$HOME/.ssh/id_ed25519" -N ""
  fi
  KEY_FILE=$([ -f "$HOME/.ssh/id_ed25519.pub" ] && echo "$HOME/.ssh/id_ed25519.pub" || echo "$HOME/.ssh/id_rsa.pub")
  echo -e "  ${YELLOW}1. Kopiere diesen Public Key:${NC}"
  echo ""
  echo -e "  ${GREEN}$(cat "$KEY_FILE")${NC}"
  echo ""
  echo -e "  ${YELLOW}2. Füge ihn hier ein: https://github.com/settings/keys${NC}"
  echo -e "  ${YELLOW}3. Dann dieses Script erneut starten.${NC}"
  echo ""
  command -v xdg-open &>/dev/null && xdg-open "https://github.com/settings/keys" 2>/dev/null || \
  command -v open      &>/dev/null && open      "https://github.com/settings/keys" 2>/dev/null || true
  read -rp "  Drücke ENTER sobald der Key eingetragen ist..."
  SSH_OUT2=$(ssh -T git@github.com 2>&1 || true)
  echo "$SSH_OUT2" | grep -q "successfully authenticated" || error "SSH immer noch nicht autorisiert."
  success "SSH OK"
fi

# ── Alle Projektdateien erstellen / sicherstellen ─────────────────────────
info "Schreibe alle Projektdateien..."

mkdir -p api core/node/src core/tokens/src webui/src webui/public \
         docs .github/workflows .github/ISSUE_TEMPLATE

# ── .gitignore ────────────────────────────────────────────────────────────
cat > .gitignore << 'EOF'
core/target/
**/*.rs.bk
__pycache__/
*.py[cod]
.venv/
*.egg-info/
.ruff_cache/
webui/node_modules/
webui/dist/
*.wallet.json
wallet.json
config.local.toml
.DS_Store
Thumbs.db
.idea/
.vscode/
*.swp
docker-compose.models.yml
EOF

# ── api/requirements.txt ──────────────────────────────────────────────────
cat > api/requirements.txt << 'EOF'
fastapi==0.111.0
uvicorn[standard]==0.29.0
pydantic==2.7.0
pydantic-settings==2.2.1
httpx==0.27.0
EOF

# ── api/Dockerfile ────────────────────────────────────────────────────────
cat > api/Dockerfile << 'EOF'
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD curl -sf http://localhost:8000/health || exit 1
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--log-level", "info"]
EOF

# ── webui/Dockerfile.prod ─────────────────────────────────────────────────
cat > webui/Dockerfile.prod << 'EOF'
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s CMD wget -qO- http://localhost/ || exit 1
CMD ["nginx", "-g", "daemon off;"]
EOF

# ── webui/nginx.conf ──────────────────────────────────────────────────────
cat > webui/nginx.conf << 'EOF'
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;
    location / { try_files $uri $uri/ /index.html; }
    location /v1 {
        proxy_pass http://api:8000;
        proxy_set_header Host $host;
        proxy_buffering off;
    }
    location /health { proxy_pass http://api:8000; }
}
EOF

# ── webui/package.json ────────────────────────────────────────────────────
cat > webui/package.json << 'EOF'
{
  "name": "ai4all-webui",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-markdown": "^9.0.1",
    "remark-gfm": "^4.0.0",
    "lucide-react": "^0.400.0"
  },
  "devDependencies": {
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1",
    "typescript": "^5.5.3",
    "vite": "^5.3.4",
    "tailwindcss": "^3.4.6",
    "autoprefixer": "^10.4.19",
    "postcss": "^8.4.40"
  }
}
EOF

# ── webui/tsconfig.json ───────────────────────────────────────────────────
cat > webui/tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true
  },
  "include": ["src"]
}
EOF

# ── webui/vite.config.ts ──────────────────────────────────────────────────
cat > webui/vite.config.ts << 'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/v1':     { target: 'http://localhost:8000', changeOrigin: true },
      '/health': { target: 'http://localhost:8000', changeOrigin: true },
    }
  }
})
EOF

# ── webui/tailwind.config.js ──────────────────────────────────────────────
cat > webui/tailwind.config.js << 'EOF'
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: { extend: {} },
  plugins: []
}
EOF

# ── webui/postcss.config.js ───────────────────────────────────────────────
cat > webui/postcss.config.js << 'EOF'
export default { plugins: { tailwindcss: {}, autoprefixer: {} } }
EOF

# ── webui/index.html ──────────────────────────────────────────────────────
cat > webui/index.html << 'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>AI4All – AI for Everyone</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

# ── webui/src/main.tsx ────────────────────────────────────────────────────
cat > webui/src/main.tsx << 'EOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'
ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode><App /></React.StrictMode>
)
EOF

# ── webui/src/index.css ───────────────────────────────────────────────────
cat > webui/src/index.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
@layer base {
  body { @apply bg-gray-950 text-gray-100 font-sans; }
  ::-webkit-scrollbar { @apply w-1.5; }
  ::-webkit-scrollbar-track { @apply bg-gray-900; }
  ::-webkit-scrollbar-thumb { @apply bg-gray-600 rounded-full; }
}
EOF

# ── webui/src/api.ts ──────────────────────────────────────────────────────
cat > webui/src/api.ts << 'EOF'
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
EOF


# ── webui/src/App.tsx (base64-encoded to avoid heredoc issues with JSX) ───
echo 'aW1wb3J0IHsgdXNlU3RhdGUsIHVzZUVmZmVjdCwgdXNlUmVmLCB1c2VDYWxsYmFjayB9IGZyb20gJ3JlYWN0JwppbXBvcnQgUmVhY3RNYXJrZG93biBmcm9tICdyZWFjdC1tYXJrZG93bicKaW1wb3J0IHJlbWFya0dmbSBmcm9tICdyZW1hcmstZ2ZtJwppbXBvcnQgewogIFNlbmQsIEJvdCwgVXNlciwgQ3B1LCBDb2lucywgR2xvYmUsIENvZGUyLAogIEV5ZSwgRmxhc2tDb25pY2FsLCBMb2FkZXIyLCBDaGV2cm9uRG93biwgU2V0dGluZ3MsIFJlZnJlc2hDdwp9IGZyb20gJ2x1Y2lkZS1yZWFjdCcKaW1wb3J0IHsKICBmZXRjaE1vZGVscywgZmV0Y2hUb2tlbkJhbGFuY2UsIGZldGNoTm9kZVN0YXR1cywgZmV0Y2hHcHVTdGF0dXMsCiAgc3RyZWFtQ2hhdCwgTW9kZWwsIE1lc3NhZ2UsIFRva2VuQmFsYW5jZSwgTm9kZVN0YXR1cywgR3B1U3RhdHVzCn0gZnJvbSAnLi9hcGknCgovLyDilIDilIAgQ2F0ZWdvcnkgaWNvbnMg4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACmNvbnN0IENBVEVHT1JZX0lDT05TOiBSZWNvcmQ8c3RyaW5nLCBSZWFjdC5SZWFjdE5vZGU+ID0gewogIGdlbmVyYWw6IDxHbG9iZSAgY2xhc3NOYW1lPSJ3LTQgaC00IiAvPiwKICBjb2RlOiAgICA8Q29kZTIgIGNsYXNzTmFtZT0idy00IGgtNCIgLz4sCiAgdmlzaW9uOiAgPEV5ZSAgICBjbGFzc05hbWU9InctNCBoLTQiIC8+LAogIHNjaWVuY2U6IDxGbGFza0NvbmljYWwgY2xhc3NOYW1lPSJ3LTQgaC00IiAvPiwKfQoKY29uc3QgQ0FURUdPUllfQ09MT1JTOiBSZWNvcmQ8c3RyaW5nLCBzdHJpbmc+ID0gewogIGdlbmVyYWw6ICdiZy1ibHVlLTkwMC80MCB0ZXh0LWJsdWUtMzAwIGJvcmRlci1ibHVlLTcwMCcsCiAgY29kZTogICAgJ2JnLWdyZWVuLTkwMC80MCB0ZXh0LWdyZWVuLTMwMCBib3JkZXItZ3JlZW4tNzAwJywKICB2aXNpb246ICAnYmctcHVycGxlLTkwMC80MCB0ZXh0LXB1cnBsZS0zMDAgYm9yZGVyLXB1cnBsZS03MDAnLAogIHNjaWVuY2U6ICdiZy1vcmFuZ2UtOTAwLzQwIHRleHQtb3JhbmdlLTMwMCBib3JkZXItb3JhbmdlLTcwMCcsCn0KCi8vIOKUgOKUgCBDaGF0IG1lc3NhZ2UgY29tcG9uZW50IOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApmdW5jdGlvbiBDaGF0TWVzc2FnZSh7IG1zZyB9OiB7IG1zZzogTWVzc2FnZSAmIHsgbG9hZGluZz86IGJvb2xlYW4gfSB9KSB7CiAgY29uc3QgaXNVc2VyID0gbXNnLnJvbGUgPT09ICd1c2VyJwogIHJldHVybiAoCiAgICA8ZGl2IGNsYXNzTmFtZT17YGZsZXggZ2FwLTMgJHtpc1VzZXIgPyAnZmxleC1yb3ctcmV2ZXJzZScgOiAnZmxleC1yb3cnfSBtYi02YH0+CiAgICAgIDxkaXYgY2xhc3NOYW1lPXtgZmxleC1zaHJpbmstMCB3LTggaC04IHJvdW5kZWQtZnVsbCBmbGV4IGl0ZW1zLWNlbnRlciBqdXN0aWZ5LWNlbnRlcgogICAgICAgICR7aXNVc2VyID8gJ2JnLWJsdWUtNjAwJyA6ICdiZy1ncmF5LTcwMCd9YH0+CiAgICAgICAge2lzVXNlciA/IDxVc2VyIGNsYXNzTmFtZT0idy00IGgtNCIgLz4gOiA8Qm90IGNsYXNzTmFtZT0idy00IGgtNCIgLz59CiAgICAgIDwvZGl2PgogICAgICA8ZGl2IGNsYXNzTmFtZT17YG1heC13LVs4MCVdIHJvdW5kZWQtMnhsIHB4LTQgcHktMyB0ZXh0LXNtCiAgICAgICAgJHtpc1VzZXIKICAgICAgICAgID8gJ2JnLWJsdWUtNjAwIHRleHQtd2hpdGUgcm91bmRlZC10ci1zbScKICAgICAgICAgIDogJ2JnLWdyYXktODAwIHRleHQtZ3JheS0xMDAgcm91bmRlZC10bC1zbSd9YH0+CiAgICAgICAge21zZy5sb2FkaW5nID8gKAogICAgICAgICAgPHNwYW4gY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMiB0ZXh0LWdyYXktNDAwIj4KICAgICAgICAgICAgPExvYWRlcjIgY2xhc3NOYW1lPSJ3LTMgaC0zIGFuaW1hdGUtc3BpbiIgLz4gVGhpbmtpbmfigKYKICAgICAgICAgIDwvc3Bhbj4KICAgICAgICApIDogaXNVc2VyID8gKAogICAgICAgICAgPHAgY2xhc3NOYW1lPSJ3aGl0ZXNwYWNlLXByZS13cmFwIj57bXNnLmNvbnRlbnR9PC9wPgogICAgICAgICkgOiAoCiAgICAgICAgICA8UmVhY3RNYXJrZG93bgogICAgICAgICAgICByZW1hcmtQbHVnaW5zPXtbcmVtYXJrR2ZtXX0KICAgICAgICAgICAgY29tcG9uZW50cz17ewogICAgICAgICAgICAgIGNvZGUoeyBub2RlLCBjbGFzc05hbWUsIGNoaWxkcmVuLCAuLi5wcm9wcyB9OiBhbnkpIHsKICAgICAgICAgICAgICAgIGNvbnN0IGlubGluZSA9ICFjbGFzc05hbWUKICAgICAgICAgICAgICAgIHJldHVybiBpbmxpbmUKICAgICAgICAgICAgICAgICAgPyA8Y29kZSBjbGFzc05hbWU9ImJnLWdyYXktOTAwIHB4LTEgcHktMC41IHJvdW5kZWQgdGV4dC1ibHVlLTMwMCB0ZXh0LXhzIiB7Li4ucHJvcHN9PntjaGlsZHJlbn08L2NvZGU+CiAgICAgICAgICAgICAgICAgIDogPHByZSBjbGFzc05hbWU9ImJnLWdyYXktOTAwIHJvdW5kZWQtbGcgcC0zIG92ZXJmbG93LXgtYXV0byBteS0yIj4KICAgICAgICAgICAgICAgICAgICAgIDxjb2RlIGNsYXNzTmFtZT0idGV4dC14cyB0ZXh0LWdyYXktMjAwIj57Y2hpbGRyZW59PC9jb2RlPgogICAgICAgICAgICAgICAgICAgIDwvcHJlPgogICAgICAgICAgICAgIH0sCiAgICAgICAgICAgICAgcDogKHsgY2hpbGRyZW4gfSkgPT4gPHAgY2xhc3NOYW1lPSJtYi0yIGxhc3Q6bWItMCI+e2NoaWxkcmVufTwvcD4sCiAgICAgICAgICAgICAgdWw6ICh7IGNoaWxkcmVuIH0pID0+IDx1bCBjbGFzc05hbWU9Imxpc3QtZGlzYyBsaXN0LWluc2lkZSBtYi0yIHNwYWNlLXktMSI+e2NoaWxkcmVufTwvdWw+LAogICAgICAgICAgICAgIG9sOiAoeyBjaGlsZHJlbiB9KSA9PiA8b2wgY2xhc3NOYW1lPSJsaXN0LWRlY2ltYWwgbGlzdC1pbnNpZGUgbWItMiBzcGFjZS15LTEiPntjaGlsZHJlbn08L29sPiwKICAgICAgICAgICAgfX0KICAgICAgICAgID57bXNnLmNvbnRlbnR9PC9SZWFjdE1hcmtkb3duPgogICAgICAgICl9CiAgICAgIDwvZGl2PgogICAgPC9kaXY+CiAgKQp9CgovLyDilIDilIAgTW9kZWwgc2VsZWN0b3Ig4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACmZ1bmN0aW9uIE1vZGVsU2VsZWN0b3IoeyBtb2RlbHMsIHNlbGVjdGVkLCBvblNlbGVjdCB9OiB7CiAgbW9kZWxzOiBNb2RlbFtdLCBzZWxlY3RlZDogc3RyaW5nLCBvblNlbGVjdDogKGlkOiBzdHJpbmcpID0+IHZvaWQKfSkgewogIGNvbnN0IFtvcGVuLCBzZXRPcGVuXSA9IHVzZVN0YXRlKGZhbHNlKQogIGNvbnN0IGN1cnJlbnQgPSBtb2RlbHMuZmluZChtID0+IG0uaWQgPT09IHNlbGVjdGVkKQoKICByZXR1cm4gKAogICAgPGRpdiBjbGFzc05hbWU9InJlbGF0aXZlIj4KICAgICAgPGJ1dHRvbgogICAgICAgIG9uQ2xpY2s9eygpID0+IHNldE9wZW4oIW9wZW4pfQogICAgICAgIGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTIgYmctZ3JheS04MDAgaG92ZXI6YmctZ3JheS03MDAgYm9yZGVyIGJvcmRlci1ncmF5LTYwMAogICAgICAgICAgcm91bmRlZC14bCBweC0zIHB5LTIgdGV4dC1zbSB0cmFuc2l0aW9uLWNvbG9ycyIKICAgICAgPgogICAgICAgIDxzcGFuPntDQVRFR09SWV9JQ09OU1tjdXJyZW50Py5jYXRlZ29yeSA/PyAnZ2VuZXJhbCddfTwvc3Bhbj4KICAgICAgICA8c3BhbiBjbGFzc05hbWU9Im1heC13LVsxNjBweF0gdHJ1bmNhdGUiPntjdXJyZW50Py5pZCA/PyBzZWxlY3RlZH08L3NwYW4+CiAgICAgICAgPENoZXZyb25Eb3duIGNsYXNzTmFtZT17YHctMyBoLTMgdHJhbnNpdGlvbi10cmFuc2Zvcm0gJHtvcGVuID8gJ3JvdGF0ZS0xODAnIDogJyd9YH0gLz4KICAgICAgPC9idXR0b24+CgogICAgICB7b3BlbiAmJiAoCiAgICAgICAgPGRpdiBjbGFzc05hbWU9ImFic29sdXRlIHRvcC1mdWxsIGxlZnQtMCBtdC0xIHctODAgYmctZ3JheS04MDAgYm9yZGVyIGJvcmRlci1ncmF5LTYwMAogICAgICAgICAgcm91bmRlZC14bCBzaGFkb3ctMnhsIHotNTAgb3ZlcmZsb3ctaGlkZGVuIj4KICAgICAgICAgIHsvKiBHcm91cCBieSBjYXRlZ29yeSAqL30KICAgICAgICAgIHtbJ2dlbmVyYWwnLCAnY29kZScsICd2aXNpb24nLCAnc2NpZW5jZSddLm1hcChjYXQgPT4gewogICAgICAgICAgICBjb25zdCBjYXRNb2RlbHMgPSBtb2RlbHMuZmlsdGVyKG0gPT4gbS5jYXRlZ29yeSA9PT0gY2F0KQogICAgICAgICAgICBpZiAoIWNhdE1vZGVscy5sZW5ndGgpIHJldHVybiBudWxsCiAgICAgICAgICAgIHJldHVybiAoCiAgICAgICAgICAgICAgPGRpdiBrZXk9e2NhdH0+CiAgICAgICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0icHgtMyBweS0xLjUgdGV4dC14cyB0ZXh0LWdyYXktNTAwIHVwcGVyY2FzZSB0cmFja2luZy13aWRlciBib3JkZXItYiBib3JkZXItZ3JheS03MDAiPgogICAgICAgICAgICAgICAgICB7Y2F0fQogICAgICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICAgICAgICB7Y2F0TW9kZWxzLm1hcChtID0+ICgKICAgICAgICAgICAgICAgICAgPGJ1dHRvbgogICAgICAgICAgICAgICAgICAgIGtleT17bS5pZH0KICAgICAgICAgICAgICAgICAgICBvbkNsaWNrPXsoKSA9PiB7IG9uU2VsZWN0KG0uaWQpOyBzZXRPcGVuKGZhbHNlKSB9fQogICAgICAgICAgICAgICAgICAgIGNsYXNzTmFtZT17YHctZnVsbCB0ZXh0LWxlZnQgcHgtMyBweS0yLjUgaG92ZXI6YmctZ3JheS03MDAgdHJhbnNpdGlvbi1jb2xvcnMKICAgICAgICAgICAgICAgICAgICAgICR7c2VsZWN0ZWQgPT09IG0uaWQgPyAnYmctZ3JheS03MDAnIDogJyd9YH0KICAgICAgICAgICAgICAgICAgPgogICAgICAgICAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMiI+CiAgICAgICAgICAgICAgICAgICAgICA8c3Bhbj57Q0FURUdPUllfSUNPTlNbY2F0XX08L3NwYW4+CiAgICAgICAgICAgICAgICAgICAgICA8ZGl2PgogICAgICAgICAgICAgICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0idGV4dC1zbSBmb250LW1lZGl1bSB0ZXh0LWdyYXktMTAwIj57bS5pZH08L2Rpdj4KICAgICAgICAgICAgICAgICAgICAgICAgPGRpdiBjbGFzc05hbWU9InRleHQteHMgdGV4dC1ncmF5LTQwMCI+e20uZGVzY3JpcHRpb259PC9kaXY+CiAgICAgICAgICAgICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICAgICAgICAgPC9idXR0b24+CiAgICAgICAgICAgICAgICApKX0KICAgICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICAgKQogICAgICAgICAgfSl9CiAgICAgICAgPC9kaXY+CiAgICAgICl9CiAgICA8L2Rpdj4KICApCn0KCi8vIOKUgOKUgCBTdGF0dXMgYmFyIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApmdW5jdGlvbiBTdGF0dXNCYXIoeyBzdGF0dXMsIHRva2VucywgZ3B1IH06IHsgc3RhdHVzOiBOb2RlU3RhdHVzIHwgbnVsbCwgdG9rZW5zOiBUb2tlbkJhbGFuY2UgfCBudWxsLCBncHU6IEdwdVN0YXR1cyB8IG51bGwgfSkgewogIHJldHVybiAoCiAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTQgcHgtNCBweS0yIGJnLWdyYXktOTAwIGJvcmRlci1iIGJvcmRlci1ncmF5LTgwMCB0ZXh0LXhzIHRleHQtZ3JheS00MDAiPgogICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTEuNSI+CiAgICAgICAgPGRpdiBjbGFzc05hbWU9e2B3LTIgaC0yIHJvdW5kZWQtZnVsbCAke3N0YXR1cyA/ICdiZy1ncmVlbi00MDAnIDogJ2JnLXJlZC00MDAnfWB9IC8+CiAgICAgICAgPHNwYW4+e3N0YXR1cyA/ICdOb2RlIG9ubGluZScgOiAnTm9kZSBvZmZsaW5lJ308L3NwYW4+CiAgICAgIDwvZGl2PgogICAgICB7c3RhdHVzICYmICgKICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTEiPgogICAgICAgICAgPEdsb2JlIGNsYXNzTmFtZT0idy0zIGgtMyIgLz4KICAgICAgICAgIDxzcGFuPntzdGF0dXMucGVlcl9jb3VudH0gcGVlcntzdGF0dXMucGVlcl9jb3VudCAhPT0gMSA/ICdzJyA6ICcnfTwvc3Bhbj4KICAgICAgICA8L2Rpdj4KICAgICAgKX0KICAgICAge3Rva2VucyAmJiAoCiAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXggaXRlbXMtY2VudGVyIGdhcC0xIHRleHQteWVsbG93LTQwMCI+CiAgICAgICAgICA8Q29pbnMgY2xhc3NOYW1lPSJ3LTMgaC0zIiAvPgogICAgICAgICAgPHNwYW4+e3Rva2Vucy5iYWxhbmNlLnRvTG9jYWxlU3RyaW5nKCl9IHRva2Vuczwvc3Bhbj4KICAgICAgICA8L2Rpdj4KICAgICAgKX0KICAgICAge2dwdT8uYXZhaWxhYmxlICYmICgKICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTEgdGV4dC1wdXJwbGUtNDAwIj4KICAgICAgICAgIDxDcHUgY2xhc3NOYW1lPSJ3LTMgaC0zIiAvPgogICAgICAgICAgPHNwYW4+e2dwdS5iYWNrZW5kfSDCtyB7Z3B1LmRldmljZXMubWFwKGQgPT4gZC5uYW1lLnJlcGxhY2UoL05WSURJQSB8QU1EIC9naSwgJycpKS5qb2luKCcsICcpfTwvc3Bhbj4KICAgICAgICAgIHtncHUuZGV2aWNlc1swXT8udnJhbV9nYiA+IDAgJiYgKAogICAgICAgICAgICA8c3BhbiBjbGFzc05hbWU9InRleHQtcHVycGxlLTUwMCI+KHtncHUuZGV2aWNlcy5yZWR1Y2UoKHMsZCkgPT4gcytkLnZyYW1fZ2IsMCl9IEdCIFZSQU0pPC9zcGFuPgogICAgICAgICAgKX0KICAgICAgICA8L2Rpdj4KICAgICAgKX0KICAgICAgPGRpdiBjbGFzc05hbWU9Im1sLWF1dG8gdGV4dC1ncmF5LTYwMCBmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMSI+CiAgICAgICAgPENwdSBjbGFzc05hbWU9InctMyBoLTMiIC8+CiAgICAgICAgQUk0QWxsIHYwLjEuMAogICAgICA8L2Rpdj4KICAgIDwvZGl2PgogICkKfQoKLy8g4pSA4pSAIE1haW4gQXBwIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgApleHBvcnQgZGVmYXVsdCBmdW5jdGlvbiBBcHAoKSB7CiAgY29uc3QgW21vZGVscywgICAgc2V0TW9kZWxzXSAgID0gdXNlU3RhdGU8TW9kZWxbXT4oW10pCiAgY29uc3QgW21vZGVsLCAgICAgc2V0TW9kZWxdICAgID0gdXNlU3RhdGUoJ2FpNGFsbC9sbGFtYTMnKQogIGNvbnN0IFttZXNzYWdlcywgIHNldE1lc3NhZ2VzXSA9IHVzZVN0YXRlPChNZXNzYWdlICYgeyBsb2FkaW5nPzogYm9vbGVhbiB9KVtdPihbXSkKICBjb25zdCBbaW5wdXQsICAgICBzZXRJbnB1dF0gICAgPSB1c2VTdGF0ZSgnJykKICBjb25zdCBbc3RyZWFtaW5nLCBzZXRTdHJlYW1pbmddID0gdXNlU3RhdGUoZmFsc2UpCiAgY29uc3QgW3N0YXR1cywgICAgc2V0U3RhdHVzXSAgID0gdXNlU3RhdGU8Tm9kZVN0YXR1cyB8IG51bGw+KG51bGwpCiAgY29uc3QgW3Rva2VucywgICAgc2V0VG9rZW5zXSAgID0gdXNlU3RhdGU8VG9rZW5CYWxhbmNlIHwgbnVsbD4obnVsbCkKICBjb25zdCBbZ3B1LCAgICAgICBzZXRHcHVdICAgICAgPSB1c2VTdGF0ZTxHcHVTdGF0dXMgfCBudWxsPihudWxsKQogIGNvbnN0IFt0ZW1wLCAgICAgIHNldFRlbXBdICAgICA9IHVzZVN0YXRlKDAuNykKICBjb25zdCBib3R0b21SZWYgICA9IHVzZVJlZjxIVE1MRGl2RWxlbWVudD4obnVsbCkKICBjb25zdCB0ZXh0YXJlYVJlZiA9IHVzZVJlZjxIVE1MVGV4dEFyZWFFbGVtZW50PihudWxsKQoKICAvLyBJbml0aWFsIGxvYWQKICB1c2VFZmZlY3QoKCkgPT4gewogICAgZmV0Y2hNb2RlbHMoKS50aGVuKG1zID0+IHsgc2V0TW9kZWxzKG1zKTsgaWYgKG1zLmxlbmd0aCkgc2V0TW9kZWwobXNbMF0uaWQpIH0pLmNhdGNoKCgpID0+IHt9KQogICAgcmVmcmVzaFN0YXR1cygpCiAgICBjb25zdCBpdiA9IHNldEludGVydmFsKHJlZnJlc2hTdGF0dXMsIDE1XzAwMCkKICAgIHJldHVybiAoKSA9PiBjbGVhckludGVydmFsKGl2KQogIH0sIFtdKQoKICBjb25zdCByZWZyZXNoU3RhdHVzID0gKCkgPT4gewogICAgZmV0Y2hOb2RlU3RhdHVzKCkudGhlbihzZXRTdGF0dXMpLmNhdGNoKCgpID0+IHNldFN0YXR1cyhudWxsKSkKICAgIGZldGNoVG9rZW5CYWxhbmNlKCkudGhlbihzZXRUb2tlbnMpLmNhdGNoKCgpID0+IHt9KQogICAgZmV0Y2hHcHVTdGF0dXMoKS50aGVuKHNldEdwdSkuY2F0Y2goKCkgPT4ge30pCiAgfQoKICB1c2VFZmZlY3QoKCkgPT4gewogICAgYm90dG9tUmVmLmN1cnJlbnQ/LnNjcm9sbEludG9WaWV3KHsgYmVoYXZpb3I6ICdzbW9vdGgnIH0pCiAgfSwgW21lc3NhZ2VzXSkKCiAgY29uc3Qgc2VuZE1lc3NhZ2UgPSB1c2VDYWxsYmFjayhhc3luYyAoKSA9PiB7CiAgICBjb25zdCB0ZXh0ID0gaW5wdXQudHJpbSgpCiAgICBpZiAoIXRleHQgfHwgc3RyZWFtaW5nKSByZXR1cm4KCiAgICBjb25zdCB1c2VyTXNnOiBNZXNzYWdlID0geyByb2xlOiAndXNlcicsIGNvbnRlbnQ6IHRleHQgfQogICAgY29uc3QgcGxhY2Vob2xkZXIgPSB7IHJvbGU6ICdhc3Npc3RhbnQnIGFzIGNvbnN0LCBjb250ZW50OiAnJywgbG9hZGluZzogdHJ1ZSB9CgogICAgc2V0TWVzc2FnZXMocHJldiA9PiBbLi4ucHJldiwgdXNlck1zZywgcGxhY2Vob2xkZXJdKQogICAgc2V0SW5wdXQoJycpCiAgICBzZXRTdHJlYW1pbmcodHJ1ZSkKCiAgICBjb25zdCBoaXN0b3J5OiBNZXNzYWdlW10gPSBbLi4ubWVzc2FnZXMsIHVzZXJNc2ddCgogICAgdHJ5IHsKICAgICAgbGV0IGZ1bGxDb250ZW50ID0gJycKICAgICAgZm9yIGF3YWl0IChjb25zdCB0b2tlbiBvZiBzdHJlYW1DaGF0KG1vZGVsLCBoaXN0b3J5LCB0ZW1wKSkgewogICAgICAgIGZ1bGxDb250ZW50ICs9IHRva2VuCiAgICAgICAgc2V0TWVzc2FnZXMocHJldiA9PiB7CiAgICAgICAgICBjb25zdCBuZXh0ID0gWy4uLnByZXZdCiAgICAgICAgICBuZXh0W25leHQubGVuZ3RoIC0gMV0gPSB7IHJvbGU6ICdhc3Npc3RhbnQnLCBjb250ZW50OiBmdWxsQ29udGVudCwgbG9hZGluZzogZmFsc2UgfQogICAgICAgICAgcmV0dXJuIG5leHQKICAgICAgICB9KQogICAgICB9CiAgICB9IGNhdGNoIChlcnI6IGFueSkgewogICAgICBzZXRNZXNzYWdlcyhwcmV2ID0+IHsKICAgICAgICBjb25zdCBuZXh0ID0gWy4uLnByZXZdCiAgICAgICAgbmV4dFtuZXh0Lmxlbmd0aCAtIDFdID0gewogICAgICAgICAgcm9sZTogJ2Fzc2lzdGFudCcsCiAgICAgICAgICBjb250ZW50OiBg4p2MICoqRXJyb3I6KiogJHtlcnIubWVzc2FnZX1cblxuTWFrZSBzdXJlIE9sbGFtYSBpcyBydW5uaW5nOiBcYG9sbGFtYSBzZXJ2ZVxgYCwKICAgICAgICAgIGxvYWRpbmc6IGZhbHNlLAogICAgICAgIH0KICAgICAgICByZXR1cm4gbmV4dAogICAgICB9KQogICAgfSBmaW5hbGx5IHsKICAgICAgc2V0U3RyZWFtaW5nKGZhbHNlKQogICAgICB0ZXh0YXJlYVJlZi5jdXJyZW50Py5mb2N1cygpCiAgICB9CiAgfSwgW2lucHV0LCBtZXNzYWdlcywgbW9kZWwsIHN0cmVhbWluZywgdGVtcF0pCgogIGNvbnN0IGhhbmRsZUtleURvd24gPSAoZTogUmVhY3QuS2V5Ym9hcmRFdmVudCkgPT4gewogICAgaWYgKGUua2V5ID09PSAnRW50ZXInICYmICFlLnNoaWZ0S2V5KSB7IGUucHJldmVudERlZmF1bHQoKTsgc2VuZE1lc3NhZ2UoKSB9CiAgfQoKICBjb25zdCBjbGVhckNoYXQgPSAoKSA9PiBzZXRNZXNzYWdlcyhbXSkKCiAgcmV0dXJuICgKICAgIDxkaXYgY2xhc3NOYW1lPSJmbGV4IGZsZXgtY29sIGgtc2NyZWVuIGJnLWdyYXktOTUwIj4KICAgICAgey8qIEhlYWRlciAqL30KICAgICAgPGhlYWRlciBjbGFzc05hbWU9ImZsZXggaXRlbXMtY2VudGVyIGp1c3RpZnktYmV0d2VlbiBweC02IHB5LTMgYmctZ3JheS05MDAgYm9yZGVyLWIgYm9yZGVyLWdyYXktODAwIj4KICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTMiPgogICAgICAgICAgPGRpdiBjbGFzc05hbWU9InctOCBoLTggYmctYmx1ZS02MDAgcm91bmRlZC1sZyBmbGV4IGl0ZW1zLWNlbnRlciBqdXN0aWZ5LWNlbnRlciBmb250LWJvbGQgdGV4dC1zbSI+CiAgICAgICAgICAgIEEKICAgICAgICAgIDwvZGl2PgogICAgICAgICAgPGRpdj4KICAgICAgICAgICAgPGgxIGNsYXNzTmFtZT0iZm9udC1zZW1pYm9sZCB0ZXh0LXdoaXRlIj5BSTRBbGw8L2gxPgogICAgICAgICAgICA8cCBjbGFzc05hbWU9InRleHQteHMgdGV4dC1ncmF5LTQwMCI+RGVjZW50cmFsaXplZCBBSSBmb3IgRXZlcnlvbmU8L3A+CiAgICAgICAgICA8L2Rpdj4KICAgICAgICA8L2Rpdj4KICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTIiPgogICAgICAgICAgPGJ1dHRvbgogICAgICAgICAgICBvbkNsaWNrPXtyZWZyZXNoU3RhdHVzfQogICAgICAgICAgICBjbGFzc05hbWU9InAtMiBob3ZlcjpiZy1ncmF5LTgwMCByb3VuZGVkLWxnIHRyYW5zaXRpb24tY29sb3JzIHRleHQtZ3JheS00MDAgaG92ZXI6dGV4dC13aGl0ZSIKICAgICAgICAgICAgdGl0bGU9IlJlZnJlc2ggc3RhdHVzIgogICAgICAgICAgPgogICAgICAgICAgICA8UmVmcmVzaEN3IGNsYXNzTmFtZT0idy00IGgtNCIgLz4KICAgICAgICAgIDwvYnV0dG9uPgogICAgICAgICAgPGJ1dHRvbgogICAgICAgICAgICBvbkNsaWNrPXtjbGVhckNoYXR9CiAgICAgICAgICAgIGNsYXNzTmFtZT0icHgtMyBweS0xLjUgdGV4dC14cyB0ZXh0LWdyYXktNDAwIGhvdmVyOnRleHQtd2hpdGUgaG92ZXI6YmctZ3JheS04MDAKICAgICAgICAgICAgICByb3VuZGVkLWxnIHRyYW5zaXRpb24tY29sb3JzIGJvcmRlciBib3JkZXItZ3JheS03MDAiCiAgICAgICAgICA+CiAgICAgICAgICAgIE5ldyBjaGF0CiAgICAgICAgICA8L2J1dHRvbj4KICAgICAgICA8L2Rpdj4KICAgICAgPC9oZWFkZXI+CgogICAgICB7LyogU3RhdHVzIGJhciAqL30KICAgICAgPFN0YXR1c0JhciBzdGF0dXM9e3N0YXR1c30gdG9rZW5zPXt0b2tlbnN9IGdwdT17Z3B1fSAvPgoKICAgICAgey8qIE1lc3NhZ2VzICovfQogICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleC0xIG92ZXJmbG93LXktYXV0byBweC00IHB5LTYiPgogICAgICAgIDxkaXYgY2xhc3NOYW1lPSJtYXgtdy0zeGwgbXgtYXV0byI+CiAgICAgICAgICB7bWVzc2FnZXMubGVuZ3RoID09PSAwICYmICgKICAgICAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXggZmxleC1jb2wgaXRlbXMtY2VudGVyIGp1c3RpZnktY2VudGVyIGgtZnVsbCBtaW4taC1bNDAwcHhdIHRleHQtY2VudGVyIj4KICAgICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0idy0xNiBoLTE2IGJnLWJsdWUtNjAwLzIwIHJvdW5kZWQtMnhsIGZsZXggaXRlbXMtY2VudGVyIGp1c3RpZnktY2VudGVyIG1iLTQiPgogICAgICAgICAgICAgICAgPEJvdCBjbGFzc05hbWU9InctOCBoLTggdGV4dC1ibHVlLTQwMCIgLz4KICAgICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICAgICA8aDIgY2xhc3NOYW1lPSJ0ZXh0LXhsIGZvbnQtc2VtaWJvbGQgdGV4dC13aGl0ZSBtYi0yIj5Ib3cgY2FuIEkgaGVscCB5b3U/PC9oMj4KICAgICAgICAgICAgICA8cCBjbGFzc05hbWU9InRleHQtZ3JheS00MDAgdGV4dC1zbSBtYXgtdy1zbSI+CiAgICAgICAgICAgICAgICBBSTRBbGwgcnVucyBBSSBtb2RlbHMgYWNyb3NzIGEgZGVjZW50cmFsaXplZCBuZXR3b3JrLgogICAgICAgICAgICAgICAgQ2hvb3NlIGEgbW9kZWwgYW5kIHN0YXJ0IGNoYXR0aW5nLgogICAgICAgICAgICAgIDwvcD4KICAgICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0ibXQtNiBncmlkIGdyaWQtY29scy0yIGdhcC0yIG1heC13LXNtIHctZnVsbCI+CiAgICAgICAgICAgICAgICB7WwogICAgICAgICAgICAgICAgICAn4pyN77iPIFdyaXRlIGEgUHl0aG9uIGZ1bmN0aW9uIHRvIHBhcnNlIEpTT04nLAogICAgICAgICAgICAgICAgICAn8J+UrCBFeHBsYWluIHF1YW50dW0gZW50YW5nbGVtZW50IHNpbXBseScsCiAgICAgICAgICAgICAgICAgICfwn5KhIEdpdmUgbWUgaWRlYXMgZm9yIGEgc2lkZSBwcm9qZWN0JywKICAgICAgICAgICAgICAgICAgJ/CflI0gV2hhdCBhcmUgdGhlIGxhdGVzdCBBSSBmcmFtZXdvcmtzPycsCiAgICAgICAgICAgICAgICBdLm1hcChzdWdnZXN0aW9uID0+ICgKICAgICAgICAgICAgICAgICAgPGJ1dHRvbgogICAgICAgICAgICAgICAgICAgIGtleT17c3VnZ2VzdGlvbn0KICAgICAgICAgICAgICAgICAgICBvbkNsaWNrPXsoKSA9PiBzZXRJbnB1dChzdWdnZXN0aW9uLnNsaWNlKDMpKX0KICAgICAgICAgICAgICAgICAgICBjbGFzc05hbWU9InRleHQtbGVmdCBweC0zIHB5LTIgYmctZ3JheS04MDAgaG92ZXI6YmctZ3JheS03MDAgcm91bmRlZC14bAogICAgICAgICAgICAgICAgICAgICAgdGV4dC14cyB0ZXh0LWdyYXktMzAwIHRyYW5zaXRpb24tY29sb3JzIGJvcmRlciBib3JkZXItZ3JheS03MDAiCiAgICAgICAgICAgICAgICAgID4KICAgICAgICAgICAgICAgICAgICB7c3VnZ2VzdGlvbn0KICAgICAgICAgICAgICAgICAgPC9idXR0b24+CiAgICAgICAgICAgICAgICApKX0KICAgICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICApfQoKICAgICAgICAgIHttZXNzYWdlcy5tYXAoKG1zZywgaSkgPT4gKAogICAgICAgICAgICA8Q2hhdE1lc3NhZ2Uga2V5PXtpfSBtc2c9e21zZ30gLz4KICAgICAgICAgICkpfQogICAgICAgICAgPGRpdiByZWY9e2JvdHRvbVJlZn0gLz4KICAgICAgICA8L2Rpdj4KICAgICAgPC9kaXY+CgogICAgICB7LyogSW5wdXQgYXJlYSAqL30KICAgICAgPGRpdiBjbGFzc05hbWU9ImJvcmRlci10IGJvcmRlci1ncmF5LTgwMCBiZy1ncmF5LTkwMCBweC00IHB5LTQiPgogICAgICAgIDxkaXYgY2xhc3NOYW1lPSJtYXgtdy0zeGwgbXgtYXV0byI+CiAgICAgICAgICB7LyogVG9vbGJhciAqL30KICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMiBtYi0zIj4KICAgICAgICAgICAgPE1vZGVsU2VsZWN0b3IgbW9kZWxzPXttb2RlbHN9IHNlbGVjdGVkPXttb2RlbH0gb25TZWxlY3Q9e3NldE1vZGVsfSAvPgogICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTIgbWwtYXV0byB0ZXh0LXhzIHRleHQtZ3JheS01MDAiPgogICAgICAgICAgICAgIDxzcGFuPlRlbXA8L3NwYW4+CiAgICAgICAgICAgICAgPGlucHV0CiAgICAgICAgICAgICAgICB0eXBlPSJyYW5nZSIgbWluPSIwIiBtYXg9IjIiIHN0ZXA9IjAuMSIgdmFsdWU9e3RlbXB9CiAgICAgICAgICAgICAgICBvbkNoYW5nZT17ZSA9PiBzZXRUZW1wKHBhcnNlRmxvYXQoZS50YXJnZXQudmFsdWUpKX0KICAgICAgICAgICAgICAgIGNsYXNzTmFtZT0idy0yMCBhY2NlbnQtYmx1ZS01MDAiCiAgICAgICAgICAgICAgLz4KICAgICAgICAgICAgICA8c3BhbiBjbGFzc05hbWU9InctNiB0ZXh0LWdyYXktMzAwIj57dGVtcC50b0ZpeGVkKDEpfTwvc3Bhbj4KICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8L2Rpdj4KCiAgICAgICAgICB7LyogVGV4dGFyZWEgKyBTZW5kICovfQogICAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXggZ2FwLTIgaXRlbXMtZW5kIj4KICAgICAgICAgICAgPHRleHRhcmVhCiAgICAgICAgICAgICAgcmVmPXt0ZXh0YXJlYVJlZn0KICAgICAgICAgICAgICB2YWx1ZT17aW5wdXR9CiAgICAgICAgICAgICAgb25DaGFuZ2U9e2UgPT4gc2V0SW5wdXQoZS50YXJnZXQudmFsdWUpfQogICAgICAgICAgICAgIG9uS2V5RG93bj17aGFuZGxlS2V5RG93bn0KICAgICAgICAgICAgICBwbGFjZWhvbGRlcj0iTWVzc2FnZSBBSTRBbGzigKYgKEVudGVyIHRvIHNlbmQsIFNoaWZ0K0VudGVyIGZvciBuZXdsaW5lKSIKICAgICAgICAgICAgICByb3dzPXsxfQogICAgICAgICAgICAgIHN0eWxlPXt7IHJlc2l6ZTogJ25vbmUnIH19CiAgICAgICAgICAgICAgY2xhc3NOYW1lPSJmbGV4LTEgYmctZ3JheS04MDAgYm9yZGVyIGJvcmRlci1ncmF5LTcwMCByb3VuZGVkLXhsIHB4LTQgcHktMwogICAgICAgICAgICAgICAgdGV4dC1zbSB0ZXh0LXdoaXRlIHBsYWNlaG9sZGVyLWdyYXktNTAwIGZvY3VzOm91dGxpbmUtbm9uZSBmb2N1czpib3JkZXItYmx1ZS01MDAKICAgICAgICAgICAgICAgIHRyYW5zaXRpb24tY29sb3JzIG1pbi1oLVs0OHB4XSBtYXgtaC00OCBvdmVyZmxvdy15LWF1dG8iCiAgICAgICAgICAgICAgb25JbnB1dD17ZSA9PiB7CiAgICAgICAgICAgICAgICBjb25zdCBlbCA9IGUuY3VycmVudFRhcmdldAogICAgICAgICAgICAgICAgZWwuc3R5bGUuaGVpZ2h0ID0gJ2F1dG8nCiAgICAgICAgICAgICAgICBlbC5zdHlsZS5oZWlnaHQgPSBNYXRoLm1pbihlbC5zY3JvbGxIZWlnaHQsIDE5MikgKyAncHgnCiAgICAgICAgICAgICAgfX0KICAgICAgICAgICAgLz4KICAgICAgICAgICAgPGJ1dHRvbgogICAgICAgICAgICAgIG9uQ2xpY2s9e3NlbmRNZXNzYWdlfQogICAgICAgICAgICAgIGRpc2FibGVkPXshaW5wdXQudHJpbSgpIHx8IHN0cmVhbWluZ30KICAgICAgICAgICAgICBjbGFzc05hbWU9ImZsZXgtc2hyaW5rLTAgdy0xMCBoLTEwIGJnLWJsdWUtNjAwIGhvdmVyOmJnLWJsdWUtNTAwIGRpc2FibGVkOmJnLWdyYXktNzAwCiAgICAgICAgICAgICAgICBkaXNhYmxlZDpjdXJzb3Itbm90LWFsbG93ZWQgcm91bmRlZC14bCBmbGV4IGl0ZW1zLWNlbnRlciBqdXN0aWZ5LWNlbnRlciB0cmFuc2l0aW9uLWNvbG9ycyIKICAgICAgICAgICAgPgogICAgICAgICAgICAgIHtzdHJlYW1pbmcKICAgICAgICAgICAgICAgID8gPExvYWRlcjIgY2xhc3NOYW1lPSJ3LTQgaC00IGFuaW1hdGUtc3BpbiIgLz4KICAgICAgICAgICAgICAgIDogPFNlbmQgY2xhc3NOYW1lPSJ3LTQgaC00IiAvPgogICAgICAgICAgICAgIH0KICAgICAgICAgICAgPC9idXR0b24+CiAgICAgICAgICA8L2Rpdj4KICAgICAgICAgIDxwIGNsYXNzTmFtZT0idGV4dC14cyB0ZXh0LWdyYXktNjAwIG10LTIgdGV4dC1jZW50ZXIiPgogICAgICAgICAgICBBSTRBbGwgaXMgb3BlbiBzb3VyY2UgYW5kIGNvbW11bml0eS1vcGVyYXRlZC4gUmVzcG9uc2VzIG1heSBiZSBpbmFjY3VyYXRlLgogICAgICAgICAgPC9wPgogICAgICAgIDwvZGl2PgogICAgICA8L2Rpdj4KICAgIDwvZGl2PgogICkKfQo=' | base64 -d > webui/src/App.tsx

success "Alle Dateien geschrieben"

# ── Git init & commit ─────────────────────────────────────────────────────
echo ""
info "Initialisiere Git-Repository..."

if [ ! -d ".git" ]; then git init; fi

if git remote get-url origin &>/dev/null 2>&1; then
  git remote set-url origin "$REPO"
else
  git remote add origin "$REPO"
fi

git add -A
CHANGED=$(git status --short | wc -l | tr -d ' ')
info "$CHANGED Datei(en) zur Versionierung vorgemerkt"

git diff --cached --quiet && warn "Keine Änderungen – alles bereits committet." || \
  git commit -m "fix: add all missing project files

- api/Dockerfile
- api/requirements.txt
- webui/Dockerfile.prod
- webui/package.json + tsconfig + vite config
- webui/src/ (App.tsx, api.ts, main.tsx, index.css)
- webui/nginx.conf"

git branch -M main
info "Pushe zu $REPO ..."
git push -u origin main --force

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅  Erfolgreich auf GitHub gepusht!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  🔗  https://github.com/FunCyRanger/AI4All"
echo ""
echo "  Nächster Schritt:"
echo "    git pull   (im geklonten Repo)"
echo "    bash setup.sh"
echo ""
