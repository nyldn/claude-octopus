#!/usr/bin/env bash
_agent_sync_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_agent_sync_lib_dir}/agent-spec.sh" 2>/dev/null || true
source "${_agent_sync_lib_dir}/provider-registry.sh" || { echo "agent-sync: failed to load provider-registry.sh" >&2; return 1 2>/dev/null || exit 1; }
source "${_agent_sync_lib_dir}/fallback-chain.sh" 2>/dev/null || true
# ═══════════════════════════════════════════════════════════════════════════════
# agent-sync.sh — Agent synchronous dispatch & Agent Teams routing
# Extracted from orchestrate.sh (v9.7.4)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Fleet dispatch guards ─────────────────────────────────────────────────────
# orchestrate.sh runs as a Bash tool subprocess. Agent Teams dispatch writes
# AGENT_TEAMS_DISPATCH: signals to stdout that CC's host never sees in that
# context, leaving all result files empty (issue #289, #288).
#
# Every parallel spawn loop MUST call fleet_dispatch_begin before the first
# spawn_agent call and fleet_dispatch_end after the last one. The smoke test
# tests/smoke/test-fleet-dispatch-guard.sh enforces this statically.
_octopus_agent_sync_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! type start_quota_watcher >/dev/null 2>&1; then
    source "${_octopus_agent_sync_lib_dir}/quota-watcher.sh" 2>/dev/null || true
fi
if ! type is_claude_agent_type >/dev/null 2>&1; then
    source "${_octopus_agent_sync_lib_dir}/routing.sh" 2>/dev/null || true
fi
if ! type run_contract_transition >/dev/null 2>&1; then
    source "${_octopus_agent_sync_lib_dir}/run-contract.sh" 2>/dev/null || true
fi
if ! type classify_agent_output >/dev/null 2>&1; then
    source "${_octopus_agent_sync_lib_dir}/error-tracking.sh" 2>/dev/null || true
fi

fleet_dispatch_begin() {
    export OCTOPUS_FORCE_LEGACY_DISPATCH=true
}

quota_watcher_kill_sync_dispatch() {
    local dispatch_pid="$1"
    pkill -KILL -P "$dispatch_pid" 2>/dev/null || true
    kill -KILL "$dispatch_pid" 2>/dev/null || true
}

fleet_dispatch_end() {
    unset OCTOPUS_FORCE_LEGACY_DISPATCH
}

