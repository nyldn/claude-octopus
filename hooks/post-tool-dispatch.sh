#!/usr/bin/env bash
# PostToolUse Dispatcher — Consolidated hook runner (v9.20.0)
# Replaces 3 blanket PostToolUse hooks (context-awareness, strategy-rotation,
# output-compressor) with a single process spawn.
# Saves 2 fork+exec per tool call (~200 process spawns per 100-tool session).
#
# Hook event: PostToolUse (blanket matcher: Bash|Agent|Write|Edit|Read|WebFetch|Grep)
# Note: Specifically-matched hooks (quality-gate, task-completion, telemetry)
#       remain as separate entries in hooks.json.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOKS_DIR="${PLUGIN_ROOT}/hooks"

# Read stdin once (tool output from CC hook protocol)
STDIN_DATA=""
if [[ ! -t 0 ]]; then
    if command -v timeout &>/dev/null; then
        STDIN_DATA=$(timeout 5 cat 2>/dev/null || true)
    else
        STDIN_DATA=$(cat 2>/dev/null || true)
    fi
fi

# Collect additionalContext from sub-hooks
CONTEXTS=""

# 1. Context awareness — only when bridge file exists
SESSION="${CLAUDE_SESSION_ID:-unknown}"
BRIDGE="/tmp/octopus-ctx-${SESSION}.json"
if [[ -f "$BRIDGE" ]]; then
    ctx=$("$HOOKS_DIR/context-awareness.sh" <<< "" 2>/dev/null || echo "")
    if [[ -n "$ctx" ]] && echo "$ctx" | grep -q 'additionalContext'; then
        msg=$(echo "$ctx" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('additionalContext',''))" 2>/dev/null || echo "")
        [[ -n "$msg" ]] && CONTEXTS="${CONTEXTS}${CONTEXTS:+ | }${msg}"
    fi
fi

# 2. Strategy rotation — pass stdin data for failure tracking
bash "$HOOKS_DIR/strategy-rotation.sh" <<< "$STDIN_DATA" 2>/dev/null || true

# 3. Output compressor — only on large outputs (>3K chars)
if [[ ${#STDIN_DATA} -gt 3000 && "${OCTOPUS_COMPRESS_ENABLED:-true}" == "true" ]]; then
    comp=$("$HOOKS_DIR/output-compressor.sh" <<< "$STDIN_DATA" 2>/dev/null || echo "")
    if [[ -n "$comp" ]] && echo "$comp" | grep -q 'additionalContext'; then
        msg=$(echo "$comp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('additionalContext',''))" 2>/dev/null || echo "")
        [[ -n "$msg" ]] && CONTEXTS="${CONTEXTS}${CONTEXTS:+ | }${msg}"
    fi
fi

# Emit combined response
if [[ -n "$CONTEXTS" ]]; then
    escaped=$(echo "$CONTEXTS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null | sed 's/^"//;s/"$//')
    echo "{\"decision\":\"continue\",\"additionalContext\":\"${escaped}\"}"
else
    echo '{"decision":"continue"}'
fi
