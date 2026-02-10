#!/bin/bash
# Claude Octopus Budget Gate Hook (v8.7.0)
# PreToolUse hook that enforces session cost budget
# Reads OCTOPUS_MAX_COST_USD and compares against metrics-session.json
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}
set -euo pipefail

# If no budget configured, always continue
if [[ -z "${OCTOPUS_MAX_COST_USD:-}" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

# Read tool input from stdin (not used for budget check but required by hook protocol)
cat > /dev/null 2>&1 || true

# Locate metrics file
metrics_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}"
metrics_file="${metrics_dir}/metrics-session.json"

if [[ ! -f "$metrics_file" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

# Requires jq for JSON parsing
if ! command -v jq &>/dev/null; then
    echo '{"decision": "continue", "reason": "jq not available for budget check"}'
    exit 0
fi

# Sum estimated_cost_usd from session metrics
current_cost=$(jq -r '.totals.estimated_cost_usd // 0' "$metrics_file" 2>/dev/null || echo "0")

# Compare using awk (portable float comparison)
budget_status=$(awk -v current="$current_cost" -v budget="$OCTOPUS_MAX_COST_USD" '
BEGIN {
    if (current + 0 >= budget + 0) {
        print "over"
    } else if (current + 0 >= (budget + 0) * 0.8) {
        print "warning"
    } else {
        print "ok"
    }
}')

case "$budget_status" in
    over)
        echo "{\"decision\": \"block\", \"reason\": \"Session cost \$${current_cost} exceeds budget \$${OCTOPUS_MAX_COST_USD}. Set OCTOPUS_MAX_COST_USD to increase limit.\"}"
        ;;
    warning)
        echo "{\"decision\": \"continue\", \"reason\": \"Budget warning: \$${current_cost} of \$${OCTOPUS_MAX_COST_USD} used (80%+ threshold)\"}"
        ;;
    *)
        echo '{"decision": "continue"}'
        ;;
esac

exit 0
