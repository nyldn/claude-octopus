#!/usr/bin/env bash
# claude-mem-bridge.sh — Optional integration bridge to claude-mem plugin
# All operations are non-blocking and fault-tolerant — silently no-ops when claude-mem is unavailable.
# v8.57.0

set -euo pipefail

CLAUDE_MEM_PORT="${CLAUDE_MEM_PORT:-37777}"
CLAUDE_MEM_HOST="${CLAUDE_MEM_HOST:-localhost}"
CLAUDE_MEM_URL="http://${CLAUDE_MEM_HOST}:${CLAUDE_MEM_PORT}"
CLAUDE_MEM_TIMEOUT=3  # seconds — fast fail

# Check if claude-mem worker is reachable
# Returns 0 if healthy, 1 otherwise
claude_mem_available() {
    curl -sf --max-time "$CLAUDE_MEM_TIMEOUT" "${CLAUDE_MEM_URL}/api/health" >/dev/null 2>&1
}

# Search claude-mem for relevant past observations
# Usage: claude_mem_search "query" [limit] [project]
# Outputs: JSON search results or empty string on failure
claude_mem_search() {
    local query="$1"
    local limit="${2:-5}"
    local project="${3:-}"

    local url="${CLAUDE_MEM_URL}/api/search?query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$query'))" 2>/dev/null || echo "$query")&limit=${limit}"
    if [[ -n "$project" ]]; then
        url="${url}&project=${project}"
    fi

    curl -sf --max-time "$CLAUDE_MEM_TIMEOUT" "$url" 2>/dev/null || echo ""
}

# Write an observation to claude-mem
# Usage: claude_mem_observe "type" "title" "text" [project]
# Types: decision, discovery, change, feature, bugfix, refactor
claude_mem_observe() {
    local obs_type="$1"
    local title="$2"
    local text="$3"
    local project="${4:-}"

    # Find active session
    local session_id
    session_id=$(curl -sf --max-time "$CLAUDE_MEM_TIMEOUT" \
        "${CLAUDE_MEM_URL}/api/sessions?status=active&limit=1" 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['memory_session_id'] if d else '')" 2>/dev/null || echo "")

    if [[ -z "$session_id" ]]; then
        return 0  # No active session — silently skip
    fi

    # POST observation (non-blocking)
    curl -sf --max-time "$CLAUDE_MEM_TIMEOUT" \
        -X POST "${CLAUDE_MEM_URL}/api/sessions/${session_id}/observations" \
        -H "Content-Type: application/json" \
        -d "$(python3 -c "
import json, sys
print(json.dumps({
    'type': '$obs_type',
    'title': '$title',
    'text': '$text',
    'source': 'claude-octopus',
    'concept': 'how-it-works'
}))" 2>/dev/null)" >/dev/null 2>&1 &

    return 0
}

# Get recent context summary for current project
# Usage: claude_mem_context [project] [limit]
# Outputs: Formatted text summary or empty string
claude_mem_context() {
    local project="${1:-}"
    local limit="${2:-3}"

    local results
    results=$(claude_mem_search "recent work" "$limit" "$project")

    if [[ -z "$results" || "$results" == "[]" ]]; then
        echo ""
        return 0
    fi

    # Format results as brief context
    python3 -c "
import json, sys
try:
    data = json.loads('''$results''')
    if not data or not isinstance(data, list):
        sys.exit(0)
    print('## Recent claude-mem observations')
    for item in data[:$limit]:
        title = item.get('title', 'untitled')
        obs_type = item.get('type', '')
        created = item.get('created_at', '')[:10]
        print(f'- [{obs_type}] {title} ({created})')
except:
    pass
" 2>/dev/null || echo ""
}

# Main dispatch
case "${1:-}" in
    available)
        claude_mem_available && echo "true" || echo "false"
        ;;
    search)
        shift
        claude_mem_search "$@"
        ;;
    observe)
        shift
        claude_mem_observe "$@"
        ;;
    context)
        shift
        claude_mem_context "$@"
        ;;
    *)
        echo "Usage: claude-mem-bridge.sh {available|search|observe|context} [args...]"
        exit 1
        ;;
esac