# Bind a resolved AGY model to the exact argv environment used by agy-exec.
# This keeps provider execution aligned with lifecycle and cost records, while
# preserving model labels containing spaces as one environment argument.
octopus_sync_bind_resolved_model() {
    local agent_type="${1:-}" model="${2:-}" provider="" entry
    local -a filtered_env
    provider="$(octo_agent_spec_provider "$agent_type" 2>/dev/null || true)"
    [[ "$provider" == "agy" && -n "$model" ]] || return 0

    filtered_env=()
    if [[ ${#PROVIDER_ENV_ARRAY[@]} -gt 0 ]]; then
        for entry in "${PROVIDER_ENV_ARRAY[@]}"; do
            [[ "$entry" == OCTOPUS_AGY_MODEL=* ]] && continue
            filtered_env+=("$entry")
        done
    fi
    if [[ ${#filtered_env[@]} -eq 0 ]]; then
        filtered_env=(env)
    fi
    filtered_env+=("OCTOPUS_AGY_MODEL=$model")
    PROVIDER_ENV_ARRAY=("${filtered_env[@]}")
}

# Claude Code's native Agent Teams API does not expose a provider PID or a
# timeout/cancellation handle to plugin scripts. A positive Octopus timeout
# therefore cannot be enforced on that path: Claude Code documents that team
# shutdown waits for the teammate's current request/tool call. Keep native
# dispatch only for explicitly unlimited work; bounded work uses the supervised
# provider subprocess where run_with_timeout owns the process tree.
octopus_agent_teams_can_honor_timeout() {
    local effective_timeout="${1:-}"
    [[ "$effective_timeout" =~ ^[0-9]+$ ]] || return 1
    [[ "$effective_timeout" -eq 0 ]]
}

# Return the integer timeout for one synchronous attempt within a fixed
# wall-clock deadline. Retried attempts reserve one second because date(1) and
# run_with_timeout both operate at whole-second precision; without that margin,
# differing fractional start times can extend the original budget by <1s.
octopus_sync_attempt_timeout() {
    local deadline="$1"
    local now="$2"
    local retry_count="${3:-0}"
    local remaining

    [[ "$deadline" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ && "$retry_count" =~ ^[0-9]+$ ]] || return 1
    remaining=$((deadline - now))
    if [[ "$retry_count" -gt 0 ]]; then
        remaining=$((remaining - 1))
    fi
    [[ "$remaining" -gt 0 ]] || return 1
    printf '%s\n' "$remaining"
}

# Check if an agent should use Agent Teams dispatch
# Returns 0 (true) if agent should use native teams, 1 (false) for legacy bash
should_use_agent_teams() {
    local agent_type="$1"

    # Keep every caller (including retry/resume routing) consistent with
    # spawn_agent(): a bounded task needs the subprocess watchdog and PID tree.
    if ! octopus_agent_teams_can_honor_timeout "${TIMEOUT:-0}"; then
        log "DEBUG" "Bounded dispatch (${TIMEOUT}s) requires the supervised provider subprocess"
        return 1
    fi

    # Native dispatch returns before a provider process can report completion.
    # Older Claude Code builds have stable Agent Teams but no
    # last_assistant_message hook, so those tasks would remain "running"
    # forever. Route them through the supervised subprocess instead.
    if [[ "${SUPPORTS_HOOK_LAST_MESSAGE:-false}" != "true" ]]; then
        log "DEBUG" "Native Agent Teams requires SubagentStop result capture; using supervised dispatch for $agent_type"
        return 1
    fi

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
        if is_claude_agent_type "$agent_type"; then
            if [[ "$SUPPORTS_STABLE_AGENT_TEAMS" == "true" ]]; then
                return 0
            else
                log "WARN" "Agent Teams forced but SUPPORTS_STABLE_AGENT_TEAMS not available"
                return 1
            fi
        fi

        # Non-Claude agents always use legacy (external CLIs)
        return 1
    fi

    # Auto mode: use teams for Claude agents when stable teams are available
    if [[ "$SUPPORTS_STABLE_AGENT_TEAMS" == "true" ]] && is_claude_agent_type "$agent_type"; then
        return 0
    fi

    return 1
}

# Add a small, private Git directory to the disposable workspace. The object
# database remains read-only through an alternate, while HEAD and the index are
# local copies so reviewer Git commands work without copying the source .git.
_octopus_initialize_workspace_git_context() {
    local source_root="$1"
    local workspace="$2"
    local common_dir object_dir head_oid head_ref

    common_dir="$(git -C "$source_root" rev-parse --git-common-dir 2>/dev/null)" || return 1
    case "$common_dir" in
        /*) ;;
        *) common_dir="${source_root}/${common_dir}" ;;
    esac
    common_dir="$(cd "$common_dir" 2>/dev/null && pwd -P)" || return 1
    object_dir="${common_dir}/objects"
    [[ -d "$object_dir" ]] || return 1

    git -C "$workspace" init -q || return 1
    mkdir -p "$workspace/.git/objects/info" || return 1
    printf '%s\n' "$object_dir" > "$workspace/.git/objects/info/alternates" || return 1

    head_oid="$(git -C "$source_root" rev-parse --verify HEAD 2>/dev/null || true)"
    if [[ -n "$head_oid" ]]; then
        head_ref="$(git -C "$source_root" symbolic-ref -q HEAD 2>/dev/null || true)"
        if [[ -n "$head_ref" ]]; then
            git -C "$workspace" symbolic-ref HEAD "$head_ref" || return 1
            git -C "$workspace" update-ref "$head_ref" "$head_oid" || return 1
        else
            git -C "$workspace" update-ref --no-deref HEAD "$head_oid" || return 1
        fi
    fi

    # Rebuild the index from Git's portable stage records. Copying the index
    # file itself would break split-index and worktree-specific configurations.
    (
        set -o pipefail
        git -C "$source_root" ls-files --stage -z |
            git -C "$workspace" update-index -z --index-info
    ) || return 1
}

# Copy only tracked plus untracked-but-not-ignored files from a Git work tree.
# Nested repositories are removed from the parent archive list before tar runs,
# then copied recursively under their own ignore rules. Symlinks must resolve
# within their source repository. Any failure is fatal for a Git source.
_octopus_copy_git_tracked_tree() {
    local source_root="$1"
    local workspace="$2"
    local filelist copylist nestedlist entry rel entry_path
    local nested_top nested_rel resolved

    git -C "$source_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    source_root="$(cd "$source_root" 2>/dev/null && pwd -P)" || return 1

    filelist="$(mktemp "${TMPDIR:-/tmp}/octopus-tracked-tree.XXXXXX")" || return 1
    copylist="$(mktemp "${TMPDIR:-/tmp}/octopus-copy-tree.XXXXXX")" || {
        rm -f "$filelist"
        return 1
    }
    nestedlist="$(mktemp "${TMPDIR:-/tmp}/octopus-nested-tree.XXXXXX")" || {
        rm -f "$filelist" "$copylist"
        return 1
    }
    git -C "$source_root" ls-files -z --cached --others --exclude-standard >"$filelist" 2>/dev/null || {
        rm -f "$filelist" "$copylist" "$nestedlist"
        return 1
    }

    while IFS= read -r -d '' entry; do
        rel="${entry%/}"
        [[ -n "$rel" ]] || continue
        entry_path="${source_root}/${rel}"

        # Deleted tracked paths remain in the index but have no bytes to copy.
        [[ -e "$entry_path" || -L "$entry_path" ]] || continue

        if [[ -L "$entry_path" ]]; then
            # An absolute link would still point back into the source checkout
            # after tar preserves it, so fail closed even when its target is
            # physically inside source_root.
            case "$(readlink "$entry_path" 2>/dev/null)" in
                /*)
                    rm -f "$filelist" "$copylist" "$nestedlist"
                    return 1
                    ;;
            esac
            resolved="$(realpath "$entry_path" 2>/dev/null)" || {
                rm -f "$filelist" "$copylist" "$nestedlist"
                return 1
            }
            case "$resolved" in
                "$source_root"|"$source_root"/*) ;;
                *)
                    rm -f "$filelist" "$copylist" "$nestedlist"
                    return 1
                    ;;
            esac
        elif [[ -d "$entry_path" ]]; then
            nested_top="$(git -C "$entry_path" rev-parse --show-toplevel 2>/dev/null || true)"
            if [[ -n "$nested_top" ]]; then
                nested_top="$(cd "$nested_top" 2>/dev/null && pwd -P)" || {
                    rm -f "$filelist" "$copylist" "$nestedlist"
                    return 1
                }
                if [[ "$nested_top" != "$source_root" ]]; then
                    case "$nested_top" in
                        "$source_root"/*) nested_rel="${nested_top#"$source_root"/}" ;;
                        *)
                            rm -f "$filelist" "$copylist" "$nestedlist"
                            return 1
                            ;;
                    esac
                    printf '%s\0' "$nested_rel" >> "$nestedlist"
                    continue
                fi
            fi
        fi

        printf '%s\0' "$rel" >> "$copylist"
    done < "$filelist"

    if ! (
        set -o pipefail
        tar --null -C "$source_root" -T "$copylist" -cf - | tar -xf - -C "$workspace"
    ); then
        rm -f "$filelist" "$copylist" "$nestedlist"
        return 1
    fi

    while IFS= read -r -d '' nested_rel; do
        mkdir -p "$workspace/$nested_rel" || {
            rm -f "$filelist" "$copylist" "$nestedlist"
            return 1
        }
        _octopus_copy_git_tracked_tree "$source_root/$nested_rel" "$workspace/$nested_rel" || {
            rm -f "$filelist" "$copylist" "$nestedlist"
            return 1
        }
    done < "$nestedlist"

    _octopus_initialize_workspace_git_context "$source_root" "$workspace" || {
        rm -f "$filelist" "$copylist" "$nestedlist"
        return 1
    }

    rm -f "$filelist" "$copylist" "$nestedlist"
}

# Prepare an isolated copy-on-write workspace for advisory agents.
# Git sources fail closed if their selective copy fails. Non-Git directories
# retain the original private whole-tree copy because they have no ignore index.
_octopus_prepare_consultative_workspace() {
    local source_root="$1"
    local temp_root workspace git_root source_prefix
    temp_root="$(mktemp -d "${TMPDIR:-/tmp}/octopus-consultative.XXXXXX")" || return 1
    workspace="${temp_root}/workspace"
    mkdir -p "$workspace" || { rm -rf "$temp_root"; return 1; }

    if git -C "$source_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        source_root="$(cd "$source_root" 2>/dev/null && pwd -P)" || {
            rm -rf "$temp_root"
            return 1
        }
        git_root="$(git -C "$source_root" rev-parse --show-toplevel 2>/dev/null)" || {
            rm -rf "$temp_root"
            return 1
        }
        git_root="$(cd "$git_root" 2>/dev/null && pwd -P)" || {
            rm -rf "$temp_root"
            return 1
        }
        case "$source_root" in
            "$git_root") source_prefix="" ;;
            "$git_root"/*) source_prefix="${source_root#"$git_root"/}" ;;
            *)
                rm -rf "$temp_root"
                return 1
                ;;
        esac

        _octopus_copy_git_tracked_tree "$git_root" "$workspace" || {
            rm -rf "$temp_root"
            return 1
        }
        if [[ -n "$source_prefix" ]]; then
            workspace="${workspace}/${source_prefix}"
            [[ -d "$workspace" ]] || { rm -rf "$temp_root"; return 1; }
        fi
    else
        if ! cp -a --reflink=auto "${source_root}/." "${workspace}/" 2>/dev/null; then
            rm -rf "$workspace"
            mkdir -p "$workspace" || { rm -rf "$temp_root"; return 1; }
            cp -a "${source_root}/." "${workspace}/" || { rm -rf "$temp_root"; return 1; }
        fi
    fi

    printf '%s\n' "$workspace"
}

# Run a synchronous agent in a strictly consultative context.
#
# Council seats and pre-implementation design reviews are advisory. Native
# read-only sandboxing is not portable across all Codex runtimes (notably
# Landlock-restricted hosts), so advisory agents run with the functional
# danger-full-access mode inside a private disposable workspace. Relative-path
# writes made during normal advisory work are discarded with that workspace.
# This is mutation isolation for accidental workspace edits, not a security
# boundary against deliberate access to absolute paths outside the workspace.
run_agent_sync_consultative() {
    local old_security_set="${OCTOPUS_SECURITY_V870+x}"
    local old_security="${OCTOPUS_SECURITY_V870:-}"
    local old_agy_sandbox_set="${OCTOPUS_AGY_SANDBOX+x}"
    local old_agy_sandbox="${OCTOPUS_AGY_SANDBOX:-}"
    local old_codex_sandbox_set="${OCTOPUS_CODEX_SANDBOX+x}"
    local old_codex_sandbox="${OCTOPUS_CODEX_SANDBOX:-}"
    local old_autonomy_set="${CLAUDE_OCTOPUS_AUTONOMY+x}"
    local old_autonomy="${CLAUDE_OCTOPUS_AUTONOMY:-}"
    local source_root source_root_logical workspace workspace_root temp_root rc original_prompt isolated_prompt agent_output cleanup_note
    local -a consultative_args

    source_root_logical="$PWD"
    source_root="$(pwd -P)"
    workspace="$(_octopus_prepare_consultative_workspace "$source_root")" || {
        log ERROR "Failed to prepare disposable consultative workspace from: $source_root"
        return 1
    }
    workspace_root="$(git -C "$workspace" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$workspace")"
    temp_root="$(dirname "$workspace_root")"

    consultative_args=("$@")
    original_prompt="${consultative_args[1]:-}"
    isolated_prompt="${original_prompt//$source_root/$workspace}"
    if [[ "$source_root_logical" != "$source_root" ]]; then
        isolated_prompt="${isolated_prompt//$source_root_logical/$workspace}"
    fi
    isolated_prompt="${isolated_prompt}

## Consultative Workspace Boundary
Work only inside this disposable workspace: ${workspace}
Treat ${workspace} as the working copy for this advisory task. Any relative-path workspace changes are exploratory and will be discarded. Return analysis and recommendations only."
    consultative_args[1]="$isolated_prompt"

    unset OCTOPUS_SECURITY_V870
    unset OCTOPUS_AGY_SANDBOX
    unset CLAUDE_OCTOPUS_AUTONOMY
    export OCTOPUS_CODEX_SANDBOX="danger-full-access"

    if agent_output=$(cd "$workspace" && run_agent_sync "${consultative_args[@]}"); then
        rc=0
    else
        rc=$?
    fi

    cleanup_note="Octopus deleted the workspace before returning."
    if ! rm -rf "$temp_root" 2>/dev/null; then
        cleanup_note="Octopus attempted cleanup before returning but could not confirm deletion."
        if declare -F log >/dev/null 2>&1; then
            log WARN "Failed to remove consultative workspace: $temp_root"
        else
            printf 'WARN: failed to remove consultative workspace: %s\n' "$temp_root" >&2
        fi
    fi

    if [[ -n "$old_security_set" ]]; then export OCTOPUS_SECURITY_V870="$old_security"; else unset OCTOPUS_SECURITY_V870; fi
    if [[ -n "$old_agy_sandbox_set" ]]; then export OCTOPUS_AGY_SANDBOX="$old_agy_sandbox"; else unset OCTOPUS_AGY_SANDBOX; fi
    if [[ -n "$old_autonomy_set" ]]; then export CLAUDE_OCTOPUS_AUTONOMY="$old_autonomy"; else unset CLAUDE_OCTOPUS_AUTONOMY; fi
    if [[ -n "$old_codex_sandbox_set" ]]; then
        export OCTOPUS_CODEX_SANDBOX="$old_codex_sandbox"
    else
        unset OCTOPUS_CODEX_SANDBOX
    fi

    if [[ -n "$agent_output" ]]; then
        cat <<EOF
## UNVERIFIED CONSULTATIVE OUTPUT

This output came from a disposable workspace. ${cleanup_note} It is advisory and non-deliverable. Claimed file changes, test counts, live probes, or completed implementation are not verified evidence and must not be reported as delivered work.

${agent_output}

## END UNVERIFIED CONSULTATIVE OUTPUT
EOF
    fi

    return "$rc"
}

# Synchronous agent execution (for sequential steps within phases)
run_agent_sync() {
    local agent_type="$1"
    local prompt="$2"
    local timeout_secs="${3:-120}"
    local role="${4:-}"   # Optional role override
    local phase="${5:-}"  # Optional phase context

    # OCTOPUS_AGENT_TIMEOUT env var overrides all caller-hardcoded values.
    # Without this, callers passing explicit values (e.g. 300, 600) bypass the
    # dynamic path and the env var has no effect — making it dead code (#410).
    if [[ -n "${OCTOPUS_AGENT_TIMEOUT:-}" && "${OCTOPUS_AGENT_TIMEOUT}" =~ ^[0-9]+$ ]]; then
        timeout_secs="$OCTOPUS_AGENT_TIMEOUT"
    elif [[ "$timeout_secs" -eq 120 ]]; then
        # v8.19.0: Dynamic timeout calculation (when caller uses default 120)
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

    local _progress_unique
    if declare -F _octopus_next_spawn_task_id >/dev/null 2>&1; then
        _progress_unique="$(_octopus_next_spawn_task_id)"
    else
        local _sync_unique_dir
        _sync_unique_dir="$(mktemp -d "${TMPDIR:-/tmp}/octopus-sync-id.XXXXXX")" || return 74
        _progress_unique="$(basename "$_sync_unique_dir")-$$"
        rmdir "$_sync_unique_dir" 2>/dev/null || true
    fi
    local _sync_seat_id
    _sync_seat_id="sync-${phase:-unknown}-$(octo_agent_spec_slug "$agent_type")-${_progress_unique}"
    local _contract_provider _contract_requested_model
    _contract_provider="$(octo_agent_spec_contract_provider "$agent_type")" || return 74
    _contract_requested_model="$(octo_agent_spec_contract_model "$agent_type" "${OCTOPUS_REQUESTED_MODEL:-}")" || return 74
    if [[ "${OCTOPUS_PERSISTENCE_AVAILABLE:-true}" == "false" ]]; then
        log ERROR "Persistence unavailable; refusing untracked provider dispatch for $agent_type"
    fi
    run_contract_transition "$_sync_seat_id" planned \
        "requested_provider=$_contract_provider" \
        "requested_model=$_contract_requested_model" \
        "requested_effort=${OCTOPUS_REQUESTED_EFFORT:-}" \
        "phase=${phase:-unknown}" "role=${role:-none}" \
        "attempt_id=${_sync_seat_id}-attempt-1" || return 74

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

    # v9.37.0: Enforce prompt budget after all sync-agent injections, including
    # the Codex subagent preamble. This catches oversized prompts before a
    # provider burns time and exits with a context-length error.
    if [[ "$agent_type" == codex* && "$agent_type" != "codex-review" ]]; then
        enhanced_prompt="${CODEX_SUBAGENT_PREAMBLE}${enhanced_prompt}"
    fi
    local tokens_in
    tokens_in=$(( ${#enhanced_prompt} / 4 ))
    enhanced_prompt=$(enforce_context_budget "$enhanced_prompt" "$role" "$agent_type")
    local _budget_rc=$?
    if [[ $_budget_rc -ne 0 ]]; then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Prompt exceeded context budget" >/dev/null 2>&1 || true
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" 0 "Prompt exceeded context budget" 0 "" "$role" "$_sync_seat_id" failed none || true
        return "$_budget_rc"
    fi

    log DEBUG "run_agent_sync: agent=$agent_type, role=${role:-none}, phase=${phase:-none}"

    if declare -f octo_routing_policy >/dev/null 2>&1 &&
       [[ "$(octo_routing_policy 2>/dev/null || printf '%s' off)" == "eval" ]] &&
       declare -f octo_route_task_class >/dev/null 2>&1; then
        local OCTOPUS_TASK_CLASS
        OCTOPUS_TASK_CLASS="$(octo_route_task_class "$enhanced_prompt" "$role" "$phase")"
        export OCTOPUS_TASK_CLASS
    fi

    # Resolve the baseline seat before provider preflight so failures retain the
    # v10 planned → starting lifecycle. Fable's atomic claim happens later,
    # during command construction, only after health and persistence succeed.
    local model
    if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Model resolution failed" >/dev/null 2>&1 || true
        return 1
    fi
    local _progress_task_id
    _progress_task_id="$_sync_seat_id"
    local _estimated_cost="0.000000"
    if type estimate_agent_call_cost >/dev/null 2>&1; then
        _estimated_cost=$(estimate_agent_call_cost "$agent_type" "$model" "$enhanced_prompt")
    fi
    run_contract_transition "$_sync_seat_id" starting \
        "resolved_provider=$_contract_provider" "resolved_model=$model" \
        "resolved_effort=${OCTOPUS_RESOLVED_EFFORT:-${OCTOPUS_REQUESTED_EFFORT:-}}" \
        "estimated_cost_usd=$_estimated_cost" || return 74

    # v8.49.0: Pre-dispatch health check — verify provider is reachable.
    local _provider_for_health="" _health_handler="none"
    _provider_for_health="$(octo_provider_canonical "$(octo_agent_spec_executor "$agent_type")" 2>/dev/null || true)"
    if [[ -n "$_provider_for_health" ]]; then
        _health_handler="$(octo_provider_health_handler "$_provider_for_health" 2>/dev/null || printf '%s' none)"
    fi
    if [[ "$_health_handler" != "none" ]]; then
        local _health_diag="" _health_failed=false
        if ! declare -f "$_health_handler" >/dev/null 2>&1; then
            _health_diag="registry health handler unavailable: $_health_handler"
            _health_failed=true
        elif ! _health_diag=$("$_health_handler" "$_provider_for_health" 2>&1); then
            _health_failed=true
        fi
        if [[ "$_health_failed" == true ]]; then
            log WARN "Provider '$_provider_for_health' health check failed: $_health_diag"
            log WARN "Skipping agent dispatch for $agent_type (provider unavailable)"
            type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" 0 "Provider unavailable: $_health_diag" 0 "" "$role" "$_sync_seat_id" failed none || true
            run_contract_transition "$_sync_seat_id" failed \
                "reason=Provider unavailable: $_health_diag" >/dev/null 2>&1 || true
            echo "[Provider $_provider_for_health unavailable: $_health_diag]"
            return 1
        fi
    fi

    run_contract_transition "$_sync_seat_id" authenticated || return 74

    if [[ "${OCTOPUS_PERSISTENCE_AVAILABLE:-true}" == "false" ]]; then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Persistence unavailable" >/dev/null 2>&1 || true
        return 74
    fi

    local cmd _prompt_bytes
    if ! _prompt_bytes=$(octo_prompt_byte_length "$enhanced_prompt"); then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Prompt byte measurement failed" >/dev/null 2>&1 || true
        return 1
    fi
    if ! cmd=$(get_agent_command "$agent_type" "$phase" "$role" "$_prompt_bytes"); then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Provider command unavailable" >/dev/null 2>&1 || true
        return 1
    fi
    if declare -f octo_dispatch_command_model >/dev/null 2>&1; then
        model="$(octo_dispatch_command_model "$cmd" "$model")"
    fi

    record_agent_call "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}" "${role:-none}" "0"

    # v7.25.0: Record metrics start
    local metrics_id=""
    if command -v record_agent_start &> /dev/null; then
        metrics_id=$(record_agent_start "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}") || true
    fi

    # SECURITY: Use array-based execution to prevent word-splitting vulnerabilities
    local -a cmd_array
    local -a inner_cmd_array
    build_provider_env "$agent_type"
    octopus_sync_bind_resolved_model "$agent_type" "$model"
    read -ra inner_cmd_array <<< "$cmd"
    if [[ ${#PROVIDER_ENV_ARRAY[@]} -gt 0 ]]; then
        cmd_array=("${PROVIDER_ENV_ARRAY[@]}" "${inner_cmd_array[@]}")
        log "DEBUG" "Credential isolation active for $agent_type"
    else
        cmd_array=("${inner_cmd_array[@]}")
    fi

    # Capture output and exit code separately
    local output
    local exit_code
    local temp_err="${RESULTS_DIR}/.tmp-agent-error-${_progress_unique}.err"
    local temp_out="${RESULTS_DIR}/.tmp-agent-out-${_progress_unique}.out"

    # -p "" triggers headless mode for CLIs that require it while prompt content
    # comes via stdin to avoid OS argument limits. Qwen and Cursor Agent follow
    # the same headless contract; Copilot parity is
    # maintained with spawn/workflows dispatch paths.
    if [[ "$agent_type" == copilot* || "$agent_type" == qwen* || "$agent_type" == cursor-agent* ]]; then
        cmd_array+=(-p "")
    fi

    # v9.2.2: All agents use stdin to avoid ARG_MAX "Argument list too long" on large diffs (Issue #173)
    # Captured for partial-writes detection on timeout.
    local _dispatch_start _dispatch_cwd _sync_timeout_deadline=0
    _dispatch_start=$(date +%s)
    _dispatch_cwd=$(pwd)
    if [[ "$timeout_secs" =~ ^[0-9]+$ ]] && [[ "$timeout_secs" -gt 0 ]]; then
        _sync_timeout_deadline=$((_dispatch_start + timeout_secs))
    fi

    local _quota_watcher_pid=""

    # Always init temp files so readers never fail on missing file.
    mkdir -p "${RESULTS_DIR}" 2>/dev/null || true
    : > "$temp_err"
    : > "$temp_out"
    type update_agent_status >/dev/null 2>&1 && update_agent_status \
        "$agent_type" "running" 0 "$_estimated_cost" "$timeout_secs" \
        "$_progress_task_id" "${phase:-unknown}" "" || true
    run_contract_transition "$_sync_seat_id" running \
        "resolved_model=$model" || return 74

    # AGY has an intermittent native SIGSEGV under heterogeneous orchestration
    # (#943). Retry that provider exactly once, while keeping both attempts
    # inside the caller's original wall-clock budget. Signal stderr is retained
    # for every provider so terminal crashes remain diagnosable from run data.
    local _sync_retry_count=0
    local _sync_sigsegv_retries=0
    local _sync_recovered_sigsegv=false
    local _sync_signal_artifact=""
    case "$agent_type" in
        agy*|antigravity) _sync_sigsegv_retries=1 ;;
    esac

    while true; do
        local _attempt_timeout="$timeout_secs"
        if [[ "$_sync_timeout_deadline" -gt 0 ]]; then
            local _attempt_now
            _attempt_now=$(date +%s)
            if ! _attempt_timeout=$(octopus_sync_attempt_timeout \
                "$_sync_timeout_deadline" "$_attempt_now" "$_sync_retry_count"); then
                exit_code=124
                break
            fi
        fi

        if printf '%s' "$enhanced_prompt" | OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP="true" \
            run_with_timeout "$_attempt_timeout" "${cmd_array[@]}" 2>"$temp_err" >"$temp_out"; then
            exit_code=0
        else
            exit_code=$?
        fi

        if [[ "$exit_code" -ge 128 && "$exit_code" -le 192 ]]; then
            local _signal_attempt=$((_sync_retry_count + 1))
            _sync_signal_artifact="${RESULTS_DIR}/sync-failure-${_progress_unique}-attempt-${_signal_attempt}.stderr.log"
            if (umask 077; cp "$temp_err" "$_sync_signal_artifact") 2>/dev/null; then
                chmod 600 "$_sync_signal_artifact" 2>/dev/null || true
            else
                _sync_signal_artifact=""
            fi
        fi

        if [[ "$exit_code" -eq 139 && "$_sync_retry_count" -lt "$_sync_sigsegv_retries" ]]; then
            _sync_retry_count=$((_sync_retry_count + 1))
            log WARN "Agent $agent_type exited 139 (SIGSEGV); retrying once within the original ${timeout_secs}s budget (stderr: ${_sync_signal_artifact:-unavailable})"
            : > "$temp_err"
            : > "$temp_out"
            continue
        fi
        [[ "$exit_code" -eq 0 && "$_sync_retry_count" -gt 0 ]] && _sync_recovered_sigsegv=true
        break
    done
    stop_quota_watcher "$_quota_watcher_pid"
    local _sync_output_truncated=false

    local _elapsed_ms
    _elapsed_ms=$(( ($(date +%s) - _dispatch_start) * 1000 ))

    # Check exit code and handle errors
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Agent $agent_type failed with exit code $exit_code (role=$role, phase=$phase)"
        if [[ -s "$temp_err" ]]; then
            log ERROR "Error details: $(cat "$temp_err")"
        fi
        # Hint callers when codex wrote deliverables under workspace-write
        # before SIGTERM — a bare "TIMEOUT" banner otherwise hides that work.
        if [[ $exit_code -eq 124 || $exit_code -eq 143 ]]; then
            # -newermt is GNU findutils only; skip silently on BSD find (macOS).
            if find /dev/null -newermt "@0" >/dev/null 2>&1; then
                # Single-pass while-read avoids `find | head` SIGPIPE under
                # inherited pipefail and counts every match instead of capping
                # at the head budget. -maxdepth bounds traversal on monorepos.
                local _n_changed=0
                local _samples=()
                local _line
                while IFS= read -r _line; do
                    _n_changed=$((_n_changed + 1))
                    [[ ${#_samples[@]} -lt 5 ]] && _samples+=("$_line")
                done < <(find "$_dispatch_cwd" -maxdepth "${OCTOPUS_PARTIAL_WRITES_DEPTH:-4}" \
                            -type f -newermt "@${_dispatch_start}" \
                            -not -path '*/.git/*' -not -path '*/node_modules/*' \
                            2>/dev/null)
                if [[ $_n_changed -gt 0 ]]; then
                    local _ts
                    _ts=$(date -d "@${_dispatch_start}" '+%H:%M:%S' 2>/dev/null \
                          || date -r "${_dispatch_start}" '+%H:%M:%S' 2>/dev/null \
                          || echo "dispatch")
                    log WARN "Timeout with ${_n_changed} file(s) modified in $_dispatch_cwd since dispatch — provider may have written deliverables. Inspect before retrying."
                    log INFO "Partial writes detected (${_n_changed} files changed since ${_ts})"
                    local _s
                    for _s in "${_samples[@]}"; do log INFO "   $_s"; done
                    [[ $_n_changed -gt 5 ]] && log INFO "   ... (+$((_n_changed - 5)) more)"
                fi
            fi
        fi
        local _sync_status="failed"
        local _sync_reason="Exit code $exit_code"
        if [[ $exit_code -eq 124 || $exit_code -eq 143 ]]; then
            _sync_status="timeout"
            _sync_reason="Timed out before completion"
        fi
        run_contract_transition "$_sync_seat_id" "$_sync_status" \
            "reason=$_sync_reason" "stderr_file=$_sync_signal_artifact" \
            "duration_ms=$_elapsed_ms" >/dev/null 2>&1 || true
        type update_agent_status >/dev/null 2>&1 && update_agent_status \
            "$agent_type" "$_sync_status" "$_elapsed_ms" "$_estimated_cost" "$timeout_secs" \
            "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "$_sync_status" "$tokens_in" "$(octo_estimate_tokens_for_file "$temp_out" 2>/dev/null || echo 0)" "$_sync_reason" "$_elapsed_ms" "$_sync_signal_artifact" "$role" "$_sync_seat_id" "$_sync_status" none || true
        rm -f "$temp_err" "$temp_out"
        return $exit_code
    fi

    if type classify_agent_output >/dev/null 2>&1; then
        local _classification _sync_status _sync_reason
        _classification=$(classify_agent_output "$temp_out" "$exit_code" "$agent_type" "$temp_err")
        _sync_status="${_classification%%:*}"
        _sync_reason="${_classification#*:}"
        if [[ "$_sync_status" == "failed" ]]; then
            # Oversize rejections are a provider-input-size mismatch, not a hard
            # run failure. Return 0 with empty output so multi-provider dispatch
            # loops continue to gather perspectives from remaining providers (#410).
            if [[ "$_sync_reason" == *"oversize"* || "$_sync_reason" == *"Prompt rejected by provider"* ]]; then
                log WARN "Agent $agent_type prompt rejected as oversized — skipping provider (reduce session context or lower OCTOPUS_CONTEXT_BUDGET)"
                type update_agent_status >/dev/null 2>&1 && update_agent_status \
                    "$agent_type" "skipped" "$_elapsed_ms" 0 "$timeout_secs" \
                    "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "skipped" "$tokens_in" 0 "Prompt rejected by provider (oversize)" "$_elapsed_ms" "$_sync_signal_artifact" "$role" "$_sync_seat_id" skipped none || true
                run_contract_transition "$_sync_seat_id" skipped \
                    "reason=Prompt rejected by provider (oversize)" \
                    "duration_ms=$_elapsed_ms" >/dev/null 2>&1 || true
                rm -f "$temp_err" "$temp_out"
                echo ""
                return 0
            fi
            log ERROR "Agent $agent_type returned unusable output: $_sync_reason"
            type update_agent_status >/dev/null 2>&1 && update_agent_status \
                "$agent_type" "failed" "$_elapsed_ms" "$_estimated_cost" "$timeout_secs" \
                "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
            type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" "$(octo_estimate_tokens_for_file "$temp_out" 2>/dev/null || echo 0)" "$_sync_reason" "$_elapsed_ms" "$_sync_signal_artifact" "$role" "$_sync_seat_id" failed none || true
            run_contract_transition "$_sync_seat_id" failed \
                "reason=$_sync_reason" "stderr_file=$_sync_signal_artifact" \
                "duration_ms=$_elapsed_ms" >/dev/null 2>&1 || true
            rm -f "$temp_err" "$temp_out"
            return 1
        fi
        if [[ "$_sync_recovered_sigsegv" == "true" ]]; then
            _sync_status="degraded"
            if [[ -n "$_sync_reason" ]]; then
                _sync_reason="Recovered after AGY exit 139; ${_sync_reason}"
            else
                _sync_reason="Recovered after AGY exit 139"
            fi
        fi
        local _sync_artifact_source="$temp_out"
        if ! _octo_run_output_usable_file "$_sync_artifact_source" && \
           [[ "$_sync_status" == degraded ]] && \
           octo_file_has_codex_recoverable_stderr "$temp_err"; then
            _sync_artifact_source="$temp_err"
        fi

        # Apply the byte cap after selecting stdout or recoverable stderr so
        # both the returned text and durable artifact obey the same contract.
        local _max_bytes="${OCTOPUS_AGENT_MAX_OUTPUT_BYTES:-262144}"
        local _orig_bytes _banner _banner_bytes _budget _head_bytes _tail_bytes
        local _head_chunk="" _tail_chunk=""
        _orig_bytes="$(wc -c < "$_sync_artifact_source" 2>/dev/null | tr -d ' ')"
        [[ "$_orig_bytes" =~ ^[0-9]+$ ]] || _orig_bytes=0
        output="$(cat "$_sync_artifact_source")"
        if [[ "$_max_bytes" =~ ^[0-9]+$ && "$_max_bytes" -gt 0 && "$_orig_bytes" -gt "$_max_bytes" ]]; then
            _banner=$'\n\n--- OUTPUT TRUNCATED: '"${_orig_bytes}"$' bytes captured ---\n(override with OCTOPUS_AGENT_MAX_OUTPUT_BYTES=<bytes>; 0 disables cap)\n\n'
            _banner_bytes="$(printf '%s' "$_banner" | wc -c | tr -d ' ')"
            _budget=$((_max_bytes - _banner_bytes))
            if [[ "$_budget" -le 0 ]]; then
                output="${_banner:0:$_max_bytes}"
            else
                _head_bytes=$((_budget / 8))
                [[ "$_head_bytes" -gt 4096 ]] && _head_bytes=4096
                _tail_bytes=$((_budget - _head_bytes))
                _head_chunk="$(head -c "$_head_bytes" "$_sync_artifact_source" 2>/dev/null)"
                _tail_chunk="$(tail -c "$_tail_bytes" "$_sync_artifact_source" 2>/dev/null)"
                output="${_head_chunk}${_banner}${_tail_chunk}"
            fi
            log WARN "Agent $agent_type output truncated: ${_orig_bytes}B (cap=${_max_bytes}B)"
            _sync_output_truncated=true
        fi
        if [[ "$_sync_output_truncated" == "true" ]]; then
            _sync_status="degraded"
            if [[ -n "$_sync_reason" ]]; then
                _sync_reason="${_sync_reason}; output truncated"
            else
                _sync_reason="Output truncated"
            fi
        fi
        local _sync_result_artifact="${RESULTS_DIR}/sync-result-${_progress_unique}.md"
        local _sync_result_tmp
        _sync_result_tmp="$(mktemp "${_sync_result_artifact}.tmp.XXXXXX")" || {
            run_contract_transition "$_sync_seat_id" failed \
                "reason=Unable to allocate durable result artifact" >/dev/null 2>&1 || true
            rm -f "$temp_err" "$temp_out"
            return 1
        }
        local _sync_result_write_rc=0
        if [[ "$_sync_output_truncated" == true ]]; then
            (umask 077; printf '%s' "$output" > "$_sync_result_tmp") 2>/dev/null || _sync_result_write_rc=$?
        else
            (umask 077; cp "$_sync_artifact_source" "$_sync_result_tmp") 2>/dev/null || _sync_result_write_rc=$?
        fi
        if [[ "$_sync_result_write_rc" -ne 0 ]] || \
           ! mv "$_sync_result_tmp" "$_sync_result_artifact" 2>/dev/null; then
            rm -f "$_sync_result_tmp" "$temp_err" "$temp_out"
            run_contract_transition "$_sync_seat_id" failed \
                "reason=Unable to publish durable result artifact" >/dev/null 2>&1 || true
            return 1
        fi

        local _sync_stderr_artifact="$_sync_signal_artifact"
        if [[ -z "$_sync_stderr_artifact" && -s "$temp_err" ]]; then
            _sync_stderr_artifact="${RESULTS_DIR}/sync-stderr-${_progress_unique}.log"
            local _sync_stderr_tmp
            _sync_stderr_tmp="$(mktemp "${_sync_stderr_artifact}.tmp.XXXXXX")" || {
                run_contract_transition "$_sync_seat_id" failed \
                    "reason=Unable to allocate durable stderr artifact" >/dev/null 2>&1 || true
                rm -f "$temp_err" "$temp_out"
                return 1
            }
            if ! (umask 077; cp "$temp_err" "$_sync_stderr_tmp") 2>/dev/null || \
               ! mv "$_sync_stderr_tmp" "$_sync_stderr_artifact" 2>/dev/null; then
                rm -f "$_sync_stderr_tmp" "$temp_err" "$temp_out"
                run_contract_transition "$_sync_seat_id" failed \
                    "reason=Unable to publish durable stderr artifact" >/dev/null 2>&1 || true
                return 1
            fi
        fi

        run_contract_transition "$_sync_seat_id" output_received \
            "output_file=$_sync_result_artifact" "stderr_file=$_sync_stderr_artifact" \
            "attempt_id=${_sync_seat_id}-attempt-$((_sync_retry_count + 1))" \
            "tokens_out=$(octo_estimate_tokens_for_file "$_sync_result_artifact" 2>/dev/null || echo 0)" \
            "duration_ms=$_elapsed_ms" || {
                run_contract_transition "$_sync_seat_id" failed \
                    "reason=Unable to record received output" >/dev/null 2>&1 || true
                rm -f "$temp_err" "$temp_out"
                return 1
            }
        run_contract_transition "$_sync_seat_id" validated \
            "contribution=eligible" || {
                run_contract_transition "$_sync_seat_id" failed \
                    "reason=Unable to validate provider output" >/dev/null 2>&1 || true
                rm -f "$temp_err" "$temp_out"
                return 1
            }
        if [[ "$_sync_status" == degraded ]]; then
            run_contract_transition "$_sync_seat_id" degraded \
                "contribution=eligible-with-warning" "reason=$_sync_reason" || {
                    run_contract_transition "$_sync_seat_id" failed \
                        "reason=Unable to record degraded contribution" >/dev/null 2>&1 || true
                    rm -f "$temp_err" "$temp_out"
                    return 1
                }
        else
            run_contract_transition "$_sync_seat_id" contributed \
                "contribution=eligible" || {
                    run_contract_transition "$_sync_seat_id" failed \
                        "reason=Unable to record successful contribution" >/dev/null 2>&1 || true
                    rm -f "$temp_err" "$temp_out"
                    return 1
                }
        fi
        local _sync_projection_transition=contributed
        local _sync_projection_contribution=eligible
        if [[ "$_sync_status" == degraded ]]; then
            _sync_projection_transition=degraded
            _sync_projection_contribution=eligible-with-warning
        fi
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "$_sync_status" "$tokens_in" "$(octo_estimate_tokens_for_file "$_sync_result_artifact" 2>/dev/null || echo 0)" "$_sync_reason" "$_elapsed_ms" "$_sync_result_artifact" "$role" "$_sync_seat_id" "$_sync_projection_transition" "$_sync_projection_contribution" || true
        type update_agent_status >/dev/null 2>&1 && update_agent_status \
            "$agent_type" "$_sync_status" "$_elapsed_ms" "$_estimated_cost" "$timeout_secs" \
            "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
    else
        local _unclassified_status="completed"
        local _unclassified_reason=""
        if [[ "$_sync_recovered_sigsegv" == "true" ]]; then
            _unclassified_status="degraded"
            _unclassified_reason="Recovered after AGY exit 139"
        fi
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "$_unclassified_status" "$tokens_in" "$(octo_estimate_tokens_for_file "$temp_out" 2>/dev/null || echo 0)" "$_unclassified_reason" "$_elapsed_ms" "$_sync_signal_artifact" "$role" || true
        type update_agent_status >/dev/null 2>&1 && update_agent_status \
            "$agent_type" "$_unclassified_status" "$_elapsed_ms" "$_estimated_cost" "$timeout_secs" \
            "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
    fi

    # v8.7.0: Wrap external CLI output with trust markers
    case "$agent_type" in codex*|gemini*|agy*|antigravity|perplexity*|cursor-agent*)
        output=$(wrap_cli_output "$agent_type" "$output") ;; esac

    # Check if output is suspiciously empty or placeholder
    if [[ -z "$output" || "$output" == "Provider available" ]]; then
        log WARN "Agent $agent_type returned empty or placeholder output (role=$role, phase=$phase)"
        if [[ -s "$temp_err" ]]; then
            log WARN "Possible issue: $(cat "$temp_err")"
        fi
    fi

    rm -f "$temp_err" "$temp_out"

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
