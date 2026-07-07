#!/usr/bin/env bash
# Qwen CLI provider execution (v9.10.0)
# Fork of the Antigravity CLI — same flags, different binary.
# Auth: API key / Coding-Plan (QWEN_API_KEY, or OPENAI_API_KEY+OPENAI_BASE_URL).
#   NOTE: the Qwen free OAuth tier was discontinued 2026-04-15 and its token
#   auto-refresh is broken; an expired ~/.qwen/oauth_creds.json never recovers.
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

# Get the auth method currently in use (for doctor/setup reporting)
# Returns: "env:QWEN_API_KEY", "env:OPENAI_COMPAT", "oauth",
# "oauth-expired", "oauth-unvalidated", "config", or "none"
#
# oco-dar: an EXPIRED oauth_creds.json must report "oauth-expired" (treated as
# unauthenticated by callers), not "oauth" — otherwise dispatch launches an
# interactive browser device-auth flow that hangs the workflow.
qwen_auth_method() {
    if [[ -n "${QWEN_API_KEY:-}" ]]; then
        echo "env:QWEN_API_KEY"
        return
    fi
    if [[ -n "${OPENAI_API_KEY:-}" && -n "${OPENAI_BASE_URL:-}" ]]; then
        echo "env:OPENAI_COMPAT"
        return
    fi
    if [[ -f "${HOME}/.qwen/oauth_creds.json" ]]; then
        if declare -f octo_oauth_token_valid >/dev/null 2>&1; then
            if octo_oauth_token_valid "${HOME}/.qwen/oauth_creds.json"; then
                echo "oauth"
            else
                echo "oauth-expired"
            fi
        else
            # Validator unavailable (auth.sh not sourced) — fail closed so an
            # unvalidated OAuth file never re-enables the stale-token hang path.
            echo "oauth-unvalidated"
        fi
        return
    fi
    if [[ -f "${HOME}/.qwen/config.json" ]]; then
        echo "config"
    else
        echo "none"
    fi
}

# Is qwen usable right now? (binary present AND a valid, non-expired auth source)
# Returns 0 if usable, 1 otherwise. Single source of truth for dispatch gating.
qwen_is_usable() {
    command -v qwen >/dev/null 2>&1 || return 1
    case "$(qwen_auth_method)" in
        env:QWEN_API_KEY|env:OPENAI_COMPAT|oauth|config) return 0 ;;
        *) return 1 ;;   # oauth-expired, oauth-unvalidated, none
    esac
}

# Execute a prompt via Qwen CLI headless mode
# Args: $1=agent_type (e.g. qwen, qwen-research), $2=prompt, $3=output_file (optional)
# Qwen CLI is a fork of the Antigravity CLI — same flags: -p, -o text, --approval-mode yolo
qwen_execute() {
    local agent_type="$1"
    local prompt="$2"
    local output_file="${3:-}"

    if ! command -v qwen &>/dev/null; then
        log ERROR "qwen: CLI not found — install: npm install -g @qwen-code/qwen-code"
        return 1
    fi

    if declare -f qwen_is_usable >/dev/null 2>&1 && ! qwen_is_usable; then
        log ERROR "qwen: not usable (auth: $(qwen_auth_method)). Set QWEN_API_KEY or configure Coding-Plan (OPENAI_API_KEY + OPENAI_BASE_URL)."
        return 1
    fi

    local timeout="${OCTOPUS_QWEN_TIMEOUT:-90}"

    [[ "${VERBOSE:-}" == "true" ]] && log DEBUG "qwen_execute: type=$agent_type, timeout=${timeout}s, auth=$(qwen_auth_method)" || true

    local response exit_code
    if declare -f run_with_timeout >/dev/null 2>&1; then
        response=$(NO_BROWSER=1 NODE_NO_WARNINGS=1 run_with_timeout "$timeout" qwen -p "$prompt" --approval-mode yolo -o text 2>&1) && exit_code=0 || exit_code=$?
    else
        response=$(NO_BROWSER=1 NODE_NO_WARNINGS=1 timeout -k 10 "$timeout" qwen -p "$prompt" --approval-mode yolo -o text 2>&1) && exit_code=0 || exit_code=$?
    fi

    # Handle errors
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 124 ]]; then
            log WARN "qwen: Timed out after ${timeout}s"
            return 1
        fi
        # Check for auth errors
        if printf '%s' "$response" | grep -qiE 'unauthorized|auth|login|token'; then
            log ERROR "qwen: Auth failure — set QWEN_API_KEY or configure Coding-Plan (OPENAI_API_KEY + OPENAI_BASE_URL)"
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
