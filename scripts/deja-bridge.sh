#!/usr/bin/env bash
# CLI adapter for deja-vu (github.com/vshulcz/deja-vu).
# deja indexes the session transcripts Claude Code, Codex, Gemini CLI and the
# other agents already keep on disk, so search covers every provider Octopus
# dispatched to, including sessions from before deja was installed.
# No server: each call is one `deja` subprocess. No-ops when deja is absent.

set -euo pipefail

DEJA_BIN="${DEJA_BIN:-deja}"
DEJA_TIMEOUT="${DEJA_TIMEOUT:-5}"

_deja() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$DEJA_TIMEOUT" "$DEJA_BIN" "$@"
    else
        "$DEJA_BIN" "$@"
    fi
}

deja_available() {
    command -v "$DEJA_BIN" >/dev/null 2>&1
}

# Usage: deja_search "query" [limit] [project]
# Outputs a JSON array, one item per session, or empty on failure.
deja_search() {
    local query="${1:-}" limit="${2:-5}" scope="${3:-}"
    deja_available || { echo ""; return 0; }
    command -v jq >/dev/null 2>&1 || { echo ""; return 0; }
    [[ -n "$query" ]] || { echo ""; return 0; }
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=5
    (( limit >= 1 && limit <= 100 )) || limit=5

    local args=(search --json --limit "$limit")
    [[ -n "$scope" ]] && args+=(--project "$scope")

    _deja "${args[@]}" -- "$query" 2>/dev/null | jq -c '
        # Older deja releases printed a bare array; current ones wrap it in .hits.
        # tier "relevance" means no session held every word, only the nearest
        # ones; memory_search stops at the first backend with results, so those
        # would keep a later backend with a real match from being asked.
        [(if type == "array" then .
          elif .tier == "relevance" then []
          else (.hits // []) end)[] | {
            title: (.session.title // (.snippets[0] // "") | .[0:120]),
            content: ((.snippets // []) | join("\n")),
            created_at: (.session.updated // .session.started // ""),
            harness: .session.harness,
            session_id: .session.id,
            project: (.session.project // ""),
            source: "deja"
        }]' 2>/dev/null || echo ""
}

# Usage: deja_observe "type" "title" "text" [project]
# Writes a deja note; it is searchable from every agent deja serves.
deja_observe() {
    local obs_type="${1:-note}" title="${2:-}" text="${3:-}" scope="${4:-}"
    deja_available || return 1
    local content="$title"
    [[ -n "$text" ]] && content="${content}"$'\n\n'"${text}"
    [[ -n "$content" ]] || return 1

    local args=(remember "$content" --tag octopus --tag "$obs_type")
    [[ -n "$scope" ]] && args+=(--project "$scope")
    _deja "${args[@]}" >/dev/null 2>&1
}

# Usage: deja_context [project] [limit]
# The project digest deja prints at session start, for the current directory.
deja_context() {
    deja_available || { echo ""; return 0; }
    local out
    out=$(_deja hook-context --plain 2>/dev/null || echo "")
    [[ -n "$out" ]] || { echo ""; return 0; }
    printf '## deja: earlier sessions in this project\n%s\n' "$out"
}

case "${1:-}" in
    available) deja_available && echo "true" || echo "false" ;;
    search)    shift; deja_search "$@" ;;
    observe)   shift; deja_observe "$@" ;;
    context)   shift; deja_context "$@" ;;
    *)
        echo "Usage: deja-bridge.sh {available|search|observe|context} [args...]" >&2
        exit 1
        ;;
esac
