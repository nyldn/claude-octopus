#!/usr/bin/env bash
# Double Diamond workflow phases
# Extracted from orchestrate.sh to reduce file size
# Functions: probe_single_agent, probe_discover, grasp_define, tangle_develop, ink_deliver

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
    enhanced_prompt=$(enforce_context_budget "$enhanced_prompt" "$role")

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
        gemini*) provider_name="gemini" ;;
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
    # Qwen and Cursor Agent are forks of Gemini CLI — same flags
    if [[ "$agent_type" == gemini* ]] || [[ "$agent_type" == copilot* ]] || [[ "$agent_type" == qwen* ]] || [[ "$agent_type" == cursor-agent* ]]; then
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
                /^(codex|gemini|assistant)$/ { in_response = 1; next; }
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

        # Trust marker for external CLI output
        case "$agent_type" in codex*|gemini*|perplexity*|cursor-agent*)
            if [[ "${OCTOPUS_SECURITY_V870:-true}" == "true" ]]; then
                sed -i.bak '1s/^/<!-- trust=untrusted provider='"$agent_type"' -->\n/' "$result_file" 2>/dev/null || true
                rm -f "${result_file}.bak"
            fi ;; esac

        echo '```' >> "$result_file"
        echo "" >> "$result_file"
        echo "## Status: SUCCESS" >> "$result_file"

        local end_time_ms elapsed_ms
        end_time_ms=$(( $(date +%s) * 1000 ))
        elapsed_ms=$((end_time_ms - start_time_ms))
        update_agent_status "$agent_type" "completed" "$elapsed_ms" 0.0
        record_outcome "$agent_type" "$agent_type" "research" "$phase" "success" "$elapsed_ms" 2>/dev/null || true
        # v9.3.0: Record file co-occurrence pattern for heuristic learning
        record_run_pattern "$agent_type" "${enhanced_prompt:-$original_prompt}" "$result_file" 2>/dev/null || true
    elif [[ $exit_code -eq 124 ]] || [[ $exit_code -eq 143 ]]; then
        # Timeout — preserve partial output
        if [[ -s "$temp_output" ]]; then
            if [[ $(grep -c '^--------$' "$temp_output" 2>/dev/null || true) -gt 0 ]]; then
                awk '
                    BEGIN { in_response = 0; header_done = 0; }
                    /^--------$/ { header_done = 1; next; }
                    !header_done { next; }
                    /^(codex|gemini|assistant)$/ { in_response = 1; next; }
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
    fi

    # Cleanup temp files
    rm -f "$temp_output" "$temp_errors" "$raw_output"

    log "INFO" "probe_single_agent complete: $result_file"
    # Output the result file path for the caller
    echo "$result_file"
}

