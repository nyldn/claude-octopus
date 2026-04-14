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

    # ═══════════════════════════════════════════════════════════════════════════
    # Cache-aligned prompt structure: stable prefix first, variable suffix last
    # This enables Claude's cached-token discount on repeated prefix content
    # ═══════════════════════════════════════════════════════════════════════════

    # ── STABLE PREFIX ─────────────────────────────────────────────────────────

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

    # v8.18.0: Inject earned skills context (STABLE — changes rarely within a project)
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

    # ── VARIABLE SUFFIX ───────────────────────────────────────────────────────

    # v8.18.0: Inject per-provider history context (VARIABLE — changes each run)
    local provider_ctx
    provider_ctx=$(build_provider_context "$agent_type")
    if [[ -n "$provider_ctx" ]]; then
        # v8.41.0: Wrap file-sourced provider history in anti-injection nonce
        provider_ctx=$(sanitize_external_content "$provider_ctx" "provider-history")
        enhanced_prompt="${enhanced_prompt}

---

${provider_ctx}"
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
    # WHY capture start+cwd: on timeout we use these to detect whether the
    # provider wrote deliverables to disk before SIGTERM.
    local _dispatch_start _dispatch_cwd
    _dispatch_start=$(date +%s)
    _dispatch_cwd=$(pwd)
    output=$(printf '%s' "$enhanced_prompt" | run_with_timeout "$timeout_secs" "${cmd_array[@]}" 2>"$temp_err")
    exit_code=$?

    # WHY tail-bias: codex-style output puts the deliverable summary at the
    # END, so head-bias would drop exactly the section the user relies on.
    # Unbounded capture also blows up downstream prompt context.
    local _max_bytes="${OCTOPUS_AGENT_MAX_OUTPUT_BYTES:-262144}"
    if [[ -n "$output" && $_max_bytes -gt 0 && ${#output} -gt $_max_bytes ]]; then
        local _orig_bytes=${#output}
        local _head_bytes=4096
        local _tail_bytes=$((_max_bytes - _head_bytes - 256))
        # WHY positive offset form: `${output: -$n}` (space-prefixed negative
        # offset) is bash 4.2+; repo supports bash 3.x.
        local _tail_start=$((_orig_bytes - _tail_bytes))
        [[ $_tail_start -lt 0 ]] && _tail_start=0
        local _head="${output:0:$_head_bytes}"
        local _tail="${output:$_tail_start:$_tail_bytes}"
        output="${_head}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  OUTPUT TRUNCATED — ${_orig_bytes} bytes captured, showing first ${_head_bytes}B + last ${_tail_bytes}B
   (override with OCTOPUS_AGENT_MAX_OUTPUT_BYTES=<bytes>; 0 disables cap)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${_tail}"
        log WARN "Agent $agent_type output truncated: ${_orig_bytes}B → ${#output}B (cap=${_max_bytes}B)"
    fi

    # Check exit code and handle errors
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Agent $agent_type failed with exit code $exit_code (role=$role, phase=$phase)"
        if [[ -s "$temp_err" ]]; then
            log ERROR "Error details: $(cat "$temp_err")"
        fi
        # WHY: a bare "TIMEOUT" banner at heartbeat.sh leads users to discard
        # completed work when codex under workspace-write had already written
        # deliverables before SIGTERM. Surface that signal so the caller can
        # decide whether to keep them.
        if [[ $exit_code -eq 124 || $exit_code -eq 143 ]]; then
            # WHY feature-detect -newermt: GNU findutils only. BSD find (stock
            # macOS) would silently error; we skip the diagnostic there rather
            # than mis-report. Callers on macOS still see the underlying
            # timeout log — they just don't get the partial-writes hint.
            if find /dev/null -newermt "@0" >/dev/null 2>&1; then
                # WHY -maxdepth: bounds traversal on large monorepos (otherwise
                # find stats every file in the tree on every timeout).
                # OCTOPUS_PARTIAL_WRITES_DEPTH overrides for niche layouts.
                local _changed
                _changed=$(find "$_dispatch_cwd" -maxdepth "${OCTOPUS_PARTIAL_WRITES_DEPTH:-4}" \
                            -type f -newermt "@${_dispatch_start}" \
                            -not -path '*/.git/*' -not -path '*/node_modules/*' \
                            2>/dev/null | head -20)
                if [[ -n "$_changed" ]]; then
                    local _n_changed _ts
                    _n_changed=$(printf '%s\n' "$_changed" | wc -l | tr -d ' ')
                    _ts=$(date -d "@${_dispatch_start}" '+%H:%M:%S' 2>/dev/null \
                          || date -r "${_dispatch_start}" '+%H:%M:%S' 2>/dev/null \
                          || echo "dispatch")
                    log WARN "Timeout with ${_n_changed} file(s) modified in $_dispatch_cwd since dispatch — provider may have written deliverables. Inspect before retrying."
                    echo "" >&2
                    echo "ℹ️  Partial writes detected (${_n_changed} files changed since ${_ts})" >&2
                    # WHY piped sed instead of `printf %s $(...)`: unquoted
                    # command substitution word-splits on whitespace in
                    # filenames. sed prepends indentation without splitting.
                    printf '%s\n' "$_changed" | head -5 | sed 's/^/   /' >&2
                    [[ $_n_changed -gt 5 ]] && echo "   ... (+$((_n_changed - 5)) more)" >&2
                fi
            fi
        fi
        rm -f "$temp_err"
        return $exit_code
    fi

    # v8.7.0: Wrap external CLI output with trust markers
    case "$agent_type" in codex*|gemini*|perplexity*)
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
