#!/usr/bin/env bash
# CLI-level fallback adapter for mcp-memory-service
# (github.com/doobidoo/mcp-memory-service). Claude's MCP layer is the primary
# path — this bridge exists so bash detection/read paths don't need a live MCP
# session. No-ops when the CLI is missing.

set -euo pipefail

MCP_MEMORY_CMD="${OCTOPUS_MCP_MEMORY_CMD:-uvx mcp-memory-service}"
MCP_MEMORY_TIMEOUT=5

# Detect presence without spawning the full tool (uvx would pull Torch/CUDA).
_mcp_memory_cli_ready() {
    local bin="${MCP_MEMORY_CMD%% *}"
    command -v "$bin" >/dev/null 2>&1
}

mcp_memory_available() {
    _mcp_memory_cli_ready && echo "true" || echo "false"
}

# Arg shape mirrors claude-mem-bridge for contract-level swap compatibility.
mcp_memory_search() {
    local query="${1:-}" limit="${2:-5}" scope="${3:-}"
    _mcp_memory_cli_ready || { echo ""; return 0; }
    # shellcheck disable=SC2086
    timeout "$MCP_MEMORY_TIMEOUT" $MCP_MEMORY_CMD query \
        --json \
        ${scope:+--project "$scope"} \
        --limit "$limit" \
        -- "$query" 2>/dev/null || echo ""
}

mcp_memory_observe() {
    local obs_type="${1:-note}" title="${2:-}" text="${3:-}" scope="${4:-}"
    _mcp_memory_cli_ready || return 0
    # shellcheck disable=SC2086
    timeout "$MCP_MEMORY_TIMEOUT" $MCP_MEMORY_CMD store \
        --tag "$obs_type" \
        --tag "octopus" \
        ${scope:+--project "$scope"} \
        --title "$title" \
        -- "$text" >/dev/null 2>&1 &
    return 0
}

mcp_memory_context() {
    local scope="${1:-}" limit="${2:-3}"
    local results
    results=$(mcp_memory_search "recent work" "$limit" "$scope")
    [[ -z "$results" || "$results" == "[]" ]] && { echo ""; return 0; }
    printf '%s' "$results" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if not isinstance(data, list) or not data:
        sys.exit(0)
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    print('## Recent mcp-memory-service observations')
    for item in data[:limit]:
        title = item.get('title') or item.get('content', '')[:60] or 'untitled'
        tags = ','.join(item.get('tags', [])[:3])
        created = (item.get('created_at') or '')[:10]
        print(f'- [{tags}] {title} ({created})')
except Exception:
    pass
" "$limit" 2>/dev/null || echo ""
}

case "${1:-}" in
    available) mcp_memory_available ;;
    search)    shift; mcp_memory_search "$@" ;;
    observe)   shift; mcp_memory_observe "$@" ;;
    context)   shift; mcp_memory_context "$@" ;;
    *)
        echo "Usage: mcp-memory-bridge.sh {available|search|observe|context} [args...]" >&2
        exit 1
        ;;
esac
