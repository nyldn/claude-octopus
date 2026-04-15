#!/usr/bin/env bash
# Cursor Agent CLI provider execution (v9.23.0)
# Uses `agent -p` headless mode with --trust to skip workspace prompts.
# Auth: Cursor OAuth session (via `agent login`), stored in ~/.cursor/
# Unique models: grok-4-20, grok-4-20-thinking, composer-2-fast, composer-2
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

# Verify that `agent` binary is actually Cursor Agent CLI (not some other tool)
# The binary name is generic; check version output for Cursor identity
_is_cursor_agent_binary() {
    local version_output
    version_output=$(agent --version 2>&1) || return 1
    # Cursor Agent versions look like: 2026.04.14-ee4b43a
    [[ "$version_output" =~ ^20[0-9]{2}\. ]] && return 0
    return 1
}

# Check if Cursor Agent CLI is available and authenticated
# Returns 0 if ready, 1 if not
cursor_agent_is_available() {
    if ! command -v agent &>/dev/null; then
        return 1
    fi
    # Verify binary identity — `agent` is a generic name
    if ! _is_cursor_agent_binary; then
        return 1
    fi
    # Check auth: env var first (fast), then Cursor config paths
    if [[ -n "${CURSOR_API_KEY:-}" ]]; then
        return 0
    fi
    # Cursor stores auth state in ~/.cursor/ (shared with Cursor IDE)
    if [[ -f "${HOME}/.cursor/agent-cli-state.json" ]]; then
        return 0
    fi
    return 1
}

# Get the auth method currently in use (for doctor/setup reporting)
# Returns: "env:CURSOR_API_KEY", "cursor-session", or "none"
cursor_agent_auth_method() {
    if [[ -n "${CURSOR_API_KEY:-}" ]]; then
        echo "env:CURSOR_API_KEY"
    elif [[ -f "${HOME}/.cursor/agent-cli-state.json" ]]; then
        echo "cursor-session"
    else
        echo "none"
    fi
}

# Execute a prompt via Cursor Agent CLI headless mode
# Args: $1=agent_type (e.g. cursor-agent), $2=prompt, $3=output_file (optional)
cursor_agent_execute() {
    local agent_type="$1"
    local prompt="$2"
    local output_file="${3:-}"

    if ! command -v agent &>/dev/null; then
        log ERROR "cursor-agent: CLI not found — install: curl -fsSL https://cursor.com/install | bash"
        return 1
    fi

    local timeout="${OCTOPUS_CURSOR_TIMEOUT:-120}"

    [[ "${VERBOSE:-}" == "true" ]] && log DEBUG "cursor_agent_execute: type=$agent_type, timeout=${timeout}s, auth=$(cursor_agent_auth_method)" || true

    # Note: --model is set by dispatch.sh via get_agent_command(), not here
    local response exit_code
    response=$(timeout "$timeout" agent -p "$prompt" --trust --output-format text 2>&1) && exit_code=0 || exit_code=$?

    # Handle errors
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 124 ]]; then
            log WARN "cursor-agent: Timed out after ${timeout}s"
            return 1
        fi
        # Check for auth errors
        if printf '%s' "$response" | grep -qiE 'unauthorized|auth|login|token|forbidden'; then
            log ERROR "cursor-agent: Auth failure — run: agent login (or set CURSOR_API_KEY)"
            return 1
        fi
        log WARN "cursor-agent: Exit code $exit_code"
        # Still return output if we got some (non-zero exit can include useful output)
    fi

    if [[ -z "$response" ]]; then
        log WARN "cursor-agent: Empty response"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        printf '%s\n' "$response" > "$output_file"
    else
        printf '%s\n' "$response"
    fi
}
