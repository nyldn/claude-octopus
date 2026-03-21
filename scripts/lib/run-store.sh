#!/usr/bin/env bash
# Run Store — Structured JSONL storage for workflow results (v9.8.0)
# Canonical location: ~/.claude-octopus/runs/run-log.jsonl
# Schema: {date, workflow, providers, timestamp, findings_count, status, duration_ms, metadata}
# Uses octo_db_append from intelligence.sh for capped JSONL writes
#
# Kill switch: OCTO_RUN_STORE=off
# ═══════════════════════════════════════════════════════════════════════════════

_RUN_STORE_DIR="${HOME}/.claude-octopus/runs"
_RUN_STORE_FILE="${_RUN_STORE_DIR}/run-log.jsonl"
_RUN_STORE_MAX_ENTRIES=1000

# Record a workflow run completion
# Args: workflow providers status [findings_count] [duration_ms] [metadata_json]
# Example: record_run "discover" "codex,gemini,claude" "success" "12" "45000" '{"topic":"auth"}'
record_run() {
    [[ "${OCTO_RUN_STORE:-on}" == "off" ]] && return 0

    local workflow="$1"
    local providers="$2"
    local run_status="$3"
    local findings_count="${4:-0}"
    local duration_ms="${5:-0}"
    local empty_json='{}'
    local metadata="${6:-$empty_json}"

    local date_stamp
    date_stamp=$(date +%Y-%m-%d)
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)

    local entry
    if command -v jq &>/dev/null; then
        entry=$(jq -n -c \
            --arg d "$date_stamp" \
            --arg w "$workflow" \
            --arg p "$providers" \
            --arg ts "$timestamp" \
            --arg fc "$findings_count" \
            --arg s "$run_status" \
            --arg dm "$duration_ms" \
            --argjson m "$metadata" \
            '{date:$d, workflow:$w, providers:$p, timestamp:$ts, findings_count:($fc|tonumber), status:$s, duration_ms:($dm|tonumber), metadata:$m}' 2>/dev/null)
    else
        # Fallback without jq
        entry="{\"date\":\"$date_stamp\",\"workflow\":\"$workflow\",\"providers\":\"$providers\",\"timestamp\":\"$timestamp\",\"findings_count\":$findings_count,\"status\":\"$run_status\",\"duration_ms\":$duration_ms,\"metadata\":$metadata}"
    fi

    [[ -z "$entry" ]] && return 1

    mkdir -p "$_RUN_STORE_DIR" 2>/dev/null || true

    # Use octo_db_append if available (from intelligence.sh), otherwise inline
    if type octo_db_append &>/dev/null; then
        octo_db_append "$_RUN_STORE_FILE" "$entry" "$_RUN_STORE_MAX_ENTRIES"
    else
        echo "$entry" >> "$_RUN_STORE_FILE"
        # Inline cap enforcement
        if [[ -f "$_RUN_STORE_FILE" ]]; then
            local count
            count=$(wc -l < "$_RUN_STORE_FILE" 2>/dev/null | tr -d ' ')
            if [[ "$count" -gt "$_RUN_STORE_MAX_ENTRIES" ]]; then
                tail -n "$_RUN_STORE_MAX_ENTRIES" "$_RUN_STORE_FILE" > "${_RUN_STORE_FILE}.tmp" && mv "${_RUN_STORE_FILE}.tmp" "$_RUN_STORE_FILE"
            fi
        fi
    fi

    log "DEBUG" "Run store: recorded $workflow ($run_status, ${findings_count} findings)" 2>/dev/null || true
}

# Record an experiment iteration (for /octo:loop metric mode)
# Args: iteration metric_value status description [commit_hash]
record_experiment() {
    [[ "${OCTO_RUN_STORE:-on}" == "off" ]] && return 0

    local iteration="$1"
    local metric_value="$2"
    local exp_status="$3"
    local description="$4"
    local commit_hash="${5:-}"

    local date_stamp
    date_stamp=$(date +%Y-%m-%d)
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    local experiment_file="${_RUN_STORE_DIR}/experiments/${date_stamp}.jsonl"

    mkdir -p "${_RUN_STORE_DIR}/experiments" 2>/dev/null || true

    local entry
    if command -v jq &>/dev/null; then
        entry=$(jq -n -c \
            --arg i "$iteration" \
            --arg ts "$timestamp" \
            --arg m "$metric_value" \
            --arg s "$exp_status" \
            --arg d "$description" \
            --arg c "$commit_hash" \
            '{iteration:($i|tonumber), timestamp:$ts, metric:($m|tonumber), status:$s, description:$d, commit:$c}' 2>/dev/null)
    else
        entry="{\"iteration\":$iteration,\"timestamp\":\"$timestamp\",\"metric\":$metric_value,\"status\":\"$exp_status\",\"description\":\"$description\",\"commit\":\"$commit_hash\"}"
    fi

    echo "$entry" >> "$experiment_file"
}

# Query recent runs — returns JSONL lines matching criteria
# Args: [count] [workflow_filter] [date_filter]
# Example: query_runs 10 "discover" "2026-03-21"
query_runs() {
    local count="${1:-20}"
    local workflow_filter="${2:-}"
    local date_filter="${3:-}"

    [[ ! -f "$_RUN_STORE_FILE" ]] && return 0

    local result
    if [[ -n "$workflow_filter" && -n "$date_filter" ]]; then
        result=$(grep "\"workflow\":\"$workflow_filter\"" "$_RUN_STORE_FILE" 2>/dev/null | grep "\"date\":\"$date_filter\"" | tail -n "$count")
    elif [[ -n "$workflow_filter" ]]; then
        result=$(grep "\"workflow\":\"$workflow_filter\"" "$_RUN_STORE_FILE" 2>/dev/null | tail -n "$count")
    elif [[ -n "$date_filter" ]]; then
        result=$(grep "\"date\":\"$date_filter\"" "$_RUN_STORE_FILE" 2>/dev/null | tail -n "$count")
    else
        result=$(tail -n "$count" "$_RUN_STORE_FILE" 2>/dev/null)
    fi

    echo "$result"
}

# Get run store summary stats
# Returns: total runs, unique workflows, date range
get_run_store_stats() {
    [[ ! -f "$_RUN_STORE_FILE" ]] && { echo "No runs recorded yet."; return 0; }

    local total
    total=$(wc -l < "$_RUN_STORE_FILE" 2>/dev/null | tr -d ' ')

    local first_date last_date
    first_date=$(head -1 "$_RUN_STORE_FILE" 2>/dev/null | grep -oE '"date":"[^"]*"' | head -1 | sed 's/"date":"//;s/"//')
    last_date=$(tail -1 "$_RUN_STORE_FILE" 2>/dev/null | grep -oE '"date":"[^"]*"' | head -1 | sed 's/"date":"//;s/"//')

    local workflows
    workflows=$(grep -oE '"workflow":"[^"]*"' "$_RUN_STORE_FILE" 2>/dev/null | sort -u | sed 's/"workflow":"//;s/"//' | tr '\n' ', ' | sed 's/,$//')

    local success_count
    success_count=$(grep -c '"status":"success"' "$_RUN_STORE_FILE" 2>/dev/null || echo 0)

    echo "Total runs: $total"
    echo "Success rate: $success_count/$total"
    echo "Date range: ${first_date:-unknown} to ${last_date:-unknown}"
    echo "Workflows: ${workflows:-none}"
}
