#!/bin/bash
# Claude Octopus Scheduler - Security Gate Hook (v8.15.0)
# PreToolUse hook active when OCTOPUS_JOB_ID is set.
# Blocks tools not in the job's allowed list and restricts filesystem access.
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}

set -euo pipefail

# Only active during scheduled job execution
if [[ -z "${OCTOPUS_JOB_ID:-}" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

# Read tool input from stdin
INPUT=$(cat 2>/dev/null || echo '{}')

SCHEDULER_DIR="${HOME}/.claude-octopus/scheduler"
JOB_FILE="${SCHEDULER_DIR}/jobs/${OCTOPUS_JOB_ID}.json"

# If job file not found, block for safety
if [[ ! -f "$JOB_FILE" ]]; then
    echo "{\"decision\": \"block\", \"reason\": \"Scheduler security gate: job file not found for ${OCTOPUS_JOB_ID}\"}"
    exit 0
fi

# Get workspace from job definition
WORKSPACE=$(jq -r '.execution.workspace // ""' "$JOB_FILE" 2>/dev/null)

# Get tool name from hook input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Block dangerous flags in Bash commands
if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

    # Block --dangerously-skip-permissions in any form
    if echo "$COMMAND" | grep -qi 'dangerously.skip.permissions'; then
        echo '{"decision": "block", "reason": "Scheduler security gate: --dangerously-skip-permissions is prohibited in scheduled jobs"}'
        exit 0
    fi

    # Block rm -rf on sensitive paths
    if echo "$COMMAND" | grep -qE 'rm\s+-[a-zA-Z]*r[a-zA-Z]*f.*(/|~|\$HOME)'; then
        echo '{"decision": "block", "reason": "Scheduler security gate: destructive rm -rf on sensitive path blocked"}'
        exit 0
    fi
fi

# Validate file access is within workspace (for Read, Write, Edit tools)
if [[ "$TOOL_NAME" == "Read" ]] || [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    if [[ -n "$WORKSPACE" ]]; then
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")

        if [[ -n "$FILE_PATH" ]]; then
            # Resolve to absolute path for comparison
            resolved_path=$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && echo "$(pwd)/$(basename "$FILE_PATH")" || echo "$FILE_PATH")

            # Allow access to workspace and scheduler dirs
            if [[ "$resolved_path" != "${WORKSPACE}"* ]] && \
               [[ "$resolved_path" != "${HOME}/.claude-octopus"* ]] && \
               [[ "$resolved_path" != "${HOME}/.claude"* ]]; then
                echo "{\"decision\": \"block\", \"reason\": \"Scheduler security gate: file access outside workspace blocked: ${FILE_PATH}\"}"
                exit 0
            fi
        fi
    fi
fi

echo '{"decision": "continue"}'
exit 0
