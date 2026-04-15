#!/usr/bin/env bash
# OpenCLI Bridge for Claude Octopus
# Bridges Octopus workflows to OpenCLI commands for real-time web data
# and desktop app control.
#
# Usage:
#   opencli-bridge.sh <action> <args...>
#
# Actions:
#   search <platform> <query>     — Search a platform (twitter, reddit, youtube, etc.)
#   trending <platform>           — Get trending/hot content from a platform
#   fetch <platform> <command>    — Run any OpenCLI command
#   list                          — List all available OpenCLI commands
#   status                        — Check OpenCLI availability
#   explore <url>                 — Discover APIs for a website
#   desktop <app> <command>       — Control a desktop app

set -euo pipefail

OPENCLI_TIMEOUT="${OPENCLI_TIMEOUT:-30}"
OPENCLI_FORMAT="${OPENCLI_FORMAT:-json}"

# ── Helpers ──────────────────────────────────────────────────────────

log_info()  { echo "🌐 [opencli-bridge] $*" >&2; }
log_error() { echo "❌ [opencli-bridge] $*" >&2; }

# Check if opencli is available
check_opencli() {
    if ! command -v opencli &>/dev/null; then
        log_error "opencli not found. Install with: npm install -g opencli"
        return 1
    fi
    return 0
}

# Run an opencli command with timeout and format
run_opencli() {
    local timeout_val="$OPENCLI_TIMEOUT"
    
    if ! check_opencli; then
        echo '{"error": "opencli not installed", "install": "npm install -g opencli"}'
        return 1
    fi

    # Run with timeout
    if command -v timeout &>/dev/null; then
        timeout "${timeout_val}s" opencli "$@" -f "$OPENCLI_FORMAT" 2>/dev/null
    elif command -v gtimeout &>/dev/null; then
        gtimeout "${timeout_val}s" opencli "$@" -f "$OPENCLI_FORMAT" 2>/dev/null
    else
        opencli "$@" -f "$OPENCLI_FORMAT" 2>/dev/null
    fi
}

# ── Actions ──────────────────────────────────────────────────────────

action_search() {
    local platform="${1:?Platform required (twitter, reddit, youtube, etc.)}"
    local query="${2:?Search query required}"
    shift 2
    log_info "Searching $platform for: $query"
    run_opencli "$platform" search "$query" "$@"
}

action_trending() {
    local platform="${1:?Platform required (twitter, reddit, hackernews, etc.)}"
    shift
    log_info "Getting trending content from $platform"
    
    case "$platform" in
        twitter|x)
            run_opencli twitter trending "$@"
            ;;
        reddit)
            run_opencli reddit hot "$@"
            ;;
        hackernews|hn)
            run_opencli hackernews hot "$@"
            ;;
        bilibili)
            run_opencli bilibili hot "$@"
            ;;
        zhihu)
            run_opencli zhihu hot "$@"
            ;;
        xueqiu)
            run_opencli xueqiu hot "$@"
            ;;
        v2ex)
            run_opencli v2ex hot "$@"
            ;;
        producthunt|ph)
            run_opencli producthunt hot "$@"
            ;;
        *)
            if ! run_opencli "$platform" hot "$@" 2>/dev/null; then
                if ! run_opencli "$platform" trending "$@" 2>/dev/null; then
                    log_error "Unknown platform: $platform"
                    return 1
                fi
            fi
            ;;
    esac
}

action_fetch() {
    local platform="${1:?Platform required}"
    local command="${2:?Command required}"
    shift 2
    log_info "Running: opencli $platform $command $*"
    run_opencli "$platform" "$command" "$@"
}

action_list() {
    log_info "Listing all available opencli commands"
    run_opencli list "$@"
}

action_status() {
    log_info "Checking opencli status"
    if check_opencli; then
        local version daemon_status bridge_status status_resp
        version=$(opencli --version 2>/dev/null || echo "unknown")

        # Check daemon status — capture JSON to parse bridge connectivity
        status_resp=$(curl -s --max-time 2 localhost:19825/status 2>/dev/null || true)
        if [[ -n "$status_resp" ]]; then
            daemon_status="running"
            # Parse bridge_status from JSON payload; fall back to "disconnected" if absent
            if command -v jq &>/dev/null; then
                bridge_status=$(printf '%s' "$status_resp" | jq -r '.bridge_connected // "disconnected"' 2>/dev/null || echo "disconnected")
                [[ "$bridge_status" == "true" ]] && bridge_status="connected" || true
                [[ "$bridge_status" == "false" ]] && bridge_status="disconnected" || true
            else
                # No jq — check for known truthy fields inline
                if printf '%s' "$status_resp" | grep -ciE '"bridge[_-]connected"\s*:\s*true' >/dev/null 2>&1; then
                    bridge_status="connected"
                else
                    bridge_status="disconnected"
                fi
            fi
        else
            daemon_status="not running"
            bridge_status="disconnected"
        fi

        echo "{\"status\": \"available\", \"version\": \"$version\", \"daemon\": \"$daemon_status\", \"browser_bridge\": \"$bridge_status\"}"
    else
        echo "{\"status\": \"not installed\"}"
        return 1
    fi
}

