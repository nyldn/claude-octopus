#!/usr/bin/env bash
# Session Manager - Claude Code v2.1.9+ Session Variable Integration
# Provides session tracking and provider-specific session isolation

set -eo pipefail

# Resolve physical path so the fallback `dirname "$SCRIPT_DIR"` plugin_root
# (used when CLAUDE_PLUGIN_ROOT is unset) is the real install path rather than
# the convenience symlink — prevents self-referential symlink creation. See #371.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/lib/session-id.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/plugin-root.sh" 2>/dev/null || true

# Export session variables for Claude Code v2.1.9+
export_session_variables() {
    # Use Claude Code's official Bash session ID if available, otherwise generate.
    if declare -f octo_resolve_session_id >/dev/null 2>&1; then
        export OCTOPUS_SESSION_ID
        OCTOPUS_SESSION_ID=$(octo_resolve_session_id "octopus-$(date +%s)")
    elif [[ -n "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}" ]]; then
        export OCTOPUS_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
    else
        export OCTOPUS_SESSION_ID="octopus-$(date +%s)"
    fi

    # Provider-specific session IDs
    export OCTOPUS_CODEX_SESSION="codex-${OCTOPUS_SESSION_ID}"
    export OCTOPUS_CLAUDE_SESSION="claude-${OCTOPUS_SESSION_ID}"

    # Bridge CLAUDE_PLUGIN_ROOT to a stable symlink for LLM Bash tool access.
    # CLAUDE_PLUGIN_ROOT is set by Claude Code for hook execution but NOT
    # available in the LLM's Bash shell. This symlink makes all skill
    # references to ${HOME}/.claude-octopus/plugin/scripts/... resolve correctly.
    # Created BEFORE session directories so the symlink exists even if mkdir fails.
    #
    # IMPORTANT: canonicalize plugin_root to its physical path before passing
    # to the self-heal. Claude Code may set CLAUDE_PLUGIN_ROOT to the stable
    # symlink path itself, which would otherwise cause octo_ensure_stable_plugin_root
    # to recreate the symlink pointing at itself (ELOOP). See #371.
    local plugin_root_raw="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
    local plugin_root
    plugin_root="$(cd "$plugin_root_raw" 2>/dev/null && pwd -P)" || plugin_root="$plugin_root_raw"
    if declare -f octo_ensure_stable_plugin_root >/dev/null 2>&1; then
        octo_ensure_stable_plugin_root "$plugin_root" >/dev/null 2>&1 || true
    else
        mkdir -p "${HOME}/.claude-octopus"
        ln -sfn "$plugin_root" "${HOME}/.claude-octopus/plugin"
    fi

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
        ((count++)) || true
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
