#!/usr/bin/env bash
# Cursor Agent CLI provider execution (v9.23.0)
# NOTE: no top-level `set -e*` — sourced libs must not alter parent shell options
# (per upstream cfaf6871 fix(#269)). orchestrate.sh already sets `set -eo pipefail`.

# Internal log helper — proxies to orchestrate.sh's log() if available, otherwise
# prints level-prefixed messages to stderr so this file is safe to source standalone.
_cursor_log() {
    if declare -f log >/dev/null 2>&1; then
        log "$@"
    else
        echo "[${1}] ${*:2}" >&2
    fi
}
# Uses `agent -p` headless mode with --trust to skip workspace prompts.
# Auth: Cursor OAuth session (via `agent login`), stored in ~/.cursor/
# Unique models: grok-4-20, grok-4-20-thinking, composer-2-fast, composer-2
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

# Cursor Agent CLI binary identity check
#
# Version format: CalVer (YYYY.MM.DD-hash), e.g. "2026.04.14-ee4b43a"
# Detection regex: ^20[0-9]{2}\.  (year 20xx followed by dot)
#
# Why this pattern (not semver): the binary name "agent" is generic and could
# collide with other tools. Cursor's calendar-versioning is distinctive enough
# to disambiguate; semver-style "1.x.y" outputs are intentionally rejected.
#
# If Cursor changes versioning scheme, update both this regex and the
# corresponding checks in: preflight.sh, embrace.sh, build-fleet.sh,
# model-resolver.sh (is_agent_available_v2 cursor-agent case).
_is_cursor_agent_binary() {
    local version_output
    # Wrap with timeout: an unrelated `agent` binary on PATH could hang on stdin
    # or spawn an interactive session, blocking every caller (cursor_agent_is_available,
    # preflight, doctor, smoke, build-fleet). Redirect stdin to /dev/null too.
    if command -v timeout &>/dev/null; then
        version_output=$(timeout 3 agent --version </dev/null 2>&1) || return 1
    elif command -v gtimeout &>/dev/null; then
        version_output=$(gtimeout 3 agent --version </dev/null 2>&1) || return 1
    else
        version_output=$(agent --version </dev/null 2>&1) || return 1
    fi
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
        _cursor_log ERROR "cursor-agent: CLI not found — install: curl -fsSL https://cursor.com/install | bash"
        return 1
    fi
    if ! _is_cursor_agent_binary; then
        _cursor_log ERROR "cursor-agent: 'agent' binary on PATH is not Cursor Agent CLI"
        return 1
    fi

    local timeout="${OCTOPUS_CURSOR_AGENT_TIMEOUT:-120}"

    [[ "${VERBOSE:-}" == "true" ]] && _cursor_log DEBUG "cursor_agent_execute: type=$agent_type, timeout=${timeout}s, auth=$(cursor_agent_auth_method)" || true

    # Note: --model is set by dispatch.sh via get_agent_command(), not here
    # Guard for timeout availability (GNU coreutils; not on stock macOS)
    local response exit_code
    if command -v timeout &>/dev/null; then
        response=$(timeout "$timeout" agent -p "$prompt" --trust --output-format text 2>&1) && exit_code=0 || exit_code=$?
    elif command -v gtimeout &>/dev/null; then
        response=$(gtimeout "$timeout" agent -p "$prompt" --trust --output-format text 2>&1) && exit_code=0 || exit_code=$?
    else
        # No timeout binary — run without timeout protection
        response=$(agent -p "$prompt" --trust --output-format text 2>&1) && exit_code=0 || exit_code=$?
    fi

    # Handle errors
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 124 ]]; then
            _cursor_log WARN "cursor-agent: Timed out after ${timeout}s"
            return 1
        fi
        # Check for auth errors
        if printf '%s' "$response" | grep -ciE 'unauthorized|auth|login|token|forbidden' >/dev/null; then
            _cursor_log ERROR "cursor-agent: Auth failure — run: agent login (or set CURSOR_API_KEY)"
            return 1
        fi
        _cursor_log WARN "cursor-agent: Exit code $exit_code"
        # Still return output if we got some (non-zero exit can include useful output)
    fi

    if [[ -z "$response" ]]; then
        _cursor_log WARN "cursor-agent: Empty response"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        printf '%s\n' "$response" > "$output_file"
    else
        printf '%s\n' "$response"
    fi

    if [[ $exit_code -ne 0 ]]; then
        return "$exit_code"
    fi

    return 0
}
