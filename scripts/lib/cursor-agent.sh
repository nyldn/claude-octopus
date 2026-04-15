#!/usr/bin/env bash
# Cursor Agent CLI provider execution (v9.23.0)
# Uses `agent -p` headless mode with --trust to skip workspace prompts.
# Auth: Cursor OAuth session (via `agent login`)
# Unique models: grok-4-20, grok-4-20-thinking, composer-2-fast, composer-2, kimi-k2.5
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

# Check if Cursor Agent CLI is available and authenticated
# Returns 0 if ready, 1 if not
cursor_agent_is_available() {
    if ! command -v agent &>/dev/null; then
        return 1
    fi
    # Check auth: env var first (fast), then config dirs
    if [[ -n "${CURSOR_API_KEY:-}" ]]; then
        return 0
    fi
    if [[ -f "${HOME}/.cursor-agent/config.json" ]]; then
        return 0
    fi
    if [[ -f "${HOME}/.cursor-agent/credentials.json" ]]; then
        return 0
    fi
    return 1
}

# Get the auth method currently in use (for doctor/setup reporting)
# Returns: "env:CURSOR_API_KEY", "config", "credentials", or "none"
cursor_agent_auth_method() {
    if [[ -n "${CURSOR_API_KEY:-}" ]]; then
        echo "env:CURSOR_API_KEY"
    elif [[ -f "${HOME}/.cursor-agent/config.json" ]]; then
        echo "config"
    elif [[ -f "${HOME}/.cursor-agent/credentials.json" ]]; then
        echo "credentials"
    else
        echo "none"
    fi
}

# Execute a prompt via Cursor Agent CLI headless mode
# Args: $1=agent_type (e.g. cursor-agent, cursor-agent-grok), $2=prompt, $3=output_file (optional)
cursor_agent_execute() {
    local agent_type="$1"
    local prompt="$2"
    local output_file="${3:-}"

    if ! command -v agent &>/dev/null; then
        log ERROR "cursor-agent: CLI not found — install: curl -fsSL https://cursor.com/install | bash"
        return 1
    fi

    local timeout="${OCTOPUS_CURSOR_TIMEOUT:-120}"
    local model="${OCTOPUS_CURSOR_MODEL:-grok-4-20}"

    [[ "${VERBOSE:-}" == "true" ]] && log DEBUG "cursor_agent_execute: type=$agent_type, model=$model, timeout=${timeout}s, auth=$(cursor_agent_auth_method)" || true

    local response exit_code
    response=$(timeout "$timeout" agent -p "$prompt" --trust --model "$model" --output-format text 2>&1) && exit_code=0 || exit_code=$?

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
