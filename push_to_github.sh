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
  CMD curl -sf http://localhost:8001/health || exit 1
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
      '/v1':     { target: 'http://localhost:8001', changeOrigin: true },
      '/health': { target: 'http://localhost:8001', changeOrigin: true },
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
echo 'aW1wb3J0IHsgdXNlU3RhdGUsIHVzZUVmZmVjdCwgdXNlUmVmLCB1c2VDYWxsYmFjayB9IGZyb20gJ3JlYWN0JwppbXBvcnQgUmVhY3RNYXJrZG93biBmcm9tICdyZWFjdC1tYXJrZG93bicKaW1wb3J0IHJlbWFya0dmbSBmcm9tICdyZW1hcmstZ2ZtJwppbXBvcnQgewogIFNlbmQsIEJvdCwgVXNlciwgQ3B1LCBDb2lucywgR2xvYmUsIENvZGUyLCBFeWUsCiAgRmxhc2tDb25pY2FsLCBMb2FkZXIyLCBDaGV2cm9uRG93biwgUmVmcmVzaEN3LAogIEFjdGl2aXR5LCBNZW1vcnlTdGljaywgVGhlcm1vbWV0ZXIsIFphcCwgR2lmdCwgWCwgQ2hldnJvblVwCn0gZnJvbSAnbHVjaWRlLXJlYWN0JwppbXBvcnQgewogIGZldGNoTW9kZWxzLCBmZXRjaFRva2VuQmFsYW5jZSwgZmV0Y2hOb2RlU3RhdHVzLCBmZXRjaEdwdVN0YXR1cywKICBzdHJlYW1DaGF0LCBNb2RlbCwgTWVzc2FnZSwgVG9rZW5CYWxhbmNlLCBOb2RlU3RhdHVzLCBHcHVTdGF0dXMKfSBmcm9tICcuL2FwaScKCi8vIOKUgOKUgCBUeXBlcyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKCmludGVyZmFjZSBTeXN0ZW1TdGF0cyB7CiAgY3B1X3BjdDogbnVtYmVyCiAgcmFtX3BjdDogbnVtYmVyCiAgcmFtX3VzZWRfZ2I6IG51bWJlcgogIHJhbV90b3RhbF9nYjogbnVtYmVyCiAgZ3B1OiBBcnJheTx7CiAgICBpbmRleDogbnVtYmVyOyBuYW1lOiBzdHJpbmc7IHZlbmRvcjogc3RyaW5nCiAgICB1dGlsX3BjdDogbnVtYmVyOyB2cmFtX3VzZWQ6IG51bWJlcjsgdnJhbV90b3RhbDogbnVtYmVyOyB0ZW1wX2M6IG51bWJlciB8IG51bGwKICB9Pgp9CgppbnRlcmZhY2UgSW5mZXJlbmNlU3RhdGUgewogIGFjdGl2ZTogYm9vbGVhbgogIG1vZGVsOiBzdHJpbmcKICB0b2tlbnNHZW5lcmF0ZWQ6IG51bWJlcgogIHRva2Vuc1BlclNlYzogbnVtYmVyCiAgZWxhcHNlZFNlYzogbnVtYmVyCiAgcGhhc2U6ICdsb2FkaW5nJyB8ICd0aGlua2luZycgfCAnZ2VuZXJhdGluZycKfQoKLy8g4pSA4pSAIENvbnN0YW50cyDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKCmNvbnN0IENBVEVHT1JZX0lDT05TOiBSZWNvcmQ8c3RyaW5nLCBSZWFjdC5SZWFjdE5vZGU+ID0gewogIGdlbmVyYWw6IDxHbG9iZSBjbGFzc05hbWU9InctNCBoLTQiIC8+LAogIGNvZGU6ICAgIDxDb2RlMiBjbGFzc05hbWU9InctNCBoLTQiIC8+LAogIHZpc2lvbjogIDxFeWUgY2xhc3NOYW1lPSJ3LTQgaC00IiAvPiwKICBzY2llbmNlOiA8Rmxhc2tDb25pY2FsIGNsYXNzTmFtZT0idy00IGgtNCIgLz4sCn0KCmNvbnN0IFBIQVNFX0xBQkVMUzogUmVjb3JkPHN0cmluZywgc3RyaW5nPiA9IHsKICBsb2FkaW5nOiAgICAnTW9kZWxsIHdpcmQgZ2VsYWRlbiDigKYnLAogIHRoaW5raW5nOiAgICdBbmFseXNpZXJ0IEFuZnJhZ2Ug4oCmJywKICBnZW5lcmF0aW5nOiAnR2VuZXJpZXJ0IEFudHdvcnQnLAp9Cgpjb25zdCBQSEFTRV9DT0xPUlM6IFJlY29yZDxzdHJpbmcsIHN0cmluZz4gPSB7CiAgbG9hZGluZzogICAgJ3RleHQteWVsbG93LTQwMCcsCiAgdGhpbmtpbmc6ICAgJ3RleHQtYmx1ZS00MDAnLAogIGdlbmVyYXRpbmc6ICd0ZXh0LWdyZWVuLTQwMCcsCn0KCi8vIOKUgOKUgCBIZWxwZXJzIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAoKZnVuY3Rpb24gZ2V0U2Vzc2lvbklkKCk6IHN0cmluZyB7CiAgbGV0IGlkID0gc2Vzc2lvblN0b3JhZ2UuZ2V0SXRlbSgnYWk0YWxsX3Nlc3Npb24nKQogIGlmICghaWQpIHsgaWQgPSBjcnlwdG8ucmFuZG9tVVVJRCgpOyBzZXNzaW9uU3RvcmFnZS5zZXRJdGVtKCdhaTRhbGxfc2Vzc2lvbicsIGlkKSB9CiAgcmV0dXJuIGlkCn0KCmFzeW5jIGZ1bmN0aW9uIGZldGNoU3lzdGVtU3RhdHMoKTogUHJvbWlzZTxTeXN0ZW1TdGF0cz4gewogIGNvbnN0IHIgPSBhd2FpdCBmZXRjaCgnL3YxL3N5c3RlbS9zdGF0cycpCiAgcmV0dXJuIHIuanNvbigpCn0KCmFzeW5jIGZ1bmN0aW9uIGNsYWltU3RhcnRlclRva2VucyhzZXNzaW9uSWQ6IHN0cmluZykgewogIGNvbnN0IHIgPSBhd2FpdCBmZXRjaCgnL3YxL3Rva2Vucy9zdGFydGVyJywgewogICAgbWV0aG9kOiAnUE9TVCcsCiAgICBoZWFkZXJzOiB7ICdDb250ZW50LVR5cGUnOiAnYXBwbGljYXRpb24vanNvbicgfSwKICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KHsgc2Vzc2lvbl9pZDogc2Vzc2lvbklkIH0pLAogIH0pCiAgcmV0dXJuIHIuanNvbigpCn0KCi8vIOKUgOKUgCBNaW5pIHByb2dyZXNzIGJhciDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKCmZ1bmN0aW9uIEJhcih7IHZhbHVlLCBjb2xvciA9ICdiZy1ibHVlLTUwMCcsIGxhYmVsIH06IHsgdmFsdWU6IG51bWJlcjsgY29sb3I/OiBzdHJpbmc7IGxhYmVsPzogc3RyaW5nIH0pIHsKICByZXR1cm4gKAogICAgPGRpdiBjbGFzc05hbWU9ImZsZXggaXRlbXMtY2VudGVyIGdhcC0yIj4KICAgICAge2xhYmVsICYmIDxzcGFuIGNsYXNzTmFtZT0idy04IHRleHQtcmlnaHQgdGV4dC1ncmF5LTUwMCB0ZXh0LXhzIj57bGFiZWx9PC9zcGFuPn0KICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXgtMSBoLTEuNSBiZy1ncmF5LTgwMCByb3VuZGVkLWZ1bGwgb3ZlcmZsb3ctaGlkZGVuIj4KICAgICAgICA8ZGl2CiAgICAgICAgICBjbGFzc05hbWU9e2BoLWZ1bGwgcm91bmRlZC1mdWxsIHRyYW5zaXRpb24tYWxsIGR1cmF0aW9uLTcwMCAke2NvbG9yfWB9CiAgICAgICAgICBzdHlsZT17eyB3aWR0aDogYCR7TWF0aC5taW4oMTAwLCB2YWx1ZSl9JWAgfX0KICAgICAgICAvPgogICAgICA8L2Rpdj4KICAgICAgPHNwYW4gY2xhc3NOYW1lPSJ3LTkgdGV4dC14cyB0ZXh0LXJpZ2h0IHRhYnVsYXItbnVtcyB0ZXh0LWdyYXktNDAwIj57dmFsdWUudG9GaXhlZCgwKX0lPC9zcGFuPgogICAgPC9kaXY+CiAgKQp9CgovLyDilIDilIAgU3lzdGVtIFN0YXRzIFBhbmVsIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAoKZnVuY3Rpb24gU3RhdHNQYW5lbCh7IHN0YXRzLCBvcGVuLCBvblRvZ2dsZSB9OiB7CiAgc3RhdHM6IFN5c3RlbVN0YXRzIHwgbnVsbDsgb3BlbjogYm9vbGVhbjsgb25Ub2dnbGU6ICgpID0+IHZvaWQKfSkgewogIGNvbnN0IGNwdUNvbG9yICA9IChzdGF0cz8uY3B1X3BjdCA/PyAwKSA+IDgwID8gJ2JnLXJlZC01MDAnIDogKHN0YXRzPy5jcHVfcGN0ID8/IDApID4gNTAgPyAnYmcteWVsbG93LTUwMCcgOiAnYmctYmx1ZS01MDAnCiAgY29uc3QgcmFtQ29sb3IgID0gKHN0YXRzPy5yYW1fcGN0ID8/IDApID4gODAgPyAnYmctcmVkLTUwMCcgOiAoc3RhdHM/LnJhbV9wY3QgPz8gMCkgPiA2MCA/ICdiZy15ZWxsb3ctNTAwJyA6ICdiZy1lbWVyYWxkLTUwMCcKCiAgcmV0dXJuICgKICAgIDxkaXYgY2xhc3NOYW1lPSJib3JkZXItYiBib3JkZXItZ3JheS04MDAgYmctZ3JheS05MDAvODAgYmFja2Ryb3AtYmx1ci1zbSI+CiAgICAgIHsvKiBUb2dnbGUgcm93ICovfQogICAgICA8YnV0dG9uCiAgICAgICAgb25DbGljaz17b25Ub2dnbGV9CiAgICAgICAgY2xhc3NOYW1lPSJ3LWZ1bGwgZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTMgcHgtNCBweS0yIGhvdmVyOmJnLWdyYXktODAwLzUwIHRyYW5zaXRpb24tY29sb3JzIHRleHQteHMgdGV4dC1ncmF5LTUwMCIKICAgICAgPgogICAgICAgIDxBY3Rpdml0eSBjbGFzc05hbWU9InctMyBoLTMiIC8+CiAgICAgICAgPHNwYW4gY2xhc3NOYW1lPSJmb250LW1lZGl1bSB0cmFja2luZy13aWRlIHVwcGVyY2FzZSI+U3lzdGVtYXVzbGFzdHVuZzwvc3Bhbj4KCiAgICAgICAgey8qIElubGluZSBzdW1tYXJ5IHdoZW4gY29sbGFwc2VkICovfQogICAgICAgIHshb3BlbiAmJiBzdGF0cyAmJiAoCiAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTMgbWwtMiB0ZXh0LWdyYXktNjAwIj4KICAgICAgICAgICAgPHNwYW4+Q1BVIHtzdGF0cy5jcHVfcGN0LnRvRml4ZWQoMCl9JTwvc3Bhbj4KICAgICAgICAgICAgPHNwYW4+UkFNIHtzdGF0cy5yYW1fcGN0LnRvRml4ZWQoMCl9JTwvc3Bhbj4KICAgICAgICAgICAge3N0YXRzLmdwdVswXSAmJiA8c3Bhbj5HUFUge3N0YXRzLmdwdVswXS51dGlsX3BjdH0lPC9zcGFuPn0KICAgICAgICAgIDwvZGl2PgogICAgICAgICl9CiAgICAgICAgPGRpdiBjbGFzc05hbWU9Im1sLWF1dG8iPgogICAgICAgICAge29wZW4gPyA8Q2hldnJvblVwIGNsYXNzTmFtZT0idy0zIGgtMyIgLz4gOiA8Q2hldnJvbkRvd24gY2xhc3NOYW1lPSJ3LTMgaC0zIiAvPn0KICAgICAgICA8L2Rpdj4KICAgICAgPC9idXR0b24+CgogICAgICB7LyogRXhwYW5kZWQgcGFuZWwgKi99CiAgICAgIHtvcGVuICYmICgKICAgICAgICA8ZGl2IGNsYXNzTmFtZT0icHgtNCBwYi0zIGdyaWQgZ3JpZC1jb2xzLTEgc206Z3JpZC1jb2xzLTMgZ2FwLTQiPgogICAgICAgICAgey8qIENQVSAqL30KICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJzcGFjZS15LTEiPgogICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTEuNSBtYi0yIj4KICAgICAgICAgICAgICA8Q3B1IGNsYXNzTmFtZT0idy0zLjUgaC0zLjUgdGV4dC1ibHVlLTQwMCIgLz4KICAgICAgICAgICAgICA8c3BhbiBjbGFzc05hbWU9InRleHQteHMgZm9udC1tZWRpdW0gdGV4dC1ncmF5LTMwMCI+Q1BVPC9zcGFuPgogICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICAgPEJhciB2YWx1ZT17c3RhdHM/LmNwdV9wY3QgPz8gMH0gY29sb3I9e2NwdUNvbG9yfSAvPgogICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0idGV4dC14cyB0ZXh0LWdyYXktNjAwIHBsLTEwIj4KICAgICAgICAgICAgICB7bmF2aWdhdG9yLmhhcmR3YXJlQ29uY3VycmVuY3l9IENvcmVzCiAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgPC9kaXY+CgogICAgICAgICAgey8qIFJBTSAqL30KICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJzcGFjZS15LTEiPgogICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTEuNSBtYi0yIj4KICAgICAgICAgICAgICA8TWVtb3J5U3RpY2sgY2xhc3NOYW1lPSJ3LTMuNSBoLTMuNSB0ZXh0LWVtZXJhbGQtNDAwIiAvPgogICAgICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGV4dC14cyBmb250LW1lZGl1bSB0ZXh0LWdyYXktMzAwIj5SQU08L3NwYW4+CiAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgICA8QmFyIHZhbHVlPXtzdGF0cz8ucmFtX3BjdCA/PyAwfSBjb2xvcj17cmFtQ29sb3J9IC8+CiAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJ0ZXh0LXhzIHRleHQtZ3JheS02MDAgcGwtMTAiPgogICAgICAgICAgICAgIHtzdGF0cz8ucmFtX3VzZWRfZ2IgPz8gMH0gLyB7c3RhdHM/LnJhbV90b3RhbF9nYiA/PyAwfSBHQgogICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgIDwvZGl2PgoKICAgICAgICAgIHsvKiBHUFUocykgKi99CiAgICAgICAgICB7KHN0YXRzPy5ncHU/Lmxlbmd0aCA/PyAwKSA+IDAgPyAoCiAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJzcGFjZS15LTIiPgogICAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMS41IG1iLTIiPgogICAgICAgICAgICAgICAgPFphcCBjbGFzc05hbWU9InctMy41IGgtMy41IHRleHQtcHVycGxlLTQwMCIgLz4KICAgICAgICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGV4dC14cyBmb250LW1lZGl1bSB0ZXh0LWdyYXktMzAwIj5HUFU8L3NwYW4+CiAgICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICAgICAge3N0YXRzIS5ncHUubWFwKGcgPT4gewogICAgICAgICAgICAgICAgY29uc3QgdnJhbVBjdCA9IGcudnJhbV90b3RhbCA+IDAgPyAoZy52cmFtX3VzZWQgLyBnLnZyYW1fdG90YWwpICogMTAwIDogMAogICAgICAgICAgICAgICAgY29uc3QgZ3B1Q29sb3IgPSBnLnV0aWxfcGN0ID4gODAgPyAnYmctcmVkLTUwMCcgOiAnYmctcHVycGxlLTUwMCcKICAgICAgICAgICAgICAgIHJldHVybiAoCiAgICAgICAgICAgICAgICAgIDxkaXYga2V5PXtnLmluZGV4fSBjbGFzc05hbWU9InNwYWNlLXktMSI+CiAgICAgICAgICAgICAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXggaXRlbXMtY2VudGVyIGp1c3RpZnktYmV0d2VlbiI+CiAgICAgICAgICAgICAgICAgICAgICA8c3BhbiBjbGFzc05hbWU9InRleHQteHMgdGV4dC1ncmF5LTUwMCB0cnVuY2F0ZSBtYXgtdy1bMTIwcHhdIj4KICAgICAgICAgICAgICAgICAgICAgICAge2cubmFtZS5yZXBsYWNlKCdOVklESUEgR2VGb3JjZSAnLCAnJykucmVwbGFjZSgnQU1EIFJhZGVvbiAnLCAnJyl9CiAgICAgICAgICAgICAgICAgICAgICA8L3NwYW4+CiAgICAgICAgICAgICAgICAgICAgICB7Zy50ZW1wX2MgJiYgKAogICAgICAgICAgICAgICAgICAgICAgICA8c3BhbiBjbGFzc05hbWU9e2B0ZXh0LXhzIGZsZXggaXRlbXMtY2VudGVyIGdhcC0wLjUgJHtnLnRlbXBfYyA+IDgwID8gJ3RleHQtcmVkLTQwMCcgOiAndGV4dC1ncmF5LTUwMCd9YH0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgPFRoZXJtb21ldGVyIGNsYXNzTmFtZT0idy0zIGgtMyIgLz57Zy50ZW1wX2N9wrBDCiAgICAgICAgICAgICAgICAgICAgICAgIDwvc3Bhbj4KICAgICAgICAgICAgICAgICAgICAgICl9CiAgICAgICAgICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICAgICAgICAgICAgPEJhciB2YWx1ZT17Zy51dGlsX3BjdH0gY29sb3I9e2dwdUNvbG9yfSBsYWJlbD0iS2VybiIgLz4KICAgICAgICAgICAgICAgICAgICA8QmFyIHZhbHVlPXt2cmFtUGN0fSBjb2xvcj0iYmctdmlvbGV0LTYwMCIgbGFiZWw9IlZSQU0iIC8+CiAgICAgICAgICAgICAgICAgICAgPGRpdiBjbGFzc05hbWU9InRleHQteHMgdGV4dC1ncmF5LTYwMCBwbC0xMCI+CiAgICAgICAgICAgICAgICAgICAgICB7KGcudnJhbV91c2VkIC8gMTAyNCkudG9GaXhlZCgxKX0gLyB7KGcudnJhbV90b3RhbCAvIDEwMjQpLnRvRml4ZWQoMSl9IEdCCiAgICAgICAgICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgICAgICAgKQogICAgICAgICAgICAgIH0pfQogICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICkgOiAoCiAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMiB0ZXh0LXhzIHRleHQtZ3JheS02MDAiPgogICAgICAgICAgICAgIDxaYXAgY2xhc3NOYW1lPSJ3LTMuNSBoLTMuNSIgLz4KICAgICAgICAgICAgICBLZWluIEdQVSBlcmthbm50IOKAkyBDUFUtTW9kdXMKICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICApfQogICAgICAgIDwvZGl2PgogICAgICApfQogICAgPC9kaXY+CiAgKQp9CgovLyDilIDilIAgSW5mZXJlbmNlIExpdmUgVGlja2VyIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAoKZnVuY3Rpb24gSW5mZXJlbmNlVGlja2VyKHsgc3RhdGUgfTogeyBzdGF0ZTogSW5mZXJlbmNlU3RhdGUgfSkgewogIGlmICghc3RhdGUuYWN0aXZlKSByZXR1cm4gbnVsbAogIHJldHVybiAoCiAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTMgcHgtNCBweS0xLjUgYmctZ3JheS05MDAvOTAgYm9yZGVyLWIgYm9yZGVyLWdyYXktODAwIHRleHQteHMiPgogICAgICA8TG9hZGVyMiBjbGFzc05hbWU9InctMyBoLTMgYW5pbWF0ZS1zcGluIHRleHQtYmx1ZS00MDAgZmxleC1zaHJpbmstMCIgLz4KICAgICAgPHNwYW4gY2xhc3NOYW1lPXtgZm9udC1tZWRpdW0gJHtQSEFTRV9DT0xPUlNbc3RhdGUucGhhc2VdfWB9PgogICAgICAgIHtQSEFTRV9MQUJFTFNbc3RhdGUucGhhc2VdfQogICAgICA8L3NwYW4+CiAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGV4dC1ncmF5LTYwMCI+e3N0YXRlLm1vZGVsLnJlcGxhY2UoJ2FpNGFsbC8nLCAnJyl9PC9zcGFuPgogICAgICB7c3RhdGUudG9rZW5zR2VuZXJhdGVkID4gMCAmJiAoCiAgICAgICAgPD4KICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGV4dC1ncmF5LTcwMCI+wrc8L3NwYW4+CiAgICAgICAgICA8c3BhbiBjbGFzc05hbWU9InRhYnVsYXItbnVtcyB0ZXh0LWdyYXktNTAwIj4KICAgICAgICAgICAge3N0YXRlLnRva2Vuc0dlbmVyYXRlZH0gVG9rZW4KICAgICAgICAgIDwvc3Bhbj4KICAgICAgICAgIHtzdGF0ZS50b2tlbnNQZXJTZWMgPiAwICYmICgKICAgICAgICAgICAgPD4KICAgICAgICAgICAgICA8c3BhbiBjbGFzc05hbWU9InRleHQtZ3JheS03MDAiPsK3PC9zcGFuPgogICAgICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGFidWxhci1udW1zIHRleHQtZW1lcmFsZC02MDAgZm9udC1tZWRpdW0iPgogICAgICAgICAgICAgICAge3N0YXRlLnRva2Vuc1BlclNlYy50b0ZpeGVkKDEpfSB0b2svcwogICAgICAgICAgICAgIDwvc3Bhbj4KICAgICAgICAgICAgPC8+CiAgICAgICAgICApfQogICAgICAgICAgPHNwYW4gY2xhc3NOYW1lPSJ0ZXh0LWdyYXktNzAwIj7Ctzwvc3Bhbj4KICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGFidWxhci1udW1zIHRleHQtZ3JheS02MDAiPgogICAgICAgICAgICB7c3RhdGUuZWxhcHNlZFNlYy50b0ZpeGVkKDEpfXMKICAgICAgICAgIDwvc3Bhbj4KICAgICAgICA8Lz4KICAgICAgKX0KICAgIDwvZGl2PgogICkKfQoKLy8g4pSA4pSAIFdlbGNvbWUgLyBUb2tlbiBNb2RhbCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKCmZ1bmN0aW9uIFdlbGNvbWVNb2RhbCh7IG9uQ2xvc2UgfTogeyBvbkNsb3NlOiAoKSA9PiB2b2lkIH0pIHsKICByZXR1cm4gKAogICAgPGRpdiBjbGFzc05hbWU9ImZpeGVkIGluc2V0LTAgYmctYmxhY2svNzAgYmFja2Ryb3AtYmx1ci1zbSB6LTUwIGZsZXggaXRlbXMtY2VudGVyIGp1c3RpZnktY2VudGVyIHAtNCI+CiAgICAgIDxkaXYgY2xhc3NOYW1lPSJiZy1ncmF5LTkwMCBib3JkZXIgYm9yZGVyLWdyYXktNzAwIHJvdW5kZWQtMnhsIHAtNiBtYXgtdy1zbSB3LWZ1bGwgc2hhZG93LTJ4bCI+CiAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXgganVzdGlmeS1iZXR3ZWVuIGl0ZW1zLXN0YXJ0IG1iLTQiPgogICAgICAgICAgPGRpdiBjbGFzc05hbWU9InctMTAgaC0xMCBiZy15ZWxsb3ctNTAwLzIwIHJvdW5kZWQteGwgZmxleCBpdGVtcy1jZW50ZXIganVzdGlmeS1jZW50ZXIiPgogICAgICAgICAgICA8R2lmdCBjbGFzc05hbWU9InctNSBoLTUgdGV4dC15ZWxsb3ctNDAwIiAvPgogICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8YnV0dG9uIG9uQ2xpY2s9e29uQ2xvc2V9IGNsYXNzTmFtZT0idGV4dC1ncmF5LTYwMCBob3Zlcjp0ZXh0LWdyYXktMzAwIHRyYW5zaXRpb24tY29sb3JzIj4KICAgICAgICAgICAgPFggY2xhc3NOYW1lPSJ3LTQgaC00IiAvPgogICAgICAgICAgPC9idXR0b24+CiAgICAgICAgPC9kaXY+CiAgICAgICAgPGgyIGNsYXNzTmFtZT0idGV4dC1sZyBmb250LXNlbWlib2xkIHRleHQtd2hpdGUgbWItMSI+V2lsbGtvbW1lbiBiZWkgQUk0QWxsITwvaDI+CiAgICAgICAgPHAgY2xhc3NOYW1lPSJ0ZXh0LXNtIHRleHQtZ3JheS00MDAgbWItNCI+CiAgICAgICAgICBBbHMgU3RhcnRlci1Cb251cyBiZWtvbW1zdCBkdSA8c3BhbiBjbGFzc05hbWU9InRleHQteWVsbG93LTQwMCBmb250LWJvbGQiPjEwIFRva2Vuczwvc3Bhbj4gZ2VzY2hlbmt0LgogICAgICAgICAgTWl0IFRva2VucyBiZXphaGxzdCBkdSBBbmZyYWdlbiDigJMgamUgbWVociBkdSB6dW0gTmV0endlcmsgYmVpdHLDpGdzdCwgZGVzdG8gbWVociB2ZXJkaWVuc3QgZHUgenVyw7xjay4KICAgICAgICA8L3A+CiAgICAgICAgPGRpdiBjbGFzc05hbWU9ImJnLWdyYXktODAwIHJvdW5kZWQteGwgcC0zIG1iLTQgZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTMiPgogICAgICAgICAgPENvaW5zIGNsYXNzTmFtZT0idy01IGgtNSB0ZXh0LXllbGxvdy00MDAgZmxleC1zaHJpbmstMCIgLz4KICAgICAgICAgIDxkaXY+CiAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJ0ZXh0LXdoaXRlIGZvbnQtYm9sZCB0ZXh0LWxnIGxlYWRpbmctbm9uZSI+KzEwIFRva2VuczwvZGl2PgogICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0idGV4dC14cyB0ZXh0LWdyYXktNTAwIG10LTAuNSI+RWlubWFsaWdlciBXaWxsa29tbWVuc2JvbnVzPC9kaXY+CiAgICAgICAgICA8L2Rpdj4KICAgICAgICA8L2Rpdj4KICAgICAgICA8YnV0dG9uCiAgICAgICAgICBvbkNsaWNrPXtvbkNsb3NlfQogICAgICAgICAgY2xhc3NOYW1lPSJ3LWZ1bGwgYmctYmx1ZS02MDAgaG92ZXI6YmctYmx1ZS01MDAgdGV4dC13aGl0ZSB0ZXh0LXNtIGZvbnQtbWVkaXVtIHB5LTIuNSByb3VuZGVkLXhsIHRyYW5zaXRpb24tY29sb3JzIgogICAgICAgID4KICAgICAgICAgIExvcyBnZWh0J3MhCiAgICAgICAgPC9idXR0b24+CiAgICAgIDwvZGl2PgogICAgPC9kaXY+CiAgKQp9CgovLyDilIDilIAgU3RhdHVzIEJhciDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIAKCmZ1bmN0aW9uIFN0YXR1c0Jhcih7IHN0YXR1cywgdG9rZW5zLCBncHUgfTogewogIHN0YXR1czogTm9kZVN0YXR1cyB8IG51bGw7IHRva2VuczogVG9rZW5CYWxhbmNlIHwgbnVsbDsgZ3B1OiBHcHVTdGF0dXMgfCBudWxsCn0pIHsKICByZXR1cm4gKAogICAgPGRpdiBjbGFzc05hbWU9ImZsZXggaXRlbXMtY2VudGVyIGdhcC00IHB4LTQgcHktMiBiZy1ncmF5LTkwMCBib3JkZXItYiBib3JkZXItZ3JheS04MDAgdGV4dC14cyB0ZXh0LWdyYXktNDAwIG92ZXJmbG93LXgtYXV0byI+CiAgICAgIDxkaXYgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMS41IGZsZXgtc2hyaW5rLTAiPgogICAgICAgIDxkaXYgY2xhc3NOYW1lPXtgdy0yIGgtMiByb3VuZGVkLWZ1bGwgJHtzdGF0dXMgPyAnYmctZ3JlZW4tNDAwIHNoYWRvdy1bMF8wXzZweF9yZ2JhKDc0LDIyMiwxMjgsMC42KV0nIDogJ2JnLXJlZC00MDAnfWB9IC8+CiAgICAgICAgPHNwYW4+e3N0YXR1cyA/ICdOb2RlIG9ubGluZScgOiAnTm9kZSBvZmZsaW5lJ308L3NwYW4+CiAgICAgIDwvZGl2PgogICAgICB7c3RhdHVzICYmICgKICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTEgZmxleC1zaHJpbmstMCI+CiAgICAgICAgICA8R2xvYmUgY2xhc3NOYW1lPSJ3LTMgaC0zIiAvPgogICAgICAgICAgPHNwYW4+e3N0YXR1cy5wZWVyX2NvdW50fSBQZWVye3N0YXR1cy5wZWVyX2NvdW50ICE9PSAxID8gJ3MnIDogJyd9PC9zcGFuPgogICAgICAgIDwvZGl2PgogICAgICApfQogICAgICB7dG9rZW5zICYmICgKICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTEgdGV4dC15ZWxsb3ctNDAwIGZsZXgtc2hyaW5rLTAiPgogICAgICAgICAgPENvaW5zIGNsYXNzTmFtZT0idy0zIGgtMyIgLz4KICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGFidWxhci1udW1zIGZvbnQtbWVkaXVtIj57dG9rZW5zLmJhbGFuY2UudG9Mb2NhbGVTdHJpbmcoKX08L3NwYW4+CiAgICAgICAgICA8c3BhbiBjbGFzc05hbWU9InRleHQteWVsbG93LTYwMCI+VG9rZW5zPC9zcGFuPgogICAgICAgIDwvZGl2PgogICAgICApfQogICAgICB7Z3B1Py5hdmFpbGFibGUgJiYgZ3B1LmRldmljZXNbMF0gJiYgKAogICAgICAgIDxkaXYgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMS41IHRleHQtcHVycGxlLTQwMCBmbGV4LXNocmluay0wIj4KICAgICAgICAgIDxaYXAgY2xhc3NOYW1lPSJ3LTMgaC0zIiAvPgogICAgICAgICAgPHNwYW4+e2dwdS5iYWNrZW5kfTwvc3Bhbj4KICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGV4dC1wdXJwbGUtNjAwIj7Ctzwvc3Bhbj4KICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGV4dC1wdXJwbGUtNTAwIj57Z3B1LmRldmljZXMubWFwKGQgPT4gZC5uYW1lLnJlcGxhY2UoL05WSURJQSBHZUZvcmNlIHxBTUQgUmFkZW9uIC9naSwgJycpKS5qb2luKCcsICcpfTwvc3Bhbj4KICAgICAgICA8L2Rpdj4KICAgICAgKX0KICAgICAgPGRpdiBjbGFzc05hbWU9Im1sLWF1dG8gdGV4dC1ncmF5LTcwMCBmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMSBmbGV4LXNocmluay0wIj4KICAgICAgICBBSTRBbGwgdjAuMS4wCiAgICAgIDwvZGl2PgogICAgPC9kaXY+CiAgKQp9CgovLyDilIDilIAgQ2hhdCBNZXNzYWdlIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAoKZnVuY3Rpb24gQ2hhdE1lc3NhZ2UoeyBtc2csIG1ldGEgfTogewogIG1zZzogTWVzc2FnZSAmIHsgbG9hZGluZz86IGJvb2xlYW4gfQogIG1ldGE/OiB7IHRva2Vuc0dlbmVyYXRlZD86IG51bWJlcjsgdG9rZW5zUGVyU2VjPzogbnVtYmVyOyBlbGFwc2VkU2VjPzogbnVtYmVyOyBtb2RlbD86IHN0cmluZyB9Cn0pIHsKICBjb25zdCBpc1VzZXIgPSBtc2cucm9sZSA9PT0gJ3VzZXInCiAgcmV0dXJuICgKICAgIDxkaXYgY2xhc3NOYW1lPXtgZmxleCBnYXAtMyAke2lzVXNlciA/ICdmbGV4LXJvdy1yZXZlcnNlJyA6ICdmbGV4LXJvdyd9IG1iLTUgZ3JvdXBgfT4KICAgICAgPGRpdiBjbGFzc05hbWU9e2BmbGV4LXNocmluay0wIHctNyBoLTcgcm91bmRlZC1mdWxsIGZsZXggaXRlbXMtY2VudGVyIGp1c3RpZnktY2VudGVyIHRleHQteHMKICAgICAgICAke2lzVXNlciA/ICdiZy1ibHVlLTYwMCcgOiAnYmctZ3JheS03MDAnfWB9PgogICAgICAgIHtpc1VzZXIgPyA8VXNlciBjbGFzc05hbWU9InctMy41IGgtMy41IiAvPiA6IDxCb3QgY2xhc3NOYW1lPSJ3LTMuNSBoLTMuNSIgLz59CiAgICAgIDwvZGl2PgogICAgICA8ZGl2IGNsYXNzTmFtZT0ibWF4LXctWzgyJV0gZmxleCBmbGV4LWNvbCBnYXAtMSI+CiAgICAgICAgPGRpdiBjbGFzc05hbWU9e2Byb3VuZGVkLTJ4bCBweC00IHB5LTMgdGV4dC1zbSBsZWFkaW5nLXJlbGF4ZWQKICAgICAgICAgICR7aXNVc2VyCiAgICAgICAgICAgID8gJ2JnLWJsdWUtNjAwIHRleHQtd2hpdGUgcm91bmRlZC10ci1zbScKICAgICAgICAgICAgOiAnYmctZ3JheS04MDAvODAgdGV4dC1ncmF5LTEwMCByb3VuZGVkLXRsLXNtIGJvcmRlciBib3JkZXItZ3JheS03MDAvNTAnfWB9PgogICAgICAgICAge21zZy5sb2FkaW5nID8gKAogICAgICAgICAgICA8c3BhbiBjbGFzc05hbWU9ImZsZXggaXRlbXMtY2VudGVyIGdhcC0yIHRleHQtZ3JheS00MDAiPgogICAgICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0iZmxleCBnYXAtMSI+CiAgICAgICAgICAgICAgICB7WzAsMSwyXS5tYXAoaSA9PiAoCiAgICAgICAgICAgICAgICAgIDxzcGFuIGtleT17aX0gY2xhc3NOYW1lPSJ3LTEuNSBoLTEuNSBiZy1ncmF5LTUwMCByb3VuZGVkLWZ1bGwgYW5pbWF0ZS1ib3VuY2UiCiAgICAgICAgICAgICAgICAgICAgc3R5bGU9e3sgYW5pbWF0aW9uRGVsYXk6IGAke2kgKiAwLjE1fXNgIH19IC8+CiAgICAgICAgICAgICAgICApKX0KICAgICAgICAgICAgICA8L3NwYW4+CiAgICAgICAgICAgICAgPHNwYW4gY2xhc3NOYW1lPSJ0ZXh0LWdyYXktNTAwIj5EZW5rdCBuYWNoIOKApjwvc3Bhbj4KICAgICAgICAgICAgPC9zcGFuPgogICAgICAgICAgKSA6IGlzVXNlciA/ICgKICAgICAgICAgICAgPHAgY2xhc3NOYW1lPSJ3aGl0ZXNwYWNlLXByZS13cmFwIj57bXNnLmNvbnRlbnR9PC9wPgogICAgICAgICAgKSA6ICgKICAgICAgICAgICAgPFJlYWN0TWFya2Rvd24KICAgICAgICAgICAgICByZW1hcmtQbHVnaW5zPXtbcmVtYXJrR2ZtXX0KICAgICAgICAgICAgICBjb21wb25lbnRzPXt7CiAgICAgICAgICAgICAgICBjb2RlKHsgY2xhc3NOYW1lLCBjaGlsZHJlbiwgLi4ucHJvcHMgfTogYW55KSB7CiAgICAgICAgICAgICAgICAgIGNvbnN0IGlubGluZSA9ICFjbGFzc05hbWUKICAgICAgICAgICAgICAgICAgcmV0dXJuIGlubGluZQogICAgICAgICAgICAgICAgICAgID8gPGNvZGUgY2xhc3NOYW1lPSJiZy1ncmF5LTkwMCBweC0xLjUgcHktMC41IHJvdW5kZWQgdGV4dC1ibHVlLTMwMCB0ZXh0LXhzIGZvbnQtbW9ubyIgey4uLnByb3BzfT57Y2hpbGRyZW59PC9jb2RlPgogICAgICAgICAgICAgICAgICAgIDogPHByZSBjbGFzc05hbWU9ImJnLWdyYXktOTUwIGJvcmRlciBib3JkZXItZ3JheS03MDAgcm91bmRlZC14bCBwLTQgb3ZlcmZsb3cteC1hdXRvIG15LTMiPgogICAgICAgICAgICAgICAgICAgICAgICA8Y29kZSBjbGFzc05hbWU9InRleHQteHMgdGV4dC1ncmF5LTIwMCBmb250LW1vbm8iPntjaGlsZHJlbn08L2NvZGU+CiAgICAgICAgICAgICAgICAgICAgICA8L3ByZT4KICAgICAgICAgICAgICAgIH0sCiAgICAgICAgICAgICAgICBwOiAoeyBjaGlsZHJlbiB9KSA9PiA8cCBjbGFzc05hbWU9Im1iLTIgbGFzdDptYi0wIj57Y2hpbGRyZW59PC9wPiwKICAgICAgICAgICAgICAgIHVsOiAoeyBjaGlsZHJlbiB9KSA9PiA8dWwgY2xhc3NOYW1lPSJsaXN0LWRpc2MgbGlzdC1pbnNpZGUgbWItMiBzcGFjZS15LTEgdGV4dC1ncmF5LTIwMCI+e2NoaWxkcmVufTwvdWw+LAogICAgICAgICAgICAgICAgb2w6ICh7IGNoaWxkcmVuIH0pID0+IDxvbCBjbGFzc05hbWU9Imxpc3QtZGVjaW1hbCBsaXN0LWluc2lkZSBtYi0yIHNwYWNlLXktMSB0ZXh0LWdyYXktMjAwIj57Y2hpbGRyZW59PC9vbD4sCiAgICAgICAgICAgICAgICBoMTogKHsgY2hpbGRyZW4gfSkgPT4gPGgxIGNsYXNzTmFtZT0idGV4dC1sZyBmb250LWJvbGQgbWItMiB0ZXh0LXdoaXRlIj57Y2hpbGRyZW59PC9oMT4sCiAgICAgICAgICAgICAgICBoMjogKHsgY2hpbGRyZW4gfSkgPT4gPGgyIGNsYXNzTmFtZT0idGV4dC1iYXNlIGZvbnQtc2VtaWJvbGQgbWItMiB0ZXh0LXdoaXRlIj57Y2hpbGRyZW59PC9oMj4sCiAgICAgICAgICAgICAgICBoMzogKHsgY2hpbGRyZW4gfSkgPT4gPGgzIGNsYXNzTmFtZT0idGV4dC1zbSBmb250LXNlbWlib2xkIG1iLTEgdGV4dC1ncmF5LTIwMCI+e2NoaWxkcmVufTwvaDM+LAogICAgICAgICAgICAgICAgYmxvY2txdW90ZTogKHsgY2hpbGRyZW4gfSkgPT4gPGJsb2NrcXVvdGUgY2xhc3NOYW1lPSJib3JkZXItbC0yIGJvcmRlci1ncmF5LTYwMCBwbC0zIHRleHQtZ3JheS00MDAgbXktMiI+e2NoaWxkcmVufTwvYmxvY2txdW90ZT4sCiAgICAgICAgICAgICAgfX0KICAgICAgICAgICAgPnttc2cuY29udGVudH08L1JlYWN0TWFya2Rvd24+CiAgICAgICAgICApfQogICAgICAgIDwvZGl2PgogICAgICAgIHsvKiBUb2tlbiBtZXRhIGJlbG93IGFzc2lzdGFudCBtZXNzYWdlcyAqL30KICAgICAgICB7IWlzVXNlciAmJiAhbXNnLmxvYWRpbmcgJiYgbWV0YSAmJiBtZXRhLnRva2Vuc0dlbmVyYXRlZCAmJiBtZXRhLnRva2Vuc0dlbmVyYXRlZCA+IDAgJiYgKAogICAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXggaXRlbXMtY2VudGVyIGdhcC0yIHB4LTEgdGV4dC14cyB0ZXh0LWdyYXktNzAwIG9wYWNpdHktMCBncm91cC1ob3ZlcjpvcGFjaXR5LTEwMCB0cmFuc2l0aW9uLW9wYWNpdHkiPgogICAgICAgICAgICA8c3Bhbj57bWV0YS50b2tlbnNHZW5lcmF0ZWR9IFRva2Vuczwvc3Bhbj4KICAgICAgICAgICAge21ldGEudG9rZW5zUGVyU2VjICYmIG1ldGEudG9rZW5zUGVyU2VjID4gMCAmJiAoCiAgICAgICAgICAgICAgPD48c3Bhbj7Ctzwvc3Bhbj48c3BhbiBjbGFzc05hbWU9InRleHQtZ3JheS02MDAiPnttZXRhLnRva2Vuc1BlclNlYy50b0ZpeGVkKDEpfSB0b2svczwvc3Bhbj48Lz4KICAgICAgICAgICAgKX0KICAgICAgICAgICAge21ldGEuZWxhcHNlZFNlYyAmJiAoCiAgICAgICAgICAgICAgPD48c3Bhbj7Ctzwvc3Bhbj48c3Bhbj57bWV0YS5lbGFwc2VkU2VjLnRvRml4ZWQoMSl9czwvc3Bhbj48Lz4KICAgICAgICAgICAgKX0KICAgICAgICAgICAge21ldGEubW9kZWwgJiYgKAogICAgICAgICAgICAgIDw+PHNwYW4+wrc8L3NwYW4+PHNwYW4gY2xhc3NOYW1lPSJ0ZXh0LWdyYXktNzAwIj57bWV0YS5tb2RlbC5yZXBsYWNlKCdhaTRhbGwvJywgJycpfTwvc3Bhbj48Lz4KICAgICAgICAgICAgKX0KICAgICAgICAgIDwvZGl2PgogICAgICAgICl9CiAgICAgIDwvZGl2PgogICAgPC9kaXY+CiAgKQp9CgovLyDilIDilIAgTW9kZWwgU2VsZWN0b3Ig4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSA4pSACgpmdW5jdGlvbiBNb2RlbFNlbGVjdG9yKHsgbW9kZWxzLCBzZWxlY3RlZCwgb25TZWxlY3QgfTogewogIG1vZGVsczogTW9kZWxbXTsgc2VsZWN0ZWQ6IHN0cmluZzsgb25TZWxlY3Q6IChpZDogc3RyaW5nKSA9PiB2b2lkCn0pIHsKICBjb25zdCBbb3Blbiwgc2V0T3Blbl0gPSB1c2VTdGF0ZShmYWxzZSkKICBjb25zdCBjdXJyZW50ID0gbW9kZWxzLmZpbmQobSA9PiBtLmlkID09PSBzZWxlY3RlZCkKICBjb25zdCByZWYgPSB1c2VSZWY8SFRNTERpdkVsZW1lbnQ+KG51bGwpCgogIHVzZUVmZmVjdCgoKSA9PiB7CiAgICBjb25zdCBoYW5kbGVyID0gKGU6IE1vdXNlRXZlbnQpID0+IHsgaWYgKHJlZi5jdXJyZW50ICYmICFyZWYuY3VycmVudC5jb250YWlucyhlLnRhcmdldCBhcyBOb2RlKSkgc2V0T3BlbihmYWxzZSkgfQogICAgZG9jdW1lbnQuYWRkRXZlbnRMaXN0ZW5lcignbW91c2Vkb3duJywgaGFuZGxlcikKICAgIHJldHVybiAoKSA9PiBkb2N1bWVudC5yZW1vdmVFdmVudExpc3RlbmVyKCdtb3VzZWRvd24nLCBoYW5kbGVyKQogIH0sIFtdKQoKICByZXR1cm4gKAogICAgPGRpdiBjbGFzc05hbWU9InJlbGF0aXZlIiByZWY9e3JlZn0+CiAgICAgIDxidXR0b24gb25DbGljaz17KCkgPT4gc2V0T3Blbighb3Blbil9CiAgICAgICAgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMiBiZy1ncmF5LTgwMCBob3ZlcjpiZy1ncmF5LTcwMCBib3JkZXIgYm9yZGVyLWdyYXktNzAwIHJvdW5kZWQteGwgcHgtMyBweS0yIHRleHQtc20gdHJhbnNpdGlvbi1jb2xvcnMiPgogICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGV4dC1ncmF5LTQwMCI+e0NBVEVHT1JZX0lDT05TW2N1cnJlbnQ/LmNhdGVnb3J5ID8/ICdnZW5lcmFsJ119PC9zcGFuPgogICAgICAgIDxzcGFuIGNsYXNzTmFtZT0ibWF4LXctWzE0MHB4XSB0cnVuY2F0ZSB0ZXh0LWdyYXktMjAwIj57Y3VycmVudD8uaWQ/LnJlcGxhY2UoJ2FpNGFsbC8nLCAnJykgPz8gc2VsZWN0ZWR9PC9zcGFuPgogICAgICAgIDxDaGV2cm9uRG93biBjbGFzc05hbWU9e2B3LTMgaC0zIHRleHQtZ3JheS01MDAgdHJhbnNpdGlvbi10cmFuc2Zvcm0gJHtvcGVuID8gJ3JvdGF0ZS0xODAnIDogJyd9YH0gLz4KICAgICAgPC9idXR0b24+CiAgICAgIHtvcGVuICYmICgKICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iYWJzb2x1dGUgdG9wLWZ1bGwgbGVmdC0wIG10LTEgdy03MiBiZy1ncmF5LTg1MCBiZy1ncmF5LTkwMCBib3JkZXIgYm9yZGVyLWdyYXktNzAwIHJvdW5kZWQteGwgc2hhZG93LTJ4bCB6LTUwIG92ZXJmbG93LWhpZGRlbiI+CiAgICAgICAgICB7WydnZW5lcmFsJywgJ2NvZGUnLCAndmlzaW9uJ10ubWFwKGNhdCA9PiB7CiAgICAgICAgICAgIGNvbnN0IGNhdE1vZGVscyA9IG1vZGVscy5maWx0ZXIobSA9PiBtLmNhdGVnb3J5ID09PSBjYXQpCiAgICAgICAgICAgIGlmICghY2F0TW9kZWxzLmxlbmd0aCkgcmV0dXJuIG51bGwKICAgICAgICAgICAgcmV0dXJuICgKICAgICAgICAgICAgICA8ZGl2IGtleT17Y2F0fT4KICAgICAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJweC0zIHB5LTEuNSB0ZXh0LXhzIHRleHQtZ3JheS02MDAgdXBwZXJjYXNlIHRyYWNraW5nLXdpZGVzdCBib3JkZXItYiBib3JkZXItZ3JheS04MDAgYmctZ3JheS05MDAvNTAiPgogICAgICAgICAgICAgICAgICB7Y2F0ID09PSAnZ2VuZXJhbCcgPyAnQWxsZ2VtZWluJyA6IGNhdCA9PT0gJ2NvZGUnID8gJ0NvZGUnIDogJ1Zpc2lvbid9CiAgICAgICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICAgICAgIHtjYXRNb2RlbHMubWFwKG0gPT4gKAogICAgICAgICAgICAgICAgICA8YnV0dG9uIGtleT17bS5pZH0gb25DbGljaz17KCkgPT4geyBvblNlbGVjdChtLmlkKTsgc2V0T3BlbihmYWxzZSkgfX0KICAgICAgICAgICAgICAgICAgICBjbGFzc05hbWU9e2B3LWZ1bGwgdGV4dC1sZWZ0IHB4LTMgcHktMi41IGhvdmVyOmJnLWdyYXktODAwIHRyYW5zaXRpb24tY29sb3JzIGZsZXggaXRlbXMtY2VudGVyIGdhcC0zCiAgICAgICAgICAgICAgICAgICAgICAke3NlbGVjdGVkID09PSBtLmlkID8gJ2JnLWdyYXktODAwLzYwJyA6ICcnfWB9PgogICAgICAgICAgICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idGV4dC1ncmF5LTUwMCI+e0NBVEVHT1JZX0lDT05TW2NhdF19PC9zcGFuPgogICAgICAgICAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJtaW4tdy0wIj4KICAgICAgICAgICAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJ0ZXh0LXNtIHRleHQtZ3JheS0xMDAgZm9udC1tZWRpdW0iPnttLmlkLnJlcGxhY2UoJ2FpNGFsbC8nLCAnJyl9PC9kaXY+CiAgICAgICAgICAgICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0idGV4dC14cyB0ZXh0LWdyYXktNjAwIHRydW5jYXRlIj57bS5kZXNjcmlwdGlvbn08L2Rpdj4KICAgICAgICAgICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICAgICAgICAgICB7c2VsZWN0ZWQgPT09IG0uaWQgJiYgPGRpdiBjbGFzc05hbWU9Im1sLWF1dG8gdy0xLjUgaC0xLjUgcm91bmRlZC1mdWxsIGJnLWJsdWUtNTAwIGZsZXgtc2hyaW5rLTAiIC8+fQogICAgICAgICAgICAgICAgICA8L2J1dHRvbj4KICAgICAgICAgICAgICAgICkpfQogICAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgICApCiAgICAgICAgICB9KX0KICAgICAgICA8L2Rpdj4KICAgICAgKX0KICAgIDwvZGl2PgogICkKfQoKLy8g4pSA4pSAIE1haW4gQXBwIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgAoKdHlwZSBNc2dXaXRoTWV0YSA9IE1lc3NhZ2UgJiB7CiAgbG9hZGluZz86IGJvb2xlYW4KICBtZXRhPzogeyB0b2tlbnNHZW5lcmF0ZWQ6IG51bWJlcjsgdG9rZW5zUGVyU2VjOiBudW1iZXI7IGVsYXBzZWRTZWM6IG51bWJlcjsgbW9kZWw6IHN0cmluZyB9Cn0KCmV4cG9ydCBkZWZhdWx0IGZ1bmN0aW9uIEFwcCgpIHsKICBjb25zdCBbbW9kZWxzLCAgICBzZXRNb2RlbHNdICAgPSB1c2VTdGF0ZTxNb2RlbFtdPihbXSkKICBjb25zdCBbbW9kZWwsICAgICBzZXRNb2RlbF0gICAgPSB1c2VTdGF0ZSgnYWk0YWxsL2xsYW1hMycpCiAgY29uc3QgW21lc3NhZ2VzLCAgc2V0TWVzc2FnZXNdID0gdXNlU3RhdGU8TXNnV2l0aE1ldGFbXT4oW10pCiAgY29uc3QgW2lucHV0LCAgICAgc2V0SW5wdXRdICAgID0gdXNlU3RhdGUoJycpCiAgY29uc3QgW3N0cmVhbWluZywgc2V0U3RyZWFtaW5nXSA9IHVzZVN0YXRlKGZhbHNlKQogIGNvbnN0IFtzdGF0dXMsICAgIHNldFN0YXR1c10gICA9IHVzZVN0YXRlPE5vZGVTdGF0dXMgfCBudWxsPihudWxsKQogIGNvbnN0IFt0b2tlbnMsICAgIHNldFRva2Vuc10gICA9IHVzZVN0YXRlPFRva2VuQmFsYW5jZSB8IG51bGw+KG51bGwpCiAgY29uc3QgW2dwdSwgICAgICAgc2V0R3B1XSAgICAgID0gdXNlU3RhdGU8R3B1U3RhdHVzIHwgbnVsbD4obnVsbCkKICBjb25zdCBbc3RhdHMsICAgICBzZXRTdGF0c10gICAgPSB1c2VTdGF0ZTxTeXN0ZW1TdGF0cyB8IG51bGw+KG51bGwpCiAgY29uc3QgW3N0YXRzT3Blbiwgc2V0U3RhdHNPcGVuXSA9IHVzZVN0YXRlKGZhbHNlKQogIGNvbnN0IFt0ZW1wLCAgICAgIHNldFRlbXBdICAgICA9IHVzZVN0YXRlKDAuNykKICBjb25zdCBbc2hvd1dlbGNvbWUsIHNldFNob3dXZWxjb21lXSA9IHVzZVN0YXRlKGZhbHNlKQogIGNvbnN0IFtpbmZlcmVuY2UsIHNldEluZmVyZW5jZV0gPSB1c2VTdGF0ZTxJbmZlcmVuY2VTdGF0ZT4oewogICAgYWN0aXZlOiBmYWxzZSwgbW9kZWw6ICcnLCB0b2tlbnNHZW5lcmF0ZWQ6IDAsIHRva2Vuc1BlclNlYzogMCwgZWxhcHNlZFNlYzogMCwgcGhhc2U6ICdsb2FkaW5nJwogIH0pCgogIGNvbnN0IGJvdHRvbVJlZiAgID0gdXNlUmVmPEhUTUxEaXZFbGVtZW50PihudWxsKQogIGNvbnN0IHRleHRhcmVhUmVmID0gdXNlUmVmPEhUTUxUZXh0QXJlYUVsZW1lbnQ+KG51bGwpCiAgY29uc3Qgc3RhcnRUaW1lUmVmID0gdXNlUmVmPG51bWJlcj4oMCkKICBjb25zdCB0b2tlbkNvdW50UmVmID0gdXNlUmVmPG51bWJlcj4oMCkKCiAgLy8gSW5pdGlhbCBzZXR1cAogIHVzZUVmZmVjdCgoKSA9PiB7CiAgICBmZXRjaE1vZGVscygpLnRoZW4obXMgPT4geyBzZXRNb2RlbHMobXMpOyBpZiAobXMubGVuZ3RoKSBzZXRNb2RlbChtc1swXS5pZCkgfSkuY2F0Y2goKCkgPT4ge30pCiAgICByZWZyZXNoU3RhdHVzKCkKICAgIGNvbnN0IGl2ID0gc2V0SW50ZXJ2YWwocmVmcmVzaFN0YXR1cywgMTVfMDAwKQoKICAgIC8vIFN0YXJ0ZXIgdG9rZW5zIGZvciBuZXcgc2Vzc2lvbnMKICAgIGNvbnN0IHNlc3Npb25JZCA9IGdldFNlc3Npb25JZCgpCiAgICBjb25zdCBhbHJlYWR5Q2xhaW1lZCA9IGxvY2FsU3RvcmFnZS5nZXRJdGVtKCdhaTRhbGxfdG9rZW5zX2NsYWltZWQnKQogICAgaWYgKCFhbHJlYWR5Q2xhaW1lZCkgewogICAgICBjbGFpbVN0YXJ0ZXJUb2tlbnMoc2Vzc2lvbklkKS50aGVuKHJlcyA9PiB7CiAgICAgICAgaWYgKHJlcy5ncmFudGVkKSB7CiAgICAgICAgICBsb2NhbFN0b3JhZ2Uuc2V0SXRlbSgnYWk0YWxsX3Rva2Vuc19jbGFpbWVkJywgJzEnKQogICAgICAgICAgc2V0U2hvd1dlbGNvbWUodHJ1ZSkKICAgICAgICAgIHNldFRpbWVvdXQocmVmcmVzaFN0YXR1cywgNTAwKSAvLyByZWZyZXNoIGJhbGFuY2UgYWZ0ZXIgZ3JhbnQKICAgICAgICB9CiAgICAgIH0pLmNhdGNoKCgpID0+IHt9KQogICAgfQoKICAgIHJldHVybiAoKSA9PiBjbGVhckludGVydmFsKGl2KQogIH0sIFtdKQoKICAvLyBTeXN0ZW0gc3RhdHMgcG9sbGluZyAobW9yZSBmcmVxdWVudCB3aGVuIHN0YXRzIHBhbmVsIG9wZW4pCiAgdXNlRWZmZWN0KCgpID0+IHsKICAgIGNvbnN0IHBvbGwgPSAoKSA9PiBmZXRjaFN5c3RlbVN0YXRzKCkudGhlbihzZXRTdGF0cykuY2F0Y2goKCkgPT4ge30pCiAgICBwb2xsKCkKICAgIGNvbnN0IGl2ID0gc2V0SW50ZXJ2YWwocG9sbCwgc3RhdHNPcGVuID8gMjAwMCA6IDgwMDApCiAgICByZXR1cm4gKCkgPT4gY2xlYXJJbnRlcnZhbChpdikKICB9LCBbc3RhdHNPcGVuXSkKCiAgY29uc3QgcmVmcmVzaFN0YXR1cyA9ICgpID0+IHsKICAgIGZldGNoTm9kZVN0YXR1cygpLnRoZW4oc2V0U3RhdHVzKS5jYXRjaCgoKSA9PiBzZXRTdGF0dXMobnVsbCkpCiAgICBmZXRjaFRva2VuQmFsYW5jZSgpLnRoZW4oc2V0VG9rZW5zKS5jYXRjaCgoKSA9PiB7fSkKICAgIGZldGNoR3B1U3RhdHVzKCkudGhlbihzZXRHcHUpLmNhdGNoKCgpID0+IHt9KQogIH0KCiAgdXNlRWZmZWN0KCgpID0+IHsKICAgIGJvdHRvbVJlZi5jdXJyZW50Py5zY3JvbGxJbnRvVmlldyh7IGJlaGF2aW9yOiAnc21vb3RoJyB9KQogIH0sIFttZXNzYWdlc10pCgogIC8vIExpdmUgZWxhcHNlZC10aW1lIHRpY2tlciBkdXJpbmcgc3RyZWFtaW5nCiAgdXNlRWZmZWN0KCgpID0+IHsKICAgIGlmICghc3RyZWFtaW5nKSByZXR1cm4KICAgIGNvbnN0IGl2ID0gc2V0SW50ZXJ2YWwoKCkgPT4gewogICAgICBzZXRJbmZlcmVuY2UocHJldiA9PiB7CiAgICAgICAgaWYgKCFwcmV2LmFjdGl2ZSkgcmV0dXJuIHByZXYKICAgICAgICBjb25zdCBlbGFwc2VkID0gKERhdGUubm93KCkgLSBzdGFydFRpbWVSZWYuY3VycmVudCkgLyAxMDAwCiAgICAgICAgY29uc3QgdHBzID0gZWxhcHNlZCA+IDAgPyB0b2tlbkNvdW50UmVmLmN1cnJlbnQgLyBlbGFwc2VkIDogMAogICAgICAgIHJldHVybiB7IC4uLnByZXYsIGVsYXBzZWRTZWM6IGVsYXBzZWQsIHRva2Vuc1BlclNlYzogdHBzIH0KICAgICAgfSkKICAgIH0sIDIwMCkKICAgIHJldHVybiAoKSA9PiBjbGVhckludGVydmFsKGl2KQogIH0sIFtzdHJlYW1pbmddKQoKICBjb25zdCBzZW5kTWVzc2FnZSA9IHVzZUNhbGxiYWNrKGFzeW5jICgpID0+IHsKICAgIGNvbnN0IHRleHQgPSBpbnB1dC50cmltKCkKICAgIGlmICghdGV4dCB8fCBzdHJlYW1pbmcpIHJldHVybgoKICAgIGNvbnN0IHVzZXJNc2c6IE1zZ1dpdGhNZXRhID0geyByb2xlOiAndXNlcicsIGNvbnRlbnQ6IHRleHQgfQogICAgY29uc3QgcGxhY2Vob2xkZXI6IE1zZ1dpdGhNZXRhID0geyByb2xlOiAnYXNzaXN0YW50JywgY29udGVudDogJycsIGxvYWRpbmc6IHRydWUgfQoKICAgIHNldE1lc3NhZ2VzKHByZXYgPT4gWy4uLnByZXYsIHVzZXJNc2csIHBsYWNlaG9sZGVyXSkKICAgIHNldElucHV0KCcnKQogICAgc2V0U3RyZWFtaW5nKHRydWUpCiAgICBzdGFydFRpbWVSZWYuY3VycmVudCA9IERhdGUubm93KCkKICAgIHRva2VuQ291bnRSZWYuY3VycmVudCA9IDAKCiAgICBzZXRJbmZlcmVuY2UoeyBhY3RpdmU6IHRydWUsIG1vZGVsLCB0b2tlbnNHZW5lcmF0ZWQ6IDAsIHRva2Vuc1BlclNlYzogMCwgZWxhcHNlZFNlYzogMCwgcGhhc2U6ICdsb2FkaW5nJyB9KQoKICAgIGNvbnN0IGhpc3Rvcnk6IE1lc3NhZ2VbXSA9IFsuLi5tZXNzYWdlcywgdXNlck1zZ10KICAgIGxldCBmdWxsQ29udGVudCA9ICcnCiAgICBsZXQgZmlyc3RUb2tlbiA9IHRydWUKCiAgICB0cnkgewogICAgICBmb3IgYXdhaXQgKGNvbnN0IHRva2VuIG9mIHN0cmVhbUNoYXQobW9kZWwsIGhpc3RvcnksIHRlbXApKSB7CiAgICAgICAgZnVsbENvbnRlbnQgKz0gdG9rZW4KICAgICAgICB0b2tlbkNvdW50UmVmLmN1cnJlbnQrKwoKICAgICAgICBpZiAoZmlyc3RUb2tlbikgewogICAgICAgICAgZmlyc3RUb2tlbiA9IGZhbHNlCiAgICAgICAgICBzZXRJbmZlcmVuY2UocHJldiA9PiAoeyAuLi5wcmV2LCBwaGFzZTogJ2dlbmVyYXRpbmcnIH0pKQogICAgICAgIH0KCiAgICAgICAgY29uc3QgZWxhcHNlZCA9IChEYXRlLm5vdygpIC0gc3RhcnRUaW1lUmVmLmN1cnJlbnQpIC8gMTAwMAogICAgICAgIGNvbnN0IHRwcyA9IGVsYXBzZWQgPiAwID8gdG9rZW5Db3VudFJlZi5jdXJyZW50IC8gZWxhcHNlZCA6IDAKCiAgICAgICAgc2V0SW5mZXJlbmNlKHByZXYgPT4gKHsKICAgICAgICAgIC4uLnByZXYsCiAgICAgICAgICBhY3RpdmU6IHRydWUsCiAgICAgICAgICB0b2tlbnNHZW5lcmF0ZWQ6IHRva2VuQ291bnRSZWYuY3VycmVudCwKICAgICAgICAgIHRva2Vuc1BlclNlYzogdHBzLAogICAgICAgICAgZWxhcHNlZFNlYzogZWxhcHNlZCwKICAgICAgICAgIHBoYXNlOiB0b2tlbkNvdW50UmVmLmN1cnJlbnQgPCAzID8gJ3RoaW5raW5nJyA6ICdnZW5lcmF0aW5nJywKICAgICAgICB9KSkKCiAgICAgICAgc2V0TWVzc2FnZXMocHJldiA9PiB7CiAgICAgICAgICBjb25zdCBuZXh0ID0gWy4uLnByZXZdCiAgICAgICAgICBuZXh0W25leHQubGVuZ3RoIC0gMV0gPSB7IHJvbGU6ICdhc3Npc3RhbnQnLCBjb250ZW50OiBmdWxsQ29udGVudCwgbG9hZGluZzogZmFsc2UgfQogICAgICAgICAgcmV0dXJuIG5leHQKICAgICAgICB9KQogICAgICB9CgogICAgICAvLyBGaW5hbGl6ZSB3aXRoIG1ldGEgc3RhdHMKICAgICAgY29uc3QgZWxhcHNlZCA9IChEYXRlLm5vdygpIC0gc3RhcnRUaW1lUmVmLmN1cnJlbnQpIC8gMTAwMAogICAgICBjb25zdCB0cHMgPSBlbGFwc2VkID4gMCA/IHRva2VuQ291bnRSZWYuY3VycmVudCAvIGVsYXBzZWQgOiAwCgogICAgICBzZXRNZXNzYWdlcyhwcmV2ID0+IHsKICAgICAgICBjb25zdCBuZXh0ID0gWy4uLnByZXZdCiAgICAgICAgbmV4dFtuZXh0Lmxlbmd0aCAtIDFdID0gewogICAgICAgICAgcm9sZTogJ2Fzc2lzdGFudCcsCiAgICAgICAgICBjb250ZW50OiBmdWxsQ29udGVudCwKICAgICAgICAgIGxvYWRpbmc6IGZhbHNlLAogICAgICAgICAgbWV0YTogeyB0b2tlbnNHZW5lcmF0ZWQ6IHRva2VuQ291bnRSZWYuY3VycmVudCwgdG9rZW5zUGVyU2VjOiB0cHMsIGVsYXBzZWRTZWM6IGVsYXBzZWQsIG1vZGVsIH0sCiAgICAgICAgfQogICAgICAgIHJldHVybiBuZXh0CiAgICAgIH0pCgogICAgfSBjYXRjaCAoZXJyOiBhbnkpIHsKICAgICAgc2V0TWVzc2FnZXMocHJldiA9PiB7CiAgICAgICAgY29uc3QgbmV4dCA9IFsuLi5wcmV2XQogICAgICAgIG5leHRbbmV4dC5sZW5ndGggLSAxXSA9IHsKICAgICAgICAgIHJvbGU6ICdhc3Npc3RhbnQnLAogICAgICAgICAgY29udGVudDogYOKdjCAqKkZlaGxlcjoqKiAke2Vyci5tZXNzYWdlfVxuXG5TdGVsbGUgc2ljaGVyLCBkYXNzIE9sbGFtYSBsw6R1ZnQ6IFxgb2xsYW1hIHNlcnZlXGBgLAogICAgICAgICAgbG9hZGluZzogZmFsc2UsCiAgICAgICAgfQogICAgICAgIHJldHVybiBuZXh0CiAgICAgIH0pCiAgICB9IGZpbmFsbHkgewogICAgICBzZXRTdHJlYW1pbmcoZmFsc2UpCiAgICAgIHNldEluZmVyZW5jZShwcmV2ID0+ICh7IC4uLnByZXYsIGFjdGl2ZTogZmFsc2UgfSkpCiAgICAgIHRleHRhcmVhUmVmLmN1cnJlbnQ/LmZvY3VzKCkKICAgICAgc2V0VGltZW91dChyZWZyZXNoU3RhdHVzLCAxMDAwKQogICAgfQogIH0sIFtpbnB1dCwgbWVzc2FnZXMsIG1vZGVsLCBzdHJlYW1pbmcsIHRlbXBdKQoKICBjb25zdCBoYW5kbGVLZXlEb3duID0gKGU6IFJlYWN0LktleWJvYXJkRXZlbnQpID0+IHsKICAgIGlmIChlLmtleSA9PT0gJ0VudGVyJyAmJiAhZS5zaGlmdEtleSkgeyBlLnByZXZlbnREZWZhdWx0KCk7IHNlbmRNZXNzYWdlKCkgfQogIH0KCiAgcmV0dXJuICgKICAgIDxkaXYgY2xhc3NOYW1lPSJmbGV4IGZsZXgtY29sIGgtc2NyZWVuIGJnLWdyYXktOTUwIj4KICAgICAge3Nob3dXZWxjb21lICYmIDxXZWxjb21lTW9kYWwgb25DbG9zZT17KCkgPT4gc2V0U2hvd1dlbGNvbWUoZmFsc2UpfSAvPn0KCiAgICAgIHsvKiBIZWFkZXIgKi99CiAgICAgIDxoZWFkZXIgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBqdXN0aWZ5LWJldHdlZW4gcHgtNSBweS0zIGJnLWdyYXktOTAwIGJvcmRlci1iIGJvcmRlci1ncmF5LTgwMCI+CiAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXggaXRlbXMtY2VudGVyIGdhcC0zIj4KICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJ3LTggaC04IGJnLWdyYWRpZW50LXRvLWJyIGZyb20tYmx1ZS01MDAgdG8tYmx1ZS03MDAgcm91bmRlZC14bCBmbGV4IGl0ZW1zLWNlbnRlciBqdXN0aWZ5LWNlbnRlciBmb250LWJvbGQgdGV4dC1zbSBzaGFkb3ctbGciPgogICAgICAgICAgICBBCiAgICAgICAgICA8L2Rpdj4KICAgICAgICAgIDxkaXY+CiAgICAgICAgICAgIDxoMSBjbGFzc05hbWU9ImZvbnQtc2VtaWJvbGQgdGV4dC13aGl0ZSB0cmFja2luZy10aWdodCI+QUk0QWxsPC9oMT4KICAgICAgICAgICAgPHAgY2xhc3NOYW1lPSJ0ZXh0LXhzIHRleHQtZ3JheS01MDAiPkRlY2VudHJhbGl6ZWQgQUkgZm9yIEV2ZXJ5b25lPC9wPgogICAgICAgICAgPC9kaXY+CiAgICAgICAgPC9kaXY+CiAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXggaXRlbXMtY2VudGVyIGdhcC0yIj4KICAgICAgICAgIDxidXR0b24gb25DbGljaz17cmVmcmVzaFN0YXR1c30KICAgICAgICAgICAgY2xhc3NOYW1lPSJwLTIgaG92ZXI6YmctZ3JheS04MDAgcm91bmRlZC1sZyB0cmFuc2l0aW9uLWNvbG9ycyB0ZXh0LWdyYXktNTAwIGhvdmVyOnRleHQtZ3JheS0zMDAiIHRpdGxlPSJTdGF0dXMgYWt0dWFsaXNpZXJlbiI+CiAgICAgICAgICAgIDxSZWZyZXNoQ3cgY2xhc3NOYW1lPSJ3LTMuNSBoLTMuNSIgLz4KICAgICAgICAgIDwvYnV0dG9uPgogICAgICAgICAgPGJ1dHRvbiBvbkNsaWNrPXsoKSA9PiBzZXRNZXNzYWdlcyhbXSl9CiAgICAgICAgICAgIGNsYXNzTmFtZT0icHgtMyBweS0xLjUgdGV4dC14cyB0ZXh0LWdyYXktNTAwIGhvdmVyOnRleHQtZ3JheS0yMDAgaG92ZXI6YmctZ3JheS04MDAgcm91bmRlZC1sZyB0cmFuc2l0aW9uLWNvbG9ycyBib3JkZXIgYm9yZGVyLWdyYXktODAwIj4KICAgICAgICAgICAgTmV1ZXIgQ2hhdAogICAgICAgICAgPC9idXR0b24+CiAgICAgICAgPC9kaXY+CiAgICAgIDwvaGVhZGVyPgoKICAgICAgPFN0YXR1c0JhciBzdGF0dXM9e3N0YXR1c30gdG9rZW5zPXt0b2tlbnN9IGdwdT17Z3B1fSAvPgogICAgICA8U3RhdHNQYW5lbCBzdGF0cz17c3RhdHN9IG9wZW49e3N0YXRzT3Blbn0gb25Ub2dnbGU9eygpID0+IHNldFN0YXRzT3BlbihvID0+ICFvKX0gLz4KICAgICAgPEluZmVyZW5jZVRpY2tlciBzdGF0ZT17aW5mZXJlbmNlfSAvPgoKICAgICAgey8qIE1lc3NhZ2VzICovfQogICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleC0xIG92ZXJmbG93LXktYXV0byBweC00IHB5LTYiPgogICAgICAgIDxkaXYgY2xhc3NOYW1lPSJtYXgtdy0zeGwgbXgtYXV0byI+CiAgICAgICAgICB7bWVzc2FnZXMubGVuZ3RoID09PSAwICYmICgKICAgICAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXggZmxleC1jb2wgaXRlbXMtY2VudGVyIGp1c3RpZnktY2VudGVyIGgtZnVsbCBtaW4taC1bMzgwcHhdIHRleHQtY2VudGVyIj4KICAgICAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0idy0xNCBoLTE0IGJnLWJsdWUtNjAwLzE1IGJvcmRlciBib3JkZXItYmx1ZS01MDAvMjAgcm91bmRlZC0yeGwgZmxleCBpdGVtcy1jZW50ZXIganVzdGlmeS1jZW50ZXIgbWItNCI+CiAgICAgICAgICAgICAgICA8Qm90IGNsYXNzTmFtZT0idy03IGgtNyB0ZXh0LWJsdWUtNDAwIiAvPgogICAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgICAgIDxoMiBjbGFzc05hbWU9InRleHQteGwgZm9udC1zZW1pYm9sZCB0ZXh0LXdoaXRlIG1iLTIiPldpZSBrYW5uIGljaCBoZWxmZW4/PC9oMj4KICAgICAgICAgICAgICA8cCBjbGFzc05hbWU9InRleHQtZ3JheS01MDAgdGV4dC1zbSBtYXgtdy14cyBtYi02Ij4KICAgICAgICAgICAgICAgIEFJNEFsbCB2ZXJ0ZWlsdCBLSS1Nb2RlbGxlIMO8YmVyIGVpbiBkZXplbnRyYWxlcyBOZXR6d2Vyay4gV8OkaGxlIGVpbiBNb2RlbGwgdW5kIHN0YXJ0ZS4KICAgICAgICAgICAgICA8L3A+CiAgICAgICAgICAgICAgPGRpdiBjbGFzc05hbWU9ImdyaWQgZ3JpZC1jb2xzLTIgZ2FwLTIgbWF4LXctc20gdy1mdWxsIj4KICAgICAgICAgICAgICAgIHtbCiAgICAgICAgICAgICAgICAgIFsn4pyN77iPJywgJ1B5dGhvbi1GdW5rdGlvbiB6dW0gSlNPTi1QYXJzZW4gc2NocmVpYmVuJ10sCiAgICAgICAgICAgICAgICAgIFsn8J+UrCcsICdRdWFudGVudmVyc2NocsOkbmt1bmcgZWluZmFjaCBlcmtsw6RyZW4nXSwKICAgICAgICAgICAgICAgICAgWyfwn5KhJywgJ1NpZGUtUHJvamVjdC1JZGVlbiBnZW5lcmllcmVuJ10sCiAgICAgICAgICAgICAgICAgIFsn8J+boO+4jycsICdEb2NrZXIgQ29tcG9zZSBEYXRlaSBvcHRpbWllcmVuJ10sCiAgICAgICAgICAgICAgICBdLm1hcCgoW2Vtb2ppLCB0ZXh0XSkgPT4gKAogICAgICAgICAgICAgICAgICA8YnV0dG9uIGtleT17dGV4dH0gb25DbGljaz17KCkgPT4gc2V0SW5wdXQodGV4dCl9CiAgICAgICAgICAgICAgICAgICAgY2xhc3NOYW1lPSJ0ZXh0LWxlZnQgcHgtMyBweS0yLjUgYmctZ3JheS05MDAgaG92ZXI6YmctZ3JheS04MDAgcm91bmRlZC14bAogICAgICAgICAgICAgICAgICAgICAgdGV4dC14cyB0ZXh0LWdyYXktNDAwIGhvdmVyOnRleHQtZ3JheS0yMDAgdHJhbnNpdGlvbi1jb2xvcnMgYm9yZGVyIGJvcmRlci1ncmF5LTgwMCBob3Zlcjpib3JkZXItZ3JheS03MDAiPgogICAgICAgICAgICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0ibXItMS41Ij57ZW1vaml9PC9zcGFuPnt0ZXh0fQogICAgICAgICAgICAgICAgICA8L2J1dHRvbj4KICAgICAgICAgICAgICAgICkpfQogICAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgICl9CiAgICAgICAgICB7bWVzc2FnZXMubWFwKChtc2csIGkpID0+ICgKICAgICAgICAgICAgPENoYXRNZXNzYWdlIGtleT17aX0gbXNnPXttc2d9IG1ldGE9e21zZy5tZXRhfSAvPgogICAgICAgICAgKSl9CiAgICAgICAgICA8ZGl2IHJlZj17Ym90dG9tUmVmfSAvPgogICAgICAgIDwvZGl2PgogICAgICA8L2Rpdj4KCiAgICAgIHsvKiBJbnB1dCAqL30KICAgICAgPGRpdiBjbGFzc05hbWU9ImJvcmRlci10IGJvcmRlci1ncmF5LTgwMCBiZy1ncmF5LTkwMC85NSBiYWNrZHJvcC1ibHVyLXNtIHB4LTQgcHktMyI+CiAgICAgICAgPGRpdiBjbGFzc05hbWU9Im1heC13LTN4bCBteC1hdXRvIHNwYWNlLXktMiI+CiAgICAgICAgICA8ZGl2IGNsYXNzTmFtZT0iZmxleCBpdGVtcy1jZW50ZXIgZ2FwLTIiPgogICAgICAgICAgICA8TW9kZWxTZWxlY3RvciBtb2RlbHM9e21vZGVsc30gc2VsZWN0ZWQ9e21vZGVsfSBvblNlbGVjdD17c2V0TW9kZWx9IC8+CiAgICAgICAgICAgIDxkaXYgY2xhc3NOYW1lPSJmbGV4IGl0ZW1zLWNlbnRlciBnYXAtMiBtbC1hdXRvIHRleHQteHMgdGV4dC1ncmF5LTYwMCI+CiAgICAgICAgICAgICAgPHNwYW4+VGVtcGVyYXR1cjwvc3Bhbj4KICAgICAgICAgICAgICA8aW5wdXQgdHlwZT0icmFuZ2UiIG1pbj0iMCIgbWF4PSIyIiBzdGVwPSIwLjEiIHZhbHVlPXt0ZW1wfQogICAgICAgICAgICAgICAgb25DaGFuZ2U9e2UgPT4gc2V0VGVtcChwYXJzZUZsb2F0KGUudGFyZ2V0LnZhbHVlKSl9CiAgICAgICAgICAgICAgICBjbGFzc05hbWU9InctMjAgYWNjZW50LWJsdWUtNTAwIGN1cnNvci1wb2ludGVyIiAvPgogICAgICAgICAgICAgIDxzcGFuIGNsYXNzTmFtZT0idy03IHRleHQtcmlnaHQgdGV4dC1ncmF5LTQwMCB0YWJ1bGFyLW51bXMiPnt0ZW1wLnRvRml4ZWQoMSl9PC9zcGFuPgogICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgIDwvZGl2PgogICAgICAgICAgPGRpdiBjbGFzc05hbWU9ImZsZXggZ2FwLTIgaXRlbXMtZW5kIj4KICAgICAgICAgICAgPHRleHRhcmVhIHJlZj17dGV4dGFyZWFSZWZ9IHZhbHVlPXtpbnB1dH0KICAgICAgICAgICAgICBvbkNoYW5nZT17ZSA9PiBzZXRJbnB1dChlLnRhcmdldC52YWx1ZSl9CiAgICAgICAgICAgICAgb25LZXlEb3duPXtoYW5kbGVLZXlEb3dufQogICAgICAgICAgICAgIHBsYWNlaG9sZGVyPSJOYWNocmljaHQgZWluZ2ViZW4g4oCmIChFbnRlciBzZW5kZW4sIFNoaWZ0K0VudGVyIG5ldWUgWmVpbGUpIgogICAgICAgICAgICAgIHJvd3M9ezF9CiAgICAgICAgICAgICAgc3R5bGU9e3sgcmVzaXplOiAnbm9uZScgfX0KICAgICAgICAgICAgICBjbGFzc05hbWU9ImZsZXgtMSBiZy1ncmF5LTgwMCBib3JkZXIgYm9yZGVyLWdyYXktNzAwIHJvdW5kZWQteGwgcHgtNCBweS0zCiAgICAgICAgICAgICAgICB0ZXh0LXNtIHRleHQtd2hpdGUgcGxhY2Vob2xkZXItZ3JheS02MDAgZm9jdXM6b3V0bGluZS1ub25lIGZvY3VzOmJvcmRlci1ibHVlLTYwMAogICAgICAgICAgICAgICAgdHJhbnNpdGlvbi1jb2xvcnMgbWluLWgtWzQ4cHhdIG1heC1oLTQ0IG92ZXJmbG93LXktYXV0byBsZWFkaW5nLXJlbGF4ZWQiCiAgICAgICAgICAgICAgb25JbnB1dD17ZSA9PiB7CiAgICAgICAgICAgICAgICBjb25zdCBlbCA9IGUuY3VycmVudFRhcmdldAogICAgICAgICAgICAgICAgZWwuc3R5bGUuaGVpZ2h0ID0gJ2F1dG8nCiAgICAgICAgICAgICAgICBlbC5zdHlsZS5oZWlnaHQgPSBNYXRoLm1pbihlbC5zY3JvbGxIZWlnaHQsIDE3NikgKyAncHgnCiAgICAgICAgICAgICAgfX0KICAgICAgICAgICAgLz4KICAgICAgICAgICAgPGJ1dHRvbiBvbkNsaWNrPXtzZW5kTWVzc2FnZX0gZGlzYWJsZWQ9eyFpbnB1dC50cmltKCkgfHwgc3RyZWFtaW5nfQogICAgICAgICAgICAgIGNsYXNzTmFtZT0iZmxleC1zaHJpbmstMCB3LTEwIGgtMTAgYmctYmx1ZS02MDAgaG92ZXI6YmctYmx1ZS01MDAgZGlzYWJsZWQ6YmctZ3JheS04MDAKICAgICAgICAgICAgICAgIGRpc2FibGVkOnRleHQtZ3JheS02MDAgcm91bmRlZC14bCBmbGV4IGl0ZW1zLWNlbnRlciBqdXN0aWZ5LWNlbnRlciB0cmFuc2l0aW9uLWNvbG9ycyI+CiAgICAgICAgICAgICAge3N0cmVhbWluZwogICAgICAgICAgICAgICAgPyA8TG9hZGVyMiBjbGFzc05hbWU9InctNCBoLTQgYW5pbWF0ZS1zcGluIiAvPgogICAgICAgICAgICAgICAgOiA8U2VuZCBjbGFzc05hbWU9InctNCBoLTQiIC8+CiAgICAgICAgICAgICAgfQogICAgICAgICAgICA8L2J1dHRvbj4KICAgICAgICAgIDwvZGl2PgogICAgICAgICAgPHAgY2xhc3NOYW1lPSJ0ZXh0LXhzIHRleHQtZ3JheS03MDAgdGV4dC1jZW50ZXIiPgogICAgICAgICAgICBBSTRBbGwgaXN0IG9wZW4gc291cmNlIHVuZCBjb21tdW5pdHktYmV0cmllYmVuIMK3IEFudHdvcnRlbiBrw7ZubmVuIHVuZ2VuYXUgc2VpbgogICAgICAgICAgPC9wPgogICAgICAgIDwvZGl2PgogICAgICA8L2Rpdj4KICAgIDwvZGl2PgogICkKfQo=' | base64 -d > webui/src/App.tsx

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
