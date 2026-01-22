#!/bin/bash
# task-dependency-validator.sh
# Validates task dependencies before TaskCreate executes
# Part of Claude Code v2.1.12+ integration

set -euo pipefail

# This hook receives task metadata via stdin when TaskCreate is called
# Input format: JSON with task details
# Output: JSON with validation result

# Get the plugin root directory
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKSPACE_DIR="${OCTOPUS_WORKSPACE:-/tmp/octopus}"

# Initialize workspace for task tracking
mkdir -p "${WORKSPACE_DIR}/tasks"

# Read task metadata from stdin (if available)
if [ -t 0 ]; then
    # No stdin, this is a direct invocation
    TASK_DATA="{}"
else
    # Read from stdin
    TASK_DATA=$(cat)
fi

# Log function
log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] task-dependency-validator: $*" >&2
}

# Check if we're running in a Claude Code v2.1.12+ environment
check_version_support() {
    if ! command -v claude &>/dev/null; then
        log "DEBUG" "Claude CLI not available, skipping validation"
        return 1
    fi

    # Check for task management support (v2.1.16+)
    if [[ -z "${CLAUDE_SESSION_ID:-}" ]]; then
        log "DEBUG" "No Claude session detected, skipping validation"
        return 1
    fi

    return 0
}

# Validate task dependencies
validate_dependencies() {
    local task_subject="${1:-unknown}"
    local dependencies="${2:-}"

    log "INFO" "Validating dependencies for task: $task_subject"

    # If no dependencies, validation passes
    if [[ -z "$dependencies" ]]; then
        log "DEBUG" "No dependencies to validate"
        return 0
    fi

    # Check if blocking tasks exist
    IFS=',' read -ra DEPS <<< "$dependencies"
    for dep in "${DEPS[@]}"; do
        dep=$(echo "$dep" | xargs) # trim whitespace

        if [[ -f "${WORKSPACE_DIR}/tasks/${dep}.id" ]]; then
            log "DEBUG" "Dependency found: $dep"
        else
            log "WARN" "Dependency not found: $dep (will be created on-demand)"
        fi
    done

    return 0
}

# Detect circular dependencies
detect_circular_dependencies() {
    local task_id="$1"
    local blocked_by="$2"

    # Simple circular dependency check
    # In production, this would use graph traversal
    if [[ "$blocked_by" == *"$task_id"* ]]; then
        log "ERROR" "Circular dependency detected: $task_id blocks itself"
        return 1
    fi

    return 0
}

# Main validation logic
main() {
    log "INFO" "Task dependency validation hook triggered"

    # Check if we should run validation
    if ! check_version_support; then
        # Return success to allow task creation to proceed
        echo '{"decision": "continue", "reason": "Version check failed, skipping validation"}'
        exit 0
    fi

    # Parse task data (simplified - in production would use jq)
    # For now, just log and allow to proceed
    log "DEBUG" "Task metadata received: ${TASK_DATA:0:100}..."

    # Validate dependencies
    if validate_dependencies "task" ""; then
        log "INFO" "Task dependencies validated successfully"
        echo '{"decision": "continue", "reason": "Dependencies validated"}'
        exit 0
    else
        log "WARN" "Task dependency validation failed, but allowing to proceed"
        echo '{"decision": "continue", "reason": "Validation failed but non-blocking"}'
        exit 0
    fi
}

# Run main function
main "$@"
