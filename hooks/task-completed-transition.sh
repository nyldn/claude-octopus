#!/usr/bin/env bash
# TaskCompleted Hook Handler - Claude Code v2.1.33+
# Manages phase transitions when workflow tasks complete
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

# Increment completed task count
COMPLETED=$(jq -r '.phase_tasks.completed // 0' "$SESSION_FILE" 2>/dev/null)
TOTAL=$(jq -r '.phase_tasks.total // 0' "$SESSION_FILE" 2>/dev/null)
AUTONOMY=$(jq -r '.autonomy // "supervised"' "$SESSION_FILE" 2>/dev/null)
COMPLETED=$((COMPLETED + 1))

jq ".phase_tasks.completed = $COMPLETED" "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
    && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

# Record metrics
METRICS_DIR="${HOME}/.claude-octopus/metrics"
mkdir -p "$METRICS_DIR"
echo "{\"event\":\"task_completed\",\"phase\":\"$CURRENT_PHASE\",\"completed\":$COMPLETED,\"total\":$TOTAL,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    >> "${METRICS_DIR}/completion-events.jsonl"

# Check if phase is complete
if [[ "$COMPLETED" -ge "$TOTAL" ]] && [[ "$TOTAL" -gt 0 ]]; then
    # Determine next phase
    case "$CURRENT_PHASE" in
        probe)  NEXT_PHASE="grasp" ;;
        grasp)  NEXT_PHASE="tangle" ;;
        tangle) NEXT_PHASE="ink" ;;
        ink)    NEXT_PHASE="complete" ;;
        *)      NEXT_PHASE="unknown" ;;
    esac

    # Record phase completion
    RESULTS_DIR="${HOME}/.claude-octopus/results"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    echo "{\"phase\":\"$CURRENT_PHASE\",\"completed_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"tasks_completed\":$COMPLETED,\"next_phase\":\"$NEXT_PHASE\"}" \
        > "${RESULTS_DIR}/${CURRENT_PHASE}-complete-${TIMESTAMP}.json" 2>/dev/null || true

    if [[ "$NEXT_PHASE" == "complete" ]]; then
        echo "🐙 TaskCompleted: All workflow phases complete! ✅"
        jq '.phase = "complete" | .workflow_status = "finished"' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
            && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
    else
        case "$AUTONOMY" in
            autonomous|semi-autonomous)
                # Auto-transition to next phase
                jq ".phase = \"$NEXT_PHASE\" | .phase_tasks = {\"total\": 0, \"completed\": 0}" \
                    "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
                    && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
                echo "🐙 TaskCompleted: Phase '$CURRENT_PHASE' complete → Auto-transitioning to '$NEXT_PHASE'"
                ;;
            *)
                # Supervised mode - signal but don't auto-transition
                echo "🐙 TaskCompleted: Phase '$CURRENT_PHASE' complete ($COMPLETED/$TOTAL tasks)."
                echo "   Next phase: '$NEXT_PHASE' — awaiting user approval to proceed."
                ;;
        esac
    fi
else
    PROGRESS_PCT=$((COMPLETED * 100 / TOTAL))
    echo "🐙 TaskCompleted: Phase '$CURRENT_PHASE' progress: $COMPLETED/$TOTAL ($PROGRESS_PCT%)"
fi
