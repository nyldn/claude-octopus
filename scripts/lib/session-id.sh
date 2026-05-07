#!/usr/bin/env bash
# lib/session-id.sh — Resolve the current Octopus session ID across hosts.
# Source-safe: no main execution block.

[[ -n "${_OCTOPUS_SESSION_ID_LIB_LOADED:-}" ]] && return 0
_OCTOPUS_SESSION_ID_LIB_LOADED=true

octo_extract_session_id_from_json() {
    local input="${1:-}"
    [[ -z "$input" ]] && return 1

    if command -v jq >/dev/null 2>&1; then
        local jq_out
        jq_out=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || true
        if [[ -n "$jq_out" && "$jq_out" != "null" ]]; then
            printf '%s\n' "$jq_out"
            return 0
        fi
    fi

    local pattern='"session_id"[[:space:]]*:[[:space:]]*"([^"]+)"'
    if [[ "$input" =~ $pattern ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

octo_resolve_session_id() {
    local fallback="${1:-}"
    local hook_input="${2:-}"
    local host="${OCTOPUS_HOST:-claude}"
    local sid=""

    case "$host" in
        codex)
            sid="${CODEX_SESSION_ID:-${CODEX_TASK_ID:-}}"
            ;;
        gemini)
            sid="${GEMINI_SESSION_ID:-}"
            ;;
        *)
            # Claude Code v2.1.132+ exposes this to Bash tool subprocesses.
            # Keep CLAUDE_SESSION_ID/CLAUDE_CODE_SESSION for older runtimes.
            sid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION:-}}}"
            ;;
    esac

    if [[ -z "$sid" && -n "$hook_input" ]]; then
        sid=$(octo_extract_session_id_from_json "$hook_input" 2>/dev/null || true)
    fi

    sid="${sid:-$fallback}"
    [[ -n "$sid" ]] || return 1
    printf '%s\n' "$sid"
}

octo_session_state_file() {
    local name="$1"
    local extension="${2:-txt}"
    local hook_input="${3:-}"
    local sid
    sid=$(octo_resolve_session_id "$$" "$hook_input" 2>/dev/null || printf '%s' "$$")
    printf '/tmp/octopus-%s-%s.%s\n' "$name" "$sid" "$extension"
}
