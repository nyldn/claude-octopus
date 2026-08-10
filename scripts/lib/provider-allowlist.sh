#!/usr/bin/env bash
_provider_allowlist_registry_dir="${BASH_SOURCE[0]%/*}"
[[ "$_provider_allowlist_registry_dir" == "${BASH_SOURCE[0]}" ]] && _provider_allowlist_registry_dir="."
_provider_allowlist_registry_dir="$(cd "$_provider_allowlist_registry_dir" && pwd)"
source "${_provider_allowlist_registry_dir}/provider-registry.sh" || { echo "provider-allowlist: failed to load provider-registry.sh" >&2; return 1 2>/dev/null || exit 1; }
# Sourced by orchestrator scripts. Deliberately sets NO shell options: `set -e`
# and `set -o pipefail` in a sourced file leak into the caller's shell and stay
# there after this file returns. Callers such as lib/providers.sh document
# themselves as source-safe and run probe code where a nonzero exit is normal,
# so inheriting errexit from here would abort them on the first failed probe.
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
    local provider requested_canonical
    provider="$(octo_normalize_provider_name "${1:-}")"
    [[ -n "$provider" ]] || return 1
    requested_canonical="$(octo_provider_canonical "$provider" 2>/dev/null || printf '%s' "$provider")"

    local allowed
    allowed="$(octo_provider_allowlist_value)"
    if [[ -z "$allowed" ]]; then
        return 0
    fi

    local token normalized token_canonical
    # shellcheck disable=SC2086 # Intentional word splitting: space separated allowlist.
    for token in ${allowed//,/ }; do
        normalized="$(octo_normalize_provider_name "$token")"
        [[ -n "$normalized" ]] || continue

        token_canonical="$(octo_provider_canonical "$normalized" 2>/dev/null || printf '%s' "$normalized")"
        [[ "$requested_canonical" == "$token_canonical" ]] && return 0

        # Ambiguous organization/group aliases remain policy rather than
        # provider identity. `google` authorizes the Antigravity Google seat;
        # `xai` retains the historical Cursor/Grok grouping.
        case "$normalized" in
            google)
                [[ "$requested_canonical" == "agy" ]] && return 0
                ;;
            xai)
                case "$requested_canonical" in cursor-agent|grok) return 0 ;; esac
                ;;
        esac
    done

    return 1
}
