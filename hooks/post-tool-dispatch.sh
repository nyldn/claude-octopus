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
ACTIVATION_LIB="${PLUGIN_ROOT}/scripts/lib/hook-activation.sh"
PROFILE_POST_TOOL=false
PROFILE_NAME=core
if [[ -r "$ACTIVATION_LIB" ]]; then
    # shellcheck source=../scripts/lib/hook-activation.sh
    source "$ACTIVATION_LIB" 2>/dev/null || true
    PROFILE_NAME="$(octo_hook_profile)"
    octo_hook_profile_allows "post-tool-dispatch" && PROFILE_POST_TOOL=true
fi
if [[ "$PROFILE_POST_TOOL" != true ]]; then
    case "${OCTOPUS_CONTEXT_AWARENESS:-off}:${OCTO_STRATEGY_ROTATION:-off}:${OCTOPUS_COMPRESS_ENABLED:-false}" in
        on:*|*:on:*|*:*:true) ;;
        *) exit 0 ;;
    esac
fi

SESSION="${CLAUDE_SESSION_ID:-unknown}"
BRIDGE="/tmp/octopus-ctx-${SESSION}.json"

# Read stdin once (tool output from CC hook protocol)
STDIN_DATA=""
if [[ ! -t 0 ]]; then
    if command -v timeout &>/dev/null; then
        STDIN_DATA=$(timeout 5 cat 2>/dev/null || true)
    else
        STDIN_DATA=$(cat 2>/dev/null || true)
    fi
fi

# Profiles activate bounded coordination only while this host session owns an
# active Octopus workflow. Explicit environment opt-ins retain their existing
# behavior outside a workflow. Full also enables output compression unless the
# user explicitly disabled it.
if [[ "$PROFILE_POST_TOOL" == true ]] && octo_hook_workflow_active "$STDIN_DATA"; then
    OCTOPUS_CONTEXT_AWARENESS="${OCTOPUS_CONTEXT_AWARENESS:-on}"
    OCTO_STRATEGY_ROTATION="${OCTO_STRATEGY_ROTATION:-on}"
    if [[ "$PROFILE_NAME" == full ]]; then
        OCTOPUS_COMPRESS_ENABLED="${OCTOPUS_COMPRESS_ENABLED:-true}"
    fi
fi

# A statusline bridge by itself is display state, not consent to model-context
# injection.
if [[ "${OCTOPUS_CONTEXT_AWARENESS:-off}" != "on" \
      && "${OCTO_STRATEGY_ROTATION:-off}" != "on" \
      && "${OCTOPUS_COMPRESS_ENABLED:-false}" != "true" ]]; then
    exit 0
fi

# Collect additionalContext from sub-hooks
CONTEXTS=""

# 1. Context awareness — only after explicit opt-in and when bridge state exists
if [[ "${OCTOPUS_CONTEXT_AWARENESS:-off}" == "on" && -f "$BRIDGE" ]]; then
    ctx=$("$HOOKS_DIR/context-awareness.sh" <<< "" 2>/dev/null || echo "")
    if [[ -n "$ctx" ]] && echo "$ctx" | grep -q 'additionalContext'; then
        msg=$(echo "$ctx" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null || echo "")
        [[ -n "$msg" ]] && CONTEXTS="${CONTEXTS}${CONTEXTS:+ | }${msg}"
    fi
fi

# 2. Strategy rotation — pass stdin data for failure tracking
if [[ "${OCTO_STRATEGY_ROTATION:-off}" == "on" ]]; then
    OCTO_STRATEGY_ROTATION=on bash "$HOOKS_DIR/strategy-rotation.sh" <<< "$STDIN_DATA" 2>/dev/null || true
fi

# 3. Output compressor — only on large outputs (>3K chars)
if [[ ${#STDIN_DATA} -gt 3000 && "${OCTOPUS_COMPRESS_ENABLED:-false}" == "true" ]]; then
    comp=$("$HOOKS_DIR/output-compressor.sh" <<< "$STDIN_DATA" 2>/dev/null || echo "")
    if [[ -n "$comp" ]] && echo "$comp" | grep -q 'additionalContext'; then
        msg=$(echo "$comp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null || echo "")
        [[ -n "$msg" ]] && CONTEXTS="${CONTEXTS}${CONTEXTS:+ | }${msg}"
    fi
fi

# Emit combined response
if [[ -n "$CONTEXTS" ]]; then
    escaped=$(echo "$CONTEXTS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null | sed 's/^"//;s/"$//')
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"${escaped}\"}}"
else
    : # pass-through — current hook schema treats silence as continue
fi
