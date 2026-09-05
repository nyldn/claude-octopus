#!/usr/bin/env bash
# Unified configurable fallback-chain helpers.
# Source-safe: defines functions only and resolves providers/models lazily.

_octo_fallback_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octo_provider_canonical >/dev/null 2>&1; then
    source "${_octo_fallback_lib_dir}/provider-registry.sh" 2>/dev/null || true
fi
if ! declare -f octo_model_canonical_id >/dev/null 2>&1; then
    source "${_octo_fallback_lib_dir}/models.sh" 2>/dev/null || true
fi
unset _octo_fallback_lib_dir

_octo_fallback_config_file() {
    if declare -f _octopus_profile_config_file >/dev/null 2>&1; then
        _octopus_profile_config_file
    else
        printf '%s\n' "${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
    fi
}

octo_fallback_builtin_chain_json() {
    local name="${1:-default}"
    case "$name" in
        default)
            printf '%s\n' '[{"role":"code-reviewer"},{"role":"implementer-heavy"},{"role":"architect"}]'
            ;;
        *)
            printf '%s\n' '[]'
            ;;
    esac
}

octo_fallback_chain_json() {
    local name="${1:-default}" cfg selection="" configured=""
    cfg="$(_octo_fallback_config_file)"

    if [[ -f "$cfg" ]]; then
        selection="$(jq -ce --arg name "$name" '
            if type != "object" then error("providers config must be an object")
            elif (has("routing") and .routing != null and (.routing | type) != "object") then error("routing must be an object")
            elif (.routing != null and (.routing | has("roles")) and .routing.roles != null and (.routing.roles | type) != "object") then error("routing.roles must be an object")
            elif (.routing != null and (.routing | has("phases")) and .routing.phases != null and (.routing.phases | type) != "object") then error("routing.phases must be an object")
            else (.routing.fallbackChains? // null) as $chains
            | if $chains == null then {found:false}
              elif ($chains | type) != "object" then error("routing.fallbackChains must be an object")
              elif ($chains | has($name)) then {found:true,value:$chains[$name]}
              elif ($name != "default" and ($chains | has("default"))) then {found:true,value:$chains.default}
              else {found:false} end end
        ' "$cfg" 2>/dev/null)" || return 2

        if [[ "$(jq -r '.found' <<<"$selection")" == "true" ]]; then
            configured="$(jq -ce '
                .value as $chain
                | if ($chain | type) == "array" then $chain
                  elif (($chain | type) == "object" and ($chain | has("attempts")) and ($chain.attempts | type) == "array") then $chain.attempts
                  else error("fallback chain must be an array or an object with an attempts array") end
            ' <<<"$selection" 2>/dev/null)" || return 2
            printf '%s\n' "$configured"
            return 0
        fi
    fi

    octo_fallback_builtin_chain_json "$name"
}

_octo_fallback_ensure_role_resolver() {
    declare -f get_role_agent >/dev/null 2>&1 && return 0
    local lib_dir nounset_was_on="false"
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [[ "$-" == *u* ]] && nounset_was_on="true" && set +u
    source "${lib_dir}/agent-utils.sh" 2>/dev/null || true
    [[ "$nounset_was_on" == "true" ]] && set -u
    declare -f get_role_agent >/dev/null 2>&1
}

_octo_fallback_bare_route_provider() {
    local requested="${1:-}" normalized="" id aliases command org caps alias old_ifs
    declare -f octo_provider_normalize >/dev/null 2>&1 || return 1
    normalized="$(octo_provider_normalize "$requested")"
    [[ -n "$normalized" ]] || return 1

    while IFS='|' read -r id aliases command org caps; do
        [[ "$normalized" == "$id" ]] && { printf '%s\n' "$id"; return 0; }
        old_ifs="$IFS"
        IFS=','
        for alias in $aliases; do
            IFS="$old_ifs"
            alias="${alias%\*}"
            if [[ -n "$alias" && "$normalized" == "$alias" ]]; then
                printf '%s\n' "$id"
                return 0
            fi
            IFS=','
        done
        IFS="$old_ifs"
    done <<EOF
$(octo_provider_registry_rows)
EOF

    # Keep the legacy AGY research seat aligned with model-resolver's bare-route
    # classifier. It predates registry-backed canonical provider prefixes.
    if [[ "$normalized" == "agy-research" ]]; then
        printf '%s\n' "agy"
        return 0
    fi
    return 1
}

octo_fallback_role_agent_spec() {
    local role="$1" phase="${2:-}" provider="" model="" routed_provider=""
    local route="null" route_type="null" route_value="" route_provider="" route_model=""

    case "$role" in
        architect|researcher|reviewer|code-reviewer|security-reviewer|implementer|implementer-heavy|synthesizer|strategist) ;;
        *) return 1 ;;
    esac
    _octo_fallback_ensure_role_resolver || return 1
    routed_provider="$(get_role_agent "$role" 2>/dev/null || true)"
    [[ -n "$routed_provider" ]] || return 1

    provider="$routed_provider"
    if declare -f _octopus_profile_route_json >/dev/null 2>&1; then
        route="$(_octopus_profile_route_json "$phase" "$role" 2>/dev/null)" || return 2
        route_type="$(jq -r 'type' <<<"$route" 2>/dev/null || printf '%s\n' null)"
    fi

    case "$route_type" in
        object)
            jq -e '
                ((has("provider") | not) or (.provider | type) == "string") and
                ((has("model") | not) or (.model | type) == "string") and
                ((.provider // "") != "" or (.model // "") != "")
            ' <<<"$route" >/dev/null 2>&1 || return 1
            route_provider="$(jq -r '.provider // empty' <<<"$route")"
            route_model="$(jq -r '.model // empty' <<<"$route")"
            local route_has_provider=false resolution_provider=""
            [[ -n "$route_provider" ]] && { provider="$route_provider"; route_has_provider=true; }
            if [[ -n "$route_model" ]]; then
                declare -f resolve_octopus_model >/dev/null 2>&1 || return 1
                resolution_provider="$(octo_provider_canonical "$provider" 2>/dev/null)" || return 1
                model="$(resolve_octopus_model "$resolution_provider" "$provider" "$phase" "$role")" || return 1
                [[ "$route_has_provider" == true ]] && provider="$resolution_provider"
            fi
            ;;
        string)
            route_value="$(jq -r '.' <<<"$route" 2>/dev/null || true)"
            if [[ "$route_value" == *:* ]]; then
                route_provider="${route_value%%:*}"
                route_model="${route_value#*:}"
                [[ -n "$route_provider" && -n "$route_model" ]] || return 1
                declare -f resolve_octopus_model >/dev/null 2>&1 || return 1
                model="$(resolve_octopus_model "$route_provider" "$route_model" "" "")" || return 1
                provider="$route_provider"
            elif [[ -n "$route_value" ]]; then
                if route_provider="$(_octo_fallback_bare_route_provider "$route_value" 2>/dev/null)"; then
                    provider="$route_provider"
                else
                    declare -f resolve_octopus_model >/dev/null 2>&1 || return 1
                    route_provider="$(octo_provider_canonical "$provider" 2>/dev/null)" || return 1
                    model="$(resolve_octopus_model "$route_provider" "$provider" "$phase" "$role")" || return 1
                fi
            fi
            ;;
        null) ;;
        *) return 1 ;;
    esac

    octo_fallback_canonical_agent_spec "${provider}${model:+:$model}"
}

