#!/usr/bin/env bash
# GitHub Copilot CLI provider execution (v9.8.0 - Issue #198)
# Uses official `copilot -p` programmatic mode (GA Feb 2026).
# Auth: COPILOT_GITHUB_TOKEN > GH_TOKEN > GITHUB_TOKEN > keychain > gh CLI
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

# Check that the installed CLI exposes every flag the non-interactive adapter
# relies on. Capability detection is safer than inventing an undocumented
# version floor and remains correct if GitHub backports or changes versions.
copilot_has_required_capabilities() {
    local help_text="" required=""
    if ! help_text="$(copilot --help </dev/null 2>/dev/null)" || [[ -z "$help_text" ]]; then
        return 1
    fi
    for required in --prompt --model --silent --no-ask-user --disable-builtin-mcps; do
        grep -E -c -- "(^|[[:space:],])${required}([[:space:],=]|$)" <<< "$help_text" >/dev/null || return 1
    done
    return 0
}

# Check if Copilot CLI is available, capable, and authenticated.
# Returns 0 if ready, 1 if not
copilot_is_available() {
    if ! command -v copilot &>/dev/null; then
        return 1
    fi
    copilot_has_required_capabilities || return 1
    # Check auth: env vars first (fast), then keychain/gh (slower)
    if [[ -n "${COPILOT_GITHUB_TOKEN:-}" ]] || \
       [[ -n "${GH_TOKEN:-}" ]] || \
       [[ -n "${GITHUB_TOKEN:-}" ]]; then
        return 0
    fi
    # Check for stored OAuth token (keychain)
    if [[ -f "${HOME}/.copilot/config.json" ]]; then
        return 0
    fi
    # Check gh CLI fallback
    if command -v gh &>/dev/null && gh auth status &>/dev/null; then
        return 0
    fi
    return 1
}

# Get the auth method currently in use (for doctor/setup reporting)
# Returns: "env:COPILOT_GITHUB_TOKEN", "env:GH_TOKEN", "env:GITHUB_TOKEN",
#          "keychain", "gh-cli", or "none"
copilot_auth_method() {
    if [[ -n "${COPILOT_GITHUB_TOKEN:-}" ]]; then
        echo "env:COPILOT_GITHUB_TOKEN"
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        echo "env:GH_TOKEN"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "env:GITHUB_TOKEN"
    elif [[ -f "${HOME}/.copilot/config.json" ]]; then
        echo "keychain"
    elif command -v gh &>/dev/null && gh auth status &>/dev/null; then
        echo "gh-cli"
    else
        echo "none"
    fi
}

# Execute a prompt via Copilot CLI programmatic mode
# Args: $1=model (agent type, e.g. copilot, copilot-research), $2=prompt, $3=output_file (optional)
# OCTOPUS_COPILOT_MODEL defaults to the CLI's service-owned auto selector.
copilot_execute() {
    local agent_type="$1"
    local prompt="$2"
    local output_file="${3:-}"

    if ! command -v copilot &>/dev/null; then
        log ERROR "copilot: CLI not found — install: brew install copilot-cli"
        return 1
    fi

    # Build auth env — forward the right token
    local -a auth_env=()
    if [[ -n "${COPILOT_GITHUB_TOKEN:-}" ]]; then
        auth_env=(env "COPILOT_GITHUB_TOKEN=${COPILOT_GITHUB_TOKEN}")
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        auth_env=(env "GH_TOKEN=${GH_TOKEN}")
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_env=(env "GITHUB_TOKEN=${GITHUB_TOKEN}")
    fi

    local timeout="${OCTOPUS_COPILOT_TIMEOUT:-90}"
    local model="${OCTOPUS_COPILOT_MODEL:-auto}"

    [[ "${VERBOSE:-}" == "true" ]] && log DEBUG "copilot_execute: type=$agent_type, timeout=${timeout}s, auth=$(copilot_auth_method)" || true

    local response exit_code
    if [[ ${#auth_env[@]} -gt 0 ]]; then
        response=$("${auth_env[@]}" timeout "$timeout" copilot -p "$prompt" --model "$model" --no-ask-user -s --disable-builtin-mcps 2>&1) && exit_code=0 || exit_code=$?
    else
        response=$(timeout "$timeout" copilot -p "$prompt" --model "$model" --no-ask-user -s --disable-builtin-mcps 2>&1) && exit_code=0 || exit_code=$?
    fi

    # Handle errors
    if [[ $exit_code -ne 0 ]]; then
        if [[ $exit_code -eq 124 ]]; then
            log WARN "copilot: Timed out after ${timeout}s"
            return 1
        fi
        # Check for auth errors
        if printf '%s' "$response" | grep -ciE 'unauthorized|forbidden|(^|[^0-9])(401|403)([^0-9]|$)|authentication[[:space:]]+(failed|required)|not[[:space:]]+authorized|invalid[[:space:]]+token|expired[[:space:]]+token|token[[:space:]]+expired|please[[:space:]]+(re)?login|login[[:space:]]+required' >/dev/null; then
            log ERROR "copilot: Auth failure — run: copilot login (or set COPILOT_GITHUB_TOKEN)"
            return 1
        fi
        log WARN "copilot: Exit code $exit_code"
        # Still return output if we got some (non-zero exit can include useful output)
    fi

    if [[ -z "$response" ]]; then
        log WARN "copilot: Empty response"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        printf '%s\n' "$response" > "$output_file"
    else
        printf '%s\n' "$response"
    fi
}
