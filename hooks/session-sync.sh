#!/bin/bash
# Claude Octopus Session Sync Hook
# Propagates Claude Code session ID to spawned agents
# Enables session tracking and result aggregation

SESSION_ID="${CLAUDE_SESSION_ID:-}"

if [[ -z "$SESSION_ID" ]]; then
    # No session ID available - continue without sync
    echo '{"decision": "continue", "reason": "No Claude Code session ID available"}'
    exit 0
fi

# Session ID is available - propagate to agent environment
export CLAUDE_OCTOPUS_SESSION_ID="$SESSION_ID"

# Log session sync for debugging
if [[ "${VERBOSE:-false}" == "true" ]]; then
    echo "[Session Sync] Propagating session ID: $SESSION_ID" >&2
fi

echo '{"decision": "continue", "session_id": "'"$SESSION_ID"'"}'
exit 0
