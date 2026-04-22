#!/usr/bin/env bash
# Claude Octopus — Context Awareness Hook (v9.19.0)
# PostToolUse hook that warns when context window usage is high.
# Reads bridge file written by statusline hooks and emits warnings
# at 65% (WARNING), 75% (CRITICAL), and 80% (AUTO_COMPACT) thresholds.
#
# v9.19.0: RTK-aware optimization nudges at all severity levels.
#           When RTK is installed, shows gain stats. When not, suggests install.
#           RTK tip shown at WARNING and CRITICAL (not just WARNING).
# v9.6.0:  Workflow-aware messages with phase-specific advice.
# Debounced: fires every 5 tool calls to avoid flooding.
# Severity escalation bypasses debounce.
#
# Hook event: PostToolUse (blanket matcher)

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Read stdin (required by hook protocol — drain to prevent SIGPIPE)
if command -v timeout &>/dev/null; then
    timeout 3 cat > /dev/null 2>&1 || true
else
    cat > /dev/null 2>&1 || true
fi

SESSION="${CLAUDE_SESSION_ID:-unknown}"
# Exit if session ID unknown — cannot safely identify the right bridge file
[[ "$SESSION" == "unknown" ]] && exit 0
BRIDGE="/tmp/octopus-ctx-${SESSION}.json"
DEBOUNCE_FILE="/tmp/octopus-ctx-debounce-${SESSION}.count"
LAST_SEVERITY_FILE="/tmp/octopus-ctx-severity-${SESSION}.level"
SESSION_FILE="${HOME}/.claude-octopus/session.json"

# No bridge file = statusline hasn't run yet, skip silently
[[ -f "$BRIDGE" ]] || exit 0

# Read bridge data
if ! command -v python3 &>/dev/null; then
    exit 0
fi

USED_PCT=$(BRIDGE_PATH="$BRIDGE" python3 -c "
import json, os
try:
    d = json.load(open(os.environ['BRIDGE_PATH']))
    print(d.get('used_pct', 0))
except:
    print(0)
" 2>/dev/null) || USED_PCT=0

# Determine severity (3 levels)
SEVERITY=""
if [[ "$USED_PCT" -ge 80 ]]; then
    SEVERITY="AUTO_COMPACT"
elif [[ "$USED_PCT" -ge 75 ]]; then
    SEVERITY="CRITICAL"
elif [[ "$USED_PCT" -ge 65 ]]; then
    SEVERITY="WARNING"
fi

# No warning needed
[[ -z "$SEVERITY" ]] && exit 0

# Debounce: increment counter, fire every 5 tool calls
COUNT=0
[[ -f "$DEBOUNCE_FILE" ]] && COUNT=$(<"$DEBOUNCE_FILE" 2>/dev/null) || COUNT=0
COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$DEBOUNCE_FILE" 2>/dev/null || true

# Check for severity escalation (bypasses debounce)
LAST_SEVERITY=""
[[ -f "$LAST_SEVERITY_FILE" ]] && LAST_SEVERITY=$(<"$LAST_SEVERITY_FILE" 2>/dev/null) || true
ESCALATED=false
if [[ "$SEVERITY" == "AUTO_COMPACT" && "$LAST_SEVERITY" != "AUTO_COMPACT" ]]; then
    ESCALATED=true
elif [[ "$SEVERITY" == "CRITICAL" && "$LAST_SEVERITY" == "WARNING" ]]; then
    ESCALATED=true
fi

# Only fire every 5 tool calls unless escalated
if [[ "$ESCALATED" != "true" && $((COUNT % 5)) -ne 0 ]]; then
    exit 0
fi

# Record current severity
printf '%s' "$SEVERITY" > "$LAST_SEVERITY_FILE" 2>/dev/null || true

# v9.6.0: Detect active workflow phase for tailored advice
REMAINING=$((100 - USED_PCT))
PHASE=""
WORKFLOW=""
if [[ -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
    PHASE=$(jq -r '.current_phase // .phase // empty' "$SESSION_FILE" 2>/dev/null) || PHASE=""
    WORKFLOW=$(jq -r '.workflow // empty' "$SESSION_FILE" 2>/dev/null) || WORKFLOW=""
fi

# Build workflow-aware warning message
ADVICE=""
if [[ -n "$PHASE" && "$PHASE" != "null" && "$PHASE" != "none" ]]; then
    case "$PHASE" in
        probe|grasp)
            ADVICE="Research phase active — consider /octo:quick for lighter execution, or narrow your research scope." ;;
        tangle)
            ADVICE="Implementation phase is context-heavy — consider splitting remaining work into a fresh /octo:develop session." ;;
        ink)
            ADVICE="Validation phase — focus on verification, skip exploration. Use targeted grep over full file reads." ;;
        *)
            ADVICE="Be concise in responses and avoid reading large files unnecessarily." ;;
    esac
else
    ADVICE="Be concise in responses and avoid reading large files unnecessarily."
fi

# v9.19.0: RTK-aware optimization nudges
RTK_TIP=""
if command -v rtk &>/dev/null; then
    # RTK installed — show gain stats at CRITICAL+ to remind of savings
    if [[ "$SEVERITY" == "CRITICAL" || "$SEVERITY" == "AUTO_COMPACT" ]]; then
        RTK_SAVED=""
        if command -v python3 &>/dev/null; then
            RTK_SAVED=$(rtk gain --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); s=d.get('summary',d); print(s.get('total_saved',''))" 2>/dev/null) || RTK_SAVED=""
        fi
        if [[ -n "$RTK_SAVED" && "$RTK_SAVED" != "0" ]]; then
            RTK_TIP=" RTK active (${RTK_SAVED} tokens saved). Use Read/Grep tools instead of bash cat/grep to save more."
        fi
    fi
else
    # RTK not installed — suggest at WARNING, CRITICAL, and AUTO_COMPACT
    if [[ "$SEVERITY" == "WARNING" || "$SEVERITY" == "CRITICAL" || "$SEVERITY" == "AUTO_COMPACT" ]]; then
        RTK_TIP=" Tip: brew install rtk && rtk init -g (60-90% token savings). /octo:doctor to install."
    fi
fi

case "$SEVERITY" in
    AUTO_COMPACT)
        MSG="ctx ${USED_PCT}% — auto-compact imminent, finish current thought. ${ADVICE}${RTK_TIP}" ;;
    CRITICAL)
        MSG="ctx ${USED_PCT}% critical. ${ADVICE}${RTK_TIP}" ;;
    WARNING)
        MSG="ctx ${USED_PCT}% warning. ${ADVICE}${RTK_TIP}" ;;
esac

# Return hook response with context warning
cat <<EOF
{"decision":"continue","additionalContext":"[🐙] ${MSG}"}
EOF
