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

fan_out() {
    local prompt="$1"
    local agents=("codex" "gemini")
    local pids=()
    local task_group
    task_group=$(date +%s)

    log INFO "Fan-out: Sending prompt to ${#agents[@]} agents"
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

parallel_execute() {
    local tasks_file="${1:-$TASKS_FILE}"

    # v8.48.0: Disable cron during parallel execution to prevent interference
    if [[ "$SUPPORTS_DISABLE_CRON_ENV" == "true" ]]; then
        export CLAUDE_CODE_DISABLE_CRON=1
        log DEBUG "Cron jobs disabled for parallel execution duration"
    fi

    if [[ ! -f "$tasks_file" ]]; then
        log ERROR "Tasks file not found: $tasks_file"
        log INFO "Run '$(basename "$0") init' to create a template"
        return 1
    fi

    log INFO "Loading tasks from: $tasks_file"

    if ! command -v jq &> /dev/null; then
        log ERROR "jq is required for parallel execution. Install with: brew install jq"
        return 1
    fi

    # SECURITY: Validate JSON structure first
    if ! jq -e . "$tasks_file" >/dev/null 2>&1; then
        log ERROR "Invalid JSON in tasks file: $tasks_file"
        return 1
    fi

    local task_count
    task_count=$(jq '.tasks | length' "$tasks_file" 2>/dev/null) || {
        log ERROR "Failed to read tasks array from file"
        return 1
    }
    log INFO "Found $task_count tasks"

    local running=0
    local completed=0
    local skipped=0
    local pids=()

    while IFS= read -r task; do
        local task_id agent prompt

        # SECURITY: Safe JSON extraction with validation
        task_id=$(extract_json_field "$task" "id" true) || {
            log WARN "Skipping task with invalid/missing id"
            ((skipped++)) || true
            continue
        }

        agent=$(extract_json_field "$task" "agent" true) || {
            log WARN "Skipping task $task_id: invalid/missing agent"
            ((skipped++)) || true
            continue
        }

        # SECURITY: Validate agent type against allowlist
        validate_agent_type "$agent" || {
            log WARN "Skipping task $task_id: unknown agent '$agent'"
            ((skipped++)) || true
            continue
        }

        prompt=$(extract_json_field "$task" "prompt" true) || {
            log WARN "Skipping task $task_id: invalid/missing prompt"
            ((skipped++)) || true
            continue
        }

        while [[ $running -ge $MAX_PARALLEL ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[i]'
                    ((running--))
                    ((completed++)) || true
                fi
            done
            sleep 1
        done

        local pid
        if pid=$(spawn_agent_capture_pid "$agent" "$prompt" "$task_id"); then
            pids+=("$pid")
            ((running++)) || true
        else
            log WARN "Skipping task $task_id: failed to spawn agent '$agent'"
            ((skipped++)) || true
            continue
        fi

        log INFO "Progress: $completed/$task_count completed, $running running"
    done < <(jq -c '.tasks[]' "$tasks_file")

    log INFO "Waiting for remaining $running tasks to complete..."
    while [[ $running -gt 0 ]]; do
        local saw_completion=false
        for i in "${!pids[@]}"; do
            if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                unset 'pids[i]'
                ((running--)) || true
                ((completed++)) || true
                saw_completion=true
            fi
        done
        [[ "$saw_completion" == "false" ]] && sleep 1
    done

    if [[ $skipped -gt 0 ]]; then
        log WARN "Completed with $skipped skipped tasks (invalid/malformed)"
    fi
    log INFO "All $task_count tasks processed ($((task_count - skipped)) executed, $skipped skipped)"
    aggregate_results
}

map_reduce() {
    local main_prompt="$1"
    local task_group
    task_group=$(date +%s)

    log INFO "Map-Reduce: Decomposing task and distributing to agents"

    log INFO "Phase 1: Task decomposition with Gemini"
    local decompose_prompt="Analyze this task and break it into subtasks that can be executed in parallel.
If the task produces a single deliverable (one file, one script, one page, one config), keep it as ONE subtask — do not split it. Only decompose when subtasks are truly independent with no cross-file references. Aim for 2-5 subtasks; fewer is better when the work is tightly coupled.
Output as a simple numbered list. Task: $main_prompt"

    local decompose_result="${RESULTS_DIR}/decompose-${task_group}.txt"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would decompose: $main_prompt"
        return 0
    fi

    gemini "$decompose_prompt" > "$decompose_result" 2>&1 || {
        log WARN "Decomposition failed, falling back to fan-out"
        fan_out "$main_prompt"
        return
    }

    log INFO "Decomposition complete. Subtasks:"
    cat "$decompose_result"
    echo ""

    log INFO "Phase 2: Mapping subtasks to agents"
    local subtask_num=0
    local agents=("codex" "gemini")
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
    > "$raw_concat"
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

    # Phase 2: Synthesize if we have a provider available and multiple results
    if [[ $result_count -gt 1 ]] && command -v gemini &> /dev/null && [[ "$DRY_RUN" != "true" ]]; then
        log INFO "Synthesizing $result_count results (ranked by quality, not just concatenating)..."

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

        local synthesis_result
        if synthesis_result=$(printf '%s' "$synthesis_prompt" | run_with_timeout "$TIMEOUT" gemini 2>/dev/null) && [[ -n "$synthesis_result" ]]; then
            echo "# Claude Octopus - Synthesized Results" > "$aggregate_file"
            echo "" >> "$aggregate_file"
            echo "Generated: $(date)" >> "$aggregate_file"
            echo "Sources: $result_count subtask outputs (ranked by quality)" >> "$aggregate_file"
            [[ -n "$user_query" ]] && echo "Query: $user_query" >> "$aggregate_file"
            echo "" >> "$aggregate_file"
            echo "$synthesis_result" >> "$aggregate_file"
            rm -f "$raw_concat"
            log INFO "Synthesized $result_count results to: $aggregate_file"
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
