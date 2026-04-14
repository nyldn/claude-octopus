#!/usr/bin/env bash
# Memory-provider contract. Callers go through memory_* so backends are
# swappable without touching orchestration code.
#
# Env:
#   OCTOPUS_MEMORY_BACKEND  "auto" (default) | comma-separated list
#   OCTOPUS_MEMORY_SCOPE    override scope label (default: repo basename)

set -euo pipefail

_MEMORY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_MEMORY_PLUGIN_DIR="$(cd "${_MEMORY_LIB_DIR}/../.." && pwd)"
_MEMORY_BRIDGE_DIR="${_MEMORY_PLUGIN_DIR}/scripts"

# Precedence mirrors Claude Code's own settings resolution.
_memory_claude_settings_path() {
    local candidates=(
        "${CLAUDE_SETTINGS_FILE:-}"
        "$HOME/.claude.json"
        "$HOME/.claude/settings.json"
    )
    for path in "${candidates[@]}"; do
        [[ -n "$path" && -r "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

# Match by command/package string so users can name the server key anything.
_memory_mcp_service_registered() {
    local settings
    settings=$(_memory_claude_settings_path) || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e '
        (.mcpServers // {}) as $m
        | [$m | to_entries[] | (.value.command // "") + " " + ((.value.args // []) | join(" "))]
        | any(test("mcp-memory-service"))
    ' "$settings" >/dev/null 2>&1
}

memory_backends() {
    local pref="${OCTOPUS_MEMORY_BACKEND:-auto}"
    if [[ "$pref" != "auto" ]]; then
        printf '%s\n' "$pref" | tr ',' '\n' | awk 'NF'
        return 0
    fi
    if _memory_mcp_service_registered; then
        printf 'mcp-memory-service\nclaude-mem\n'
    else
        printf 'claude-mem\n'
    fi
}

memory_scope() {
    if [[ -n "${OCTOPUS_MEMORY_SCOPE:-}" ]]; then
        printf '%s' "$OCTOPUS_MEMORY_SCOPE"
        return 0
    fi
    local git_root
    if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        basename "$git_root"
        return 0
    fi
    printf 'default'
}

_memory_invoke() {
    local backend="$1"; shift
    local primitive="$1"; shift
    case "$backend" in
        claude-mem)
            local bridge="${_MEMORY_BRIDGE_DIR}/claude-mem-bridge.sh"
            [[ -x "$bridge" ]] || return 1
            case "$primitive" in
                available) "$bridge" available ;;
                search)    "$bridge" search "$1" "${2:-5}" "${3:-}" ;;
                observe)   "$bridge" observe "$1" "$2" "$3" "${4:-}" ;;
                context)   "$bridge" context "${1:-}" "${2:-3}" ;;
                *) return 1 ;;
            esac
            ;;
        mcp-memory-service)
            local bridge="${_MEMORY_BRIDGE_DIR}/mcp-memory-bridge.sh"
            [[ -x "$bridge" ]] || return 1
            "$bridge" "$primitive" "$@"
            ;;
        *)
            return 1
            ;;
    esac
}

memory_available() {
    local backend result
    while IFS= read -r backend; do
        [[ -z "$backend" ]] && continue
        result=$(_memory_invoke "$backend" available 2>/dev/null || echo "false")
        [[ "$result" == "true" ]] && { printf 'true'; return 0; }
    done < <(memory_backends)
    printf 'false'
    return 1
}

# OCTOPUS_MEMORY_SEARCH_MERGE=1 aggregates across backends instead of first-win.
memory_search() {
    local query="$1"
    local limit="${2:-5}"
    local scope="${3:-$(memory_scope)}"
    local merge="${OCTOPUS_MEMORY_SEARCH_MERGE:-0}"
    local backend result aggregated="[]"

    while IFS= read -r backend; do
        [[ -z "$backend" ]] && continue
        result=$(_memory_invoke "$backend" search "$query" "$limit" "$scope" 2>/dev/null || echo "")
        [[ -z "$result" || "$result" == "[]" ]] && continue
        if [[ "$merge" == "1" ]] && command -v jq >/dev/null 2>&1; then
            aggregated=$(jq -s 'add // []' <(printf '%s' "$aggregated") <(printf '%s' "$result") 2>/dev/null || printf '%s' "$aggregated")
        else
            printf '%s' "$result"
            return 0
        fi
    done < <(memory_backends)

    [[ "$merge" == "1" ]] && printf '%s' "$aggregated"
}

# First reachable backend only, so decisions aren't double-recorded.
memory_observe() {
    local type="$1" title="$2" text="$3"
    local scope="${4:-$(memory_scope)}"
    local backend
    while IFS= read -r backend; do
        [[ -z "$backend" ]] && continue
        if _memory_invoke "$backend" observe "$type" "$title" "$text" "$scope" 2>/dev/null; then
            return 0
        fi
    done < <(memory_backends)
    return 1
}

memory_context() {
    local scope="${1:-$(memory_scope)}"
    local limit="${2:-3}"
    local backend result
    while IFS= read -r backend; do
        [[ -z "$backend" ]] && continue
        result=$(_memory_invoke "$backend" context "$scope" "$limit" 2>/dev/null || echo "")
        [[ -n "$result" ]] && { printf '%s' "$result"; return 0; }
    done < <(memory_backends)
}
