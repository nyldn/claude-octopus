#!/usr/bin/env bash
# Immutable, redacted execution decisions shared by synchronous and background
# dispatch. Provider adapters still own command/auth construction; this layer
# records and transports their resolved result without re-running policy.

[[ -n "${_OCTOPUS_DISPATCH_PLAN_LOADED:-}" ]] && return 0
_OCTOPUS_DISPATCH_PLAN_LOADED=true
_octo_dispatch_plan_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_octo_dispatch_plan_is_credential_name() {
    case "${1:-}" in
        *API_KEY*|*_TOKEN|*_TOKEN_*|*SECRET*|*PASSWORD*|*CREDENTIAL*) return 0 ;;
        *) return 1 ;;
    esac
}

# Bind provider-native model labels that cannot safely be serialized into the
# legacy command string. Antigravity labels may contain spaces and parentheses;
# keeping the label in one env argv element preserves it across both sync and
# background dispatch without eval or shell re-parsing.
octo_dispatch_plan_bind_model_env() {
    local agent_spec="${1:-}" model="${2:-}" provider="" entry
    local -a filtered_env=()
    provider="$(octo_agent_spec_provider "$agent_spec" 2>/dev/null || true)"
    [[ "$provider" == "agy" && -n "$model" ]] || return 0

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

octo_dispatch_selection_source() {
    local agent_spec="${1:-}" provider model_env
    if octo_agent_spec_explicit_model "$agent_spec" >/dev/null 2>&1; then
        printf 'explicit-agent-spec\n'
        return 0
    fi
    provider="$(octo_agent_spec_provider "$agent_spec" 2>/dev/null || true)"
    model_env="$(octo_provider_model_env "$provider" 2>/dev/null || true)"
    if [[ -n "$model_env" && -n "${!model_env:-}" ]]; then
        printf 'environment\n'
    else
        printf 'resolved-policy\n'
    fi
}

octo_dispatch_plan_create() {
    local agent_spec="${1:-}" phase="${2:-}" role="${3:-}"
    local command="${4:-}" requested_model="${5:-}"
    local deadline_epoch="${6:-0}" prompt_bytes="${7:-0}"
    local append_empty_prompt="${8:-false}"
    local project_root="${PROJECT_ROOT:-}" plugin_root="${PLUGIN_DIR:-${_octo_dispatch_plan_lib_dir}/../..}"
    local provider canonical_model family selection_source tool_policy
    local input_budget output_reserve overhead_reserve billing_mode
    local entry name provider_env_declaration
    local -a argv=()

    [[ "$project_root" == /* && "$plugin_root" == /* ]] || return 2
    [[ -d "$project_root" && -d "$plugin_root" ]] || return 2
    project_root="$(cd "$project_root" && pwd -P)" || return 2
    plugin_root="$(cd "$plugin_root" && pwd -P)" || return 2
    [[ "$project_root" != / && "$plugin_root" != / ]] || return 2
    [[ "$deadline_epoch" =~ ^[0-9]+$ && "$prompt_bytes" =~ ^[0-9]+$ ]] || return 2
    [[ -n "$command" && -n "$requested_model" ]] || return 2

    provider="$(octo_agent_spec_provider "$agent_spec")" || return 2
    canonical_model="$(octo_model_canonical_id "$requested_model")" || return 2
    family="$(octo_model_family "$canonical_model")"
    selection_source="$(octo_dispatch_selection_source "$agent_spec")"
    if declare -f get_provider_context_limit >/dev/null 2>&1; then
        input_budget="$(get_provider_context_limit "$agent_spec" "$phase" "$role")" || return 2
    else
        input_budget="${OCTOPUS_CONTEXT_BUDGET:-12000}"
    fi
    output_reserve="${OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS:-1024}"
    overhead_reserve="${OCTOPUS_CONTEXT_OVERHEAD_TOKENS:-512}"

    tool_policy="$(get_tool_policy "$role" 2>/dev/null || printf 'unknown')"
    if declare -f octo_tool_loop_requires_no_tools >/dev/null 2>&1 &&
       octo_tool_loop_requires_no_tools "$phase" "$role"; then
        tool_policy=none
    fi
    if declare -f _octo_usage_billing_mode >/dev/null 2>&1; then
        billing_mode="$(_octo_usage_billing_mode "$agent_spec")"
    else
        billing_mode="unknown"
    fi

    read -ra argv <<< "$command"
    if [[ "$append_empty_prompt" == true ]]; then
        argv+=("-p" "")
    fi
    [[ ${#argv[@]} -gt 0 ]] || return 2
    for entry in "${argv[@]}"; do
        if [[ "$entry" == *=* ]]; then
            name="${entry%%=*}"
            _octo_dispatch_plan_is_credential_name "$name" && return 2
        fi
    done

    local env_json='[]' credentials_json='[]'
    provider_env_declaration="$(declare -p PROVIDER_ENV_ARRAY 2>/dev/null || true)"
    if [[ -n "$provider_env_declaration" &&
          "$provider_env_declaration" != *"=()" &&
          "$provider_env_declaration" != *"='()'" ]]; then
        for entry in "${PROVIDER_ENV_ARRAY[@]}"; do
            [[ "$entry" == *=* ]] || continue
            name="${entry%%=*}"
            [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
            env_json="$(jq -cn --argjson values "$env_json" --arg name "$name" '$values + [$name]')" || return 2
            if _octo_dispatch_plan_is_credential_name "$name"; then
                credentials_json="$(jq -cn --argjson values "$credentials_json" --arg name "$name" '$values + [$name]')" || return 2
            fi
        done
    fi

    local argv_json
    argv_json="$(jq -cn --args '$ARGS.positional' -- "${argv[@]}")" || return 2

    jq -cn \
        --argjson schema_version 1 \
        --arg agent_spec "$agent_spec" --arg provider "$provider" \
        --arg requested_model "$requested_model" --arg canonical_model "$canonical_model" \
        --arg model_family "$family" --arg selection_source "$selection_source" \
        --arg project_root "$project_root" --arg plugin_root "$plugin_root" \
        --arg phase "$phase" --arg role "$role" --arg tool_policy "$tool_policy" \
        --arg billing_mode "$billing_mode" \
        --argjson argv "$argv_json" --argjson environment_names "$env_json" \
        --argjson credential_names "$credentials_json" \
        --argjson available_input_tokens "$input_budget" \
        --argjson output_reserve_tokens "$output_reserve" \
        --argjson overhead_tokens "$overhead_reserve" \
        --argjson prompt_bytes "$prompt_bytes" --argjson deadline_epoch "$deadline_epoch" \
        '{schema_version:$schema_version, agent_spec:$agent_spec, provider:$provider,
          requested_model:$requested_model, canonical_model:$canonical_model,
          model_family:$model_family, selection_source:$selection_source,
          project_root:$project_root, plugin_root:$plugin_root, phase:$phase, role:$role,
          argv:$argv, environment_names:$environment_names,
          credential_names:$credential_names, tool_policy:$tool_policy,
          budgets:{available_input_tokens:$available_input_tokens,
                   output_reserve_tokens:$output_reserve_tokens,
                   overhead_tokens:$overhead_tokens, prompt_bytes:$prompt_bytes},
          deadline_epoch:$deadline_epoch, billing_mode:$billing_mode}'
}

octo_dispatch_plan_load_argv() {
    local plan="${1:-}" item
    OCTO_DISPATCH_PLAN_ARGV=()
    while IFS= read -r item; do
        OCTO_DISPATCH_PLAN_ARGV+=("$item")
    done < <(jq -er '.argv[]' <<< "$plan") || return 2
    [[ ${#OCTO_DISPATCH_PLAN_ARGV[@]} -gt 0 ]]
}

_octo_dispatch_plan_lock_is_stale() {
    local lock="${1:-}" pid="" timestamp="" now="" stale_secs="${OCTOPUS_DISPATCH_PLAN_LOCK_STALE_SECS:-30}"
    [[ -d "$lock" ]] || return 1
    [[ "$stale_secs" =~ ^[1-9][0-9]*$ ]] || stale_secs=30
    [[ -f "$lock/pid" ]] && IFS= read -r pid < "$lock/pid" || true
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        kill -0 "$pid" 2>/dev/null && return 1
        return 0
    fi
    [[ -f "$lock/ts" ]] && IFS= read -r timestamp < "$lock/ts" || true
    if [[ ! "$timestamp" =~ ^[0-9]+$ ]]; then
        timestamp="$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || printf '0')"
    fi
    now="$(date +%s 2>/dev/null || printf '0')"
    [[ "$timestamp" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ && "$now" -ge "$timestamp" ]] || return 1
    [[ $((now - timestamp)) -ge "$stale_secs" ]]
}

_octo_dispatch_plan_reclaim_lock() {
    local lock="${1:-}" stolen
    _octo_dispatch_plan_lock_is_stale "$lock" || return 1
    stolen="${lock}.stale.${BASHPID:-$$}"
    mv "$lock" "$stolen" 2>/dev/null || return 1
    if _octo_dispatch_plan_lock_is_stale "$stolen"; then
        rm -f "$stolen/pid" "$stolen/ts" 2>/dev/null || true
        rmdir "$stolen" 2>/dev/null || true
        return 0
    fi
    mv "$stolen" "$lock" 2>/dev/null || true
    return 1
}

octo_dispatch_plan_record() {
    local plan="${1:-}" destination="${2:-${RESULTS_DIR:-}/dispatch-plans.jsonl}"
    local lock attempts=0 record
    [[ -n "$destination" && "$destination" == /* ]] || return 2
    jq -e '.schema_version == 1' <<< "$plan" >/dev/null || return 2
    mkdir -p "$(dirname "$destination")" || return 2
    lock="${destination}.lock"
    while ! mkdir "$lock" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [[ $((attempts % 50)) -eq 0 ]]; then
            _octo_dispatch_plan_reclaim_lock "$lock" || true
        fi
        [[ "$attempts" -lt 200 ]] || return 75
        sleep 0.01
    done
    # A direct child's PPID identifies this subshell on Bash 3, where $$ still
    # identifies the top-level shell. Do not wrap this call in $(...).
    if ! /bin/sh -c 'printf "%s\n" "$PPID" > "$1"' _ "$lock/pid" 2>/dev/null ||
       ! date +%s > "$lock/ts" 2>/dev/null; then
        rm -f "$lock/pid" "$lock/ts" 2>/dev/null || true
        rmdir "$lock" 2>/dev/null || true
        return 2
    fi
    record="$(jq -cn --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson plan "$plan" '{event:"dispatch-plan", timestamp:$timestamp, plan:$plan}')" || {
        rm -f "$lock/pid" "$lock/ts" 2>/dev/null || true
        rmdir "$lock" 2>/dev/null || true
        return 2
    }
    (umask 077; printf '%s\n' "$record" >> "$destination")
    local rc=$?
    rm -f "$lock/pid" "$lock/ts" 2>/dev/null || true
    rmdir "$lock" 2>/dev/null || true
    return "$rc"
}