# Phase 1: PROBE (Discover) - Parallel research with synthesis
# Like an octopus probing with multiple tentacles simultaneously
probe_discover() {
    local _ts; _ts=$(date +%s)
    local prompt="$1"
    local task_group="$_ts"

    echo ""
    octopus_phase_banner "RESEARCH (Phase 1/4)" "Parallel Exploration" "$MAGENTA"
    echo ""

    log INFO "Phase 1: Parallel exploration with multiple perspectives"
    log "DEBUG" "probe_discover: task_group=$task_group, results_dir=$RESULTS_DIR"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would probe: $prompt"
        log INFO "[DRY-RUN] Would spawn 5+ parallel research agents (Codex, Gemini, Sonnet 4.6, +codebase if in git repo, +Perplexity if API key set)"
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
    display_rich_progress "$task_group" "${#pids[@]}" "$start_time" "${pids[@]}"

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

            # Categorize based on content and status markers
            if grep -q "Status: SUCCESS" "$result_file"; then
                echo -e " ${GREEN}✓${NC} $agent_display probe $i: completed ($(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                ((success_count++)) || true
            elif grep -q "Status: TIMEOUT" "$result_file"; then
                echo -e " ${YELLOW}⏳${NC} $agent_display probe $i: timeout with partial results ($(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                ((timeout_count++)) || true
            elif grep -q "Status: FAILED" "$result_file"; then
                if [[ $file_size -gt 1024 ]]; then
                    echo -e " ${YELLOW}⚠${NC}  $agent_display probe $i: failed but has output ($(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                    ((timeout_count++)) || true  # Count as partial success
                else
                    echo -e " ${RED}✗${NC} $agent_display probe $i: failed ($(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                    ((failure_count++)) || true
                fi
            else
                # No clear status marker - check file size
                if [[ $file_size -gt 1024 ]]; then
                    echo -e " ${YELLOW}?${NC} $agent_display probe $i: unknown status but has content ($(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                    ((timeout_count++)) || true  # Count as partial success
                else
                    echo -e " ${RED}✗${NC} $agent_display probe $i: empty or missing ($(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "${file_size}B"))"
                    ((failure_count++)) || true
                fi
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
            if [[ ! -f "$result_file" ]] || grep -q "Status: FAILED" "$result_file" 2>/dev/null; then
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

    # v8.48.0: Write synthesis marker before attempting synthesis
    # WHY: The Bash tool's 120s timeout frequently kills the process during
    # the Gemini synthesis call (~30-60s) that follows ~60-90s of agent work.
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
        log INFO "[DRY-RUN] Would gather 4 perspectives (Codex, Gemini, Sonnet 4.6) and build consensus"
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
    def2=$(run_agent_sync "gemini" "Based on: $prompt\n${context}Define success criteria. How will we know when this is solved correctly? List 3-5 measurable criteria." 120 "researcher" "grasp") || {
        log WARN "Gemini failed for success criteria, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Gemini unavailable for success criteria — falling back to Claude"
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
    consensus=$(run_agent_sync "gemini" "$consensus_prompt" 180 "synthesizer" "grasp") || {
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

    # v8.18.0: Pre-work design review ceremony
    design_review_ceremony "$prompt" "$context"

    # Step 1: Decompose into validated subtasks
    log INFO "Step 1: Task decomposition..."
    local decompose_prompt="Decompose this task into subtasks that can be executed in parallel.
Each subtask should be:
- Self-contained and independently verifiable
- Clear about inputs and expected outputs
- Assignable to either a coding agent [CODING] or reasoning agent [REASONING]

**Cohesion rule:** If the task produces a single deliverable (one file, one script, one page, one config), keep it as ONE subtask — do not split it. Only decompose when subtasks are truly independent with no cross-file references between them. Aim for 2-6 subtasks; fewer is better when the work is tightly coupled.

${context}Task: $prompt

Output as numbered list with [CODING] or [REASONING] prefix for each subtask."

    local subtasks
    subtasks=$(run_agent_sync "gemini" "$decompose_prompt" 120 "researcher" "tangle") || \
    subtasks=$(run_agent_sync "codex" "$decompose_prompt" 120 "researcher" "tangle") || {
        log WARN "Decomposition failed with all providers, falling back to direct execution"
        spawn_agent "codex" "$prompt" "tangle-${task_group}-direct" "implementer" "tangle"
        wait
        return
    }

    echo -e "${CYAN}Decomposed into subtasks:${NC}"
    echo "$subtasks"
    echo ""

    # Step 2: Parallel execution with progress tracking
    log INFO "Step 2: Parallel execution..."
    local subtask_num=0
    local pids=()

    fleet_dispatch_begin
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ ! "$line" =~ ^[0-9]+[\.\)] ]] && continue

        local subtask
        subtask=$(echo "$line" | sed 's/^[0-9]*[\.\)]\s*//')
        local agent="codex"
        local role="implementer"
        local pane_icon="⚙️"
        if [[ "$subtask" =~ \[REASONING\] ]]; then
            agent="gemini"
            role="researcher"
            pane_icon="🧠"
        fi
        subtask=$(echo "$subtask" | sed 's/\[CODING\]\s*//; s/\[REASONING\]\s*//')
        local task_id="tangle-${task_group}-${subtask_num}"
        local pane_title="$pane_icon Subtask $((subtask_num+1))"

        if [[ "$TMUX_MODE" == "true" ]]; then
            # Use async+tmux spawning
            local pid
            pid=$(spawn_agent_async "$agent" "$subtask" "$task_id" "$role" "tangle" "$pane_title")
            pids+=("$pid")
        else
            # Standard spawning
            local pid
            pid=$(spawn_agent_capture_pid "$agent" "$subtask" "$task_id" "$role" "tangle")
            pids+=("$pid")
        fi
        ((subtask_num++)) || true
    done <<< "$subtasks"
    fleet_dispatch_end

    log INFO "Spawned $subtask_num development threads"

    # Wait with progress monitoring
    local completed=0
    while [[ $completed -lt ${#pids[@]} ]]; do
        completed=0
        for pid in "${pids[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                ((completed++)) || true
            fi
        done
        echo -ne "\r${CYAN}Progress: $completed/${#pids[@]} subtasks complete${NC}"
        sleep 2
    done
    echo ""

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
    validate_tangle_results "$task_group" "$prompt"
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

    local all_results=""
    local result_count=0
    for result in "$RESULTS_DIR"/*.md; do
        [[ -f "$result" ]] || continue
        [[ "$result" == *aggregate* || "$result" == *delivery* ]] && continue
        all_results+="$(<"$result")\n\n"
        ((result_count++)) || true
        [[ $result_count -ge 10 ]] && break  # Limit context size
    done

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

Results to synthesize:
$all_results"

    local delivery
    delivery=$(run_agent_sync "gemini" "$synthesis_prompt" 180 "synthesizer" "ink") || {
        delivery="[Synthesis failed - raw results attached]\n\n$all_results"
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
- Results synthesized: $result_count files
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
        command -v gemini &>/dev/null && providers+="🟡"
        [[ -n "${PERPLEXITY_API_KEY:-}" ]] && providers+="🟣"
        providers+="🔵"
        echo "🐙 ${workflow} — ${description} | ${providers}"
    else
        # Full: standard verbose banner (existing behavior, unchanged)
        echo "🐙 **CLAUDE OCTOPUS ACTIVATED** - ${workflow}"
        echo "${phase_emoji} ${description}"
    fi
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

    log INFO "Task: $prompt"
    log INFO "Autonomy mode: $AUTONOMY_MODE"
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

        # Clean up exported flags
        unset OCTOPUS_SKIP_PHASE_COST_PROMPT
        unset OCTOPUS_WORKFLOW_PHASE
        unset OCTOPUS_WORKFLOW_TYPE
        unset OCTOPUS_TASK_GROUP
        unset OCTOPUS_TOTAL_PHASES
        unset OCTOPUS_COMPLETED_PHASES
        unset CLAUDE_CODE_DISABLE_CRON 2>/dev/null || true
        return 0
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # HARDCODED PHASE LOGIC (fallback when YAML runtime not available)
    # ═══════════════════════════════════════════════════════════════════════════
    local probe_synthesis grasp_consensus tangle_validation

    # Phase 1: PROBE (Discover)
    if [[ -z "$resume_from" || "$resume_from" == "null" ]]; then
        export OCTOPUS_WORKFLOW_PHASE="probe"
        _write_embrace_session_state "probe" "running"
        echo ""
        echo -e "${CYAN}[1/4] Starting PROBE phase (Discover)...${NC}"
        echo ""
        probe_discover "$prompt"
        probe_synthesis=$(ls -t "$RESULTS_DIR"/probe-synthesis-*.md 2>/dev/null | head -1)

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
        [[ -z "$probe_synthesis" ]] && probe_synthesis=$(ls -t "$RESULTS_DIR"/probe-synthesis-*.md 2>/dev/null | head -1)
        log INFO "Skipping probe phase (resuming)"
    fi

    # Phase 2: GRASP (Define)
    if [[ -z "$resume_from" || "$resume_from" == "null" || "$resume_from" == "probe" ]]; then
        export OCTOPUS_WORKFLOW_PHASE="grasp"
        _write_embrace_session_state "grasp" "running"
        echo ""
        echo -e "${CYAN}[2/4] Starting GRASP phase (Define)...${NC}"
        echo ""
        grasp_define "$prompt" "$probe_synthesis"
        grasp_consensus=$(ls -t "$RESULTS_DIR"/grasp-consensus-*.md 2>/dev/null | head -1)

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
        [[ -z "$grasp_consensus" ]] && grasp_consensus=$(ls -t "$RESULTS_DIR"/grasp-consensus-*.md 2>/dev/null | head -1)
        log INFO "Skipping grasp phase (resuming)"
    fi

    # Phase 3: TANGLE (Develop)
    if [[ -z "$resume_from" || "$resume_from" == "null" || "$resume_from" == "probe" || "$resume_from" == "grasp" ]]; then
        export OCTOPUS_WORKFLOW_PHASE="tangle"
        _write_embrace_session_state "tangle" "running"
        echo ""
        echo -e "${CYAN}[3/4] Starting TANGLE phase (Develop)...${NC}"
        echo ""
        tangle_develop "$prompt" "$grasp_consensus"
        tangle_validation=$(ls -t "$RESULTS_DIR"/tangle-validation-*.md 2>/dev/null | head -1)

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
        [[ -z "$tangle_validation" ]] && tangle_validation=$(ls -t "$RESULTS_DIR"/tangle-validation-*.md 2>/dev/null | head -1)
        log INFO "Skipping tangle phase (resuming)"
    fi

    # Phase 4: INK (Deliver)
    export OCTOPUS_WORKFLOW_PHASE="ink"
    _write_embrace_session_state "ink" "running"
    echo ""
    echo -e "${CYAN}[4/4] Starting INK phase (Deliver)...${NC}"
    echo ""
    ink_deliver "$prompt" "$tangle_validation"

    # v7.25.0: Display phase metrics
    if command -v display_phase_metrics &> /dev/null; then
        display_phase_metrics "ink" 2>/dev/null || true
    fi

    # v8.14.0: Capture phase context in persistent state
    local ink_output
    ink_output=$(ls -t "$RESULTS_DIR"/delivery-*.md 2>/dev/null | head -1)
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
    [[ -n "$tangle_validation" ]] && echo -e "  Tangle: $tangle_validation"
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
    unset OCTOPUS_SKIP_PHASE_COST_PROMPT
    unset OCTOPUS_WORKFLOW_PHASE
    unset OCTOPUS_WORKFLOW_TYPE
    unset OCTOPUS_TASK_GROUP
    unset OCTOPUS_TOTAL_PHASES
    unset OCTOPUS_COMPLETED_PHASES
    unset CLAUDE_CODE_DISABLE_CRON 2>/dev/null || true
}
