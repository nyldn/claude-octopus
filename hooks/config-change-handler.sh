#!/bin/bash
# Claude Octopus ConfigChange Hook Handler
# Triggered when Claude Code configuration changes (v2.1.49+)
# Re-detects fast mode and logs changes for debugging

# Read config change info from stdin (JSON payload from Claude Code)
CONFIG_CHANGE_DATA=""
if [[ ! -t 0 ]]; then
    CONFIG_CHANGE_DATA="$(cat)"
fi

SESSION_ID="${CLAUDE_SESSION_ID:-}"
WORKFLOW_PHASE="${OCTOPUS_WORKFLOW_PHASE:-unknown}"

# Log the change for debugging
if [[ "${VERBOSE:-false}" == "true" ]]; then
    echo "[ConfigChange] Session: $SESSION_ID, Phase: $WORKFLOW_PHASE" >&2
    if [[ -n "$CONFIG_CHANGE_DATA" ]]; then
        echo "[ConfigChange] Data: $CONFIG_CHANGE_DATA" >&2
    fi
fi

# Re-detect fast mode if settings changed (the /fast toggle may have been flipped)
if [[ -n "$CONFIG_CHANGE_DATA" ]]; then
    # Check if fast mode setting is in the change payload
    if echo "$CONFIG_CHANGE_DATA" | grep -q '"fast"' 2>/dev/null; then
        if [[ "${VERBOSE:-false}" == "true" ]]; then
            echo "[ConfigChange] Fast mode setting changed, will re-detect on next orchestration" >&2
        fi
    fi
fi

echo '{"decision": "continue"}'
exit 0
