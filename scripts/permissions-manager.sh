#!/usr/bin/env bash
# Permissions Manager - Claude Code v2.1.19+ Background Agent Permissions
# Handles user consent for background AI operations with cost transparency

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if running in interactive mode
is_interactive() {
    [[ -t 0 ]] && [[ -t 1 ]]
}

# Estimate API cost for workflow
estimate_cost() {
    local workflow="$1"
    local providers="$2"

    case "$workflow" in
        discover|probe)
            # Research phase: moderate queries
            echo "\$0.05-0.15"
            ;;
        define|grasp)
            # Consensus phase: light queries
            echo "\$0.03-0.08"
            ;;
        develop|tangle)
            # Implementation phase: heavy queries
            echo "\$0.10-0.30"
            ;;
        deliver|ink)
            # Validation phase: moderate queries
            echo "\$0.05-0.15"
            ;;
        embrace)
            # Full workflow: all 4 phases
            echo "\$0.23-0.68"
            ;;
        *)
            echo "\$0.01-0.50"
            ;;
    esac
}

# Request background permission
request_background_permission() {
    local workflow="$1"
    local autonomy_mode="$2"
    local providers="$3"

    # Skip permission in autonomous mode
    if [[ "$autonomy_mode" == "autonomous" ]]; then
        echo "auto-approved"
        return 0
    fi

    # Skip if not interactive
    if ! is_interactive; then
        echo "auto-approved"
        return 0
    fi

    local cost_estimate=$(estimate_cost "$workflow" "$providers")

    echo "" >&2
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}" >&2
    echo -e "${YELLOW}⚠️  BACKGROUND AI OPERATION PERMISSION${NC}" >&2
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}" >&2
    echo "" >&2
    echo -e "This workflow will spawn background AI agents:" >&2
    echo "" >&2

    # Show which providers will be used
    if echo "$providers" | grep -q "codex"; then
        echo -e "  🔴 ${RED}Codex CLI${NC} - Uses your OPENAI_API_KEY" >&2
    fi
    if echo "$providers" | grep -q "gemini"; then
        echo -e "  🟡 ${YELLOW}Gemini CLI${NC} - Uses your GEMINI_API_KEY" >&2
    fi
    echo -e "  🔵 ${CYAN}Claude${NC} - Included with Claude Code" >&2
    echo "" >&2

    echo -e "${CYAN}Estimated API cost: ${cost_estimate}${NC}" >&2
    echo -e "(Depends on query complexity and response length)" >&2
    echo "" >&2

    echo -e "Autonomy mode: ${GREEN}${autonomy_mode}${NC}" >&2

    if [[ "$autonomy_mode" == "semi-autonomous" ]]; then
        echo -e "${YELLOW}Note: You'll only be prompted again if quality gates fail${NC}" >&2
    elif [[ "$autonomy_mode" == "supervised" ]]; then
        echo -e "${YELLOW}Note: You'll be prompted for approval after each phase${NC}" >&2
    fi

    echo "" >&2
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}" >&2
    echo -e "Continue with background AI operations? [y/N] " >&2
    read -r response

    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            echo "approved"
            return 0
            ;;
        *)
            echo "denied"
            return 1
            ;;
    esac
}

# Check if background operation is allowed
check_background_permission() {
    local workflow="$1"
    local autonomy_mode="${2:-supervised}"
    local providers="${3:-codex gemini claude}"

    local permission_result
    permission_result=$(request_background_permission "$workflow" "$autonomy_mode" "$providers")

    if [[ "$permission_result" == "approved" ]] || [[ "$permission_result" == "auto-approved" ]]; then
        return 0
    else
        echo -e "${RED}❌ Background execution cancelled by user${NC}" >&2
        return 1
    fi
}

# Log background operation start
log_background_start() {
    local workflow="$1"
    local providers="$2"
    local session_id="${OCTOPUS_SESSION_ID:-unknown}"

    local log_file="${HOME}/.claude-octopus/background-operations.log"
    mkdir -p "$(dirname "$log_file")"

    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START workflow=$workflow session=$session_id providers=$providers" >> "$log_file"
}

# Log background operation end
log_background_end() {
    local workflow="$1"
    local status="$2"
    local session_id="${OCTOPUS_SESSION_ID:-unknown}"

    local log_file="${HOME}/.claude-octopus/background-operations.log"

    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] END workflow=$workflow session=$session_id status=$status" >> "$log_file"
}

# Main command dispatcher
case "${1:-}" in
    request)
        request_background_permission "$2" "${3:-supervised}" "${4:-codex gemini claude}"
        ;;
    check)
        check_background_permission "$2" "${3:-supervised}" "${4:-codex gemini claude}"
        ;;
    log-start)
        log_background_start "$2" "${3:-codex gemini claude}"
        ;;
    log-end)
        log_background_end "$2" "$3"
        ;;
    estimate)
        estimate_cost "$2" "${3:-codex gemini claude}"
        ;;
    *)
        cat <<EOF
Usage: permissions-manager.sh COMMAND [ARGS]

Commands:
  request WORKFLOW [AUTONOMY] [PROVIDERS]
                           Request permission for background operation
  check WORKFLOW [AUTONOMY] [PROVIDERS]
                           Check if background operation is allowed (exit code)
  log-start WORKFLOW [PROVIDERS]
                           Log background operation start
  log-end WORKFLOW STATUS  Log background operation end
  estimate WORKFLOW [PROVIDERS]
                           Estimate API cost for workflow

Workflows: discover, define, develop, deliver, embrace
Autonomy: supervised, semi-autonomous, autonomous
Providers: Space-separated list (e.g., "codex gemini claude")

EOF
        exit 1
        ;;
esac
