#!/usr/bin/env bash
# Claude Octopus Scheduler - CLI Entry Point (v8.15.0)
# Subcommands: start, stop, status, add, list, remove, enable, disable, logs, emergency-stop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/store.sh"
source "${SCRIPT_DIR}/cron.sh"
source "${SCRIPT_DIR}/daemon.sh"

VERSION="8.15.0"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    cat <<EOF
${BOLD}Claude Octopus Scheduler v${VERSION}${NC}

${BOLD}Daemon management:${NC}
  start              Start the scheduler daemon
  stop               Graceful shutdown (waits for current job)
  status             Show daemon state, uptime, next scheduled job
  emergency-stop     Kill all jobs and create KILL_ALL switch

${BOLD}Job management:${NC}
  add <file.json>    Add a job from a JSON definition file
  list               List all jobs with status and next run
  remove <id>        Remove a job by ID
  enable <id>        Enable a disabled job
  disable <id>       Disable a job
  logs [id]          Tail daemon log or job-specific logs

${BOLD}Examples:${NC}
  octopus-scheduler.sh start
  octopus-scheduler.sh add nightly-security.json
  octopus-scheduler.sh list
  octopus-scheduler.sh logs nightly-security
EOF
}

# --- Job Management ---

cmd_add() {
    local file="${1:-}"
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        echo -e "${RED}ERROR:${NC} Job file not found: $file" >&2
        exit 1
    fi

    # Validate JSON
    if ! jq empty "$file" 2>/dev/null; then
        echo -e "${RED}ERROR:${NC} Invalid JSON in $file" >&2
        exit 1
    fi

    # Validate required fields
    local id workflow
    id=$(jq -r '.id // ""' "$file")
    workflow=$(jq -r '.task.workflow // ""' "$file")

    if [[ -z "$id" ]]; then
        echo -e "${RED}ERROR:${NC} Job must have an 'id' field" >&2
        exit 1
    fi
    if [[ -z "$workflow" ]]; then
        echo -e "${RED}ERROR:${NC} Job must have a 'task.workflow' field" >&2
        exit 1
    fi

    # Validate cron expression
    local cron_expr
    cron_expr=$(jq -r '.schedule.cron // ""' "$file")
    if [[ -n "$cron_expr" ]] && ! cron_validate "$cron_expr" 2>/dev/null; then
        echo -e "${RED}ERROR:${NC} Invalid cron expression: $cron_expr" >&2
        exit 1
    fi

    # Run policy checks
    local policy_result
    policy_result=$(policy_check "$file" 2>/dev/null) || true
    local allowed
    allowed=$(echo "$policy_result" | jq -r '.allowed // false' 2>/dev/null)

    if [[ "$allowed" != "true" ]]; then
        local reason
        reason=$(echo "$policy_result" | jq -r '.reason // "Policy check failed"' 2>/dev/null)
        echo -e "${RED}ERROR:${NC} Policy rejected job: $reason" >&2
        exit 1
    fi

    # Copy to jobs directory
    store_init
    cp "$file" "${JOBS_DIR}/${id}.json"
    echo -e "${GREEN}Added job:${NC} $id"

    local name
    name=$(jq -r '.name // "Untitled"' "$file")
    echo "  Name: $name"
    echo "  Workflow: $workflow"
    echo "  Schedule: $cron_expr"

    local next_run
    next_run=$(cron_next_run "$cron_expr" 2>/dev/null || echo "unknown")
    echo "  Next run: $next_run"
}