octo_fallback_canonical_agent_spec() {
    local spec="${1:-}" executor="" provider="" model="" canonical_executor=""
    executor="${spec%%:*}"
    [[ -n "$executor" ]] || return 1
    declare -f octo_provider_canonical >/dev/null 2>&1 || return 1
    provider="$(octo_provider_canonical "$executor" 2>/dev/null)" || return 1

    canonical_executor="$executor"
    case "$executor" in
        "$provider"|"$provider"-*) ;;
        *) canonical_executor="$provider" ;;
    esac

    if [[ "$spec" == *:* ]]; then
        model="${spec#*:}"
        [[ -n "$model" ]] || return 1
        declare -f validate_model_name_for_provider >/dev/null 2>&1 || return 1
        validate_model_name_for_provider "$provider" "$model" >/dev/null 2>&1 || return 1
        printf '%s:%s\n' "$canonical_executor" "$model"
    else
        printf '%s\n' "$canonical_executor"
    fi
}

octo_fallback_spec_matches_invocation_pin() {
    local spec="${1:-}" provider="" model="" env_var="" pinned=""
    [[ "$spec" == *:* ]] || return 1
    provider="$(_octo_fallback_provider_identity "$spec")"
    model="${spec#*:}"

    if declare -f octo_provider_model_env >/dev/null 2>&1; then
        env_var="$(octo_provider_model_env "$provider" 2>/dev/null || true)"
        [[ -n "$env_var" ]] && pinned="${!env_var:-}"
    fi
    if [[ -z "$pinned" && "$provider" == "claude" ]]; then
        pinned="${CLAUDE_MODEL:-}"
    fi
    [[ -n "$pinned" ]] || return 1
    [[ "$(octo_model_canonical_id "$pinned")" == "$(octo_model_canonical_id "$model")" ]]
}

