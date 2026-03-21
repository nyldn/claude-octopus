#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# agent-sync.sh — Agent synchronous dispatch & Agent Teams routing
# Extracted from orchestrate.sh (v9.7.4)
# ═══════════════════════════════════════════════════════════════════════════════

# Check if an agent should use Agent Teams dispatch
# Returns 0 (true) if agent should use native teams, 1 (false) for legacy bash
should_use_agent_teams() {
    local agent_type="$1"

    # P0-B fix: When orchestrate.sh runs as a Bash tool subprocess (not inside
    # Claude Code's native context), Agent Teams JSON instruction files are never
    # picked up and SubagentStop hooks never fire.  Probe phase sets this flag
    # before spawning agents in parallel background subshells.
    if [[ "${OCTOPUS_FORCE_LEGACY_DISPATCH:-}" == "true" ]]; then
        log "DEBUG" "Force legacy dispatch active — skipping Agent Teams for $agent_type"
        return 1
    fi

    # User override: force legacy mode
    if [[ "$OCTOPUS_AGENT_TEAMS" == "legacy" ]]; then
        return 1
    fi

    # User override: force native for Claude agents
    if [[ "$OCTOPUS_AGENT_TEAMS" == "native" ]]; then
        case "$agent_type" in
            claude|claude-sonnet|claude-opus|claude-opus-fast)
                if [[ "$SUPPORTS_STABLE_AGENT_TEAMS" == "true" ]]; then
                    return 0
                else
                    log "WARN" "Agent Teams forced but SUPPORTS_STABLE_AGENT_TEAMS not available"
                    return 1
                fi
                ;;
            *)
                # Non-Claude agents always use legacy (external CLIs)
                return 1
                ;;
        esac
    fi

    # Auto mode: use teams for Claude agents when stable teams are available
    if [[ "$SUPPORTS_STABLE_AGENT_TEAMS" == "true" ]]; then
        case "$agent_type" in
            claude|claude-sonnet|claude-opus|claude-opus-fast)
                return 0
                ;;
        esac
    fi

    return 1
}

