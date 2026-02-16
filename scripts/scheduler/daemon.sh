#!/usr/bin/env bash
# Claude Octopus Scheduler - Daemon (v8.15.0)
# Main tick loop: PID management, heartbeat, signal handlers, FIFO IPC, cron dispatch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/store.sh"
source "${SCRIPT_DIR}/cron.sh"
source "${SCRIPT_DIR}/policy.sh"
source "${SCRIPT_DIR}/runner.sh"

PID_FILE="${RUNTIME_DIR}/daemon.pid"
HEARTBEAT_FILE="${RUNTIME_DIR}/heartbeat"
CONTROL_FIFO="${RUNTIME_DIR}/control.fifo"
DAEMON_LOG="${LOGS_DIR}/daemon.log"
TICK_INTERVAL=30

# Daemon state
DAEMON_RUNNING=true
DAEMON_PAUSED=false

# --- Signal Handlers ---

daemon_handle_sigterm() {
    daemon_log "Received SIGTERM, shutting down gracefully..."
    DAEMON_RUNNING=false
}

daemon_handle_sigint() {
    daemon_log "Received SIGINT, shutting down immediately..."
    DAEMON_RUNNING=false
}

# --- Logging ---

daemon_log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$DAEMON_LOG"
}

# --- PID Management ---

daemon_is_running() {
    if [[ ! -f "$PID_FILE" ]]; then
        return 1
    fi
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [[ -z "$pid" ]]; then
        return 1
    fi
    # Check if process is alive
    if kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    # Stale PID file
    rm -f "$PID_FILE"
    return 1
}

daemon_write_pid() {
    echo $$ > "$PID_FILE"
}

daemon_remove_pid() {
    rm -f "$PID_FILE"
}

# --- FIFO Control ---

daemon_setup_fifo() {
    rm -f "$CONTROL_FIFO"
    mkfifo "$CONTROL_FIFO"
}

daemon_cleanup_fifo() {
    rm -f "$CONTROL_FIFO"
}

# Read a command from FIFO (non-blocking via timeout)
daemon_read_fifo() {
    if [[ ! -p "$CONTROL_FIFO" ]]; then
        return 1
    fi

    local cmd=""
    # Non-blocking read with 1s timeout
    if read -t 1 cmd < "$CONTROL_FIFO" 2>/dev/null; then
        daemon_handle_command "$cmd"
    fi
}

daemon_handle_command() {
    local cmd="$1"
    daemon_log "Received command: $cmd"

    case "$cmd" in
        status)
            local uptime_secs
            uptime_secs=$(( $(date +%s) - DAEMON_START_TIME ))
            daemon_log "STATUS: running=${DAEMON_RUNNING}, paused=${DAEMON_PAUSED}, uptime=${uptime_secs}s"
            ;;
        pause)
            DAEMON_PAUSED=true
            daemon_log "Paused dispatch of new jobs"
            ;;
        resume)
            DAEMON_PAUSED=false
            daemon_log "Resumed dispatch of new jobs"
            ;;
        stop)
            daemon_log "Stop command received"
            DAEMON_RUNNING=false
            ;;
        *)
            daemon_log "Unknown command: $cmd"
            ;;
    esac
}

# --- Heartbeat ---

daemon_heartbeat() {
    touch "$HEARTBEAT_FILE"
}

# --- Tick: Check and dispatch jobs ---

