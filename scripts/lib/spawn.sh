#!/usr/bin/env bash
# spawn_agent — extracted from orchestrate.sh (v9.7.x)
# Agent spawning and lifecycle management

_octopus_spawn_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_octopus_spawn_lib_dir}/agent-spec.sh" 2>/dev/null || true
if ! type start_quota_watcher >/dev/null 2>&1; then
    source "${_octopus_spawn_lib_dir}/quota-watcher.sh" 2>/dev/null || true
fi
if ! type octopus_agent_teams_can_honor_timeout >/dev/null 2>&1; then
    source "${_octopus_spawn_lib_dir}/agent-sync.sh" 2>/dev/null || true
fi
if ! type run_contract_transition >/dev/null 2>&1; then
    source "${_octopus_spawn_lib_dir}/run-contract.sh" 2>/dev/null || true
fi

quota_watcher_kill_spawn_children() {
    local spawn_pid="$1"
    pkill -TERM -P "$spawn_pid" 2>/dev/null || true
    sleep 1
    pkill -KILL -P "$spawn_pid" 2>/dev/null || true
}

# Background execution contract helpers. Native Agent Teams dispatch and the
# supervised subprocess path share this lifecycle, so dispatch evidence can
# never be mistaken for a completed contribution.
octo_spawn_contract_seat_id() {
    local task_id="${1:-unknown}"
    task_id="$(printf '%s' "$task_id" | sed 's/[^A-Za-z0-9_.:-]/_/g')"
    printf 'spawn-%s\n' "$task_id"
}

octo_spawn_contract_plan() {
    local task_id="${1:-}" agent_type="${2:-unknown}" model="${3:-}"
    local effort="${4:-}" phase="${5:-unknown}" role="${6:-none}" seat_id
    local contract_provider contract_model
    local source_root source_sha="" source_dirty="not-a-git-worktree" worktree=""
    contract_provider="$(octo_agent_spec_contract_provider "$agent_type")" || return 74
    contract_model="$(octo_agent_spec_contract_model "$agent_type" "$model")" || return 74
    seat_id="$(octo_spawn_contract_seat_id "$task_id")"
    source_root="${OCTOPUS_PROJECT_DIR:-$PWD}"
    worktree="$(git -C "$source_root" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$worktree" ]]; then
        source_sha="$(git -C "$worktree" rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "$(git -C "$worktree" status --porcelain 2>/dev/null)" ]]; then
            if [[ "${OCTOPUS_ALLOW_DIRTY_SOURCE:-0}" == "1" ]]; then
                source_dirty="dirty-allowed"
            else
                source_dirty="dirty-blocked"
            fi
        else
            source_dirty="clean"
        fi
    fi

    run_contract_transition "$seat_id" planned \
        "requested_provider=$contract_provider" "requested_model=$contract_model" \
        "requested_effort=$effort" "phase=$phase" "role=$role" \
        "isolation=background" "attempt_id=${seat_id}-attempt-1" \
        "checkpoint=$phase" "source_sha=$source_sha" \
        "source_dirty=$source_dirty" "worktree=$worktree" || return 74
}

octo_spawn_contract_resolve() {
    local seat_id="${1:-}" agent_type="${2:-unknown}" model="${3:-unresolved}"
    local effort="${4:-}" estimated_cost="${5:-}" contract_provider
    contract_provider="$(octo_agent_spec_contract_provider "$agent_type")" || return 74
    run_contract_transition "$seat_id" starting \
        "resolved_provider=$contract_provider" "resolved_model=$model" \
        "resolved_effort=$effort" "estimated_cost_usd=$estimated_cost" || return 74
}

octo_spawn_contract_authenticated() {
    run_contract_transition "${1:-}" authenticated
}

octo_spawn_contract_running() {
    local seat_id="${1:-}" output_file="${2:-}" pid="${3:-}" model="${4:-}"
    local effort="${5:-}" pgid=""
    local -a transition_fields
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
    fi
    transition_fields=("output_file=$output_file" "pid=$pid" "pgid=$pgid")
    [[ -n "$model" ]] && transition_fields+=("resolved_model=$model")
    [[ -n "$effort" ]] && transition_fields+=("resolved_effort=$effort")
    run_contract_transition "$seat_id" running "${transition_fields[@]}"
}

octo_spawn_contract_begin() {
    local task_id="${1:-}" agent_type="${2:-unknown}" model="${3:-unresolved}"
    local effort="${4:-}" phase="${5:-unknown}" role="${6:-none}" seat_id
    seat_id="$(octo_spawn_contract_seat_id "$task_id")"
    octo_spawn_contract_plan "$task_id" "$agent_type" "$model" "$effort" "$phase" "$role" || return 74
    octo_spawn_contract_resolve "$seat_id" "$agent_type" "$model" "$effort" || return 74
    octo_spawn_contract_authenticated "$seat_id" || return 74
    octo_spawn_contract_running "$seat_id" || return 74
}

octo_spawn_contract_finish() {
    octo_run_contract_finish_background "$@"
}

# Capture the current Bash process ID without requiring BASHPID (Bash 4+).
# A directly executed child shell reports this shell as its PPID, including
# inside a background subshell where $$ remains pinned to the top-level Bash.
octo_capture_current_shell_pid() {
    OCTO_CAPTURED_SHELL_PID="${BASHPID:-}"
    [[ "$OCTO_CAPTURED_SHELL_PID" =~ ^[0-9]+$ ]] && return 0

    local pid_file
    pid_file="$(mktemp "${TMPDIR:-/tmp}/octo-current-pid.XXXXXX")" || return 1
    if ! /bin/sh -c 'printf "%s\n" "$PPID" > "$1"' _ "$pid_file" 2>/dev/null; then
        rm -f "$pid_file"
        return 1
    fi
    IFS= read -r OCTO_CAPTURED_SHELL_PID < "$pid_file" || true
    rm -f "$pid_file"
    [[ "$OCTO_CAPTURED_SHELL_PID" =~ ^[0-9]+$ ]]
}


