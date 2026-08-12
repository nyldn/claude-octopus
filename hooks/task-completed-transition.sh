#!/usr/bin/env bash
# TaskCompleted Hook Handler - Claude Code v2.1.33+
# Manages phase transitions when workflow tasks complete
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


SESSION_FILE="${HOME}/.claude-octopus/session.json"

# Only act if an active workflow session exists
if [[ ! -f "$SESSION_FILE" ]]; then
    exit 0
fi

# Check if jq is available
if ! command -v jq &>/dev/null; then
    exit 0
fi

if ! jq -e 'type == "object"' "$SESSION_FILE" >/dev/null 2>&1; then
    exit 0
fi

_update_session_state() {
    local filter="$1"
    shift
    local session_tmp=""
    session_tmp=$(mktemp "${SESSION_FILE}.tmp.XXXXXX") || return 1
    if jq "$@" "$filter" "$SESSION_FILE" > "$session_tmp" 2>/dev/null &&
       mv "$session_tmp" "$SESSION_FILE" 2>/dev/null; then
        return 0
    fi
    rm -f "$session_tmp"
    return 1
}

CURRENT_PHASE=$(jq -r '.phase // empty' "$SESSION_FILE" 2>/dev/null)
if [[ -z "$CURRENT_PHASE" ]]; then
    exit 0
fi

# Increment completed task count
COMPLETED=$(jq -r '.phase_tasks.completed // 0' "$SESSION_FILE" 2>/dev/null)
TOTAL=$(jq -r '.phase_tasks.total // 0' "$SESSION_FILE" 2>/dev/null)
AUTONOMY=$(jq -r '.autonomy // "supervised"' "$SESSION_FILE" 2>/dev/null)

# A phase can be visible before its task ledger is initialized. Treat missing,
# zero, or non-integer totals as no work instead of incrementing stale state and
# dividing by zero in the progress message (#894).
if [[ ! "$COMPLETED" =~ ^[0-9]+$ || ! "$TOTAL" =~ ^[0-9]+$ || "$TOTAL" -eq 0 ]]; then
    exit 0
fi
COMPLETED=$((COMPLETED + 1))

_update_session_state '.phase_tasks.completed = $completed' \
    --argjson completed "$COMPLETED" || exit 0

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
        _update_session_state '.phase = "complete" | .workflow_status = "finished"' || exit 0
    else
        case "$AUTONOMY" in
            autonomous|semi-autonomous)
                # Auto-transition to next phase
                _update_session_state \
                    '.phase = $next_phase | .phase_tasks = {"total": 0, "completed": 0}' \
                    --arg next_phase "$NEXT_PHASE" || exit 0
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
