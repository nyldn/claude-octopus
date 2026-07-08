#!/usr/bin/env bash
set -euo pipefail
# /octo:preflight — Provider health probe with per-provider timeouts.
# Called by /octo:preflight slash command and setup.md STEP 1.
#
# Usage:
#   bash scripts/helpers/preflight.sh            # interactive dashboard
#   bash scripts/helpers/preflight.sh --exit-code # exits 0 if Claude available (always)
#   bash scripts/helpers/preflight.sh --json      # JSON output for scripting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK_VERSIONS="${SCRIPT_DIR}/check-versions.sh"
CHECK_OLLAMA_MODELS="${SCRIPT_DIR}/check-ollama-models.sh"

TIMEOUT_CMD=""
if command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout"
fi

PROVIDERS_READY=0
PROVIDERS_DEGRADED=0
declare -a RESULT_LINES
declare -a RESULT_NAMES
declare -a RESULT_STATUSES

check_provider() {
  local name="$1"
  local check_cmd="$2"
  local timeout_s="${3:-2}"
  local icon
  local available=false

  if [[ -n "$TIMEOUT_CMD" ]]; then
    "$TIMEOUT_CMD" "$timeout_s" bash -c "$check_cmd" &>/dev/null && available=true
  else
    bash -c "$check_cmd" &>/dev/null && available=true
  fi

  if $available; then
    icon="✅"
    ((PROVIDERS_READY++)) || true
    RESULT_STATUSES+=("available")
  else
    icon="⚠️ "
    ((PROVIDERS_DEGRADED++)) || true
    RESULT_STATUSES+=("unavailable")
  fi

  RESULT_NAMES+=("$name")
  RESULT_LINES+=("  ${icon} ${name}")
}

# Claude is always available (built-in)
check_provider "Claude (built-in)" "true"
check_provider "Codex CLI"    "command -v codex"
check_provider "Copilot"      "command -v gh && gh copilot --version"
check_provider "Qwen CLI"     "command -v qwen"
check_provider "OpenCode"     "command -v opencode"
check_provider "Ollama"       "curl -sf --max-time 2 http://localhost:11434/api/tags" 2
check_provider "Perplexity"   "[ -n \"${PERPLEXITY_API_KEY:-}\" ]"
check_provider "OpenRouter"   "[ -n \"${OPENROUTER_API_KEY:-}\" ]"

if [[ "${1:-}" == "--exit-code" ]]; then
  exit 0
fi

print_json_output() {
  local ver_json ollama_json
  ver_json="{}"
  if [[ -f "$CHECK_VERSIONS" ]]; then
    ver_json=$(bash "$CHECK_VERSIONS" --json 2>/dev/null) || ver_json='{"any_below_floor":false,"results":[]}'
  fi
  ollama_json='{"reachable":false,"models":[]}'
  if [[ -f "$CHECK_OLLAMA_MODELS" ]]; then
    ollama_json=$(bash "$CHECK_OLLAMA_MODELS" --json 2>/dev/null) || ollama_json='{"reachable":false,"models":[]}'
  fi

  OCTO_PREFLIGHT_NAMES="$(printf '%s\n' "${RESULT_NAMES[@]}")"
  OCTO_PREFLIGHT_STATUSES="$(printf '%s\n' "${RESULT_STATUSES[@]}")"
  OCTO_PREFLIGHT_VERSIONS="$ver_json"
  OCTO_PREFLIGHT_OLLAMA="$ollama_json"
  export OCTO_PREFLIGHT_NAMES OCTO_PREFLIGHT_STATUSES OCTO_PREFLIGHT_VERSIONS OCTO_PREFLIGHT_OLLAMA

  python3 - "$PROVIDERS_READY" "$PROVIDERS_DEGRADED" <<'PYEOF'
import json
import os
import sys

names = os.environ.get("OCTO_PREFLIGHT_NAMES", "").split("\n")
statuses = os.environ.get("OCTO_PREFLIGHT_STATUSES", "").split("\n")
if names == [""]:
    names = []
if statuses == [""]:
    statuses = []
while names and names[-1] == "":
    names.pop()
while statuses and statuses[-1] == "":
    statuses.pop()
try:
    versions = json.loads(os.environ.get("OCTO_PREFLIGHT_VERSIONS", "{}"))
except json.JSONDecodeError:
    versions = {"any_below_floor": False, "results": []}
try:
    ollama = json.loads(os.environ.get("OCTO_PREFLIGHT_OLLAMA", "{}"))
except json.JSONDecodeError:
    ollama = {"reachable": False, "models": []}

print(json.dumps({
    "providers_ready": int(sys.argv[1]),
    "providers_degraded": int(sys.argv[2]),
    "results": [
        {"name": name, "status": status}
        for name, status in zip(names, statuses)
    ],
    "versions": versions,
    "ollama_models": ollama,
}, indent=2))
PYEOF
}

if [[ "${1:-}" == "--json" ]]; then
  print_json_output
  exit 0
fi

echo ""
echo "🐙 Octopus Provider Health"
echo "──────────────────────────"
for line in "${RESULT_LINES[@]}"; do
  echo "$line"
done
echo ""
echo "  Ready: $PROVIDERS_READY  |  Unavailable: $PROVIDERS_DEGRADED"
echo ""
if [[ $PROVIDERS_READY -eq 1 ]]; then
  echo "  ℹ️  Claude-only mode. Run /octo:setup to add providers."
elif [[ $PROVIDERS_READY -ge 3 ]]; then
  echo "  🚀 Multi-provider mode active. Run /octo:embrace for full orchestration."
fi

# Version floor section
if [[ -f "$CHECK_VERSIONS" ]]; then
  bash "$CHECK_VERSIONS" 2>/dev/null || true
fi

# Ollama model staleness section
if [[ -f "$CHECK_OLLAMA_MODELS" ]]; then
  bash "$CHECK_OLLAMA_MODELS" 2>/dev/null || true
fi

echo ""
exit 0