octo_fallback_admit_automatic_spec() {
    local spec="${1:-}" escalation_grant="${2:-}" provider="" model="" canonical="" granted=""
    [[ "$spec" == *:* ]] || return 0
    provider="$(_octo_fallback_provider_identity "$spec")"
    model="${spec#*:}"
    canonical="$(octo_model_canonical_id "$model")" || return 1

    if octo_model_automatic_target_allowed "$model" "$provider"; then
        return 0
    fi
    # A provider model environment pin is explicit input to this invocation,
    # not persisted fallback policy. Preserve that source before consulting a
    # separate escalation grant.
    octo_fallback_spec_matches_invocation_pin "$spec" && return 0
    [[ -n "$escalation_grant" ]] || return 1
    granted="$(octo_model_canonical_id "$escalation_grant")" || return 1
    [[ "$granted" == "$canonical" ]]
}

octo_fallback_candidate_agent_spec() {
    local candidate="$1" phase="${2:-}" escalation_grant="${3:-}" type role provider model agent spec=""
    type="$(jq -r 'type' <<<"$candidate" 2>/dev/null || true)"

    if [[ "$type" == "string" ]]; then
        role="$(jq -r '.' <<<"$candidate")"
        [[ -n "$role" ]] || return 1
        spec="$(octo_fallback_role_agent_spec "$role" "$phase")" || return 1
        octo_fallback_admit_automatic_spec "$spec" "$escalation_grant" || return 1
        printf '%s\n' "$spec"
        return 0
    fi
    [[ "$type" == "object" ]] || return 1

    jq -e '
        (([has("role"),has("agent"),has("provider")] | map(select(.)) | length) == 1) and
        ((keys - ["agent","model","provider","role"]) | length == 0) and
        ((has("role") | not) or ((.role | type) == "string" and .role != "" and (has("agent") | not) and (has("provider") | not) and (has("model") | not))) and
        ((has("agent") | not) or ((.agent | type) == "string" and .agent != "" and (has("model") | not))) and
        ((has("provider") | not) or ((.provider | type) == "string" and .provider != "" and ((has("model") | not) or ((.model | type) == "string" and .model != ""))))
    ' <<<"$candidate" >/dev/null 2>&1 || return 1

    role="$(jq -r '.role // empty' <<<"$candidate")"
    if [[ -n "$role" ]]; then
        spec="$(octo_fallback_role_agent_spec "$role" "$phase")" || return 1
        octo_fallback_admit_automatic_spec "$spec" "$escalation_grant" || return 1
        printf '%s\n' "$spec"
        return 0
    fi

    agent="$(jq -r '.agent // empty' <<<"$candidate")"
    if [[ -n "$agent" ]]; then
        spec="$(octo_fallback_canonical_agent_spec "$agent")" || return 1
        octo_fallback_admit_automatic_spec "$spec" "$escalation_grant" || return 1
        printf '%s\n' "$spec"
        return 0
    fi

    provider="$(jq -r '.provider // empty' <<<"$candidate")"
    model="$(jq -r '.model // empty' <<<"$candidate")"
    [[ -n "$provider" ]] || return 1
    spec="$(octo_fallback_canonical_agent_spec "${provider}${model:+:$model}")" || return 1
    octo_fallback_admit_automatic_spec "$spec" "$escalation_grant" || return 1
    printf '%s\n' "$spec"
}

octo_fallback_chain_agent_specs() {
    local name="${1:-default}" phase="${2:-}" escalation_grant="${3:-}" chain candidates candidate spec specs="" seen="|"
    chain="$(octo_fallback_chain_json "$name")" || return $?
    candidates="$(jq -ce '.[]' <<<"$chain" 2>/dev/null)" || {
        [[ "$chain" == "[]" ]] && return 0
        return 2
    }
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        spec="$(octo_fallback_candidate_agent_spec "$candidate" "$phase" "$escalation_grant" 2>/dev/null)" || return 2
        [[ -n "$spec" ]] || return 2
        [[ "$seen" == *"|$spec|"* ]] && continue
        seen+="$spec|"
        specs+="${spec}"$'\n'
    done <<<"$candidates"
    printf '%s' "$specs"
}

