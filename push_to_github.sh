#!/usr/bin/env bash
# AI4All – Push to GitHub via SSH
# Repo: git@github.com:FunCyRanger/AI4All.git
#
# Usage:
#   chmod +x push_to_github.sh
#   bash push_to_github.sh
#
# Prerequisites:
#   1. SSH key added to your GitHub account
#      → https://github.com/settings/keys
#   2. git installed

set -e

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}ℹ  ${NC}$*"; }
success() { echo -e "${GREEN}✓  ${NC}$*"; }
warn()    { echo -e "${YELLOW}⚠  ${NC}$*"; }
error()   { echo -e "${RED}✗  ${NC}$*"; exit 1; }

REPO="git@github.com:FunCyRanger/AI4All.git"

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   AI4All – Push to GitHub (SSH)          ║"
echo "  ║   → FunCyRanger/AI4All                   ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# ── Check git ──────────────────────────────────────────────────────────────
command -v git &>/dev/null || error "git is not installed."
success "git found ($(git --version))"

# ── Check SSH key ──────────────────────────────────────────────────────────
info "Testing SSH connection to GitHub..."
SSH_TEST=$(ssh -T git@github.com 2>&1 || true)

if echo "$SSH_TEST" | grep -q "successfully authenticated"; then
  success "SSH authentication OK  →  $SSH_TEST"
else
  echo ""
  warn "SSH key not yet authorized. Let's set one up."
  echo ""

  # Find or generate a key
  if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    KEY_FILE="$HOME/.ssh/id_ed25519.pub"
    success "Found existing key: $KEY_FILE"
  elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    KEY_FILE="$HOME/.ssh/id_rsa.pub"
    success "Found existing key: $KEY_FILE"
  else
    info "No SSH key found – generating one now..."
    ssh-keygen -t ed25519 -C "AI4All GitHub Key" -f "$HOME/.ssh/id_ed25519" -N ""
    KEY_FILE="$HOME/.ssh/id_ed25519.pub"
    success "New SSH key generated"
  fi

  echo ""
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}  ACTION REQUIRED – Add this public key to GitHub:${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "  1. Copy the key below"
  echo "  2. Go to: https://github.com/settings/keys"
  echo "  3. Click 'New SSH key' → paste → Save"
  echo "  4. Run this script again"
  echo ""
  echo -e "${GREEN}$(cat "$KEY_FILE")${NC}"
  echo ""
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Offer to open browser
  if command -v xdg-open &>/dev/null; then
    read -rp "Open GitHub in browser now? [y/N] " OPEN
    [[ "$OPEN" =~ ^[Yy]$ ]] && xdg-open "https://github.com/settings/keys"
  elif command -v open &>/dev/null; then
    read -rp "Open GitHub in browser now? [y/N] " OPEN
    [[ "$OPEN" =~ ^[Yy]$ ]] && open "https://github.com/settings/keys"
  fi

  echo ""
  read -rp "Press ENTER once you've added the key to GitHub..." _
  echo ""

  # Re-test
  SSH_TEST2=$(ssh -T git@github.com 2>&1 || true)
  if echo "$SSH_TEST2" | grep -q "successfully authenticated"; then
    success "SSH authentication confirmed!"
  else
    error "Still can't authenticate. Please check your key on https://github.com/settings/keys and try again."
  fi
fi

# ── Init git repo ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
info "Working directory: $SCRIPT_DIR"

if [ ! -d ".git" ]; then
  info "Initializing git repository..."
  git init
  success "Git initialized"
fi

# ── Set remote ─────────────────────────────────────────────────────────────
if git remote get-url origin &>/dev/null 2>&1; then
  info "Updating remote origin → $REPO"
  git remote set-url origin "$REPO"
else
  info "Adding remote origin → $REPO"
  git remote add origin "$REPO"
fi
success "Remote: $(git remote get-url origin)"

# ── Stage & commit ─────────────────────────────────────────────────────────
info "Staging all files..."
git add -A
CHANGED=$(git status --short | wc -l)
info "$CHANGED file(s) staged"

git diff --cached --quiet && {
  warn "Nothing new to commit – all files already committed."
} || {
  info "Creating commit..."
  git commit -m "feat: initial AI4All MVP

Core components:
- Rust P2P node (libp2p: mDNS + Kademlia + Gossipsub)
- Ed25519 signed token wallet
- FastAPI gateway – OpenAI-compatible, Ollama backend, SSE streaming
- React Web UI – model selector, streaming chat, node status
- Docker Compose one-command stack
- GitHub Actions CI pipeline

AI4All – AI belongs to everyone."
  success "Commit created"
}

# ── Push ───────────────────────────────────────────────────────────────────
info "Pushing to $REPO ..."
git branch -M main
git push -u origin main --force

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅  Successfully pushed to GitHub!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  🔗  https://github.com/FunCyRanger/AI4All"
echo ""
echo "  Next steps:"
echo "  1. Check GitHub Actions:  https://github.com/FunCyRanger/AI4All/actions"
echo "  2. Start locally:         bash setup.sh"
echo "  3. Share the link and invite contributors!"
echo ""
