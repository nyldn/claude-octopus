#!/usr/bin/env bash
# Shared quota fast-fail watcher for provider CLIs that retry for a long time
# after quota exhaustion instead of exiting promptly.

OCTOPUS_QUOTA_PATTERN='QUOTA_EXHAUSTED|TerminalQuotaError|exhausted your capacity|RetryableQuotaError|Attempt [0-9]+ failed.*exhausted'

quota_watcher_has_match() {
    local temp_err="$1"
    local temp_out="$2"

    grep -qE "$OCTOPUS_QUOTA_PATTERN" "$temp_err" 2>/dev/null || \
        grep -qE "$OCTOPUS_QUOTA_PATTERN" "$temp_out" 2>/dev/null
}

start_quota_watcher() {
    local target_pid="$1"
    local temp_err="$2"
    local temp_out="$3"
    local kill_callback="$4"
    local warning_message="${5:-Quota exhaustion detected - fast-failing}"

    > "$temp_err"
    > "$temp_out"

    (
        while kill -0 "$target_pid" 2>/dev/null; do
            sleep 2
            if quota_watcher_has_match "$temp_err" "$temp_out"; then
                log "WARN" "$warning_message"
                "$kill_callback" "$target_pid"
                break
            fi
        done
    ) >/dev/null &
    echo "$!"
}

stop_quota_watcher() {
    local watcher_pid="${1:-}"
    [[ -n "$watcher_pid" ]] || return 0

    kill "$watcher_pid" 2>/dev/null || true
    wait "$watcher_pid" 2>/dev/null || true
}
