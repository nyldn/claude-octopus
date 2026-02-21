#!/usr/bin/env bash
# TeammateIdle Hook Handler - Claude Code v2.1.33+
# Dispatches queued work to idle agents during multi-agent workflows
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SESSION_FILE="${HOME}/.claude-octopus/session.json"

# Only act if an active workflow session exists
if [[ ! -f "$SESSION_FILE" ]]; then
    exit 0
fi

# Check if jq is available
if ! command -v jq &>/dev/null; then
    exit 0
fi

CURRENT_PHASE=$(jq -r '.phase // empty' "$SESSION_FILE" 2>/dev/null)
if [[ -z "$CURRENT_PHASE" ]]; then
    exit 0
fi

QUEUE_LENGTH=$(jq -r '.agent_queue // [] | length' "$SESSION_FILE" 2>/dev/null)

if [[ "$QUEUE_LENGTH" -gt 0 ]]; then
    # Dequeue next task
    NEXT_TASK=$(jq -r '.agent_queue[0].task // "No task description"' "$SESSION_FILE" 2>/dev/null)
    NEXT_ROLE=$(jq -r '.agent_queue[0].role // "general"' "$SESSION_FILE" 2>/dev/null)

    # Remove from queue
    jq '.agent_queue = .agent_queue[1:]' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
        && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

    # Track idle event in metrics
    METRICS_DIR="${HOME}/.claude-octopus/metrics"
    mkdir -p "$METRICS_DIR"
    echo "{\"event\":\"teammate_idle\",\"phase\":\"$CURRENT_PHASE\",\"dispatched_task\":\"$NEXT_TASK\",\"dispatched_role\":\"$NEXT_ROLE\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
        >> "${METRICS_DIR}/idle-events.jsonl"

    # Feed task back to teammate via stderr (stdout is not returned to Claude)
    # Exit code 2 = "don't go idle, here's more work" with stderr as feedback
    echo "🐙 TeammateIdle: Dispatching queued task to idle agent" >&2
    echo "Phase: $CURRENT_PHASE | Role: $NEXT_ROLE | Queue remaining: $((QUEUE_LENGTH - 1))" >&2
    echo "" >&2
    echo "Your next task: $NEXT_TASK" >&2
    exit 2
else
    # No more work - check if phase should transition
    COMPLETED=$(jq -r '.phase_tasks.completed // 0' "$SESSION_FILE" 2>/dev/null)
    TOTAL=$(jq -r '.phase_tasks.total // 0' "$SESSION_FILE" 2>/dev/null)

    if [[ "$COMPLETED" -ge "$TOTAL" ]] && [[ "$TOTAL" -gt 0 ]]; then
        echo "🐙 TeammateIdle: All phase tasks complete. Ready for phase transition."
    fi
fi
