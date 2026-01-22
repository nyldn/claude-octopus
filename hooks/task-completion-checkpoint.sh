#!/bin/bash
# task-completion-checkpoint.sh
# Creates checkpoint when tasks complete for session resumption
# Part of Claude Code v2.1.12+ integration

set -euo pipefail

# Get the plugin root directory
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKSPACE_DIR="${OCTOPUS_WORKSPACE:-/tmp/octopus}"
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
    TASK_DATA=$(cat)
fi

# Create checkpoint file
create_checkpoint() {
    local task_id="${1:-unknown}"
    local status="${2:-completed}"
    local timestamp=$(date +%s)

    local checkpoint_file="${CHECKPOINT_DIR}/${task_id}.checkpoint"

    log "INFO" "Creating checkpoint for task: $task_id (status: $status)"

    # Write checkpoint data
    cat > "$checkpoint_file" <<EOF
{
  "task_id": "$task_id",
  "status": "$status",
  "timestamp": $timestamp,
  "session_id": "${CLAUDE_SESSION_ID:-unknown}",
  "completed_at": "$(date -Iseconds)"
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
  "last_updated": "$(date -Iseconds)",
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
