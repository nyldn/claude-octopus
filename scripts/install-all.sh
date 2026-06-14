#!/usr/bin/env bash
# Single-command dependency installer for Claude Octopus providers.
# Installs Codex CLI, Gemini CLI, Qwen CLI, and jq.
#
# Usage:
#   bash scripts/install-all.sh           # install all missing deps
#   bash scripts/install-all.sh --dry-run # show what would be installed

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log() {
  local level="$1"
  shift
  echo "  [${level}] $*"
}

install_npm_pkg() {
  local pkg="$1" label="${2:-$1}"
  if ! command -v npm &>/dev/null; then
    log WARN "npm not found — cannot install $label. Install Node.js: https://nodejs.org"
    return 0
  fi
  $DRY_RUN && { log INFO "[dry-run] npm install -g $pkg"; return 0; }
  log INFO "Installing $label via npm..."
  npm install -g "$pkg" 2>&1 || log WARN "$label install failed. Try: sudo npm install -g $pkg"
  hash -r 2>/dev/null || rehash 2>/dev/null || true
}

install_jq() {
  command -v jq &>/dev/null && { log INFO "jq already installed ($(jq --version))"; return 0; }
  $DRY_RUN && { log INFO "[dry-run] install jq"; return 0; }
  if command -v brew &>/dev/null; then
    log INFO "Installing jq via Homebrew..."
    brew install jq
  elif command -v apt-get &>/dev/null; then
    log INFO "Installing jq via apt-get..."
    sudo apt-get install -y jq
  elif command -v choco &>/dev/null; then
    log INFO "Installing jq via Chocolatey..."
    choco install jq -y
  elif command -v winget &>/dev/null; then
    log INFO "Installing jq via winget..."
    winget install jqlang.jq
  else
    log WARN "No package manager found for jq. Install: https://jqlang.github.io/jq/download/"
  fi
}

echo ""
echo "🐙 Claude Octopus — Install All Dependencies"
echo "─────────────────────────────────────────────"
$DRY_RUN && echo "  (dry-run mode — no changes will be made)"
echo ""

echo "System:"
install_jq

echo ""
echo "Provider CLIs:"
command -v codex  &>/dev/null && log INFO "Codex CLI already installed"  || install_npm_pkg "@openai/codex"          "Codex CLI"
command -v gemini &>/dev/null && log INFO "Gemini CLI already installed" || install_npm_pkg "@google/gemini-cli"    "Gemini CLI"
command -v qwen   &>/dev/null && log INFO "Qwen CLI already installed"   || install_npm_pkg "@qwen-code/qwen-code"  "Qwen CLI (API-key/Coding-Plan)"

echo ""
echo "─────────────────────────────────────────────"
echo "  ✓ install-all complete."
echo ""
echo "  Providers requiring auth after install:"
echo "    Codex:  codex login"
echo "    Gemini: gemini auth login"
echo ""
echo "  Run /octo:preflight to verify provider status."
echo ""
