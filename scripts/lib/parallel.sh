#!/usr/bin/env bash
# parallel.sh — Parallel execution primitives: fan-out, map-reduce, aggregation
#
# Functions:
#   fan_out
#   extract_json_field
#   validate_agent_type
#   parallel_execute
#   map_reduce
#   aggregate_results
#
# Extracted from orchestrate.sh (v9.7.8)
# Source-safe: no main execution block.

# _fan_out_agents_from_config (v9.31.0): read .routing.features.parallel from
# providers.json. /octo:model-config wizard writes this array under "Parallel
# execution providers"; before this change there was no consumer.
# Output: one agent_type per line. Empty when config absent/empty/missing.
_fan_out_agents_from_config() {
    local feature="${1:-parallel}"
    local breadth="${OCTOPUS_FANOUT_BREADTH:-${OCTOPUS_RESEARCH_BREADTH:-}}"
    local config_file="${HOME}/.claude-octopus/config/providers.json"
    [[ ! -f "$config_file" ]] && return 0
    command -v jq >/dev/null 2>&1 || return 0

    jq -r --arg feature "$feature" --arg breadth "$breadth" '
        if $feature == "research" and $breadth != "" then
            (.routing.features.research_breadth[$breadth] // .routing.features.research // .routing.features.parallel // [])
        else
            (.routing.features[$feature] // .routing.features.parallel // [])
        end
        | if type == "array" then .[] else empty end
    ' "$config_file" 2>/dev/null || true
}

# Resolve the preferred non-Codex dispatch seat for fan-out / map-reduce.
# AGY (Antigravity) is the sole Google seat. Legacy gemini* configuration is
# canonicalized to AGY at the provider boundary. Always echoes a usable agent.
_parallel_google_seat() {
    if { ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed agy; } \
        && command -v agy >/dev/null 2>&1; then
        echo "agy"; return 0
    fi
    echo "claude-sonnet"; return 0
}

fan_out() {
    local prompt="$1"
    local agents=()
    local pids=()
    local task_group
    task_group=$(date +%s)

    # v9.31.0: honor wizard-configured participants if present
    local _configured
    _configured=$(_fan_out_agents_from_config "${OCTOPUS_FANOUT_FEATURE:-parallel}")
    if [[ -n "$_configured" ]]; then
        while IFS= read -r _a; do
            [[ -z "$_a" ]] && continue
            local _resolved
            if _resolved=$(resolve_provider_to_agent "$_a"); then
                agents+=("$_resolved")
            else
                log WARN "Fan-out: skipping unknown agent '$_a' (not in AVAILABLE_AGENTS)"
            fi
        done <<< "$_configured"
    fi

    # Fallback to default pair when config absent or all entries invalid.
    # Second seat prefers AGY, the sole Google seat.
    [[ ${#agents[@]} -eq 0 ]] && agents=("codex" "$(_parallel_google_seat)")

    log INFO "Fan-out: Sending prompt to ${#agents[@]} agents (${agents[*]})"
    echo ""

    for agent in "${agents[@]}"; do
        local pid
        if pid=$(spawn_agent_capture_pid "$agent" "$prompt" "${task_group}-${agent}"); then
            pids+=("$pid")
        else
            log WARN "Fan-out: failed to spawn $agent"
        fi
        sleep 0.5
    done

    log INFO "All agents spawned. PIDs: ${pids[*]}"
    echo ""
    echo -e "${CYAN}Monitor progress:${NC}"
    echo "  $(basename "$0") status"
    echo ""
    echo -e "${CYAN}View results:${NC}"
    echo "  ls -la $RESULTS_DIR/"
    echo "  $(basename "$0") agent-summary"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Safe JSON field extraction with validation
# Returns empty string on failure, logs errors
# ═══════════════════════════════════════════════════════════════════════════════
extract_json_field() {
    local json="$1"
    local field="$2"
    local required="${3:-true}"

    local value
    if ! value=$(echo "$json" | jq -r ".$field // empty" 2>/dev/null); then
        log ERROR "JSON parse error extracting field '$field'"
        return 1
    fi

    if [[ -z "$value" || "$value" == "null" ]]; then
        if [[ "$required" == "true" ]]; then
            log ERROR "Required field '$field' is missing or null"
            return 1
        fi
        echo ""
        return 0
    fi

    echo "$value"
}

# Validate agent type against allowlist
validate_agent_type() {
    local agent="$1"
    if [[ " $AVAILABLE_AGENTS " != *" $agent "* ]]; then
        log ERROR "Invalid agent type: $agent (allowed: $AVAILABLE_AGENTS)"
        return 1
    fi
    return 0
}

# Return success once a tracked PID has exited. A direct child can remain as a
# zombie until wait(1) collects its status, so kill -0 alone is not sufficient.
_parallel_pid_has_finished() {
    local pid="$1" state=""
    if ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    state=$(ps -o stat= -p "$pid" 2>/dev/null | awk 'NR == 1 { print $1 }') || state=""
    [[ "$state" == Z* ]]
}

_parallel_collect_outcome() {
    local outcome_dir="$1" pid="$2" sequence="$3" id="$4" agent="$5"
    local child_status marker="" done_file
    if wait "$pid" 2>/dev/null; then
        child_status=0
    else
        child_status=$?
    fi

    # spawn_agent_capture_pid returns the provider process, which production
    # starts below a short-lived wrapper. That PID is not this shell's child, so
    # wait returns ECHILD. spawn_agent writes the real exit status atomically.
    done_file="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents/${id}.done"
    if [[ -f "$done_file" ]]; then
        marker=$(<"$done_file")
        rm -f "$done_file" 2>/dev/null || true
        if [[ "$marker" =~ ^[0-9]+$ ]]; then
            child_status="$marker"
        else
            _parallel_write_outcome "$outcome_dir" "$sequence" "$id" true "$agent" true \
                "failed" "${marker:-missing-done-marker}" ""
            return 1
        fi
    elif [[ "$child_status" -eq 127 ]]; then
        _parallel_write_outcome "$outcome_dir" "$sequence" "$id" true "$agent" true \
            "failed" "missing-done-marker" ""
        return 1
    fi

    if [[ "$child_status" -eq 0 ]]; then
        _parallel_write_outcome "$outcome_dir" "$sequence" "$id" true "$agent" true \
            "completed" "completed" 0
        return 0
    fi

    _parallel_write_outcome "$outcome_dir" "$sequence" "$id" true "$agent" true \
        "failed" "child-exit" "$child_status"
    return 1
}

_parallel_write_outcome() {
    local outcome_dir="$1" sequence="$2" id="$3" id_present="$4"
    local agent="$5" agent_present="$6" status="$7" reason="$8"
    local exit_code="${9:-}" exit_json="null" outcome_file
    [[ -n "$exit_code" ]] && exit_json="$exit_code"
    outcome_file=$(printf '%s/%09d.json' "$outcome_dir" "$sequence")

    jq -n \
        --argjson sequence "$sequence" \
        --arg id "$id" \
        --argjson id_present "$id_present" \
        --arg agent "$agent" \
        --argjson agent_present "$agent_present" \
        --arg status "$status" \
        --arg reason "$reason" \
        --argjson exit_code "$exit_json" \
        '{
            sequence: $sequence,
            id: (if $id_present then $id else null end),
            agent: (if $agent_present then $agent else null end),
            status: $status,
            reason: $reason,
            exit_code: $exit_code
        }' > "$outcome_file"
}

_parallel_write_report() {
    local outcome_dir="$1" report_file="$2" overall_status="$3"
    local total="$4" completed="$5" skipped="$6" failed="$7"
    local aggregation_exit_code="$8" report_dir report_tmp
    local outcome_files=("$outcome_dir"/*.json)

    report_dir=$(dirname "$report_file")
    mkdir -p "$report_dir" || return 1
    report_tmp="${report_file}.tmp.$$.$RANDOM"

    if [[ -e "${outcome_files[0]}" ]]; then
        jq -s \
            --arg status "$overall_status" \
            --argjson total "$total" \
            --argjson completed "$completed" \
            --argjson skipped "$skipped" \
            --argjson failed "$failed" \
            --argjson aggregation_exit_code "$aggregation_exit_code" \
            '{
                schema_version: 1,
                status: $status,
                counts: {
                    total: $total,
                    completed: $completed,
                    skipped: $skipped,
                    failed: $failed
                },
                aggregation_exit_code: $aggregation_exit_code,
                results: sort_by(.sequence)
            }' "${outcome_files[@]}" > "$report_tmp" || {
                rm -f "$report_tmp"
                return 1
            }
    else
        jq -n \
            --arg status "$overall_status" \
            --argjson aggregation_exit_code "$aggregation_exit_code" \
            '{
                schema_version: 1,
                status: $status,
                counts: {total: 0, completed: 0, skipped: 0, failed: 0},
                aggregation_exit_code: $aggregation_exit_code,
                results: []
            }' > "$report_tmp" || {
                rm -f "$report_tmp"
                return 1
            }
    fi

    mv "$report_tmp" "$report_file"
}

parallel_execute() {
    local tasks_file="${1:-$TASKS_FILE}"
    local _parallel_cron_disabled=false
    local outcome_dir="" spawn_output=""
    local _parallel_previous_int_trap="" _parallel_previous_term_trap=""
    local _parallel_previous_exit_trap=""
    _parallel_cleanup_cron() {
        if [[ "$_parallel_cron_disabled" == "true" ]]; then
            unset CLAUDE_CODE_DISABLE_CRON 2>/dev/null || true
        fi
    }
    _parallel_cleanup_resources() {
        [[ -z "$spawn_output" ]] || rm -f "$spawn_output" 2>/dev/null || true
        [[ -z "$outcome_dir" ]] || rm -rf "$outcome_dir" 2>/dev/null || true
        spawn_output=""
        outcome_dir=""
        _parallel_cleanup_cron
    }
    _parallel_restore_traps() {
        if [[ -n "$_parallel_previous_int_trap" ]]; then
            eval "$_parallel_previous_int_trap"
        else
            trap - INT
        fi
        if [[ -n "$_parallel_previous_term_trap" ]]; then
            eval "$_parallel_previous_term_trap"
        else
            trap - TERM
        fi
        if [[ -n "$_parallel_previous_exit_trap" ]]; then
            eval "$_parallel_previous_exit_trap"
        else
            trap - EXIT
        fi
    }
    _parallel_invoke_saved_trap() {
        local saved_trap="$1"
        [[ -n "$saved_trap" ]] || return 0
        eval "set -- ${saved_trap#trap -- }"
        eval "$1"
    }
    _parallel_handle_signal() {
        local signal="$1" signal_status=143 saved_trap current_pid
        [[ "$signal" == "INT" ]] && signal_status=130
        if [[ "$signal" == "INT" ]]; then
            saved_trap="$_parallel_previous_int_trap"
        else
            saved_trap="$_parallel_previous_term_trap"
        fi
        _parallel_cleanup_resources
        _parallel_restore_traps
        if [[ -n "$saved_trap" ]]; then
            _parallel_invoke_saved_trap "$saved_trap"
        else
            current_pid="$(sh -c 'printf "%s\n" "$PPID"')"
            kill -s "$signal" "$current_pid" 2>/dev/null || true
        fi
        exit "$signal_status"
    }
    _parallel_handle_exit() {
        local exit_status=$?
        local saved_trap="$_parallel_previous_exit_trap"
        _parallel_cleanup_resources
        if [[ -n "$_parallel_previous_int_trap" ]]; then
            eval "$_parallel_previous_int_trap"
        else
            trap - INT
        fi
        if [[ -n "$_parallel_previous_term_trap" ]]; then
            eval "$_parallel_previous_term_trap"
        else
            trap - TERM
        fi
        trap - EXIT
        _parallel_invoke_saved_trap "$saved_trap"
        exit "$exit_status"
    }

    # v8.48.0: Disable cron during parallel execution to prevent interference
    if [[ "$SUPPORTS_DISABLE_CRON_ENV" == "true" ]]; then
        export CLAUDE_CODE_DISABLE_CRON=1
        _parallel_cron_disabled=true
        log DEBUG "Cron jobs disabled for parallel execution duration"
    fi

    if [[ ! -f "$tasks_file" ]]; then
        log ERROR "Tasks file not found: $tasks_file"
        log INFO "Run '$(basename "$0") init' to create a template"
        _parallel_cleanup_cron
        return 1
    fi

    log INFO "Loading tasks from: $tasks_file"

    if ! command -v jq &> /dev/null; then
        log ERROR "jq is required for parallel execution. Install with: brew install jq"
        _parallel_cleanup_cron
        return 1
    fi

    # SECURITY: Validate JSON structure first
    if ! jq -e . "$tasks_file" >/dev/null 2>&1; then
        log ERROR "Invalid JSON in tasks file: $tasks_file"
        _parallel_cleanup_cron
        return 1
    fi

    if ! jq -e '.tasks | type == "array"' "$tasks_file" >/dev/null 2>&1; then
        log ERROR "Tasks file must contain a tasks array: $tasks_file"
        _parallel_cleanup_cron
        return 1
    fi

    local task_count
    task_count=$(jq '.tasks | length' "$tasks_file" 2>/dev/null) || {
        log ERROR "Failed to read tasks array from file"
        _parallel_cleanup_cron
        return 1
    }
    log INFO "Found $task_count tasks"

    local max_parallel="${MAX_PARALLEL:-3}"
    if ! [[ "$max_parallel" =~ ^[1-9][0-9]*$ ]]; then
        log ERROR "MAX_PARALLEL must be a positive integer (got: $max_parallel)"
        _parallel_cleanup_cron
        return 1
    fi

    local report_file
    outcome_dir=$(mktemp -d "${TMPDIR:-/tmp}/octo-parallel-outcomes.XXXXXX") || {
        log ERROR "Failed to create parallel outcome directory"
        _parallel_cleanup_cron
        return 1
    }
    report_file="${OCTOPUS_PARALLEL_REPORT_FILE:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}/state/parallel-report.json}"
    _parallel_previous_int_trap="$(trap -p INT)"
    _parallel_previous_term_trap="$(trap -p TERM)"
    _parallel_previous_exit_trap="$(trap -p EXIT)"
    trap '_parallel_handle_signal INT' INT
    trap '_parallel_handle_signal TERM' TERM
    trap '_parallel_handle_exit' EXIT

    local running=0
    local completed=0
    local skipped=0
    local failed=0
    local sequence=0
    local pids=()
    local task_ids=()
    local task_agents=()
    local task_sequences=()
    local seen_task_ids=$'\n'

    while IFS= read -r task; do
        local task_id="" agent="" prompt="" current_sequence="$sequence"
        ((sequence++)) || true

        if ! jq -e 'type == "object"' <<< "$task" >/dev/null 2>&1; then
            log WARN "Skipping malformed task at sequence $current_sequence"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "" false "" false \
                "skipped" "malformed-task" ""
            ((skipped++)) || true
            continue
        fi

        task_id=$(jq -r '.id // empty' <<< "$task" 2>/dev/null) || task_id=""
        agent=$(jq -r '.agent // empty' <<< "$task" 2>/dev/null) || agent=""
        prompt=$(jq -r '.prompt // empty' <<< "$task" 2>/dev/null) || prompt=""

        # SECURITY: Safe JSON extraction with validation
        if [[ -z "$task_id" ]]; then
            log WARN "Skipping task with invalid/missing id"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "" false "$agent" \
                "$([[ -n "$agent" ]] && echo true || echo false)" "skipped" "missing-id" ""
            ((skipped++)) || true
            continue
        fi

        # Task IDs become result and completion-marker filenames in spawn.sh.
        # Reject path separators and traversal before any filesystem use.
        if [[ ! "$task_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || "$task_id" == *..* ]]; then
            log WARN "Skipping task with unsafe id '$task_id'"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" \
                "$([[ -n "$agent" ]] && echo true || echo false)" "skipped" "invalid-id" ""
            ((skipped++)) || true
            continue
        fi

        local duplicate_id=false
        case "$seen_task_ids" in
            *$'\n'"$task_id"$'\n'*) duplicate_id=true ;;
        esac
        if [[ "$duplicate_id" == "true" ]]; then
            log WARN "Skipping duplicate task id '$task_id'"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" \
                "$([[ -n "$agent" ]] && echo true || echo false)" "skipped" "duplicate-id" ""
            ((skipped++)) || true
            continue
        fi
        seen_task_ids+="$task_id"$'\n'

        if [[ -z "$agent" ]]; then
            log WARN "Skipping task $task_id: invalid/missing agent"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "" false \
                "skipped" "missing-agent" ""
            ((skipped++)) || true
            continue
        fi

        # SECURITY: Validate agent type against allowlist
        validate_agent_type "$agent" || {
            log WARN "Skipping task $task_id: unknown agent '$agent'"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                "skipped" "unknown-agent" ""
            ((skipped++)) || true
            continue
        }

        if [[ -z "$prompt" ]]; then
            log WARN "Skipping task $task_id: invalid/missing prompt"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                "skipped" "missing-prompt" ""
            ((skipped++)) || true
            continue
        fi

        local provider="$agent"
        if declare -f octo_agent_spec_provider >/dev/null 2>&1; then
            provider=$(octo_agent_spec_provider "$agent")
        fi
        if declare -f is_provider_available >/dev/null 2>&1 && ! is_provider_available "$provider"; then
            log WARN "Skipping task $task_id: circuit open for '$provider'"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                "skipped" "circuit-open" ""
            ((skipped++)) || true
            continue
        fi
        if declare -f octo_quota_is_dead >/dev/null 2>&1 && octo_quota_is_dead "$provider"; then
            log WARN "Skipping task $task_id: quota dead for '$provider'"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                "skipped" "quota-dead" ""
            ((skipped++)) || true
            continue
        fi

        # A reused task ID must not inherit a completion marker from an earlier
        # run. IDs are filename-safe by the validation above.
        rm -f "${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents/${task_id}.done" \
            2>/dev/null || true

        while [[ $running -ge $max_parallel ]]; do
            for i in "${!pids[@]}"; do
                if _parallel_pid_has_finished "${pids[$i]}"; then
                    if _parallel_collect_outcome "$outcome_dir" "${pids[$i]}" \
                        "${task_sequences[$i]}" "${task_ids[$i]}" "${task_agents[$i]}"; then
                        ((completed++)) || true
                    else
                        ((failed++)) || true
                    fi
                    unset 'pids[i]'
                    unset 'task_ids[i]' 'task_agents[i]' 'task_sequences[i]'
                    ((running--)) || true
                fi
            done
            [[ $running -ge $max_parallel ]] && sleep "${OCTOPUS_PARALLEL_POLL_INTERVAL:-0.2}"
        done

        local pid="" spawn_status=0
        spawn_output=""
        spawn_output=$(mktemp "${TMPDIR:-/tmp}/octo-parallel-spawn.XXXXXX") || spawn_status=1
        if [[ "$spawn_status" -eq 0 ]]; then
            if spawn_agent_capture_pid "$agent" "$prompt" "$task_id" > "$spawn_output"; then
                pid=$(awk '/^[0-9]+$/ { value=$1 } END { print value }' "$spawn_output" 2>/dev/null)
                [[ "$pid" =~ ^[1-9][0-9]*$ ]] || spawn_status=1
            else
                spawn_status=$?
            fi
            rm -f "$spawn_output"
            spawn_output=""
        fi

        if [[ "$spawn_status" -eq 0 ]]; then
            pids+=("$pid")
            task_ids+=("$task_id")
            task_agents+=("$agent")
            task_sequences+=("$current_sequence")
            ((running++)) || true
        else
            log WARN "Skipping task $task_id: failed to spawn agent '$agent'"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                "failed" "failed-spawn" "$spawn_status"
            ((failed++)) || true
            continue
        fi

        log INFO "Progress: $completed/$task_count completed, $running running"
    done < <(jq -c '.tasks[]' "$tasks_file")

    log INFO "Waiting for remaining $running tasks to complete..."
    while [[ $running -gt 0 ]]; do
        local saw_completion=false
        for i in "${!pids[@]}"; do
            if _parallel_pid_has_finished "${pids[$i]}"; then
                if _parallel_collect_outcome "$outcome_dir" "${pids[$i]}" \
                    "${task_sequences[$i]}" "${task_ids[$i]}" "${task_agents[$i]}"; then
                    ((completed++)) || true
                else
                    ((failed++)) || true
                fi
                unset 'pids[i]'
                unset 'task_ids[i]' 'task_agents[i]' 'task_sequences[i]'
                ((running--)) || true
                saw_completion=true
            fi
        done
        [[ "$saw_completion" == "false" ]] && sleep "${OCTOPUS_PARALLEL_POLL_INTERVAL:-0.2}"
    done

    if [[ $skipped -gt 0 ]]; then
        log WARN "Completed with $skipped skipped tasks (invalid/malformed)"
    fi
    log INFO "All $task_count tasks processed ($completed completed, $skipped skipped, $failed failed)"
    if type render_agent_summary >/dev/null 2>&1; then
        if ! render_agent_summary; then
            log WARN "Agent summary rendering failed; continuing to structured report"
        fi
    fi
    local aggregate_status=0
    if aggregate_results; then
        aggregate_status=0
    else
        aggregate_status=$?
    fi

    local overall_status="complete"
    if [[ "$aggregate_status" -ne 0 ]] || { [[ "$task_count" -gt 0 ]] && [[ "$completed" -eq 0 ]]; }; then
        overall_status="failed"
    elif [[ "$skipped" -gt 0 || "$failed" -gt 0 ]]; then
        overall_status="degraded"
    fi

    local report_status=0
    if ! _parallel_write_report "$outcome_dir" "$report_file" "$overall_status" \
        "$task_count" "$completed" "$skipped" "$failed" "$aggregate_status"; then
        log ERROR "Failed to write parallel execution report: $report_file"
        report_status=1
    else
        log INFO "Parallel execution report: $report_file ($overall_status)"
    fi
    _parallel_cleanup_resources
    _parallel_restore_traps
    [[ "$report_status" -ne 0 ]] && return "$report_status"
    [[ "$aggregate_status" -ne 0 ]] && return "$aggregate_status"
    [[ "$overall_status" == "failed" ]] && return 1
    return 0
}

map_reduce() {
    local main_prompt="$1"
    local task_group
    task_group=$(date +%s)

    log INFO "Map-Reduce: Decomposing task and distributing to agents"

    log INFO "Phase 1: Task decomposition"
    local decompose_prompt="Analyze this task and break it into subtasks that can be executed in parallel.
If the task produces a single deliverable (one file, one script, one page, one config), keep it as ONE subtask — do not split it. Only decompose when subtasks are truly independent with no cross-file references. Aim for 2-5 subtasks; fewer is better when the work is tightly coupled.
Output as a simple numbered list. Task: $main_prompt"

    local decompose_result="${RESULTS_DIR}/decompose-${task_group}.txt"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would decompose: $main_prompt"
        return 0
    fi

    # Route decomposition through the agy-capable run_agent_sync abstraction
    # (Gemini CLI sunset 2026-06-18; agy is the Google seat, #524), mirroring
    # aggregate_results' synthesis path. claude-sonnet is the fallback; a plain
    # fan-out is the last resort when no decomposition agent succeeds.
    if type run_agent_sync >/dev/null 2>&1; then
        local decompose_agent decompose_output=""
        decompose_agent=$(_parallel_google_seat)
        log INFO "Decomposing with $decompose_agent"
        if decompose_output=$(run_agent_sync "$decompose_agent" "$decompose_prompt" "${TIMEOUT:-120}" "decompose" "parallel" 2>/dev/null) \
            && [[ -n "$decompose_output" ]]; then
            printf '%s\n' "$decompose_output" > "$decompose_result"
        elif [[ "$decompose_agent" != "claude-sonnet" ]] \
            && decompose_output=$(run_agent_sync "claude-sonnet" "$decompose_prompt" "${TIMEOUT:-120}" "decompose" "parallel" 2>/dev/null) \
            && [[ -n "$decompose_output" ]]; then
            log WARN "Decomposition via '$decompose_agent' failed — used claude-sonnet fallback"
            printf '%s\n' "$decompose_output" > "$decompose_result"
        else
            log WARN "Decomposition failed, falling back to fan-out"
            fan_out "$main_prompt"
            return
        fi
    else
        log WARN "run_agent_sync unavailable, falling back to fan-out"
        fan_out "$main_prompt"
        return
    fi

    log INFO "Decomposition complete. Subtasks:"
    cat "$decompose_result"
    echo ""

    log INFO "Phase 2: Mapping subtasks to agents"
    local subtask_num=0
    # Second seat prefers agy (Google seat) over the sunset Gemini CLI (#524)
    local agents=("codex" "$(_parallel_google_seat)")
    local pids=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[0-9]+[\.\)] ]] || continue

        local subtask
        subtask=$(echo "$line" | sed 's/^[0-9]*[\.\)]\s*//')
        local agent="${agents[$((subtask_num % ${#agents[@]}))]}"

        local pid
        if pid=$(spawn_agent_capture_pid "$agent" "$subtask" "${task_group}-subtask-${subtask_num}"); then
            pids+=("$pid")
        else
            log WARN "Map-Reduce: failed to spawn subtask $subtask_num with $agent"
        fi
        ((subtask_num++)) || true
    done < "$decompose_result"

    log INFO "Spawned $subtask_num subtask agents"

    log INFO "Phase 3: Waiting for subtasks to complete..."
    local remaining=${#pids[@]}
    while [[ $remaining -gt 0 ]]; do
        remaining=0
        for i in "${!pids[@]}"; do
            if kill -0 "${pids[$i]}" 2>/dev/null; then
                ((remaining++)) || true
            else
                unset 'pids[i]'
            fi
        done
        [[ $remaining -gt 0 ]] && sleep 1
    done

    aggregate_results "$task_group"
}

# v9.45.1: Pick the synthesis provider for aggregate_results.
# The Gemini CLI was sunset 2026-06-18; agy (Antigravity) is now the default
# Google seat / synthesizer, mirroring the workflows.sh phase synthesizers
# (#524). Preference order:
#   1. agy           — Google seat, when the agy CLI is installed/allowed
#   2. claude-sonnet — always available inside Claude Code
# Echoes the chosen agent type, or empty when no synthesis provider is reachable
# (the caller then falls back to plain concatenation). Always returns 0 — the
# exit code is unused and the caller branches on the echoed value, so a non-zero
# return would only misfire `set -e` in `synth_agent=$(...)` assignments.
_aggregate_pick_synth_agent() {
    if { ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed agy; } \
        && command -v agy >/dev/null 2>&1; then
        echo "agy"; return 0
    fi
    # claude-sonnet is the fallback only when the allowlist permits it — the
    # picker is the single source of truth for synthesis authorization (#538).
    if { ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed claude-sonnet; } \
        && command -v claude >/dev/null 2>&1; then
        echo "claude-sonnet"; return 0
    fi
    echo ""; return 0
}

aggregate_results() {
    local _ts; _ts=$(date +%s)
    local filter="${1:-}"
    local user_query="${2:-}"  # v8.49.0: Optional user query for relevance-aware synthesis
    local aggregate_file="${RESULTS_DIR}/aggregate-${_ts}.md"
    local raw_concat="${RESULTS_DIR}/.raw-concat-$$.md"

    log INFO "Aggregating results..."

    # Phase 1: Collect results ranked by quality signals (v8.49.0)
    # Results are ordered best-first so the synthesis LLM sees highest-quality content first
    local result_count=0
    : > "$raw_concat"
    local ranked_files
    ranked_files=$(rank_results_by_signals "$RESULTS_DIR" "$filter")

    if [[ -z "$ranked_files" ]]; then
        # Fallback: no ranked results, use original glob order
        for result in "$RESULTS_DIR"/*.md; do
            [[ -f "$result" ]] || continue
            [[ "$result" == *aggregate* ]] && continue
            [[ "$result" == *.raw-concat* ]] && continue
            [[ -n "$filter" && "$result" != *"$filter"* ]] && continue
            ranked_files+="$result"$'\n'
        done
    fi

    while IFS= read -r result; do
        [[ -z "$result" ]] && continue
        local score
        score=$(score_result_file "$result")
        echo "---" >> "$raw_concat"
        echo "## Source: $(basename "$result") [Quality: ${score}/100]" >> "$raw_concat"
        echo "" >> "$raw_concat"
        cat "$result" >> "$raw_concat"
        echo "" >> "$raw_concat"
        ((result_count++)) || true
    done <<< "$ranked_files"

    # Phase 2: Synthesize via the agy-capable run_agent_sync abstraction when we
    # have a reachable synthesis provider and multiple results. (Gemini CLI sunset
    # 2026-06-18 — agy is the default Google seat; claude-sonnet is the fallback.
    # Plain concatenation is used only when NO synthesis provider is available.)
    local synth_agent synth_used
    synth_agent=$(_aggregate_pick_synth_agent)
    synth_used="$synth_agent"
    if [[ $result_count -gt 1 ]] && [[ -n "$synth_agent" ]] \
        && type run_agent_sync >/dev/null 2>&1 && [[ "$DRY_RUN" != "true" ]]; then
        log INFO "Synthesizing $result_count results via $synth_agent (ranked by quality, not just concatenating)..."

        # v8.49.0: Enhanced synthesis prompt with relevance awareness and structured output
        local query_context=""
        if [[ -n "$user_query" ]]; then
            query_context="
Original User Query: $user_query
Weight content by relevance to this query. Sources are pre-ranked by quality (best first)."
        fi

        local synthesis_prompt
        synthesis_prompt="Synthesize these $result_count subtask results into ONE coherent output.
${query_context}
Rules:
- Sources are ordered by quality score (best first); weight accordingly
- Merge overlapping content; preserve distinct contributions from each source
- Short but critical findings (minority opinions, edge cases, warnings) are EQUALLY important as verbose analysis — do NOT dismiss them for brevity
- If sources conflict, state the conflict and your resolution
- The output must stand alone — a reader should get the complete picture without seeing the inputs

Structure the output as:
1. **Key Findings** — Top 3-5 actionable insights
2. **Detailed Analysis** — Organized by topic, not by source
3. **Conflicts & Trade-offs** — Where sources disagreed and why
4. **Recommendations** — Prioritized next steps

Subtask results:
$(<"$raw_concat")"

        local synthesis_result=""
        if synthesis_result=$(run_agent_sync "$synth_agent" "$synthesis_prompt" "$TIMEOUT" "synthesizer" "parallel" 2>/dev/null) \
            && [[ -n "$synthesis_result" ]]; then
            :  # primary synthesizer produced output
        elif [[ "$synth_agent" != "claude-sonnet" ]] \
            && { ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed claude-sonnet; } \
            && command -v claude >/dev/null 2>&1 \
            && synthesis_result=$(run_agent_sync "claude-sonnet" "$synthesis_prompt" "$TIMEOUT" "synthesizer" "parallel" 2>/dev/null) \
            && [[ -n "$synthesis_result" ]]; then
            log WARN "Synthesizer '$synth_agent' failed — used claude-sonnet fallback"
            synth_used="claude-sonnet"
        else
            synthesis_result=""
        fi

        if [[ -n "$synthesis_result" ]]; then
            echo "# Claude Octopus - Synthesized Results" > "$aggregate_file"
            echo "" >> "$aggregate_file"
            echo "Generated: $(date)" >> "$aggregate_file"
            echo "Sources: $result_count subtask outputs (ranked by quality)" >> "$aggregate_file"
            echo "Synthesizer: $synth_used" >> "$aggregate_file"
            [[ -n "$user_query" ]] && echo "Query: $user_query" >> "$aggregate_file"
            echo "" >> "$aggregate_file"
            echo "$synthesis_result" >> "$aggregate_file"
            rm -f "$raw_concat"
            log INFO "Synthesized $result_count results via $synth_used to: $aggregate_file"
            # #498: emit a synthesis lifecycle event on the success path, attributing
            # the provider that actually produced the artifact ($synth_used, which
            # reflects the claude-sonnet fallback above).
            declare -f octo_event_emit >/dev/null 2>&1 && octo_event_emit "synthesis" phase="parallel" provider="$synth_used" provider_label_kind="legacy-alias" executor_alias="$synth_used" configured_provider="$(octo_provider_identity_from_agent_type "${synth_used:-unknown}")" configured_model="$(get_agent_model "$synth_used" "parallel" "synthesizer" 2>/dev/null || echo unresolved)" runtime_provider="unknown" runtime_model="unknown" council_role="synthesizer" synthesis_strategy="parallel" count="$result_count" || true
            echo ""
            echo -e "${GREEN}✓${NC} Results synthesized to: $aggregate_file"
            guard_output "$(<"$aggregate_file")" "aggregate-synthesis"
            return
        fi
        log WARN "Synthesis failed, falling back to concatenation"
    fi

    # Fallback: concatenation (single result or no synthesis provider)
    echo "# Claude Octopus - Aggregated Results" > "$aggregate_file"
    echo "" >> "$aggregate_file"
    echo "Generated: $(date)" >> "$aggregate_file"
    echo "" >> "$aggregate_file"
    cat "$raw_concat" >> "$aggregate_file"
    echo "" >> "$aggregate_file"
    echo "**Total Results: $result_count**" >> "$aggregate_file"

    rm -f "$raw_concat"
    log INFO "Aggregated $result_count results to: $aggregate_file"
    echo ""
    echo -e "${GREEN}✓${NC} Results aggregated to: $aggregate_file"
    guard_output "$(<"$aggregate_file")" "aggregate-concat"
}
