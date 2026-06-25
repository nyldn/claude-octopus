#!/usr/bin/env bash
# Sourced by orchestrator scripts; keep nounset off so this file does not leak
# stricter unset-variable handling into callers after returning.
set -eo pipefail
# provider-allowlist.sh - Shared provider allowlist helpers.
#
# OCTO_ALLOWED_PROVIDERS is a space/comma separated list of provider names.
# When unset, every detected provider is allowed. When set, scripts should
# treat non-listed providers as unavailable even if their CLI/API key exists.
#
# Session commands can also write an allowlist under
# ~/.claude-octopus/config/provider-allowlist.<session>. The env var wins when
# present, then the session file, then the global config file.

octo_normalize_provider_name() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr -d ','
}

octo_provider_allowlist_config_dir() {
    printf '%s\n' "${OCTOPUS_CONFIG_DIR:-${HOME}/.claude-octopus/config}"
}

octo_provider_allowlist_session_id() {
    local raw
    raw="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_CODE_SESSION:-${OCTOPUS_SESSION_ID:-${CLAUDE_SESSION_ID:-global}}}}"
    raw="$(printf '%s' "$raw" | tr -c 'A-Za-z0-9_.-' '-' | sed 's/--*/-/g;s/^-//;s/-$//')"
    printf '%s\n' "${raw:-global}"
}

octo_provider_allowlist_session_file() {
    printf '%s/provider-allowlist.%s\n' "$(octo_provider_allowlist_config_dir)" "$(octo_provider_allowlist_session_id)"
}

octo_provider_allowlist_global_file() {
    printf '%s/provider-allowlist\n' "$(octo_provider_allowlist_config_dir)"
}

octo_provider_allowlist_source() {
    if [[ -n "${OCTO_ALLOWED_PROVIDERS:-}" ]]; then
        printf 'env:OCTO_ALLOWED_PROVIDERS\n'
        return 0
    fi

    local session_file
    session_file="$(octo_provider_allowlist_session_file)"
    if [[ -f "$session_file" ]]; then
        printf 'session:%s\n' "$session_file"
        return 0
    fi

    local global_file
    global_file="$(octo_provider_allowlist_global_file)"
    if [[ -f "$global_file" ]]; then
        printf 'global:%s\n' "$global_file"
        return 0
    fi

    printf 'unset\n'
}

octo_provider_allowlist_value() {
    if [[ -n "${OCTO_ALLOWED_PROVIDERS:-}" ]]; then
        printf '%s\n' "$OCTO_ALLOWED_PROVIDERS"
        return 0
    fi

    local session_file
    session_file="$(octo_provider_allowlist_session_file)"
    if [[ -f "$session_file" ]]; then
        tr '\n' ' ' < "$session_file"
        printf '\n'
        return 0
    fi

    local global_file
    global_file="$(octo_provider_allowlist_global_file)"
    if [[ -f "$global_file" ]]; then
        tr '\n' ' ' < "$global_file"
        printf '\n'
        return 0
    fi

    printf '\n'
}

octo_provider_allowed() {
    local provider
    provider="$(octo_normalize_provider_name "${1:-}")"
    [[ -n "$provider" ]] || return 1

    local allowed
    allowed="$(octo_provider_allowlist_value)"
    if [[ -z "$allowed" ]]; then
        return 0
    fi

    local token normalized
    # shellcheck disable=SC2086 # Intentional word splitting: space separated allowlist.
    for token in ${allowed//,/ }; do
        normalized="$(octo_normalize_provider_name "$token")"
        [[ -n "$normalized" ]] || continue

        [[ "$provider" == "$normalized" ]] && return 0

        case "$normalized" in
            claude|anthropic|sonnet)
                case "$provider" in
                    claude|claude-sonnet|claude-opus|sonnet) return 0 ;;
                esac
                ;;
            codex|openai)
                case "$provider" in
                    codex|codex-*) return 0 ;;
                esac
                ;;
            gemini|google)
                case "$provider" in
                    gemini|gemini-*) return 0 ;;
                esac
                ;;
            agy|antigravity)
                case "$provider" in
                    agy|agy-*|antigravity) return 0 ;;
                esac
                ;;
            grok|grok-*)
                case "$provider" in
                    grok|grok-*) return 0 ;;
                esac
                ;;
            cursor|cursor-agent)
                [[ "$provider" == "cursor-agent" ]] && return 0
                ;;
            xai)
                case "$provider" in
                    cursor-agent|grok|grok-*) return 0 ;;
                esac
                ;;
            local)
                [[ "$provider" == "ollama" ]] && return 0
                ;;
        esac
    done

    return 1
}
