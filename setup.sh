#!/usr/bin/env bash
# AI4All – Setup Script with auto GPU detection
# Usage:  bash setup.sh [--cpu] [--nvidia] [--amd]

set -e

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}ℹ  ${NC}$*"; }
success() { echo -e "${GREEN}✓  ${NC}$*"; }
warn()    { echo -e "${YELLOW}⚠  ${NC}$*"; }
error()   { echo -e "${RED}✗  ${NC}$*\n"; exit 1; }

# ── Always run from the script's own directory ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
info "Working directory: $SCRIPT_DIR"

# ── Parse flags ────────────────────────────────────────────────────────────
FORCE_CPU=false; FORCE_NVIDIA=false; FORCE_AMD=false
for arg in "$@"; do
  case $arg in --cpu) FORCE_CPU=true;; --nvidia) FORCE_NVIDIA=true;; --amd) FORCE_AMD=true;; esac
done

echo ""
echo -e "  ${BOLD}╔═══════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║        AI4All – Setup Wizard              ║${NC}"
echo -e "  ${BOLD}╚═══════════════════════════════════════════╝${NC}"
echo ""

# ── 1. Verify required files exist ────────────────────────────────────────
echo -e "${BOLD}── File Structure Check ──${NC}"

REQUIRED_FILES=(
  "docker-compose.yml"
  "api/Dockerfile"
  "api/main.py"
  "api/requirements.txt"
  "webui/Dockerfile.prod"
  "webui/package.json"
  "webui/src/App.tsx"
)

ALL_OK=true
for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$SCRIPT_DIR/$f" ]; then
    success "$f"
  else
    echo -e "${RED}✗  MISSING: $f${NC}"
    ALL_OK=false
  fi
done

if ! $ALL_OK; then
  echo ""
  error "Some required files are missing. Make sure you are running this script
  from the AI4All project root directory (where docker-compose.yml lives).

  Expected structure:
    AI4All/
    ├── docker-compose.yml   ← run 'bash setup.sh' from here
    ├── api/
    │   ├── Dockerfile
    │   ├── main.py
    │   └── requirements.txt
    └── webui/
        ├── Dockerfile.prod
        └── src/App.tsx

  If you cloned from GitHub:
    git clone https://github.com/FunCyRanger/AI4All.git
    cd AI4All
    bash setup.sh"
fi

echo ""

# ── 2. Check Docker ────────────────────────────────────────────────────────
echo -e "${BOLD}── Dependency Check ──${NC}"

command -v docker &>/dev/null \
  || error "Docker not found.\n  Install: https://docs.docker.com/get-docker/"
success "Docker: $(docker --version | head -1)"

if ! docker info &>/dev/null 2>&1; then
  error "Docker daemon is not running.\n  Start it: sudo systemctl start docker  (Linux)\n  Or open Docker Desktop (Mac/Windows)"
fi
success "Docker daemon: running"

if docker compose version &>/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE="docker-compose"
else
  error "Docker Compose not found.\n  Install: https://docs.docker.com/compose/install/"
fi
success "Compose: $($COMPOSE version | head -1)"

echo ""

# ── 3. GPU Detection ───────────────────────────────────────────────────────
echo -e "${BOLD}── GPU Detection ──${NC}"

GPU_MODE="cpu"
COMPOSE_FILES="-f docker-compose.yml"

if $FORCE_CPU; then
  warn "CPU mode forced (--cpu flag)"
elif $FORCE_NVIDIA; then
  GPU_MODE="nvidia"
  COMPOSE_FILES="-f docker-compose.yml -f docker-compose.nvidia.yml"
  success "NVIDIA mode forced (--nvidia flag)"
elif $FORCE_AMD; then
  GPU_MODE="amd"
  COMPOSE_FILES="-f docker-compose.yml -f docker-compose.amd.yml"
  success "AMD mode forced (--amd flag)"
else
  # Auto-detect NVIDIA
  if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
    if docker info 2>/dev/null | grep -q "nvidia"; then
      GPU_MODE="nvidia"
      COMPOSE_FILES="-f docker-compose.yml -f docker-compose.nvidia.yml"
      GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "NVIDIA GPU")
      success "NVIDIA GPU: $GPU_NAME"
    else
      warn "NVIDIA GPU found, but Container Toolkit not configured → CPU fallback"
      warn "  Fix: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    fi
  # Auto-detect AMD
  elif [ -e /dev/kfd ] && [ -d /dev/dri ]; then
    GPU_MODE="amd"
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.amd.yml"
    GPU_NAME=$(command -v rocm-smi &>/dev/null && rocm-smi --showproductname 2>/dev/null | grep -i "gpu\|card" | head -1 || echo "AMD GPU (ROCm)")
    success "AMD GPU detected: $GPU_NAME"
    # Auto-detect GFX version
    if command -v rocminfo &>/dev/null; then
      GFX=$(rocminfo 2>/dev/null | grep -oE 'gfx[0-9]+' | head -1)
      if [ -n "$GFX" ]; then
        case "$GFX" in
          gfx11*) VER="11.0.0";; gfx103*) VER="10.3.0";;
          gfx101*) VER="10.1.0";; gfx90a) VER="9.0.10";;
          gfx908) VER="9.0.8";; gfx906) VER="9.0.6";;
          *) VER="11.0.0";;
        esac
        info "AMD GFX: $GFX → HSA_OVERRIDE_GFX_VERSION=$VER"
        sed -i "s/HSA_OVERRIDE_GFX_VERSION=.*/HSA_OVERRIDE_GFX_VERSION=$VER/" docker-compose.amd.yml 2>/dev/null || true
      fi
    fi
  else
    warn "No GPU detected → CPU-only mode (inference will be slow)"
    info "  Force GPU mode: bash setup.sh --nvidia  OR  bash setup.sh --amd"
  fi
fi

echo -e "  GPU Mode: ${CYAN}${BOLD}${GPU_MODE^^}${NC}"
echo ""

# ── 4. Start stack ─────────────────────────────────────────────────────────
echo -e "${BOLD}── Starting Services ──${NC}"
info "Running: $COMPOSE $COMPOSE_FILES up -d --build"
echo ""

$COMPOSE $COMPOSE_FILES up -d --build

echo ""

# ── 5. Health check ────────────────────────────────────────────────────────
echo -e "${BOLD}── Waiting for API ──${NC}"
printf "  "
for i in $(seq 1 40); do
  if curl -sf http://localhost:8000/health &>/dev/null; then
    echo ""
    success "API gateway is healthy"
    break
  fi
  printf "."
  sleep 3
  if [ "$i" -eq 40 ]; then
    echo ""
    warn "API not responding after 2 min. Check:"
    warn "  $COMPOSE $COMPOSE_FILES logs api"
  fi
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅  AI4All is running! (${GPU_MODE^^} mode)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  🌐  Web UI :  http://localhost:3000"
echo "  📡  API    :  http://localhost:8000/docs"
echo "  🖥   GPU    :  http://localhost:8000/v1/gpu"
echo ""
echo "  Models download in background:"
echo "  $COMPOSE $COMPOSE_FILES logs -f model-init"
echo ""
echo "  Stop:  $COMPOSE $COMPOSE_FILES down"
echo ""
