#!/usr/bin/env bash
# Double Diamond workflow phases
# Extracted from orchestrate.sh to reduce file size
# Functions: probe_single_agent, probe_discover, grasp_define, tangle_develop, ink_deliver

if ! type probe_result_file_status >/dev/null 2>&1; then
    _octo_probe_results_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/probe-results.sh"
    [[ -f "$_octo_probe_results_lib" ]] && source "$_octo_probe_results_lib"
fi
if ! type review_kill_process_tree_frozen >/dev/null 2>&1; then
    _octo_review_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/review.sh"
    if [[ -f "$_octo_review_lib" ]]; then
        # shellcheck source=/dev/null
        source "$_octo_review_lib" || printf 'ERROR: failed to load Tangle cancellation helpers: %s\n' "$_octo_review_lib" >&2
    else
        printf 'ERROR: missing Tangle cancellation helpers: %s\n' "$_octo_review_lib" >&2
    fi
    unset _octo_review_lib
fi

# v8.54.0: Single-agent probe for multi-agentic skill dispatch
# Runs one probe perspective synchronously and writes result to RESULTS_DIR.
# Called by Claude's Agent tool (one per perspective) instead of probe_discover().
# WHY: probe_discover() runs 5-7 agents + synthesis inside a single Bash subprocess
# that frequently exceeds the 120s Bash tool timeout. By exposing each agent as a
# standalone command, the skill layer can launch them via Agent(run_in_background=true)
# with no timeout constraint, and Claude synthesizes in-conversation.
probe_single_agent() {
    local _ts; _ts=$(date +%s)
    local agent_type="$1"
    local perspective="$2"
    local task_id="$3"
    local original_prompt="${4:-}"

    log "INFO" "probe_single_agent: agent=$agent_type task=$task_id"
    log "DEBUG" "probe_single_agent: perspective=${perspective:0:100}..."

    # Pre-flight validation
    preflight_check || return 1

    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    # Dispatch from the user's project so provider sandboxes (codex workdir,
    # provider sandboxes can read project files (bug 260609). probe-single runs
    # in its own orchestrate.sh process, so cd here cannot leak to other work.
    if [[ -n "${PROJECT_ROOT:-}" && -d "$PROJECT_ROOT" ]]; then
        cd "$PROJECT_ROOT" || log "WARN" "probe_single_agent: cannot cd to PROJECT_ROOT=$PROJECT_ROOT"
    fi

    # Determine role and phase
    local role="researcher"
    local phase="probe"

    # Determine role if routing rules override
    local routed_role
    routed_role=$(match_routing_rule "$(classify_task "$perspective" 2>/dev/null)" "$perspective" 2>/dev/null) || true
    if [[ -n "$routed_role" ]]; then
        role="$routed_role"
    fi

    # v8.53.0: Pre-compute curated_name for readonly frontmatter check
    local curated_name_early=""
    if [[ "$SUPPORTS_AGENT_TYPE_ROUTING" == "true" ]]; then
        curated_name_early=$(select_curated_agent "$perspective" "$phase") || true
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # Cache-aligned prompt structure: stable prefix first, variable suffix last
    # This enables Claude's cached-token discount on repeated prefix content
    # ═══════════════════════════════════════════════════════════════════════════

    # ── STABLE PREFIX ─────────────────────────────────────────────────────────

    # Apply persona to prompt
    local enhanced_prompt
    enhanced_prompt=$(apply_persona "$role" "$perspective" "false" "${curated_name_early:-}")

    # v8.21.0: Persona pack override
    if type get_persona_override &>/dev/null 2>&1 && [[ "${OCTOPUS_PERSONA_PACKS:-auto}" != "off" ]]; then
        local persona_override_file
        persona_override_file=$(get_persona_override "${curated_name_early:-$agent_type}" 2>/dev/null)
        if [[ -n "$persona_override_file" && -f "$persona_override_file" ]]; then
            local pack_persona
            pack_persona=$(cat "$persona_override_file" 2>/dev/null)
            if [[ -n "$pack_persona" ]]; then
                enhanced_prompt="${pack_persona}

---

${enhanced_prompt}"
            fi
        fi
    fi

    # v9.3.0: Search spiral guard — prevent research agents from token waste (STABLE — static boilerplate)
    enhanced_prompt="${enhanced_prompt}

IMPORTANT: If you find yourself searching or grepping more than 3 times in a row without reading files or writing analysis, STOP searching. Consolidate what you've found so far and write your analysis. More searching rarely improves the output — synthesis does."

    # ── VARIABLE SUFFIX ───────────────────────────────────────────────────────
    # (probe dispatch has minimal variable content — context budget is the boundary)

    # v8.10.0: Enforce context budget AFTER all injections
    local tokens_in
    tokens_in=$(( ${#enhanced_prompt} / 4 ))
    enhanced_prompt=$(enforce_context_budget "$enhanced_prompt" "$role" "$agent_type")
    local _budget_rc=$?
    if [[ $_budget_rc -ne 0 ]]; then
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" 0 "Prompt exceeded context budget" 0 "" "$role" || true
        return "$_budget_rc"
    fi

    # Resolve model and command
    local model
    model=$(get_agent_model "$agent_type" "$phase" "$role")

    local cmd
    if ! cmd=$(get_agent_command "$agent_type" "$phase" "$role"); then
        log ERROR "Unknown agent type: $agent_type"
        return 1
    fi

    if ! validate_agent_command "$cmd"; then
        log ERROR "Invalid agent command: $cmd"
        return 1
    fi

    # Record agent call
    record_agent_call "$agent_type" "$model" "$enhanced_prompt" "$phase" "$role" "0"
    local estimated_cost="0.000000"
    if type estimate_agent_call_cost >/dev/null 2>&1; then
        estimated_cost=$(estimate_agent_call_cost "$agent_type" "$model" "$enhanced_prompt")
    fi

    # Track provider usage
    local provider_name
    case "$agent_type" in
        codex*) provider_name="codex" ;;
        gemini*|agy*|antigravity) provider_name="agy" ;;
        claude*) provider_name="claude" ;;
        perplexity*) provider_name="perplexity" ;;
        copilot*) provider_name="copilot" ;;
        ollama*) provider_name="ollama" ;;
        qwen*) provider_name="qwen" ;;
        cursor-agent*) provider_name="cursor-agent" ;;
        opencode*) provider_name="opencode" ;;
        *) provider_name="$agent_type" ;;
    esac
    update_metrics "provider" "$provider_name" 2>/dev/null || true

    # Register in bridge ledger
    bridge_register_task "$task_id" "$agent_type" "$phase" "$role" || true

    local result_file="${RESULTS_DIR}/${agent_type}-${task_id}.md"
    update_agent_status "$agent_type" "running" 0 "$estimated_cost" "$TIMEOUT" "$task_id" "$phase" "$result_file"

    # Build command array with credential isolation
    local -a cmd_array
    local -a inner_cmd_array
    build_provider_env "$agent_type"
    read -ra inner_cmd_array <<< "$cmd"
    if [[ ${#PROVIDER_ENV_ARRAY[@]} -gt 0 ]]; then
        cmd_array=("${PROVIDER_ENV_ARRAY[@]}" "${inner_cmd_array[@]}")
    else
        cmd_array=("${inner_cmd_array[@]}")
    fi

    local temp_output="${RESULTS_DIR}/.tmp-${task_id}.out"
    local temp_errors="${RESULTS_DIR}/.tmp-${task_id}.err"
    local temp_input="${RESULTS_DIR}/.tmp-${task_id}.in"
    local raw_output="${RESULTS_DIR}/.raw-${task_id}.out"

    # Write result file header
    echo "# Agent: $agent_type" > "$result_file"
    echo "# Task ID: $task_id" >> "$result_file"
    echo "# Role: $role" >> "$result_file"
    echo "# Phase: $phase" >> "$result_file"
    echo "# Prompt: ${perspective:0:200}" >> "$result_file"
    echo "# Started: $(date)" >> "$result_file"
    echo "" >> "$result_file"
    echo "## Output" >> "$result_file"
    echo '```' >> "$result_file"

    # Append headless flag (-p "" triggers stdin reading) for CLI providers
    # Qwen and Cursor Agent require the same stdin headless trigger.
    if [[ "$agent_type" == copilot* ]] || [[ "$agent_type" == qwen* ]] || [[ "$agent_type" == cursor-agent* ]]; then
        cmd_array+=(-p "")
    fi

    # Auth-aware retry loop (same logic as spawn_agent legacy path)
    local max_auth_retries=0
    if [[ "$OCTOPUS_BACKEND" != "api" ]]; then
        max_auth_retries="${OCTOPUS_AUTH_RETRIES:-2}"
    fi
    if [[ "$SUPPORTS_STABLE_AUTH" == "true" ]]; then
        max_auth_retries=$((max_auth_retries > 1 ? 1 : max_auth_retries))
    fi

    local auth_attempt=0
    local exit_code=0
    local final_rc=0
    local start_time_ms
    start_time_ms=$(( $(date +%s) * 1000 ))

    while true; do
        exit_code=0
        # v9.2.2: All agents use stdin to avoid ARG_MAX. File-backed capture is
        # portable to Git Bash and cannot be held open by provider descendants.
        if octopus_capture_provider_output \
            "$enhanced_prompt" "$TIMEOUT" "$temp_input" \
            "$raw_output" "$temp_errors" "${cmd_array[@]}"; then
            exit_code=0
        else
            exit_code=$?
        fi
        cp "$raw_output" "$temp_output" 2>/dev/null || : > "$temp_output"

        if [[ $exit_code -ne 0 ]] && [[ $auth_attempt -lt $max_auth_retries ]]; then
            local stderr_content=""
            [[ -s "$temp_errors" ]] && stderr_content=$(<"$temp_errors")
            if [[ "$stderr_content" == *"unauthorized"* ]] || \
               [[ "$stderr_content" == *"401"* ]] || \
               [[ "$stderr_content" == *"auth"* ]] || \
               [[ "$stderr_content" == *"credential"* ]] || \
               [[ "$stderr_content" == *"token expired"* ]] || \
               [[ "$stderr_content" == *"refresh"* ]]; then
                ((auth_attempt++)) || true
                local backoff=$((auth_attempt * 5))
                log "WARN" "Auth failure (attempt $auth_attempt/$max_auth_retries), retrying in ${backoff}s..."
                sleep "$backoff"
                : > "$temp_output"; : > "$temp_errors"; : > "$raw_output"
                continue
            fi
        fi
        break
    done

    # Process output
    if [[ $exit_code -eq 0 ]]; then
        local separator_count
        separator_count=$(grep -cE '^--------$' "$temp_output" 2>/dev/null || true)
        separator_count=${separator_count%%$'\n'*}
        separator_count=${separator_count:-0}
        if [[ "$agent_type" == cursor-agent* ]]; then
            # cursor-agent stdout is clean — strip surrounding blanks only
            awk '
                !started && /^[[:space:]]*$/ { next }
                { started = 1; lines[++count] = $0 }
                END {
                    while (count > 0 && lines[count] ~ /^[[:space:]]*$/) {
                        count--
                    }
                    for (i = 1; i <= count; i++) {
                        print lines[i]
                    }
                }
            ' "$temp_output" >> "$result_file"
        elif [[ "${separator_count:-0}" -gt 0 ]]; then
            # v9.27.0: Port #191 awk-header-guard fix from spawn_agent — codex exec
            # sends clean response on stdout (no header), banner on stderr.
            awk '
                BEGIN { in_response = 0; header_done = 0; }
                /^--------$/ { header_done = 1; next; }
                !header_done { next; }
                /^(codex|assistant)$/ { in_response = 1; next; }
                /^thinking$/ { next; }
                /^tokens used$/ { next; }
                /^[0-9,]+$/ && in_response { next; }
                in_response { print; }
            ' "$temp_output" >> "$result_file"
        else
            # No separator + not cursor-agent: strip noise banners (v9.27.0)
            grep -v \
                -e '^MCP issues detected' \
                -e '^Loading extension:' \
                -e '^YOLO mode is enabled' \
                -e '^Run /mcp' \
                "$temp_output" >> "$result_file" 2>/dev/null || cat "$temp_output" >> "$result_file"
        fi
        local codex_stderr_transcript_appended=false
        if [[ "$agent_type" == codex* ]] \
            && ! grep -q '[[:alnum:]]' "$temp_output" 2>/dev/null \
            && type octo_file_has_codex_recoverable_stderr >/dev/null 2>&1 \
            && octo_file_has_codex_recoverable_stderr "$temp_errors"; then
            echo "(Codex response was emitted on stderr; see Errors transcript below.)" >> "$result_file"
            echo '```' >> "$result_file"
            echo "" >> "$result_file"
            echo "## Errors" >> "$result_file"
            echo '```' >> "$result_file"
            cat "$temp_errors" >> "$result_file"
            echo '```' >> "$result_file"
            echo "" >> "$result_file"
            codex_stderr_transcript_appended=true
        fi

        # Trust marker for external CLI output
        case "$agent_type" in codex*|gemini*|agy*|antigravity|perplexity*|cursor-agent*)
            if [[ "${OCTOPUS_SECURITY_V870:-true}" == "true" ]]; then
                sed -i.bak '1s/^/<!-- trust=untrusted provider='"$agent_type"' -->\n/' "$result_file" 2>/dev/null || true
                rm -f "${result_file}.bak"
            fi ;; esac

        local end_time_ms elapsed_ms
        end_time_ms=$(( $(date +%s) * 1000 ))
        elapsed_ms=$((end_time_ms - start_time_ms))

        local classification status reason tokens_out
        classification=$(classify_agent_output "$temp_output" "$exit_code" "$agent_type" "$temp_errors" 2>/dev/null || echo "ok:")
        status="${classification%%:*}"
        reason="${classification#*:}"
        tokens_out=$(octo_estimate_tokens_for_file "$temp_output" 2>/dev/null || echo 0)

        if [[ "$codex_stderr_transcript_appended" != "true" ]]; then
            echo '```' >> "$result_file"
            echo "" >> "$result_file"
        fi
        # Legacy result consumers look for literal "Status: FAILED" and "Status: TIMEOUT" markers.
        case "$status" in
            failed)
                echo "## Status: FAILED (${reason:-unusable output})" >> "$result_file"
                if [[ -s "$temp_errors" ]]; then
                    echo "" >> "$result_file"
                    echo "## Errors" >> "$result_file"
                    echo '```' >> "$result_file"
                    cat "$temp_errors" >> "$result_file"
                    echo '```' >> "$result_file"
                fi
                update_agent_status "$agent_type" "failed" "$elapsed_ms" "$estimated_cost" "$TIMEOUT" "$task_id" "$phase" "$result_file"
                record_outcome "$agent_type" "$agent_type" "research" "$phase" "fail" "$elapsed_ms" 2>/dev/null || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" "$tokens_out" "${reason:-unusable output}" "$elapsed_ms" "$result_file" "$role" || true
                final_rc=1
                ;;
            degraded)
                echo "## Status: SUCCESS (DEGRADED: ${reason:-partial output})" >> "$result_file"
                update_agent_status "$agent_type" "degraded" "$elapsed_ms" "$estimated_cost" "$TIMEOUT" "$task_id" "$phase" "$result_file"
                record_outcome "$agent_type" "$agent_type" "research" "$phase" "success" "$elapsed_ms" 2>/dev/null || true
                record_run_pattern "$agent_type" "${enhanced_prompt:-$original_prompt}" "$result_file" 2>/dev/null || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "degraded" "$tokens_in" "$tokens_out" "${reason:-partial output}" "$elapsed_ms" "$result_file" "$role" || true
                ;;
            *)
                echo "## Status: SUCCESS" >> "$result_file"
                update_agent_status "$agent_type" "completed" "$elapsed_ms" "$estimated_cost" "$TIMEOUT" "$task_id" "$phase" "$result_file"
                record_outcome "$agent_type" "$agent_type" "research" "$phase" "success" "$elapsed_ms" 2>/dev/null || true
                # v9.3.0: Record file co-occurrence pattern for heuristic learning
                record_run_pattern "$agent_type" "${enhanced_prompt:-$original_prompt}" "$result_file" 2>/dev/null || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "ok" "$tokens_in" "$tokens_out" "" "$elapsed_ms" "$result_file" "$role" || true
                ;;
        esac
    elif [[ $exit_code -eq 124 ]] || [[ $exit_code -eq 143 ]]; then
        # Timeout — preserve partial output
        if [[ -s "$temp_output" ]]; then
            if [[ $(grep -c '^--------$' "$temp_output" 2>/dev/null || true) -gt 0 ]]; then
                awk '
                    BEGIN { in_response = 0; header_done = 0; }
                    /^--------$/ { header_done = 1; next; }
                    !header_done { next; }
                    /^(codex|assistant)$/ { in_response = 1; next; }
                    /^thinking$/ { next; }
                    /^tokens used$/ { next; }
                    /^[0-9,]+$/ && in_response { next; }
                    in_response { print; }
                ' "$temp_output" >> "$result_file"
            else
                cat "$temp_output" >> "$result_file"
            fi
        fi
        echo '```' >> "$result_file"
        echo "" >> "$result_file"
        echo "## Status: TIMEOUT" >> "$result_file"
        log "WARN" "Agent $agent_type timed out for task $task_id"
        local end_time_ms elapsed_ms tokens_out
        end_time_ms=$(( $(date +%s) * 1000 ))
        elapsed_ms=$((end_time_ms - start_time_ms))
        tokens_out=$(octo_estimate_tokens_for_file "$temp_output" 2>/dev/null || echo 0)
        update_agent_status "$agent_type" "timeout" "$elapsed_ms" "$estimated_cost" "$TIMEOUT" "$task_id" "$phase" "$result_file"
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "timeout" "$tokens_in" "$tokens_out" "Timed out before completion" "$elapsed_ms" "$result_file" "$role" || true
        final_rc=$exit_code
    else
        # Failure
        if [[ -s "$temp_output" ]]; then
            cat "$temp_output" >> "$result_file"
        fi
        echo '```' >> "$result_file"
        echo "" >> "$result_file"
        echo "## Status: FAILED (exit code: $exit_code)" >> "$result_file"
        if [[ -s "$temp_errors" ]]; then
            echo "" >> "$result_file"
            echo "## Errors" >> "$result_file"
            echo '```' >> "$result_file"
            cat "$temp_errors" >> "$result_file"
            echo '```' >> "$result_file"
        fi
        log "WARN" "Agent $agent_type failed for task $task_id (exit=$exit_code)"
        local end_time_ms elapsed_ms tokens_out
        end_time_ms=$(( $(date +%s) * 1000 ))
        elapsed_ms=$((end_time_ms - start_time_ms))
        tokens_out=$(octo_estimate_tokens_for_file "$temp_output" 2>/dev/null || echo 0)
        update_agent_status "$agent_type" "failed" "$elapsed_ms" "$estimated_cost" "$TIMEOUT" "$task_id" "$phase" "$result_file"
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" "$tokens_out" "Exit code $exit_code" "$elapsed_ms" "$result_file" "$role" || true
        final_rc=$exit_code
    fi

    # Cleanup temp files
    rm -f "$temp_input" "$temp_output" "$temp_errors" "$raw_output"

    log "INFO" "probe_single_agent complete: $result_file"
    # Output the result file path for the caller
    echo "$result_file"
    return "$final_rc"
}

# Active probe cancellation state is global because Bash signal traps can fire
# while the main shell is blocked inside a child command or progress loop. The
# state is populated incrementally, so cancellation during the spawn loop can
# still reconcile tasks already appended to the PID ledger.
OCTOPUS_ACTIVE_PROBE_TASK_GROUP=""
OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID=""
OCTOPUS_ACTIVE_PROBE_SYNTHESIS_LAUNCHING="false"
OCTOPUS_ACTIVE_PROBE_TMUX="false"
OCTOPUS_ACTIVE_PROBE_PIDS=()
OCTOPUS_ACTIVE_PROBE_AGENTS=()
OCTOPUS_ACTIVE_PROBE_TASK_IDS=()

octopus_probe_clear_active() {
    OCTOPUS_ACTIVE_PROBE_TASK_GROUP=""
    OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID=""
    OCTOPUS_ACTIVE_PROBE_SYNTHESIS_LAUNCHING="false"
    OCTOPUS_ACTIVE_PROBE_TMUX="false"
    OCTOPUS_ACTIVE_PROBE_PIDS=()
    OCTOPUS_ACTIVE_PROBE_AGENTS=()
    OCTOPUS_ACTIVE_PROBE_TASK_IDS=()
}

_octopus_probe_restore_traps() {
    local previous_int_trap="${1:-}"
    local previous_term_trap="${2:-}"

    octopus_probe_clear_active
    if [[ -n "$previous_int_trap" ]]; then
        eval "$previous_int_trap"
    else
        trap - INT
    fi
    if [[ -n "$previous_term_trap" ]]; then
        eval "$previous_term_trap"
    else
        trap - TERM
    fi
}

_octopus_probe_terminate_tree() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
    kill -0 "$pid" 2>/dev/null || return 0

    if declare -F review_terminate_process_tree >/dev/null 2>&1; then
        review_terminate_process_tree "$pid" 1
    else
        pkill -TERM -P "$pid" 2>/dev/null || true
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        pkill -KILL -P "$pid" 2>/dev/null || true
        kill -KILL "$pid" 2>/dev/null || true
    fi
}

_octopus_probe_prune_pid_ledger() {
    local task_group="$1"
    [[ -n "${PID_FILE:-}" && -f "$PID_FILE" ]] || return 0

    local tmp_file="${PID_FILE}.cancel.$$"
    if awk -F: -v prefix="probe-${task_group}-" \
        'index($3, prefix) != 1 { print }' "$PID_FILE" > "$tmp_file"; then
        mv -f "$tmp_file" "$PID_FILE"
    else
        rm -f "$tmp_file" 2>/dev/null || true
    fi
}

octopus_probe_cancel_active() {
    local signal_name="${1:-TERM}"
    local task_group="${OCTOPUS_ACTIVE_PROBE_TASK_GROUP:-}"
    [[ -n "$task_group" ]] || return 0

    local exit_code=143
    [[ "$signal_name" == "INT" ]] && exit_code=130

    # The + expansion is required for Bash 3.2 with nounset: expanding a
    # declared-but-empty array directly is treated as an unbound variable.
    local -a cancel_pids=("${OCTOPUS_ACTIVE_PROBE_PIDS[@]+"${OCTOPUS_ACTIVE_PROBE_PIDS[@]}"}")
    local -a cancel_agents=("${OCTOPUS_ACTIVE_PROBE_AGENTS[@]+"${OCTOPUS_ACTIVE_PROBE_AGENTS[@]}"}")
    local -a cancel_tasks=("${OCTOPUS_ACTIVE_PROBE_TASK_IDS[@]+"${OCTOPUS_ACTIVE_PROBE_TASK_IDS[@]}"}")
    local ledger_pid ledger_agent ledger_task existing found found_idx idx

    for idx in "${!cancel_tasks[@]}"; do
        [[ -n "${cancel_agents[$idx]:-}" ]] || cancel_agents[$idx]="unknown"
        [[ -n "${cancel_tasks[$idx]:-}" ]] \
            || cancel_tasks[$idx]="probe-${task_group}-${idx}"
    done

    # The PID ledger is authoritative for a signal that lands between spawn's
    # append and the caller's array assignment.
    if [[ -n "${PID_FILE:-}" && -f "$PID_FILE" ]]; then
        while IFS=: read -r ledger_pid ledger_agent ledger_task; do
            [[ "$ledger_task" == "probe-${task_group}-"* ]] || continue
            found=false
            found_idx=""
            for idx in "${!cancel_tasks[@]}"; do
                existing="${cancel_tasks[$idx]:-}"
                if [[ "$existing" == "$ledger_task" ]]; then
                    found=true
                    found_idx="$idx"
                    break
                fi
            done
            if [[ "$found" == "true" ]]; then
                [[ -n "${cancel_pids[$found_idx]:-}" ]] \
                    || cancel_pids[$found_idx]="$ledger_pid"
                [[ -n "${cancel_agents[$found_idx]:-}" ]] \
                    || cancel_agents[$found_idx]="$ledger_agent"
            else
                cancel_pids+=("$ledger_pid")
                cancel_agents+=("$ledger_agent")
                cancel_tasks+=("$ledger_task")
            fi
        done < "$PID_FILE"
    fi

    local synthesis_pid="${OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID:-}"
    # A trap can run after the monitor has been backgrounded but before the
    # caller assigns $! to the registered PID. During that tiny handoff window,
    # the shell's last-background PID is the authoritative value.
    if [[ ! "$synthesis_pid" =~ ^[0-9]+$ ]] \
       && [[ "${OCTOPUS_ACTIVE_PROBE_SYNTHESIS_LAUNCHING:-false}" == "true" ]]; then
        synthesis_pid="${!:-}"
    fi
    if [[ "$synthesis_pid" =~ ^[0-9]+$ ]]; then
        _octopus_probe_terminate_tree "$synthesis_pid"
        wait "$synthesis_pid" 2>/dev/null || true
    fi

    for idx in "${!cancel_tasks[@]}"; do
        ledger_pid="${cancel_pids[$idx]:-}"
        _octopus_probe_terminate_tree "$ledger_pid"
    done

    local result_file done_file completed task_id agent
    for idx in "${!cancel_tasks[@]}"; do
        ledger_pid="${cancel_pids[$idx]:-}"
        agent="${cancel_agents[$idx]:-unknown}"
        task_id="${cancel_tasks[$idx]:-probe-${task_group}-${idx}}"
        result_file="${RESULTS_DIR:-}/$agent-$task_id.md"
        done_file="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents/${task_id}.done"
        completed=false
        [[ -f "$done_file" ]] && completed=true
        if [[ -f "$result_file" ]] \
           && grep -Eq '^# Completed:|^## Status: (SUCCESS|FAILED|TIMEOUT)' "$result_file" 2>/dev/null; then
            completed=true
        fi

        if [[ "$ledger_pid" =~ ^[0-9]+$ ]]; then
            wait "$ledger_pid" 2>/dev/null || true
            rm -f "${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents/${ledger_pid}.heartbeat" \
                2>/dev/null || true
        fi

        if [[ "$completed" == "false" ]]; then
            if [[ -f "$result_file" ]] && ! grep -c '^## Status: CANCELLED' "$result_file" >/dev/null 2>&1; then
                {
                    echo '```'
                    echo ""
                    echo "## Status: CANCELLED - PARTIAL RESULTS"
                    echo ""
                    echo "Probe interrupted by SIG${signal_name}; partial output above was preserved."
                } >> "$result_file"
            fi
            if declare -F _octopus_agent_lifecycle_event >/dev/null 2>&1; then
                _octopus_agent_lifecycle_event "cancelled" "$agent" "$task_id" \
                    "researcher" "probe" "$ledger_pid" "$result_file" \
                    "$exit_code" "cancelled"
            fi
        fi
    done

    _octopus_probe_prune_pid_ledger "$task_group"
    if [[ "${OCTOPUS_ACTIVE_PROBE_TMUX:-false}" == "true" ]] \
       && declare -F tmux_cleanup >/dev/null 2>&1; then
        tmux_cleanup 2>/dev/null || true
    fi
    octopus_probe_clear_active
}