daemon_tick() {
    # Check kill switches first
    if [[ -f "${SWITCHES_DIR}/KILL_ALL" ]]; then
        daemon_log "KILL_ALL switch detected, stopping daemon"
        DAEMON_RUNNING=false
        return
    fi

    if [[ -f "${SWITCHES_DIR}/PAUSE_ALL" ]] || $DAEMON_PAUSED; then
        return
    fi

    # Get current time components
    local minute hour day month weekday
    minute=$(date +%-M)
    hour=$(date +%-H)
    day=$(date +%-d)
    month=$(date +%-m)
    weekday=$(date +%u)

    # Iterate over enabled jobs
    local job_file
    for job_file in "$JOBS_DIR"/*.json; do
        [[ -f "$job_file" ]] || continue

        local enabled
        enabled=$(jq -r '.enabled // false' "$job_file")
        [[ "$enabled" == "true" ]] || continue

        local cron_expr
        cron_expr=$(jq -r '.schedule.cron // ""' "$job_file")
        [[ -n "$cron_expr" ]] || continue

        # Check if cron matches current time
        if cron_matches "$cron_expr" "$minute" "$hour" "$day" "$month" "$weekday" 2>/dev/null; then
            local job_id
            job_id=$(jq -r '.id' "$job_file")
            daemon_log "Cron match for job: $job_id ($cron_expr)"

            # Run policy checks
            local policy_result
            policy_result=$(policy_check "$job_file")
            local allowed
            allowed=$(echo "$policy_result" | jq -r '.allowed // false')

            if [[ "$allowed" != "true" ]]; then
                local reason
                reason=$(echo "$policy_result" | jq -r '.reason // "unknown"')
                daemon_log "Job $job_id blocked by policy: $reason"
                append_event "{\"event\":\"job_blocked\",\"job_id\":\"${job_id}\",\"reason\":\"${reason}\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
                continue
            fi

            # Dispatch job (in background so tick loop continues)
            daemon_log "Dispatching job: $job_id"
            runner_execute "$job_file" &
            local runner_pid=$!
            daemon_log "Job $job_id dispatched with PID $runner_pid"

            # Only dispatch one job per tick (non-reentrant lock ensures sequential execution)
            break
        fi
    done
}

# --- Main Daemon Loop ---

daemon_start() {
    store_init

    # Check for existing daemon
    if daemon_is_running; then
        local existing_pid
        existing_pid=$(cat "$PID_FILE")
        echo "Daemon already running (PID $existing_pid)" >&2
        return 1
    fi

    # Set up
    daemon_write_pid
    daemon_setup_fifo
    trap daemon_handle_sigterm SIGTERM
    trap daemon_handle_sigint SIGINT
    trap 'daemon_remove_pid; daemon_cleanup_fifo' EXIT

    DAEMON_START_TIME=$(date +%s)
    daemon_log "Daemon started (PID $$)"
    daemon_heartbeat

    # Main loop
    while $DAEMON_RUNNING; do
        daemon_heartbeat

        # Process FIFO commands (non-blocking)
        daemon_read_fifo || true

        # Run tick
        daemon_tick

        # Sleep with drift correction: align to TICK_INTERVAL boundaries
        if $DAEMON_RUNNING; then
            local now
            now=$(date +%s)
            local sleep_time=$(( TICK_INTERVAL - (now % TICK_INTERVAL) ))
            (( sleep_time == 0 )) && sleep_time=$TICK_INTERVAL
            sleep "$sleep_time" &
            local sleep_pid=$!
            # Allow signals to interrupt sleep
            wait "$sleep_pid" 2>/dev/null || true
        fi
    done

    daemon_log "Daemon stopped"
}

# --- Daemon Control Functions (called from CLI) ---

daemon_stop() {
    if ! daemon_is_running; then
        echo "Daemon is not running" >&2
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")
    echo "Stopping daemon (PID $pid)..."
    kill -TERM "$pid" 2>/dev/null || true

    # Wait up to 30s for graceful shutdown
    local waited=0
    while kill -0 "$pid" 2>/dev/null && (( waited < 30 )); do
        sleep 1
        waited=$((waited + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        echo "Force killing daemon..."
        kill -KILL "$pid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
    echo "Daemon stopped"
}

daemon_status() {
    store_init

    if daemon_is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        local uptime_secs=0
        if [[ -f "$HEARTBEAT_FILE" ]]; then
            local last_heartbeat
            last_heartbeat=$(stat -f %m "$HEARTBEAT_FILE" 2>/dev/null || stat -c %Y "$HEARTBEAT_FILE" 2>/dev/null || echo "0")
            local now
            now=$(date +%s)
            local heartbeat_age=$(( now - last_heartbeat ))
            echo "Daemon: RUNNING (PID $pid)"
            echo "Last heartbeat: ${heartbeat_age}s ago"
        else
            echo "Daemon: RUNNING (PID $pid)"
            echo "Last heartbeat: unknown"
        fi
    else
        echo "Daemon: STOPPED"
    fi

    # Show kill switches
    [[ -f "${SWITCHES_DIR}/KILL_ALL" ]]  && echo "Kill switch: KILL_ALL ACTIVE"
    [[ -f "${SWITCHES_DIR}/PAUSE_ALL" ]] && echo "Kill switch: PAUSE_ALL ACTIVE"

    # Show job count
    local job_count=0
    local enabled_count=0
    local job_file
    for job_file in "$JOBS_DIR"/*.json; do
        [[ -f "$job_file" ]] || continue
        job_count=$((job_count + 1))
        local enabled
        enabled=$(jq -r '.enabled // false' "$job_file")
        [[ "$enabled" == "true" ]] && enabled_count=$((enabled_count + 1))
    done
    echo "Jobs: ${enabled_count} enabled / ${job_count} total"

    # Show daily spend
    local daily_spend
    daily_spend=$(get_daily_spend)
    echo "Daily spend: \$${daily_spend}"
}

daemon_emergency_stop() {
    store_init

    # Create kill switch
    touch "${SWITCHES_DIR}/KILL_ALL"
    echo "KILL_ALL switch created"

    # Stop daemon if running
    if daemon_is_running; then
        daemon_stop
    fi

    echo "Emergency stop complete. Remove ${SWITCHES_DIR}/KILL_ALL to allow restart."
}

# Allow sourcing without executing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        start) daemon_start ;;
        stop)  daemon_stop ;;
        status) daemon_status ;;
        emergency-stop) daemon_emergency_stop ;;
        *) echo "Usage: daemon.sh {start|stop|status|emergency-stop}" >&2; exit 1 ;;
    esac
fi
