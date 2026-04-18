#!/usr/bin/env bash
# spawn_agent — extracted from orchestrate.sh (v9.7.x)
# Agent spawning and lifecycle management

spawn_agent() {
    local _ts; _ts=$(date +%s)
    local agent_type="$1"
    local prompt="$2"
    local task_id="${3:-$_ts}"
    local role="${4:-}"         # Optional role override
    local phase="${5:-}"        # Optional phase context
    local use_fork="${6:-false}" # Optional fork context (v2.1.12+)

    # v7.25.0: Debug logging
    log "DEBUG" "spawn_agent: agent=$agent_type, task_id=$task_id, role=${role:-auto}, phase=${phase:-none}, fork=$use_fork"
    log "DEBUG" "spawn_agent: prompt_length=${#prompt} chars"

    # Fork context support (v2.1.12+)
    if [[ "$use_fork" == "true" ]] && [[ "$SUPPORTS_FORK_CONTEXT" == "true" ]]; then
        log "INFO" "Spawning $agent_type in fork context for isolation"

        # Create fork marker for tracking
        local fork_marker="${WORKSPACE_DIR}/forks/${task_id}.fork"
        mkdir -p "$(dirname "$fork_marker")"
        echo "$agent_type|$phase" > "$fork_marker"

        # Note: Actual fork context execution happens in Claude Code context
        # This marker allows orchestrate.sh to track fork-based agents
    elif [[ "$use_fork" == "true" ]] && [[ "$SUPPORTS_FORK_CONTEXT" != "true" ]]; then
        log "WARN" "Fork context requested but not supported, using standard execution"
        use_fork="false"
    fi

    # v8.34.0: Propagate Octopus env vars to worktree agents (G8)
    if [[ "$SUPPORTS_WORKTREE_HOOKS" == "true" ]]; then
        log "DEBUG" "Worktree hooks available — Octopus env vars will propagate via WorktreeCreate"
    fi

    # Determine role if not provided
    if [[ -z "$role" ]]; then
        local task_type
        task_type=$(classify_task "$prompt")
        role=$(get_role_for_context "$agent_type" "$task_type" "$phase")
    fi

    # v8.19.0: Check routing rules for role override
    local routed_role
    routed_role=$(match_routing_rule "$(classify_task "$prompt" 2>/dev/null)" "$prompt" 2>/dev/null) || true
    if [[ -n "$routed_role" ]]; then
        log DEBUG "Routing rules override: $role -> $routed_role"
        role="$routed_role"
    fi

    # v8.19.0: Check for checkpoint (crash-recovery)
    local checkpoint_ctx=""
    local checkpoint_data
    checkpoint_data=$(load_agent_checkpoint "$task_id" 2>/dev/null) || true
    if [[ -n "$checkpoint_data" ]]; then
        local partial_output
        if command -v jq &>/dev/null; then
            partial_output=$(echo "$checkpoint_data" | jq -r '.partial_output // ""' 2>/dev/null)
        else
            partial_output=$(echo "$checkpoint_data" | grep -o '"partial_output":"[^"]*"' | sed 's/"partial_output":"//;s/"$//')
        fi
        if [[ -n "$partial_output" ]]; then
            checkpoint_ctx="${partial_output:0:1500}"
            log INFO "Loaded checkpoint for task $task_id (${#checkpoint_ctx} chars)"
        fi
    fi

    # v8.34.0: Fast bash — skip login shell in spawned agents (G9)
    if [[ "$SUPPORTS_FAST_BASH" == "true" ]]; then
        export CLAUDE_BASH_NO_LOGIN=true
    fi

    # v8.53.0: Pre-compute curated_name before apply_persona so readonly flag is available
    local curated_name_early=""
    if [[ "$SUPPORTS_AGENT_TYPE_ROUTING" == "true" ]]; then
        curated_name_early=$(select_curated_agent "$prompt" "$phase") || true
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # Cache-aligned prompt structure: stable prefix first, variable suffix last
    # This enables Claude's cached-token discount on repeated prefix content
    #
    # STABLE PREFIX (identical across calls for same agent/role):
    #   1. Persona pack override (if any)
    #   2. Persona definition + task framing (apply_persona)
    #   3. Agent skill context (deterministic per agent type)
    #   4. Earned project skills (stable within a project session)
    #   5. Search spiral guard (static text, researcher role only)
    #
    # VARIABLE SUFFIX (changes per call):
    #   6. Checkpoint context (crash-recovery, ephemeral)
    #   7. Memory context (session-specific warm start)
    #   8. Provider history (per-provider learning, changes each run)
    #   9. Heuristic context (past-run file patterns)
    # ═══════════════════════════════════════════════════════════════════════════

    # ── STABLE PREFIX ─────────────────────────────────────────────────────────

    # Apply persona to prompt (v8.53.0: pass curated_name for readonly frontmatter check)
    local enhanced_prompt
    enhanced_prompt=$(apply_persona "$role" "$prompt" "false" "${curated_name_early:-}")

    # v8.21.0: Check for persona pack override
    if type get_persona_override &>/dev/null 2>&1 && [[ "${OCTOPUS_PERSONA_PACKS:-auto}" != "off" ]]; then
        local persona_override_file
        persona_override_file=$(get_persona_override "${curated_name_early:-${curated_name:-$agent_type}}" 2>/dev/null)
        if [[ -n "$persona_override_file" && -f "$persona_override_file" ]]; then
            local pack_persona
            pack_persona=$(cat "$persona_override_file" 2>/dev/null)
            if [[ -n "$pack_persona" ]]; then
                enhanced_prompt="${pack_persona}

---

${enhanced_prompt}"
                log "INFO" "Applied persona pack override from: $persona_override_file"
            fi
        fi
    fi

    # v8.2.0: Load agent skill context if available (STABLE — deterministic per agent type)
    # NOTE: enforce_context_budget() moved AFTER all injections (v8.10.0 Issue #25)
    if [[ "$SUPPORTS_AGENT_TYPE_ROUTING" == "true" ]]; then
        local curated_agent=""
        curated_agent=$(select_curated_agent "$prompt" "$phase") || true
        if [[ -n "$curated_agent" ]]; then
            local skill_context
            skill_context=$(build_skill_context "$curated_agent")
            if [[ -n "$skill_context" ]]; then
                # v9.15: Skill context in stable prefix for prompt cache alignment
                enhanced_prompt="${enhanced_prompt}

---

## Agent Skill Context
${skill_context}"
                log "DEBUG" "Injected skill context for agent: $curated_agent"
            fi
        fi
    fi

    # v8.18.0: Inject earned skills context (STABLE — changes rarely within a project)
    local earned_skills_ctx
    earned_skills_ctx=$(load_earned_skills 2>/dev/null)
    if [[ -n "$earned_skills_ctx" ]]; then
        # Truncate to 1500 chars
        if [[ ${#earned_skills_ctx} -gt 1500 ]]; then
            earned_skills_ctx="${earned_skills_ctx:0:1500}..."
        fi
        # v8.41.0: Wrap file-sourced earned skills in anti-injection nonce
        earned_skills_ctx=$(sanitize_external_content "$earned_skills_ctx" "earned-skills")
        enhanced_prompt="${enhanced_prompt}

---

## Earned Project Skills
${earned_skills_ctx}"
        log "DEBUG" "Injected earned skills context (${#earned_skills_ctx} chars)"
    fi

    # v9.3.0: Search spiral guard for researcher role (STABLE — static boilerplate)
    if [[ "$role" == "researcher" ]]; then
        enhanced_prompt="${enhanced_prompt}

IMPORTANT: If you find yourself searching or grepping more than 3 times in a row without reading files or writing analysis, STOP searching. Consolidate what you've found so far and write your analysis. More searching rarely improves the output — synthesis does."
    fi

    # ── VARIABLE SUFFIX ───────────────────────────────────────────────────────
    # Everything below changes per invocation (timestamps, session state, etc.)

    # v8.19.0: Inject checkpoint context if available (VARIABLE — ephemeral crash-recovery)
    if [[ -n "$checkpoint_ctx" ]]; then
        enhanced_prompt="${enhanced_prompt}

---

## Previous Attempt Context (crash-recovery)
${checkpoint_ctx}"
    fi

    # v8.2.0: Log enhanced agent fields + v8.5: Inject memory context (VARIABLE)
    if [[ "$SUPPORTS_AGENT_TYPE_ROUTING" == "true" ]]; then
        local curated_name
        curated_name=$(select_curated_agent "$prompt" "$phase") || true
        if [[ -n "$curated_name" ]]; then
            # v8.6.0: Export persona name for domain-specific gate scripts
            export OCTOPUS_AGENT_PERSONA="${curated_name}"

            local agent_mem agent_perm
            agent_mem=$(get_agent_memory "$curated_name")
            agent_perm=$(get_agent_permission_mode "$curated_name")
            log "DEBUG" "Agent fields: memory=$agent_mem, permissionMode=$agent_perm"

            # v8.5: Cross-memory warm start - inject memory context into prompt
            # v8.26: Skip when native auto-memory handles project/user scope (v2.1.59+)
            local _skip_mem=false
            if [[ "$SUPPORTS_NATIVE_AUTO_MEMORY" == "true" && "$agent_mem" != "local" && "$agent_mem" != "none" ]]; then
                _skip_mem=true
                log "DEBUG" "Skipping Octopus memory injection for $curated_name (scope=$agent_mem, native auto-memory active)"
            fi
            if [[ "$_skip_mem" != "true" && -n "$agent_mem" && "$agent_mem" != "none" ]]; then
                local memory_context
                memory_context=$(build_memory_context "$agent_mem")
                if [[ -n "$memory_context" ]]; then
                    # v8.41.0: Wrap file-sourced memory in anti-injection nonce
                    memory_context=$(sanitize_external_content "$memory_context" "memory")
                    enhanced_prompt="${enhanced_prompt}

---

## Previous Context (from ${agent_mem} memory)
${memory_context}"
                    log "INFO" "Injected ${agent_mem} memory context (${#memory_context} chars) for agent: $curated_name"
                fi
            fi
        fi
    fi

    # v8.18.0: Inject per-provider history context (VARIABLE — changes each run)
    local provider_ctx
    provider_ctx=$(build_provider_context "$agent_type")
    if [[ -n "$provider_ctx" ]]; then
        # v8.41.0: Wrap file-sourced provider history in anti-injection nonce
        provider_ctx=$(sanitize_external_content "$provider_ctx" "provider-history")
        enhanced_prompt="${enhanced_prompt}

---

${provider_ctx}"
        log "DEBUG" "Injected provider history context (${#provider_ctx} chars) for $agent_type"
    fi

    # v9.3.0: Inject heuristic context from past successful runs (VARIABLE)
    if [[ "${OCTOPUS_HEURISTIC_LEARNING:-on}" != "off" ]] && type build_heuristic_context &>/dev/null 2>&1; then
        local heuristic_ctx
        heuristic_ctx=$(build_heuristic_context "$enhanced_prompt" 2>/dev/null) || true
        if [[ -n "$heuristic_ctx" ]]; then
            heuristic_ctx=$(sanitize_external_content "$heuristic_ctx" "heuristics")
            enhanced_prompt="${enhanced_prompt}

---

## File Heuristics
${heuristic_ctx}"
            log "DEBUG" "Injected heuristic context (${#heuristic_ctx} chars)"
        fi
    fi

    # v8.10.0: Enforce context budget AFTER all injections (skill + memory)
    # Previously called before injections, causing final prompt to exceed budget (Issue #25)
    enhanced_prompt=$(enforce_context_budget "$enhanced_prompt" "${role:-}")

    # v8.4: Auto-route claude-opus to fast mode when appropriate
    # WARNING: Fast Opus is 6x more expensive ($30/$150 vs $5/$25 per MTok)
    # Only used for interactive single-shot tasks, never for multi-phase workflows
    if [[ "$agent_type" == "claude-opus" ]] && [[ "$SUPPORTS_FAST_OPUS" == "true" ]]; then
        local opus_tier
        opus_tier=$(get_agent_config "${curated_agent:-}" "tier" 2>/dev/null) || opus_tier="premium"
        local session_autonomy
        session_autonomy=$(jq -r '.autonomy // "supervised"' "${HOME}/.claude-octopus/session.json" 2>/dev/null) || session_autonomy="supervised"
        local opus_mode
        opus_mode=$(select_opus_mode "$phase" "$opus_tier" "$session_autonomy")
        if [[ "$opus_mode" == "fast" ]]; then
            agent_type="claude-opus-fast"
            log "INFO" "Auto-routing to Opus 4.6 Fast mode (phase=$phase, tier=$opus_tier, autonomy=$session_autonomy)"
            log "WARN" "Fast Opus is 6x more expensive: \$30/\$150 per MTok vs \$5/\$25 standard"
        fi
    fi

    # v9.13: Circuit breaker check — skip provider if circuit is open
    local provider_prefix="${agent_type%%-*}"  # codex-standard → codex
    if type is_provider_available &>/dev/null && ! is_provider_available "$provider_prefix"; then
        log "WARN" "Circuit open for $provider_prefix — skipping $agent_type (use fallback)"
        record_outcome "$provider_prefix" "$agent_type" "skipped" "${phase:-unknown}" "circuit_open" "0" 2>/dev/null || true
        return 1
    fi

    local cmd
    if ! cmd=$(get_agent_command "$agent_type" "${phase:-}" "${role:-}"); then
        log ERROR "Unknown agent type: $agent_type"
        log INFO "Available agents: $AVAILABLE_AGENTS"
        return 1
    fi

    # Validate command to prevent injection
    if ! validate_agent_command "$cmd"; then
        log ERROR "Invalid agent command returned: $cmd"
        return 1
    fi

    # Cursor Agent uses a generic `agent` binary name; validate binary identity
    # and auth at spawn time so all caller paths enforce the same guard.
    if [[ "$agent_type" == cursor-agent* ]] && ! cursor_agent_is_available; then
        log ERROR "Cursor Agent is not available or authenticated"
        return 1
    fi

    local log_file="${LOGS_DIR}/${agent_type}-${task_id}.log"
    local result_file="${RESULTS_DIR}/${agent_type}-${task_id}.md"

    # v8.52: Warn if spawning Claude agent on enterprise without subagent model fix (CC < v2.1.73)
    # Prior to v2.1.73, model: opus/sonnet/haiku in agent frontmatter was silently downgraded on Bedrock/Vertex/Foundry
    # v8.56: CC v2.1.74+ also accepts full model IDs (claude-opus-4-6) in agent model: field
    if [[ "$agent_type" == "claude"* ]] && [[ "$OCTOPUS_BACKEND" != "api" ]] && [[ "$SUPPORTS_SUBAGENT_MODEL_FIX" != "true" ]]; then
        log "WARN" "Enterprise backend ($OCTOPUS_BACKEND) + CC < v2.1.73: agent model frontmatter may be silently downgraded. Upgrade to CC v2.1.73+ to fix."
    elif [[ "$SUPPORTS_FULL_MODEL_IDS" == "true" ]]; then
        log "DEBUG" "CC v2.1.74+: full model IDs (e.g. claude-opus-4-6) supported in agent frontmatter"
    fi

    # v8.57: CC v2.1.76+ preserves partial results when background agents are killed
    # Multi-agentic workflows (/octo:research, /octo:parallel) can safely time out agents
    if [[ "$SUPPORTS_BG_PARTIAL_RESULTS" == "true" ]]; then
        log "DEBUG" "CC v2.1.76+: background agent partial results preserved on kill"
    fi

    log INFO "Spawning $agent_type agent (task: $task_id, role: ${role:-none})"
    log DEBUG "Command: $cmd"
    log DEBUG "Phase: ${phase:-none}, Role: ${role:-none}"

    # Record usage (get model from agent type, with phase/role context)
    local model
    model=$(get_agent_model "$agent_type" "${phase:-}" "${role:-}")
    log "DEBUG" "Model selected: $model (from agent_type=$agent_type, phase=${phase:-none})"

    # v8.35.0: Adaptive reasoning effort per phase
    # get_effort_level() maps phase+complexity to low/medium/high effort
    # Only active when SUPPORTS_OPUS_MEDIUM_EFFORT=true (Claude Code v2.1.68+)
    local effort_level=""
    if [[ "$SUPPORTS_OPUS_MEDIUM_EFFORT" == "true" ]]; then
        effort_level=$(get_effort_level "${phase:-unknown}")
        if [[ -n "$effort_level" ]]; then
            export OCTOPUS_EFFORT_LEVEL="$effort_level"
            log "DEBUG" "Effort level: $effort_level (phase=${phase:-unknown})"
            # v8.40.0: Display effort level in agent spawn output when supported
            if [[ "$SUPPORTS_EFFORT_CALLOUT" == "true" ]]; then
                # v8.48.0: Use v2.1.72 effort symbols when available
                local effort_symbol=""
                if [[ "$SUPPORTS_EFFORT_REDESIGN" == "true" ]]; then
                    case "$effort_level" in
                        low) effort_symbol="○" ;;
                        medium) effort_symbol="◐" ;;
                        high) effort_symbol="●" ;;
                    esac
                    log "USER" "  Effort: ${effort_symbol} ${effort_level}"
                else
                    log "USER" "  Effort: $effort_level"
                fi
            fi
        fi
    fi

    record_agent_call "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}" "${role:-none}" "0"

    # v8.14.0: Track provider usage in persistent state
    local provider_name
    case "$agent_type" in
        codex*) provider_name="codex" ;;
        gemini*) provider_name="gemini" ;;
        claude*) provider_name="claude" ;;
        *) provider_name="$agent_type" ;;
    esac
    update_metrics "provider" "$provider_name" 2>/dev/null || true

    # v8.7.0: Register task in bridge ledger (non-fatal if ledger missing)
    bridge_register_task "$task_id" "$agent_type" "${phase:-unknown}" "${role:-none}" || true

    # Record metrics start (v7.25.0)
    local metrics_id=""
    if command -v record_agent_start &> /dev/null; then
        metrics_id=$(record_agent_start "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}") || true
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd with role=${role:-none}"
        return 0
    fi

    # Store metrics mapping for batch completion recording (after DRY_RUN gate)
    if [[ -n "$metrics_id" ]]; then
        local metrics_base="${WORKSPACE_DIR:-${HOME}/.claude-octopus}"
        local metrics_map="${metrics_base}/.metrics-map"
        echo "${task_group:-${task_id}}:${metrics_id}:${agent_type}:${model}" >> "$metrics_map"
    fi

    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
    touch "$PID_FILE"

    # v8.5: Agent Teams dispatch for Claude agents
    if should_use_agent_teams "$agent_type"; then
        log "INFO" "Dispatching via Agent Teams: $agent_type (task: $task_id)"

        # Write structured agent instruction for Claude Code's native team dispatch
        # The agent instruction file is picked up by teammate-idle-dispatch.sh
        local teams_dir="${WORKSPACE_DIR}/agent-teams"
        mkdir -p "$teams_dir"

        local agent_instruction_file="${teams_dir}/${task_id}.json"
        if command -v jq &>/dev/null; then
            jq -n \
                --arg agent_type "$agent_type" \
                --arg task_id "$task_id" \
                --arg role "${role:-none}" \
                --arg phase "${phase:-none}" \
                --arg model "$model" \
                --arg prompt "$enhanced_prompt" \
                --arg result_file "$result_file" \
                --arg effort "${effort_level:-medium}" \
                --arg model_override "$SUPPORTS_AGENT_MODEL_OVERRIDE" \
                '{agent_type: $agent_type, task_id: $task_id, role: $role,
                  phase: $phase, model: $model, prompt: $prompt,
                  result_file: $result_file, dispatch_method: "agent_teams",
                  effort: $effort,
                  model_override_supported: ($model_override == "true"),
                  agent_id: "", dispatched_at: now | todate}' \
                > "$agent_instruction_file" 2>/dev/null
        fi

        # v8.30: Write task_id mapping for agent_id correlation (continuation support)
        if [[ "$SUPPORTS_CONTINUATION" == "true" ]]; then
            local task_map_file="${teams_dir}/.task-agent-map"
            echo "${task_id}:" >> "$task_map_file"
            log "DEBUG" "Registered task $task_id for agent_id correlation"
        fi

        # Output structured instruction for Claude Code to pick up
        echo "AGENT_TEAMS_DISPATCH:${agent_type}:${task_id}:${role:-none}:${phase:-none}"

        # Write initial result file header
        echo "# Agent: $agent_type (via Agent Teams)" > "$result_file"
        echo "# Task ID: $task_id" >> "$result_file"
        echo "# Role: ${role:-none}" >> "$result_file"
        echo "# Phase: ${phase:-none}" >> "$result_file"
        echo "# Dispatch: Agent Teams (native)" >> "$result_file"
        echo "# Started: $(date)" >> "$result_file"
        if [[ "$SUPPORTS_HOOK_LAST_MESSAGE" == "true" ]]; then
            echo "# Result-capture: SubagentStop hook" >> "$result_file"
        fi
        echo "" >> "$result_file"

        log "DEBUG" "Agent Teams instruction written to: $agent_instruction_file"
        if [[ "$SUPPORTS_HOOK_LAST_MESSAGE" == "true" ]]; then
            log "DEBUG" "Result capture via SubagentStop hook (last_assistant_message)"
        fi
        return 0
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # LEGACY PATH: Execute agent in bash subprocess (Codex/Gemini or teams unavailable)
    # ═══════════════════════════════════════════════════════════════════════════

    # Execute agent in background
    (
        cd "$PROJECT_ROOT" || exit 1
        set -f  # Disable glob expansion
        set -o pipefail  # v9.15.1: Pipeline exit code = first failure (prevents silent codex/gemini errors)

        echo "# Agent: $agent_type" > "$result_file"
        echo "# Task ID: $task_id" >> "$result_file"
        echo "# Role: ${role:-none}" >> "$result_file"
        echo "# Phase: ${phase:-none}" >> "$result_file"
        echo "# Prompt: $prompt" >> "$result_file"
        echo "# Started: $(date)" >> "$result_file"
        echo "" >> "$result_file"
        echo "## Output" >> "$result_file"
        echo '```' >> "$result_file"

        # SECURITY: Use array-based execution to prevent word-splitting vulnerabilities
        # v8.32.0: Per-provider credential isolation — each agent only sees its own API key
        local -a cmd_array
        local env_prefix
        env_prefix=$(build_provider_env "$agent_type")
        if [[ -n "$env_prefix" ]]; then
            read -ra cmd_array <<< "$env_prefix $cmd"
            log "DEBUG" "Credential isolation active for $agent_type"
        else
            read -ra cmd_array <<< "$cmd"
        fi

        # IMPROVED: Use temp files for reliable output capture (v7.13.2 - Issue #10)
        # v7.19.0 P0.1: Real-time output streaming to result file
        local temp_output="${RESULTS_DIR}/.tmp-${task_id}.out"
        local temp_errors="${RESULTS_DIR}/.tmp-${task_id}.err"
        local raw_output="${RESULTS_DIR}/.raw-${task_id}.out"  # Backup of unfiltered output

        # Update task progress with context-aware spinner verb (v7.16.0 Feature 1)
        if [[ -n "$CLAUDE_TASK_ID" ]]; then
            local active_verb
            active_verb=$(get_active_form_verb "$phase" "$agent_type" "$prompt")
            update_task_progress "$CLAUDE_TASK_ID" "$active_verb"
        fi

        # Mark agent as running and capture start time (v7.16.0 Feature 2)
        local start_time_ms
        # Use seconds instead of milliseconds for compatibility (macOS date doesn't support %N)
        start_time_ms=$(( $(date +%s) * 1000 ))
        update_agent_status "$agent_type" "running" 0 0.0

        # v7.19.0 P0.1: Use tee to stream output to both temp file and raw backup
        # v8.10.0: Gemini uses stdin-based prompt delivery (Issue #25)
        # -p "" triggers headless mode; prompt content comes via stdin to avoid OS arg limits

        # v8.16: Auth-aware retry for enterprise backends
        local max_auth_retries=0
        if [[ "$OCTOPUS_BACKEND" != "api" ]]; then
            max_auth_retries="${OCTOPUS_AUTH_RETRIES:-2}"
        fi
        # On stable auth (v2.1.44+), reduce retry aggressiveness
        if [[ "$SUPPORTS_STABLE_AUTH" == "true" ]]; then
            max_auth_retries=$((max_auth_retries > 1 ? 1 : max_auth_retries))
        fi

        # Append headless flag (-p "") for CLI providers that read prompt from stdin
        if [[ "$agent_type" == gemini* ]] || [[ "$agent_type" == cursor-agent* ]] || [[ "$agent_type" == copilot* ]] || [[ "$agent_type" == qwen* ]]; then
            cmd_array+=(-p "")
        fi

        # v9.2.2: Inject subagent preamble for Codex dispatches (Issue #176)
        if [[ "$agent_type" == codex* && "$agent_type" != "codex-review" ]]; then
            enhanced_prompt="${CODEX_SUBAGENT_PREAMBLE}${enhanced_prompt}"
        fi

        local auth_attempt=0
        local exit_code=0
        while true; do
            exit_code=0
            # v9.2.2: All agents use stdin-based prompt delivery to avoid ARG_MAX limits (Issue #173)
            # Previously only gemini used stdin; codex/claude passed prompt as CLI arg which fails on large diffs
            if printf '%s' "$enhanced_prompt" | run_with_timeout "$TIMEOUT" "${cmd_array[@]}" 2> "$temp_errors" | tee "$raw_output" > "$temp_output"; then
                exit_code=0
            else
                exit_code=$?
            fi

            # v8.16: Check if failure is auth-related and retryable
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
                    log "WARN" "Auth failure detected (attempt $auth_attempt/$max_auth_retries), retrying in ${backoff}s..."
                    sleep "$backoff"
                    # Clear temp files for retry
                    > "$temp_output"
                    > "$temp_errors"
                    > "$raw_output"
                    continue
                fi
            fi
            break
        done

        # v8.16: Log auth retry metrics if retries occurred
        if [[ $auth_attempt -gt 0 ]]; then
            log "INFO" "Auth retries used: $auth_attempt/$max_auth_retries (backend=$OCTOPUS_BACKEND, exit=$exit_code)"
        fi

        # v8.32: Skip CLI output capture if SubagentStop hook already wrote the result
        local _hook_captured=false
        if [[ "$SUPPORTS_HOOK_LAST_MESSAGE" == "true" ]] && grep -q "Capture: SubagentStop hook" "$result_file" 2>/dev/null; then
            _hook_captured=true
            log "DEBUG" "Result already captured by SubagentStop hook, skipping CLI output parse"
        fi

        # v7.19.0 P0.1: Process output regardless of exit code (preserves partial results)
        if [[ "$_hook_captured" == "true" ]]; then
            # Hook already wrote ## Output + ## Status: SUCCESS — skip to post-processing
            :
        elif [[ $exit_code -eq 0 ]]; then
            # Filter out CLI header noise and extract actual response
            # v9.3.1: Check for CLI header separator before filtering — codex exec
            # sends clean response on stdout (no header), banner on stderr.
            if [[ $(grep -c '^--------$' "$temp_output" 2>/dev/null || true) -gt 0 ]]; then
                # CLI-wrapped output: strip banner and extract response
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
                # Clean stdout (e.g. codex exec) — pass through with noise filtering
                # v9.15.1: Filter Gemini MCP status messages and CLI preamble from stdout
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

            # v8.7.0: Add trust marker for external CLI output
            # v9.22.1: Also wrap the Output block in nonce boundaries so downstream
            # synthesis prompts can identify provider-authored text as untrusted.
            case "$agent_type" in codex*|gemini*|perplexity*|cursor-agent*)
                if [[ "${OCTOPUS_SECURITY_V870:-true}" == "true" ]]; then
                    sed -i.bak '1s/^/<!-- trust=untrusted provider='"$agent_type"' -->\n/' "$result_file" 2>/dev/null || true
                    rm -f "${result_file}.bak"
                fi
                # Close the fenced block, then append an END marker (BEGIN goes below)
                echo '```' >> "$result_file"
                local _untrusted_nonce
                _untrusted_nonce=$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null) \
                    || _untrusted_nonce="${RANDOM}${RANDOM}${RANDOM}$(date +%s)"
                echo "<!-- END-UNTRUSTED:provider=${agent_type}:nonce=${_untrusted_nonce} -->" >> "$result_file"
                # Insert the BEGIN marker just above the "## Output" header
                awk -v marker="<!-- BEGIN-UNTRUSTED:provider=${agent_type}:nonce=${_untrusted_nonce} -->" '
                    /^## Output$/ && !done { print marker; done=1 }
                    { print }
                ' "$result_file" > "${result_file}.nonce" && mv "${result_file}.nonce" "$result_file"
                ;;
            *)
                echo '```' >> "$result_file"
                ;;
            esac

            echo "" >> "$result_file"
            echo "## Status: SUCCESS" >> "$result_file"

            # v8.6.0: Preserve native metrics block for batch completion
            if [[ -s "$raw_output" ]]; then
                local usage_block
                usage_block=$(sed -n '/<usage>/,/<\/usage>/p' "$raw_output" 2>/dev/null || true)
                if [[ -n "$usage_block" ]]; then
                    echo "" >> "$result_file"
                    echo "## Native Metrics" >> "$result_file"
                    echo "$usage_block" >> "$result_file"
                fi
            fi

            # Append stderr if it contains useful content (not just warnings)
            if [[ -s "$temp_errors" ]] && ! grep -q "^mcp startup:" "$temp_errors"; then
                echo "" >> "$result_file"
                echo "## Warnings/Errors" >> "$result_file"
                echo '```' >> "$result_file"
                cat "$temp_errors" >> "$result_file"
                echo '```' >> "$result_file"
            fi

            # Mark agent as completed (v7.16.0 Feature 2)
            local end_time_ms elapsed_ms
            end_time_ms=$(( $(date +%s) * 1000 ))
            elapsed_ms=$((end_time_ms - start_time_ms))
            update_agent_status "$agent_type" "completed" "$elapsed_ms" 0.0
            # v8.18.0: Record provider learning
            local result_summary
            result_summary=$(head -c 200 "$result_file" 2>/dev/null | tr '\n' ' ')
            append_provider_history "$agent_type" "${phase:-unknown}" "${enhanced_prompt:0:100}" "$result_summary" 2>/dev/null || true
            # v8.20.0: Record outcome for provider intelligence
            record_outcome "$agent_type" "$agent_type" "${task_type:-unknown}" "${phase:-unknown}" "success" "$elapsed_ms" 2>/dev/null || true
            # v9.13: Reset circuit breaker on success
            type record_success &>/dev/null && record_success "$provider_prefix" 2>/dev/null || true
            # v9.3.0: Record file co-occurrence pattern for heuristic learning
            record_run_pattern "$agent_type" "${enhanced_prompt:-$prompt}" "$result_file" 2>/dev/null || true
            # v8.20.1: Record task duration metric
            record_task_metric "task_duration_ms" "$elapsed_ms" 2>/dev/null || true
            # v8.21.0: Anti-drift checkpoint (non-blocking)
            if type run_drift_check &>/dev/null 2>&1; then
                run_drift_check "${enhanced_prompt:-$prompt}" "$(cat "$result_file" 2>/dev/null)" "$agent_type" "${phase:-unknown}" 2>/dev/null || true
            fi
        elif [[ $exit_code -eq 124 ]] || [[ $exit_code -eq 143 ]]; then
            # v7.19.0 P0.2: TIMEOUT - Preserve partial output
            # Process whatever output exists (may be significant partial work)
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
            elif [[ -s "$raw_output" ]]; then
                # Fallback: use raw output if filtered output is empty
                cat "$raw_output" >> "$result_file"
            else
                echo "(no output captured before timeout)" >> "$result_file"
            fi
            echo '```' >> "$result_file"
            echo "" >> "$result_file"
            echo "## Status: TIMEOUT - PARTIAL RESULTS (exit code: $exit_code)" >> "$result_file"
            echo "" >> "$result_file"
            echo "⚠️  **Warning**: Agent timed out after ${TIMEOUT}s but partial output preserved above." >> "$result_file"
            echo "" >> "$result_file"
            echo "**Recommendations**:" >> "$result_file"
            echo "- Partial results may still be valuable" >> "$result_file"
            echo "- Consider increasing timeout: \`--timeout $((TIMEOUT * 2))\`" >> "$result_file"
            echo "- Simplify prompt to reduce complexity" >> "$result_file"

            # Append error details
            if [[ -s "$temp_errors" ]]; then
                echo "" >> "$result_file"
                echo "## Error Log" >> "$result_file"
                echo '```' >> "$result_file"
                cat "$temp_errors" >> "$result_file"
                echo '```' >> "$result_file"
            fi

            # v8.19.0: Record timeout error and save checkpoint
            record_error "$agent_type" "$prompt" "Agent timed out" "124" "spawn_agent timeout" 2>/dev/null || true
            local timeout_partial=""
            [[ -s "$temp_output" ]] && timeout_partial=$(<"$temp_output")
            [[ -z "$timeout_partial" && -s "$raw_output" ]] && timeout_partial=$(<"$raw_output")
            save_agent_checkpoint "$task_id" "$agent_type" "${phase:-unknown}" "$timeout_partial" 2>/dev/null || true

            # Mark agent as timeout (partial success) (v7.19.0)
            local end_time_ms elapsed_ms
            end_time_ms=$(( $(date +%s) * 1000 ))
            elapsed_ms=$((end_time_ms - start_time_ms))
            update_agent_status "$agent_type" "timeout" "$elapsed_ms" 0.0
            # v8.20.0: Record timeout for provider intelligence
            record_outcome "$agent_type" "$agent_type" "${task_type:-unknown}" "${phase:-unknown}" "timeout" "$elapsed_ms" 2>/dev/null || true
            # v9.13: Record timeout as transient failure for circuit breaker
            type record_failure &>/dev/null && record_failure "$provider_prefix" "transient" 2>/dev/null || true
        else
            # v7.19.0 P0.2: Other failures - still try to preserve output
            if [[ -s "$temp_output" ]]; then
                cat "$temp_output" >> "$result_file"
            elif [[ -s "$raw_output" ]]; then
                cat "$raw_output" >> "$result_file"
            else
                echo "(no output captured)" >> "$result_file"
            fi
            echo '```' >> "$result_file"
            echo "" >> "$result_file"
            echo "## Status: FAILED (exit code: $exit_code)" >> "$result_file"

            # Append error details
            if [[ -s "$temp_errors" ]]; then
                echo "" >> "$result_file"
                echo "## Error Log" >> "$result_file"
                echo '```' >> "$result_file"
                cat "$temp_errors" >> "$result_file"
                echo '```' >> "$result_file"
            fi

            # v8.19.0: Record error for learning loop
            local error_detail=""
            [[ -s "$temp_errors" ]] && error_detail=$(head -5 "$temp_errors")
            record_error "$agent_type" "$prompt" "${error_detail:-Unknown error}" "$exit_code" "spawn_agent failure" 2>/dev/null || true

            # v8.19.0: Save checkpoint for crash-recovery
            local partial_for_checkpoint=""
            [[ -s "$temp_output" ]] && partial_for_checkpoint=$(<"$temp_output")
            [[ -z "$partial_for_checkpoint" && -s "$raw_output" ]] && partial_for_checkpoint=$(<"$raw_output")
            save_agent_checkpoint "$task_id" "$agent_type" "${phase:-unknown}" "$partial_for_checkpoint" 2>/dev/null || true

            # Mark agent as failed (v7.16.0 Feature 2)
            local end_time_ms elapsed_ms
            end_time_ms=$(( $(date +%s) * 1000 ))
            elapsed_ms=$((end_time_ms - start_time_ms))
            update_agent_status "$agent_type" "failed" "$elapsed_ms" 0.0
            # v8.20.0: Record failure for provider intelligence
            record_outcome "$agent_type" "$agent_type" "${task_type:-unknown}" "${phase:-unknown}" "fail" "$elapsed_ms" 2>/dev/null || true
            # v9.13: Record failure for circuit breaker (classify from error output if available)
            if type record_failure &>/dev/null; then
                local _err_class="transient"
                if [[ -s "$temp_errors" ]]; then
                    _err_class=$(classify_error "$(head -c 200 "$temp_errors" 2>/dev/null)" 2>/dev/null) || _err_class="transient"
                fi
                record_failure "$provider_prefix" "$_err_class" 2>/dev/null || true
            fi
        fi

        # v7.19.0 P0.1: Verify result file has meaningful content
        local result_size
        result_size=$(wc -c < "$result_file" 2>/dev/null || echo "0")
        if [[ $result_size -lt 1024 ]] && [[ -s "$raw_output" ]]; then
            # Result file is suspiciously small but raw output exists - append raw output
            echo "" >> "$result_file"
            echo "## Raw Output (filter may have removed valid content)" >> "$result_file"
            echo '```' >> "$result_file"
            cat "$raw_output" >> "$result_file"
            echo '```' >> "$result_file"
        fi

        # Cleanup temp files (keep raw_output for debugging if result is empty)
        rm -f "$temp_output" "$temp_errors"
        if [[ $result_size -ge 1024 ]]; then
            rm -f "$raw_output"  # Clean up if result looks good
        fi

        echo "# Completed: $(date)" >> "$result_file"

        # v8.7.0: Record result hash for integrity verification
        record_result_hash "$result_file"

        # Ensure file is fully written before background process exits
        sync

        # v8.19.0: Cleanup heartbeat (self-terminating monitor handles this too)
        cleanup_heartbeat "$$" 2>/dev/null || true
    ) &

    local pid=$!

    # v8.19.0: Start heartbeat monitor for agent process
    start_heartbeat_monitor "$pid" "$task_id"

    # Atomic PID file write with file locking to prevent race conditions
    # Use flock on Linux, skip locking on macOS (flock not available)
    if command -v flock &>/dev/null; then
        (
            flock -x 200
            echo "$pid:$agent_type:$task_id" >> "$PID_FILE"
        ) 200>"${PID_FILE}.lock"
    else
        # macOS fallback: simple append (race condition risk is low for our use case)
        echo "$pid:$agent_type:$task_id" >> "$PID_FILE"
    fi

    log INFO "Agent spawned with PID: $pid"
    echo "$pid"
}