action_explore() {
    local url="${1:?URL required}"
    shift
    # Only allow HTTPS targets to prevent forwarding plaintext/internal URLs
    if [[ "$url" != https://* ]]; then
        log_error "explore: only HTTPS URLs are supported (got: $url)"
        return 1
    fi
    log_info "Exploring: $url"
    run_opencli explore "$url" "$@"
}

action_desktop() {
    local app="${1:?App name required (cursor, antigravity, chatgpt, etc.)}"
    local command="${2:?Command required}"
    shift 2
    log_info "Desktop: $app $command"
    run_opencli "$app" "$command" "$@"
}

# ── Multi-platform aggregation (for Octopus research phase) ──────────

# Parse platform list: accepts either multiple args or a single comma-separated string
# Usage: _parse_platforms [platform,platform,...] or platform1 platform2 ...
# Outputs platform names space-separated into array variable $platforms
_parse_platform_args() {
    local -n _out_arr="$1"
    shift
    if [[ $# -eq 1 && "$1" == *","* ]]; then
        # Single comma-separated arg: "twitter,reddit,hackernews"
        local IFS=','
        read -ra _out_arr <<< "$1"
    elif [[ $# -gt 0 ]]; then
        _out_arr=("$@")
    fi
}

# Merge a key/value into a JSON object string without requiring jq
_json_merge_no_jq() {
    local base="$1" key="$2" value="$3"
    # Strip trailing } from base and prepend new key/value
    local trimmed="${base%\}}"
    # Detect if we need a comma (base is not empty "{}")
    if [[ "$trimmed" == "{" ]]; then
        printf '%s"%s":%s}' "$trimmed" "$key" "$value"
    else
        printf '%s,"%s":%s}' "$trimmed" "$key" "$value"
    fi
}

action_multi_search() {
    local query="${1:?Search query required}"
    shift
    local -a platforms=("twitter" "reddit" "hackernews")
    _parse_platform_args platforms "$@"

    log_info "Multi-platform search for: $query"

    local result="{}"
    for platform in "${platforms[@]}"; do
        platform="${platform// /}"  # trim any whitespace from comma-split
        [[ -z "$platform" ]] && continue
        local platform_result
        platform_result=$(action_search "$platform" "$query" 2>/dev/null) || platform_result='{"error": "failed"}'
        if command -v jq &>/dev/null; then
            result=$(echo "$result" | jq --arg k "$platform" --argjson v "$platform_result" '. + {($k): $v}' 2>/dev/null) || \
            result=$(echo "$result" | jq --arg k "$platform" --arg v "$platform_result" '. + {($k): $v}')
        else
            result=$(_json_merge_no_jq "$result" "$platform" "$platform_result")
        fi
    done
    echo "$result"
}

action_multi_trending() {
    local -a platforms=("twitter" "reddit" "hackernews")
    _parse_platform_args platforms "$@"

    log_info "Multi-platform trending"

    local result="{}"
    for platform in "${platforms[@]}"; do
        platform="${platform// /}"
        [[ -z "$platform" ]] && continue
        local platform_result
        platform_result=$(action_trending "$platform" 2>/dev/null) || platform_result='{"error": "failed"}'
        if command -v jq &>/dev/null; then
            result=$(echo "$result" | jq --arg k "$platform" --argjson v "$platform_result" '. + {($k): $v}' 2>/dev/null) || \
            result=$(echo "$result" | jq --arg k "$platform" --arg v "$platform_result" '. + {($k): $v}')
        else
            result=$(_json_merge_no_jq "$result" "$platform" "$platform_result")
        fi
    done
    echo "$result"
}

# ── Main Dispatch ────────────────────────────────────────────────────

main() {
    local action="${1:-help}"
    shift 2>/dev/null || true

    case "$action" in
        search)         action_search "$@" ;;
        trending)       action_trending "$@" ;;
        fetch)          action_fetch "$@" ;;
        list)           action_list "$@" ;;
        status)         action_status ;;
        explore)        action_explore "$@" ;;
        desktop)        action_desktop "$@" ;;
        multi-search)   action_multi_search "$@" ;;
        multi-trending) action_multi_trending "$@" ;;
        help|--help|-h)
            cat <<'EOF'
OpenCLI Bridge for Claude Octopus

Usage: opencli-bridge.sh <action> [args...]

Actions:
  search <platform> <query>       Search a platform
  trending <platform>             Get trending content
  fetch <platform> <cmd> [args]   Run any opencli command
  list                            List available commands
  status                          Check opencli availability
  explore <url>                   Discover APIs for a URL
  desktop <app> <cmd>             Control a desktop app
  multi-search <query> [platforms...]   Search across multiple platforms
  multi-trending [platforms...]         Get trending from multiple platforms

Platforms: twitter, reddit, hackernews, youtube, bilibili, zhihu, xueqiu, v2ex, producthunt
Desktop Apps: cursor, antigravity, chatgpt, notion, discord, wechat

Environment:
  OPENCLI_TIMEOUT   Command timeout in seconds (default: 30)
  OPENCLI_FORMAT    Output format: json, table, yaml, md, csv (default: json)
EOF
            ;;
        *)
            log_error "Unknown action: $action (use --help for usage)"
            return 1
            ;;
    esac
}

main "$@"