# Emit agent lifecycle events to the Octopus JSONL event stream and, optionally,
# to an external observer hook. The event stream is the primary integration
# surface; OCTOPUS_AGENT_LIFECYCLE_HOOK is a best-effort bridge for local control
# planes that need an immediate callback without tailing OCTO_EVENT_LOG.
_octopus_agent_lifecycle_event() {
    local event="$1"
    local agent_type="$2"
    local task_id="$3"
    local role="${4:-}"
    local phase="${5:-}"
    local normalized_phase="${phase:-unknown}"
    local pid="${6:-}"
    local result_file="${7:-}"
    local exit_code="${8:-}"
    local status="${9:-}"

    local provider
    provider="$(octo_agent_spec_provider "$agent_type")"
    local event_name="agent.${event}"

    if declare -f octo_event_emit >/dev/null 2>&1; then
        octo_event_emit "$event_name" \
            provider="$provider" \
            provider_label_kind="legacy-alias" \
            executor_alias="$agent_type" \
            configured_provider="$(octo_provider_identity_from_agent_type "${agent_type:-${provider:-unknown}}")" \
            configured_model="$(get_agent_model "$agent_type" "$phase" "$role" 2>/dev/null || echo unresolved)" \
            runtime_provider="unknown" \
            runtime_model="unknown" \
            agent_type="$agent_type" \
            task_id="$task_id" \
            role="$role" \
            phase="$normalized_phase" \
            pid="$pid" \
            result_file="$result_file" \
            results_dir="${RESULTS_DIR:-}" \
            workspace_dir="${WORKSPACE_DIR:-}" \
            exit_code="$exit_code" \
            status="$status" \
            root_session_id="${CRABFLEET_ROOT_SESSION_ID:-${OCTOPUS_ROOT_SESSION_ID:-}}" \
            parent_session_id="${CRABFLEET_PARENT_SESSION_ID:-${OCTOPUS_PARENT_SESSION_ID:-}}" || true
    fi

    local hook="${OCTOPUS_AGENT_LIFECYCLE_HOOK:-}"
    [[ -n "$hook" && -x "$hook" ]] || return 0

    local hook_log="${OCTOPUS_AGENT_LIFECYCLE_HOOK_LOG:-/dev/null}"
    (
        export OCTOPUS_AGENT_HOOK_EVENT="$event"
        export OCTOPUS_AGENT_EVENT_NAME="$event_name"
        export OCTOPUS_AGENT_PROVIDER="$provider"
        export OCTOPUS_AGENT_TYPE="$agent_type"
        export OCTOPUS_AGENT_TASK_ID="$task_id"
        export OCTOPUS_AGENT_ROLE="$role"
        export OCTOPUS_AGENT_PHASE="$normalized_phase"
        export OCTOPUS_AGENT_PID="$pid"
        export OCTOPUS_AGENT_RESULT_FILE="$result_file"
        export OCTOPUS_AGENT_RESULTS_DIR="${RESULTS_DIR:-}"
        export OCTOPUS_AGENT_WORKSPACE_DIR="${WORKSPACE_DIR:-}"
        export OCTOPUS_AGENT_EXIT_CODE="$exit_code"
        export OCTOPUS_AGENT_STATUS="$status"
        export OCTOPUS_AGENT_ROOT_SESSION_ID="${CRABFLEET_ROOT_SESSION_ID:-${OCTOPUS_ROOT_SESSION_ID:-}}"
        export OCTOPUS_AGENT_PARENT_SESSION_ID="${CRABFLEET_PARENT_SESSION_ID:-${OCTOPUS_PARENT_SESSION_ID:-}}"
        local hook_timeout="${OCTOPUS_AGENT_LIFECYCLE_HOOK_TIMEOUT:-3}"
        if [[ ! "$hook_timeout" =~ ^[0-9]+$ ]]; then
            hook_timeout=3
        else
            hook_timeout=$((10#$hook_timeout))
            [[ "$hook_timeout" -lt 1 ]] && hook_timeout=3
        fi
        if declare -f run_with_timeout >/dev/null 2>&1; then
            run_with_timeout "$hook_timeout" "$hook" "$event"
        elif command -v timeout >/dev/null 2>&1; then
            timeout "$hook_timeout" "$hook" "$event"
        else
            # Built-in timeout fallback: run the hook and an independent sleep
            # watchdog in parallel, then kill the hook group if the watchdog
            # finishes first. This avoids wall-clock deadlines (`SECONDS` can
            # jump with the host clock) and uses only Bash builtins plus the
            # already-required sleep command. See issues #511 and #837.
            #
            # `set -m` puts the backgrounded hook in its own process group
            # (Bash's job-control assigns pgid = pid of the group leader),
            # so `kill -SIG -- -pid` on teardown signals the hook AND any
            # children it forks — no pkill dependency required. See #827.
            set -m
            "$hook" "$event" &
            local _hook_pid=$!
            set +m
            sleep "$hook_timeout" &
            local _hook_watchdog_pid=$!
            while kill -0 "$_hook_pid" 2>/dev/null && kill -0 "$_hook_watchdog_pid" 2>/dev/null; do
                sleep 1
            done
            if kill -0 "$_hook_pid" 2>/dev/null; then
                kill -TERM -- "-$_hook_pid" 2>/dev/null || true
                kill -TERM "$_hook_pid" 2>/dev/null || true
                sleep 1
                kill -KILL -- "-$_hook_pid" 2>/dev/null || true
                kill -KILL "$_hook_pid" 2>/dev/null || true
            fi
            wait "$_hook_pid" 2>/dev/null || true
            kill "$_hook_watchdog_pid" 2>/dev/null || true
            wait "$_hook_watchdog_pid" 2>/dev/null || true
        fi
    ) >>"$hook_log" 2>&1 || true
}

# Default task_id for spawns that don't supply one (#661). An earlier version
# of this used ${BASHPID:-$$}: BASHPID needs bash 4+ (docs/CONTRIBUTING.md's
# floor is 3.2, e.g. macOS's system /bin/bash), and on the $$ fallback path
# two spawn_agent/spawn_agent_capture_pid calls backgrounded with `&` from
# the same shell still collided — $$ stays pinned to the top-level shell's
# PID across every subshell forked from it (bash(1)), confirmed failing in
# CI on macOS. mktemp's file creation is atomic at the OS/filesystem level —
# genuinely collision-free, not just low-probability — and needs no bash
# version at all, so use its generated suffix instead. The reservation file
# is deliberately kept (not rm'd): deleting it would free that exact name
# for reuse by a later mktemp call, turning the "genuinely unique" guarantee
# back into a probabilistic one. Reservations older than seven days can be
# deleted safely because the timestamp component makes their full IDs distinct
# from every current-day allocation.
# Falls back to the old PID/RANDOM combination only if mktemp itself is
# unavailable — that path is not a hard uniqueness guarantee, only a
# best-effort default for environments where mktemp can't run at all.
# Shared by spawn_agent() and spawn_agent_capture_pid() so both default
# paths — and their tests — stay in sync from one definition.
_octopus_prune_task_id_reservations() {
    local reservation_dir="$1" prune_day marker lock_dir
    prune_day=$(date +%Y%m%d 2>/dev/null || printf 'unknown')
    marker="${reservation_dir}/.pruned-${prune_day}"
    [[ -e "$marker" ]] && return 0
    lock_dir="${marker}.lock"
    if mkdir "$lock_dir" 2>/dev/null; then
        find "$reservation_dir" -type f -mtime +7 -delete 2>/dev/null || true
        : > "$marker"
        rmdir "$lock_dir" 2>/dev/null || true
    fi
}

_octopus_next_spawn_task_id() {
    local _reservation_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/task-ids"
    mkdir -p "$_reservation_dir" 2>/dev/null || true
    _octopus_prune_task_id_reservations "$_reservation_dir"
    local _tmp _uniq
    _tmp=$(mktemp "${_reservation_dir}/XXXXXX" 2>/dev/null) && _uniq="${_tmp##*/}"
    printf '%s-%s\n' "$(date +%s)" "${_uniq:-${BASHPID:-$$}${RANDOM}}"
}

write_agent_result_header() {
    local result_file="$1"
    local agent_type="$2"
    local model="$3"
    local task_id="$4"
    local role="${5:-none}"
    local phase="${6:-none}"
    local dispatch="${7:-legacy}"

    {
        if [[ "$dispatch" == "agent-teams" ]]; then
            echo "# Agent: $agent_type (via Agent Teams)"
        else
            echo "# Agent: $agent_type"
        fi
        echo "# Executor alias: $agent_type"
        echo "# Configured provider: $(octo_provider_identity_from_agent_type "$agent_type")"
        echo "# Configured model: ${model:-unresolved}"
        echo "# Task ID: $task_id"
        echo "# Role: ${role:-none}"
        echo "# Phase: ${phase:-none}"
    } > "$result_file"
}

# Resolve the single wall-clock budget owned by spawn_agent. TIMEOUT=0 remains
# explicitly unlimited; phase floors only raise positive configured budgets.
octopus_effective_agent_timeout() {
    local configured_timeout="${1:-0}"
    local phase="${2:-}"
    local role="${3:-}"

    if [[ "$phase" == "tangle" && "$role" == "implementer" ]]; then
        local tangle_floor="${OCTOPUS_TANGLE_TIMEOUT:-1200}"
        if ! [[ "$tangle_floor" =~ ^[1-9][0-9]*$ ]]; then
            log "WARN" "OCTOPUS_TANGLE_TIMEOUT='$tangle_floor' is not a positive integer; using default 1200s floor"
            tangle_floor=1200
        fi
        if [[ "$configured_timeout" =~ ^[0-9]+$ ]] && \
           [[ "$configured_timeout" -gt 0 ]] && \
           [[ "$tangle_floor" -gt "$configured_timeout" ]]; then
            configured_timeout="$tangle_floor"
        fi
    fi

    printf '%s\n' "$configured_timeout"
}

# Print the positive number of seconds left before a fixed deadline. Returning
# nonzero at/after the deadline prevents callers from accidentally translating
# an expired budget to run_with_timeout's special unlimited value (0).
octopus_timeout_remaining() {
    local deadline="$1"
    local now="${2:-$(date +%s)}"

    [[ "$deadline" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] || return 1
    [[ "$deadline" -gt "$now" ]] || return 1
    printf '%s\n' "$((deadline - now))"
}

spawn_agent() {
    local agent_type="$1"
    if [[ "$agent_type" == "claude-opus-fast" ]]; then
        agent_type="claude-opus"
        log "WARN" "Legacy claude-opus-fast executor normalized to supported standard Claude dispatch"
    fi
    local prompt="$2"
    local task_id="${3:-$(_octopus_next_spawn_task_id)}"
    local agent_slug
    agent_slug="$(octo_agent_spec_slug "$agent_type")"
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

    if [[ "$DRY_RUN" == "true" ]]; then
        # Validate and render the real command without consuming stateful
        # routing decisions such as the run's one Fable escalation seat.
        local preview_cmd
        if ! preview_cmd=$(OCTOPUS_DISPATCH_PREVIEW=true \
            get_agent_command "$agent_type" "${phase:-}" "${role:-}" "${#prompt}"); then
            log ERROR "Unknown agent type: $agent_type"
            log INFO "Available agents: $AVAILABLE_AGENTS"
            return 1
        fi
        log INFO "[DRY-RUN] Would execute: $preview_cmd with role=${role:-none}"
        return 0
    fi

    local _contract_seat_id
    _contract_seat_id="$(octo_spawn_contract_seat_id "$task_id")"
    if ! octo_spawn_contract_plan "$task_id" "$agent_type" \
        "${OCTOPUS_REQUESTED_MODEL:-}" "${OCTOPUS_REQUESTED_EFFORT:-}" \
        "${phase:-unknown}" "${role:-none}"; then
        log ERROR "Unable to persist planned execution contract for background task $task_id"
        return 74
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

    # v8.10.0/v9.37.0: Enforce context budget AFTER all injections and after
    # the Codex subagent preamble. Previously the Codex preamble was appended in
    # the subprocess after budgeting, so Codex prompts could still exceed limits.
    if [[ "$agent_type" == codex* && "$agent_type" != "codex-review" ]]; then
        enhanced_prompt="${CODEX_SUBAGENT_PREAMBLE}${enhanced_prompt}"
    fi
    local tokens_in _budget_original_chars _budget_final_chars _budget_compression
    _budget_original_chars=${#enhanced_prompt}
    tokens_in=$(( _budget_original_chars / 4 ))
    enhanced_prompt=$(enforce_context_budget "$enhanced_prompt" "${role:-}" "$agent_type" "${phase:-}")
    local _budget_rc=$?
    if [[ $_budget_rc -ne 0 ]]; then
        octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
            "Prompt exceeded context budget" "$_budget_rc" "" >/dev/null 2>&1 || true
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" 0 "Prompt exceeded context budget" 0 "" "${role:-}" || true
        return "$_budget_rc"
    fi
    _budget_final_chars=${#enhanced_prompt}
    _budget_compression=none
    [[ "$_budget_final_chars" -lt "$_budget_original_chars" ]] && _budget_compression=applied

    if declare -f octo_routing_policy >/dev/null 2>&1 &&
       [[ "$(octo_routing_policy 2>/dev/null || printf '%s' off)" == "eval" ]] &&
       declare -f octo_route_task_class >/dev/null 2>&1; then
        local OCTOPUS_TASK_CLASS
        OCTOPUS_TASK_CLASS="$(octo_route_task_class "$enhanced_prompt" "${role:-}" "${phase:-}")"
        export OCTOPUS_TASK_CLASS
    fi

    # Auto-route claude-opus to fast mode when appropriate.
    # Current Opus fast is 2x standard ($10/$50 vs $5/$25 per MTok); legacy 4.6
    # fast remains 6x standard.
    # Only used for interactive single-shot tasks, never for multi-phase workflows
    if [[ "$agent_type" == "claude-opus" ]] && [[ "$SUPPORTS_FAST_OPUS" == "true" ]]; then
        local opus_tier
        opus_tier=$(get_agent_config "${curated_agent:-}" "tier" 2>/dev/null) || opus_tier="premium"
        local session_autonomy
        session_autonomy=$(jq -r '.autonomy // "supervised"' "${HOME}/.claude-octopus/session.json" 2>/dev/null) || session_autonomy="supervised"
        local opus_mode
        opus_mode=$(select_opus_mode "$phase" "$opus_tier" "$session_autonomy")
        if [[ "$opus_mode" == "fast" ]]; then
            log "INFO" "Opus Fast was selected for this context; using supported standard subprocess dispatch"
            log_opus_fast_pricing_warning "$phase" "${role:-}"
        fi
    fi

    # v9.13: Circuit breaker check — skip provider if circuit is open
    local provider_prefix
    provider_prefix="$(octo_agent_spec_provider "$agent_type")"  # codex-standard → codex; provider:model → provider
    if type is_provider_available &>/dev/null && ! is_provider_available "$provider_prefix"; then
        log "WARN" "Circuit open for $provider_prefix — skipping $agent_type (use fallback)"
        record_outcome "$provider_prefix" "$agent_type" "skipped" "${phase:-unknown}" "circuit_open" "0" 2>/dev/null || true
        octo_spawn_contract_finish "$_contract_seat_id" skipped "" "" \
            "Provider circuit is open" 1 "" >/dev/null 2>&1 || true
        return 1
    fi

    # oco-aek: provider selected for dispatch (circuit closed). Opt-in event.
    declare -f octo_event_emit >/dev/null 2>&1 && octo_event_emit "provider.selected" provider="$provider_prefix" provider_label_kind="legacy-alias" executor_alias="$agent_type" configured_provider="$(octo_provider_identity_from_agent_type "${agent_type:-unknown}")" configured_model="$(get_agent_model "$agent_type" "${phase:-}" "${role:-}" 2>/dev/null || echo unresolved)" runtime_provider="unknown" runtime_model="unknown" agent_type="$agent_type" role="${role:-none}" phase="${phase:-unknown}" || true

    local model
    if ! model=$(get_agent_model "$agent_type" "${phase:-}" "${role:-}"); then
        octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
            "Model resolution failed" 1 "" >/dev/null 2>&1 || true
        return 1
    fi

    # Resolve one effective wall-clock budget before selecting a persistence
    # path. The degraded synchronous fallback must enforce the same phase floor
    # as the normal subprocess, while TIMEOUT=0 remains unlimited.
    local _eff_timeout
    _eff_timeout=$(octopus_effective_agent_timeout "${TIMEOUT:-0}" "$phase" "$role")

    local log_file="${LOGS_DIR}/${agent_slug}-${task_id}.log"
    local result_file="${RESULTS_DIR}/${agent_slug}-${task_id}.md"

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
    log DEBUG "Phase: ${phase:-none}, Role: ${role:-none}"

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

    local _estimated_cost="0.000000"
    if type estimate_agent_call_cost >/dev/null 2>&1; then
        _estimated_cost=$(estimate_agent_call_cost "$agent_type" "$model" "$enhanced_prompt")
    fi
    if ! octo_spawn_contract_resolve "$_contract_seat_id" "$agent_type" "$model" \
        "${effort_level:-${OCTOPUS_RESOLVED_EFFORT:-${OCTOPUS_REQUESTED_EFFORT:-}}}" \
        "$_estimated_cost"; then
        log ERROR "Unable to persist resolved execution contract for background task $task_id"
        return 74
    fi

    local _provider_for_health=""
    case "$agent_type" in
        codex*) _provider_for_health="codex" ;;
        gemini*|agy*|antigravity) _provider_for_health="agy" ;;
        claude-sdk*) _provider_for_health="claude-sdk" ;;
        claude*) _provider_for_health="claude" ;;
        openrouter*) _provider_for_health="openrouter" ;;
        perplexity*) _provider_for_health="perplexity" ;;
        cursor-agent*) _provider_for_health="cursor-agent" ;;
    esac
    if [[ -n "$_provider_for_health" ]] && declare -F check_provider_health >/dev/null 2>&1; then
        local _health_diag
        if ! _health_diag=$(check_provider_health "$_provider_for_health" 2>&1); then
            octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
                "Provider unavailable: $_health_diag" 1 "" >/dev/null 2>&1 || true
            log WARN "Provider '$_provider_for_health' health check failed: $_health_diag"
            return 1
        fi
    fi

    if ! octo_spawn_contract_authenticated "$_contract_seat_id"; then
        log ERROR "Unable to persist authenticated execution contract for background task $task_id"
        return 74
    fi
    if [[ "${OCTOPUS_PERSISTENCE_AVAILABLE:-true}" == "false" ]]; then
        octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
            "Persistence unavailable" 74 "" >/dev/null 2>&1 || true
        log ERROR "Persistence unavailable; refusing untracked background dispatch for $agent_type"
        return 74
    fi

    # Command construction occurs only after health and persistence pass because
    # an eligible Fable command atomically claims the run's premium seat.
    local cmd _prompt_bytes
    if ! _prompt_bytes=$(octo_prompt_byte_length "$enhanced_prompt"); then
        octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
            "Prompt byte measurement failed" 1 "" >/dev/null 2>&1 || true
        return 1
    fi
    if ! cmd=$(get_agent_command "$agent_type" "${phase:-}" "${role:-}" "$_prompt_bytes"); then
        log ERROR "Unknown agent type: $agent_type"
        log INFO "Available agents: $AVAILABLE_AGENTS"
        octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
            "Provider command unavailable" 1 "" >/dev/null 2>&1 || true
        return 1
    fi
    if declare -f octo_dispatch_command_model >/dev/null 2>&1; then
        model="$(octo_dispatch_command_model "$cmd" "$model")"
    fi
    if ! validate_agent_command "$cmd"; then
        log ERROR "Invalid agent command returned: $cmd"
        octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
            "Provider command failed validation" 1 "" >/dev/null 2>&1 || true
        return 1
    fi
    if [[ "$agent_type" == cursor-agent* ]] && ! cursor_agent_is_available; then
        log ERROR "Cursor Agent is not available or authenticated"
        octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
            "Cursor Agent is unavailable or unauthenticated" 1 "" >/dev/null 2>&1 || true
        return 1
    fi
    log DEBUG "Command: $cmd"
    log "DEBUG" "Model selected: $model (from agent_type=$agent_type, phase=${phase:-none})"
    record_agent_call "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}" "${role:-none}" "0"

    # v8.14.0: Track provider usage in persistent state. provider_prefix is the
    # canonical provider identity used by circuit-breaker/history/accounting; do
    # not split metrics by model-qualified agent_spec.
    local provider_name="$provider_prefix"
    update_metrics "provider" "$provider_name" 2>/dev/null || true

    # v8.7.0: Register task in bridge ledger (non-fatal if ledger missing)
    bridge_register_task "$task_id" "$agent_type" "${phase:-unknown}" "${role:-none}" || true

    # Record metrics start (v7.25.0)
    local metrics_id=""
    if command -v record_agent_start &> /dev/null; then
        metrics_id=$(record_agent_start "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}") || true
    fi

    # Store metrics mapping for batch completion recording (after DRY_RUN gate)
    if [[ -n "$metrics_id" ]]; then
        local metrics_base="${WORKSPACE_DIR:-${HOME}/.claude-octopus}"
        local metrics_map="${metrics_base}/.metrics-map"
        echo "${task_group:-${task_id}}:${metrics_id}:${agent_type}:${model}" >> "$metrics_map"
    fi

    if ! mkdir -p "$RESULTS_DIR" "$LOGS_DIR" || ! touch "$PID_FILE"; then
        octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
            "Background state directory is not writable" 74 "" >/dev/null 2>&1 || true
        return 74
    fi

    # v8.5: Agent Teams dispatch for Claude agents. Native teammates have no
    # plugin-accessible cancellation handle, so positive bounded work must stay
    # on the supervised subprocess path where the timeout is enforceable.
    local _use_agent_teams=false
    if should_use_agent_teams "$agent_type"; then
        if octopus_agent_teams_can_honor_timeout "$_eff_timeout"; then
            _use_agent_teams=true
        else
            log "INFO" "Bounded dispatch (${_eff_timeout}s) uses the supervised provider subprocess; native Agent Teams cannot enforce a wall-clock timeout"
        fi
    fi
    if [[ "$_use_agent_teams" == "true" ]]; then
        log "INFO" "Dispatching via Agent Teams: $agent_type (task: $task_id)"

        # Write structured agent instruction for Claude Code's native team dispatch
        # The agent instruction file is picked up by teammate-idle-dispatch.sh
        local teams_dir="${WORKSPACE_DIR}/agent-teams"
        if ! mkdir -p "$teams_dir"; then
            octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
                "Agent Teams state directory is not writable" 74 "" >/dev/null 2>&1 || true
            return 74
        fi

        local agent_instruction_file="${teams_dir}/${task_id}.json"
        if ! command -v jq &>/dev/null || ! jq -n \
                --arg agent_type "$agent_type" \
                --arg task_id "$task_id" \
                --arg run_id "$(octo_run_contract_id)" \
                --arg seat_id "$_contract_seat_id" \
                --arg role "${role:-none}" \
                --arg phase "${phase:-none}" \
                --arg model "$model" \
                --arg prompt "$enhanced_prompt" \
                --arg result_file "$result_file" \
                --arg effort "${effort_level:-medium}" \
                --arg model_override "$SUPPORTS_AGENT_MODEL_OVERRIDE" \
                --argjson timeout_seconds "$_eff_timeout" \
                '{agent_type: $agent_type, task_id: $task_id,
                  run_id: $run_id, seat_id: $seat_id, role: $role,
                  phase: $phase, model: $model, prompt: $prompt,
                  result_file: $result_file, dispatch_method: "agent_teams",
                  effort: $effort,
                  timeout_seconds: $timeout_seconds,
                  model_override_supported: ($model_override == "true"),
                  agent_id: "", dispatched_at: now | todate}' \
                > "$agent_instruction_file" 2>/dev/null; then
            octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
                "Failed to persist Agent Teams dispatch instruction" 74 "" >/dev/null 2>&1 || true
            log ERROR "Failed to persist Agent Teams instruction: $agent_instruction_file"
            return 74
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
        if ! write_agent_result_header "$result_file" "$agent_type" "${model:-unresolved}" "$task_id" "${role:-none}" "${phase:-none}" "agent-teams"; then
            octo_spawn_contract_finish "$_contract_seat_id" failed "" "" \
                "Failed to persist Agent Teams result header" 74 "" >/dev/null 2>&1 || true
            return 74
        fi
        printf '# Prompt metadata: original_chars=%s final_chars=%s compression=%s\n' \
            "$_budget_original_chars" "$_budget_final_chars" "$_budget_compression" >> "$result_file"
        printf '# Prompt: %s\n' "$enhanced_prompt" >> "$result_file"
        echo "# Started: $(date)" >> "$result_file"
        echo "# Dispatch: Agent Teams (native)" >> "$result_file"
        if [[ "$SUPPORTS_HOOK_LAST_MESSAGE" == "true" ]]; then
            echo "# Result-capture: SubagentStop hook" >> "$result_file"
        fi
        echo "" >> "$result_file"
        if ! octo_spawn_contract_running "$_contract_seat_id" "$result_file" "" \
            "$model" "${effort_level:-}"; then
            log ERROR "Unable to persist running execution contract for Agent Teams task $task_id"
            return 74
        fi
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "running" "$tokens_in" 0 "Dispatched via Agent Teams" "$_eff_timeout" "$result_file" "${role:-none}" "$_contract_seat_id" running none || true
        update_agent_status "$agent_type" "running" 0 "$_estimated_cost" "$_eff_timeout" "$task_id" "${phase:-unknown}" "$result_file"

        log "DEBUG" "Agent Teams instruction written to: $agent_instruction_file"
        if [[ "$SUPPORTS_HOOK_LAST_MESSAGE" == "true" ]]; then
            log "DEBUG" "Result capture via SubagentStop hook (last_assistant_message)"
        fi
        _octopus_agent_lifecycle_event "spawned" "$agent_type" "$task_id" "$role" "$phase" "" "$result_file" "" "running"
        return 0
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # LEGACY PATH: Execute an external agent in a Bash subprocess when teams are unavailable.
    # ═══════════════════════════════════════════════════════════════════════════

    # Execute each worker in a dedicated process group. The recorded PID is also
    # its PGID, allowing cancellation to atomically stop every provider
    # descendant even if the Bash group leader exits during teardown (#900).
    # Preserve a caller that already enabled monitor mode rather than forcing it
    # off after the spawn.
    local _spawn_monitor_was_enabled=false
    [[ "$-" == *m* ]] && _spawn_monitor_was_enabled=true
    set -m
    (
        cd "$PROJECT_ROOT" || exit 1
        set -f  # Disable glob expansion
        set -o pipefail  # v9.15.1: Pipeline exit code = first failure
        octo_capture_current_shell_pid || OCTO_CAPTURED_SHELL_PID="$$"

        write_agent_result_header "$result_file" "$agent_type" "${model:-unresolved}" "$task_id" "${role:-none}" "${phase:-none}" "legacy"
        printf '# Prompt metadata: original_chars=%s final_chars=%s compression=%s\n' \
            "$_budget_original_chars" "$_budget_final_chars" "$_budget_compression" >> "$result_file"
        printf '# Prompt: %s\n' "$enhanced_prompt" >> "$result_file"
        echo "# Started: $(date)" >> "$result_file"
        echo "" >> "$result_file"
        echo "## Output" >> "$result_file"
        echo '```' >> "$result_file"

        # SECURITY: Use array-based execution to prevent word-splitting vulnerabilities
        # v8.32.0: Per-provider credential isolation — each agent only sees its own API key
        local -a cmd_array
        local -a inner_cmd_array
        build_provider_env "$agent_type"
        read -ra inner_cmd_array <<< "$cmd"
        if [[ ${#PROVIDER_ENV_ARRAY[@]} -gt 0 ]]; then
            cmd_array=("${PROVIDER_ENV_ARRAY[@]}" "${inner_cmd_array[@]}")
            log "DEBUG" "Credential isolation active for $agent_type"
        else
            cmd_array=("${inner_cmd_array[@]}")
        fi

        # IMPROVED: Use temp files for reliable output capture (v7.13.2 - Issue #10)
        # v7.19.0 P0.1: Real-time output streaming to result file
        local temp_output="${RESULTS_DIR}/.tmp-${task_id}.out"
        local temp_errors="${RESULTS_DIR}/.tmp-${task_id}.err"
        local temp_input="${RESULTS_DIR}/.tmp-${task_id}.in"
        local raw_output="${RESULTS_DIR}/.raw-${task_id}.out"  # Backup of unfiltered output

        # Update task progress with context-aware spinner verb (v7.16.0 Feature 1)
        if [[ -n "$CLAUDE_TASK_ID" ]]; then
            local active_verb
            active_verb=$(get_active_form_verb "$phase" "$agent_type" "$prompt")
            update_task_progress "$CLAUDE_TASK_ID" "$active_verb"
        fi

        # Mark agent as running and capture start time (v7.16.0 Feature 2)
        local start_time_secs start_time_ms _timeout_deadline=0
        # Use seconds instead of milliseconds for compatibility (macOS date doesn't support %N)
        start_time_secs=$(date +%s)
        start_time_ms=$((start_time_secs * 1000))
        if [[ "$_eff_timeout" =~ ^[0-9]+$ ]] && [[ "$_eff_timeout" -gt 0 ]]; then
            _timeout_deadline=$((start_time_secs + _eff_timeout))
        fi
        update_agent_status "$agent_type" "running" 0 "$_estimated_cost" "$_eff_timeout" "$task_id" "${phase:-unknown}" "$result_file"
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "running" "$tokens_in" 0 "" 0 "$result_file" "${role:-none}" || true

        # v7.19.0 P0.1: Use tee to stream output to both temp file and raw backup
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
        if [[ "$agent_type" == cursor-agent* ]] || [[ "$agent_type" == copilot* ]] || [[ "$agent_type" == qwen* ]]; then
            cmd_array+=(-p "")
        fi

        local auth_attempt=0
        local exit_code=0
        if ! octo_spawn_contract_running "$_contract_seat_id" "$result_file" \
            "$OCTO_CAPTURED_SHELL_PID" "$model" "${effort_level:-}"; then
            log ERROR "Unable to persist provider launch for background task $task_id"
            exit 74
        fi
        while true; do
            exit_code=0
            local _attempt_timeout="$_eff_timeout"
            if [[ "$_timeout_deadline" -gt 0 ]] && \
               ! _attempt_timeout=$(octopus_timeout_remaining "$_timeout_deadline"); then
                exit_code=124
                break
            fi

            # oco-48z: quota/terminal-error fast-fail watcher for ALL providers (was
            # provider-specific). Greps temp files every 2s; on match it kills the provider
            # early and marks it quota-dead for the session (oco-cbb), so preflight and
            # is_agent_available skip it instead of re-dispatching into the same failure.
            local _quota_watcher_pid=""
            local _spawn_pid="$OCTO_CAPTURED_SHELL_PID"
            local _provider_prefix
            _provider_prefix="$(octo_agent_spec_provider "$agent_type")"
            _provider_prefix="$(octo_provider_canonical "$_provider_prefix" 2>/dev/null || printf '%s' "$_provider_prefix")"
            _quota_watcher_pid=$(start_quota_watcher \
                "$_spawn_pid" \
                "$temp_errors" \
                "$raw_output" \
                quota_watcher_kill_spawn_children \
                "[$agent_type] Quota/terminal error detected - fast-failing (saves ~${_eff_timeout}s wait)" \
                "$_provider_prefix")

            # v9.2.2: All agents use stdin-based prompt delivery to avoid ARG_MAX
            # limits. File-backed capture avoids waiting for EOF from a provider
            # descendant that inherited stdout (#892).
            if octopus_capture_provider_output \
                "$enhanced_prompt" "$_attempt_timeout" "$temp_input" \
                "$raw_output" "$temp_errors" "${cmd_array[@]}"; then
                exit_code=0
            else
                exit_code=$?
            fi
            cp "$raw_output" "$temp_output" 2>/dev/null || : > "$temp_output"

            stop_quota_watcher "$_quota_watcher_pid"

            # v8.16: Check if failure is auth-related and retryable
            if [[ $exit_code -ne 0 ]] && [[ $exit_code -ne 124 ]] && [[ $exit_code -ne 143 ]] && \
               [[ $auth_attempt -lt $max_auth_retries ]]; then
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
                    if [[ "$_timeout_deadline" -gt 0 ]]; then
                        local _retry_remaining
                        if ! _retry_remaining=$(octopus_timeout_remaining "$_timeout_deadline") || \
                           [[ "$_retry_remaining" -le "$backoff" ]]; then
                            log "WARN" "Auth retry skipped: agent wall-clock budget exhausted"
                            exit_code=124
                            break
                        fi
                    fi
                    log "WARN" "Auth failure detected (attempt $auth_attempt/$max_auth_retries), retrying in ${backoff}s..."
                    sleep "$backoff"
                    # Clear temp files for retry
                    : > "$temp_output"
                    : > "$temp_errors"
                    : > "$raw_output"
                    continue
                fi
            fi
            break
        done

        if [[ $exit_code -ne 0 && -s "$temp_errors" ]]; then
            local stderr_excerpt=""
            stderr_excerpt=$(grep -m5 '[^[:space:]]' "$temp_errors" 2>/dev/null | tr '\n' ' ' | head -c 600 || true)
            if [[ -n "$stderr_excerpt" ]]; then
                log "ERROR" "[$agent_type] provider stderr: $stderr_excerpt"
            fi
        fi

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

        local _octo_success_status="ok"
        local _octo_success_reason=""
        local _octo_tokens_out=0

        # v7.19.0 P0.1: Process output regardless of exit code (preserves partial results)
        if [[ "$_hook_captured" == "true" ]]; then
            # Hook already wrote ## Output + ## Status: SUCCESS — skip to post-processing
            _octo_tokens_out=$(octo_estimate_tokens_for_file "$result_file" 2>/dev/null || echo 0)
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
                # Filter known external-CLI status noise from stdout.
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
            if [[ "$agent_type" == codex* ]] \
                && ! grep -q '[[:alnum:]]' "$temp_output" 2>/dev/null \
                && type octo_file_has_codex_recoverable_stderr >/dev/null 2>&1 \
                && octo_file_has_codex_recoverable_stderr "$temp_errors"; then
                echo "(Codex response was emitted on stderr; see Warnings/Errors transcript below.)" >> "$result_file"
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
            local _classification
            _classification=$(classify_agent_output "$temp_output" "$exit_code" "$agent_type" "$temp_errors" 2>/dev/null || echo "ok:")
            _octo_success_status="${_classification%%:*}"
            _octo_success_reason="${_classification#*:}"
            _octo_tokens_out=$(octo_estimate_tokens_for_file "$temp_output" 2>/dev/null || echo 0)

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

            octo_append_runtime_identity "$result_file" "$agent_type" "${model:-unresolved}" "$raw_output"

            local end_time_ms elapsed_ms
            end_time_ms=$(( $(date +%s) * 1000 ))
            elapsed_ms=$((end_time_ms - start_time_ms))

            if [[ "$_octo_success_status" != "failed" ]]; then
                local _contract_outcome="success"
                [[ "$_octo_success_status" == "degraded" ]] && _contract_outcome="degraded"
                if ! octo_spawn_contract_finish "$_contract_seat_id" "$_contract_outcome" \
                    "$result_file" "$temp_errors" "$_octo_success_reason" "$exit_code" "$elapsed_ms" "" "$temp_output"; then
                    _octo_success_status="failed"
                    _octo_success_reason="Execution contract persistence failed"
                    exit_code=74
                fi
            fi

            case "$_octo_success_status" in
                failed)
                    echo "## Status: FAILED (${_octo_success_reason:-unusable output})" >> "$result_file"
                    ;;
                degraded)
                    echo "## Status: SUCCESS (DEGRADED: ${_octo_success_reason:-partial output})" >> "$result_file"
                    ;;
                *)
                    echo "## Status: SUCCESS" >> "$result_file"
                    ;;
            esac

            # Mark agent as completed (v7.16.0 Feature 2)
            if [[ "$_octo_success_status" == "failed" ]]; then
                update_agent_status "$agent_type" "failed" "$elapsed_ms" "$_estimated_cost" "$_eff_timeout" "$task_id" "${phase:-unknown}" "$result_file"
                record_outcome "$agent_type" "$agent_type" "${task_type:-unknown}" "${phase:-unknown}" "fail" "$elapsed_ms" 2>/dev/null || true
                type record_failure &>/dev/null && record_failure "$provider_prefix" "provider_rejection" 2>/dev/null || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" "$_octo_tokens_out" "${_octo_success_reason:-unusable output}" "$elapsed_ms" "$result_file" "${role:-none}" || true
                octo_spawn_contract_finish "$_contract_seat_id" failed "$result_file" "$temp_errors" \
                    "${_octo_success_reason:-Provider returned unusable output}" "$exit_code" "$elapsed_ms" >/dev/null 2>&1 || true
            else
                update_agent_status "$agent_type" "$_octo_success_status" "$elapsed_ms" "$_estimated_cost" "$_eff_timeout" "$task_id" "${phase:-unknown}" "$result_file"
                # v8.18.0: Record provider learning
                local result_summary
                result_summary=$(head -c 200 "$result_file" 2>/dev/null | tr '\n' ' ')
                append_provider_history "$provider_prefix" "${phase:-unknown}" "${enhanced_prompt:0:100}" "$result_summary" 2>/dev/null || true
                # v8.20.0: Record outcome for provider intelligence
                record_outcome "$agent_type" "$agent_type" "${task_type:-unknown}" "${phase:-unknown}" "success" "$elapsed_ms" 2>/dev/null || true
                # v9.13: Reset circuit breaker on success
                type record_success &>/dev/null && record_success "$provider_prefix" 2>/dev/null || true
                # v9.3.0: Record file co-occurrence pattern for heuristic learning
                record_run_pattern "$agent_type" "${enhanced_prompt:-$prompt}" "$result_file" 2>/dev/null || true
                # v8.20.1: Record task duration metric
                record_task_metric "task_duration_ms" "$elapsed_ms" 2>/dev/null || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "$_octo_success_status" "$tokens_in" "$_octo_tokens_out" "$_octo_success_reason" "$elapsed_ms" "$result_file" "${role:-none}" || true
                # v8.21.0: Anti-drift checkpoint (non-blocking)
                if type run_drift_check &>/dev/null 2>&1; then
                    run_drift_check "${enhanced_prompt:-$prompt}" "$(cat "$result_file" 2>/dev/null)" "$agent_type" "${phase:-unknown}" 2>/dev/null || true
                fi
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
            echo "⚠️  **Warning**: Agent timed out after ${_eff_timeout}s but partial output preserved above." >> "$result_file"
            echo "" >> "$result_file"
            echo "**Recommendations**:" >> "$result_file"
            echo "- Partial results may still be valuable" >> "$result_file"
            if [[ "$_eff_timeout" =~ ^[0-9]+$ && "$_eff_timeout" -gt 0 ]]; then
                echo "- Consider increasing timeout: \`--timeout $((_eff_timeout * 2))\`" >> "$result_file"
            else
                echo "- Consider setting an explicit timeout only if this task needs a wall-clock cap" >> "$result_file"
            fi
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
            update_agent_status "$agent_type" "timeout" "$elapsed_ms" "$_estimated_cost" "$_eff_timeout" "$task_id" "${phase:-unknown}" "$result_file"
            # #869: tokens_out must be estimated from whichever file actually holds
            # more of the salvaged content — otherwise a timeout whose real output
            # only reached raw_output (or whose result_file gets a later raw_output
            # append below, when it's under 1KB) gets reported as tokens_out=0 or an
            # undercount next to a result_file full of preserved output, making
            # completed work look discarded.
            local _tokens_out_source="$temp_output"
            local _tos_size=0 _ros_size=0
            [[ -s "$temp_output" ]] && _tos_size=$(wc -c < "$temp_output" 2>/dev/null || echo 0)
            [[ -s "$raw_output" ]] && _ros_size=$(wc -c < "$raw_output" 2>/dev/null || echo 0)
            [[ "$_ros_size" -gt "$_tos_size" ]] && _tokens_out_source="$raw_output"
            local tokens_out
            tokens_out=$(octo_estimate_tokens_for_file "$_tokens_out_source" 2>/dev/null || echo 0)
            type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "timeout" "$tokens_in" "$tokens_out" "Timed out before completion" "$elapsed_ms" "$result_file" "${role:-none}" || true
            if ! octo_spawn_contract_finish "$_contract_seat_id" timeout "$result_file" "$temp_errors" \
                "Timed out before completion" "$exit_code" "$elapsed_ms" >/dev/null 2>&1; then
                exit_code=74
                update_agent_status "$agent_type" "failed" "$elapsed_ms" "$_estimated_cost" "$_eff_timeout" "$task_id" "${phase:-unknown}" "$result_file"
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" "$tokens_out" "Execution contract persistence failed" "$elapsed_ms" "$result_file" "${role:-none}" || true
                echo "## Contract Status: FAILED (persistence error)" >> "$result_file"
            fi
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
                echo "(no output captured — ${agent_type} produced no stdout; check provider auth/config with 'orchestrate.sh doctor')" >> "$result_file"
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
            update_agent_status "$agent_type" "failed" "$elapsed_ms" "$_estimated_cost" "$_eff_timeout" "$task_id" "${phase:-unknown}" "$result_file"
            local tokens_out
            tokens_out=$(octo_estimate_tokens_for_file "$temp_output" 2>/dev/null || echo 0)
            type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" "$tokens_out" "Exit code $exit_code" "$elapsed_ms" "$result_file" "${role:-none}" || true
            if ! octo_spawn_contract_finish "$_contract_seat_id" failed "$result_file" "$temp_errors" \
                "Exit code $exit_code" "$exit_code" "$elapsed_ms" >/dev/null 2>&1; then
                exit_code=74
                echo "## Contract Status: FAILED (persistence error)" >> "$result_file"
            fi
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
        rm -f "$temp_input" "$temp_output" "$temp_errors"
        if [[ $result_size -ge 1024 ]]; then
            rm -f "$raw_output"  # Clean up if result looks good
        fi

        echo "# Completed: $(date)" >> "$result_file"

        # v8.7.0: Record result hash for integrity verification
        record_result_hash "$result_file"

        # Ensure file is fully written before background process exits
        sync

        # Write completion marker — used by tangle_develop to detect thread end
        # without relying on kill -0 (which tracks wrapper PID, not provider PID)
        local _spawn_exit="${exit_code:-0}"
        local _done_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.octo/agents"
        local _done_tmp="${_done_dir}/${task_id}.done.tmp.$$"
        local _done_file="${_done_dir}/${task_id}.done"
        if ! mkdir -p "$_done_dir" 2>/dev/null \
           || ! { echo "$_spawn_exit" > "$_done_tmp" && mv -f "$_done_tmp" "$_done_file"; } 2>/dev/null; then
            log WARN "Failed to write completion marker for $task_id (exit=$_spawn_exit)"
            rm -f "$_done_tmp" 2>/dev/null || true
        fi

        local _hook_final_status="failed"
        if [[ "${_spawn_exit:-0}" -eq 0 ]]; then
            if [[ "${_octo_success_status:-ok}" == "failed" ]]; then
                _hook_final_status="failed"
            else
                _hook_final_status="completed"
            fi
        elif [[ "${_spawn_exit:-0}" -eq 124 || "${_spawn_exit:-0}" -eq 143 ]]; then
            _hook_final_status="timeout"
        fi
        _octopus_agent_lifecycle_event "completed" "$agent_type" "$task_id" "$role" "$phase" "$OCTO_CAPTURED_SHELL_PID" "$result_file" "$_spawn_exit" "$_hook_final_status"

        # v8.19.0: Cleanup heartbeat (self-terminating monitor handles this too)
        cleanup_heartbeat "$OCTO_CAPTURED_SHELL_PID" 2>/dev/null || true
    ) &

    local pid=$!
    [[ "$_spawn_monitor_was_enabled" == "true" ]] || set +m

    _octopus_agent_lifecycle_event "spawned" "$agent_type" "$task_id" "$role" "$phase" "$pid" "$result_file" "" "running"

    # v8.19.0: Start heartbeat monitor for agent process
    start_heartbeat_monitor "$pid" "$task_id"

    # Atomic PID file write with file locking to prevent race conditions
    # Use flock on Linux, skip locking on macOS (flock not available)
    if command -v flock &>/dev/null; then
        (
            flock -x 200
            echo "$pid:$agent_slug:$task_id" >> "$PID_FILE"
        ) 200>"${PID_FILE}.lock"
    else
        # macOS fallback: simple append (race condition risk is low for our use case)
        echo "$pid:$agent_slug:$task_id" >> "$PID_FILE"
    fi

    log INFO "Agent spawned with PID: $pid"
    echo "$pid"
}

