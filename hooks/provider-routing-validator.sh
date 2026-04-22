#!/bin/bash
# provider-routing-validator.sh
# Validates provider availability before workflow execution
# Part of Claude Code v2.1.12+ integration

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Get the plugin root directory
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Log function
log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] provider-routing-validator: $*" >&2
}

# Check provider availability
check_provider() {
    local provider="$1"

    case "$provider" in
        codex)
            if command -v codex &>/dev/null; then
                log "INFO" "Codex CLI available"
                return 0
            else
                log "WARN" "Codex CLI not found"
                return 1
            fi
            ;;
        gemini)
            if command -v gemini &>/dev/null; then
                log "INFO" "Gemini CLI available"
                return 0
            else
                log "WARN" "Gemini CLI not found"
                return 1
            fi
            ;;
        *)
            log "DEBUG" "Unknown provider: $provider"
            return 0
            ;;
    esac
}

# Parse orchestrate.sh command to determine which providers will be used
parse_workflow_command() {
    local command="$1"

    log "INFO" "Validating provider routing for command: ${command:0:100}"

    # Detect workflow type
    if [[ "$command" =~ (probe|discover) ]]; then
        log "INFO" "Discover workflow detected - will use Codex + Gemini"
        check_provider "codex" || echo "⚠️  Codex CLI unavailable - workflow will run in degraded mode"
        check_provider "gemini" || echo "⚠️  Gemini CLI unavailable - workflow will run in degraded mode"
    elif [[ "$command" =~ (grasp|define) ]]; then
        log "INFO" "Define workflow detected - will use Gemini + Claude"
        check_provider "gemini" || echo "⚠️  Gemini CLI unavailable - workflow will run in degraded mode"
    elif [[ "$command" =~ (tangle|develop) ]]; then
        log "INFO" "Develop workflow detected - will use Codex"
        check_provider "codex" || echo "⚠️  Codex CLI unavailable - workflow will run in degraded mode"
    elif [[ "$command" =~ (ink|deliver) ]]; then
        log "INFO" "Deliver workflow detected - will use Claude primarily"
    elif [[ "$command" =~ embrace ]]; then
        log "INFO" "Full embrace workflow detected - will use all providers"
        check_provider "codex" || echo "⚠️  Codex CLI unavailable - some phases will run in degraded mode"
        check_provider "gemini" || echo "⚠️  Gemini CLI unavailable - some phases will run in degraded mode"
    fi
}

# v8.19: Check smoke test cache status (Issue #34)
# Non-blocking: warns only, does not prevent execution
check_smoke_test_status() {
    local workspace_dir="${CLAUDE_OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus}"
    local cache_file="${workspace_dir}/.smoke-test-cache"

    [[ -f "$cache_file" ]] || return 0

    local cache_time cache_status current_time cache_age cache_ttl
    cache_time=$(head -1 "$cache_file" 2>/dev/null || echo "0")
    cache_status=$(sed -n '3p' "$cache_file" 2>/dev/null || echo "")
    current_time=$(date +%s)
    cache_age=$((current_time - cache_time))
    cache_ttl=3600

    # Only warn if cache is recent and shows failure
    if [[ $cache_age -lt $cache_ttl && "$cache_status" == "1" ]]; then
        echo "⚠️  Provider smoke test previously failed — workflow may produce empty results"
        echo "   Re-run: bash orchestrate.sh doctor smoke"
        log "WARN" "Smoke test cache indicates previous failure (${cache_age}s ago)"
    fi
}

# Main validation logic
main() {
    log "INFO" "Provider routing validation hook triggered"

    # Read hook input from stdin (CC hook protocol: JSON with tool_input.command)
    local stdin_data=""
    if [[ ! -t 0 ]]; then
        stdin_data=$(cat 2>/dev/null || true)
    fi

    # Extract the bash command from hook JSON input
    local bash_command=""
    if [[ -n "$stdin_data" ]]; then
        if command -v jq &>/dev/null; then
            bash_command=$(printf '%s' "$stdin_data" | jq -r '.tool_input.command // empty' 2>/dev/null) || true
        elif command -v python3 &>/dev/null; then
            bash_command=$(printf '%s' "$stdin_data" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))" 2>/dev/null) || true
        fi
    fi

    # Fallback to positional arg (for manual testing)
    [[ -z "$bash_command" ]] && bash_command="${1:-}"

    if [[ -z "$bash_command" ]]; then
        log "DEBUG" "No command to validate, proceeding"
        exit 0
    fi

    # Check smoke test status (non-blocking warning)
    check_smoke_test_status

    # Validate providers for this workflow
    parse_workflow_command "$bash_command"

    log "INFO" "Provider routing validation complete"
    exit 0
}

# Run main function
main "$@"