cmd_list() {
    store_init

    local found=false
    local job_file

    printf "${BOLD}%-20s %-30s %-8s %-18s %-20s${NC}\n" "ID" "NAME" "ENABLED" "SCHEDULE" "NEXT RUN"
    printf "%-20s %-30s %-8s %-18s %-20s\n" "----" "----" "-------" "--------" "--------"

    for job_file in "$JOBS_DIR"/*.json; do
        [[ -f "$job_file" ]] || continue
        found=true

        local id name enabled cron_expr
        id=$(jq -r '.id // "?"' "$job_file")
        name=$(jq -r '.name // "Untitled"' "$job_file")
        enabled=$(jq -r '.enabled // false' "$job_file")
        cron_expr=$(jq -r '.schedule.cron // ""' "$job_file")

        local next_run="N/A"
        if [[ "$enabled" == "true" ]] && [[ -n "$cron_expr" ]]; then
            next_run=$(cron_next_run "$cron_expr" 2>/dev/null || echo "unknown")
        fi

        local enabled_display
        if [[ "$enabled" == "true" ]]; then
            enabled_display="${GREEN}yes${NC}"
        else
            enabled_display="${RED}no${NC}"
        fi

        printf "%-20s %-30s " "$id" "$name"
        echo -en "$enabled_display"
        printf "     %-18s %-20s\n" "$cron_expr" "$next_run"
    done

    if ! $found; then
        echo "No jobs found. Use 'add <file.json>' to create one."
    fi
}

cmd_remove() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo -e "${RED}ERROR:${NC} Job ID required" >&2
        exit 1
    fi

    local job_file="${JOBS_DIR}/${id}.json"
    if [[ ! -f "$job_file" ]]; then
        echo -e "${RED}ERROR:${NC} Job not found: $id" >&2
        exit 1
    fi

    rm -f "$job_file"
    echo -e "${GREEN}Removed job:${NC} $id"
}

cmd_enable() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo -e "${RED}ERROR:${NC} Job ID required" >&2
        exit 1
    fi

    local job_file="${JOBS_DIR}/${id}.json"
    if [[ ! -f "$job_file" ]]; then
        echo -e "${RED}ERROR:${NC} Job not found: $id" >&2
        exit 1
    fi

    local updated
    updated=$(jq '.enabled = true' "$job_file")
    store_atomic_write "$job_file" "$updated"
    echo -e "${GREEN}Enabled job:${NC} $id"
}

cmd_disable() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo -e "${RED}ERROR:${NC} Job ID required" >&2
        exit 1
    fi

    local job_file="${JOBS_DIR}/${id}.json"
    if [[ ! -f "$job_file" ]]; then
        echo -e "${RED}ERROR:${NC} Job not found: $id" >&2
        exit 1
    fi

    local updated
    updated=$(jq '.enabled = false' "$job_file")
    store_atomic_write "$job_file" "$updated"
    echo -e "${YELLOW}Disabled job:${NC} $id"
}

cmd_logs() {
    local id="${1:-}"

    if [[ -z "$id" ]]; then
        # Show daemon log
        if [[ -f "$DAEMON_LOG" ]]; then
            tail -50 "$DAEMON_LOG"
        else
            echo "No daemon log found"
        fi
    else
        # Show job-specific logs
        local job_log_dir="${LOGS_DIR}/${id}"
        if [[ ! -d "$job_log_dir" ]]; then
            echo "No logs found for job: $id"
            return
        fi

        local latest
        latest=$(ls -t "$job_log_dir"/*.log 2>/dev/null | head -1)
        if [[ -n "$latest" ]]; then
            echo -e "${BOLD}Latest log for $id:${NC} $latest"
            echo "---"
            tail -50 "$latest"
        else
            echo "No log files found for job: $id"
        fi
    fi
}

# --- Main ---

main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        start)          daemon_start ;;
        stop)           daemon_stop ;;
        status)         daemon_status ;;
        emergency-stop) daemon_emergency_stop ;;
        add)            cmd_add "$@" ;;
        list)           cmd_list ;;
        remove)         cmd_remove "$@" ;;
        enable)         cmd_enable "$@" ;;
        disable)        cmd_disable "$@" ;;
        logs)           cmd_logs "$@" ;;
        -h|--help|help) usage ;;
        "")             usage ;;
        *)
            echo -e "${RED}Unknown command:${NC} $cmd" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