_octopus_probe_start_synthesis_monitor() {
    local task_group="$1"
    local prompt="$2"
    local interval="${3:-2}"

    OCTOPUS_ACTIVE_PROBE_SYNTHESIS_LAUNCHING="true"
    progressive_synthesis_monitor "$task_group" "$prompt" "$interval" &
    local monitor_pid=$!

    # Runtime-only seam for deterministically exercising the signal handoff.
    if declare -F _octopus_test_after_synthesis_spawn >/dev/null 2>&1; then
        _octopus_test_after_synthesis_spawn "$monitor_pid"
    fi

    # A cancellation during the handoff clears the active task group. Reap the
    # just-launched monitor and do not re-register stale state afterward.
    if [[ -z "${OCTOPUS_ACTIVE_PROBE_TASK_GROUP:-}" ]]; then
        _octopus_probe_terminate_tree "$monitor_pid"
        wait "$monitor_pid" 2>/dev/null || true
        OCTOPUS_ACTIVE_PROBE_SYNTHESIS_LAUNCHING="false"
        return 143
    fi

    OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID="$monitor_pid"
    OCTOPUS_ACTIVE_PROBE_SYNTHESIS_LAUNCHING="false"
    return 0
}

_octopus_probe_finalize_synthesis() {
    local task_group="$1"
    local prompt="$2"
    local usable_results="$3"
    local synthesis_marker="$4"
    local synthesis_monitor_pid="$5"
    local previous_int_trap="${6:-}"
    local previous_term_trap="${7:-}"
    local synthesis_status=0
    local summary_status=0

    synthesize_probe_results "$task_group" "$prompt" "$usable_results" \
        || synthesis_status=$?

    # Preserve the marker on failure so synthesize-probe can recover the run.
    if [[ "$synthesis_status" -eq 0 ]]; then
        rm -f "$synthesis_marker"
        log DEBUG "Synthesis marker removed (synthesis completed successfully)"
    fi

    if [[ "$synthesis_monitor_pid" =~ ^[0-9]+$ ]]; then
        kill "$synthesis_monitor_pid" 2>/dev/null || true
        wait "$synthesis_monitor_pid" 2>/dev/null || true
        OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID=""
        log "DEBUG" "Progressive synthesis monitor stopped"
    fi

    # Guard summary rendering because orchestrate.sh enables errexit. Cleanup
    # and trap restoration must happen even when the renderer fails.
    display_progress_summary || summary_status=$?
    _octopus_probe_restore_traps "$previous_int_trap" "$previous_term_trap"

    [[ "$synthesis_status" -ne 0 ]] && return "$synthesis_status"
    return "$summary_status"
}

octopus_probe_handle_signal() {
    local signal_name="${1:-TERM}"
    local exit_code=143
    [[ "$signal_name" == "INT" ]] && exit_code=130
    trap - INT TERM
    octopus_probe_cancel_active "$signal_name"
    exit "$exit_code"
}