# Synchronous agent execution (for sequential steps within phases)
run_agent_sync() {
    local agent_type="$1"
    local prompt="$2"
    local timeout_secs="${3:-120}"
    local role="${4:-}"   # Optional role override
    local phase="${5:-}"  # Optional phase context

    # v8.19.0: Dynamic timeout calculation (when caller uses default 120)
    if [[ "$timeout_secs" -eq 120 ]]; then
        local task_type_for_timeout
        task_type_for_timeout=$(classify_task "$prompt" 2>/dev/null) || task_type_for_timeout="standard"
        timeout_secs=$(compute_dynamic_timeout "$task_type_for_timeout" "$prompt")
    fi

    # Determine role if not provided
    if [[ -z "$role" ]]; then
        local task_type
        task_type=$(classify_task "$prompt")
        role=$(get_role_for_context "$agent_type" "$task_type" "$phase")
    fi

    # Apply persona to prompt (v8.53.0: empty agent_name — readonly not enforced in sync agents)
    local enhanced_prompt
    enhanced_prompt=$(apply_persona "$role" "$prompt" "false" "")

    # v8.21.0: Check for persona pack override (run_agent_sync)
    if type get_persona_override &>/dev/null 2>&1 && [[ "${OCTOPUS_PERSONA_PACKS:-auto}" != "off" ]]; then
        local persona_override_file
        persona_override_file=$(get_persona_override "$agent_type" 2>/dev/null)
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

    # v8.18.0: Inject per-provider history context
    local provider_ctx
    provider_ctx=$(build_provider_context "$agent_type")
    if [[ -n "$provider_ctx" ]]; then
        # v8.41.0: Wrap file-sourced provider history in anti-injection nonce
        provider_ctx=$(sanitize_external_content "$provider_ctx" "provider-history")
        enhanced_prompt="${enhanced_prompt}

---

${provider_ctx}"
    fi

    # v8.18.0: Inject earned skills context
    local earned_skills_ctx
    earned_skills_ctx=$(load_earned_skills 2>/dev/null)
    if [[ -n "$earned_skills_ctx" ]]; then
        if [[ ${#earned_skills_ctx} -gt 1500 ]]; then
            earned_skills_ctx="${earned_skills_ctx:0:1500}..."
        fi
        enhanced_prompt="${enhanced_prompt}

---

## Earned Project Skills
${earned_skills_ctx}"
    fi

    log DEBUG "run_agent_sync: agent=$agent_type, role=${role:-none}, phase=${phase:-none}"

    # Record usage (get model from agent type)
    local model
    model=$(get_agent_model "$agent_type" "$phase" "$role")

    # v8.49.0: Pre-dispatch health check — verify provider is reachable
    local _provider_for_health=""
    case "$agent_type" in
        codex*)      _provider_for_health="codex" ;;
        gemini*)     _provider_for_health="gemini" ;;
        claude*)     _provider_for_health="claude" ;;
        openrouter*) _provider_for_health="openrouter" ;;
        perplexity*) _provider_for_health="perplexity" ;;
        copilot*)    _provider_for_health="copilot" ;;
    esac
    if [[ -n "$_provider_for_health" ]]; then
        local _health_diag
        if ! _health_diag=$(check_provider_health "$_provider_for_health" 2>&1); then
            log WARN "Provider '$_provider_for_health' health check failed: $_health_diag"
            log WARN "Skipping agent dispatch for $agent_type (provider unavailable)"
            echo "[Provider $_provider_for_health unavailable: $_health_diag]"
            return 1
        fi
    fi

    record_agent_call "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}" "${role:-none}" "0"

    # v7.25.0: Record metrics start
    local metrics_id=""
    if command -v record_agent_start &> /dev/null; then
        metrics_id=$(record_agent_start "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}") || true
    fi

    local cmd
    cmd=$(get_agent_command "$agent_type" "$phase" "$role") || return 1

    # SECURITY: Use array-based execution to prevent word-splitting vulnerabilities
    local -a cmd_array
    read -ra cmd_array <<< "$cmd"

    # Capture output and exit code separately
    local output
    local exit_code
    local temp_err="${RESULTS_DIR}/.tmp-agent-error-$$.err"

    # v8.10.0: Gemini uses stdin-based prompt delivery (Issue #25)
    # -p "" triggers headless mode; prompt content comes via stdin to avoid OS arg limits
    if [[ "$agent_type" == gemini* ]]; then
        cmd_array+=(-p "")
    fi

    # v9.2.2: Inject subagent preamble for Codex dispatches (Issue #176)
    if [[ "$agent_type" == codex* && "$agent_type" != "codex-review" ]]; then
        enhanced_prompt="${CODEX_SUBAGENT_PREAMBLE}${enhanced_prompt}"
    fi

    # v9.2.2: All agents use stdin to avoid ARG_MAX "Argument list too long" on large diffs (Issue #173)
    output=$(printf '%s' "$enhanced_prompt" | run_with_timeout "$timeout_secs" "${cmd_array[@]}" 2>"$temp_err")
    exit_code=$?

    # Check exit code and handle errors
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Agent $agent_type failed with exit code $exit_code (role=$role, phase=$phase)"
        if [[ -s "$temp_err" ]]; then
            log ERROR "Error details: $(cat "$temp_err")"
        fi
        rm -f "$temp_err"
        return $exit_code
    fi

    # v8.7.0: Wrap external CLI output with trust markers
    case "$agent_type" in codex*|gemini*|perplexity*|copilot*)
        output=$(wrap_cli_output "$agent_type" "$output") ;; esac

    # Check if output is suspiciously empty or placeholder
    if [[ -z "$output" || "$output" == "Provider available" ]]; then
        log WARN "Agent $agent_type returned empty or placeholder output (role=$role, phase=$phase)"
        if [[ -s "$temp_err" ]]; then
            log WARN "Possible issue: $(cat "$temp_err")"
        fi
    fi

    rm -f "$temp_err"

    # v7.25.0: Record metrics completion
    if [[ -n "$metrics_id" ]] && command -v record_agent_complete &> /dev/null; then
        # v8.6.0: Pass native metrics from Task tool output
        parse_task_metrics "$output"
        record_agent_complete "$metrics_id" "$agent_type" "$model" "$output" "${phase:-unknown}" \
            "$_PARSED_TOKENS" "$_PARSED_TOOL_USES" "$_PARSED_DURATION_MS" 2>/dev/null || true
    fi

    echo "$output"
    return 0
}
