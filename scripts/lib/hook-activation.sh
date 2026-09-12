#!/usr/bin/env bash
# Source-safe activation helpers for hooks that must stay dormant by default.

[[ -n "${_OCTOPUS_HOOK_ACTIVATION_LOADED:-}" ]] && return 0
_OCTOPUS_HOOK_ACTIVATION_LOADED=true

_octopus_hook_activation_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

octo_normalize_context_profile() {
    case "${1:-}" in
        core|minimal) printf 'core\n' ;;
        orchestration|workflow) printf 'orchestration\n' ;;
        full|all) printf 'full\n' ;;
        *) printf 'core\n' ;;
    esac
}

octo_context_profile() {
    local profile="${OCTOPUS_CONTEXT_PROFILE:-}"
    if [[ -z "$profile" && -r "${HOME}/.claude-octopus/user-config.json" ]] && command -v jq >/dev/null 2>&1; then
        profile="$(jq -r '.context_profile // empty' "${HOME}/.claude-octopus/user-config.json" 2>/dev/null || true)"
    fi
    octo_normalize_context_profile "$profile"
}

octo_hook_profile() {
    octo_normalize_context_profile "${OCTOPUS_HOOK_PROFILE:-$(octo_context_profile)}"
}

# Profiles control optional context work only. Safety and lifecycle hooks never
# call this function, so a profile cannot disable their checks.
octo_hook_profile_allows() {
    local hook_id="${1:-}" profile config
    [[ -n "$hook_id" ]] || return 1
    profile="$(octo_hook_profile)"
    config="${OCTOPUS_HOOK_PROFILE_CONFIG:-${_octopus_hook_activation_dir}/../../config/hook-profiles.json}"
    [[ -r "$config" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e --arg profile "$profile" --arg hook "$hook_id" \
        '.profiles[$profile] // [] | any(. == "*" or . == $hook)' "$config" >/dev/null 2>&1
}

octo_hook_session_id() {
    local input="${1:-}" sid=""
    sid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"

    if [[ -z "$sid" && -n "$input" ]]; then
        if [[ "$input" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            sid="${BASH_REMATCH[1]}"
        elif command -v jq >/dev/null 2>&1; then
            sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
        fi
    fi

    [[ -n "$sid" ]] || return 1
    printf '%s\n' "$sid"
}

octo_hook_workflow_active() {
    local input="${1:-}" state_file="${2:-${HOME}/.claude-octopus/session.json}"
    local hook_session="" state_session="" state_status="" state_phase=""

    case "${OCTOPUS_ACTIVE_WORKFLOW:-}" in
        1|true|on|yes) return 0 ;;
    esac

    [[ -r "$state_file" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e 'type == "object"' "$state_file" >/dev/null 2>&1 || return 1

    hook_session="$(octo_hook_session_id "$input" 2>/dev/null || true)"
    [[ -n "$hook_session" ]] || return 1
    state_session="$(jq -r '.host_session_id // empty' "$state_file" 2>/dev/null || true)"
    [[ -n "$state_session" && "$state_session" == "$hook_session" ]] || return 1

    state_status="$(jq -r '.status // .workflow_status // .phase_status // empty' "$state_file" 2>/dev/null || true)"
    state_phase="$(jq -r '.current_phase // .phase // empty' "$state_file" 2>/dev/null || true)"
    case "$state_status" in
        in_progress|active|running|started) ;;
        *) return 1 ;;
    esac
    case "$state_phase" in
        complete|completed|finished|done) return 1 ;;
    esac
    return 0
}
