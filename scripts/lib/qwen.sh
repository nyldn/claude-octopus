#!/usr/bin/env bash
# Qwen CLI provider execution (v9.10.0)
# Fork of Gemini CLI — same flags, different binary.
# Auth: Qwen OAuth free tier (1000-2000 req/day), stored in ~/.qwen/
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

# Get the auth method currently in use (for doctor/setup reporting)
# Returns: "oauth", "config", "env:QWEN_API_KEY", or "none"
qwen_auth_method() {
    if [[ -f "${HOME}/.qwen/oauth_creds.json" ]]; then
        echo "oauth"
    elif [[ -f "${HOME}/.qwen/config.json" ]]; then
        echo "config"
    elif [[ -n "${QWEN_API_KEY:-}" ]]; then
        echo "env:QWEN_API_KEY"
    else
        echo "none"
    fi
}

# Execute a prompt via Qwen CLI headless mode
# Args: $1=agent_type (e.g. qwen, qwen-research), $2=prompt, $3=output_file (optional)
# Qwen CLI is a fork of Gemini CLI — same flags: -p, -o text, --approval-mode yolo
qwen_execute() {
    local agent_type="$1"
    local prompt="$2"
    local output_file="${3:-}"

    if ! command -v qwen &>/dev/null; then
        log ERROR "qwen: CLI not found — install: npm install -g @qwen-code/qwen-code"
        return 1
    fi

    local timeout="${OCTOPUS_QWEN_TIMEOUT:-90}"

    [[ "${VERBOSE:-}" == "true" ]] && log DEBUG "qwen_execute: type=$agent_type, timeout=${timeout}s, auth=$(qwen_auth_method)" || true

    local response exit_code
    response=$(timeout "$timeout" qwen -p "$prompt" --approval-mode yolo -o text 2>&1) && exit_code=0 || exit_code=$?

    # Handle errors
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 124 ]]; then
            log WARN "qwen: Timed out after ${timeout}s"
            return 1
        fi
        # Check for auth errors
        if printf '%s' "$response" | grep -qiE 'unauthorized|auth|login|token'; then
            log ERROR "qwen: Auth failure — run: qwen (to trigger OAuth) or set QWEN_API_KEY"
            return 1
        fi
        log WARN "qwen: Exit code $exit_code"
        # Still return output if we got some (non-zero exit can include useful output)
    fi

    if [[ -z "$response" ]]; then
        log WARN "qwen: Empty response"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        printf '%s\n' "$response" > "$output_file"
    else
        printf '%s\n' "$response"
    fi
}