octo_fallback_agent_available() {
    local spec="${1:-}" executor="" provider="" model=""
    executor="${spec%%:*}"
    [[ -n "$executor" ]] || return 1

    if [[ "$spec" == *:* ]]; then
        model="${spec#*:}"
        [[ -n "$model" ]] || return 1
        declare -f octo_agent_spec_provider >/dev/null 2>&1 || return 1
        provider="$(octo_agent_spec_provider "$spec" 2>/dev/null)" || return 1
        [[ -n "$provider" ]] || return 1
        declare -f validate_model_name_for_provider >/dev/null 2>&1 || return 1
        validate_model_name_for_provider "$provider" "$model" >/dev/null 2>&1 || return 1
    fi

    if declare -f is_agent_available_v2 >/dev/null 2>&1; then
        is_agent_available_v2 "$executor"
        return $?
    fi
    # Fallback candidates must fail closed. The legacy is_agent_available()
    # assumes unknown providers are available, which can defer an invalid seat
    # until dispatch. Callers that use configurable fallback chains must provide
    # the v2 availability contract from model-resolver.sh.
    return 1
}

_octo_fallback_provider_identity() {
    local spec="${1:-}" executor=""
    executor="${spec%%:*}"
    if declare -f octo_agent_spec_provider >/dev/null 2>&1; then
        octo_agent_spec_provider "$spec" 2>/dev/null && return 0
    fi
    case "$executor" in
        codex|codex-*) echo codex ;;
        claude|claude-*) echo claude ;;
        agy|agy-*|antigravity|gemini|gemini-*) echo agy ;;
        commandcode|commandcode-*) echo commandcode ;;
        openrouter|openrouter-*) echo openrouter ;;
        *) echo "$executor" ;;
    esac
}

octo_fallback_first_available() {
    local name="${1:-default}" preferred="${2:-}" phase="${3:-}" escalation_grant="${4:-}" spec executor specs
    local preferred_provider="" candidate_provider=""
    preferred_provider="$(_octo_fallback_provider_identity "$preferred")"
    specs="$(octo_fallback_chain_agent_specs "$name" "$phase" "$escalation_grant")" || return $?
    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        executor="${spec%%:*}"
        candidate_provider="$(_octo_fallback_provider_identity "$spec")"
        [[ -n "$preferred_provider" && "$candidate_provider" == "$preferred_provider" ]] && continue
        if octo_fallback_agent_available "$spec"; then
            printf '%s\n' "$spec"
            return 0
        fi
    done <<<"$specs"
    return 1
}

octo_fallback_output_usable() {
    local output="${1:-}" validator="${2:-}"
    [[ -n "${output//[[:space:]]/}" ]] || return 1
    if [[ -n "$validator" ]]; then
        declare -F "$validator" >/dev/null 2>&1 || return 2
        "$validator" "$output" >/dev/null
        return $?
    fi
    return 0
}

run_agent_sync_fallback_chain() {
    local primary_agent="$1" prompt="$2" timeout_secs="${3:-120}" semantic_role="${4:-}" phase="${5:-}"
    local validator="${6:-}" chain_name="${7:-default}" preferred_fallback="${8:-}" escalation_grant="${9:-}"
    local spec raw_spec output="" rc=0 reason="" candidates="" fallback_specs="" seen="|"

    fallback_specs="$(octo_fallback_chain_agent_specs "$chain_name" "$phase" "$escalation_grant")" || return $?
    if [[ -n "$primary_agent" ]]; then
        spec="$(octo_fallback_canonical_agent_spec "$primary_agent")" || return 2
        seen+="$spec|"
        candidates+="${spec}"$'\n'
    fi
    if [[ -n "$preferred_fallback" ]]; then
        spec="$(octo_fallback_canonical_agent_spec "$preferred_fallback")" || return 2
        octo_fallback_admit_automatic_spec "$spec" "$escalation_grant" || return 2
        if [[ "$seen" != *"|$spec|"* ]]; then
            seen+="$spec|"
            candidates+="${spec}"$'\n'
        fi
    fi
    while IFS= read -r raw_spec; do
        [[ -n "$raw_spec" ]] || continue
        spec="$(octo_fallback_canonical_agent_spec "$raw_spec")" || return 2
        [[ "$seen" == *"|$spec|"* ]] && continue
        seen+="$spec|"
        candidates+="${spec}"$'\n'
    done <<<"$fallback_specs"

    while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        output=""
        rc=0
        if output=$(run_agent_sync "$spec" "$prompt" "$timeout_secs" "$semantic_role" "$phase"); then
            if octo_fallback_output_usable "$output" "$validator"; then
                printf '%s\n' "$output"
                return 0
            fi
            reason="semantic-invalid"
        else
            rc=$?
            reason="process-error:$rc"
        fi
        if declare -f log >/dev/null 2>&1; then
            log WARN "Fallback chain '$chain_name': $spec failed ($reason); trying next candidate"
        fi
    done <<<"$candidates"

    if declare -f log >/dev/null 2>&1; then
        log ERROR "Fallback chain '$chain_name' exhausted without a usable result"
    fi
    return 1
}
