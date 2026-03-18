#!/usr/bin/env bash
# Claude Octopus — Context Awareness Hook (v9.5.0)
# PostToolUse hook that warns when context window usage is high.
# Reads bridge file written by statusline hooks and emits warnings
# at 65% (WARNING) and 75% (CRITICAL) usage thresholds.
#
# Debounced: fires every 5 tool calls to avoid flooding.
# Severity escalation bypasses debounce.
#
# Hook event: PostToolUse (blanket matcher)

set -euo pipefail

# Read stdin (required by hook protocol)
timeout 3 cat > /dev/null 2>&1 || true

SESSION="${CLAUDE_SESSION_ID:-unknown}"
BRIDGE="/tmp/octopus-ctx-${SESSION}.json"
DEBOUNCE_FILE="/tmp/octopus-ctx-debounce-${SESSION}.count"
LAST_SEVERITY_FILE="/tmp/octopus-ctx-severity-${SESSION}.level"

# No bridge file = statusline hasn't run yet, skip silently
[[ -f "$BRIDGE" ]] || exit 0

# Read bridge data
if ! command -v python3 &>/dev/null; then
    exit 0
fi

USED_PCT=$(python3 -c "
import json, sys
try:
    d = json.load(open('$BRIDGE'))
    print(d.get('used_pct', 0))
except:
    print(0)
" 2>/dev/null) || USED_PCT=0

# Determine severity
SEVERITY=""
if [[ "$USED_PCT" -ge 75 ]]; then
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
if [[ "$SEVERITY" == "CRITICAL" && "$LAST_SEVERITY" != "CRITICAL" ]]; then
    ESCALATED=true
fi

# Only fire every 5 tool calls unless escalated
if [[ "$ESCALATED" != "true" && $((COUNT % 5)) -ne 0 ]]; then
    exit 0
fi

# Record current severity
printf '%s' "$SEVERITY" > "$LAST_SEVERITY_FILE" 2>/dev/null || true

# Build warning message
REMAINING=$((100 - USED_PCT))
if [[ "$SEVERITY" == "CRITICAL" ]]; then
    MSG="CRITICAL: Context window at ${USED_PCT}% (${REMAINING}% remaining). Consider compacting or summarizing before continuing. Long outputs and large file reads will accelerate context exhaustion."
else
    MSG="WARNING: Context window at ${USED_PCT}% (${REMAINING}% remaining). Be concise in responses and avoid reading large files unnecessarily."
fi

# Return hook response with context warning
cat <<EOF
{"decision":"continue","additionalContext":"[Octopus Context Monitor] ${MSG}"}
EOF
