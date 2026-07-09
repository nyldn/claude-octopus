#!/usr/bin/env bash
# CLI-level fallback adapter for agentmemory (github.com/rohitg00/agentmemory).
# Claude/Codex/Cursor MCP remains the primary path; this bridge lets Octopus
# memory hooks use the same local server without requiring MCP tools in bash.
# No-ops when the server is not reachable.

set -euo pipefail

AGENTMEMORY_URL="${AGENTMEMORY_URL:-http://localhost:3111}"
AGENTMEMORY_URL="${AGENTMEMORY_URL%/}"
AGENTMEMORY_TIMEOUT="${AGENTMEMORY_TIMEOUT:-3}"

_agentmemory_curl() {
    local method="$1" url="$2" data="${3:-}"
    local args=(-sf --max-time "$AGENTMEMORY_TIMEOUT")
    [[ -n "${AGENTMEMORY_SECRET:-}" ]] && args+=(-H "Authorization: Bearer ${AGENTMEMORY_SECRET}")
    if [[ "$method" != "GET" ]]; then
        args+=(-H "Content-Type: application/json" -X "$method" -d "$data")
    fi
    curl "${args[@]}" "$url"
}

agentmemory_available() {
    _agentmemory_curl GET "${AGENTMEMORY_URL}/agentmemory/livez" >/dev/null 2>&1 ||
    _agentmemory_curl GET "${AGENTMEMORY_URL}/agentmemory/health" >/dev/null 2>&1
}

_agentmemory_json_available() {
    command -v jq >/dev/null 2>&1
}

agentmemory_search() {
    local query="${1:-}" limit="${2:-5}" scope="${3:-}"
    agentmemory_available || { echo ""; return 0; }
    _agentmemory_json_available || { echo ""; return 0; }
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=5
    [[ -n "$scope" ]] && query="${query} ${scope}"

    local payload
    payload=$(jq -n \
        --arg query "$query" \
        --argjson limit "$limit" \
        '{query: $query, limit: $limit}')

    _agentmemory_curl POST "${AGENTMEMORY_URL}/agentmemory/smart-search" "$payload" 2>/dev/null || echo ""
}

agentmemory_observe() {
    local obs_type="${1:-note}" title="${2:-}" text="${3:-}" scope="${4:-}"
    agentmemory_available || return 0
    _agentmemory_json_available || return 0

    local content payload
    content="$title"
    [[ -n "$text" ]] && content="${content}"$'\n\n'"${text}"

    payload=$(jq -n \
        --arg content "$content" \
        --arg type "$obs_type" \
        --arg scope "$scope" \
        '{
            content: $content,
            concepts: (["octopus", $type] + (if $scope != "" then [$scope] else [] end))
        }')

    _agentmemory_curl POST "${AGENTMEMORY_URL}/agentmemory/remember" "$payload" >/dev/null 2>&1 &
    return 0
}

agentmemory_context() {
    local scope="${1:-}" limit="${2:-3}"
    local results
    results=$(agentmemory_search "recent work" "$limit" "$scope")
    [[ -z "$results" || "$results" == "[]" ]] && { echo ""; return 0; }
    printf '%s' "$results" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if isinstance(data, dict):
        items = data.get('results') or data.get('memories') or data.get('data') or []
    elif isinstance(data, list):
        items = data
    else:
        items = []
    if not items:
        sys.exit(0)
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    print('## Recent agentmemory observations')
    for item in items[:limit]:
        if not isinstance(item, dict):
            title = str(item)[:80]
            created = ''
        else:
            content = item.get('content') or item.get('text') or item.get('memory') or item.get('summary') or ''
            title = item.get('title') or item.get('name') or content[:80] or 'untitled'
            created = (item.get('created_at') or item.get('timestamp') or item.get('date') or '')[:10]
        suffix = f' ({created})' if created else ''
        print(f'- {title}{suffix}')
except Exception:
    pass
" "$limit" 2>/dev/null || echo ""
}

case "${1:-}" in
    available) agentmemory_available && echo "true" || echo "false" ;;
    search)    shift; agentmemory_search "$@" ;;
    observe)   shift; agentmemory_observe "$@" ;;
    context)   shift; agentmemory_context "$@" ;;
    *)
        echo "Usage: agentmemory-bridge.sh {available|search|observe|context} [args...]" >&2
        exit 1
        ;;
esac
