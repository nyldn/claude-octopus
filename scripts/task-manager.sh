#!/usr/bin/env bash
# Task Manager Helper - Claude Code v2.1.16+ Task Management Integration
# Provides task creation, updating, and tracking for multi-phase workflows

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Task state file (stores task IDs for the current session)
TASK_STATE_FILE="${HOME}/.claude-octopus/task-state-${CLAUDE_SESSION_ID:-default}.json"

# Initialize task state
init_task_state() {
    mkdir -p "$(dirname "$TASK_STATE_FILE")"
    if [[ ! -f "$TASK_STATE_FILE" ]]; then
        echo '{}' > "$TASK_STATE_FILE"
    fi
}

# Store task ID for a phase
store_task_id() {
    local phase="$1"
    local task_id="$2"

    init_task_state

    # Update JSON with new task ID
    local tmp_file="${TASK_STATE_FILE}.tmp"
    jq --arg phase "$phase" --arg id "$task_id" \
        '.[$phase] = $id' \
        "$TASK_STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$TASK_STATE_FILE"
}

# Get task ID for a phase
get_task_id() {
    local phase="$1"

    if [[ ! -f "$TASK_STATE_FILE" ]]; then
        echo ""
        return
    fi

    jq -r --arg phase "$phase" '.[$phase] // ""' "$TASK_STATE_FILE"
}

# Create workflow tasks for embrace (all 4 phases)
create_embrace_tasks() {
    local prompt="$1"

    echo -e "${CYAN}Creating workflow tasks...${NC}" >&2

    # Note: Actual TaskCreate calls should be made by Claude in the main context
    # This function outputs the task creation commands for Claude to execute

    cat <<'EOF'
# Task creation for Embrace workflow
# Claude should execute these TaskCreate calls:

TaskCreate({
  subject: "Discover Phase - Multi-AI Research",
  description: "Run multi-provider research using Codex, Gemini, and Claude for: PROMPT_PLACEHOLDER",
  activeForm: "Running Discover phase research"
})

TaskCreate({
  subject: "Define Phase - Consensus Building",
  description: "Build consensus on requirements and approach based on Discover findings",
  activeForm: "Building consensus in Define phase"
})

TaskCreate({
  subject: "Develop Phase - Implementation",
  description: "Implement solution with quality gates and multi-AI validation",
  activeForm: "Developing solution with quality checks"
})

TaskCreate({
  subject: "Deliver Phase - Final Validation",
  description: "Validate, review, and deliver final output with quality certification",
  activeForm: "Validating and delivering final output"
})
EOF
}

# Create a single phase task
create_phase_task() {
    local phase="$1"
    local prompt="$2"

    local subject activeForm description

    case "$phase" in
        probe|discover)
            subject="Discover Phase - Multi-AI Research"
            activeForm="Running multi-provider research"
            description="Multi-provider research (Codex + Gemini + Claude) for: $prompt"
            ;;
        grasp|define)
            subject="Define Phase - Consensus Building"
            activeForm="Building consensus on requirements"
            description="Building consensus on approach for: $prompt"
            ;;
        tangle|develop)
            subject="Develop Phase - Implementation"
            activeForm="Implementing with quality gates"
            description="Implementation with multi-AI validation for: $prompt"
            ;;
        ink|deliver)
            subject="Deliver Phase - Final Validation"
            activeForm="Validating and delivering output"
            description="Final validation and delivery for: $prompt"
            ;;
        *)
            echo "ERROR: Unknown phase: $phase" >&2
            return 1
            ;;
    esac

    # Output task creation command for Claude to execute
    cat <<EOF
TaskCreate({
  subject: "$subject",
  description: "$description",
  activeForm: "$activeForm"
})
EOF
}

# Get task status summary
get_task_status() {
    init_task_state

    local discover_id=$(get_task_id "discover")
    local define_id=$(get_task_id "define")
    local develop_id=$(get_task_id "develop")
    local deliver_id=$(get_task_id "deliver")

    local status_parts=()

    [[ -n "$discover_id" ]] && status_parts+=("Discover:$discover_id")
    [[ -n "$define_id" ]] && status_parts+=("Define:$define_id")
    [[ -n "$develop_id" ]] && status_parts+=("Develop:$develop_id")
    [[ -n "$deliver_id" ]] && status_parts+=("Deliver:$deliver_id")

    if [[ ${#status_parts[@]} -eq 0 ]]; then
        echo "No active tasks"
    else
        echo "${status_parts[*]}"
    fi
}

# Clean up task state for session
cleanup_task_state() {
    if [[ -f "$TASK_STATE_FILE" ]]; then
        rm -f "$TASK_STATE_FILE"
    fi
}

# Main command dispatcher
case "${1:-}" in
    create-embrace)
        create_embrace_tasks "$2"
        ;;
    create-phase)
        create_phase_task "$2" "$3"
        ;;
    store-id)
        store_task_id "$2" "$3"
        ;;
    get-id)
        get_task_id "$2"
        ;;
    get-status)
        get_task_status
        ;;
    cleanup)
        cleanup_task_state
        ;;
    *)
        cat <<EOF
Usage: task-manager.sh COMMAND [ARGS]

Commands:
  create-embrace PROMPT      Generate TaskCreate commands for all 4 phases
  create-phase PHASE PROMPT  Generate TaskCreate command for single phase
  store-id PHASE TASK_ID     Store task ID for phase
  get-id PHASE               Get task ID for phase
  get-status                 Get task status summary
  cleanup                    Clean up task state file

EOF
        exit 1
        ;;
esac
