#!/usr/bin/env bash
# Double Diamond workflow phases
# Extracted from orchestrate.sh to reduce file size
# Functions: probe_single_agent, probe_discover, grasp_define, tangle_develop, ink_deliver

if ! type probe_result_file_status >/dev/null 2>&1; then
    _octo_probe_results_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/probe-results.sh"
    [[ -f "$_octo_probe_results_lib" ]] && source "$_octo_probe_results_lib"
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
    # agy workspace) can read project files (bug 260609). probe-single runs
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

    # Track provider usage
    local provider_name
    case "$agent_type" in
        codex*) provider_name="codex" ;;
        agy*|antigravity) provider_name="agy" ;;
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
    # Qwen and Cursor Agent share the same CLI flags
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
        # v9.2.2: All agents use stdin to avoid ARG_MAX "Argument list too long" on large diffs (Issue #173)
        # v9.17.1: Windows/MINGW fallback — pipe chain through tee loses stdout on Git Bash (fixes #235)
        # Use file-based capture instead of pipe chain when on Windows
        if [[ "${OCTOPUS_PLATFORM:-}" == MINGW* ]] || [[ "${OCTOPUS_PLATFORM:-}" == MSYS* ]]; then
            printf '%s' "$enhanced_prompt" | run_with_timeout "$TIMEOUT" "${cmd_array[@]}" > "$raw_output" 2> "$temp_errors" || exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
                cp "$raw_output" "$temp_output"
            fi
        elif printf '%s' "$enhanced_prompt" | run_with_timeout "$TIMEOUT" "${cmd_array[@]}" 2> "$temp_errors" | tee "$raw_output" > "$temp_output"; then
            exit_code=0
        else
            exit_code=$?
        fi

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
                > "$temp_output"; > "$temp_errors"; > "$raw_output"
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
                -e '^Keychain initialization' \
                -e '^Using FileKeychain' \
                -e '^Loaded cached credentials' \
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
        case "$agent_type" in codex*|agy*|antigravity|perplexity*|cursor-agent*)
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
                update_agent_status "$agent_type" "failed" "$elapsed_ms" 0.0
                record_outcome "$agent_type" "$agent_type" "research" "$phase" "fail" "$elapsed_ms" 2>/dev/null || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" "$tokens_out" "${reason:-unusable output}" "$elapsed_ms" "$result_file" "$role" || true
                final_rc=1
                ;;
            degraded)
                echo "## Status: SUCCESS (DEGRADED: ${reason:-partial output})" >> "$result_file"
                update_agent_status "$agent_type" "completed" "$elapsed_ms" 0.0
                record_outcome "$agent_type" "$agent_type" "research" "$phase" "success" "$elapsed_ms" 2>/dev/null || true
                record_run_pattern "$agent_type" "${enhanced_prompt:-$original_prompt}" "$result_file" 2>/dev/null || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "degraded" "$tokens_in" "$tokens_out" "${reason:-partial output}" "$elapsed_ms" "$result_file" "$role" || true
                ;;
            *)
                echo "## Status: SUCCESS" >> "$result_file"
                update_agent_status "$agent_type" "completed" "$elapsed_ms" 0.0
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
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" "$tokens_out" "Exit code $exit_code" "$elapsed_ms" "$result_file" "$role" || true
        final_rc=$exit_code
    fi

    # Cleanup temp files
    rm -f "$temp_output" "$temp_errors" "$raw_output"

    log "INFO" "probe_single_agent complete: $result_file"
    # Output the result file path for the caller
    echo "$result_file"
    return "$final_rc"
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
        log INFO "[DRY-RUN] Would spawn 5+ parallel research agents (Codex, agy, Sonnet 4.6, +codebase if in git repo, +Perplexity if API key set)"
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

    fleet_dispatch_begin

    local pids=()
    for i in "${!perspectives[@]}"; do
        local perspective="${perspectives[$i]}"
        local agent="${probe_agents[$i]}"
        local task_id="probe-${task_group}-${i}"

        if [[ "$TMUX_MODE" == "true" ]]; then
            # Use async+tmux spawning
            local pid
            pid=$(spawn_agent_async "$agent" "$perspective" "$task_id" "researcher" "probe" "${pane_titles[$i]}")
            pids+=("$pid")
        else
            # Standard spawning
            local pid
            pid=$(spawn_agent_capture_pid "$agent" "$perspective" "$task_id" "researcher" "probe")
            pids+=("$pid")
        fi
        sleep 0.1
    done

    fleet_dispatch_end

    log INFO "Spawned ${#pids[@]} parallel research threads"

    # v7.19.0 P2.4: Start progressive synthesis monitor in background
    local synthesis_monitor_pid=""
    if [[ "$ENABLE_PROGRESSIVE_SYNTHESIS" == "true" ]]; then
        progressive_synthesis_monitor "$task_group" "$prompt" 2 &
        synthesis_monitor_pid=$!
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
        render_agent_summary || return $?
    fi

    # v8.48.0: Write synthesis marker before attempting synthesis
    # WHY: The Bash tool's 120s timeout frequently kills the process during
    # the agy synthesis call (~30-60s) that follows ~60-90s of agent work.
    # This marker lets the user recover by running `synthesize-probe <task_group>`.
    local synthesis_marker="${RESULTS_DIR}/probe-needs-synthesis-${task_group}.marker"
    {
        echo "task_group=${task_group}"
        printf 'prompt=%q\n' "$(printf '%s' "$prompt" | head -c 4096)"
        echo "usable_results=${usable_results}"
        echo "timestamp=$(date -Iseconds)"
    } > "$synthesis_marker"
    log DEBUG "Synthesis marker written: $synthesis_marker"

    # Intelligent synthesis (v7.19.0 P1.1: allow with partial results)
    synthesize_probe_results "$task_group" "$prompt" "$usable_results"

    # Synthesis succeeded — remove the marker
    rm -f "$synthesis_marker"
    log DEBUG "Synthesis marker removed (synthesis completed successfully)"

    # v7.19.0 P2.4: Stop progressive synthesis monitor
    if [[ -n "$synthesis_monitor_pid" ]]; then
        kill "$synthesis_monitor_pid" 2>/dev/null
        wait "$synthesis_monitor_pid" 2>/dev/null
        log "DEBUG" "Progressive synthesis monitor stopped"
    fi

    # Display workflow summary (v7.16.0 Feature 2)
    display_progress_summary
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
        log INFO "[DRY-RUN] Would gather 4 perspectives (Codex, agy, Sonnet 4.6) and build consensus"
        return 0
    fi

    # Cost transparency (v7.18.0 - P0.0)
    if ! display_workflow_cost_estimate "Grasp (Define Phase)" 1 2 1200; then
        log "WARN" "Workflow cancelled by user after cost review"
        return 1
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

    local def1 def2 def3
    def1=$(run_agent_sync "codex" "Based on: $prompt\n${context}Define the core problem statement in 2-3 sentences. What is the essential challenge?" 120 "backend-architect" "grasp") || {
        log WARN "Codex failed for problem definition, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Codex unavailable for problem definition — falling back to Claude"
        def1=$(run_agent_sync "claude-sonnet" "Based on: $prompt\n${context}Define the core problem statement in 2-3 sentences. What is the essential challenge?" 120 "backend-architect" "grasp") || true
    }
    def2=$(run_agent_sync "agy" "Based on: $prompt\n${context}Define success criteria. How will we know when this is solved correctly? List 3-5 measurable criteria." 120 "researcher" "grasp") || {
        log WARN "agy failed for success criteria, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  agy unavailable for success criteria — falling back to Claude"
        def2=$(run_agent_sync "claude-sonnet" "Based on: $prompt\n${context}Define success criteria. How will we know when this is solved correctly? List 3-5 measurable criteria." 120 "researcher" "grasp") || true
    }
    def3=$(run_agent_sync "claude-sonnet" "Based on: $prompt\n${context}Define constraints and boundaries. What are we NOT solving? What are hard limits?" 120 "researcher" "grasp")

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
    consensus=$(run_agent_sync "agy" "$consensus_prompt" 180 "synthesizer" "grasp") || {
        consensus="[Auto-consensus failed - manual review required]\n\nProblem: $def1\n\nSuccess Criteria: $def2\n\nConstraints: $def3"
    }

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

    local repo_context
    repo_context=$(tangle_build_repo_context_block "$assigned_subtask")

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