# #947: spawn_agent (below) can legitimately block for a while before it ever
# prints a provider PID, because it runs enforce_context_budget ->
# summarize_then_dispatch synchronously on an oversized prompt: up to 5
# summarizer candidates (lib/dispatch.sh's optional OCTOPUS_OVERSIZE_SUMMARIZER
# plus its 4-candidate fallback chain), each bounded by compute_dynamic_timeout
# — which OCTOPUS_AGENT_TIMEOUT overrides directly (lib/heartbeat.sh). A fixed
# 120s wait window (the old 1200-attempt default) could be shorter than a
# single candidate's own budget, let alone the full chain, so a wrapper that
# was still legitimately working had its seat discarded by
# spawn_agent_capture_pid below. Derive the default window from the same
# per-candidate budget the summarizer chain actually uses, times the
# worst-case candidate count, so raising OCTOPUS_AGENT_TIMEOUT to help a slow
# provider can no longer cause its own spawn to be abandoned instead. Falls
# back to a fixed value if heartbeat.sh (an optional dep of this file) isn't
# sourced, e.g. a test harness loading only this function. Split out from
# spawn_agent_capture_pid so the pure derivation is unit-testable without
# driving the real polling loop.
_octopus_spawn_pid_wait_default_attempts() {
    local preflight_candidates=5
    local preflight_secs=360
    if declare -F compute_dynamic_timeout >/dev/null 2>&1; then
        preflight_secs=$(compute_dynamic_timeout complex 2>/dev/null) || preflight_secs=360
    fi
    [[ "$preflight_secs" =~ ^[0-9]+$ ]] || preflight_secs=360
    # compute_dynamic_timeout echoes OCTOPUS_AGENT_TIMEOUT verbatim when it's
    # set as an override, so a value like "0900" reaches here unmodified;
    # 10# forces base-10 so bash arithmetic doesn't misread a leading zero
    # as an octal prefix (which either errors out or silently truncates).
    local attempts=$(( (10#$preflight_secs * preflight_candidates + 60) * 10 ))
    (( attempts < 1200 )) && attempts=1200
    echo "$attempts"
}

# Launch spawn_agent in the background and return the inner provider PID that
# spawn_agent prints, not the short-lived wrapper PID from `$!`.
spawn_agent_capture_pid() {
    local agent_type="$1"
    local prompt="$2"
    local task_id="${3:-$(_octopus_next_spawn_task_id)}"
    local role="${4:-}"
    local phase="${5:-}"
    local use_fork="${6:-false}"
    local notice_file="${OCTOPUS_NOTICE_FILE:-}" owns_notice_file=false

    if type octo_notice_channel_is_valid >/dev/null 2>&1 &&
       ! octo_notice_channel_is_valid "$notice_file" &&
       type octo_notice_channel_create >/dev/null 2>&1; then
        notice_file="$(octo_notice_channel_create 2>/dev/null || true)"
        [[ -n "$notice_file" ]] && owns_notice_file=true
    fi

    local pid_file
    if ! pid_file=$(mktemp "${TMPDIR:-/tmp}/octo-spawn-pid.XXXXXX"); then
        [[ "$owns_notice_file" == true ]] && rm -f "$notice_file" 2>/dev/null || true
        return 1
    fi
    if [[ "${OCTOPUS_SPAWN_PID_HANDOFF_FD:-}" == "9" ]]; then
        printf 'capture-file:%s\n' "$pid_file" >&9
    fi

    OCTOPUS_NOTICE_FILE="$notice_file" \
        OCTOPUS_NOTICE_FD=8 \
        spawn_agent "$agent_type" "$prompt" "$task_id" "$role" "$phase" "$use_fork" \
        8>&2 >"$pid_file" 2>&1 &
    local wrapper_pid=$!
    if [[ "${OCTOPUS_SPAWN_PID_HANDOFF_FD:-}" == "9" ]]; then
        printf 'wrapper:%s\n' "$wrapper_pid" >&9
    fi

    local pid=""
    local attempts=0
    local default_max_attempts=1200
    if declare -F _octopus_spawn_pid_wait_default_attempts >/dev/null 2>&1; then
        default_max_attempts=$(_octopus_spawn_pid_wait_default_attempts) || default_max_attempts=1200
    fi

    local "max_attempts=${OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS:-$default_max_attempts}"
    if ! [[ "$max_attempts" =~ ^[1-9][0-9]*$ ]]; then
        log "WARN" "invalid OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS='$max_attempts'; using default $default_max_attempts" >&2
        max_attempts=$default_max_attempts
    fi
    while [[ $attempts -lt $max_attempts ]]; do
        pid=$(awk '/^[0-9]+$/ { value=$1 } END { print value }' "$pid_file" 2>/dev/null)
        [[ -n "$pid" ]] && break
        if ! kill -0 "$wrapper_pid" 2>/dev/null; then
            wait "$wrapper_pid" 2>/dev/null || true
            pid=$(awk '/^[0-9]+$/ { value=$1 } END { print value }' "$pid_file" 2>/dev/null)
            break
        fi
        sleep 0.1
        ((attempts++)) || true
    done

    if [[ -z "$pid" ]]; then
        log "ERROR" "spawn_agent produced no provider PID for $task_id; refusing to track wrapper PID $wrapper_pid" >&2
        if [[ -s "$pid_file" ]]; then
            tail -20 "$pid_file" >&2 || true
        fi
        # #736: the wait budget can expire while $wrapper_pid is still blocked
        # inside the provider pipeline (e.g. summarization outran the PID-wait
        # window). A bare `kill "$wrapper_pid"` only signals that one process —
        # any already-forked pipeline children (timeout/codex/gemini) become
        # orphans that keep running and spending tokens. Reap the whole tree
        # with the same helper review.sh uses for stalled providers, falling
        # back to the old single-PID kill if review.sh wasn't sourced (e.g.
        # a test harness that loads only this file).
        if declare -F review_terminate_process_tree >/dev/null 2>&1; then
            review_terminate_process_tree "$wrapper_pid" 5
        else
            kill "$wrapper_pid" 2>/dev/null || true
        fi
        wait "$wrapper_pid" 2>/dev/null || true
        rm -f "$pid_file"
        if [[ "$owns_notice_file" == true ]]; then
            octo_notice_channel_replay "$notice_file"
        fi
        return 1
    fi

    # parallel_execute opens fd 9 to an internal handoff file so its signal
    # handler can see the provider PID before this function returns. Keep the
    # channel opt-in so other capture callers retain their existing stdout-only
    # contract.
    if [[ "${OCTOPUS_SPAWN_PID_HANDOFF_FD:-}" == "9" ]]; then
        printf 'provider:%s\n' "$pid" >&9
    fi
    rm -f "$pid_file"
    if [[ "$owns_notice_file" == true ]]; then
        octo_notice_channel_replay "$notice_file"
    fi
    echo "$pid"
}