# Phase 1: PROBE (Discover) - Parallel research with synthesis
# Like an octopus probing with multiple tentacles simultaneously
probe_discover() {
    local _ts; _ts=$(date +%s)
    local prompt="$1"
    local task_group="$_ts"
    export OCTOPUS_COMMAND="${OCTOPUS_COMMAND:-discover}"
    export OCTOPUS_COMMAND_ARGS="${OCTOPUS_COMMAND_ARGS:-$prompt}"

    echo ""
    octopus_phase_banner "RESEARCH (Phase 1/4)" "Parallel Exploration" "$MAGENTA"
    echo ""

    log INFO "Phase 1: Parallel exploration with multiple perspectives"
    log "DEBUG" "probe_discover: task_group=$task_group, results_dir=$RESULTS_DIR"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would probe: $prompt"
        log INFO "[DRY-RUN] Would spawn 5+ parallel research agents (Codex, Antigravity/agy, Sonnet 5, +codebase if in git repo, +Perplexity if API key set)"
        return 0
    fi

    # Pre-flight validation
    preflight_check || return 1

    # Cost transparency (v7.18.0 - P0.0)
    # v8.24.0: Perplexity adds +1 external call when available
    local probe_external_calls=5
    [[ -n "${PERPLEXITY_API_KEY:-}" ]] && ((++probe_external_calls))
    if ! display_workflow_cost_estimate "Probe (Discover Phase)" "$probe_external_calls" 0 1500; then
        log "WARN" "Workflow cancelled by user after cost review"
        return 1
    fi

    # v7.19.0 P2.3: Check cache for existing results
    local cache_key
    cache_key=$(get_cache_key "$prompt")

    if check_cache "$cache_key"; then
        echo -e "${CYAN}♻️  Using cached results from previous run${NC}"
        local cached_file="${CACHE_DIR}/${cache_key}.md"
        local synthesis_file="${RESULTS_DIR}/probe-synthesis-${task_group}.md"

        # Copy cached result to current synthesis file
        cp "$cached_file" "$synthesis_file"

        log "INFO" "Cache hit - skipping probe execution"
        echo -e "${GREEN}✓${NC} Synthesis retrieved from cache: $synthesis_file"
        echo ""

        return 0
    fi

    # Clean up expired cache entries
    cleanup_cache

    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    # Initialize tmux if enabled
    if [[ "$TMUX_MODE" == "true" ]]; then
        tmux_init
    fi

    # Research prompts from different angles
    local perspectives=(
        "Analyze the problem space: $prompt. Focus on understanding constraints, requirements, and user needs."
        "Research existing solutions and patterns for: $prompt. What has been done before? What worked, what failed?"
        "Explore edge cases and potential challenges for: $prompt. What could go wrong? What's often overlooked?"
        "Investigate technical feasibility and dependencies for: $prompt. What are the prerequisites?"
        "Synthesize cross-cutting concerns for: $prompt. What themes emerge across problem space, solutions, and feasibility?"
    )
    local pane_titles=(
        "🔍 Problem Analysis"
        "📚 Solution Research"
        "⚠️  Edge Cases"
        "🔧 Feasibility"
        "🔵 Cross-Synthesis"
    )
    # v9.2.0: Smart dispatch — choose providers based on task analysis
    local dispatch_result
    dispatch_result=$(get_dispatch_strategy "$prompt" "research")
    local dispatch_providers
    dispatch_providers=$(echo "$dispatch_result" | cut -d: -f2)
    log INFO "probe_discover: smart dispatch=$dispatch_result"

    # Build agent rotation from dispatch strategy
    local IFS_OLD="$IFS"
    IFS=',' read -ra _strategy_providers <<< "$dispatch_providers"
    IFS="$IFS_OLD"
    local probe_agents=()
    local _sp_count=${#_strategy_providers[@]}
    for _pi in "${!perspectives[@]}"; do
        probe_agents+=("${_strategy_providers[$((_pi % _sp_count))]}")
    done

    # v9.2.0: Blind spot injection — augment edge-case + synthesis perspectives
    local _blind_spot_checklist
    _blind_spot_checklist=$(load_blind_spot_checklist "$prompt")
    if [[ -n "$_blind_spot_checklist" ]]; then
        log INFO "probe_discover: injecting blind spot checklist ($(echo "$_blind_spot_checklist" | wc -l | tr -d ' ') items)"
        # Augment edge-case perspective (index 2)
        perspectives[2]="${perspectives[2]}

IMPORTANT — The following perspectives are systematically missed by LLMs. You MUST address each one:
${_blind_spot_checklist}"
        # Augment cross-synthesis perspective (index 4)
        perspectives[4]="${perspectives[4]}

When synthesizing, verify that these commonly-missed perspectives have been addressed. If any were missed by other agents, include them:
${_blind_spot_checklist}"
    fi

    # v8.14.0: Codebase-aware discovery — add 6th agent when inside a git repo
    if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        local src_dirs
        src_dirs=$(find . -maxdepth 2 -type f \( -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.js" \) 2>/dev/null | head -1)
        if [[ -n "$src_dirs" ]]; then
            perspectives+=("Analyze the LOCAL CODEBASE in the current directory for: $prompt. Run: find . -type f -name '*.ts' -o -name '*.py' -o -name '*.js' | head -30, then read key files. Report: tech stack, architecture patterns, file structure, coding conventions, and how they relate to the prompt. Focus on ACTUAL code, not hypotheticals.")
            pane_titles+=("📂 Codebase Analysis")
            probe_agents+=("claude-sonnet")
            log INFO "Codebase detected - adding local codebase analysis agent"
        fi
    fi

    # v8.24.0: Web-grounded research via Perplexity Sonar (Issue #22)
    # Adds a live web search perspective when PERPLEXITY_API_KEY is available
    if [[ -n "${PERPLEXITY_API_KEY:-}" ]]; then
        perspectives+=("Search the live web for the latest information about: $prompt. Find recent articles, documentation, blog posts, GitHub repos, and community discussions. Include source URLs and publication dates. Focus on information from the last 12 months that may not be in training data.")
        pane_titles+=("🟣 Web Research")
        probe_agents+=("perplexity")
        log INFO "Perplexity API key detected - adding web-grounded research agent"
    fi

    # Initialize progress tracking with actual agent count (dynamic, may be 5, 6, or 7)
    init_progress_tracking "discover" "${#perspectives[@]}"

    local probe_previous_int_trap probe_previous_term_trap
    probe_previous_int_trap="$(trap -p INT)"
    probe_previous_term_trap="$(trap -p TERM)"
    OCTOPUS_ACTIVE_PROBE_TASK_GROUP="$task_group"
    OCTOPUS_ACTIVE_PROBE_TMUX="$TMUX_MODE"
    OCTOPUS_ACTIVE_PROBE_PIDS=()
    OCTOPUS_ACTIVE_PROBE_AGENTS=()
    OCTOPUS_ACTIVE_PROBE_TASK_IDS=()
    trap 'octopus_probe_handle_signal INT' INT
    trap 'octopus_probe_handle_signal TERM' TERM

    fleet_dispatch_begin

    local pids=()
    for i in "${!perspectives[@]}"; do
        local perspective="${perspectives[$i]}"
        local agent="${probe_agents[$i]}"
        local task_id="probe-${task_group}-${i}"
        OCTOPUS_ACTIVE_PROBE_AGENTS+=("$agent")
        OCTOPUS_ACTIVE_PROBE_TASK_IDS+=("$task_id")

        local pid=""
        local spawn_status=0
        if [[ "$TMUX_MODE" == "true" ]]; then
            # Use async+tmux spawning
            if pid=$(spawn_agent_async "$agent" "$perspective" "$task_id" "researcher" "probe" "${pane_titles[$i]}"); then
                :
            else
                spawn_status=$?
            fi
        else
            # Standard spawning
            if pid=$(spawn_agent_capture_pid "$agent" "$perspective" "$task_id" "researcher" "probe"); then
                :
            else
                spawn_status=$?
            fi
        fi
        if [[ "$spawn_status" -eq 0 && ! "$pid" =~ ^[0-9]+$ ]]; then
            spawn_status=1
        fi
        if [[ "$spawn_status" -ne 0 ]]; then
            log ERROR "probe_discover: failed to spawn $agent for $task_id"
            octopus_probe_cancel_active TERM
            fleet_dispatch_end
            _octopus_probe_restore_traps "$probe_previous_int_trap" "$probe_previous_term_trap"
            return "$spawn_status"
        fi
        pids+=("$pid")
        OCTOPUS_ACTIVE_PROBE_PIDS+=("$pid")
        sleep 0.1
    done

    fleet_dispatch_end

    log INFO "Spawned ${#pids[@]} parallel research threads"

    # v7.19.0 P2.4: Start progressive synthesis monitor in background
    local synthesis_monitor_pid=""
    if [[ "$ENABLE_PROGRESSIVE_SYNTHESIS" == "true" ]]; then
        local monitor_start_status=0
        _octopus_probe_start_synthesis_monitor "$task_group" "$prompt" 2 \
            || monitor_start_status=$?
        if [[ "$monitor_start_status" -ne 0 ]]; then
            octopus_probe_cancel_active TERM
            _octopus_probe_restore_traps "$probe_previous_int_trap" "$probe_previous_term_trap"
            return "$monitor_start_status"
        fi
        synthesis_monitor_pid="$OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID"
        log "DEBUG" "Progressive synthesis monitor started (PID: $synthesis_monitor_pid)"
    fi

    # Wait for all to complete with progress
    # v7.19.0 P1.2: Rich progress display
    local start_time=$(date +%s)
    OCTO_PROGRESS_AGENT_TYPES=("${probe_agents[@]}")
    OCTO_PROGRESS_AGENT_NAMES=("${pane_titles[@]}")
    display_rich_progress "$task_group" "${#pids[@]}" "$start_time" "${pids[@]}"
    unset OCTO_PROGRESS_AGENT_TYPES OCTO_PROGRESS_AGENT_NAMES

    # Cleanup tmux if enabled
    if [[ "$TMUX_MODE" == "true" ]]; then
        tmux_cleanup
    fi

    # v7.25.0: Record agent completion metrics
    if command -v record_agents_batch_complete &> /dev/null; then
        record_agents_batch_complete "probe" "$task_group" 2>/dev/null || true
    fi

    # v8.34.0: Agent memory GC — release completed subagent state (G11)
    if [[ "$SUPPORTS_AGENT_MEMORY_GC" == "true" ]]; then
        log "DEBUG" "Agent memory GC available — Claude Code will release completed subagent state"
    fi

    # v7.19.0 P0.3: Check agent status and report results
    echo ""
    echo -e "${CYAN}Analyzing results...${NC}"
    local success_count=0
    local timeout_count=0
    local failure_count=0
    local total_size=0

    for i in "${!perspectives[@]}"; do
        local task_id="probe-${task_group}-${i}"
        local agent="${probe_agents[$i]}"
        local result_file="${RESULTS_DIR}/${agent}-${task_id}.md"

        if [[ -f "$result_file" ]]; then
            local file_size
            file_size=$(wc -c < "$result_file" 2>/dev/null || echo "0")
            total_size=$((total_size + file_size))

            # Capitalize first letter of agent name properly
            local agent_display="$(_ucfirst "$agent")"

            local classification status reason
            classification="$(probe_result_file_status "$result_file")"
            status="${classification%%:*}"
            reason="${classification#*:}"

            if [[ "$status" == "success" ]]; then
                echo -e " ${GREEN}✓${NC} $agent_display probe $i: completed ($(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                ((success_count++)) || true
            elif [[ "$status" == "timeout" ]]; then
                echo -e " ${YELLOW}⏳${NC} $agent_display probe $i: timeout with partial results ($(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                ((timeout_count++)) || true
            elif [[ "$status" == "degraded" ]]; then
                echo -e " ${YELLOW}⚠${NC} $agent_display probe $i: partial result (${reason:-degraded}; $(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                ((timeout_count++)) || true
            else
                echo -e " ${RED}✗${NC} $agent_display probe $i: unusable (${reason:-failed}; $(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                ((failure_count++)) || true
            fi
        else
            local agent_display="$(_ucfirst "$agent")"
            echo -e " ${RED}✗${NC} $agent_display probe $i: result file missing"
            ((failure_count++)) || true
        fi
    done

    echo ""
    local usable_results=$((success_count + timeout_count))
    echo -e "${CYAN}Results summary: ${GREEN}$success_count${NC} success, ${YELLOW}$timeout_count${NC} partial, ${RED}$failure_count${NC} failed | Total: $(numfmt --to=iec-i --suffix=B $total_size 2>/dev/null || echo "${total_size}B")${NC}"

    # v8.23.2: Surface per-provider failure summary so users know which providers actually contributed
    if [[ $failure_count -gt 0 ]]; then
        local failed_providers=""
        for i in "${!perspectives[@]}"; do
            local task_id="probe-${task_group}-${i}"
            local agent="${probe_agents[$i]}"
            local result_file="${RESULTS_DIR}/${agent}-${task_id}.md"
            if [[ ! -f "$result_file" ]] || ! probe_result_file_is_usable "$result_file"; then
                failed_providers="${failed_providers:+$failed_providers, }${agent}"
            fi
        done
        if [[ -n "$failed_providers" ]]; then
            echo -e "${YELLOW}⚠  Failed providers: ${failed_providers}${NC}"
            echo -e "${YELLOW}   Results will be synthesized from successful providers only.${NC}"
            echo -e "${YELLOW}   Check logs for details: ${LOGS_DIR}/${NC}"
        fi
    fi
    echo ""

    # v9.37.0: Make provider participation explicit before synthesis so users
    # can tell which LLMs actually contributed and fail-fast if all providers
    # are required.
    if type render_agent_summary >/dev/null 2>&1; then
        local summary_status=0
        render_agent_summary || summary_status=$?
        if [[ "$summary_status" -ne 0 ]]; then
            if [[ -n "$synthesis_monitor_pid" ]]; then
                kill "$synthesis_monitor_pid" 2>/dev/null || true
                wait "$synthesis_monitor_pid" 2>/dev/null || true
                OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID=""
            fi
            _octopus_probe_restore_traps "$probe_previous_int_trap" "$probe_previous_term_trap"
            return "$summary_status"
        fi
    fi

    # v8.48.0: Write synthesis marker before attempting synthesis
    # WHY: The Bash tool's 120s timeout frequently kills the process during
    # the synthesis call (~30-60s) that follows ~60-90s of agent work.
    # This marker lets the user recover by running `synthesize-probe <task_group>`.
    local synthesis_marker="${RESULTS_DIR}/probe-needs-synthesis-${task_group}.marker"
    {
        echo "task_group=${task_group}"
        printf 'prompt=%q\n' "$(printf '%s' "$prompt" | head -c 4096)"
        echo "usable_results=${usable_results}"
        echo "timestamp=$(date -Iseconds)"
    } > "$synthesis_marker"
    log DEBUG "Synthesis marker written: $synthesis_marker"

    # Intelligent synthesis plus cleanup. Keep the call guarded so a nonzero
    # synthesis or summary status survives orchestrate.sh's errexit setting.
    local finalize_status=0
    _octopus_probe_finalize_synthesis "$task_group" "$prompt" "$usable_results" \
        "$synthesis_marker" "$synthesis_monitor_pid" \
        "$probe_previous_int_trap" "$probe_previous_term_trap" \
        || finalize_status=$?
    return "$finalize_status"
}

# Phase 2: GRASP (Define) - Consensus building on approach
# The octopus grasps the core problem with coordinated tentacles
grasp_define() {
    local prompt="$1"
    local probe_results="${2:-}"
    local task_group
    task_group=$(date +%s)

    echo ""
    octopus_phase_banner "DEFINE (Phase 2/4)" "Consensus Building" "$MAGENTA"
    echo ""

    log INFO "Phase 2: Building consensus on problem definition"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would grasp: $prompt"
        log INFO "[DRY-RUN] Would gather 4 perspectives (Codex, Antigravity/agy, Sonnet 5) and build consensus"
        return 0
    fi

    # Cost transparency (v7.18.0 - P0.0)
    if ! display_workflow_cost_estimate "Grasp (Define Phase)" 1 2 1200; then
        log "WARN" "Workflow cancelled by user after cost review"
        return 1
    fi

    if declare -F begin_progress_phase >/dev/null 2>&1; then
        begin_progress_phase "define"
    fi

    mkdir -p "$RESULTS_DIR"

    # Include probe context if available
    local context=""
    if [[ -n "$probe_results" && -f "$probe_results" ]]; then
        context="Previous research findings:\n$(<"$probe_results")\n\n"
        log INFO "Using probe context from: $probe_results"
    fi

    # Multiple agents define the problem from their perspective
    log INFO "Gathering problem definitions from multiple perspectives..."

    local def1 def2="" def3
    def1=$(run_agent_sync "codex" "Based on: $prompt\n${context}Define the core problem statement in 2-3 sentences. What is the essential challenge?" 300 "backend-architect" "grasp") || {
        log WARN "Codex failed for problem definition, falling back to Claude"
        def1=$(run_agent_sync "claude-sonnet" "Based on: $prompt\n${context}Define the core problem statement in 2-3 sentences. What is the essential challenge?" 300 "backend-architect" "grasp") || true
    }
    if octo_provider_allowed agy && command -v agy >/dev/null 2>&1; then
        def2=$(run_agent_sync "agy" "Based on: $prompt\n${context}Define success criteria. How will we know when this is solved correctly? List 3-5 measurable criteria." 300 "researcher" "grasp") || {
            log WARN "Antigravity (agy) dispatch failed for success criteria, falling back to Claude"
            def2=""
        }
    else
        log WARN "Antigravity (agy) unavailable or not allowed, using Claude for success criteria"
    fi
    if [[ -z "$def2" ]]; then
        def2=$(run_agent_sync "claude-sonnet" "Based on: $prompt\n${context}Define success criteria. How will we know when this is solved correctly? List 3-5 measurable criteria." 300 "researcher" "grasp") || true
    fi
    def3=$(run_agent_sync "claude-sonnet" "Based on: $prompt\n${context}Define constraints and boundaries. What are we NOT solving? What are hard limits?" 300 "researcher" "grasp")

    # Build consensus
    local consensus_file="${RESULTS_DIR}/grasp-consensus-${task_group}.md"

    log INFO "Building consensus from perspectives..."

    local consensus_prompt="Review these different problem definitions and create a unified problem statement.
Resolve any conflicts and synthesize the best elements from each.

Problem Statement Perspective:
$def1

Success Criteria Perspective:
$def2

Constraints Perspective:
$def3

Output a single, clear problem definition document with:
1. Problem Statement (2-3 sentences)
2. Success Criteria (bullet points)
3. Constraints & Boundaries
4. Recommended Approach"

    local consensus
    if octo_provider_allowed agy && command -v agy >/dev/null 2>&1; then
        if ! consensus=$(run_agent_sync "agy" "$consensus_prompt" 300 "synthesizer" "grasp") || \
            [[ ! "$consensus" =~ [^[:space:]] ]]; then
            log WARN "Antigravity (agy) returned no usable consensus; preserving source perspectives"
            consensus="[Auto-consensus failed - manual review required]

Problem: $def1

Success Criteria: $def2

Constraints: $def3"
        fi
    else
        log WARN "Antigravity (agy) unavailable or not allowed, skipping automated consensus synthesis"
        consensus="[Auto-consensus skipped - Antigravity (agy) unavailable or not allowed]

Problem: $def1

Success Criteria: $def2

Constraints: $def3"
    fi

    cat > "$consensus_file" << EOF
# GRASP Phase - Problem Definition Consensus
## Task: $prompt
## Generated: $(date)

$consensus

---
*Consensus built from multiple agent perspectives (task group: $task_group)*
EOF

    log INFO "Consensus document: $consensus_file"
    echo ""
    echo -e "${GREEN}✓${NC} Problem definition saved to: $consensus_file"
    echo ""
}

build_tangle_subtask_prompt() {
    local original_task="$1"
    local assigned_subtask="$2"

    if [[ -z "${original_task//[[:space:]]/}" ]]; then
        echo "build_tangle_subtask_prompt: original task is required" >&2
        return 64
    fi
    if [[ -z "${assigned_subtask//[[:space:]]/}" ]]; then
        echo "build_tangle_subtask_prompt: assigned subtask is required" >&2
        return 64
    fi

    local repo_context migration_safety
    repo_context=$(tangle_build_repo_context_block "$assigned_subtask")
    if [[ "${OCTOPUS_TANGLE_ALLOW_DB_APPLY:-false}" == "true" ]]; then
        migration_safety="- External migration application is explicitly authorized for this run. Never rename, delete, or rewrite a migration after any database has applied its version, and prove the applied history still matches the files on disk."
    else
        migration_safety="- Do not apply, push, repair, or mark database migrations on a persistent local, linked, remote, or shared database. Use only the project's disposable reset/test workflow; if verification requires persistent mutation, report a blocker. Never rename, delete, or rewrite a migration after any database has applied its version."
    fi

    cat <<EOF
Original task context:
${original_task}

Assigned subtask:
${assigned_subtask}

${repo_context}

Execution instructions:
- Treat the original task as authoritative for requirements, explicit file targets, acceptance criteria, and forbidden changes.
- Complete the assigned subtask without dropping original constraints that apply to it.
- For [CODING] work, edit the repository files directly in the current worktree. Do not only describe a plan or paste code snippets.
- For [CODING] work, treat file paths/directories named in the assigned subtask as approximate exclusive write scope intent. Use the resolved repository context files above as the concrete targets. Do not edit files clearly owned by another subtask; report a blocker if the required change crosses scopes.
- If the subtask creates a new exported component, command, event type, route, hook, or helper, wire it into at least one production call site unless the original task explicitly asks for an isolated artifact.
- Tests alone are not integration evidence. User-facing features must be reachable from the relevant user flow or the subtask must report a blocker.
Migration safety:
${migration_safety}
- In the final output, include "## Worktree Changes", "## Integration Evidence", and "## Verification" sections.
- If the assigned subtask is incomplete, contradictory, or omits required context, report the blocker instead of inventing scope.
EOF
}

tangle_extract_write_scopes() {
    local text="$1"
    local files_text

    files_text=$(printf '%s\n' "$text" | sed -nE 's/.*Files:[[:space:]]*//p' | head -n 1)
    files_text=$(printf '%s\n' "$files_text" | sed -E 's/[[:space:]]+[—-][[:space:]]+Task:.*$//; s/[[:space:]]+Task:.*$//')
    [[ -n "$files_text" ]] || return 0

    printf '%s\n' "$files_text" \
        | tr ' `",;()[]{}' '\n' \
        | sed -nE '/^([A-Za-z0-9_.@%+-]+(\/[A-Za-z0-9_.@%+\/-]+)?)(\*|\/)?(:[0-9]+)?$/p' \
        | sed -E 's/:([0-9]+)$//; s/[[:punct:]]+$//' \
        | sed -E 's#^\./##; s#/\*$#/#; s#//+#/#g' \
        | sed '/^$/d' \
        | sort -u
}

tangle_scope_is_directory() {
    local scope="$1"
    local base
    [[ "$scope" == */ ]] && return 0
    [[ "$scope" == *"*"* ]] && return 0
    base="${scope##*/}"
    [[ "$base" != *.* ]]
}

tangle_scopes_overlap() {
    local left="${1%/}"
    local right="${2%/}"
    [[ -z "$left" || -z "$right" ]] && return 1
    [[ "$left" == "$right" ]] && return 0

    if tangle_scope_is_directory "$1" && [[ "$right" == "$left"/* ]]; then
        return 0
    fi
    if tangle_scope_is_directory "$2" && [[ "$left" == "$right"/* ]]; then
        return 0
    fi

    return 1
}

tangle_resolve_repo_root() {
    local repo_root
    local resolved_root

    if [[ -n "${PROJECT_ROOT:-}" ]]; then
        if [[ -d "$PROJECT_ROOT" ]]; then
            resolved_root=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)
            if [[ -z "$resolved_root" ]]; then
                printf '%s\n' "$PROJECT_ROOT"
                return 0
            fi
            printf '%s\n' "$resolved_root"
            return 0
        fi
        repo_root="$(pwd)"
    else
        repo_root="$(pwd)"
    fi

    resolved_root=$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null || true)
    [[ -n "$resolved_root" ]] || return 1
    printf '%s\n' "$resolved_root"
}

tangle_resolve_repo_context_files() {
    local text="$1"
    local max_files="${OCTOPUS_TANGLE_CONTEXT_MAX_FILES:-16}"
    [[ "$max_files" =~ ^[0-9]+$ ]] || max_files=16

    local repo_root
    repo_root=$(tangle_resolve_repo_root) || return 0
    git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1 || return 0

    local files=()
    local token full basename

    # Keep concrete existing files explicitly named by the decomposition.
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        token="${token#./}"
        if [[ -f "$repo_root/$token" ]]; then
            files+=("$token")
        else
            basename="${token##*/}"
            if [[ "$basename" == *.* ]]; then
                while IFS= read -r full; do
                    [[ -n "$full" ]] && files+=("$full")
                done < <(git -C "$repo_root" ls-files | awk -v b="$basename" 'BEGIN{n=0} {split($0,a,"/"); if (a[length(a)]==b && n<4) {print; n++}}')
            fi
        fi
    done < <(printf '%s\n' "$text" | grep -Eo '[A-Za-z0-9_./-]+\.(js|ts|json|md|yml|yaml|toml|py|sh)' | sort -u)

    # Add high-signal files by endpoint/domain terms.
    local lower
    lower=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower" == *"runterminalscript"* || "$lower" == *"commands/execute"* || "$lower" == *"script mode"* || "$lower" == *"bounded executor"* ]]; then
        for full in api/terminal.js serverModules/apiRoutes.js serverModules/swaggerSetup.js api/activityLog.js package.json README.md SETUP.md; do
            [[ -f "$repo_root/$full" ]] && files+=("$full")
        done
    fi
    if [[ "$lower" == *"openapi"* || "$lower" == *"schema"* || "$lower" == *"readme"* || "$lower" == *"setup"* || "$lower" == *"documentation"* ]]; then
        for full in serverModules/swaggerSetup.js README.md SETUP.md package.json; do
            [[ -f "$repo_root/$full" ]] && files+=("$full")
        done
    fi
    if [[ "$lower" == *"test"* || "$lower" == *"acceptance"* || "$lower" == *"smoke"* ]]; then
        for full in package.json README.md SETUP.md; do
            [[ -f "$repo_root/$full" ]] && files+=("$full")
        done
    fi

    # Fallback: use grep over tracked text files for rare domain tokens.
    if [[ ${#files[@]} -lt 3 ]]; then
        for token in runterminalscript commands execute terminal swagger activity bounded timeout; do
            if [[ "$lower" == *"$token"* ]]; then
                while IFS= read -r full; do
                    [[ -n "$full" ]] && files+=("$full")
                done < <(git -C "$repo_root" grep -Il -m1 "$token" -- '*.js' '*.json' '*.md' 2>/dev/null | head -n 6)
            fi
        done
    fi

    [[ ${#files[@]} -gt 0 ]] || return 0
    printf '%s\n' "${files[@]}" | sed '/^$/d' | awk '!seen[$0]++' | sed -n "1,${max_files}p"
}

tangle_build_repo_context_block() {
    local assigned_subtask="$1"
    local repo_root
    repo_root=$(tangle_resolve_repo_root) || return 0
    local resolved
    resolved=$(tangle_resolve_repo_context_files "$assigned_subtask")
    cat <<EOF
Repository context for this subtask:
- The worktree is the source of truth. Do not invent repository layout from generic names.
- Treat the decomposer's Files clause as approximate intent. Prefer the resolved files below when they conflict with invented paths.
- If none of the resolved files fit, inspect the tracked file list and report the blocker.

Tracked files, first 200:
$(git -C "$repo_root" ls-files 2>/dev/null | sed -n '1,200p')

Resolved relevant files to inspect/edit for this subtask:
${resolved:-<none resolved>}
EOF
}

tangle_scope_is_safe_relative_path() {
    local scope="$1"
    local normalized="${scope#./}"
    normalized="${normalized%/}"

    # Reject scopes that are empty once trimmed, not merely empty: a
    # whitespace-only scope is non-empty here but names nothing.
    [[ -n "${normalized//[[:space:]]/}" ]] || return 1
    case "$normalized" in
        /*|.|..|*\\*|*'*'*|*'?'*|*'['*|*']'*) return 1 ;;
    esac
    # Compare the .git check case-insensitively. macOS APFS/HFS+ is
    # case-insensitive by default and is this project's primary platform, so a
    # literal `.git` match let `.GIT/hooks/pre-commit` through — which resolves
    # to the real hook and is arbitrary code execution on the next commit.
    # Verified in a scratch repo: `mkdir -p .GIT/hooks && echo x > .GIT/hooks/p`
    # creates `.git/hooks/p`.
    local lower
    lower=$(printf '%s' "$normalized" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        .git|.git/*) return 1 ;;
    esac
    case "/$normalized/" in
        */../*|*/./*) return 1 ;;
    esac
    return 0
}

tangle_scope_has_existing_repo_ancestor() {
    local repo_root="$1"
    local normalized="$2"
    local probe="$normalized"

    while [[ "$probe" == */* ]]; do
        probe="${probe%/*}"
        [[ -n "$probe" ]] || break
        if [[ -d "$repo_root/$probe" || -f "$repo_root/$probe" ]]; then
            return 0
        fi
        if git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1; then
            if [[ -n "$(git -C "$repo_root" ls-files "$probe/" 2>/dev/null || true)" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

tangle_scope_is_known_or_explicit_new_file() {
    local scope="$1"
    local normalized="${scope#./}"
    normalized="${normalized%/}"
    tangle_scope_is_safe_relative_path "$scope" || return 1

    local repo_root
    if ! repo_root=$(tangle_resolve_repo_root 2>/dev/null); then
        if [[ -n "${PROJECT_ROOT:-}" && -d "$PROJECT_ROOT" ]]; then
            repo_root="$PROJECT_ROOT"
        else
            repo_root=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || pwd)
        fi
    fi

    if git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1; then
        if git -C "$repo_root" ls-files --error-unmatch "$normalized" >/dev/null 2>&1; then
            return 0
        fi
        if [[ -n "$(git -C "$repo_root" ls-files "$normalized/" 2>/dev/null || true)" ]]; then
            return 0
        fi
    fi

    [[ -e "$repo_root/$normalized" ]] && return 0

    # Explicit new files or directories are valid when anchored below an
    # existing repository path. Preserve the declared scope instead of
    # replacing it with heuristic context-file inference.
    tangle_scope_has_existing_repo_ancestor "$repo_root" "$normalized"
}


tangle_line_is_numbered_subtask() {
    local line="$1"
    local numbered_subtask_pattern='^[[:space:]]*(\*\*)?[0-9]+[.)]'
    if [[ "$line" =~ $numbered_subtask_pattern ]]; then
        return 0
    fi
    return 1
}

tangle_parseable_subtask_count() {
    local subtasks="$1"
    local count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        tangle_line_is_numbered_subtask "$line" && ((count++)) || true
    done <<< "$subtasks"
    echo "$count"
}

tangle_parseable_coding_subtask_count() {
    local subtasks="$1"
    local count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        tangle_line_is_numbered_subtask "$line" || continue
        [[ "$line" =~ \[CODING\] ]] && ((count++)) || true
    done <<< "$subtasks"
    echo "$count"
}

tangle_reformat_decomposition() {
    local original_task="$1"
    local previous_decomposition="$2"
    local reason="${3:-not parseable}"
    local repo_file_map="${4:-}"
    local reformat_prompt="Reformat the previous Octopus task decomposition. Do not add analysis.

Required output format, exactly one subtask per line:
1. [CODING] Short title — Files: relative/file.js, another/file.js — Task: specific coding work
2. [REASONING] Short title — Task: specific reasoning/review work

Rules:
- Output only numbered lines. No Markdown headings, no code fences, no prose before or after.
- Every [CODING] line must include a same-line 'Files:' clause.
- Use relative file or directory scopes from the repository file map when possible.
- Prefer concrete paths from the repository file map; invented/generic paths will be resolved against the actual worktree before dispatch.
- New files should be explicit filenames whose parent directory already exists, or root-level files; avoid creating new source trees unless explicitly required.
- Coding write scopes must be disjoint. If scopes overlap, merge those items into one [CODING] line.
- If all coding work touches the same files, output one [CODING] line with those files rather than pretending it can be parallelized.
- Keep 1-6 total subtasks.

${repo_file_map}

Original task:
${original_task}

Previous decomposition failed validation because: ${reason}

Previous decomposition:
${previous_decomposition}
"

    local tangle_decompose_agent="agy" tangle_decompose_fallback_agent="codex"
    if declare -f octopus_agent_override >/dev/null 2>&1; then
        tangle_decompose_agent=$(octopus_execution_profile_provider "tangle" "decompose" "researcher" "agy")
        tangle_decompose_fallback_agent=$(octopus_execution_profile_provider "tangle" "decompose_fallback" "implementer" "codex")
    fi

    OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="tangle-reformat-validation" run_agent_sync "$tangle_decompose_agent" "$reformat_prompt" 0 "researcher" "tangle" || \
    OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="tangle-reformat-validation" run_agent_sync "$tangle_decompose_fallback_agent" "$reformat_prompt" 0 "researcher" "tangle"
}

tangle_validate_parallel_write_scopes() {
    local subtasks="$1"
    local task_index=0
    local coding_count=0
    local existing_scopes=()
    local existing_tasks=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        tangle_line_is_numbered_subtask "$line" || continue

        local subtask
        subtask=$(echo "$line" | sed -E 's/^[[:space:]]*(\*\*)?[0-9]+[\.\)][[:space:]]*//; s/^[[:space:]]+//')
        ((task_index++)) || true

        if [[ "$subtask" =~ \[REASONING\] ]]; then
            continue
        fi

        ((coding_count++)) || true
        subtask=$(echo "$subtask" | sed 's/\[CODING\]\s*//; s/\[REASONING\]\s*//')

        local scopes
        scopes=$(tangle_extract_write_scopes "$subtask")
        if [[ -z "$scopes" ]]; then
            echo "coding subtask ${task_index} has no explicit file or directory write scope"
            return 1
        fi

        local effective_scopes=""
        while IFS= read -r scope; do
            [[ -z "$scope" ]] && continue
            if tangle_scope_is_known_or_explicit_new_file "$scope"; then
                effective_scopes="${effective_scopes}${scope}
"
            else
                local resolved_scopes
                resolved_scopes=$(tangle_resolve_repo_context_files "$subtask")
                if [[ -n "$resolved_scopes" ]]; then
                    effective_scopes="${effective_scopes}${resolved_scopes}
"
                else
                    effective_scopes="${effective_scopes}${scope}
"
                fi
            fi
        done <<< "$scopes"
        effective_scopes=$(printf '%s
' "$effective_scopes" | sed '/^$/d' | sort -u)

        while IFS= read -r scope; do
            [[ -z "$scope" ]] && continue
            local i
            for i in "${!existing_scopes[@]}"; do
                [[ "${existing_tasks[$i]}" == "$task_index" ]] && continue
                if tangle_scopes_overlap "$scope" "${existing_scopes[$i]}"; then
                    echo "coding subtask ${task_index} effective write scope '${scope}' overlaps subtask ${existing_tasks[$i]} scope '${existing_scopes[$i]}'"
                    return 1
                fi
            done
            existing_scopes+=("$scope")
            existing_tasks+=("$task_index")
        done <<< "$effective_scopes"
    done <<< "$subtasks"

    [[ $coding_count -eq 0 ]] && return 0
    return 0
}


tangle_consolidate_overlapping_subtasks() {
    local subtasks="$1"
    local lines=()
    local coding_lines=()
    local coding_scopes=()
    local parent=()
    local line

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        tangle_line_is_numbered_subtask "$line" || continue
        lines+=("$line")
        if [[ "$line" =~ \[CODING\] ]]; then
            local subtask scopes effective_scopes=""
            subtask=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*(\*\*)?[0-9]+[\.\)][[:space:]]*//; s/^[[:space:]]+//')
            scopes=$(tangle_extract_write_scopes "$subtask")
            while IFS= read -r scope; do
                [[ -z "$scope" ]] && continue
                if tangle_scope_is_known_or_explicit_new_file "$scope"; then
                    effective_scopes="${effective_scopes}${scope}"$'\n'
                else
                    local resolved_scopes
                    resolved_scopes=$(tangle_resolve_repo_context_files "$subtask")
                    if [[ -n "$resolved_scopes" ]]; then
                        effective_scopes="${effective_scopes}${resolved_scopes}"$'\n'
                    else
                        effective_scopes="${effective_scopes}${scope}"$'\n'
                    fi
                fi
            done <<< "$scopes"
            effective_scopes=$(printf '%s\n' "$effective_scopes" | sed '/^$/d' | sort -u)
            coding_lines+=("$line")
            coding_scopes+=("$effective_scopes")
            parent+=("$((${#parent[@]}))")
        fi
    done <<< "$subtasks"

    local coding_count=${#coding_lines[@]}
    [[ $coding_count -gt 1 ]] || { printf '%s\n' "$subtasks"; return 0; }

    local i j left right root_i root_j
    for ((i=0; i<coding_count; i++)); do
        for ((j=i+1; j<coding_count; j++)); do
            local overlaps=false
            while IFS= read -r left; do
                [[ -z "$left" ]] && continue
                while IFS= read -r right; do
                    [[ -z "$right" ]] && continue
                    if tangle_scopes_overlap "$left" "$right"; then
                        overlaps=true
                        break
                    fi
                done <<< "${coding_scopes[$j]}"
                [[ "$overlaps" == true ]] && break
            done <<< "${coding_scopes[$i]}"
            if [[ "$overlaps" == true ]]; then
                root_i=$i
                while [[ ${parent[$root_i]} -ne $root_i ]]; do root_i=${parent[$root_i]}; done
                root_j=$j
                while [[ ${parent[$root_j]} -ne $root_j ]]; do root_j=${parent[$root_j]}; done
                [[ $root_i -eq $root_j ]] || parent[$root_j]=$root_i
            fi
        done
    done

    for ((i=0; i<coding_count; i++)); do
        root_i=$i
        while [[ ${parent[$root_i]} -ne $root_i ]]; do root_i=${parent[$root_i]}; done
        parent[$i]=$root_i
    done

    local output="" output_index=0 coding_index=0 current_position
    for ((current_position=0; current_position<${#lines[@]}; current_position++)); do
        line=${lines[$current_position]}
        if [[ ! "$line" =~ \[CODING\] ]]; then
            ((output_index++)) || true
            local reasoning_body
            reasoning_body=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*(\*\*)?[0-9]+[\.\)][[:space:]]*//')
            output="${output}${output_index}. ${reasoning_body}"$'\n'
            continue
        fi

        root_i=${parent[$coding_index]}
        if [[ $root_i -ne $coding_index ]]; then
            ((coding_index++)) || true
            continue
        fi

        local member_count=0 merged_scopes="" merged_tasks="" member
        for ((member=0; member<coding_count; member++)); do
            [[ ${parent[$member]} -eq $root_i ]] || continue
            ((member_count++)) || true
            merged_scopes="${merged_scopes}${coding_scopes[$member]}"$'\n'
            local task_text
            task_text=$(printf '%s\n' "${coding_lines[$member]}" | sed -nE 's/.*[[:space:]]Task:[[:space:]]*//p')
            if [[ -z "$task_text" ]]; then
                task_text=$(printf '%s\n' "${coding_lines[$member]}" | sed -E 's/^[[:space:]]*(\*\*)?[0-9]+[\.\)][[:space:]]*//; s/[[:space:]]+[—-][[:space:]]+Files:.*$//')
            fi
            [[ -z "$merged_tasks" ]] || merged_tasks="${merged_tasks}; "
            merged_tasks="${merged_tasks}${task_text}"
        done

        ((output_index++)) || true
        if [[ $member_count -eq 1 ]]; then
            local coding_body
            coding_body=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*(\*\*)?[0-9]+[\.\)][[:space:]]*//')
            output="${output}${output_index}. ${coding_body}"$'\n'
        else
            local scopes_csv
            scopes_csv=$(printf '%s\n' "$merged_scopes" | sed '/^$/d' | sort -u | awk 'BEGIN { first=1 } { if (!first) printf ", "; printf "%s", $0; first=0 } END { print "" }')
            output="${output}${output_index}. [CODING] Consolidated parallel-safe scope — Files: ${scopes_csv} — Task: ${merged_tasks}"$'\n'
        fi
        ((coding_index++)) || true
    done

    printf '%s' "$output"
}


octo_bool_disabled() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        0|false|off|no|disabled) return 0 ;;
        *) return 1 ;;
    esac
}

octo_bool_enabled() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|on|yes|enabled) return 0 ;;
        *) return 1 ;;
    esac
}

tangle_review_warning_text() {
    local findings_file="$1"
    [[ -f "$findings_file" ]] || return 0
    jq -r '(.warning // (if ((.message // "") | test("No changes found to review"; "i")) then .message else "" end)) // ""' "$findings_file" 2>/dev/null || true
}

tangle_review_blocking_count() {
    local findings_file="$1"
    [[ -f "$findings_file" ]] || { echo 0; return 0; }
    local review_warning
    review_warning=$(tangle_review_warning_text "$findings_file")
    if [[ -n "$review_warning" ]]; then
        echo 1
        return 0
    fi
    local count
    if ! count=$(jq '[.findings[]? | select((.severity // "") == "normal")] | length' "$findings_file" 2>/dev/null); then
        # fail closed: malformed/truncated findings must block delivery.
        echo 1
        return 0
    fi
    echo "$count"
}

tangle_review_findings_summary() {
    local findings_file="$1"
    [[ -f "$findings_file" ]] || return 0
    jq -r '.findings[]? | "- [" + (.severity // "unknown") + "] " + (.title // "untitled") + " — " + (.file // "unknown") + ":" + ((.line // 0)|tostring) + "\n  " + (.detail // "")' "$findings_file" 2>/dev/null || true
}

tangle_normal_findings_summary() {
    local findings_file="$1"
    [[ -f "$findings_file" ]] || return 0
    jq -r '.findings[]? | select((.severity // "") == "normal") | "### " + (.title // "untitled") + "\n- Location: " + (.file // "unknown") + ":" + ((.line // 0)|tostring) + "\n- Confidence: " + ((.confidence // 0)|tostring) + "\n\n" + (.detail // "") + "\n"' "$findings_file" 2>/dev/null || true
}

tangle_findings_signature() {
    local findings_file="$1"
    [[ -f "$findings_file" ]] || { echo "missing"; return 0; }
    jq -r '[.findings[]? | select((.severity // "") == "normal") | (.title // .message // "untitled")] | sort | join(" | ")' "$findings_file" 2>/dev/null || echo "unparseable"
}

# Stable blocker identities for convergence tracking. File + normalized title is
# intentionally stronger than count-only progress while remaining resilient to
# line movement and detail/confidence rewrites between review rounds.
tangle_normal_finding_keys() {
    local findings_file="$1"
    [[ -f "$findings_file" ]] || return 0
    jq -r '''
        .findings[]?
        | select((.severity // "") == "normal")
        | [
            (.file // "unknown"),
            ((.title // .message // "untitled")
              | ascii_downcase
              | gsub("[[:space:]]+"; " ")
              | sub("^ "; "")
              | sub(" $"; ""))
          ]
        | @json
    ''' "$findings_file" 2>/dev/null | sort -u || true
}

tangle_resolved_finding_count() {
    local previous_keys="$1"
    local current_keys="$2"
    comm -23         <(printf '%s\n' "$previous_keys" | sed '/^$/d' | sort -u)         <(printf '%s\n' "$current_keys" | sed '/^$/d' | sort -u)         | awk 'NF { n++ } END { print n + 0 }'
}

# Fingerprint only the actionable validation-gate decision. This lets the
# correction loop distinguish useful validation movement from a static gate that
# is being recomputed from immutable initial subtask result files.
tangle_validation_signature() {
    local validation_file="$1"
    [[ -f "$validation_file" ]] || { echo "missing"; return 0; }
    awk '
        /^### Quality Gate:/ { capture=1 }
        /^### Subtask Results/ { capture=0 }
        capture { print }
    ' "$validation_file" 2>/dev/null | sha256sum | awk '{print $1}'
}

tangle_worktree_fingerprint() {
    local repo_root
    repo_root=$(tangle_resolve_repo_root 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null || pwd)
    {
        git -C "$repo_root" status --porcelain 2>/dev/null || true
        git -C "$repo_root" diff --stat 2>/dev/null || true
        git -C "$repo_root" ls-files --others --exclude-standard 2>/dev/null || true
    } | sha256sum 2>/dev/null | awk '{print $1}'
}

tangle_process_is_active_non_zombie() {
    local pid="${1:-}"
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    local stat
    stat=$(ps -o stat= -p "$pid" 2>/dev/null | awk 'NR==1 {print $1}') || stat=""
    [[ -n "$stat" ]] || return 1
    [[ "$stat" == Z* ]] && return 1
    return 0
}

# Active Tangle state is process-global because INT/TERM can arrive while the
# controller is blocked in spawn PID capture or the completion watcher.
OCTOPUS_ACTIVE_TANGLE_TASK_GROUP=""
OCTOPUS_ACTIVE_TANGLE_TMUX="false"
OCTOPUS_ACTIVE_TANGLE_PIDS=()
OCTOPUS_ACTIVE_TANGLE_AGENTS=()
OCTOPUS_ACTIVE_TANGLE_TASK_IDS=()

octopus_tangle_clear_active() {
    OCTOPUS_ACTIVE_TANGLE_TASK_GROUP=""
    OCTOPUS_ACTIVE_TANGLE_TMUX="false"
    OCTOPUS_ACTIVE_TANGLE_PIDS=()
    OCTOPUS_ACTIVE_TANGLE_AGENTS=()
    OCTOPUS_ACTIVE_TANGLE_TASK_IDS=()
}

_octopus_tangle_restore_traps() {
    local previous_int_trap="${1:-}"
    local previous_term_trap="${2:-}"

    octopus_tangle_clear_active
    if [[ -n "$previous_int_trap" ]]; then eval "$previous_int_trap"; else trap - INT; fi
    if [[ -n "$previous_term_trap" ]]; then eval "$previous_term_trap"; else trap - TERM; fi
}

_octopus_tangle_prune_pid_ledger_unlocked() {
    local task_group="$1"
    [[ -n "${PID_FILE:-}" && -f "$PID_FILE" ]] || return 0
    local tmp_file
    tmp_file=$(mktemp "${PID_FILE}.cancel.XXXXXX") || return 1
    if awk -F: -v prefix="tangle-${task_group}-" \
        'index($3, prefix) != 1 { print }' "$PID_FILE" > "$tmp_file"; then
        mv -f "$tmp_file" "$PID_FILE"
    else
        rm -f "$tmp_file" 2>/dev/null || true
    fi
}

_octopus_tangle_prune_pid_ledger() {
    local task_group="$1"
    [[ -n "${PID_FILE:-}" && -f "$PID_FILE" ]] || return 0
    if command -v flock >/dev/null 2>&1; then
        (
            flock -x 200 || exit $?
            _octopus_tangle_prune_pid_ledger_unlocked "$task_group"
        ) 200>"${PID_FILE}.lock"
    else
        _octopus_tangle_prune_pid_ledger_unlocked "$task_group"
    fi
}

octopus_tangle_cancel_active() {
    local signal_name="${1:-TERM}"
    local task_group="${OCTOPUS_ACTIVE_TANGLE_TASK_GROUP:-}"
    [[ -n "$task_group" ]] || return 0
    if ! declare -F review_kill_process_tree_frozen >/dev/null 2>&1 \
       || ! declare -F review_kill_descendants_frozen >/dev/null 2>&1; then
        log ERROR "Tangle cancellation helpers are unavailable; refusing incomplete cleanup"
        return 1
    fi

    local exit_code=143
    [[ "$signal_name" == "INT" ]] && exit_code=130
    local -a cancel_pids=("${OCTOPUS_ACTIVE_TANGLE_PIDS[@]+"${OCTOPUS_ACTIVE_TANGLE_PIDS[@]}"}")
    local -a cancel_agents=("${OCTOPUS_ACTIVE_TANGLE_AGENTS[@]+"${OCTOPUS_ACTIVE_TANGLE_AGENTS[@]}"}")
    local -a cancel_tasks=("${OCTOPUS_ACTIVE_TANGLE_TASK_IDS[@]+"${OCTOPUS_ACTIVE_TANGLE_TASK_IDS[@]}"}")
    local ledger_pid ledger_agent ledger_task idx found found_idx

    # The ledger closes the race between spawn_agent's append and the caller's
    # assignment of the returned PID into the active in-memory arrays.
    if [[ -n "${PID_FILE:-}" && -f "$PID_FILE" ]]; then
        while IFS=: read -r ledger_pid ledger_agent ledger_task; do
            [[ "$ledger_task" == "tangle-${task_group}-"* ]] || continue
            found=false
            found_idx=""
            for idx in "${!cancel_tasks[@]}"; do
                if [[ "${cancel_tasks[$idx]:-}" == "$ledger_task" ]]; then
                    found=true
                    found_idx="$idx"
                    break
                fi
            done
            if [[ "$found" == "true" ]]; then
                [[ -n "${cancel_pids[$found_idx]:-}" ]] || cancel_pids[$found_idx]="$ledger_pid"
                [[ -n "${cancel_agents[$found_idx]:-}" ]] || cancel_agents[$found_idx]="$ledger_agent"
            else
                cancel_pids+=("$ledger_pid")
                cancel_agents+=("$ledger_agent")
                cancel_tasks+=("$ledger_task")
            fi
        done < "$PID_FILE"
    fi

    local pid agent task_id result_file done_dir done_file
    done_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents"
    mkdir -p "$done_dir" 2>/dev/null || true
    for idx in "${!cancel_tasks[@]}"; do
        pid="${cancel_pids[$idx]:-}"
        agent="${cancel_agents[$idx]:-unknown}"
        task_id="${cancel_tasks[$idx]:-tangle-${task_group}-${idx}}"
        result_file="${RESULTS_DIR:-}/$agent-$task_id.md"
        done_file="$done_dir/${task_id}.done"

        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            review_kill_process_tree_frozen "$pid"
            wait "$pid" 2>/dev/null || true
            rm -f "$done_dir/${pid}.heartbeat" 2>/dev/null || true
        fi
        [[ -f "$done_file" ]] || printf '%s\n' "cancelled" > "$done_file" 2>/dev/null || true
        if [[ -f "$result_file" ]] \
           && ! grep -Ec '^## Status: (SUCCESS|FAILED|TIMEOUT|CANCELLED)' "$result_file" >/dev/null 2>&1; then
            {
                echo ""
                echo "## Status: CANCELLED - PARTIAL RESULTS"
                echo ""
                echo "Tangle interrupted by SIG${signal_name}; partial output above was preserved."
            } >> "$result_file"
        fi
        if declare -F _octopus_agent_lifecycle_event >/dev/null 2>&1; then
            _octopus_agent_lifecycle_event "cancelled" "$agent" "$task_id" \
                "implementer" "tangle" "$pid" "$result_file" "$exit_code" "cancelled"
        fi
    done

    # A signal can arrive after the provider process exists but before the spawn
    # helper appends it to the PID ledger. The active orchestrator owns all of
    # its direct descendants, so sweep any unregistered child trees as the final
    # race-closing step before clearing lifecycle state.
    review_kill_descendants_frozen "$$"

    _octopus_tangle_prune_pid_ledger "$task_group" \
        || log ERROR "Failed to prune cancelled Tangle tasks from the PID ledger"
    if [[ "${OCTOPUS_ACTIVE_TANGLE_TMUX:-false}" == "true" ]] \
       && declare -F tmux_cleanup >/dev/null 2>&1; then
        tmux_cleanup 2>/dev/null || true
    fi
    declare -F fleet_dispatch_end >/dev/null 2>&1 && fleet_dispatch_end
    octopus_tangle_clear_active
}

octopus_tangle_handle_signal() {
    local signal_name="${1:-TERM}"
    local exit_code=143
    [[ "$signal_name" == "INT" ]] && exit_code=130
    trap - INT TERM
    octopus_tangle_cancel_active "$signal_name"
    exit "$exit_code"
}

tangle_scope_contamination_summary() {
    local repo_root
    repo_root=$(tangle_resolve_repo_root 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null || pwd)
    git -C "$repo_root" status --porcelain 2>/dev/null \
        | awk '{print $2}' \
        | grep -E '(^|/)(_wr\.py|.*\.bak$|.*_new\.[^.]+$|.*_p[0-9]+\.[^.]+$|.*\.tmp$|.*\.orig$)' \
        || true
}

tangle_correction_strategy_prompt() {
    local strategy="${1:-delta}"
    case "$strategy" in
        cleanup-and-fix)
            cat <<'EOF'
Strategy for this round:
- First remove or reverse out-of-scope scratch/backup files created by earlier attempts.
- Then fix the smallest set of blocking findings possible.
- Do not create backup, scratch, _new, _pN, .tmp, .orig, or helper files.
EOF
            ;;
        single-finding)
            cat <<'EOF'
Strategy for this round:
- Do not attempt to fix all findings at once.
- Pick the highest-impact blocking finding and fix that one cleanly.
- If tests or OpenAPI are the selected blocker, add only the required files/scripts.
- Do not create backup, scratch, _new, _pN, .tmp, .orig, or helper files.
EOF
            ;;
        *)
            cat <<'EOF'
Strategy for this round:
- Apply a minimal delta patch that reduces the current blocking findings.
- Prefer small, path-scoped edits over rewrites.
- Do not create backup, scratch, _new, _pN, .tmp, .orig, or helper files.
EOF
            ;;
    esac
}

TANGLE_CORRECTION_FILE=""
TANGLE_CORRECTION_STATUS=""
TANGLE_CORRECTION_CHANGED="0"
TANGLE_CORRECTION_CONTAMINATION=""

tangle_build_develop_review_context() {
    local task_group="$1"
    local resolved_prompt="$2"
    local grasp_context="$3"
    local subtasks="$4"
    local validation_file="$5"
    local worktree_before_file="$6"
    local round_label="${7:-initial}"
    local repo_root repo_root_physical octopus_dir context_dir context_dir_physical
    local context_name context_file relative_context_path context_tmp relative_context_tmp
    local final_context_dir
    if [[ -z "$task_group" || "$task_group" == "." || "$task_group" == ".." ||
          "$task_group" == *[![:alnum:]_.-]* || "$task_group" == *..* ||
          -z "$round_label" || "$round_label" == "." || "$round_label" == ".." ||
          "$round_label" == *[![:alnum:]_.-]* || "$round_label" == *..* ]]; then
        log "ERROR" "tangle review context labels contain unsafe path characters"
        return 1
    fi
    repo_root=$(tangle_resolve_repo_root 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null || pwd)
    octopus_dir="${repo_root}/.claude-octopus"
    context_dir="${repo_root}/.claude-octopus/results"
    if [[ -L "$octopus_dir" || -L "$context_dir" ]]; then
        log "ERROR" "tangle review context directory must not be a symlink: $context_dir"
        return 1
    fi
    mkdir -p "$context_dir" || return 1
    if [[ -L "$octopus_dir" || -L "$context_dir" ]]; then
        log "ERROR" "tangle review context directory became a symlink: $context_dir"
        return 1
    fi
    repo_root_physical=$(cd "$repo_root" 2>/dev/null && pwd -P) || return 1
    context_dir_physical=$(cd "$context_dir" 2>/dev/null && pwd -P) || return 1
    if [[ "$context_dir_physical" != "${repo_root_physical}/.claude-octopus/results" ]]; then
        log "ERROR" "tangle review context directory escapes repository root: $context_dir_physical"
        return 1
    fi
    context_name="develop-review-context-${task_group}-${round_label}.md"
    context_file="${context_dir_physical}/${context_name}"
    relative_context_path=".claude-octopus/results/${context_name}"
    context_tmp=".develop-review-context.$$.$RANDOM.$RANDOM"
    relative_context_tmp=".claude-octopus/results/${context_tmp}"

    # Enter the already-validated physical directory before creating anything.
    # Relative operations then remain anchored to that directory inode even if
    # another process swaps the parent pathname for a symlink.
    if ! (
        cd "$context_dir" || exit 1
        [[ "$(pwd -P)" == "$context_dir_physical" ]] || exit 1

        if [[ -L "$context_name" || -L ".gitignore" || -e "$context_tmp" || -L "$context_tmp" ]]; then
            log "ERROR" "tangle review results contain an unsafe symlink"
            exit 1
        fi

        # Keep tool-owned artifacts invisible to git without modifying an
        # existing repository-managed ignore file. If one exists, it must
        # already ignore both the final artifact and its scratch file or
        # generation fails before either file is created.
        if [[ ! -e ".gitignore" ]]; then
            if ! (set -o noclobber; printf '*\n' > ".gitignore") 2>/dev/null &&
               [[ ! -f ".gitignore" ]]; then
                exit 1
            fi
        fi
        if [[ -L ".gitignore" ]] ||
           { git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1 &&
             { ! git -C "$repo_root" check-ignore -q -- "$relative_context_path" ||
               ! git -C "$repo_root" check-ignore -q -- "$relative_context_tmp"; }; }; then
            log "ERROR" "repository ignore rules do not cover tangle review context artifacts"
            exit 1
        fi

        # The scratch name is checked against repository ignore rules before
        # noclobber creates it, so interruption cannot leave an untracked file.
        if ! (set -o noclobber
        {
        echo "# Develop Review Context"
        echo
        echo "## Purpose"
        echo "Review the current working-tree diff against the original task contract, grasp/define context, tangle decomposition, and validation evidence."
        echo
        echo "## Review round"
        echo "$round_label"
        echo
        echo "## Repository"
        echo '```text'
        echo "$repo_root"
        echo '```'
        echo
        echo "## Git status"
        echo '```text'
        git -C "$repo_root" status --short --branch 2>/dev/null || true
        echo '```'
        echo
        echo "## Changed files"
        echo '```text'
        {
            git -C "$repo_root" diff --name-status 2>/dev/null || true
            git -C "$repo_root" ls-files --others --exclude-standard 2>/dev/null | sed 's/^/??\t/' || true
        } | sort -u
        echo '```'
        echo
        echo "## Worktree diff stat"
        echo '```text'
        git -C "$repo_root" diff --stat 2>/dev/null || true
        echo '```'
        echo
        if [[ -f "$worktree_before_file" ]]; then
            echo "## Worktree snapshot before tangle"
            echo '```text'
            sed -n '1,200p' "$worktree_before_file" 2>/dev/null || true
            echo '```'
            echo
        fi
        echo "## Original task / task contract"
        echo '```markdown'
        printf '%s\n' "$resolved_prompt"
        echo '```'
        echo
        if [[ -n "$grasp_context" ]]; then
            echo "## Grasp / define context"
            echo '```markdown'
            printf '%s\n' "$grasp_context"
            echo '```'
            echo
        fi
        echo "## Tangle decomposition"
        echo '```text'
        printf '%s\n' "$subtasks"
        echo '```'
        echo
        if [[ -f "$validation_file" ]]; then
            echo "## Tangle validation report excerpt"
            echo '```markdown'
            sed -n '1,260p' "$validation_file" 2>/dev/null || true
            echo '```'
            echo
            echo "## Tangle validation key lines"
            echo '```text'
            grep -n "Quality Gate\|Success Rate\|Failed\|Decision Branch\|Worktree Change Evidence\|Missing\|Status:" "$validation_file" 2>/dev/null | head -120 || true
            echo '```'
        fi
        } > "$context_tmp"
        ); then
            rm -f "$context_tmp"
            exit 1
        fi

        if [[ -L "$context_name" || "$(pwd -P)" != "$context_dir_physical" ]] ||
           ! mv -f "$context_tmp" "$context_name"; then
            rm -f "$context_tmp"
            log "ERROR" "unable to finalize workspace-local tangle review context"
            exit 1
        fi
    ); then
        return 1
    fi

    if [[ -L "$context_file" || ! -f "$context_file" ]]; then
        log "ERROR" "workspace-local tangle review context is unavailable"
        return 1
    fi
    final_context_dir=$(cd "$(dirname "$context_file")" 2>/dev/null && pwd -P) || return 1
    if [[ "$final_context_dir" != "$context_dir_physical" ]]; then
        log "ERROR" "workspace-local tangle review context escaped after generation"
        return 1
    fi

    echo "$context_file"
}

TANGLE_REVIEW_FINDINGS_FILE=""

tangle_run_context_code_review() {
    local task_group="$1"
    local context_file="$2"
    local round_label="${3:-initial}"
    local marker findings_file review_profile review_rc
    TANGLE_REVIEW_FINDINGS_FILE=""

    if ! declare -F review_run >/dev/null 2>&1; then
        log ERROR "tangle review gate cannot run: review_run is unavailable"
        return 1
    fi

    marker=$(mktemp "${TMPDIR:-/tmp}/octopus-tangle-review-marker.XXXXXX")
    touch "$marker"
    local _marker_cleanup_trap
    _marker_cleanup_trap=$(trap -p RETURN || true)
    trap 'rm -f "${marker:-}" 2>/dev/null || true' RETURN

    review_profile=$(jq -n \
        --arg target "${OCTOPUS_TANGLE_REVIEW_TARGET:-working-tree}" \
        --arg contextFile "$context_file" \
        --arg contextLabel "Octopus tangle develop review context (${round_label})" \
        --arg provenance "octopus-tangle" \
        --arg autonomy "${OCTOPUS_TANGLE_REVIEW_AUTONOMY:-autonomous}" \
        --arg publish "${OCTOPUS_TANGLE_REVIEW_PUBLISH:-never}" \
        --arg history "${OCTOPUS_TANGLE_REVIEW_HISTORY:-fresh}" \
        '{target:$target, contextFile:$contextFile, contextLabel:$contextLabel, focus:["correctness","security","architecture","tdd","plan-conformance"], provenance:$provenance, autonomy:$autonomy, publish:$publish, history:$history}')

    log INFO "Step 4: Contextual code review (${round_label})..."
    review_run "$review_profile"
    review_rc=$?

    findings_file=""
    local _findings_candidate _findings_mtime _best_findings_mtime=0
    while IFS= read -r _findings_candidate; do
        [[ -f "$_findings_candidate" ]] || continue
        [[ "$_findings_candidate" -nt "$marker" ]] || continue
        _findings_mtime=$(stat -c '%Y' "$_findings_candidate" 2>/dev/null || stat -f '%m' "$_findings_candidate" 2>/dev/null || echo 0)
        [[ "$_findings_mtime" =~ ^[0-9]+$ ]] || _findings_mtime=0
        if [[ "$_findings_mtime" -ge "$_best_findings_mtime" ]]; then
            _best_findings_mtime="$_findings_mtime"
            findings_file="$_findings_candidate"
        fi
    done < <(find "${RESULTS_DIR:-${HOME}/.claude-octopus/results}" -maxdepth 1 -type f -name 'review-findings-*.json' 2>/dev/null || true)
    rm -f "$marker" 2>/dev/null || true
    trap - RETURN
    if [[ -n "$_marker_cleanup_trap" ]]; then
        eval "$_marker_cleanup_trap"
    fi

    if [[ -z "$findings_file" || ! -f "$findings_file" ]]; then
        log ERROR "Contextual code review did not produce a findings file"
        return 1
    fi

    TANGLE_REVIEW_FINDINGS_FILE="$findings_file"
    local normal_count review_warning
    normal_count=$(tangle_review_blocking_count "$findings_file")
    review_warning=$(tangle_review_warning_text "$findings_file")
    log INFO "Contextual code review findings: $findings_file (normal=${normal_count})"
    if [[ -n "$review_warning" ]]; then
        log WARN "Contextual code review warning: ${review_warning}"
        return 1
    fi
    return "$review_rc"
}

tangle_correction_identity_message() {
    local round_num="$1"
    local correction_strategy="$2"
    local stall_window="$3"
    local correction_agent="$4"
    local correction_model="$5"
    printf '%s\n' "Step 5: Applying contextual review corrections (round=${round_num}, role=implementer, strategy=${correction_strategy}, stall_window=${stall_window}s, executor_alias=${correction_agent}, configured_provider=$(octo_provider_identity_from_agent_type "${correction_agent}"), configured_model=${correction_model}, runtime_provider=unknown, runtime_model=unknown)..."
}

tangle_apply_review_corrections() {
    local resolved_prompt="$1"
    local context_file="$2"
    local findings_file="$3"
    local round_num="$4"
    local correction_agent="${5:-codex}"
    local correction_strategy="${6:-delta}"
    local correction_file="${RESULTS_DIR:-${HOME}/.claude-octopus/results}/tangle-review-corrections-${round_num}-$(date +%s).md"
    local rc_file="${correction_file}.rc"
    local normal_findings strategy_text before_fp after_fp last_fp last_size last_progress now

    TANGLE_CORRECTION_FILE="$correction_file"
    TANGLE_CORRECTION_STATUS="unknown"
    TANGLE_CORRECTION_CHANGED="0"
    TANGLE_CORRECTION_CONTAMINATION=""

    normal_findings=$(tangle_normal_findings_summary "$findings_file")
    if [[ -z "$normal_findings" ]]; then
        log INFO "No normal findings to correct in $findings_file"
        TANGLE_CORRECTION_STATUS="no-findings"
        return 0
    fi

    strategy_text=$(tangle_correction_strategy_prompt "$correction_strategy")
    local correction_prompt="You are in Octopus tangle correction round ${round_num}.

Do not reimplement the whole plan.
Do not expand scope.
Do not restart from scratch.
Preserve existing working-tree changes unless a change is necessary to fix a blocking finding.
Fix blocking severity=normal findings using the requested strategy.
After editing, report files changed and tests/checks run.

${strategy_text}

Hard rules:
- Do not declare success unless the intended edits were actually written.
- Do not leave backup/scratch files in the worktree.
- Prefer exact edits and tests over prose.

Original task contract:
\`\`\`markdown
${resolved_prompt}
\`\`\`

Review context file for reference:
${context_file}

Blocking findings to fix:
${normal_findings}
"

    before_fp=$(tangle_worktree_fingerprint)
    last_fp="$before_fp"
    last_size=0
    last_progress=$(date +%s)
    : > "$correction_file"
    rm -f "$rc_file" 2>/dev/null || true

    local stall_window="${OCTOPUS_TANGLE_CORRECTION_STALL_WINDOW:-1800}"
    local poll_secs="${OCTOPUS_TANGLE_CORRECTION_POLL_SECS:-30}"
    [[ "$stall_window" =~ ^[0-9]+$ ]] || stall_window=1800
    [[ "$poll_secs" =~ ^[0-9]+$ ]] || poll_secs=30
    [[ "$poll_secs" -lt 1 ]] && poll_secs=1

    local correction_model
    correction_model=$(get_agent_model "$correction_agent" "tangle" "implementer" 2>/dev/null || true)
    [[ -n "$correction_model" ]] || correction_model="unresolved"
    log INFO "$(tangle_correction_identity_message "$round_num" "$correction_strategy" "$stall_window" "$correction_agent" "$correction_model")"
    (
        OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="tangle-correction-stall-watchdog" run_agent_sync "$correction_agent" "$correction_prompt" 0 "implementer" "tangle" > "$correction_file" 2>&1
        echo "$?" > "$rc_file"
    ) &
    local correction_pid=$!
    local stalled="false"

    while true; do
        [[ -f "$rc_file" ]] && break
        if ! tangle_process_is_active_non_zombie "$correction_pid"; then
            break
        fi
        sleep "$poll_secs"
        local current_fp current_size
        current_fp=$(tangle_worktree_fingerprint)
        current_size=$(stat -c '%s' "$correction_file" 2>/dev/null || stat -f '%z' "$correction_file" 2>/dev/null || echo 0)
        if [[ "$current_fp" != "$last_fp" || "$current_size" != "$last_size" ]]; then
            last_fp="$current_fp"
            last_size="$current_size"
            last_progress=$(date +%s)
            log INFO "Correction round ${round_num}: progress observed (worktree/output changed)"
        fi
        now=$(date +%s)
        if [[ "$stall_window" -gt 0 && $((now - last_progress)) -ge "$stall_window" ]]; then
            stalled="true"
            log WARN "Correction round ${round_num}: no observable progress for ${stall_window}s — stopping agent and preserving partial writes"
            pkill -TERM -P "$correction_pid" 2>/dev/null || true
            kill -TERM "$correction_pid" 2>/dev/null || true
            sleep 2
            pkill -KILL -P "$correction_pid" 2>/dev/null || true
            kill -KILL "$correction_pid" 2>/dev/null || true
            break
        fi
    done

    wait "$correction_pid" 2>/dev/null || true
    local correction_rc="1"
    [[ -f "$rc_file" ]] && correction_rc=$(cat "$rc_file" 2>/dev/null || echo 1)
    rm -f "$rc_file" 2>/dev/null || true

    after_fp=$(tangle_worktree_fingerprint)
    if [[ "$after_fp" != "$before_fp" ]]; then
        TANGLE_CORRECTION_CHANGED="1"
    fi
    TANGLE_CORRECTION_CONTAMINATION=$(tangle_scope_contamination_summary)

    if [[ "$stalled" == "true" ]]; then
        TANGLE_CORRECTION_STATUS="stalled-partial"
        {
            echo ""
            echo "## Status: STALLED - PARTIAL RESULTS"
            echo "# Completed: $(date)"
        } >> "$correction_file"
        log WARN "Correction round ${round_num} stalled; partial writes changed=${TANGLE_CORRECTION_CHANGED}; result: $correction_file"
        return 0
    fi

    if [[ "$correction_rc" == "0" ]]; then
        TANGLE_CORRECTION_STATUS="completed"
        {
            echo ""
            echo "## Status: SUCCESS"
            echo "# Completed: $(date)"
        } >> "$correction_file"
        log INFO "Correction round ${round_num} result: $correction_file"
        return 0
    fi

    if [[ "$correction_rc" == "130" || "$correction_rc" == "137" || "$correction_rc" == "143" ]]; then
        TANGLE_CORRECTION_STATUS="interrupted-partial"
        {
            echo ""
            echo "## Status: INTERRUPTED - PARTIAL WRITES PRESERVED"
            echo "# Completed: $(date)"
        } >> "$correction_file"
        log WARN "Correction round ${round_num} was interrupted (rc=${correction_rc}); preserving partial writes but stopping correction loop: $correction_file"
        return 1
    fi

    if [[ "$TANGLE_CORRECTION_CHANGED" == "1" ]]; then
        TANGLE_CORRECTION_STATUS="failed-partial"
        {
            echo ""
            echo "## Status: FAILED - PARTIAL WRITES PRESERVED"
            echo "# Completed: $(date)"
        } >> "$correction_file"
        log WARN "Correction round ${round_num} failed but left partial writes; validation/review should continue: $correction_file"
        return 0
    fi

    TANGLE_CORRECTION_STATUS="failed-no-progress"
    {
        echo ""
        echo "## Status: FAILED - NO PROGRESS"
        echo "# Completed: $(date)"
    } >> "$correction_file"
    log WARN "Correction round ${round_num} failed with no observable worktree change: $correction_file"
    return 1
}


# Phase 3: TANGLE (Develop) - Enhanced map-reduce with validation
# Tentacles work together in a coordinated tangle of activity
tangle_cleanup_verification_context() {
    # Restore the caller's traps (orchestrate.sh owns an EXIT trap that removes
    # $OCTOPUS_TMP_DIR) instead of clobbering them with `trap - EXIT`. Same
    # save/restore contract as atomic_json_update in lib/validation.sh.
    eval "${TANGLE_VERIFY_PREV_EXIT_TRAP:-trap - EXIT}"
    eval "${TANGLE_VERIFY_PREV_INT_TRAP:-trap - INT}"
    eval "${TANGLE_VERIFY_PREV_TERM_TRAP:-trap - TERM}"

    if [[ -n "${TANGLE_VERIFY_ORIGINAL_PWD:-}" ]]; then
        cd "$TANGLE_VERIFY_ORIGINAL_PWD" 2>/dev/null || true
    fi
    if [[ -n "${TANGLE_VERIFY_ORIGINAL_PROJECT_ROOT:-}" ]]; then
        PROJECT_ROOT="$TANGLE_VERIFY_ORIGINAL_PROJECT_ROOT"
        export PROJECT_ROOT
    fi

    if [[ -n "${TANGLE_VERIFY_SOURCE_ROOT:-}" && -n "${TANGLE_VERIFY_WORKTREE:-}" ]]; then
        if ! git -C "$TANGLE_VERIFY_SOURCE_ROOT" worktree remove --force "$TANGLE_VERIFY_WORKTREE" >/dev/null 2>&1; then
            log WARN "Normal verification worktree removal failed; forcing filesystem cleanup: $TANGLE_VERIFY_WORKTREE"
            rm -rf "$TANGLE_VERIFY_WORKTREE"
            git -C "$TANGLE_VERIFY_SOURCE_ROOT" worktree prune >/dev/null 2>&1 ||                 log ERROR "Failed to prune verification worktree registrations: $TANGLE_VERIFY_SOURCE_ROOT"
        fi
        if [[ -e "$TANGLE_VERIFY_WORKTREE" ]]; then
            log ERROR "Disposable verification worktree still exists after cleanup: $TANGLE_VERIFY_WORKTREE"
        fi
    fi

    unset TANGLE_VERIFY_SOURCE_ROOT TANGLE_VERIFY_WORKTREE
    unset TANGLE_VERIFY_ORIGINAL_PWD TANGLE_VERIFY_ORIGINAL_PROJECT_ROOT
    unset TANGLE_VERIFY_PREV_EXIT_TRAP TANGLE_VERIFY_PREV_INT_TRAP TANGLE_VERIFY_PREV_TERM_TRAP
}

tangle_verify() {
    local prompt="$1"
    local run_id="${OCTOPUS_VERIFY_RUN_ID:-$(date +%s)-$$}"
    if [[ ! "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ || "$run_id" == *..* ]]; then
        log ERROR "Invalid OCTOPUS_VERIFY_RUN_ID: $run_id"
        return 1
    fi
    local source_root source_commit verify_root verify_worktree
    local original_project_root="${PROJECT_ROOT:-$PWD}"
    local original_pwd="$PWD"
    local verify_agent="agy" verify_fallback_agent="codex"
    local raw_result="" result_file status rc=1
    local verify_cd_succeeded=false

    source_root=$(git -C "$original_project_root" rev-parse --show-toplevel 2>/dev/null) || {
        log ERROR "Verification-only mode requires a Git repository"
        return 1
    }
    source_commit=$(git -C "$source_root" rev-parse --verify HEAD 2>/dev/null) || {
        log ERROR "Verification-only mode requires an existing commit"
        return 1
    }

    verify_root="${OCTOPUS_VERIFY_WORKTREE_ROOT:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}/worktrees/verify}"
    verify_worktree="${verify_root}/${run_id}"
    result_file="${RESULTS_DIR}/tangle-verification-${run_id}.json"

    if [[ -e "$verify_worktree" ]]; then
        log ERROR "Verification worktree path already exists: $verify_worktree"
        return 1
    fi
    mkdir -p "$verify_root" "$RESULTS_DIR" || return 1
    if ! git -C "$source_root" worktree add --detach "$verify_worktree" "$source_commit" >/dev/null; then
        log ERROR "Failed to create verification worktree: $verify_worktree"
        return 1
    fi

    TANGLE_VERIFY_SOURCE_ROOT="$source_root"
    TANGLE_VERIFY_WORKTREE="$verify_worktree"
    TANGLE_VERIFY_ORIGINAL_PWD="$original_pwd"
    TANGLE_VERIFY_ORIGINAL_PROJECT_ROOT="$original_project_root"
    export TANGLE_VERIFY_SOURCE_ROOT TANGLE_VERIFY_WORKTREE
    export TANGLE_VERIFY_ORIGINAL_PWD TANGLE_VERIFY_ORIGINAL_PROJECT_ROOT
    # Capture the caller's traps so cleanup can restore rather than clear them.
    TANGLE_VERIFY_PREV_EXIT_TRAP=$(trap -p EXIT)
    TANGLE_VERIFY_PREV_INT_TRAP=$(trap -p INT)
    TANGLE_VERIFY_PREV_TERM_TRAP=$(trap -p TERM)
    trap 'tangle_cleanup_verification_context' EXIT INT TERM

    if declare -f octopus_agent_override >/dev/null 2>&1; then
        verify_agent=$(octopus_execution_profile_provider "tangle" "verify" "researcher" "agy")
        verify_fallback_agent=$(octopus_execution_profile_provider "tangle" "verify_fallback" "researcher" "codex")
    fi

    PROJECT_ROOT="$verify_worktree"
    export PROJECT_ROOT
    if cd "$verify_worktree"; then
        verify_cd_succeeded=true
    else
        log ERROR "Failed to enter disposable verification worktree: $verify_worktree"
    fi

    local verify_prompt="Verification-only task. Inspect and test the committed project state without implementing fixes or changing product behavior.

Task: ${prompt}

Rules:
- Reproduce the reported defect using relevant existing tests and runtime inspection.
- Run the relevant baseline tests when practical.
- Do not implement, refactor, add features, update dependencies, edit documentation, or weaken tests.
- Do not launch implementation agents.
- Return exactly one JSON object and no Markdown fences or prose.

Required schema:
{\"baselinePassed\":true|false,\"defectReproduced\":true|false,\"implementationRequired\":true|false,\"evidence\":{\"commands\":[\"...\"],\"failingTests\":[\"...\"],\"summary\":\"...\"}}

Consistency rules:
- If baseline passes and the defect is not reproduced, implementationRequired must be false.
- If the defect is reproduced and needs a code change, implementationRequired must be true."

    if [[ "$verify_cd_succeeded" != "true" || "$PWD" != "$verify_worktree" ]]; then
        raw_result=""
    else
        raw_result=$(OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="verification-only" run_agent_sync "$verify_agent" "$verify_prompt" 0 "researcher" "tangle-verify") || \
        raw_result=$(OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="verification-only" run_agent_sync "$verify_fallback_agent" "$verify_prompt" 0 "researcher" "tangle-verify") || raw_result=""
    fi

    cd "$original_pwd" 2>/dev/null || true
    PROJECT_ROOT="$original_project_root"
    export PROJECT_ROOT

    if [[ -z "$raw_result" ]] || ! jq -e '
        type == "object" and
        (.baselinePassed | type == "boolean") and
        (.defectReproduced | type == "boolean") and
        (.implementationRequired | type == "boolean") and
        (.evidence | type == "object") and
        (.evidence.commands | type == "array") and
        all(.evidence.commands[]; type == "string") and
        (.evidence.failingTests | type == "array") and
        all(.evidence.failingTests[]; type == "string") and
        (.evidence.summary | type == "string") and
        (
            if (.baselinePassed == true and .defectReproduced == false)
            then .implementationRequired == false
            else true
            end
        )
    ' >/dev/null 2>&1 <<< "$raw_result"; then
        status="NEEDS_DIAGNOSIS"
        jq -n --arg status "$status" --arg sourceCommit "$source_commit" --arg raw "$raw_result" \
            '{status:$status,sourceCommit:$sourceCommit,error:"invalid verification result",raw:$raw}' > "$result_file"
        rc=1
    else
        local baseline_passed defect_reproduced implementation_required
        baseline_passed=$(jq -r '.baselinePassed' <<< "$raw_result")
        defect_reproduced=$(jq -r '.defectReproduced' <<< "$raw_result")
        implementation_required=$(jq -r '.implementationRequired' <<< "$raw_result")

        if [[ "$baseline_passed" == "true" && "$defect_reproduced" == "false" && "$implementation_required" == "false" ]]; then
            status="VERIFIED_NO_CHANGE"
            rc=0
        elif [[ "$defect_reproduced" == "true" && "$implementation_required" == "true" ]]; then
            status="DEFECT_REPRODUCED"
            rc=2
        else
            status="NEEDS_DIAGNOSIS"
            rc=1
        fi
        jq --arg status "$status" --arg sourceCommit "$source_commit" \
            '. + {status:$status,sourceCommit:$sourceCommit}' <<< "$raw_result" > "$result_file"
    fi

    tangle_cleanup_verification_context

    log INFO "Verification-only result: $status"
    log INFO "Verification artifact: $result_file"
    TANGLE_VERIFICATION_RESULT_FILE="$result_file"
    TANGLE_VERIFICATION_STATUS="$status"
    export TANGLE_VERIFICATION_RESULT_FILE TANGLE_VERIFICATION_STATUS
    return "$rc"
}

tangle_clean_baseline_guard_enabled() {
    [[ "${OCTOPUS_TANGLE_REQUIRE_CLEAN_BASELINE:-false}" == "true" ]]
}

tangle_require_clean_git_baseline() {
    local source_root source_root_physical status_output line path allowed_path allowed_relative_entry
    local allowed_dir allowed_name allowed_physical allowed_relative
    local blocking_output=""
    local -a allowed_untracked=()
    source_root=$(git -C "${PROJECT_ROOT:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || {
        log ERROR "Tangle implementation requires a Git repository when clean-baseline enforcement is enabled"
        return 1
    }

    source_root_physical=$(cd "$source_root" 2>/dev/null && pwd -P) || return 1
    for allowed_path in "$@"; do
        [[ -n "$allowed_path" && -f "$allowed_path" && ! -L "$allowed_path" ]] || continue
        allowed_dir=$(dirname "$allowed_path")
        allowed_name=$(basename "$allowed_path")
        allowed_dir=$(cd "$allowed_dir" 2>/dev/null && pwd -P) || continue
        allowed_physical="${allowed_dir}/${allowed_name}"
        case "$allowed_physical" in
            "$source_root_physical"/*)
                allowed_relative="${allowed_physical#"$source_root_physical"/}"
                allowed_untracked+=("$allowed_relative")
                ;;
        esac
    done

    status_output=$(git -C "$source_root" status --porcelain=v1 --untracked-files=all 2>/dev/null) || {
        log ERROR "Unable to inspect Git baseline at: $source_root"
        return 1
    }
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$line" == "?? "* ]]; then
            path="${line#?? }"
            local path_is_allowed=false
            for allowed_relative_entry in ${allowed_untracked[@]+"${allowed_untracked[@]}"}; do
                [[ "$path" == "$allowed_relative_entry" ]] && path_is_allowed=true && break
            done
            if [[ "$path_is_allowed" == "true" ]]; then
                continue
            fi
        fi
        blocking_output="${blocking_output}${blocking_output:+$'\n'}${line}"
    done <<< "$status_output"

    if [[ -n "$blocking_output" ]]; then
        log ERROR "Tangle implementation requires a clean Git baseline: $source_root"
        while IFS= read -r line; do
            [[ -n "$line" ]] && log ERROR "  $line"
        done <<< "$blocking_output"
        log ERROR "Commit or stash unrelated changes. To use one untracked brief safely, reference PLAN.md, SPEC.md, or BRIEF.md explicitly (or prefix a path with plan:, spec:, or brief:) while run-worktree isolation remains enabled."
        log ERROR "Advanced bypass: OCTOPUS_TANGLE_REQUIRE_CLEAN_BASELINE=false keeps isolation enabled, but accepts responsibility for the dirty source state."
        return 1
    fi
    return 0
}

tangle_run_worktree_enabled() {
    [[ "${OCTOPUS_TANGLE_RUN_WORKTREE:-true}" == "true" ]]
}

# Reserve a collision-free default run ID. Tangle can be invoked repeatedly in
# the same shell and second (especially in tests and scripted workflows), so a
# timestamp plus $$ is not unique enough. Reuse the spawn-layer allocator when
# available; workflows.sh is also sourced directly by tests and integrations,
# so retain an atomic mktemp-based fallback here.
tangle_next_run_id() {
    if declare -F _octopus_next_spawn_task_id >/dev/null 2>&1; then
        _octopus_next_spawn_task_id
        return $?
    fi

    local reservation_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/task-ids"
    local reservation unique_suffix prune_day marker lock_dir
    mkdir -p "$reservation_dir" 2>/dev/null || true
    prune_day=$(date +%Y%m%d 2>/dev/null || printf 'unknown')
    marker="${reservation_dir}/.pruned-${prune_day}"
    lock_dir="${marker}.lock"
    if [[ ! -e "$marker" ]] && mkdir "$lock_dir" 2>/dev/null; then
        find "$reservation_dir" -type f -mtime +7 -delete 2>/dev/null || true
        : > "$marker"
        rmdir "$lock_dir" 2>/dev/null || true
    fi
    reservation=$(mktemp "${reservation_dir}/XXXXXX" 2>/dev/null) && unique_suffix="${reservation##*/}"
    printf '%s-%s\n' "$(date +%s)" "${unique_suffix:-${BASHPID:-$$}${RANDOM}}"
}

tangle_extract_plan_file_ref() {
    local prompt="$1"
    local token token_lower candidate_ref candidate_basename candidate_basename_lower raw_file_ref
    local noglob_was_set=false
    [[ "$-" == *f* ]] && noglob_was_set=true || set -f
    for token in $prompt; do
        token_lower=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
        candidate_ref="$token"
        case "$token_lower" in
            plan:*|spec:*|brief:*) candidate_ref="${token#*:}" ;;
            plan=*|spec=*|brief=*) candidate_ref="${token#*=}" ;;
        esac
        candidate_basename="${candidate_ref##*/}"
        candidate_basename_lower=$(printf '%s' "$candidate_basename" | tr '[:upper:]' '[:lower:]')
        if [[ "$token_lower" == plan:* || "$token_lower" == plan=* \
           || "$token_lower" == spec:* || "$token_lower" == spec=* \
           || "$token_lower" == brief:* || "$token_lower" == brief=* \
           || "$candidate_basename_lower" == "plan.md" \
           || "$candidate_basename_lower" == "spec.md" \
           || "$candidate_basename_lower" == "brief.md" \
           || "$candidate_basename_lower" == *.plan.md \
           || "$candidate_basename_lower" == *-plan.md \
           || "$candidate_basename_lower" == *.spec.md \
           || "$candidate_basename_lower" == *-spec.md \
           || "$candidate_basename_lower" == *.brief.md \
           || "$candidate_basename_lower" == *-brief.md ]]; then
            raw_file_ref="$candidate_ref"
            [[ "$noglob_was_set" == "false" ]] && set +f
            printf '%s' "$raw_file_ref"
            return 0
        fi
    done
    [[ "$noglob_was_set" == "false" ]] && set +f
    return 1
}

tangle_resolve_context_file_path() {
    local file_ref="$1"
    local base_dir="$2"
    local expanded_ref file_dir file_name physical_dir

    expanded_ref="${file_ref/#\~/$HOME}"
    if [[ "$expanded_ref" != /* ]]; then
        expanded_ref="${base_dir%/}/${expanded_ref}"
    fi
    [[ -f "$expanded_ref" ]] || return 1

    file_dir=$(dirname "$expanded_ref")
    file_name=$(basename "$expanded_ref")
    physical_dir=$(cd "$file_dir" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s' "$physical_dir" "$file_name"
}

tangle_resolve_prompt_plan_file_path() {
    local prompt="$1"
    local base_dir="$2"
    local raw_file_ref
    raw_file_ref=$(tangle_extract_plan_file_ref "$prompt") || return 1
    tangle_resolve_context_file_path "$raw_file_ref" "$base_dir"
}

tangle_write_run_git_metadata() {
    local task_group="$1"
    local metadata_file="${RESULTS_DIR}/.tangle-${task_group}-git.json"
    mkdir -p "$RESULTS_DIR"
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg sourceRepository "$TANGLE_RUN_SOURCE_ROOT" \
            --arg sourceCommit "$TANGLE_RUN_SOURCE_COMMIT" \
            --arg runBranch "$TANGLE_RUN_BRANCH" \
            --arg runWorktree "$TANGLE_RUN_WORKTREE" \
            '{sourceRepository:$sourceRepository,sourceCommit:$sourceCommit,runBranch:$runBranch,runWorktree:$runWorktree}' \
            > "$metadata_file"
    else
        printf '{"sourceRepository":"%s","sourceCommit":"%s","runBranch":"%s","runWorktree":"%s"}\n' \
            "$TANGLE_RUN_SOURCE_ROOT" "$TANGLE_RUN_SOURCE_COMMIT" "$TANGLE_RUN_BRANCH" "$TANGLE_RUN_WORKTREE" \
            > "$metadata_file"
    fi
    TANGLE_RUN_METADATA_FILE="$metadata_file"
    export TANGLE_RUN_METADATA_FILE
}

tangle_rollback_run_worktree() {
    local source_root="$1"
    local worktree="$2"
    local branch="$3"
    local rollback_rc=0

    if ! git -C "$source_root" worktree remove --force "$worktree" >/dev/null 2>&1; then
        log ERROR "Failed to remove Tangle run worktree during rollback: $worktree"
        rollback_rc=1
    fi
    if ! git -C "$source_root" branch -D "$branch" >/dev/null 2>&1; then
        log ERROR "Failed to delete Tangle run branch during rollback: $branch"
        rollback_rc=1
    fi
    return "$rollback_rc"
}

tangle_prepare_run_worktree() {
    local task_group="$1"
    local source_root source_commit runtime_root run_parent

    source_root=$(git -C "${PROJECT_ROOT:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || {
        log ERROR "Tangle implementation requires a Git repository when run worktree isolation is enabled"
        return 1
    }
    source_commit=$(git -C "$source_root" rev-parse --verify HEAD 2>/dev/null) || {
        log ERROR "Tangle implementation requires a repository with an existing commit"
        return 1
    }

    runtime_root="${OCTOPUS_RUN_WORKTREE_ROOT:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}/worktrees/tangle}"
    TANGLE_RUN_SOURCE_ROOT="$source_root"
    TANGLE_RUN_SOURCE_COMMIT="$source_commit"
    TANGLE_RUN_BRANCH="octopus/run/${task_group}/integration"
    TANGLE_RUN_WORKTREE="${runtime_root}/${task_group}/integration"
    run_parent=$(dirname "$TANGLE_RUN_WORKTREE")

    if [[ -e "$TANGLE_RUN_WORKTREE" ]]; then
        log ERROR "Tangle run worktree path already exists: $TANGLE_RUN_WORKTREE"
        return 1
    fi
    if git -C "$source_root" show-ref --verify --quiet "refs/heads/$TANGLE_RUN_BRANCH"; then
        log ERROR "Tangle run branch already exists: $TANGLE_RUN_BRANCH"
        return 1
    fi

    mkdir -p "$run_parent" || return 1
    if ! git -C "$source_root" worktree add -b "$TANGLE_RUN_BRANCH" "$TANGLE_RUN_WORKTREE" "$source_commit" >/dev/null; then
        log ERROR "Failed to create Tangle run worktree: $TANGLE_RUN_WORKTREE"
        return 1
    fi

    export TANGLE_RUN_SOURCE_ROOT TANGLE_RUN_SOURCE_COMMIT TANGLE_RUN_BRANCH TANGLE_RUN_WORKTREE
    tangle_write_run_git_metadata "$task_group" || {
        log ERROR "Failed to write Tangle run Git metadata"
        tangle_rollback_run_worktree "$source_root" "$TANGLE_RUN_WORKTREE" "$TANGLE_RUN_BRANCH"
        return 1
    }
    log INFO "Tangle run isolated in Git worktree: $TANGLE_RUN_WORKTREE"
    log INFO "Tangle run branch: $TANGLE_RUN_BRANCH (base $TANGLE_RUN_SOURCE_COMMIT)"
}

tangle_develop() {
    local prompt="$1"
    local grasp_file="${2:-}"
    local task_group original_project_root original_pwd resolved_grasp_file resolved_plan_file rc

    # Dry runs retain their historical side-effect-free behavior and do not
    # create an otherwise unused run worktree.
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        _tangle_develop_in_workspace "$prompt" "$grasp_file"
        return $?
    fi

    original_project_root="${PROJECT_ROOT:-$PWD}"
    original_pwd="$PWD"
    resolved_grasp_file="$grasp_file"
    resolved_plan_file=""
    rc=0

    # Resolve explicit caller context before the clean-baseline gate. A single
    # repo-contained untracked input can be safely read and injected into the
    # isolated run without admitting any unrelated dirty path.
    if tangle_run_worktree_enabled; then
        if [[ -n "$grasp_file" ]]; then
            resolved_grasp_file=$(tangle_resolve_context_file_path "$grasp_file" "$original_pwd" 2>/dev/null) \
                || resolved_grasp_file="$grasp_file"
        fi
        resolved_plan_file=$(tangle_resolve_prompt_plan_file_path "$prompt" "$original_pwd" 2>/dev/null) || true
    fi

    # Validate the caller's source checkout before creating an isolated run
    # worktree; checking afterward would only prove that the new worktree is clean.
    if tangle_clean_baseline_guard_enabled; then
        if tangle_run_worktree_enabled; then
            tangle_require_clean_git_baseline "$resolved_plan_file" "$resolved_grasp_file" || return 1
        else
            tangle_require_clean_git_baseline || return 1
        fi
    fi

    if ! tangle_run_worktree_enabled; then
        _tangle_develop_in_workspace "$prompt" "$grasp_file"
        return $?
    fi

    task_group="${OCTOPUS_TANGLE_RUN_ID:-}"
    if [[ -n "$task_group" ]]; then
        if [[ ! "$task_group" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ || "$task_group" == *..* ]]; then
            log ERROR "Invalid OCTOPUS_TANGLE_RUN_ID: $task_group"
            return 1
        fi
    else
        task_group=$(tangle_next_run_id) || return 1
    fi
    tangle_prepare_run_worktree "$task_group" || return 1

    PROJECT_ROOT="$TANGLE_RUN_WORKTREE"
    export PROJECT_ROOT
    cd "$PROJECT_ROOT" || {
        log ERROR "Failed to enter Tangle run worktree: $PROJECT_ROOT"
        tangle_rollback_run_worktree "$TANGLE_RUN_SOURCE_ROOT" "$TANGLE_RUN_WORKTREE" "$TANGLE_RUN_BRANCH"
        PROJECT_ROOT="$original_project_root"
        export PROJECT_ROOT
        return 1
    }

    _tangle_develop_in_workspace "$prompt" "$resolved_grasp_file" "$task_group" "$resolved_plan_file" || rc=$?

    cd "$original_pwd" 2>/dev/null || true
    PROJECT_ROOT="$original_project_root"
    export PROJECT_ROOT

    if [[ "$rc" -ne 0 ]]; then
        log WARN "Tangle run failed; preserving isolated branch and worktree for inspection: $TANGLE_RUN_BRANCH"
    else
        log INFO "Tangle run completed; preserving isolated branch and worktree for review: $TANGLE_RUN_BRANCH"
    fi
    return "$rc"
}

_tangle_develop_in_workspace() {
    local prompt="$1"
    local grasp_file="${2:-}"
    local task_group="${3:-$(date +%s)}"
    local pre_resolved_plan_file="${4:-}"

    echo ""
    octopus_phase_banner "DEVELOP (Phase 3/4)" "Implementation" "$MAGENTA"
    echo ""

    log INFO "Phase 3: Parallel development with validation gates"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would tangle: $prompt"
        log INFO "[DRY-RUN] Would decompose into subtasks and execute in parallel"
        return 0
    fi

    if ! declare -F review_kill_process_tree_frozen >/dev/null 2>&1 \
       || ! declare -F review_kill_descendants_frozen >/dev/null 2>&1; then
        log ERROR "Tangle cancellation helpers are unavailable; refusing to start provider work"
        return 1
    fi

    if tangle_clean_baseline_guard_enabled; then
        tangle_require_clean_git_baseline || return 1
    fi

    # Cost transparency (v7.18.0 - P0.0)
    if ! display_workflow_cost_estimate "Tangle (Develop Phase)" 2 2 1800; then
        log "WARN" "Workflow cancelled by user after cost review"
        return 1
    fi

    if declare -F begin_progress_phase >/dev/null 2>&1; then
        begin_progress_phase "develop"
    fi

    # v8.18.0: Reset lockouts for new tangle phase
    reset_provider_lockouts

    # v8.34.0: Parallel file safety — write/edit errors don't abort siblings (G12)
    if [[ "$SUPPORTS_PARALLEL_FILE_SAFETY" == "true" ]]; then
        log "DEBUG" "Parallel file safety active — concurrent file operations enabled"
    fi

    mkdir -p "$RESULTS_DIR"
    local worktree_before_file="${RESULTS_DIR}/.tangle-${task_group}-worktree-before.txt"
    local worktree_before_state_file="${RESULTS_DIR}/.tangle-${task_group}-worktree-before-state.txt"
    if type snapshot_tangle_worktree_paths >/dev/null 2>&1; then
        snapshot_tangle_worktree_paths > "$worktree_before_file" 2>/dev/null || true
    else
        : > "$worktree_before_file"
    fi
    if type snapshot_tangle_worktree_state >/dev/null 2>&1; then
        snapshot_tangle_worktree_state > "$worktree_before_state_file" 2>/dev/null || true
    else
        : > "$worktree_before_state_file"
    fi

    # Initialize tmux if enabled
    if [[ "$TMUX_MODE" == "true" ]]; then
        tmux_init
    fi

    # Load problem definition if available
    local context=""
    if [[ -n "$grasp_file" && -f "$grasp_file" ]]; then
        context="Problem Definition:\n$(<"$grasp_file")\n\n"
        log INFO "Using grasp context from: $grasp_file"
    fi

    # Resolve a referenced Markdown plan file before both design review and
    # decomposition. Claude-based reviewers cannot read files outside the active
    # worktree unless the content is injected into the prompt.
    local resolved_prompt="$prompt"
    local file_ref=""
    local raw_file_ref=""
    raw_file_ref=$(tangle_extract_plan_file_ref "$prompt") || true
    if [[ -n "$pre_resolved_plan_file" ]]; then
        file_ref="$pre_resolved_plan_file"
    elif [[ -n "$raw_file_ref" ]]; then
        file_ref=$(tangle_resolve_context_file_path "$raw_file_ref" "$PWD" 2>/dev/null) || true
    fi
    if [[ -n "$file_ref" && -f "$file_ref" ]]; then
        local max_plan_bytes="${OCTOPUS_PLAN_INJECT_MAX_BYTES:-40000}"
        [[ "$max_plan_bytes" =~ ^[0-9]+$ ]] || max_plan_bytes=40000
        local file_size
        file_size=$(wc -c < "$file_ref" 2>/dev/null || echo 0)
        local file_content
        if [[ "$file_size" -gt "$max_plan_bytes" ]]; then
            file_content="$(head -c "$max_plan_bytes" "$file_ref" 2>/dev/null)"
            file_content="${file_content}

[... truncated from ${file_size} bytes to ${max_plan_bytes} bytes ...]"
        else
            file_content=$(<"$file_ref")
        fi
        local plan_block="--- PLAN: ${file_ref} ---
${file_content}
--- END PLAN ---"
        local trimmed_prompt="$prompt"
        trimmed_prompt="${trimmed_prompt#"${trimmed_prompt%%[![:space:]]*}"}"
        trimmed_prompt="${trimmed_prompt%"${trimmed_prompt##*[![:space:]]}"}"

        if [[ "$trimmed_prompt" == "$raw_file_ref" || "$trimmed_prompt" == "$file_ref" ]]; then
            resolved_prompt="Implement the code changes described in the following plan. Do NOT modify the plan file itself (${file_ref}).

${plan_block}"
        else
            resolved_prompt="${prompt}

The following referenced plan file has been resolved. Use it as implementation context and do NOT modify the plan file itself (${file_ref}).

${plan_block}"
        fi
        log INFO "Resolved file reference: ${file_ref} - injecting content into workflow prompt"
    fi

    # v8.18.0: Pre-work design review ceremony. Use resolved_prompt so reviewers
    # receive plan content instead of an unreadable cross-workspace file path.
    design_review_ceremony "$resolved_prompt" "$context"

    # Step 1: Decompose into validated subtasks
    log INFO "Step 1: Task decomposition..."

    local repo_file_map=""
    local repo_root
    if repo_root=$(tangle_resolve_repo_root 2>/dev/null); then
        repo_file_map="Repository files available for write scopes (from git ls-files, first 200):
$(git -C "$repo_root" ls-files 2>/dev/null | sed -n 1,200p)
"
    fi

    local decompose_prompt="Decompose this task into subtasks that can be executed in parallel.
Each subtask should be:
- Self-contained and independently verifiable
- Clear about inputs and expected outputs
- Assignable to either a coding agent [CODING] or reasoning agent [REASONING]
- For every [CODING] subtask, include an explicit 'Files:' clause listing the exact files or directories that subtask owns and may edit
- Coding write scopes must be disjoint. If two subtasks need the same file or directory, merge them into one [CODING] subtask instead of splitting them.

**Cohesion rule:** If the task produces a single deliverable (one file, one script, one page, one config), keep it as ONE subtask — do not split it. Only decompose when subtasks are truly independent with no cross-file references between them. Aim for 2-6 subtasks; fewer is better when the work is tightly coupled.

${context}${repo_file_map}
Task: $resolved_prompt

Output only numbered subtask lines, with no headings, no analysis, no Markdown fences, and no prose before or after.
Required format:
1. [CODING] Short title — Files: relative/file.js, relative/dir/ — Task: specific coding work
2. [REASONING] Short title — Task: specific reasoning work
Every [CODING] line must include a same-line Files: clause."

    # Tangle decomposition agents are overridable (OCTOPUS_TANGLE_DECOMPOSE_AGENT,
    # OCTOPUS_TANGLE_DECOMPOSE_FALLBACK_AGENT, OCTOPUS_TANGLE_AGENT). Override only
    # selects the dispatch agent; the fail-closed contract below is unchanged.
    local tangle_decompose_agent="agy" tangle_decompose_fallback_agent="codex"
    if declare -f octopus_agent_override >/dev/null 2>&1; then
        tangle_decompose_agent=$(octopus_execution_profile_provider "tangle" "decompose" "researcher" "agy")
        tangle_decompose_fallback_agent=$(octopus_execution_profile_provider "tangle" "decompose_fallback" "implementer" "codex")
    fi

    local subtasks
    subtasks=$(OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="tangle-dispatch-watcher" run_agent_sync "$tangle_decompose_agent" "$decompose_prompt" 0 "researcher" "tangle") || \
    subtasks=$(OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="tangle-dispatch-watcher" run_agent_sync "$tangle_decompose_fallback_agent" "$decompose_prompt" 0 "researcher" "tangle") || {
        log ERROR "Decomposition failed with all providers; refusing monolithic direct fallback"
        return 1
    }

    echo -e "${CYAN}Decomposed into subtasks:${NC}"
    echo "$subtasks"
    echo ""

    local parseable_subtask_count
    local parseable_coding_subtask_count
    parseable_subtask_count=$(tangle_parseable_subtask_count "$subtasks")
    parseable_coding_subtask_count=$(tangle_parseable_coding_subtask_count "$subtasks")

    local parallel_safety_reason=""
    if [[ $parseable_subtask_count -eq 0 ]] || [[ $parseable_coding_subtask_count -eq 0 ]] || ! parallel_safety_reason=$(tangle_validate_parallel_write_scopes "$subtasks"); then
        local retry_reason="${parallel_safety_reason:-no parseable subtasks}"
        if [[ $parseable_subtask_count -eq 0 ]]; then
            retry_reason="no parseable subtasks"
        elif [[ $parseable_coding_subtask_count -eq 0 ]]; then
            retry_reason="no parseable [CODING] subtasks"
        fi
        log WARN "Decomposition failed validation (${retry_reason}); retrying with strict one-line Files format"
        local reformatted_subtasks
        if reformatted_subtasks=$(tangle_reformat_decomposition "$resolved_prompt" "$subtasks" "$retry_reason" "$repo_file_map"); then
            subtasks="$reformatted_subtasks"
            echo -e "${CYAN}Reformatted subtasks:${NC}"
            echo "$subtasks"
            echo ""
            parseable_subtask_count=$(tangle_parseable_subtask_count "$subtasks")
            parseable_coding_subtask_count=$(tangle_parseable_coding_subtask_count "$subtasks")
            parallel_safety_reason=""
        else
            log ERROR "Decomposition reformat retry failed; refusing monolithic direct fallback"
            return 1
        fi
    fi

    if [[ $parseable_subtask_count -eq 0 ]]; then
        log ERROR "Decomposition still produced no parseable subtasks after retry; refusing monolithic direct fallback"
        return 1
    fi
    if [[ $parseable_coding_subtask_count -eq 0 ]]; then
        log ERROR "Decomposition still produced no parseable [CODING] subtasks after retry; refusing monolithic direct fallback"
        return 1
    fi

    if [[ $parseable_coding_subtask_count -eq 0 ]]; then
        log ERROR "Decomposition still produced no parseable [CODING] subtasks after retry; refusing monolithic direct fallback"
        return 1
    fi

    if ! parallel_safety_reason=$(tangle_validate_parallel_write_scopes "$subtasks"); then
        log WARN "Reformatted decomposition still overlaps (${parallel_safety_reason}); consolidating connected coding scopes"
        subtasks=$(tangle_consolidate_overlapping_subtasks "$subtasks")
        echo -e "${CYAN}Consolidated subtasks:${NC}"
        echo "$subtasks"
        echo ""
        parseable_subtask_count=$(tangle_parseable_subtask_count "$subtasks")
        parseable_coding_subtask_count=$(tangle_parseable_coding_subtask_count "$subtasks")
        parallel_safety_reason=""
        if [[ $parseable_subtask_count -eq 0 || $parseable_coding_subtask_count -eq 0 ]] || ! parallel_safety_reason=$(tangle_validate_parallel_write_scopes "$subtasks"); then
            log ERROR "Unsafe parallel decomposition after deterministic consolidation: ${parallel_safety_reason:-no parseable coding subtasks}; refusing direct fallback"
            return 1
        fi
    fi

    # Step 2: Parallel execution with progress tracking
    log INFO "Step 2: Parallel execution..."
    local subtask_num=0
    local pids=()
    local task_ids=()
    local subtask_lines=()

    # Materialize parseable lines before dispatching providers. spawn helpers and
    # external CLIs may read stdin; if the dispatch loop itself reads from a
    # here-string, the first provider can consume the remaining decomposition and
    # silently prevent later subtasks from launching.
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        tangle_line_is_numbered_subtask "$line" || continue
        subtask_lines+=("$line")
    done <<< "$subtasks"

    if [[ ${#subtask_lines[@]} -ne $parseable_subtask_count ]]; then
        log ERROR "Parsed $parseable_subtask_count subtasks but retained ${#subtask_lines[@]} for dispatch; refusing partial tangle execution"
        return 1
    fi

    # [CODING] and [REASONING] subtask routing are overridable. This keeps
    # tangle usable on hosts where the default coding provider is unavailable,
    # misconfigured, or unsuitable for implementation work. The lookup order is
    # handled by octopus_agent_override(), e.g. OCTOPUS_TANGLE_CODING_AGENT,
    # OCTOPUS_TANGLE_AGENT, then OCTOPUS_CODING_AGENT.
    local tangle_coding_agent="codex"
    local tangle_reasoning_agent="agy"
    if declare -f octopus_agent_override >/dev/null 2>&1; then
        tangle_coding_agent=$(octopus_execution_profile_provider "tangle" "coding" "implementer" "codex")
        tangle_reasoning_agent=$(octopus_execution_profile_provider "tangle" "reasoning" "researcher" "agy")
    fi

    # [REASONING] falls back through available providers. Without this, users
    # without agy get an unconditional exit 127 on every REASONING subtask even
    # though the provider health check already flagged agy as absent.
    if ! command -v "$tangle_reasoning_agent" >/dev/null 2>&1; then
        if command -v codex >/dev/null 2>&1; then
            tangle_reasoning_agent="codex"
        fi
        # claude-sonnet is a type resolved by get_agent_command, not a bare
        # executable — command -v never finds it. Fall back unconditionally
        # since the claude binary (the host process) is always available.
        if ! command -v "$tangle_reasoning_agent" >/dev/null 2>&1; then
            tangle_reasoning_agent="claude-sonnet"
        fi
    fi

    local tangle_previous_int_trap tangle_previous_term_trap
    tangle_previous_int_trap="$(trap -p INT)"
    tangle_previous_term_trap="$(trap -p TERM)"
    OCTOPUS_ACTIVE_TANGLE_TASK_GROUP="$task_group"
    OCTOPUS_ACTIVE_TANGLE_TMUX="$TMUX_MODE"
    OCTOPUS_ACTIVE_TANGLE_PIDS=()
    OCTOPUS_ACTIVE_TANGLE_AGENTS=()
    OCTOPUS_ACTIVE_TANGLE_TASK_IDS=()
    trap 'octopus_tangle_handle_signal INT' INT
    trap 'octopus_tangle_handle_signal TERM' TERM

    fleet_dispatch_begin
    for line in "${subtask_lines[@]}"; do
        local subtask
        subtask=$(echo "$line" | sed -E 's/^[[:space:]]*(\*\*)?[0-9]+[\.\)][[:space:]]*//; s/^[[:space:]]+//')
        local agent="$tangle_coding_agent"
        local role="implementer"
        local pane_icon="⚙️"
        if [[ "$subtask" =~ \[REASONING\] ]]; then
            agent="$tangle_reasoning_agent"
            role="researcher"
            pane_icon="🧠"
        fi
        subtask=$(echo "$subtask" | sed 's/\[CODING\]\s*//; s/\[REASONING\]\s*//')
        local task_id="tangle-${task_group}-${subtask_num}"
        local pane_title="$pane_icon Subtask $((subtask_num+1))"
        local subtask_prompt
        subtask_prompt=$(build_tangle_subtask_prompt "$resolved_prompt" "$subtask")
        local active_idx="${#OCTOPUS_ACTIVE_TANGLE_TASK_IDS[@]}"
        OCTOPUS_ACTIVE_TANGLE_PIDS+=("")
        OCTOPUS_ACTIVE_TANGLE_AGENTS+=("$agent")
        OCTOPUS_ACTIVE_TANGLE_TASK_IDS+=("$task_id")

        # Tangle uses the legacy spawn path in this parallel loop so .done
        # markers are written for the completion watcher. This also allows
        # configurable CLI-backed coding/reasoning agents without requiring
        # Claude Agent Teams hooks in the host process.
        if [[ "$TMUX_MODE" == "true" ]]; then
            # Use async+tmux spawning
            local pid
            if ! pid=$(spawn_agent_async "$agent" "$subtask_prompt" "$task_id" "$role" "tangle" "$pane_title"); then
                log ERROR "Failed to spawn Tangle task $task_id"
                octopus_tangle_cancel_active TERM
                _octopus_tangle_restore_traps "$tangle_previous_int_trap" "$tangle_previous_term_trap"
                return 1
            fi
            pids+=("$pid")
        else
            # Standard spawning
            local pid
            if ! pid=$(spawn_agent_capture_pid "$agent" "$subtask_prompt" "$task_id" "$role" "tangle"); then
                log ERROR "Failed to spawn Tangle task $task_id"
                octopus_tangle_cancel_active TERM
                _octopus_tangle_restore_traps "$tangle_previous_int_trap" "$tangle_previous_term_trap"
                return 1
            fi
            pids+=("$pid")
        fi
        OCTOPUS_ACTIVE_TANGLE_PIDS[$active_idx]="$pid"
        task_ids+=("$task_id")
        ((subtask_num++)) || true
    done
    fleet_dispatch_end

    # Future-proof fail-closed guard: the current loop increments once per
    # retained line, but this catches any later continue/break/error path before
    # quality gates can validate a partial dispatch as a complete tangle run.
    if [[ $subtask_num -ne ${#subtask_lines[@]} ]]; then
        log ERROR "Spawned $subtask_num development threads for ${#subtask_lines[@]} parsed subtasks; refusing partial tangle execution"
        octopus_tangle_cancel_active TERM
        _octopus_tangle_restore_traps "$tangle_previous_int_trap" "$tangle_previous_term_trap"
        return 1
    fi

    log INFO "Spawned $subtask_num development threads"

    # Wait with progress monitoring — poll .done marker files written by spawn_agent
    # rather than kill -0 $pid (which tracks wrapper PID, not provider PID)
    local _done_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents"
    local _tangle_max_wait="${OCTOPUS_TANGLE_DEADLINE:-0}"
    [[ "$_tangle_max_wait" =~ ^[0-9]+$ ]] || _tangle_max_wait=0
    local _missing_marker_grace="${OCTOPUS_TANGLE_MISSING_MARKER_GRACE:-180}"
    [[ "$_missing_marker_grace" =~ ^[0-9]+$ ]] || _missing_marker_grace=180
    local _deadline=0
    if [[ "$_tangle_max_wait" -gt 0 ]]; then
        _deadline=$(( $(date +%s) + _tangle_max_wait ))
    fi
    local completed=0
    local _failed_tasks=()
    local _terminal_task_ids=""
    local _missing_marker_since=()
    local _last_progress=-1
    while [[ $completed -lt ${#task_ids[@]} ]]; do
        completed=0
        for i in "${!task_ids[@]}"; do
            local _done_file="${_done_dir}/${task_ids[$i]}.done"
            if [[ -f "$_done_file" ]]; then
                ((completed++)) || true
            elif [[ " $_terminal_task_ids " == *" ${task_ids[$i]} "* ]]; then
                ((completed++)) || true
            else
                local _worker_pid="${pids[$i]:-}"
                if [[ "$_tangle_max_wait" -gt 0 ]] && (( $(date +%s) > _deadline )); then
                    log WARN "Thread ${task_ids[$i]} deadline exceeded — killing and marking timeout"
                    if [[ -n "$_worker_pid" ]]; then
                        review_kill_process_tree_frozen "$_worker_pid"
                        wait "$_worker_pid" 2>/dev/null || true
                    fi
                    mkdir -p "$_done_dir" 2>/dev/null || true
                    if [[ ! -f "$_done_file" ]] && ! echo "timeout" > "$_done_file" 2>/dev/null; then
                        log WARN "Failed to write timeout marker for ${task_ids[$i]} at $_done_file"
                    fi
                    [[ " $_terminal_task_ids " == *" ${task_ids[$i]} "* ]] || _terminal_task_ids="${_terminal_task_ids:+$_terminal_task_ids }${task_ids[$i]}"
                elif [[ -n "$_worker_pid" ]] && ! tangle_process_is_active_non_zombie "$_worker_pid"; then
                    local _now
                    _now=$(date +%s)
                    if [[ -z "${_missing_marker_since[$i]:-}" ]]; then
                        _missing_marker_since[$i]="$_now"
                        log WARN "Thread ${task_ids[$i]} wrapper exited without completion marker; exited or became zombie without completion marker — waiting up to ${_missing_marker_grace}s for late result/marker"
                    elif (( _now - ${_missing_marker_since[$i]} >= _missing_marker_grace )); then
                        log WARN "Thread ${task_ids[$i]} still lacks completion marker after ${_missing_marker_grace}s — marking failed"
                        mkdir -p "$_done_dir" 2>/dev/null || true
                        if [[ ! -f "$_done_file" ]] && ! echo "missing-done-marker" > "$_done_file" 2>/dev/null; then
                            log WARN "Failed to write missing-done marker for ${task_ids[$i]} at $_done_file"
                        fi
                        [[ " $_terminal_task_ids " == *" ${task_ids[$i]} "* ]] || _terminal_task_ids="${_terminal_task_ids:+$_terminal_task_ids }${task_ids[$i]}"
                        local _result_file
                        _result_file=$(find "${RESULTS_DIR:-${HOME}/.claude-octopus/results}" -maxdepth 1 -type f -name "*-${task_ids[$i]}.md" 2>/dev/null | head -1 || true)
                        if [[ -n "$_result_file" ]]; then
                            local _status_count
                            _status_count=$(grep -c '^## Status:' "$_result_file" 2>/dev/null || true)
                            if [[ "${_status_count:-0}" -eq 0 ]]; then
                                {
                                    echo ""
                                    echo "## Status: FAILED (Missing completion marker)"
                                    echo "# Completed: $(date)"
                                } >> "$_result_file" 2>/dev/null || true
                            fi
                        fi
                    fi
                fi
            fi
        done
        if [[ -t 1 ]]; then
            echo -ne "\r${CYAN}Progress: $completed/${#task_ids[@]} subtasks complete${NC}"
        elif [[ "$completed" -ne "$_last_progress" ]]; then
            echo "Progress: $completed/${#task_ids[@]} subtasks complete"
        fi
        _last_progress="$completed"
        [[ $completed -ge ${#task_ids[@]} ]] || sleep 2
    done
    [[ -t 1 ]] && echo ""

    # Final artifact reconciliation: providers can write the result and .done
    # marker after the wrapper PID disappears. Trust a latest SUCCESS status
    # before reporting failures or entering the quality gate.
    for i in "${!task_ids[@]}"; do
        local _done_file="${_done_dir}/${task_ids[$i]}.done"
        local _exit_val
        _exit_val=$(cat "$_done_file" 2>/dev/null || echo "")
        if [[ "$_exit_val" != "0" ]]; then
            local _result_file=""
            _result_file=$(find "${RESULTS_DIR:-${HOME}/.claude-octopus/results}" -maxdepth 1 -type f -name "*-${task_ids[$i]}.md" 2>/dev/null | head -1 || true)
            if [[ -n "$_result_file" ]]; then
                local _latest_status=""
                _latest_status=$(grep '^## Status:' "$_result_file" 2>/dev/null | tail -1 || true)
                if [[ "$_latest_status" == *SUCCESS* ]]; then
                    mkdir -p "$_done_dir" 2>/dev/null || true
                    echo "0" > "$_done_file" 2>/dev/null || true
                    log INFO "Reconciled late successful result for ${task_ids[$i]} before quality gate"
                fi
            fi
        fi
    done

    # Report any failed subtasks
    for i in "${!task_ids[@]}"; do
        local _done_file="${_done_dir}/${task_ids[$i]}.done"
        local _exit_val
        _exit_val=$(cat "$_done_file" 2>/dev/null || echo "unknown")
        if [[ "$_exit_val" != "0" ]]; then
            log WARN "Subtask ${task_ids[$i]} finished with status: $_exit_val"
            _failed_tasks+=("${task_ids[$i]}")
        fi
    done
    [[ ${#_failed_tasks[@]} -gt 0 ]] && log WARN "${#_failed_tasks[@]}/${#task_ids[@]} subtasks failed: ${_failed_tasks[*]}"

    # Cleanup done markers
    for i in "${!task_ids[@]}"; do
        rm -f "${_done_dir}/${task_ids[$i]}.done" 2>/dev/null || true
    done

    # Cleanup tmux if enabled
    if [[ "$TMUX_MODE" == "true" ]]; then
        tmux_cleanup
    fi
    _octopus_tangle_restore_traps "$tangle_previous_int_trap" "$tangle_previous_term_trap"

    # v7.25.0: Record agent completion metrics
    if command -v record_agents_batch_complete &> /dev/null; then
        record_agents_batch_complete "tangle" "$task_group" 2>/dev/null || true
    fi

    # Step 3: Validation gate
    log INFO "Step 3: Validation gate..."
    local validation_file="${RESULTS_DIR:-${HOME}/.claude-octopus/results}/tangle-validation-${task_group}.md"
    local validation_rc=0
    validate_tangle_results "$task_group" "$resolved_prompt" "$worktree_before_file" || validation_rc=$?

    if ! tangle_should_attempt_contextual_review "$validation_rc" "$worktree_before_state_file"; then
        log ERROR "Tangle validation failed with status ${validation_rc}; no recoverable worktree progress detected, stopping before contextual review and corrections"
        return "$validation_rc"
    fi
    if [[ "$validation_rc" -ne 0 ]]; then
        log WARN "Tangle validation failed with status ${validation_rc}, but recoverable worktree progress exists; entering contextual review/correction recovery"
    fi

    tangle_contextual_review_gate "$task_group" "$resolved_prompt" "$context" "$subtasks" \
        "$validation_file" "$worktree_before_file" "$validation_rc" "$tangle_coding_agent"
    return $?
}

# Decide whether contextual review is useful after the initial validation gate.
# A normal validation pass always continues to the existing review path. A failed
# validation only enters recovery when Tangle produced new worktree changes since
# its pre-run snapshot; otherwise preserve the historical fail-fast behavior.
tangle_should_attempt_contextual_review() {
    local validation_rc="${1:-0}"
    local worktree_before_state_file="${2:-}"

    if [[ "$validation_rc" -eq 0 ]]; then
        return 0
    fi
    [[ -n "$worktree_before_state_file" && -f "$worktree_before_state_file" ]] || return 1
    type snapshot_tangle_worktree_state >/dev/null 2>&1 || return 1

    local worktree_after_state_file=""
    worktree_after_state_file=$(mktemp "${TMPDIR:-/tmp}/octo-tangle-worktree-state-after.XXXXXX") || return 1
    snapshot_tangle_worktree_state > "$worktree_after_state_file" 2>/dev/null || true
    if cmp -s "$worktree_before_state_file" "$worktree_after_state_file"; then
        rm -f "$worktree_after_state_file"
        return 1
    fi
    rm -f "$worktree_after_state_file"
    return 0
}

# Contextual review gate + correction loop for tangle_develop. Extracted so
# round accounting, the convergence guard, and the absolute round ceiling are
# unit-testable with stubbed review/correction functions
# (tests/unit/test-tangle-correction-loop-behavior.sh).
tangle_contextual_review_gate() {
    local task_group="$1"
    local resolved_prompt="$2"
    local context="$3"
    local subtasks="$4"
    local validation_file="$5"
    local worktree_before_file="$6"
    local validation_rc="${7:-0}"
    local tangle_coding_agent="${8:-codex}"

    if octo_bool_disabled "${OCTOPUS_TANGLE_CODE_REVIEW:-true}"; then
        log INFO "Contextual code review disabled by OCTOPUS_TANGLE_CODE_REVIEW"
        return "$validation_rc"
    fi

    local review_context_file
    review_context_file=$(tangle_build_develop_review_context "$task_group" "$resolved_prompt" "$context" "$subtasks" "$validation_file" "$worktree_before_file" "initial")

    local review_rc=0
    tangle_run_context_code_review "$task_group" "$review_context_file" "initial" || review_rc=$?
    local findings_file="$TANGLE_REVIEW_FINDINGS_FILE"
    local normal_count
    normal_count=$(tangle_review_blocking_count "$findings_file")

    local correction_mode="${OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE:-unbounded}"
    local max_correction_rounds="${OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS:-0}"
    [[ "$max_correction_rounds" =~ ^[0-9]+$ ]] || max_correction_rounds=0
    if [[ "$correction_mode" == "bounded" && "$max_correction_rounds" -eq 0 ]]; then
        log WARN "OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=bounded with no OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS set — defaulting to 1 round"
        max_correction_rounds=1
    fi
    local correction_round=1
    local previous_normal_count="$normal_count"
    local previous_signature
    previous_signature=$(tangle_findings_signature "$findings_file")
    local previous_finding_keys
    previous_finding_keys=$(tangle_normal_finding_keys "$findings_file")
    local previous_validation_signature
    previous_validation_signature=$(tangle_validation_signature "$validation_file")
    local best_normal_count="$normal_count"
    local no_progress_rounds=0
    local convergence_round_limit="${OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS:-3}"
    # Validation files are re-rendered each correction round and can change even
    # when the actionable gate is static. By default, only a new best blocker
    # count resets convergence; validation signature movement is diagnostic only.
    local validation_progress_resets_convergence="${OCTOPUS_TANGLE_CONVERGENCE_VALIDATION_PROGRESS:-false}"
    local correction_strategy="delta"
    # Absolute ceiling on correction rounds. Each round dispatches paid provider
    # calls, so even the default unbounded mode stops here; the stall watchdog
    # and convergence guard remain the primary stops. Setting the ceiling to 0
    # is an explicit opt-in to a truly unbounded loop.
    local hard_round_cap="${OCTOPUS_TANGLE_CORRECTION_HARD_CAP:-10}"
    [[ "$hard_round_cap" =~ ^[0-9]+$ ]] || hard_round_cap=10

    while [[ "${normal_count:-0}" -gt 0 ]]; do
        if [[ "$correction_mode" == "bounded" && "$max_correction_rounds" -gt 0 && "$correction_round" -gt "$max_correction_rounds" ]]; then
            log WARN "Contextual code review still has ${normal_count} blocking finding(s) after bounded ${max_correction_rounds} correction round(s): ${findings_file}"
            return 1
        fi

        if [[ "$hard_round_cap" -gt 0 && "$correction_round" -gt "$hard_round_cap" ]]; then
            log ERROR "Correction loop hit the absolute round ceiling (${hard_round_cap}) with ${normal_count} blocking finding(s) remaining: ${findings_file} — raise or disable with OCTOPUS_TANGLE_CORRECTION_HARD_CAP (0 = no ceiling)"
            return 1
        fi

        local correction_rc=0
        tangle_apply_review_corrections "$resolved_prompt" "$review_context_file" "$findings_file" "$correction_round" "$tangle_coding_agent" "$correction_strategy" || correction_rc=$?
        if [[ "$correction_rc" -ne 0 ]]; then
            if [[ "${TANGLE_CORRECTION_STATUS:-}" == "failed-no-progress" && "${TANGLE_CORRECTION_CHANGED:-0}" != "1" ]]; then
                no_progress_rounds=$((no_progress_rounds + 1))
                correction_strategy="single-finding"
                log WARN "Correction round ${correction_round} made no observable worktree progress (${no_progress_rounds}/${convergence_round_limit}); retrying under convergence policy"
                if [[ "${convergence_round_limit:-0}" -gt 0 && "$no_progress_rounds" -ge "$convergence_round_limit" ]]; then
                    log ERROR "Stopping tangle correction loop after ${no_progress_rounds} consecutive failed-no-progress rounds"
                    return 1
                fi
                ((correction_round++)) || true
                continue
            fi
            log WARN "Correction round ${correction_round} failed with terminal status=${TANGLE_CORRECTION_STATUS:-unknown}; stopping correction loop"
            return "$correction_rc"
        fi

        if [[ -n "${TANGLE_CORRECTION_CONTAMINATION:-}" ]]; then
            log WARN "Correction round ${correction_round} created out-of-scope/scratch files:"
            printf '%s\n' "$TANGLE_CORRECTION_CONTAMINATION" | while IFS= read -r _contam; do
                [[ -n "$_contam" ]] && log WARN "  $_contam"
            done
            correction_strategy="cleanup-and-fix"
        fi

        log INFO "Re-running validation gate after correction round ${correction_round} (status=${TANGLE_CORRECTION_STATUS}, changed=${TANGLE_CORRECTION_CHANGED})..."
        validation_rc=0
        OCTOPUS_TANGLE_VALIDATION_CORRECTION_FILE="${TANGLE_CORRECTION_FILE:-}" \
        OCTOPUS_TANGLE_VALIDATION_CORRECTION_ROUND="$correction_round" \
        OCTOPUS_TANGLE_VALIDATION_CORRECTION_STATUS="${TANGLE_CORRECTION_STATUS:-}" \
        OCTOPUS_TANGLE_VALIDATION_CORRECTION_CHANGED="${TANGLE_CORRECTION_CHANGED:-0}" \
            validate_tangle_results "$task_group" "$resolved_prompt" "$worktree_before_file" || validation_rc=$?

        review_context_file=$(tangle_build_develop_review_context "$task_group" "$resolved_prompt" "$context" "$subtasks" "$validation_file" "$worktree_before_file" "correction-${correction_round}")
        review_rc=0
        tangle_run_context_code_review "$task_group" "$review_context_file" "correction-${correction_round}" || review_rc=$?
        findings_file="$TANGLE_REVIEW_FINDINGS_FILE"
        normal_count=$(tangle_review_blocking_count "$findings_file")
        local current_signature
        current_signature=$(tangle_findings_signature "$findings_file")
        local current_finding_keys
        current_finding_keys=$(tangle_normal_finding_keys "$findings_file")

        if [[ "$review_rc" -ne 0 ]]; then
            if [[ "${normal_count:-0}" -gt 0 ]]; then
                log WARN "Contextual code review returned non-zero after correction round ${correction_round}, but ${normal_count} actionable blocking finding(s) remain; continuing correction loop"
            else
                log WARN "Contextual code review returned non-zero after correction round ${correction_round} with no actionable blockers"
                return "$review_rc"
            fi
        fi

        if [[ "${normal_count:-0}" -lt "${previous_normal_count:-0}" ]]; then
            log INFO "Correction round ${correction_round} improved blockers: ${previous_normal_count} -> ${normal_count}"
            correction_strategy="delta"
        elif [[ "${normal_count:-0}" -gt "${previous_normal_count:-0}" ]]; then
            log WARN "Correction round ${correction_round} worsened blockers: ${previous_normal_count} -> ${normal_count}; switching strategy"
            correction_strategy="single-finding"
        else
            if [[ "$current_signature" == "$previous_signature" ]]; then
                log WARN "Correction round ${correction_round} repeated the same blocking findings; switching strategy"
            else
                log WARN "Correction round ${correction_round} did not reduce blocker count (${normal_count}); switching strategy"
            fi
            correction_strategy="single-finding"
        fi

        local current_validation_signature
        current_validation_signature=$(tangle_validation_signature "$validation_file")
        local made_progress=0
        local resolved_finding_count=0
        resolved_finding_count=$(tangle_resolved_finding_count "$previous_finding_keys" "$current_finding_keys")
        if [[ "${normal_count:-0}" -lt "${best_normal_count:-0}" ]]; then
            best_normal_count="$normal_count"
            made_progress=1
        fi
        if [[ "${resolved_finding_count:-0}" -gt 0 ]]; then
            made_progress=1
            log INFO "Correction round ${correction_round} resolved ${resolved_finding_count} blocker identity/identities from the previous review; resetting convergence guard"
        fi
        if [[ "$current_validation_signature" != "$previous_validation_signature" ]]; then
            if octo_bool_enabled "$validation_progress_resets_convergence"; then
                made_progress=1
            else
                log INFO "Correction round ${correction_round}: validation signature changed but blocker best did not improve; not resetting convergence guard"
            fi
        fi

        if [[ "$made_progress" -eq 1 ]]; then
            no_progress_rounds=0
        else
            no_progress_rounds=$((no_progress_rounds + 1))
            log WARN "Correction round ${correction_round} did not improve best blockers (${no_progress_rounds}/${convergence_round_limit})"
        fi

        if [[ "${TANGLE_CORRECTION_CHANGED:-0}" != "1" && "${TANGLE_CORRECTION_STATUS:-}" == *"stalled"* ]]; then
            log WARN "Correction stalled without partial writes; stopping to avoid a no-progress loop"
            return 1
        fi

        if [[ "${convergence_round_limit:-0}" -gt 0 && "$no_progress_rounds" -ge "$convergence_round_limit" ]]; then
            log ERROR "Stopping tangle correction loop after ${no_progress_rounds} rounds without new best blockers (best_normal=${best_normal_count}, current_normal=${normal_count})"
            return 1
        fi

        previous_normal_count="$normal_count"
        previous_signature="$current_signature"
        previous_finding_keys="$current_finding_keys"
        previous_validation_signature="$current_validation_signature"
        ((correction_round++)) || true
    done

    if [[ "${normal_count:-0}" -gt 0 ]]; then
        log WARN "Contextual code review still has ${normal_count} blocking finding(s): ${findings_file}"
        return 1
    fi

    if [[ "$review_rc" -ne 0 ]]; then
        log WARN "Contextual code review returned non-zero despite zero blocking findings"
        return "$review_rc"
    fi

    if [[ "$validation_rc" -ne 0 ]]; then
        log WARN "Skipping ink/deliver because tangle validation gate returned non-zero (${validation_rc})"
        return "$validation_rc"
    fi

    if octo_bool_enabled "${OCTOPUS_TANGLE_INK:-false}"; then
        log INFO "OCTOPUS_TANGLE_INK enabled — running ink/deliver after contextual review passed"
        ink_deliver "$resolved_prompt"
    fi

    return 0
}

ink_delivery_sanitize_context() {
    sed -e 's/\[Synthesis failed - raw results attached\]/[Upstream phase synthesis failed; raw fallback omitted from compact delivery context]/g'
}

ink_delivery_file_label() {
    local file="$1"
    local base
    base=$(basename "$file")

    case "$base" in
        probe-synthesis-*) echo "Probe Synthesis" ;;
        grasp-consensus-*) echo "Grasp Consensus" ;;
        tangle-validation-*) echo "Tangle Validation" ;;
        *aggregate*) echo "Aggregate Result" ;;
        *) echo "Supporting Result" ;;
    esac
}

ink_delivery_append_excerpt() {
    local file="$1"
    local max_chars="$2"
    local label
    local size

    [[ -f "$file" ]] || return 0
    label=$(ink_delivery_file_label "$file")
    size=$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')
    size="${size:-0}"

    echo "## Source: ${label}"
    echo "- File: ${file}"
    echo "- Size: ${size} bytes"
    if [[ "$size" =~ ^[0-9]+$ && "$size" -gt "$max_chars" ]]; then
        echo "- Included: first ${max_chars} bytes (truncated)"
    else
        echo "- Included: full file"
    fi
    echo ""
    echo '```markdown'
    if [[ "$size" =~ ^[0-9]+$ && "$size" -gt "$max_chars" ]]; then
        head -c "$max_chars" "$file" 2>/dev/null | ink_delivery_sanitize_context
        echo ""
        echo "[... truncated by ink delivery context: original ${size} bytes, included ${max_chars} bytes ...]"
    else
        ink_delivery_sanitize_context < "$file"
    fi
    echo '```'
    echo ""
}

build_ink_delivery_context() {
    local tangle_results="${1:-}"
    local max_file="${OCTOPUS_INK_FILE_CONTEXT_CHARS:-12000}"
    local max_total="${OCTOPUS_INK_CONTEXT_CHARS:-60000}"

    [[ "$max_file" =~ ^[0-9]+$ ]] || max_file=12000
    [[ "$max_total" =~ ^[0-9]+$ ]] || max_total=60000
    max_file=$((10#$max_file))
    max_total=$((10#$max_total))
    [[ "$max_file" -lt 1000 ]] && max_file=1000
    [[ "$max_total" -lt 4000 ]] && max_total=4000

    local -a files=()
    local seen="|"
    local candidate

    for candidate in \
        "$tangle_results" \
        "$(ls -t "$RESULTS_DIR"/tangle-validation-*.md 2>/dev/null | head -1)" \
        "$(ls -t "$RESULTS_DIR"/grasp-consensus-*.md 2>/dev/null | head -1)" \
        "$(ls -t "$RESULTS_DIR"/probe-synthesis-*.md 2>/dev/null | head -1)"; do
        [[ -n "$candidate" && -f "$candidate" ]] || continue
        if [[ "$seen" != *"|$candidate|"* ]]; then
            files+=("$candidate")
            seen="${seen}${candidate}|"
        fi
    done

    for candidate in "$RESULTS_DIR"/*.md; do
        [[ -f "$candidate" ]] || continue
        [[ "$candidate" == *aggregate* || "$candidate" == *delivery* ]] && continue
        [[ "$seen" == *"|$candidate|"* ]] && continue
        files+=("$candidate")
        seen="${seen}${candidate}|"
        [[ ${#files[@]} -ge 10 ]] && break
    done

    local tmp_context
    tmp_context=$(mktemp "${TMPDIR:-/tmp}/octo-ink-context.XXXXXX") || return 1

    {
        echo "# Compact Delivery Context"
        echo ""
        echo "This context is bounded before synthesis. Full raw artifacts remain on disk in RESULTS_DIR."
        echo ""
        echo "## Context Budget"
        echo "- Max per source file: ${max_file} bytes"
        echo "- Max total context: ${max_total} bytes"
        echo "- Source files selected: ${#files[@]}"
        echo ""

        for candidate in "${files[@]}"; do
            ink_delivery_append_excerpt "$candidate" "$max_file"
        done
    } > "$tmp_context"

    local total_size
    total_size=$(wc -c < "$tmp_context" 2>/dev/null | tr -d '[:space:]')
    total_size="${total_size:-0}"

    if [[ "$total_size" =~ ^[0-9]+$ && "$total_size" -gt "$max_total" ]]; then
        head -c "$max_total" "$tmp_context" 2>/dev/null
        echo ""
        echo ""
        echo "[... compact delivery context truncated: original ${total_size} bytes, included ${max_total} bytes ...]"
    else
        cat "$tmp_context"
    fi

    rm -f "$tmp_context"
}

build_ink_fallback_delivery() {
    local prompt="$1"
    local sonnet_review="$2"
    local compact_context="$3"

    cat <<EOF
Automated synthesis unavailable.

## Executive Summary
The delivery phase completed local checks, but the synthesis provider did not return a polished final narrative. This fallback is intentionally compact and does not attach raw phase artifacts.

## Key Deliverables
- Compact delivery context assembled from phase artifacts.
- Quality review retained below when available.
- Full raw artifacts remain available in RESULTS_DIR for manual inspection.

## Quality Review
${sonnet_review}

## Compact Source Context
${compact_context}
EOF
}

# Phase 4: INK (Deliver) - Quality gates + final output
# The octopus inks the final solution with precision
ink_deliver() {
    local prompt="$1"
    local tangle_results="${2:-}"
    local task_group
    task_group=$(date +%s)

    echo ""
    octopus_phase_banner "DELIVER (Phase 4/4)" "Final Quality Gates" "$MAGENTA"
    echo ""

    log INFO "Phase 4: Finalizing delivery with quality checks"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would ink: $prompt"
        log INFO "[DRY-RUN] Would synthesize and deliver final output"
        return 0
    fi

    # Cost transparency (v7.18.0 - P0.0)
    if ! display_workflow_cost_estimate "Ink (Deliver Phase)" 1 2 1500; then
        log "WARN" "Workflow cancelled by user after cost review"
        return 1
    fi

    if declare -F begin_progress_phase >/dev/null 2>&1; then
        begin_progress_phase "deliver"
    fi

    mkdir -p "$RESULTS_DIR"

    # Step 1: Pre-delivery quality checks
    log INFO "Step 1: Running quality checks..."

    local checks_passed=true

    # Check 1: Results exist
    if [[ -z "$(ls -A "$RESULTS_DIR"/*.md 2>/dev/null)" ]]; then
        log ERROR "No results found. Cannot deliver."
        return 1
    fi

    # Check 2: No critical failures from tangle phase
    if [[ -n "$tangle_results" && -f "$tangle_results" ]]; then
        if grep -q "Quality Gate: FAILED" "$tangle_results" 2>/dev/null; then
            log WARN "Development phase has failed quality gate. Proceeding with caution."
            checks_passed=false
        fi

        # v8.18.0: Run retrospective on quality gate failure
        retrospective_ceremony "$prompt" "Quality gate FAILED in tangle phase"
    fi

    # Step 2: Synthesize final output
    log INFO "Step 2: Synthesizing final deliverable..."

    local all_results
    all_results=$(build_ink_delivery_context "$tangle_results")
    local result_count
    result_count=$(grep -c '^## Source:' <<< "$all_results" 2>/dev/null || true)
    result_count="${result_count:-0}"

    # Sonnet 5 quality review before synthesis
    log INFO "Step 2a: Sonnet 5 quality review..."
    local sonnet_review ink_review_timeout
    ink_review_timeout="${OCTOPUS_INK_REVIEW_TIMEOUT:-0}"
    [[ "$ink_review_timeout" =~ ^[0-9]+$ ]] || ink_review_timeout=0
    sonnet_review=$(run_agent_sync "claude-sonnet" "Review these development results for quality, completeness, and correctness.
Flag any issues, gaps, or improvements needed.
Rate each dimension explicitly as 'Security: N/10', 'Reliability: N/10', 'Performance: N/10', 'Accessibility: N/10'.

Original task: $prompt

Results:
$all_results" "$ink_review_timeout" "code-reviewer" "ink") || {
        sonnet_review="[Quality review unavailable]"
    }

    # v8.19.0: Cross-model review scoring (4x10)
    local review_scores
    review_scores=$(score_cross_model_review "$sonnet_review")
    local rev_sec rev_rel rev_perf rev_acc
    IFS=':' read -r rev_sec rev_rel rev_perf rev_acc <<< "$review_scores"

    echo ""
    format_review_scorecard "$rev_sec" "$rev_rel" "$rev_perf" "$rev_acc"
    echo ""

    # Record scorecard via structured decision
    write_structured_decision \
        "quality-gate" \
        "ink_deliver/cross-model-review" \
        "Review scorecard: sec=${rev_sec} rel=${rev_rel} perf=${rev_perf} acc=${rev_acc}" \
        "ink-delivery" \
        "high" \
        "4x10 cross-model review scores" \
        "" 2>/dev/null || true

    # v8.19.0: Strict 4x10 gate (when enabled)
    if [[ "$OCTOPUS_REVIEW_4X10" == "true" ]]; then
        if [[ "$rev_sec" -lt 10 || "$rev_rel" -lt 10 || "$rev_perf" -lt 10 || "$rev_acc" -lt 10 ]]; then
            log ERROR "4x10 gate FAILED: all dimensions must be 10/10 (sec=$rev_sec rel=$rev_rel perf=$rev_perf acc=$rev_acc)"
            write_structured_decision \
                "quality-gate" \
                "ink_deliver/4x10-gate" \
                "4x10 gate FAILED: sec=${rev_sec} rel=${rev_rel} perf=${rev_perf} acc=${rev_acc}" \
                "ink-delivery" \
                "high" \
                "Strict 4x10 gate requires all dimensions at 10/10" \
                "" 2>/dev/null || true
            return 1
        fi
        log INFO "4x10 gate PASSED: all dimensions at 10/10"
    fi

    # v8.29.0: Code simplification pass — identify over-engineering
    if [[ "$SUPPORTS_BATCH_COMMAND" == "true" ]]; then
        log "INFO" "Running simplification review..."
        local simplify_prompt="Review the following code changes for unnecessary complexity. Identify:
1. Premature abstractions (helpers/utilities used only once)
2. Over-engineered error handling for impossible scenarios
3. Unnecessary indirection or wrapper layers
4. Code that could be simplified without losing functionality
Be specific — list files and line numbers. If the code is already clean, say so.

Code to review:
${all_results}"
        local simplify_result
        simplify_result=$(OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="ink-review-watchdog" run_agent_sync "claude-sonnet" "$simplify_prompt" 0 "code-reviewer" "ink") || true
        if [[ -n "$simplify_result" ]]; then
            if [[ ${#simplify_result} -gt 12000 ]]; then
                simplify_result="${simplify_result:0:12000}

[... simplification review truncated to 12000 chars ...]"
            fi
            all_results="${all_results}

--- SIMPLIFICATION REVIEW ---
${simplify_result}"
        fi
    fi

    local synthesis_prompt="Create a polished final deliverable from these development results.

Structure the output as:
1. Executive Summary (2-3 sentences)
2. Key Deliverables (what was produced)
3. Implementation Details (technical specifics)
4. Next Steps / Recommendations
5. Known Limitations

Original task: $prompt

Quality Review (from Sonnet 5):
$sonnet_review

Compact source context to synthesize:
$all_results"

    local delivery
    if octo_provider_allowed agy && command -v agy >/dev/null 2>&1; then
        if ! delivery=$(OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="ink-delivery-watchdog" run_agent_sync "agy" "$synthesis_prompt" 0 "synthesizer" "ink") || \
            [[ ! "$delivery" =~ [^[:space:]] ]]; then
            log WARN "Antigravity (agy) returned no usable delivery; using bounded fallback synthesis"
            delivery=$(build_ink_fallback_delivery "$prompt" "$sonnet_review" "$all_results")
        fi
    else
        log WARN "Antigravity (agy) unavailable or not allowed, using fallback delivery synthesis"
        delivery=$(build_ink_fallback_delivery "$prompt" "$sonnet_review" "$all_results")
    fi

    # Step 3: Generate final document
    local delivery_file="${RESULTS_DIR}/delivery-${task_group}.md"

    cat > "$delivery_file" << EOF
# DELIVERY DOCUMENT
## Task: $prompt
## Generated: $(date)
## Status: $([[ "$checks_passed" == "true" ]] && echo "COMPLETE" || echo "PARTIAL - Review Required")

---

$delivery

---

## Quality Certification
- Pre-delivery checks: $([[ "$checks_passed" == "true" ]] && echo "PASSED" || echo "NEEDS REVIEW")
- Results synthesized: $result_count compact source files
- Context policy: bounded excerpts; raw phase artifacts are not embedded on synthesis failure
- Generated by: Claude Octopus Double Diamond
- Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    log INFO "Delivery document: $delivery_file"
    echo ""
    octopus_complete "Delivery"
    echo -e "Final document: ${CYAN}$delivery_file${NC}"
    echo ""
}

# ── Extracted from orchestrate.sh ──
format_workflow_banner() {
    local workflow="$1"
    local description="$2"
    local phase_emoji="${3:-🐙}"

    if [[ "$OCTOPUS_COMPACT_BANNERS" == "true" ]]; then
        # Compact: 2 lines
        local providers=""
        command -v codex &>/dev/null && providers+="🔴"
        command -v agy &>/dev/null && providers+="🧭"
        [[ -n "${PERPLEXITY_API_KEY:-}" ]] && providers+="🟣"
        providers+="🔵"
        echo "🐙 ${workflow} — ${description} | ${providers}"
    else
        # Full: standard verbose banner (existing behavior, unchanged)
        echo "🐙 **CLAUDE OCTOPUS ACTIVATED** - ${workflow}"
        echo "${phase_emoji} ${description}"
    fi
}

# ── Embrace debate gates ────────────────────────────────────────────────
embrace_normalize_debate_gates() {
    local raw="${OCTOPUS_EMBRACE_DEBATE_GATES:-${EMBRACE_DEBATE_GATES:-none}}"
    raw=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')
    raw="${raw#-}"
    raw="${raw%-}"

    case "$raw" in
        ""|none|no|false|off|skip|skipped)
            printf '%s\n' "none"
            ;;
        define|define-develop|define-to-develop|first|one|single|yes|true|on)
            printf '%s\n' "define"
            ;;
        both|all|two|full)
            printf '%s\n' "both"
            ;;
        auto|if-disagreement|only-if-disagreement|disagreement|detected)
            printf '%s\n' "auto"
            ;;
        *)
            log WARN "Unknown OCTOPUS_EMBRACE_DEBATE_GATES='$raw'; treating as none"
            printf '%s\n' "none"
            ;;
    esac
}

embrace_debate_gate_requested() {
    local gate="$1"
    local requested
    requested=$(embrace_normalize_debate_gates)

    case "$requested:$gate" in
        define:define-develop|both:define-develop|both:develop-deliver)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

embrace_debate_gate() {
    local gate="$1"
    local prompt="$2"
    local context_file="${3:-}"
    local gate_slug title style focus expected_pattern
    local task_group="${OCTOPUS_TASK_GROUP:-$(date +%s)}"
    EMBRACE_DEBATE_GATE_OUTPUT=""

    case "$gate" in
        define|define-develop)
            gate_slug="define-develop"
            title="Define → Develop"
            style="adversarial"
            focus="Challenge the proposed approach before implementation. Identify blockers, weak assumptions, missing requirements, and alternatives dismissed too quickly."
            expected_pattern="${RESULTS_DIR}/grasp-consensus-*.md"
            ;;
        develop|develop-deliver)
            gate_slug="develop-deliver"
            title="Develop → Deliver"
            style="collaborative"
            focus="Review implementation readiness before delivery. Identify missing scope, unverified claims, quality gaps, regressions, and follow-up work that must not be hidden."
            expected_pattern="${RESULTS_DIR}/tangle-validation-*.md"
            ;;
        *)
            log ERROR "Unknown embrace debate gate: $gate"
            return 1
            ;;
    esac

    if [[ -z "$context_file" ]]; then
        context_file=$(ls -t $expected_pattern 2>/dev/null | head -1) || true
    fi
    if [[ -z "$context_file" || ! -f "$context_file" ]]; then
        log ERROR "Embrace debate gate '${gate_slug}' missing context artifact"
        echo -e "${RED:-}✗${NC:-} Debate gate ${title} cannot run: context artifact missing"
        return 1
    fi

    if ! declare -f run_agent_sync >/dev/null 2>&1; then
        log ERROR "Embrace debate gate '${gate_slug}' cannot run: run_agent_sync is unavailable"
        return 1
    fi

    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    echo ""
    echo -e "${CYAN:-}Debate gate: ${title} (${style})${NC:-}"
    echo ""

    local context_excerpt gate_prompt
    context_excerpt=$(head -c "${OCTOPUS_EMBRACE_GATE_CONTEXT_BYTES:-12000}" "$context_file" 2>/dev/null || true)
    gate_prompt="EMBRACE ${title} DEBATE GATE

Style: ${style}
Task: ${prompt}
Context artifact: ${context_file}

${focus}

Context excerpt:
${context_excerpt}

Return a concise gate review with:
1. Verdict: PROCEED, PROCEED_WITH_RISKS, REVISE, or STOP
2. Blocking issues, if any
3. Non-blocking risks
4. Concrete changes needed before the next phase
5. Evidence from the context artifact"

    local codex_view="" agy_view="" claude_view="" synthesis=""
    local codex_status="failed" agy_status="failed" claude_status="failed"
    local successful=0

    if codex_view=$(run_agent_sync "codex" "$gate_prompt" 120 "code-reviewer" "embrace-gate" 2>/dev/null); then
        if [[ -n "$codex_view" ]]; then
            codex_status="ok"
            successful=$((successful + 1))
        fi
    fi
    # Antigravity (agy) is the Google seat since the Gemini CLI sunset (#524)
    if octo_provider_allowed agy && command -v agy >/dev/null 2>&1; then
        if agy_view=$(run_agent_sync "agy" "$gate_prompt" 120 "researcher" "embrace-gate" 2>/dev/null); then
            if [[ -n "$agy_view" ]]; then
                agy_status="ok"
                successful=$((successful + 1))
            fi
        fi
    else
        agy_status="skipped"
    fi
    if claude_view=$(run_agent_sync "claude-sonnet" "$gate_prompt" 120 "code-reviewer" "embrace-gate" 2>/dev/null); then
        if [[ -n "$claude_view" ]]; then
            claude_status="ok"
            successful=$((successful + 1))
        fi
    fi

    if [[ "$successful" -eq 0 ]]; then
        log ERROR "Embrace debate gate '${gate_slug}' produced no provider output"
        echo -e "${RED:-}✗${NC:-} Debate gate ${title} produced no provider output"
        return 1
    fi

    local synthesis_prompt="Synthesize this Embrace ${title} debate gate.

Task: ${prompt}
Gate style: ${style}
Provider statuses: codex=${codex_status}, agy=${agy_status}, claude=${claude_status}

Codex:
${codex_view:-[no output]}

Antigravity (agy):
${agy_view:-[no output]}

Claude:
${claude_view:-[no output]}

Return:
1. Gate verdict
2. Required actions before next phase
3. Risks accepted if proceeding
4. Provider participation summary"

    synthesis=$(run_agent_sync "claude-sonnet" "$synthesis_prompt" 120 "synthesizer" "embrace-gate" 2>/dev/null) || true
    if [[ -z "$synthesis" ]]; then
        synthesis="Synthesis unavailable. Review provider outputs below before proceeding."
    fi

    local gate_file="${RESULTS_DIR}/embrace-gate-${gate_slug}-${task_group}.md"
    cat > "$gate_file" << EOF
# EMBRACE Debate Gate: ${title}

**Generated:** $(date)
**Task:** ${prompt}
**Style:** ${style}
**Context Artifact:** ${context_file}
**Provider Statuses:** codex=${codex_status}, agy=${agy_status}, claude=${claude_status}

---

## Synthesis

${synthesis}

---

## Provider Views

### Codex (${codex_status})

${codex_view:-No output.}

### Antigravity / agy (${agy_status})

${agy_view:-No output.}

### Claude (${claude_status})

${claude_view:-No output.}
EOF

    if declare -f save_session_checkpoint >/dev/null 2>&1; then
        save_session_checkpoint "debate-${gate_slug}" "completed" "$gate_file"
    fi
    if declare -f write_structured_decision >/dev/null 2>&1; then
        write_structured_decision \
            "debate-synthesis" \
            "embrace_debate_gate/${gate_slug}" \
            "Embrace debate gate completed: ${prompt:0:80}" \
            "" \
            "high" \
            "Provider statuses: codex=${codex_status}, agy=${agy_status}, claude=${claude_status}" \
            "" 2>/dev/null || true
    fi

    EMBRACE_DEBATE_GATE_OUTPUT="$gate_file"
    echo -e "${GREEN:-}✓${NC:-} Debate gate completed: $gate_file"
    return 0
}

# ── embrace_full_workflow (moved from orchestrate.sh v9.22.1) ──
embrace_full_workflow() {
    local prompt="$1"
    local task_group
    task_group=$(date +%s)
    local resume_from=""

    echo ""
    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    echo -e "${MAGENTA}║  ${GREEN}EMBRACE${MAGENTA} - Full 4-Phase Workflow                         ║${NC}"
    echo -e "${MAGENTA}║  Research → Define → Develop → Deliver                    ║${NC}"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""

    log INFO "Starting complete Double Diamond workflow"

    # v8.49.0: Clean up expired results from prior runs
    cleanup_old_results

    # v8.5: Show compact cost estimate in banner
    show_cost_estimate "embrace" "${#prompt}"

    # v8.48.0: Disable cron during long multi-phase workflows to prevent interference
    if [[ "$SUPPORTS_DISABLE_CRON_ENV" == "true" ]]; then
        export CLAUDE_CODE_DISABLE_CRON=1
        log DEBUG "Cron jobs disabled for embrace workflow duration"
    fi

    # v8.19.0: Cleanup expired checkpoints
    cleanup_expired_checkpoints 2>/dev/null || true

    # v8.18.0: Reset lockouts for new workflow
    reset_provider_lockouts

    # v8.19.0: Inject high-importance observations into workflow context
    # NOTE: Observations are VARIABLE content — appended after task prompt so that
    # the stable persona/skill prefix (injected later by spawn_agent) stays cacheable
    local high_obs
    high_obs=$(search_observations "" 7 2>/dev/null) || true
    if [[ -n "$high_obs" ]]; then
        local obs_ctx="${high_obs:0:1500}"
        prompt="${prompt}

---

## High-Importance Observations from Previous Sessions
${obs_ctx}"
        log DEBUG "Injected ${#obs_ctx} chars of high-importance observations"
    fi

    local requested_debate_gates
    requested_debate_gates=$(embrace_normalize_debate_gates)

    log INFO "Task: $prompt"
    log INFO "Autonomy mode: $AUTONOMY_MODE"
    log INFO "Requested debate gates: $requested_debate_gates"
    [[ "$LOOP_UNTIL_APPROVED" == "true" ]] && log INFO "Loop-until-approved: enabled"

    # v8.3: Export workflow phase for event-driven hooks (TeammateIdle, TaskCompleted)
    export OCTOPUS_WORKFLOW_PHASE="init"
    export OCTOPUS_WORKFLOW_TYPE="embrace"
    export OCTOPUS_TASK_GROUP="$task_group"
    export OCTOPUS_TOTAL_PHASES=4
    export OCTOPUS_COMPLETED_PHASES=0

    # v8.3: Write session state for hook handlers to read
    # v8.5: Enhanced with phase_tasks and agent_queue for hook integration
    _write_embrace_session_state() {
        local phase="$1"
        local status="$2"
        local session_dir="${HOME}/.claude-octopus"
        local session_file="${HOME}/.claude-octopus/session.json"
        local session_tmp=""
        mkdir -p "$session_dir"
        if command -v jq &> /dev/null; then
            session_tmp=$(mktemp "${session_file}.tmp.XXXXXX") || return 0
            if jq -n \
                --arg phase "$phase" \
                --arg status "$status" \
                --arg workflow "embrace" \
                --arg host_session_id "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION:-}}}" \
                --arg group "$task_group" \
                --arg autonomy "$AUTONOMY_MODE" \
                --argjson completed "$OCTOPUS_COMPLETED_PHASES" \
                --argjson total "$OCTOPUS_TOTAL_PHASES" \
                '{workflow: $workflow, host_session_id: $host_session_id, current_phase: $phase, phase_status: $status,
                  task_group: $group, autonomy_mode: $autonomy,
                  completed_phases: $completed, total_phases: $total,
                  phase_map: {probe: "grasp", grasp: "tangle", tangle: "ink", ink: "complete"},
                  phase_tasks: {total: 0, completed: 0},
                  agent_queue: [],
                  quality_gates: {passed: false, failed: false},
                  updated_at: now | todate}' \
                > "$session_tmp" 2>/dev/null &&
               mv "$session_tmp" "$session_file" 2>/dev/null; then
                :
            else
                rm -f "$session_tmp"
            fi
        fi
    }

    _latest_embrace_output() {
        local pattern="$1"
        local latest
        latest=$(ls -t $pattern 2>/dev/null | head -1) || true
        [[ -n "$latest" && -f "$latest" ]] && printf '%s\n' "$latest"
    }

    _cleanup_embrace_exports() {
        unset OCTOPUS_SKIP_PHASE_COST_PROMPT
        unset OCTOPUS_WORKFLOW_PHASE
        unset OCTOPUS_WORKFLOW_TYPE
        unset OCTOPUS_TASK_GROUP
        unset OCTOPUS_TOTAL_PHASES
        unset OCTOPUS_COMPLETED_PHASES
        unset CLAUDE_CODE_DISABLE_CRON 2>/dev/null || true
    }

    _abort_embrace_phase() {
        local phase="$1"
        local reason="$2"
        local output="${3:-}"

        log ERROR "EMBRACE stopped at ${phase}: ${reason}"
        echo ""
        echo -e "${RED:-}${_BOX_TOP}${NC:-}"
        echo -e "${RED:-}║  EMBRACE stopped at ${phase}${NC:-}"
        echo -e "${RED:-}${_BOX_BOT}${NC:-}"
        echo -e "Reason: ${reason}"
        [[ -n "$output" ]] && echo -e "Output: ${output}"
        echo -e "Results: ${RESULTS_DIR}/"
        echo ""

        _write_embrace_session_state "$phase" "failed"
        save_session_checkpoint "$phase" "failed" "$output"
        handle_autonomy_checkpoint "$phase" "failed"
        _cleanup_embrace_exports
        return 1
    }

    _write_embrace_session_state "init" "starting"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would embrace: $prompt"
        log INFO "[DRY-RUN] Would run all 4 phases: probe → grasp → tangle → ink"
        return 0
    fi

    # Session recovery check
    if [[ "$RESUME_SESSION" == "true" ]] && check_resume_session; then
        resume_from=$(get_resume_phase)
        log INFO "Resuming from phase: $resume_from"
    else
        init_session "embrace" "$prompt"
    fi

    # Cost transparency (v7.18.0 - P0.0)
    # Display estimated costs and require user approval BEFORE execution
    if ! display_workflow_cost_estimate "Embrace (Full Double Diamond)" 4 4 2000; then
        log "WARN" "Workflow cancelled by user after cost review"
        return 1
    fi

    # Set flag to skip individual phase cost prompts (already shown above)
    export OCTOPUS_SKIP_PHASE_COST_PROMPT="true"

    # Pre-flight validation
    if ! preflight_check; then
        log ERROR "Pre-flight check failed. Aborting workflow."
        return 1
    fi

    local workflow_dir="${RESULTS_DIR}/embrace-${task_group}"
    mkdir -p "$workflow_dir"

    # Track timing
    local start_time=$SECONDS

    # ═══════════════════════════════════════════════════════════════════════════
    # v8.5: YAML RUNTIME DELEGATION
    # If YAML workflow file exists and runtime is enabled, delegate to YAML runner
    # Otherwise fall through to hardcoded logic (backward compatibility)
    # ═══════════════════════════════════════════════════════════════════════════
    local yaml_file="${PLUGIN_DIR}/config/workflows/embrace.yaml"
    local use_yaml_runtime=false

    case "$OCTOPUS_YAML_RUNTIME" in
        enabled)
            if [[ -f "$yaml_file" ]]; then
                use_yaml_runtime=true
            else
                log "ERROR" "YAML runtime enabled but embrace.yaml not found: $yaml_file"
                return 1
            fi
            ;;
        auto)
            if [[ -f "$yaml_file" ]] && [[ -z "$resume_from" || "$resume_from" == "null" ]]; then
                # Auto mode: try YAML if file exists and not resuming
                if parse_yaml_workflow "$yaml_file" 2>/dev/null; then
                    use_yaml_runtime=true
                    log "INFO" "YAML runtime auto-enabled: embrace.yaml found and valid"
                else
                    log "WARN" "YAML runtime auto-disabled: embrace.yaml parsing failed"
                fi
            fi
            ;;
        disabled)
            log "DEBUG" "YAML runtime disabled by user"
            ;;
    esac

    if [[ "$use_yaml_runtime" == "true" && ( "$requested_debate_gates" == "define" || "$requested_debate_gates" == "both" ) ]]; then
        log "INFO" "YAML runtime disabled for this embrace run because explicit debate gates were requested"
        use_yaml_runtime=false
    fi

    if [[ "$use_yaml_runtime" == "true" ]]; then
        log "INFO" "Delegating to YAML workflow runtime for embrace workflow"
        echo -e "${CYAN}Using YAML-driven workflow runtime (embrace.yaml)${NC}"
        echo ""

        local yaml_result
        if ! yaml_result=$(run_yaml_workflow "embrace" "$prompt" "$task_group"); then
            # run_yaml_workflow runs in a command-substitution subshell, so its
            # phase exports cannot reach this scope. It records the failed
            # phase in session.json before returning — read it from there.
            local _failed_phase=""
            if command -v jq &>/dev/null && [[ -f "${HOME}/.claude-octopus/session.json" ]]; then
                _failed_phase=$(jq -r '.current_phase // empty' "${HOME}/.claude-octopus/session.json" 2>/dev/null)
            fi
            _abort_embrace_phase "${_failed_phase:-unknown}" \
                "YAML runtime failed" "$yaml_result"
            return 1
        fi

        # Mark workflow complete
        export OCTOPUS_WORKFLOW_PHASE="complete"
        export OCTOPUS_COMPLETED_PHASES=4
        _write_embrace_session_state "complete" "finished"
        complete_session

        local duration=$((SECONDS - start_time))

        echo ""
        echo -e "${MAGENTA}${_BOX_TOP}${NC}"
        echo -e "${MAGENTA}║  EMBRACE workflow complete! (YAML Runtime)                ║${NC}"
        echo -e "${MAGENTA}${_BOX_BOT}${NC}"
        echo ""
        echo -e "Duration: ${duration}s"
        echo -e "Autonomy: ${AUTONOMY_MODE}"
        echo -e "Runtime: YAML (embrace.yaml)"
        echo -e "Results: ${RESULTS_DIR}/"
        echo ""

        # v7.25.0: Display session metrics
        if command -v display_session_metrics &>/dev/null; then
            display_session_metrics 2>/dev/null || true
            display_provider_breakdown 2>/dev/null || true
            # v8.6.0: Per-phase cost breakdown
            if command -v display_per_phase_cost_table &>/dev/null; then
                display_per_phase_cost_table 2>/dev/null || true
            fi
        fi

        _cleanup_embrace_exports
        return 0
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # HARDCODED PHASE LOGIC (fallback when YAML runtime not available)
    # ═══════════════════════════════════════════════════════════════════════════
    local probe_synthesis grasp_consensus tangle_validation
    local define_gate_output="" develop_gate_output=""

    # Phase 1: PROBE (Discover)
    if [[ -z "$resume_from" || "$resume_from" == "null" ]]; then
        export OCTOPUS_WORKFLOW_PHASE="probe"
        _write_embrace_session_state "probe" "running"
        echo ""
        echo -e "${CYAN}[1/4] Starting PROBE phase (Discover)...${NC}"
        echo ""
        if ! probe_discover "$prompt"; then
            _abort_embrace_phase "probe" "probe_discover returned non-zero"
            return 1
        fi
        probe_synthesis=$(_latest_embrace_output "$RESULTS_DIR"/probe-synthesis-*.md)
        if [[ -z "$probe_synthesis" ]]; then
            _abort_embrace_phase "probe" "missing probe synthesis artifact (expected probe-synthesis-*.md)"
            return 1
        fi

        # v7.25.0: Display phase metrics
        if command -v display_phase_metrics &> /dev/null; then
            display_phase_metrics "probe" 2>/dev/null || true
        fi

        # v8.14.0: Capture phase context in persistent state
        update_context "discover" "$(head -20 "$probe_synthesis" 2>/dev/null | tr '\n' ' ')" 2>/dev/null || true

        OCTOPUS_COMPLETED_PHASES=1
        _write_embrace_session_state "probe" "completed"
        save_session_checkpoint "probe" "completed" "$probe_synthesis"
        handle_autonomy_checkpoint "probe" "completed"
        sleep 1
    else
        probe_synthesis=$(get_phase_output "probe")
        [[ -z "$probe_synthesis" ]] && probe_synthesis=$(_latest_embrace_output "$RESULTS_DIR"/probe-synthesis-*.md)
        if [[ -z "$probe_synthesis" || ! -f "$probe_synthesis" ]]; then
            _abort_embrace_phase "probe" "resume requested but probe synthesis artifact is missing"
            return 1
        fi
        log INFO "Skipping probe phase (resuming)"
    fi

    # Phase 2: GRASP (Define)
    if [[ -z "$resume_from" || "$resume_from" == "null" || "$resume_from" == "probe" ]]; then
        export OCTOPUS_WORKFLOW_PHASE="grasp"
        _write_embrace_session_state "grasp" "running"
        echo ""
        echo -e "${CYAN}[2/4] Starting GRASP phase (Define)...${NC}"
        echo ""
        if ! grasp_define "$prompt" "$probe_synthesis"; then
            _abort_embrace_phase "grasp" "grasp_define returned non-zero" "$probe_synthesis"
            return 1
        fi
        grasp_consensus=$(_latest_embrace_output "$RESULTS_DIR"/grasp-consensus-*.md)
        if [[ -z "$grasp_consensus" ]]; then
            _abort_embrace_phase "grasp" "missing grasp consensus artifact (expected grasp-consensus-*.md)" "$probe_synthesis"
            return 1
        fi

        # v7.25.0: Display phase metrics
        if command -v display_phase_metrics &> /dev/null; then
            display_phase_metrics "grasp" 2>/dev/null || true
        fi

        # v8.14.0: Capture phase context in persistent state
        update_context "define" "$(head -20 "$grasp_consensus" 2>/dev/null | tr '\n' ' ')" 2>/dev/null || true

        OCTOPUS_COMPLETED_PHASES=2
        _write_embrace_session_state "grasp" "completed"
        save_session_checkpoint "grasp" "completed" "$grasp_consensus"
        handle_autonomy_checkpoint "grasp" "completed"
        sleep 1
    else
        grasp_consensus=$(get_phase_output "grasp")
        [[ -z "$grasp_consensus" ]] && grasp_consensus=$(_latest_embrace_output "$RESULTS_DIR"/grasp-consensus-*.md)
        if [[ -z "$grasp_consensus" || ! -f "$grasp_consensus" ]]; then
            _abort_embrace_phase "grasp" "resume requested but grasp consensus artifact is missing" "$probe_synthesis"
            return 1
        fi
        log INFO "Skipping grasp phase (resuming)"
    fi

    # Optional requested gate: Define → Develop.
    # Autonomy controls whether humans are asked between phases; it must not
    # silently waive a gate the user explicitly selected.
    if embrace_debate_gate_requested "define-develop"; then
        export OCTOPUS_WORKFLOW_PHASE="debate-define-develop"
        _write_embrace_session_state "debate-define-develop" "running"
        if ! embrace_debate_gate "define-develop" "$prompt" "$grasp_consensus"; then
            _abort_embrace_phase "debate-define-develop" "requested debate gate failed" "$grasp_consensus"
            return 1
        fi
        define_gate_output="$EMBRACE_DEBATE_GATE_OUTPUT"
        if [[ -z "$define_gate_output" || ! -f "$define_gate_output" ]]; then
            _abort_embrace_phase "debate-define-develop" "requested debate gate produced no artifact" "$grasp_consensus"
            return 1
        fi
        _write_embrace_session_state "debate-define-develop" "completed"
        handle_autonomy_checkpoint "debate-define-develop" "completed"
        sleep 1
    fi

    # Phase 3: TANGLE (Develop)
    if [[ -z "$resume_from" || "$resume_from" == "null" || "$resume_from" == "probe" || "$resume_from" == "grasp" ]]; then
        export OCTOPUS_WORKFLOW_PHASE="tangle"
        _write_embrace_session_state "tangle" "running"
        echo ""
        echo -e "${CYAN}[3/4] Starting TANGLE phase (Develop)...${NC}"
        echo ""
        if ! tangle_develop "$prompt" "$grasp_consensus"; then
            tangle_validation=$(_latest_embrace_output "$RESULTS_DIR"/tangle-validation-*.md)
            _abort_embrace_phase "tangle" "tangle_develop returned non-zero" "$tangle_validation"
            return 1
        fi
        tangle_validation=$(_latest_embrace_output "$RESULTS_DIR"/tangle-validation-*.md)
        if [[ -z "$tangle_validation" ]]; then
            _abort_embrace_phase "tangle" "missing tangle validation artifact (expected tangle-validation-*.md)" "$grasp_consensus"
            return 1
        fi

        # v7.25.0: Display phase metrics
        if command -v display_phase_metrics &> /dev/null; then
            display_phase_metrics "tangle" 2>/dev/null || true
        fi

        # Check quality gate status for autonomy
        local tangle_status="completed"
        if grep -q "Quality Gate: FAILED" "$tangle_validation" 2>/dev/null; then
            tangle_status="warning"
        fi
        # v8.14.0: Capture phase context in persistent state
        update_context "develop" "$(head -20 "$tangle_validation" 2>/dev/null | tr '\n' ' ')" 2>/dev/null || true

        OCTOPUS_COMPLETED_PHASES=3
        _write_embrace_session_state "tangle" "$tangle_status"
        save_session_checkpoint "tangle" "$tangle_status" "$tangle_validation"
        handle_autonomy_checkpoint "tangle" "$tangle_status"
        sleep 1
    else
        tangle_validation=$(get_phase_output "tangle")
        [[ -z "$tangle_validation" ]] && tangle_validation=$(_latest_embrace_output "$RESULTS_DIR"/tangle-validation-*.md)
        if [[ -z "$tangle_validation" || ! -f "$tangle_validation" ]]; then
            _abort_embrace_phase "tangle" "resume requested but tangle validation artifact is missing" "$grasp_consensus"
            return 1
        fi
        log INFO "Skipping tangle phase (resuming)"
    fi

    # Optional requested gate: Develop → Deliver.
    if embrace_debate_gate_requested "develop-deliver"; then
        export OCTOPUS_WORKFLOW_PHASE="debate-develop-deliver"
        _write_embrace_session_state "debate-develop-deliver" "running"
        if ! embrace_debate_gate "develop-deliver" "$prompt" "$tangle_validation"; then
            _abort_embrace_phase "debate-develop-deliver" "requested debate gate failed" "$tangle_validation"
            return 1
        fi
        develop_gate_output="$EMBRACE_DEBATE_GATE_OUTPUT"
        if [[ -z "$develop_gate_output" || ! -f "$develop_gate_output" ]]; then
            _abort_embrace_phase "debate-develop-deliver" "requested debate gate produced no artifact" "$tangle_validation"
            return 1
        fi
        _write_embrace_session_state "debate-develop-deliver" "completed"
        handle_autonomy_checkpoint "debate-develop-deliver" "completed"
        sleep 1
    fi

    # Phase 4: INK (Deliver)
    export OCTOPUS_WORKFLOW_PHASE="ink"
    _write_embrace_session_state "ink" "running"
    echo ""
    echo -e "${CYAN}[4/4] Starting INK phase (Deliver)...${NC}"
    echo ""
    if ! ink_deliver "$prompt" "$tangle_validation"; then
        _abort_embrace_phase "ink" "ink_deliver returned non-zero" "$tangle_validation"
        return 1
    fi

    # v7.25.0: Display phase metrics
    if command -v display_phase_metrics &> /dev/null; then
        display_phase_metrics "ink" 2>/dev/null || true
    fi

    # v8.14.0: Capture phase context in persistent state
    local ink_output
    ink_output=$(_latest_embrace_output "$RESULTS_DIR"/delivery-*.md)
    if [[ -z "$ink_output" ]]; then
        _abort_embrace_phase "ink" "missing delivery artifact (expected delivery-*.md)" "$tangle_validation"
        return 1
    fi
    update_context "deliver" "$(head -20 "$ink_output" 2>/dev/null | tr '\n' ' ')" 2>/dev/null || true

    OCTOPUS_COMPLETED_PHASES=4
    export OCTOPUS_WORKFLOW_PHASE="complete"
    _write_embrace_session_state "ink" "completed"
    save_session_checkpoint "ink" "completed" "$ink_output"

    # v8.18.0: Record phase completion decision
    write_structured_decision \
        "phase-completion" \
        "embrace_full_workflow" \
        "Full embrace workflow completed: ${prompt:0:80}" \
        "" \
        "high" \
        "All 4 phases completed: probe → grasp → tangle → ink" \
        "" 2>/dev/null || true

    # v8.18.0: Earn skill from embrace completion
    earn_skill \
        "workflow-${prompt:0:30}" \
        "embrace_full_workflow" \
        "Full Double Diamond execution pattern" \
        "For comprehensive end-to-end tasks" \
        "probe→grasp→tangle→ink completed for: ${prompt:0:60}" 2>/dev/null || true

    # Mark session complete
    complete_session

    # Summary
    local duration=$((SECONDS - start_time))

    echo ""
    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    echo -e "${MAGENTA}║  EMBRACE workflow complete!                               ║${NC}"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""
    echo -e "Duration: ${duration}s"
    echo -e "Autonomy: ${AUTONOMY_MODE}"
    echo -e "Results: ${RESULTS_DIR}/"
    echo ""
    echo -e "${CYAN}Phase outputs:${NC}"
    [[ -n "$probe_synthesis" ]] && echo -e "  Probe:  $probe_synthesis"
    [[ -n "$grasp_consensus" ]] && echo -e "  Grasp:  $grasp_consensus"
    [[ -n "$define_gate_output" ]] && echo -e "  Gate:   $define_gate_output"
    [[ -n "$tangle_validation" ]] && echo -e "  Tangle: $tangle_validation"
    [[ -n "$develop_gate_output" ]] && echo -e "  Gate:   $develop_gate_output"
    echo -e "  Ink:    $(ls -t "$RESULTS_DIR"/delivery-*.md 2>/dev/null | head -1)"
    echo ""

    # v7.25.0: Display session metrics
    if command -v display_session_metrics &> /dev/null; then
        display_session_metrics 2>/dev/null || true
        display_provider_breakdown 2>/dev/null || true
        # v8.6.0: Per-phase cost breakdown
        if command -v display_per_phase_cost_table &>/dev/null; then
            display_per_phase_cost_table 2>/dev/null || true
        fi
    fi

    # Clean up exported flags so they don't affect subsequent standalone calls
    _cleanup_embrace_exports
}
