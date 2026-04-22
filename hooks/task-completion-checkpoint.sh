#!/bin/bash
# task-completion-checkpoint.sh
# Creates checkpoint when tasks complete for session resumption
# Part of Claude Code v2.1.12+ integration

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Get the plugin root directory
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKSPACE_DIR="${OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus/workspace}"
CHECKPOINT_DIR="${WORKSPACE_DIR}/checkpoints"

# Initialize checkpoint directory
mkdir -p "${CHECKPOINT_DIR}"

# Log function
log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] task-completion-checkpoint: $*" >&2
}

# Read task update data from stdin (if available)
if [ -t 0 ]; then
    TASK_DATA="{}"
else
    if command -v timeout &>/dev/null; then
        TASK_DATA=$(timeout 3 cat 2>/dev/null || true)
    else
        TASK_DATA=$(cat 2>/dev/null || true)
    fi
    [[ -z "$TASK_DATA" ]] && TASK_DATA='{}'
fi

# v8.29.0: Capture last assistant message for phase context recovery
LAST_MESSAGE=""
if [[ "${SUPPORTS_HOOK_LAST_MESSAGE:-false}" == "true" && -n "$TASK_DATA" ]]; then
    LAST_MESSAGE=$(echo "$TASK_DATA" | grep -o '"last_assistant_message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null | head -c 500 || true)
fi

# Create checkpoint file
create_checkpoint() {
    local task_id="${1:-unknown}"
    local status="${2:-completed}"
    local timestamp=$(date +%s)

    local checkpoint_file="${CHECKPOINT_DIR}/${task_id}.checkpoint"

    log "INFO" "Creating checkpoint for task: $task_id (status: $status)"

    # Add last message summary to checkpoint if available
    local ESCAPED_MESSAGE=""
    if [[ -n "$LAST_MESSAGE" ]]; then
        ESCAPED_MESSAGE=$(printf '%s' "$LAST_MESSAGE" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null | sed 's/^"//;s/"$//' || echo "$LAST_MESSAGE")
    fi

    # Write checkpoint data
    cat > "$checkpoint_file" <<EOF
{
  "task_id": "$task_id",
  "status": "$status",
  "timestamp": $timestamp,
  "session_id": "${CLAUDE_SESSION_ID:-unknown}",
  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_message_summary": "${ESCAPED_MESSAGE:-}"
}
EOF

    log "INFO" "Checkpoint created: $checkpoint_file"
}

# Trigger dependent task notifications
notify_dependent_tasks() {
    local completed_task="$1"

    log "INFO" "Checking for tasks blocked by: $completed_task"

    # Look for tasks that were blocked by this one
    local tasks_dir="${WORKSPACE_DIR}/tasks"
    if [[ -d "$tasks_dir" ]]; then
        for task_file in "$tasks_dir"/*.blockedby; do
            if [[ -f "$task_file" ]] && grep -q "$completed_task" "$task_file"; then
                local blocked_task=$(basename "$task_file" .blockedby)
                log "INFO" "Task $blocked_task is now unblocked"

                # Create unblock notification
                echo "$completed_task" >> "${tasks_dir}/${blocked_task}.unblocked"
            fi
        done
    fi
}

# Update session state
update_session_state() {
    local session_state="${WORKSPACE_DIR}/session.state"

    log "INFO" "Updating session state"

    # Count completed tasks
    local completed_count=$(find "$CHECKPOINT_DIR" -name "*.checkpoint" 2>/dev/null | wc -l | xargs)

    # Update state file
    cat > "$session_state" <<EOF
{
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "completed_tasks": $completed_count,
  "session_id": "${CLAUDE_SESSION_ID:-unknown}"
}
EOF

    log "INFO" "Session state updated: $completed_count tasks completed"
}

# Main checkpoint logic
main() {
    log "INFO" "Task completion checkpoint hook triggered"

    # Parse task data (simplified)
    log "DEBUG" "Task update data: ${TASK_DATA:0:100}..."

    # Extract task ID from metadata (in production, would use jq)
    # For now, create checkpoint with timestamp
    local task_id="task-$(date +%s)"

    # Create checkpoint
    create_checkpoint "$task_id" "completed"

    # Notify dependent tasks
    notify_dependent_tasks "$task_id"

    # Update session state
    update_session_state

    log "INFO" "Checkpoint complete"
    exit 0
}

# Run main function
main "$@"