tangle_scope_is_known_or_explicit_new_file() {
    local scope="$1"
    local normalized="${scope%/}"
    [[ -z "$normalized" ]] && return 1

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
        local child_matches
        child_matches=$(git -C "$repo_root" ls-files "$normalized/" 2>/dev/null || true)
        if [[ -n "$child_matches" ]]; then
            return 0
        fi
    fi

    [[ -e "$repo_root/$normalized" ]] && return 0

    if [[ "$scope" != */ && "${normalized##*/}" == *.* ]]; then
        local parent="${normalized%/*}"
        [[ "$parent" == "$normalized" ]] && return 0
        [[ -d "$repo_root/$parent" ]] && return 0
        if git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1; then
            local parent_matches
            parent_matches=$(git -C "$repo_root" ls-files "$parent/" 2>/dev/null || true)
            if [[ -n "$parent_matches" ]]; then
                return 0
            fi
        fi
    fi
    return 1
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

    run_agent_sync "agy" "$reformat_prompt" 120 "researcher" "tangle" || \
    run_agent_sync "claude-sonnet" "$reformat_prompt" 120 "researcher" "tangle"
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

# Phase 3: TANGLE (Develop) - Enhanced map-reduce with validation
# Tentacles work together in a coordinated tangle of activity
tangle_develop() {
    local prompt="$1"
    local grasp_file="${2:-}"
    local task_group
    task_group=$(date +%s)

    echo ""
    octopus_phase_banner "DEVELOP (Phase 3/4)" "Implementation" "$MAGENTA"
    echo ""

    log INFO "Phase 3: Parallel development with validation gates"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would tangle: $prompt"
        log INFO "[DRY-RUN] Would decompose into subtasks and execute in parallel"
        return 0
    fi

    # Cost transparency (v7.18.0 - P0.0)
    if ! display_workflow_cost_estimate "Tangle (Develop Phase)" 2 2 1800; then
        log "WARN" "Workflow cancelled by user after cost review"
        return 1
    fi

    # v8.18.0: Reset lockouts for new tangle phase
    reset_provider_lockouts

    # v8.34.0: Parallel file safety — write/edit errors don't abort siblings (G12)
    if [[ "$SUPPORTS_PARALLEL_FILE_SAFETY" == "true" ]]; then
        log "DEBUG" "Parallel file safety active — concurrent file operations enabled"
    fi

    mkdir -p "$RESULTS_DIR"
    local worktree_before_file="${RESULTS_DIR}/.tangle-${task_group}-worktree-before.txt"
    if type snapshot_tangle_worktree_paths >/dev/null 2>&1; then
        snapshot_tangle_worktree_paths > "$worktree_before_file" 2>/dev/null || true
    else
        : > "$worktree_before_file"
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
    local token
    local noglob_was_set=false
    [[ "$-" == *f* ]] && noglob_was_set=true || set -f
    for token in $prompt; do
        local candidate_ref="$token"
        local candidate_basename
        candidate_ref="${candidate_ref#plan:}"
        candidate_ref="${candidate_ref#plan=}"
        candidate_basename="${candidate_ref##*/}"
        if [[ "$token" == plan:* || "$token" == plan=* || "$candidate_basename" == "plan.md" || "$candidate_basename" == *.plan.md || "$candidate_basename" == *-plan.md ]]; then
            raw_file_ref="$token"
            raw_file_ref="${raw_file_ref#plan:}"
            raw_file_ref="${raw_file_ref#plan=}"
            file_ref="${raw_file_ref/#\~/$HOME}"
            break
        fi
    done
    [[ "$noglob_was_set" == "false" ]] && set +f
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
        tangle_decompose_agent=$(octopus_agent_override "tangle" "decompose" "agy")
        tangle_decompose_fallback_agent=$(octopus_agent_override "tangle" "decompose_fallback" "codex")
    fi

    local subtasks
    subtasks=$(run_agent_sync "$tangle_decompose_agent" "$decompose_prompt" 120 "researcher" "tangle") || \
    subtasks=$(run_agent_sync "$tangle_decompose_fallback_agent" "$decompose_prompt" 120 "researcher" "tangle") || {
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
        log ERROR "Unsafe parallel decomposition after retry: ${parallel_safety_reason}; refusing monolithic direct fallback"
        return 1
    fi

    # Step 2: Parallel execution with progress tracking
    log INFO "Step 2: Parallel execution..."
    local subtask_num=0
    local pids=()
    local task_ids=()

    fleet_dispatch_begin
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        tangle_line_is_numbered_subtask "$line" || continue

        local subtask
        subtask=$(echo "$line" | sed -E 's/^[[:space:]]*(\*\*)?[0-9]+[\.\)][[:space:]]*//; s/^[[:space:]]+//')
        local agent="codex"
        local role="implementer"
        local pane_icon="⚙️"
        if [[ "$subtask" =~ \[REASONING\] ]]; then
            agent="agy"
            role="researcher"
            pane_icon="🧠"
        fi
        subtask=$(echo "$subtask" | sed 's/\[CODING\]\s*//; s/\[REASONING\]\s*//')
        local task_id="tangle-${task_group}-${subtask_num}"
        local pane_title="$pane_icon Subtask $((subtask_num+1))"
        local subtask_prompt
        subtask_prompt=$(build_tangle_subtask_prompt "$resolved_prompt" "$subtask")

        # Tangle currently routes only CLI-backed codex/agy workers. Its
        # completion watcher relies on .done markers written by the legacy
        # spawn path; add equivalent hook markers before routing Claude Agent
        # Teams into this loop.
        if [[ "$TMUX_MODE" == "true" ]]; then
            # Use async+tmux spawning
            local pid
            pid=$(spawn_agent_async "$agent" "$subtask_prompt" "$task_id" "$role" "tangle" "$pane_title")
            pids+=("$pid")
        else
            # Standard spawning
            local pid
            pid=$(spawn_agent_capture_pid "$agent" "$subtask_prompt" "$task_id" "$role" "tangle")
            pids+=("$pid")
        fi
        task_ids+=("$task_id")
        ((subtask_num++)) || true
    done <<< "$subtasks"
    fleet_dispatch_end

    log INFO "Spawned $subtask_num development threads"

    # Wait with progress monitoring — poll .done marker files written by spawn_agent
    # rather than kill -0 $pid (which tracks wrapper PID, not provider PID)
    local _done_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents"
    local _tangle_max_wait="${OCTOPUS_TANGLE_DEADLINE:-$(( ${TIMEOUT:-600} + 60 ))}"
    [[ "$_tangle_max_wait" =~ ^[0-9]+$ ]] || _tangle_max_wait=$(( ${TIMEOUT:-600} + 60 ))
    local _deadline=$(( $(date +%s) + _tangle_max_wait ))
    local completed=0
    local _failed_tasks=()
    while [[ $completed -lt ${#task_ids[@]} ]]; do
        completed=0
        for i in "${!task_ids[@]}"; do
            local _done_file="${_done_dir}/${task_ids[$i]}.done"
            if [[ -f "$_done_file" ]]; then
                ((completed++)) || true
            elif (( $(date +%s) > _deadline )); then
                log WARN "Thread ${task_ids[$i]} deadline exceeded — killing and marking timeout"
                local _wrapper_pid="${pids[$i]:-}"
                if [[ -n "$_wrapper_pid" ]]; then
                    pkill -TERM -P "$_wrapper_pid" 2>/dev/null || true
                    kill -TERM "$_wrapper_pid" 2>/dev/null || true
                    sleep 1
                    pkill -KILL -P "$_wrapper_pid" 2>/dev/null || true
                    kill -KILL "$_wrapper_pid" 2>/dev/null || true
                fi
                mkdir -p "$_done_dir" 2>/dev/null || true
                if [[ ! -f "$_done_file" ]] && ! echo "timeout" > "$_done_file" 2>/dev/null; then
                    log WARN "Failed to write timeout marker for ${task_ids[$i]} at $_done_file"
                fi
            fi
        done
        echo -ne "\r${CYAN}Progress: $completed/${#task_ids[@]} subtasks complete${NC}"
        sleep 2
    done
    echo ""

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

    # v7.25.0: Record agent completion metrics
    if command -v record_agents_batch_complete &> /dev/null; then
        record_agents_batch_complete "tangle" "$task_group" 2>/dev/null || true
    fi

    # Step 3: Validation gate
    log INFO "Step 3: Validation gate..."
    validate_tangle_results "$task_group" "$resolved_prompt" "$worktree_before_file"
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

    # Sonnet 4.6 quality review before synthesis
    log INFO "Step 2a: Sonnet 4.6 quality review..."
    local sonnet_review
    sonnet_review=$(run_agent_sync "claude-sonnet" "Review these development results for quality, completeness, and correctness.
Flag any issues, gaps, or improvements needed.
Rate each dimension explicitly as 'Security: N/10', 'Reliability: N/10', 'Performance: N/10', 'Accessibility: N/10'.

Original task: $prompt

Results:
$all_results" 120 "code-reviewer" "ink") || {
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
        simplify_result=$(run_agent_sync "claude-sonnet" "$simplify_prompt" 120 "code-reviewer" "ink") || true
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

Quality Review (from Sonnet 4.6):
$sonnet_review

Compact source context to synthesize:
$all_results"

    local delivery
    delivery=$(run_agent_sync "agy" "$synthesis_prompt" 180 "synthesizer" "ink") || {
        delivery=$(build_ink_fallback_delivery "$prompt" "$sonnet_review" "$all_results")
    }

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
        command -v agy &>/dev/null && providers+="🟡"
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
    if agy_view=$(run_agent_sync "agy" "$gate_prompt" 120 "researcher" "embrace-gate" 2>/dev/null); then
        if [[ -n "$agy_view" ]]; then
            agy_status="ok"
            successful=$((successful + 1))
        fi
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

### 🟡 Antigravity / agy (${agy_status})

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
        mkdir -p "$session_dir"
        if command -v jq &> /dev/null; then
            jq -n \
                --arg phase "$phase" \
                --arg status "$status" \
                --arg workflow "embrace" \
                --arg group "$task_group" \
                --arg autonomy "$AUTONOMY_MODE" \
                --argjson completed "$OCTOPUS_COMPLETED_PHASES" \
                --argjson total "$OCTOPUS_TOTAL_PHASES" \
                '{workflow: $workflow, current_phase: $phase, phase_status: $status,
                  task_group: $group, autonomy_mode: $autonomy,
                  completed_phases: $completed, total_phases: $total,
                  phase_map: {probe: "grasp", grasp: "tangle", tangle: "ink", ink: "complete"},
                  phase_tasks: {total: 0, completed: 0},
                  agent_queue: [],
                  quality_gates: {passed: false, failed: false},
                  updated_at: now | todate}' \
                > "$session_dir/session.json" 2>/dev/null || true
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
        yaml_result=$(run_yaml_workflow "embrace" "$prompt" "$task_group")

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
