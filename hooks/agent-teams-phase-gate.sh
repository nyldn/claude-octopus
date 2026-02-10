#!/bin/bash
# Claude Octopus Agent Teams Phase Gate Hook (v8.7.0)
# TaskCompleted hook that checks bridge ledger for phase completion
# Triggers quality gate evaluation and phase transition
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}
set -euo pipefail

# Bridge configuration
BRIDGE_DIR="${HOME}/.claude-octopus/bridge"
BRIDGE_LEDGER="${BRIDGE_DIR}/task-ledger.json"

# Read hook input from stdin
hook_input=$(cat 2>/dev/null || true)

# If bridge is not enabled or ledger doesn't exist, continue
if [[ "${OCTOPUS_AGENT_TEAMS_BRIDGE:-auto}" == "disabled" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

if [[ ! -f "$BRIDGE_LEDGER" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

if ! command -v jq &>/dev/null; then
    echo '{"decision": "continue", "reason": "jq not available for phase gate check"}'
    exit 0
fi

# Extract task ID from hook input (if available)
task_id=""
if [[ -n "$hook_input" ]]; then
    task_id=$(echo "$hook_input" | jq -r '.task_id // empty' 2>/dev/null || true)
fi

# Get current phase from ledger
current_phase=$(jq -r '.current_phase // empty' "$BRIDGE_LEDGER" 2>/dev/null || true)

if [[ -z "$current_phase" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

# If task_id provided, mark it complete in ledger
if [[ -n "$task_id" ]]; then
    tmp="${BRIDGE_LEDGER}.tmp.$$"
    jq --arg id "$task_id" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       'if .tasks[$id] then
            .tasks[$id].status = "completed" |
            .tasks[$id].completed_at = $ts |
            .phases[.tasks[$id].phase].completed_tasks = ((.phases[.tasks[$id].phase].completed_tasks // 0) + 1)
        else . end' \
       "$BRIDGE_LEDGER" > "$tmp" 2>/dev/null && mv "$tmp" "$BRIDGE_LEDGER" || rm -f "$tmp"
fi

# Check if all tasks in current phase are complete
total_tasks=$(jq -r ".phases.\"$current_phase\".total_tasks // 0" "$BRIDGE_LEDGER" 2>/dev/null)
completed_tasks=$(jq -r ".phases.\"$current_phase\".completed_tasks // 0" "$BRIDGE_LEDGER" 2>/dev/null)

if [[ "$total_tasks" -eq 0 ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

if [[ "$completed_tasks" -lt "$total_tasks" ]]; then
    remaining=$((total_tasks - completed_tasks))
    echo "{\"decision\": \"continue\", \"reason\": \"Phase $current_phase: $completed_tasks/$total_tasks tasks complete ($remaining remaining)\"}"
    exit 0
fi

# All tasks complete - evaluate quality gate
gate_threshold=$(jq -r ".phases.\"$current_phase\".gate.threshold // 0.75" "$BRIDGE_LEDGER" 2>/dev/null)

# Calculate completion ratio
completion_ratio=$(awk -v c="$completed_tasks" -v t="$total_tasks" 'BEGIN { printf "%.2f", c / t }')

gate_passed="false"
if awk -v r="$completion_ratio" -v t="$gate_threshold" 'BEGIN { exit !(r >= t) }'; then
    gate_passed="true"
fi

# Update gate result in ledger
tmp="${BRIDGE_LEDGER}.tmp.$$"
jq --arg phase "$current_phase" \
   --arg passed "$gate_passed" \
   --arg ratio "$completion_ratio" \
   '.phases[$phase].gate.status = "evaluated" |
    .phases[$phase].gate.result = {passed: ($passed == "true"), completion_ratio: ($ratio | tonumber)}' \
   "$BRIDGE_LEDGER" > "$tmp" 2>/dev/null && mv "$tmp" "$BRIDGE_LEDGER" || rm -f "$tmp"

# Update session.json if it exists
session_file="${HOME}/.claude-octopus/session.json"
if [[ -f "$session_file" ]]; then
    tmp="${session_file}.tmp.$$"
    jq --arg phase "$current_phase" \
       --arg status "completed" \
       --argjson completed "$completed_tasks" \
       '.phase_status = $status | .phase_tasks.completed = $completed' \
       "$session_file" > "$tmp" 2>/dev/null && mv "$tmp" "$session_file" || rm -f "$tmp"
fi

if [[ "$gate_passed" == "true" ]]; then
    echo "{\"decision\": \"continue\", \"reason\": \"Phase $current_phase complete: quality gate passed (${completion_ratio} >= ${gate_threshold})\"}"
else
    echo "{\"decision\": \"block\", \"reason\": \"Phase $current_phase: quality gate failed (${completion_ratio} < ${gate_threshold}). $completed_tasks/$total_tasks tasks completed.\"}"
fi

exit 0
