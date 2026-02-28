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
