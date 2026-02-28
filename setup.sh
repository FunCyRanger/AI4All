#!/usr/bin/env bash
# AI4All – One-command setup script
# Usage: bash setup.sh

set -e

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}ℹ ${NC}$*"; }
success() { echo -e "${GREEN}✓ ${NC}$*"; }
warn()    { echo -e "${YELLOW}⚠ ${NC}$*"; }
error()   { echo -e "${RED}✗ ${NC}$*"; exit 1; }

echo ""
echo "  ╔═══════════════════════════════════╗"
echo "  ║     AI4All – Setup Wizard         ║"
echo "  ║   AI for Everyone, by Everyone    ║"
echo "  ╚═══════════════════════════════════╝"
echo ""

# ── Detect OS ─────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Linux*)  PLATFORM="linux";;
  Darwin*) PLATFORM="macos";;
  *)       error "Unsupported OS: $OS. Please use Linux or macOS.";;
esac
info "Platform: $PLATFORM"

# ── Check dependencies ────────────────────────────────────────────────────
check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    error "$1 is required but not installed. $2"
  fi
  success "$1 found"
}

info "Checking dependencies..."
check_cmd docker   "Install from https://docs.docker.com/get-docker/"
check_cmd git      "Install git via your package manager"

# Docker Compose (v2 plugin or standalone)
if docker compose version &>/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE="docker-compose"
else
  error "Docker Compose not found. Install from https://docs.docker.com/compose/"
fi
success "Docker Compose found ($COMPOSE)"

# ── Optional: Ollama local (non-Docker) ───────────────────────────────────
echo ""
info "Checking for local Ollama (optional – Docker will use its own)..."
if command -v ollama &>/dev/null; then
  success "Ollama found locally"
  OLLAMA_LOCAL=true
else
  warn "Ollama not found locally – will use Dockerized version"
  OLLAMA_LOCAL=false
fi

# ── Start stack ───────────────────────────────────────────────────────────
echo ""
info "Starting AI4All stack with Docker Compose..."
$COMPOSE up -d --build

echo ""
info "Waiting for services to become healthy..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8000/health &>/dev/null; then
    success "API gateway is up"
    break
  fi
  if [ "$i" -eq 30 ]; then
    warn "API gateway not responding after 60s. Check: $COMPOSE logs api"
  fi
  sleep 2
done

# ── Done ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  AI4All is running! 🎉${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  🌐 Web UI :  http://localhost:3000"
echo "  📡 API    :  http://localhost:8000"
echo "  📖 API docs: http://localhost:8000/docs"
echo ""
echo "  First-time model pull may take a few minutes."
echo "  Models available: llama3, phi3, codellama"
echo ""
echo "  To stop:    $COMPOSE down"
echo "  Logs:       $COMPOSE logs -f"
echo ""
