#!/usr/bin/env bash
# Session Manager - Claude Code v2.1.9+ Session Variable Integration
# Provides session tracking and provider-specific session isolation

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Export session variables for Claude Code v2.1.9+
export_session_variables() {
    # Use CLAUDE_SESSION_ID if available, otherwise generate
    if [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
        export OCTOPUS_SESSION_ID="$CLAUDE_SESSION_ID"
    else
        export OCTOPUS_SESSION_ID="octopus-$(date +%s)"
    fi

    # Provider-specific session IDs
    export OCTOPUS_CODEX_SESSION="codex-${OCTOPUS_SESSION_ID}"
    export OCTOPUS_GEMINI_SESSION="gemini-${OCTOPUS_SESSION_ID}"
    export OCTOPUS_CLAUDE_SESSION="claude-${OCTOPUS_SESSION_ID}"

    # Session directories
    export OCTOPUS_SESSION_DIR="${HOME}/.claude-octopus/sessions/${OCTOPUS_SESSION_ID}"
    export OCTOPUS_SESSION_RESULTS="${OCTOPUS_SESSION_DIR}/results"
    export OCTOPUS_SESSION_LOGS="${OCTOPUS_SESSION_DIR}/logs"
    export OCTOPUS_SESSION_PLANS="${OCTOPUS_SESSION_DIR}/plans"

    # Create session directories
    mkdir -p "$OCTOPUS_SESSION_RESULTS" "$OCTOPUS_SESSION_LOGS" "$OCTOPUS_SESSION_PLANS"

    # Write session metadata
    cat > "${OCTOPUS_SESSION_DIR}/.session-metadata.json" <<EOF
{
  "session_id": "$OCTOPUS_SESSION_ID",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "providers": {
    "codex": "$OCTOPUS_CODEX_SESSION",
    "gemini": "$OCTOPUS_GEMINI_SESSION",
    "claude": "$OCTOPUS_CLAUDE_SESSION"
  },
  "directories": {
    "results": "$OCTOPUS_SESSION_RESULTS",
    "logs": "$OCTOPUS_SESSION_LOGS",
    "plans": "$OCTOPUS_SESSION_PLANS"
  }
}
EOF
}

# Get session info
get_session_info() {
    if [[ -z "${OCTOPUS_SESSION_ID:-}" ]]; then
        echo "No active session"
        return 1
    fi

    echo "Session ID: $OCTOPUS_SESSION_ID"
    echo "Results: $OCTOPUS_SESSION_RESULTS"
    echo "Logs: $OCTOPUS_SESSION_LOGS"
    echo ""
    echo "Provider Sessions:"
    echo "  🔴 Codex:  $OCTOPUS_CODEX_SESSION"
    echo "  🟡 Gemini: $OCTOPUS_GEMINI_SESSION"
    echo "  🔵 Claude: $OCTOPUS_CLAUDE_SESSION"
}

# Clean up old sessions (keep last 10)
cleanup_old_sessions() {
    local sessions_dir="${HOME}/.claude-octopus/sessions"
    if [[ ! -d "$sessions_dir" ]]; then
        return 0
    fi

    # Keep 10 most recent sessions, delete the rest
    local count=0
    for session_dir in $(ls -dt "$sessions_dir"/*/ 2>/dev/null); do
        ((count++))
        if [[ $count -gt 10 ]]; then
            echo "Removing old session: $(basename "$session_dir")"
            rm -rf "$session_dir"
        fi
    done
}

# Main command dispatcher
case "${1:-}" in
    export)
        export_session_variables
        ;;
    info)
        get_session_info
        ;;
    cleanup)
        cleanup_old_sessions
        ;;
    *)
        cat <<EOF
Usage: session-manager.sh COMMAND

Commands:
  export    Export session variables (OCTOPUS_SESSION_ID, provider sessions, etc.)
  info      Display current session information
  cleanup   Remove old sessions (keep last 10)

EOF
        exit 1
        ;;
esac
