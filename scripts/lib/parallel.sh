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
source "${BASH_SOURCE[0]%/*}/feature-scheduler.sh"

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

    # spawn_agent's dry-run branch only prints a command preview, so there is
    # no provider PID to capture.
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        for agent in "${agents[@]}"; do
            spawn_agent "$agent" "$prompt" "${task_group}-${agent}" \
                || log WARN "Fan-out: failed to spawn $agent"
        done
        return 0
    fi

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
    local RESULTS_DIR="${RESULTS_DIR:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}/results}"
    if [[ "${OCTOPUS_FEATURE_PARALLEL_WAVE_ACTIVE:-false}" != true ]]; then
        if [[ -n "${FEATURE_TASK_CONTRACT:-}" && "$tasks_file" == "$FEATURE_TASK_CONTRACT" ]] || \
           { [[ -f "$tasks_file" ]] && jq -e '.schema_version == 1 and (.feature_id|type == "string")' "$tasks_file" >/dev/null 2>&1; }; then
            local FEATURE_TASK_CONTRACT="$tasks_file"
            feature_tasks_parallel_execute "$tasks_file"
            return $?
        fi
    fi
    local _parallel_lib_dir
    _parallel_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if ! declare -f review_kill_process_tree_frozen >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${_parallel_lib_dir}/review.sh" 2>/dev/null || true
    fi
    local _parallel_cron_disabled=false
    local outcome_dir="" spawn_output="" spawn_pid_handoff=""
    local _parallel_previous_int_trap="" _parallel_previous_term_trap=""
    local _parallel_previous_exit_trap=""
    local pids=()
    local task_ids=()
    local task_agents=()
    local task_sequences=()
    local output_claims=()
    local owner_lock="" owner_python="" owner_directory="" claim_stale_seats=""
    local reserved_seat="" reservation_holder=""
    local _parallel_claim_helper="${_parallel_lib_dir}/../helpers/output-claim.py"
    # Claim records name the run whose ledgers hold each seat, so a reclaimer
    # from another run sharing these results reconciles the owner's ledgers.
    local claim_run="" claim_workspace="${WORKSPACE_DIR:-}"
    if declare -F octo_current_run_id >/dev/null 2>&1; then
        claim_run="$(octo_current_run_id)"
    fi
    [[ -z "$claim_workspace" || "$claim_workspace" == /* ]] || claim_workspace="$PWD/$claim_workspace"
    _parallel_cleanup_cron() {
        if [[ "$_parallel_cron_disabled" == "true" ]]; then
            unset CLAUDE_CODE_DISABLE_CRON 2>/dev/null || true
        fi
    }
    # fd 7 holds this invocation's owner lock. Every worker and provider
    # inherits it, so the lock stays held until all of them have exited, even
    # after SIGKILL ends this shell before cleanup can run.
    _parallel_open_owner_lock() {
        [[ -z "$owner_lock" ]] || return 0
        # Leave a descriptor 7 that the caller opened untouched.
        { : <&7; } 2>/dev/null && return 1
        if [[ -z "$owner_python" ]]; then
            if declare -F octopus_pid_python_resolve >/dev/null 2>&1; then
                owner_python=$(octopus_pid_python_resolve 2>/dev/null) || owner_python=""
            else
                owner_python=$(command -v python3 2>/dev/null) || owner_python=""
            fi
        fi
        [[ -n "$owner_python" ]] || return 1
        owner_lock=$(mktemp "$RESULTS_DIR/.parallel-owner.XXXXXX" 2>/dev/null) || { owner_lock=""; return 1; }
        # The Python claim record uses an absolute path, including when the
        # caller selected a relative results directory.
        if ! owner_directory=$(cd "$(dirname "$owner_lock")" && pwd -P); then
            rm -f -- "$owner_lock" 2>/dev/null || true
            owner_lock=""
            return 1
        fi
        owner_lock="$owner_directory/${owner_lock##*/}"
        if ! { exec 7>"$owner_lock"; } 2>/dev/null || \
           ! "$owner_python" "$_parallel_claim_helper" hold 7 </dev/null; then
            exec 7>&-
            rm -f -- "$owner_lock" 2>/dev/null || true
            owner_lock=""
            return 1
        fi
    }
    # Returns 0 when acquired, 3 when reclaimed from an exited owner, and 1
    # while another invocation, or any process it started, may still own it.
    # A reclaim prints the exited owner's dispatched and inherited seat
    # entries into claim_stale_seats; the new record keeps them until reconciled.
    _parallel_claim_output() {
        local claim="$1" seat="$2" output="$3" claim_status=0
        claim_stale_seats=""
        if _parallel_open_owner_lock; then
            # Run the helper directly, not in a command substitution, so a
            # signal during publication reaches this controller's handler.
            "$owner_python" "$_parallel_claim_helper" acquire "$claim" "$owner_lock" \
                "$seat" "$output" "$claim_run" "$claim_workspace" \
                </dev/null >"$outcome_dir/claim-stale-seats" || claim_status=$?
            claim_stale_seats=$(cat "$outcome_dir/claim-stale-seats" 2>/dev/null) || claim_stale_seats=""
            case "$claim_status" in
                0) return 0 ;;
                11) return 3 ;;
                *) return 1 ;;
            esac
        fi
        log WARN "Shell output claim at $claim: interrupted claims need manual recovery; see docs/COMMAND-REFERENCE.md"
        mkdir -- "$claim" 2>/dev/null || return 1
        # A nonempty fallback claim cannot be replaced by Python's rename.
        # If Python publishes between mkdir and this exclusive write, its owner
        # record makes the write fail, so this contender never dispatches.
        (set -o noclobber; printf '%s\n' fallback > "$claim/owner") 2>/dev/null
    }
    _parallel_cancel_orphaned_seat() {
        _parallel_cancel_seat_output "spawn-$1" "$2"
    }
    # Cancel a seat entry from a claim record in the run that recorded it,
    # matching that run's spelling of the output path. The current run's
    # same-named seats, and other spellings of the path, stay untouched.
    _parallel_reconcile_seat_entry() {
        local fields
        fields=$(jq -r '[.seat, .output, .run, .workspace] | @sh' <<< "$1" 2>/dev/null) || return 0
        eval "set -- $fields"
        [[ $# -eq 4 && -n "$1" && -n "$2" && -n "$3" ]] || return 0
        (
            export OCTOPUS_RUN_ID="$3" WORKSPACE_DIR="$4"
            _parallel_cancel_seat_output "$1" "$2"
        )
    }
    # Cancel the record's inherited seats before its claim stops proving that
    # their owner has exited.
    _parallel_reconcile_claim() {
        local claim="$1" stale_seat
        [[ -f "$claim/owner" ]] || return 0
        while IFS= read -r stale_seat; do
            [[ -z "$stale_seat" ]] || _parallel_reconcile_seat_entry "$stale_seat"
        done < <(sed -n 's/^reconcile //p' "$claim/owner" 2>/dev/null)
    }
    _parallel_cancel_seat_output() {
        local seat_id="$1" output="$2" ledger agent seat role record
        local status transition contribution seat_reason
        local reason="${3:-Seat owner exited before recording a terminal status}"
        declare -F write_agent_status >/dev/null || return 0
        declare -F octo_run_dir >/dev/null || return 0
        ledger="$(octo_run_dir)/agents.jsonl"
        [[ -s "$ledger" ]] || return 0
        while IFS=$'\t' read -r agent seat role; do
            # Native teammates have no cancellation handle. Their controller's
            # exit does not establish that the teammate has stopped.
            status=cancelled transition="" contribution="" seat_reason="$reason"
            # The finalizer takes the contract lock and first recovers an append
            # the stopped worker interrupted. A seat that already reached a
            # terminal state keeps it, so the summary projects that outcome,
            # including a contribution committed just before the worker died.
            if declare -F octo_run_contract_finish_background >/dev/null &&
               ! octo_run_contract_finish_background "$seat" cancelled "$output" "" \
                   "$reason" 143 "" already-exited >/dev/null 2>&1 &&
               record="$(run_contract_seat_record "$seat" 2>/dev/null)"; then
                IFS=$'\t' read -r transition contribution seat_reason < <(jq -r \
                    '[.transition, (.contribution // "none"), (.reason // "")] | @tsv' <<< "$record" 2>/dev/null)
                case "$transition" in
                    contributed) status=ok ;;
                    degraded|skipped|failed|timeout|cancelled) status="$transition" ;;
                    *) transition="" contribution="" seat_reason="$reason" ;;
                esac
            fi
            write_agent_status "$agent" "$status" 0 0 "$seat_reason" \
                0 "$output" "$role" "$seat" "$transition" "$contribution" || true
        done < <(jq -rs --arg seat "$seat_id" --arg file "$output" \
            "${_OCTO_AGENT_STATUS_LATEST_PER_SEAT}"'
            latest_per_seat | .[] |
            select(.status == "running" and .seat_id == $seat and .output_file == $file and
                .reason != "Dispatched via Agent Teams") |
            [.agent, .seat_id, (.role // "")] | @tsv' "$ledger")
    }
    _parallel_release_output() {
        local claim="$1" retired
        if [[ -n "$owner_lock" && "$(cat "$claim/owner" 2>/dev/null)" != fallback ]]; then
            "$owner_python" "$_parallel_claim_helper" release "$claim" "$owner_lock" </dev/null
            return $?
        fi
        # Fallback claims cannot be reclaimed by other invocations. Move the
        # complete directory before removing anything, including without Python.
        [[ "$(cat "$claim/owner" 2>/dev/null)" == fallback ]] || return 1
        retired=$(mktemp -d "$RESULTS_DIR/.retired-claim.XXXXXX") || return 1
        if ! mv -- "$claim" "$retired/claim"; then
            rmdir -- "$retired" 2>/dev/null || true
            return 1
        fi
        rm -rf -- "$retired"
    }
    _parallel_release_seat() {
        [[ -n "$reserved_seat" ]] || return 0
        run_contract_release_seat "$reserved_seat" "$reservation_holder" >/dev/null 2>&1 || true
        reserved_seat=""
    }
    _parallel_cleanup_resources() {
        local claim keep_owner_lock=false
        _parallel_release_seat
        if [[ ${#output_claims[@]} -gt 0 ]]; then
            for claim in "${output_claims[@]}"; do
                _parallel_reconcile_claim "$claim"
                _parallel_release_output "$claim" 2>/dev/null || keep_owner_lock=true
            done
        fi
        output_claims=()
        if [[ -n "$owner_lock" ]]; then
            # A signal can arrive after publication but before the claim was
            # appended above. Reconcile every claim naming this owner before
            # unlinking its lock, or that unregistered claim cannot be reclaimed.
            for claim in "$RESULTS_DIR"/.*.claim; do
                [[ -f "$claim/owner" ]] || continue
                [[ "$(head -n 1 "$claim/owner" 2>/dev/null)" == "$owner_lock" ]] || continue
                _parallel_reconcile_claim "$claim"
                _parallel_release_output "$claim" 2>/dev/null || keep_owner_lock=true
            done
            exec 7>&-
            if [[ "$keep_owner_lock" == false ]]; then
                rm -f -- "$owner_lock" 2>/dev/null || true
            fi
            owner_lock=""
        fi
        [[ -z "$spawn_output" ]] || rm -f "$spawn_output" 2>/dev/null || true
        [[ -z "$spawn_pid_handoff" ]] || rm -f "$spawn_pid_handoff" 2>/dev/null || true
        [[ -z "$outcome_dir" ]] || rm -rf "$outcome_dir" 2>/dev/null || true
        spawn_output=""
        spawn_pid_handoff=""
        outcome_dir=""
        _parallel_cleanup_cron
    }
    _parallel_terminate_tracked_processes() {
        local pid handoff_pid="" wrapper_pid="" capture_file=""
        local capture_pid="" tracked_pids="" pgid=""
        if [[ -n "$spawn_pid_handoff" && -f "$spawn_pid_handoff" ]]; then
            wrapper_pid=$(awk -F: '$1 == "wrapper" && $2 ~ /^[0-9]+$/ { value=$2 } END { print value }' \
                "$spawn_pid_handoff" 2>/dev/null)
            handoff_pid=$(awk -F: '$1 == "provider" && $2 ~ /^[0-9]+$/ { value=$2 } END { print value }' \
                "$spawn_pid_handoff" 2>/dev/null)
            capture_file=$(sed -n 's/^capture-file://p' "$spawn_pid_handoff" 2>/dev/null | tail -1)
            # Accept the original numeric-only handoff for third-party capture
            # implementations that adopted the first version of this contract.
            if [[ -z "$handoff_pid" ]]; then
                handoff_pid=$(awk '/^[0-9]+$/ { value=$1 } END { print value }' \
                    "$spawn_pid_handoff" 2>/dev/null)
            fi
            [[ "$handoff_pid" =~ ^[1-9][0-9]*$ ]] && tracked_pids="$handoff_pid"
        fi
        case "$capture_file" in
            "${TMPDIR:-/tmp}/octo-spawn-pid."*)
                if [[ -f "$capture_file" ]]; then
                    capture_pid=$(awk '/^[0-9]+$/ { value=$1 } END { print value }' \
                        "$capture_file" 2>/dev/null)
                    if [[ "$capture_pid" =~ ^[1-9][0-9]*$ ]]; then
                        case " $tracked_pids " in
                            *" $capture_pid "*) ;;
                            *) tracked_pids="${tracked_pids}${tracked_pids:+ }${capture_pid}" ;;
                        esac
                    fi
                fi
                ;;
        esac
        if [[ "$wrapper_pid" =~ ^[1-9][0-9]*$ ]]; then
            if declare -f review_kill_process_tree_frozen >/dev/null 2>&1; then
                review_kill_process_tree_frozen "$wrapper_pid"
            else
                kill -KILL "$wrapper_pid" 2>/dev/null || true
            fi
            wait "$wrapper_pid" 2>/dev/null || true
        fi
        # Bash 3.2 treats "${empty_array[@]}" as unbound under set -u even
        # when the array was declared, so expand it only when non-empty.
        if [[ "${#pids[@]}" -gt 0 ]]; then
            for pid in "${pids[@]}"; do
                [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
                case " $tracked_pids " in *" $pid "*) ;; *) tracked_pids="${tracked_pids}${tracked_pids:+ }${pid}" ;; esac
            done
        fi
        if [[ -z "$tracked_pids" ]]; then
            case "$capture_file" in
                "${TMPDIR:-/tmp}/octo-spawn-pid."*) rm -f "$capture_file" 2>/dev/null || true ;;
            esac
            return 0
        fi
        for pid in $tracked_pids; do
            [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
            if ! _parallel_pid_has_finished "$pid"; then
                if declare -f review_kill_process_tree_frozen >/dev/null 2>&1; then
                    review_kill_process_tree_frozen "$pid"
                else
                    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d '[:space:]') \
                        || pgid=""
                    if [[ "$pgid" == "$pid" ]] && kill -STOP -- "-$pid" 2>/dev/null; then
                        kill -KILL -- "-$pid" 2>/dev/null || true
                    else
                        kill -KILL "$pid" 2>/dev/null || true
                    fi
                fi
            fi
            wait "$pid" 2>/dev/null || true
        done
        case "$capture_file" in
            "${TMPDIR:-/tmp}/octo-spawn-pid."*) rm -f "$capture_file" 2>/dev/null || true ;;
        esac
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
    _parallel_cancel_running_seats() {
        # Call after terminating workers and before releasing their claims.
        # Include a seat whose PID is still being handed back by spawn.
        declare -F write_agent_status >/dev/null || return 0
        declare -F octo_run_dir >/dev/null || return 0
        local ledger seat output
        ledger="$(octo_run_dir)/agents.jsonl"
        [[ -s "$ledger" ]] || return 0
        while IFS=$'\t' read -r seat output; do
            _parallel_cancel_seat_output "$seat" "$output" "Parallel execution interrupted"
        done < <(jq -rs --slurpfile tasks /dev/stdin \
            "${_OCTO_AGENT_STATUS_LATEST_PER_SEAT}"'
            (if ($tasks | length) == 1 then $tasks[0] else error("invalid task scope") end) as $tasks |
            latest_per_seat | .[] | select(.status == "running") |
            select(. as $row | any($tasks[];
                $row.seat_id == ("spawn-" + .id) and
                $row.output_file == .output_file)) |
            [.seat_id, .output_file] | @tsv' "$ledger" <<< "${aggregate_task_scope:-[]}")
    }
    _parallel_handle_signal() {
        local signal="$1" signal_status=143 saved_trap current_pid
        [[ "$signal" == "INT" ]] && signal_status=130
        if [[ "$signal" == "INT" ]]; then
            saved_trap="$_parallel_previous_int_trap"
        else
            saved_trap="$_parallel_previous_term_trap"
        fi
        _parallel_terminate_tracked_processes
        _parallel_cancel_running_seats
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
        # Both return paths restore the traps first, so this runs only when the
        # shell exits mid-run, for example on an untrapped SIGHUP. Stop the
        # workers before releasing claims they would otherwise keep writing to.
        _parallel_terminate_tracked_processes
        _parallel_cancel_running_seats
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
    local previewed=0
    local sequence=0
    local seen_task_ids=$'\n'
    local aggregate_task_scope='[]'

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

        # spawn_agent's dry-run branch only prints a command preview, so there
        # is no provider PID to capture. Keep it off stdin, which carries the
        # remaining tasks.
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            if spawn_agent "$agent" "$prompt" "$task_id" </dev/null; then
                ((previewed++)) || true
            else
                log WARN "Skipping task $task_id: could not render a command preview for agent '$agent'"
                ((failed++)) || true
            fi
            continue
        fi

        while [[ $running -ge $max_parallel ]]; do
            for i in "${!pids[@]}"; do
                if _parallel_pid_has_finished "${pids[$i]}"; then
                    if _parallel_collect_outcome "$outcome_dir" "${pids[$i]}" \
                        "${task_sequences[$i]}" "${task_ids[$i]}" "${task_agents[$i]}"; then
                        ((completed++)) || true
                    else
                        local failed_slug="${task_agents[$i]}"
                        [[ "$failed_slug" != claude-opus-fast ]] || failed_slug=claude-opus
                        if declare -F octo_agent_spec_slug >/dev/null 2>&1; then
                            failed_slug=$(octo_agent_spec_slug "$failed_slug")
                        fi
                        _parallel_cancel_orphaned_seat "${task_ids[$i]}" "$RESULTS_DIR/$failed_slug-${task_ids[$i]}.md"
                        ((failed++)) || true
                    fi
                    unset 'pids[i]'
                    unset 'task_ids[i]' 'task_agents[i]' 'task_sequences[i]'
                    ((running--)) || true
                fi
            done
            [[ $running -ge $max_parallel ]] && sleep "${OCTOPUS_PARALLEL_POLL_INTERVAL:-0.2}"
        done

        local result_slug="$agent"
        # spawn_agent normalizes this legacy alias before choosing its filename.
        [[ "$result_slug" != claude-opus-fast ]] || result_slug=claude-opus
        if declare -F octo_agent_spec_slug >/dev/null 2>&1; then
            result_slug=$(octo_agent_spec_slug "$result_slug")
        fi
        # Agent/task pairs can share a filename, including normalized aliases.
        # Never remove or dispatch into a result already owned by this batch.
        if jq -e --arg file "$RESULTS_DIR/$result_slug-$task_id.md" \
            'any(.output_file == $file)' <<< "$aggregate_task_scope" >/dev/null; then
            log ERROR "Output path collision for task $task_id"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                "failed" "output-path-collision" ""
            # A rejected contender must not replace an earlier seat projection.
            aggregate_task_scope=$(jq -c --arg id "$task_id" \
                '. + [{id: $id, output_file: ""}]' <<< "$aggregate_task_scope")
            ((failed++)) || true
            continue
        fi
        # Claims live beside the output so separate invocations sharing a
        # results directory cannot unlink or dispatch into each other's file.
        local claim="$RESULTS_DIR/.$result_slug-$task_id.claim" claim_status=0
        mkdir -p "$RESULTS_DIR"
        _parallel_claim_output "$claim" "spawn-$task_id" "$RESULTS_DIR/$result_slug-$task_id.md" || claim_status=$?
        if [[ "$claim_status" -ne 0 && "$claim_status" -ne 3 ]]; then
            log ERROR "Output path is already claimed for task $task_id"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                failed output-path-owned ""
            ((failed++)) || true
            continue
        fi
        output_claims+=("$claim")
        if [[ "$claim_status" -eq 3 ]]; then
            log WARN "Reclaimed the output of task $task_id from an invocation that has exited"
            # Another task ID or run can share this filename, so cancel the
            # seats the exited owner recorded, in the run that recorded them.
            local stale_seat
            while IFS= read -r stale_seat; do
                [[ -z "$stale_seat" ]] || _parallel_reconcile_seat_entry "$stale_seat"
            done <<< "$claim_stale_seats"
        fi
        # Preserve active outputs from older dispatchers without claim support.
        local ledger=""
        if declare -F octo_run_dir >/dev/null 2>&1; then
            ledger="$(octo_run_dir)/agents.jsonl"
        fi
        # Only a successfully parsed ledger can establish that no seat owns
        # this path. A damaged record may contain an active owner's status.
        if [[ -s "$ledger" ]] && ! jq -es --arg file "$RESULTS_DIR/$result_slug-$task_id.md" \
            "${_OCTO_AGENT_STATUS_LATEST_PER_SEAT}"'latest_per_seat | all(.output_file != $file or .status != "running")' \
            "$ledger" >/dev/null 2>&1; then
            log ERROR "Output path has a running seat for task $task_id"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                failed output-path-owned ""
            ((failed++)) || true
            continue
        fi
        # A durable seat cannot re-enter planned in the same run. Reject that
        # retry before deleting its saved answer, even if its output claim and
        # status ledger are terminal. Use a new task ID for a new attempt.
        # The reservation also turns away a concurrent dispatcher of this seat,
        # whose different agent gives it a different output claim, until this
        # dispatcher's planner has run.
        local contract_seat="spawn-$task_id" contract_available=true
        if declare -F octo_run_contract_ledger_path >/dev/null 2>&1; then
            if declare -F octo_spawn_contract_seat_id >/dev/null 2>&1; then
                contract_seat="$(octo_spawn_contract_seat_id "$task_id")"
            fi
            # Bash 3.2 forks again inside $(...) without exec, naming a process
            # that exits at once and would make this reservation look stale.
            [[ -n "$reservation_holder" ]] || reservation_holder="$(exec sh -c 'printf "%s\n" "$PPID"')"
            if run_contract_reserve_seat "$contract_seat" "$reservation_holder"; then
                reserved_seat="$contract_seat"
            else
                contract_available=false
            fi
        fi
        if [[ "$contract_available" != true ]]; then
            log ERROR "Cannot reuse durable seat $contract_seat; select a new task ID"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                failed contract-seat-unavailable ""
            ((failed++)) || true
            continue
        fi
        # Clear stale task artifacts only after ownership and admission checks. A
        # rejected contender must leave the current owner's marker collectible.
        if ! rm -f -- "$RESULTS_DIR/$result_slug-$task_id.md" \
            "${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents/${task_id}.done"; then
            log ERROR "Cannot remove previous output or completion marker for task $task_id"
            _parallel_release_seat
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                "failed" "stale-output-removal" ""
            type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent" failed 0 0 \
                stale-output-removal 0 "" "" "spawn-$task_id" || true
            aggregate_task_scope=$(jq -c --arg id "$task_id" \
                '. + [{id: $id, output_file: ""}]' <<< "$aggregate_task_scope")
            ((failed++)) || true
            continue
        fi
        aggregate_task_scope=$(jq -c --arg id "$task_id" \
            --arg output_file "$RESULTS_DIR/$result_slug-$task_id.md" \
            '. + [{id: $id, output_file: $output_file}]' <<< "$aggregate_task_scope")
        local pid="" spawn_status=0
        spawn_output=""
        spawn_pid_handoff=""
        spawn_output=$(mktemp "${TMPDIR:-/tmp}/octo-parallel-spawn.XXXXXX") || spawn_status=1
        if [[ "$spawn_status" -eq 0 ]]; then
            spawn_pid_handoff=$(mktemp "${TMPDIR:-/tmp}/octo-parallel-pid.XXXXXX") || spawn_status=1
        fi
        if [[ "$spawn_status" -eq 0 ]]; then
            local feature_role="" feature_phase=""
            local parallel_spawn_args=("$agent" "$prompt" "$task_id")
            if [[ "${OCTOPUS_FEATURE_PARALLEL_WAVE_ACTIVE:-false}" == true ]]; then
                feature_role=$(jq -r '.role // "implementer"' <<< "$task") || feature_role=implementer
                feature_phase=tangle
                parallel_spawn_args+=("$feature_role" "$feature_phase")
            fi
            if OCTOPUS_SPAWN_PID_HANDOFF_FD=9 \
                spawn_agent_capture_pid "${parallel_spawn_args[@]}" \
                    9>"$spawn_pid_handoff" > "$spawn_output"; then
                pid=$(awk '/^[0-9]+$/ { value=$1 } END { print value }' "$spawn_output" 2>/dev/null)
                [[ "$pid" =~ ^[1-9][0-9]*$ ]] || spawn_status=1
            else
                spawn_status=$?
            fi
            if [[ "$spawn_status" -eq 0 ]]; then
                pids+=("$pid")
                task_ids+=("$task_id")
                task_agents+=("$agent")
                task_sequences+=("$current_sequence")
                ((running++)) || true
            fi
        fi
        [[ -z "$spawn_output" ]] || rm -f "$spawn_output"
        [[ -z "$spawn_pid_handoff" ]] || rm -f "$spawn_pid_handoff"
        spawn_output=""
        spawn_pid_handoff=""
        # The planner has run, so the durable ledger now decides admission.
        _parallel_release_seat

        if [[ "$spawn_status" -ne 0 ]]; then
            log WARN "Skipping task $task_id: failed to spawn agent '$agent'"
            _parallel_write_outcome "$outcome_dir" "$current_sequence" "$task_id" true "$agent" true \
                "failed" "failed-spawn" "$spawn_status"
            _parallel_cancel_orphaned_seat "$task_id" "$RESULTS_DIR/$result_slug-$task_id.md"
            ((failed++)) || true
            continue
        fi

        log INFO "Progress: $completed/$task_count completed, $running running"
    done < <(jq -c '.tasks[]' "$tasks_file")

    # A real run fails when no task completes, so a dry run that would
    # dispatch nothing fails too.
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log INFO "[DRY-RUN] Would dispatch $previewed of $task_count tasks ($skipped skipped, $failed failed)"
        _parallel_cleanup_resources
        _parallel_restore_traps
        [[ "$task_count" -gt 0 && "$previewed" -eq 0 ]] && return 1
        return 0
    fi

    log INFO "Waiting for remaining $running tasks to complete..."
    while [[ $running -gt 0 ]]; do
        local saw_completion=false
        for i in "${!pids[@]}"; do
            if _parallel_pid_has_finished "${pids[$i]}"; then
                if _parallel_collect_outcome "$outcome_dir" "${pids[$i]}" \
                    "${task_sequences[$i]}" "${task_ids[$i]}" "${task_agents[$i]}"; then
                    ((completed++)) || true
                else
                    local failed_slug="${task_agents[$i]}"
                    [[ "$failed_slug" != claude-opus-fast ]] || failed_slug=claude-opus
                    if declare -F octo_agent_spec_slug >/dev/null 2>&1; then
                        failed_slug=$(octo_agent_spec_slug "$failed_slug")
                    fi
                    _parallel_cancel_orphaned_seat "${task_ids[$i]}" "$RESULTS_DIR/$failed_slug-${task_ids[$i]}.md"
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
    if aggregate_results "" "" "$aggregate_task_scope"; then
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
    local task_scope="${3:-null}"
    local user_query="${2:-}"  # v8.49.0: Optional user query for relevance-aware synthesis
    local aggregate_file="${RESULTS_DIR}/aggregate-${_ts}.md"
    local raw_concat="${RESULTS_DIR}/.raw-concat-$$.md"

    # Validate one complete scope before ranking, including when no files exist.
    if [[ "$task_scope" != null ]] && ! task_scope=$(jq -cs '
        if length == 1 and (.[0] == null or
            (.[0] | type == "array" and all(.[];
                type == "object" and (.id | type == "string") and
                (.output_file | type == "string"))))
        then .[0] else error("invalid task scope") end' <<< "$task_scope"); then
        log ERROR "Cannot read aggregation task scope"
        return 2
    fi

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
        if [[ "$task_scope" != null ]]; then
            local scope_status=0
            jq -e --arg file "$result" 'any(.output_file == $file)' \
                <<< "$task_scope" >/dev/null || scope_status=$?
            if [[ "$scope_status" -ne 0 ]]; then
                [[ "$scope_status" -ne 1 ]] || continue
                log ERROR "Cannot read aggregation task scope (jq exit $scope_status)"
                rm -f -- "$raw_concat"
                return "$scope_status"
            fi
        fi
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
