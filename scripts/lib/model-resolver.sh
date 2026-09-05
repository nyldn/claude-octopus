#!/usr/bin/env bash
_profile_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octopus_resolve_reasoning_level >/dev/null 2>&1; then
    source "${_profile_lib_dir}/execution-profile.sh" 2>/dev/null || true
fi
source "${_profile_lib_dir}/fallback-chain.sh" 2>/dev/null || true
# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION v3.0: Unified Model Resolver (v8.50.0)
# Consolidated logic for provider, phase, and role-based model selection.
# Precedence: Env Var > Session Override > Phase/Role Routing > Capability > Tier > Defaults
# Extracted from orchestrate.sh — v9.7.5
# ═══════════════════════════════════════════════════════════════════════════════

_model_resolver_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_model_resolver_load_error() {
    local message="$1"
    if declare -f log >/dev/null 2>&1; then
        log ERROR "$message" || printf 'model-resolver: %s\n' "$message" >&2
    else
        printf 'model-resolver: %s\n' "$message" >&2
    fi
}
source "${_model_resolver_lib_dir}/provider-registry.sh" || { _model_resolver_load_error "failed to load provider-registry.sh"; return 1 2>/dev/null || exit 1; }
source "${_model_resolver_lib_dir}/kimi-model-name.sh" || { _model_resolver_load_error "failed to load kimi-model-name.sh"; return 1 2>/dev/null || exit 1; }
if ! declare -f octo_model_cache_file >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/model-cache-path.sh" 2>/dev/null || true
fi
if ! declare -f get_model_catalog >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/models.sh" || { _model_resolver_load_error "failed to load models.sh"; return 1 2>/dev/null || exit 1; }
fi
if ! declare -f _is_cursor_agent_binary >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/cursor-agent.sh" 2>/dev/null || true
fi
if ! declare -f fable5_maybe_reroute >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/fable5.sh" 2>/dev/null || true
fi
if ! declare -f _octo_assignment_has_nonempty_value >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/auth.sh" 2>/dev/null || true
fi
if ! declare -f _octo_run_bare_probe_with_timeout >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/providers.sh" 2>/dev/null || true
fi
if ! declare -f copilot_is_available >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/copilot.sh" 2>/dev/null || true
fi
if ! declare -f is_claude_agent_type >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/routing.sh" 2>/dev/null || true
source "${_model_resolver_lib_dir}/openai-compatible.sh" 2>/dev/null || true
fi
if ! declare -f is_claude_agent_type >/dev/null 2>&1; then
    is_claude_agent_type() {
        case "${1:-}" in
            claude|claude-*) return 0 ;;
            *) return 1 ;;
        esac
    }
fi

# Current-model pickers. Explicit user pins/configuration are resolved before
# these fallbacks, and OCTOPUS_OPUS_MODEL remains the final Opus-specific pin.
# Opus 5 requires Claude Code v2.1.219+; Sonnet 5 requires v2.1.197+.
# Claude Fable 5.1 (Mythos-class, $10/$50 MTok, 1M ctx) remains opt-in only:
# pin OCTOPUS_OPUS_MODEL=claude-fable-5-1. Never auto-selected — 2x Opus 5 cost,
# and Anthropic retains prompts/outputs up to 30 days for safety classifiers.
opus_default_model() {
    if [[ -n "${OCTOPUS_OPUS_MODEL:-}" ]]; then
        echo "$OCTOPUS_OPUS_MODEL"
        return 0
    fi
    if [[ "${SUPPORTS_OPUS_5:-false}" == "true" ]]; then
        echo "claude-opus-5"
    elif [[ "${SUPPORTS_OPUS_4_8:-false}" == "true" ]]; then
        echo "claude-opus-4.8"
    elif [[ "${SUPPORTS_OPUS_4_7:-false}" == "true" ]]; then
        echo "claude-opus-4.7"
    else
        echo "claude-opus-4.6"
    fi
}

sonnet_default_model() {
    if [[ "${SUPPORTS_SONNET_5:-false}" == "true" ]]; then
        echo "claude-sonnet-5"
    else
        echo "claude-sonnet-4.6"
    fi
}

codex_default_model() {
    echo "gpt-5.6-sol"
}

_octo_automatic_model_allowed() {
    octo_model_automatic_target_allowed "${1:-}"
}

# Tier targets may use provider:model syntax. Strip a known same-provider
# prefix before dispatch, reject cross-provider targets, and leave model-native
# colons such as Ollama tags untouched.
_octo_tier_target_model() {
    local provider="${1:-}" target="${2:-}" target_provider=""
    if [[ "$target" == *:* ]]; then
        target_provider="$(_octo_canonical_known_provider_name "${target%%:*}" 2>/dev/null || true)"
        if [[ -n "$target_provider" ]]; then
            [[ "$target_provider" == "$provider" ]] || return 1
            target="${target#*:}"
        fi
    fi
    printf '%s\n' "$target"
}

# Select only from the live local Ollama inventory. A hardcoded fallback can
# make `ollama run` pull many gigabytes, so an empty/unreachable inventory must
# fail closed and ask the user for an explicit installed model.
ollama_default_model() {
    local tags="" model=""
    if ! tags="$(curl -sf --max-time 3 http://localhost:11434/api/tags 2>/dev/null)" || [[ -z "$tags" ]]; then
        log ERROR "Ollama is unavailable; start it and set OCTOPUS_OLLAMA_MODEL to an installed model"
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        model="$(printf '%s' "$tags" | jq -r '.models[0].name // empty' 2>/dev/null)"
    elif command -v python3 >/dev/null 2>&1; then
        model="$(printf '%s' "$tags" | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("models") or [{}])[0].get("name", ""))' 2>/dev/null)"
    else
        model="$(printf '%s' "$tags" | sed -n 's/.*"models"[[:space:]]*:[[:space:]]*\[[[:space:]]*{[^}]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)"[^}]*}.*/\1/p' | head -1)"
    fi

    if [[ -z "$model" ]]; then
        log ERROR "No local Ollama models are installed; install one or set OCTOPUS_OLLAMA_MODEL to an installed model"
        return 1
    fi
    printf '%s\n' "$model"
}

# Validate Antigravity CLI model labels against the live CLI catalog.
#
# Antigravity's model selector is service-owned and changes outside Octopus
# releases. Real labels include spaces and parentheses (for example,
# "Gemini 3.5 Flash (Low)"), so the generic shell-token validator is too
# strict for explicit agy model pins. Validate agy pins by exact membership in
# `agy models` instead, while keeping the generic validator for all other
# providers.
validate_agy_model_name() {
    local model="$1"

    [[ -z "$model" ]] && return 1
    [[ "$model" == *$'\n'* || "$model" == *$'\r'* ]] && return 1
    case "$model" in
        *\\*) return 1 ;;
    esac

    case "$model" in
        default|agy/default)
            return 0
            ;;
    esac

    # "Cannot validate" (catalog unreachable) is NOT the same as "invalid" (a
    # model definitively absent from a reachable catalog). Treating them alike
    # turned a transient/sandboxed `agy models` failure into a spawn-time abort:
    # OCTOPUS_AGY_MODEL resolution returned 1 and the whole council crashed even
    # when the pin was perfectly valid. Fail OPEN when the catalog can't be read —
    # a genuinely bad pin is still caught by agy itself at dispatch, with a clear
    # error — and keep the strict fail-closed path behind an explicit opt-in.
    local strict="${OCTOPUS_AGY_MODEL_STRICT:-0}"

    if ! command -v agy >/dev/null 2>&1; then
        if [[ "$strict" == "1" ]]; then
            log ERROR "Cannot validate OCTOPUS_AGY_MODEL because agy CLI is not installed (OCTOPUS_AGY_MODEL_STRICT=1)"
            return 1
        fi
        log WARN "Skipping OCTOPUS_AGY_MODEL validation: agy CLI not installed; trusting pin '$model' (set OCTOPUS_AGY_MODEL_STRICT=1 to require validation)"
        return 0
    fi

    local available_models=""
    local catalog_timeout catalog_term_timeout catalog_kill_grace
    catalog_timeout="$(_octo_bare_probe_timeout "${OCTOPUS_AGY_MODELS_TIMEOUT:-5}")"
    catalog_term_timeout="$catalog_timeout"
    catalog_kill_grace=0
    if [[ "$catalog_timeout" -gt 2 ]]; then
        catalog_kill_grace=2
        catalog_term_timeout=$((catalog_timeout - catalog_kill_grace))
    fi
    if ! available_models="$(_octo_run_bare_probe_with_timeout \
        "$catalog_timeout" "$catalog_term_timeout" "$catalog_kill_grace" \
        agy models </dev/null 2>/dev/null)" || [[ -z "$available_models" ]]; then
        if [[ "$strict" == "1" ]]; then
            log ERROR "Cannot validate OCTOPUS_AGY_MODEL because 'agy models' returned no models (OCTOPUS_AGY_MODEL_STRICT=1)"
            return 1
        fi
        log WARN "Skipping OCTOPUS_AGY_MODEL validation: 'agy models' returned no catalog (offline or sandboxed); trusting pin '$model' (set OCTOPUS_AGY_MODEL_STRICT=1 to require validation)"
        return 0
    fi

    local line="" catalog_id="" catalog_label=""
    while IFS= read -r line; do
        line="${line%$'\r'}"
        catalog_id="$line"
        catalog_label="$line"
        if [[ "$line" == *$'\t'* ]]; then
            catalog_id="${line%%$'\t'*}"
            catalog_label="${line#*$'\t'}"
            while [[ "$catalog_label" == $'\t'* ]]; do
                catalog_label="${catalog_label#$'\t'}"
            done
        fi
        if [[ "$catalog_id" == "$model" || "$catalog_label" == "$model" ]]; then
            return 0
        fi
    done <<< "$available_models"

    log ERROR "Invalid OCTOPUS_AGY_MODEL: '$model'"
    printf 'Available agy models:\n%s\n' "$available_models" >&2
    return 1
}

# Kimi Code aliases are user-defined TOML keys and may contain whitespace.
# They still cross an Octopus command boundary, so retain the generic model
# validator's metacharacter, line-break, backslash, and absolute-path guards.
validate_kimi_model_name() {
    octopus_kimi_model_name_is_safe "$1"
}

validate_model_name_for_provider() {
    local provider="$1"
    local model="$2"

    case "$provider" in
        agy|agy-research|antigravity)
            validate_agy_model_name "$model"
            ;;
        kimi)
            validate_kimi_model_name "$model"
            ;;
        *)
            validate_model_name "$model"
            ;;
    esac
}

_octo_canonical_known_provider_name() {
    local requested normalized id aliases command org caps alias alias_base
    local -a aliases_list
    requested="${1:-}"
    normalized="$(octo_provider_normalize "$requested")"
    [[ -n "$normalized" ]] || return 1

    # Routing values are ambiguous: a bare string can be either a provider or
    # a model. Accept canonical IDs and exact aliases (plus the exact base of a
    # wildcard alias), but do not let wildcard aliases such as gpt* classify a
    # concrete model like gpt-5.5 as a provider route.
    while IFS='|' read -r id aliases command org caps; do
        if [[ "$normalized" == "$id" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
        aliases_list=()
        if [[ -n "$aliases" ]]; then
            IFS=',' read -r -a aliases_list <<< "$aliases"
            for alias in "${aliases_list[@]}"; do
                [[ -n "$alias" ]] || continue
                case "$alias" in
                    *'*')
                        alias_base="${alias%\*}"
                        [[ "$normalized" == "$alias_base" ]] || continue
                        ;;
                    *)
                        [[ "$normalized" == "$alias" ]] || continue
                        ;;
                esac
                printf '%s\n' "$id"
                return 0
            done
        fi
    done <<EOF
$(octo_provider_registry_rows)
EOF

    # Preserve the legacy provider variant accepted before registry-backed
    # classification was introduced.
    if [[ "$normalized" == "agy-research" ]]; then
        printf '%s\n' "agy"
        return 0
    fi
    return 1
}

_octo_is_known_provider_name() {
    _octo_canonical_known_provider_name "${1:-}" >/dev/null 2>&1
}

_octo_route_value_model_family() {
    local model="${1:-}" target_provider="${2:-}" catalog_provider=""
    if [[ "$model" == "default" && -n "$target_provider" ]]; then
        octo_provider_org "$target_provider" 2>/dev/null || printf '%s\n' unknown
        return 0
    fi
    if is_known_model "$model"; then
        catalog_provider="$(get_model_capability "$model" provider 2>/dev/null || true)"
        if [[ -n "$catalog_provider" && "$catalog_provider" != "unknown" ]]; then
            octo_provider_org "$catalog_provider" 2>/dev/null || printf '%s\n' unknown
            return 0
        fi
    fi
    case "${1:-}" in
        claude-*|anthropic/*) printf '%s\n' anthropic ;;
        gpt-*|o[134]-*|codex*|openai/*) printf '%s\n' openai ;;
        gemini-*|agy-*|google/*) printf '%s\n' google ;;
        qwen*|alibaba/*) printf '%s\n' alibaba ;;
        grok-*|xai/*|x-ai/*) printf '%s\n' xai ;;
        mistral-*|mistral/*|mistralai/*) printf '%s\n' mistral ;;
        sonar*|perplexity/*) printf '%s\n' perplexity ;;
        *) printf '%s\n' unknown ;;
    esac
}

_octo_effective_cost_mode() {
    local config_file="${1:-}"
    local mode="${OCTOPUS_COST_MODE:-}"

    if [[ -z "$mode" && -f "$config_file" ]] && command -v jq >/dev/null 2>&1; then
        mode="$(jq -r '.cost_mode // "standard"' "$config_file" 2>/dev/null || true)"
    fi
    mode="${mode:-standard}"

    case "$mode" in
        budget|standard|premium)
            printf '%s\n' "$mode"
            ;;
        *)
            if declare -f log >/dev/null 2>&1; then
                log WARN "Invalid cost mode '$mode'; using standard"
            fi
            printf '%s\n' "standard"
            ;;
    esac
}

_octo_eval_model_for_class() {
    local provider="${1:-}" task_class="${2:-}"
    case "$provider:$task_class" in
        codex:mechanical) printf '%s\n' "gpt-5.6-luna" ;;
        codex:balanced) printf '%s\n' "gpt-5.6-terra" ;;
        codex:premium|codex:review|codex:security) printf '%s\n' "gpt-5.6-sol" ;;
        claude:mechanical) printf '%s\n' "claude-haiku-4.5" ;;
        claude:balanced) printf '%s\n' "claude-sonnet-5" ;;
        claude:premium|claude:review|claude:security) printf '%s\n' "claude-opus-5" ;;
        *) return 1 ;;
    esac
}

# resolve_octopus_model <provider> <agent_type> <phase> <role>
resolve_octopus_model() {
    local provider="$1"
    local agent_type="$2"
    local phase="${3:-}"
    local role="${4:-}"
    local config_file="${OCTOPUS_PROVIDERS_CONFIG:-${HOME}/.claude-octopus/config/providers.json}"
    local resolved_model=""
    local cost_mode routing_policy
    cost_mode="$(_octo_effective_cost_mode "$config_file")"
    if declare -f octo_routing_policy >/dev/null 2>&1; then
        routing_policy="$(octo_routing_policy 2>/dev/null || printf '%s' off)"
    else
        routing_policy="${OCTOPUS_ROUTING_POLICY:-off}"
    fi

    # Env overrides must bypass caches. A prior default resolution can be cached
    # for the same provider/agent/phase tuple, but explicit user overrides are
    # session state and take precedence over any cached value.
    local canonical_provider="$provider"
    case "$canonical_provider" in
        antigravity|agy-research|gemini|gemini-*) canonical_provider="agy" ;;
    esac
    provider="$canonical_provider"
    local env_var
    if declare -f octo_provider_model_env >/dev/null 2>&1; then
        env_var="$(octo_provider_model_env "$canonical_provider")" || return 1
    else
        env_var="OCTOPUS_$(echo "$canonical_provider" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_MODEL"
    fi
    if [[ -n "${!env_var:-}" ]]; then
        if ! validate_model_name_for_provider "$canonical_provider" "${!env_var}"; then
            log ERROR "Invalid model name in $env_var"
            return 1
        fi
        # v9.51: Fable 5 security reroute applies to explicit env pins too.
        if declare -f fable5_maybe_reroute >/dev/null 2>&1; then
            fable5_maybe_reroute "${!env_var}" "$role" "$agent_type" "$phase"
        else
            echo "${!env_var}"
        fi
        return 0
    fi

    # 0. Session Cache (v8.53.0)
    # Uses a process-local memory cache + optional file-based cache for cross-process speed
    local cache_key
    # v8.49.0: Field-delimited cache key prevents collisions
    # (e.g., provider="codex" + type="spark" must differ from type="codex-spark")
    local safe_p="${canonical_provider//[^a-zA-Z0-9]/_}"
    local safe_a="${agent_type//[^a-zA-Z0-9]/_}"
    local safe_ph="${phase//[^a-zA-Z0-9]/_}"
    local safe_r="${role//[^a-zA-Z0-9]/_}"
    local safe_cm="${cost_mode//[^a-zA-Z0-9]/_}"
    local safe_rp="$routing_policy"
    local safe_tc="${OCTOPUS_TASK_CLASS:-none}"
    safe_rp="${safe_rp//[^a-zA-Z0-9]/_}"
    safe_tc="${safe_tc//[^a-zA-Z0-9]/_}"
    local safe_cfg="no_config"
    if [[ -f "$config_file" ]]; then
        safe_cfg="$(cksum < "$config_file" 2>/dev/null | awk '{print $1 "_" $2}')"
        safe_cfg="${safe_cfg//[^a-zA-Z0-9_]/_}"
    fi
    cache_key="MC_${safe_p}_A_${safe_a}_P_${safe_ph}_R_${safe_r}_M_${safe_cm}_RP_${safe_rp}_TC_${safe_tc}_C_${safe_cfg}"
    local cached_val
    eval "cached_val=\"\${_OCTO_MODEL_CACHE_${cache_key}:-}\""
    if [[ -n "$cached_val" ]]; then
        if validate_model_name_for_provider "$canonical_provider" "$cached_val" &&
           _octo_automatic_model_allowed "$cached_val"; then
            echo "$cached_val"
            return 0
        fi
        log WARN "Rejected invalid or explicit-only model in memory cache for $provider/$agent_type"
        eval "unset _OCTO_MODEL_CACHE_${cache_key}"
        cached_val=""
    fi

    # Persistent File Cache (optional, for parallel execution speed).
    # Path comes from lib/model-cache-path.sh so writers and invalidators agree.
    local persistent_cache=""
    persistent_cache="$(octo_model_cache_file 2>/dev/null)" || persistent_cache=""
    # v8.49.0: Invalidate cache if config file changed since cache was written
    if [[ -n "$persistent_cache" && -f "$persistent_cache" && -f "$config_file" && "$config_file" -nt "$persistent_cache" ]]; then
        rm -f "$persistent_cache"
    fi
    if [[ -n "$persistent_cache" && -f "$persistent_cache" ]] && command -v jq &>/dev/null; then
        cached_val=$(jq -r ".\"$cache_key\" // empty" "$persistent_cache" 2>/dev/null)
        if [[ -n "$cached_val" && "$cached_val" != "null" ]]; then
            # Reject invalid cached model names instead of mutating them into a
            # different model string before eval.
            if validate_model_name_for_provider "$canonical_provider" "$cached_val" &&
               _octo_automatic_model_allowed "$cached_val"; then
                eval "_OCTO_MODEL_CACHE_${cache_key}=\"\$cached_val\""
                echo "$cached_val"
                return 0
            fi
            rm -f "$persistent_cache" 2>/dev/null || true
            cached_val=""
        fi
    fi

    # v8.49.0: Resolution trace for debugging model selection
    local _trace="${OCTOPUS_TRACE_MODELS:-}"
    [[ -n "$_trace" ]] && echo "[model-trace] Resolving: provider=$provider type=$agent_type phase=${phase:-<none>} role=${role:-<none>}" >&2

    # 1. Force/Session Overrides (Env vars)
    if [[ -n "${!env_var:-}" ]]; then
        resolved_model="${!env_var}"
        [[ -n "$_trace" ]] && echo "[model-trace] Tier 1 (env $env_var): ${!env_var} ← SELECTED" >&2
    elif [[ -n "$_trace" ]]; then
        echo "[model-trace] Tier 1 (env $env_var): —" >&2
    fi

    # v8.41.0 Priority 0.5: Check native CC model settings
    if [[ -z "$resolved_model" && "$provider" == "claude" && -n "${CLAUDE_MODEL:-}" ]]; then
        resolved_model="${CLAUDE_MODEL}"
        [[ -n "$_trace" ]] && echo "[model-trace] Tier 0.5 (CC native CLAUDE_MODEL): $CLAUDE_MODEL ← SELECTED" >&2
    fi

    # Config file lookups
    local config_lookups_applied=false
    if [[ -z "$resolved_model" && -f "$config_file" ]] && command -v jq &> /dev/null; then
        config_lookups_applied=true
        # Load config once for this resolution tree
        local config_data
        config_data=$(<"$config_file")

        # Priority 1b: Session-only config overrides
        resolved_model=$(echo "$config_data" | jq -r --arg p "$canonical_provider" '.overrides[$p] // empty' 2>/dev/null)
        if [[ -n "$resolved_model" && "$resolved_model" != "null" ]] && ! _octo_automatic_model_allowed "$resolved_model"; then
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 2 (session override): REJECTED explicit-only model $resolved_model" >&2
            resolved_model=""
        fi
        if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 2 (session override): $resolved_model ← SELECTED" >&2
        else
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 2 (session override): —" >&2
        fi

        # 2. Role/Phase Routing
        # Object routes are literal, explicit provider/model selections. Unlike
        # legacy string routes (for example "codex:spark"), their model field
        # must not be reinterpreted as a capability alias. This makes one
        # providers.json entry sufficient for provider + exact model routing.
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            local role_route_json=""
            local phase_route_json=""
            local role_route_type=""
            local role_route_provider=""
            local role_route_model=""
            local role_route_value=""
            local phase_route_provider=""
            local phase_route_model=""
            local role_route_blocks_phase="false"
            local role_route_model_family=""
            local role_route_provider_org=""

            if [[ -n "$role" ]]; then
                role_route_json=$(echo "$config_data" | jq -c --arg role "$role" '.routing.roles[$role] // empty' 2>/dev/null)
                if [[ -n "$role_route_json" && "$role_route_json" != "null" ]]; then
                    role_route_type=$(echo "$role_route_json" | jq -r 'type' 2>/dev/null)
                    if [[ "$role_route_type" == "object" ]]; then
                        role_route_provider=$(echo "$role_route_json" | jq -r '.provider // empty' 2>/dev/null)
                        role_route_model=$(echo "$role_route_json" | jq -r '.model // empty' 2>/dev/null)
                        if [[ -n "$role_route_provider" ]]; then
                            role_route_provider="$(octo_provider_canonical "$role_route_provider" 2>/dev/null || printf '%s' "$role_route_provider")"
                        fi
                        if [[ -z "$role_route_provider" || "$role_route_provider" == "$canonical_provider" ]]; then
                            role_route_blocks_phase="true"
                            if [[ -n "$role_route_model" ]]; then
                                resolved_model="$role_route_model"
                                if ! _octo_automatic_model_allowed "$resolved_model"; then
                                    [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (literal role route): REJECTED explicit-only model $resolved_model" >&2
                                    resolved_model=""
                                fi
                                [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (literal role route): $resolved_model ← SELECTED" >&2
                            fi
                        fi
                    else
                        # A legacy role route only blocks the phase route when it
                        # applies to the provider currently being resolved.
                        role_route_value=$(echo "$role_route_json" | jq -r '.' 2>/dev/null)
                        if [[ "$role_route_value" == *:* ]]; then
                            role_route_provider="${role_route_value%%:*}"
                            role_route_provider="$(octo_provider_canonical "$role_route_provider" 2>/dev/null || printf '%s' "$role_route_provider")"
                            [[ "$role_route_provider" == "$canonical_provider" ]] && role_route_blocks_phase="true"
                        elif _octo_is_known_provider_name "$role_route_value"; then
                            role_route_provider="$(octo_provider_canonical "$role_route_value" 2>/dev/null || printf '%s' "$role_route_value")"
                            [[ "$role_route_provider" == "$canonical_provider" ]] && role_route_blocks_phase="true"
                        else
                            role_route_model_family="$(_octo_route_value_model_family "$role_route_value" "$canonical_provider")"
                            role_route_provider_org="$(octo_provider_org "$canonical_provider" 2>/dev/null || true)"
                            role_route_blocks_phase="true"
                            if ! octo_provider_has_capability "$canonical_provider" model-gateway &&
                               [[ "$role_route_model_family" != "unknown" &&
                                  "$role_route_model_family" != "$role_route_provider_org" ]]; then
                                role_route_blocks_phase="false"
                            fi
                        fi
                    fi
                fi
            fi

            if [[ ( -z "$resolved_model" || "$resolved_model" == "null" ) && "$role_route_blocks_phase" != "true" && -n "$phase" ]]; then
                phase_route_json=$(echo "$config_data" | jq -c --arg phase "$phase" '.routing.phases[$phase] // empty' 2>/dev/null)
                if [[ -n "$phase_route_json" && "$phase_route_json" != "null" ]] && [[ "$(echo "$phase_route_json" | jq -r 'type' 2>/dev/null)" == "object" ]]; then
                    phase_route_provider=$(echo "$phase_route_json" | jq -r '.provider // empty' 2>/dev/null)
                    phase_route_model=$(echo "$phase_route_json" | jq -r '.model // empty' 2>/dev/null)
                    if [[ -n "$phase_route_provider" ]]; then
                        phase_route_provider="$(octo_provider_canonical "$phase_route_provider" 2>/dev/null || printf '%s' "$phase_route_provider")"
                    fi
                    if [[ ( -z "$phase_route_provider" || "$phase_route_provider" == "$canonical_provider" ) && -n "$phase_route_model" ]]; then
                        resolved_model="$phase_route_model"
                        if ! _octo_automatic_model_allowed "$resolved_model"; then
                            [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (literal phase route): REJECTED explicit-only model $resolved_model" >&2
                            resolved_model=""
                        fi
                        [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (literal phase route): $resolved_model ← SELECTED" >&2
                    fi
                fi
            fi
        fi

        # Legacy string role/phase routes remain supported below.
        # Role routes are more specific than phase routes. In review fleets this
        # lets `logic-reviewer` use an independent model even when the broad
        # `review` phase route points at the default coding provider/model.
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            local routed=""
            local phase_routed=""
            [[ -n "$phase" ]] && phase_routed=$(echo "$config_data" | jq -r --arg phase "$phase" '
                .routing.phases[$phase] // empty |
                if type == "object" then ((.provider // "") + (if (.model // "") != "" then ":" + .model else "" end)) else . end
            ' 2>/dev/null)
            if [[ -n "$role" ]]; then
                routed=$(echo "$config_data" | jq -r --arg role "$role" '
                    .routing.roles[$role] // empty |
                    if type == "object" then ((.provider // "") + (if (.model // "") != "" then ":" + .model else "" end)) else . end
                ' 2>/dev/null)
                if [[ -n "$routed" && "$routed" != "null" ]]; then
                    local role_route_provider=""
                    if [[ "$routed" == *:* ]]; then
                        role_route_provider="${routed%%:*}"
                    elif _octo_is_known_provider_name "$routed"; then
                        role_route_provider="$routed"
                    fi
                    if [[ -n "$role_route_provider" ]]; then
                        role_route_provider="$(octo_provider_canonical "$role_route_provider" 2>/dev/null || printf '%s' "$role_route_provider")"
                    fi
                    if [[ -n "$role_route_provider" && "$role_route_provider" != "$canonical_provider" ]]; then
                        [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (role routing): SKIP (role route $routed targets $role_route_provider, resolving for $provider); checking phase route" >&2
                        routed=""
                    elif [[ -z "$role_route_provider" && "$role_route_blocks_phase" != "true" && -n "$phase_routed" && "$phase_routed" != "null" ]]; then
                        [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (role routing): SKIP (bare role route $routed is unscoped and phase route exists); checking phase route" >&2
                        routed=""
                    fi
                fi
            fi
            if [[ -z "$routed" || "$routed" == "null" ]] && [[ "$role_route_blocks_phase" != "true" ]] && [[ -n "$phase_routed" && "$phase_routed" != "null" ]]; then
                routed="$phase_routed"
            fi

            # Handle recursive reference (e.g. "codex:spark")
            # v9.17.1: Skip cross-provider routing — if route targets a different provider,
            # don't apply its model to the current provider (fixes #235 item 3)
            if [[ -n "$routed" && "$routed" != "null" ]]; then
                if [[ "$routed" == *:* ]]; then
                    local ref_provider="${routed%%:*}"
                    local ref_type="${routed#*:}"
                    local canonical_ref_provider
                    canonical_ref_provider="$(octo_provider_canonical "$ref_provider" 2>/dev/null || printf '%s' "$ref_provider")"
                    if [[ "$canonical_ref_provider" != "$canonical_provider" ]]; then
                        # Route targets a different provider — skip for this resolution
                        [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): SKIP (route $routed targets $ref_provider, resolving for $provider)" >&2
                        routed=""
                    else
                        if ! resolved_model=$(resolve_octopus_model "$canonical_ref_provider" "$ref_type" "" ""); then
                            return 1
                        fi
                    fi
                else
                    # Bare provider names in routing values are provider routes, not
                    # model names. "researcher": "perplexity" means "route this role
                    # to the perplexity provider" — it must never become
                    # `codex exec --model perplexity` (bug 260609). Treat a bare
                    # provider name like "provider:" with no model: skip for other
                    # providers, fall through to lower tiers for the provider itself.
                    if _octo_is_known_provider_name "$routed"; then
                        [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): SKIP (route '$routed' is a provider name, not a model — resolving for $provider)" >&2
                        routed=""
                    else
                        resolved_model="$routed"
                        if ! _octo_automatic_model_allowed "$resolved_model"; then
                            [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): REJECTED explicit-only model $resolved_model" >&2
                            resolved_model=""
                            routed=""
                        fi
                    fi
                fi
                if [[ -n "$routed" ]]; then
                    [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): $resolved_model ← SELECTED (route: $routed)" >&2
                fi
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): —" >&2
            fi
        fi

        # Provider-local role defaults apply only after explicit role/phase
        # routing. They select a model for the provider already chosen by the
        # workflow, but must never override user/project routing configuration.
        # Example: providers.commandcode.roles.security-reviewer.
        if [[ ( -z "$resolved_model" || "$resolved_model" == "null" ) && -n "$role" ]]; then
            resolved_model=$(echo "$config_data" | jq -r --arg p "$canonical_provider" --arg role "$role" '.providers[$p].roles[$role] // empty' 2>/dev/null)
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]] && ! _octo_automatic_model_allowed "$resolved_model"; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 3a (provider role default): REJECTED explicit-only model $resolved_model" >&2
                resolved_model=""
            fi
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 3a (provider role default): $resolved_model ← SELECTED" >&2
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 3a (provider role default): —" >&2
            fi
        fi

        # An explicitly enabled eval policy is more specific than generic
        # capability, cost-tier, and provider defaults. It remains below every
        # environment, session, role/phase, and provider-role route.
        if [[ ( -z "$resolved_model" || "$resolved_model" == "null" ) &&
              "$routing_policy" == "eval" && -n "${OCTOPUS_TASK_CLASS:-}" ]]; then
            resolved_model="$(_octo_eval_model_for_class "$canonical_provider" "$OCTOPUS_TASK_CLASS" 2>/dev/null || true)"
            if [[ -n "$resolved_model" ]] && ! _octo_automatic_model_allowed "$resolved_model"; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 3b (eval ${OCTOPUS_TASK_CLASS}): REJECTED explicit-only model $resolved_model" >&2
                resolved_model=""
            fi
            [[ -n "$_trace" && -n "$resolved_model" ]] && echo "[model-trace] Tier 3b (eval ${OCTOPUS_TASK_CLASS}): $resolved_model ← SELECTED" >&2
        fi

        # 3. Capability Mapping (providers.codex.spark, etc)
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            local capability=""
            if [[ "$agent_type" == *-* ]]; then
                capability="${agent_type#*-}"
            else
                capability="$agent_type"
            fi

            if [[ -n "$capability" && "$capability" != "$canonical_provider" ]]; then
                # Support both short capability (spark) and full model aliases (spark_model)
                resolved_model=$(echo "$config_data" | jq -r --arg p "$canonical_provider" --arg cap "$capability" '.providers[$p][$cap] // .providers[$p][($cap + "_model")] // empty' 2>/dev/null)
                if [[ -n "$resolved_model" && "$resolved_model" != "null" ]] && ! _octo_automatic_model_allowed "$resolved_model"; then
                    [[ -n "$_trace" ]] && echo "[model-trace] Tier 4 (capability map): REJECTED explicit-only model $resolved_model" >&2
                    resolved_model=""
                fi
            fi
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 4 (capability map): $resolved_model ← SELECTED (cap: ${capability:-none})" >&2
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 4 (capability map): —" >&2
            fi
        fi

        # 4. Tier Mapping
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            if [[ -n "$cost_mode" ]]; then
                resolved_model=$(echo "$config_data" | jq -r --arg mode "$cost_mode" --arg p "$canonical_provider" '.tiers[$mode][$p] // empty' 2>/dev/null)
                if [[ -n "$resolved_model" && "$resolved_model" == *:* ]]; then
                    resolved_model="$(_octo_tier_target_model "$canonical_provider" "$resolved_model" 2>/dev/null || true)"
                fi
                if [[ -n "$resolved_model" && "$resolved_model" =~ ^[a-z_]+$ ]]; then
                    # Capability ref in tier map
                    local tier_mapped_model
                    tier_mapped_model=$(echo "$config_data" | jq -r --arg p "$canonical_provider" --arg model "$resolved_model" '.providers[$p][$model] // .providers[$p][($model + "_model")] // empty' 2>/dev/null)
                [[ -n "$tier_mapped_model" && "$tier_mapped_model" != "null" ]] && resolved_model="$tier_mapped_model"
            fi
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]] && ! _octo_automatic_model_allowed "$resolved_model"; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 5 (cost mode ${cost_mode}): REJECTED explicit-only model $resolved_model" >&2
                resolved_model=""
            fi
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 5 (cost mode ${cost_mode}): ${resolved_model:-—}" >&2
            fi
        fi

        # 5. Global Defaults
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            resolved_model=$(echo "$config_data" | jq -r --arg p "$canonical_provider" '.providers[$p].default // .providers[$p].model // empty' 2>/dev/null)
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]] && ! _octo_automatic_model_allowed "$resolved_model"; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 6 (config default): REJECTED explicit-only model $resolved_model" >&2
                resolved_model=""
            fi
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 6 (config default): $resolved_model ← SELECTED" >&2
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 6 (config default): —" >&2
            fi
        fi
    fi

    # With no readable project config there are no project routes/defaults to
    # traverse, but an explicitly enabled session eval policy still precedes
    # release defaults.
    if [[ "$config_lookups_applied" != true &&
          ( -z "$resolved_model" || "$resolved_model" == "null" ) &&
          "$routing_policy" == "eval" && -n "${OCTOPUS_TASK_CLASS:-}" ]]; then
        resolved_model="$(_octo_eval_model_for_class "$canonical_provider" "$OCTOPUS_TASK_CLASS" 2>/dev/null || true)"
        if [[ -n "$resolved_model" ]] && ! _octo_automatic_model_allowed "$resolved_model"; then
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 3b (eval ${OCTOPUS_TASK_CLASS}): REJECTED explicit-only model $resolved_model" >&2
            resolved_model=""
        fi
        [[ -n "$_trace" && -n "$resolved_model" ]] && echo "[model-trace] Tier 3b (eval ${OCTOPUS_TASK_CLASS}): $resolved_model ← SELECTED" >&2
    fi

    # Fallback to hard-coded defaults (Priority 7)
    if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
        case "$agent_type" in
            codex*)          resolved_model="$(codex_default_model)" ;;
            gemini*|agy*|antigravity) resolved_model="default" ;;
            commandcode*)    resolved_model="deepseek/deepseek-v4-pro" ;;
            claude-sdk*)     resolved_model="${OCTOPUS_CLAUDE_SDK_MODEL:-claude-opus-5}" ;;  # must precede claude* glob
            claude-opus-legacy*) resolved_model="claude-opus-4.6" ;;
            claude-opus*)    resolved_model="$(opus_default_model)" ;;
            claude*)         resolved_model="$(sonnet_default_model)" ;;
            perplexity-fast)  resolved_model="sonar" ;;
            perplexity*)       resolved_model="sonar-pro" ;;
            openrouter-glm*)  resolved_model="z-ai/glm-5" ;;
            openrouter-kimi*) resolved_model="moonshotai/kimi-k2.5" ;;
            openrouter-deepseek*) resolved_model="deepseek/deepseek-v4-pro" ;;
            openrouter)      resolved_model="anthropic/claude-sonnet-4" ;; # bare OpenRouter needs a namespaced ID, not an OpenAI model string (#797)
            orcarouter*)     resolved_model="anthropic/claude-sonnet-4.6" ;; # bare OrcaRouter needs a namespaced ID, not an OpenAI model string (#797)
            openai-compatible|openai-tools|openai-compatible-agent*)
                if [[ -z "${OPENAI_COMPAT_MODEL:-}" ]]; then
                    log ERROR "OPENAI_COMPAT_MODEL or providers.json openai-compatible-agent.default is required"
                    return 1
                fi
                resolved_model="$OPENAI_COMPAT_MODEL"
                ;;
            ollama*)
                if ! resolved_model="$(ollama_default_model)"; then
                    return 1
                fi
                ;;
            copilot*)        resolved_model="auto" ;; # Let the current Copilot CLI choose its supported default.
            qwen*)           resolved_model="qwen3-coder" ;;
            cursor-agent*)   resolved_model="auto" ;; # Cursor's service-side pick; pin any `agent models` ID via OCTOPUS_CURSOR_AGENT_MODEL
            opencode-research*) resolved_model="opencode/glm-5.1" ;;
            opencode-fast*)  resolved_model="opencode/deepseek-v4-flash-free" ;;
            opencode*)       resolved_model="opencode/deepseek-v4-flash-free" ;;
            grok*)           resolved_model="default" ;; # xAI's own default; dispatch.sh/grok-exec.sh omit --model for "default" (#797)
            kimi*)           resolved_model="default" ;; # Kimi's own default from ~/.kimi-code/config.toml; the shim omits --model for "default"
            vibe*)           resolved_model="default" ;; # Mistral Vibe's own default from ~/.vibe/config.toml; never wired to --model (#797)
            atlascloud*)     resolved_model="" ;; # No safe universal default; atlascloud-agent dispatch already requires an explicit model pin (#797)
            *)              resolved_model="$(codex_default_model)" ;; # Safest universal fallback
        esac
        [[ -n "$_trace" ]] && echo "[model-trace] Tier 7 (hardcoded fallback): $resolved_model ← SELECTED" >&2
    fi

    # v9.51: Fable 5 security reroute — security dispatches never run on
    # either Fable 5 generation (safety classifiers can refuse adversarial phrasing).
    # Applied before caching so the cache key (which includes phase/role)
    # stores the rerouted value.
    if declare -f fable5_maybe_reroute >/dev/null 2>&1; then
        resolved_model="$(fable5_maybe_reroute "$resolved_model" "$role" "$agent_type" "$phase")"
    fi

    [[ -n "$_trace" ]] && echo "[model-trace] ► Result: $resolved_model" >&2

    # Validate before eval/cache. Dispatch also validates before command
    # construction, but the resolver cache itself must not eval unsafe values.
    if ! validate_model_name_for_provider "$canonical_provider" "$resolved_model"; then
        log ERROR "Invalid resolved model name for $provider/$agent_type"
        return 1
    fi

    # Update memory and persistent cache
    # Use \$var to prevent double-expansion; resolved_model is validated above and internally computed.
    eval "_OCTO_MODEL_CACHE_${cache_key}=\"\$resolved_model\""
    if [[ -n "$persistent_cache" ]] && command -v jq &>/dev/null; then
        local cache_json="{}"
        # Self-heal: reject unreadable, concatenated-JSON, or non-object payloads.
        # Plain `jq -e .` accepts `{}\n{}` as a valid stream — the exact
        # concurrent-writer artifact this gate exists to heal. Slurp to count.
        if [[ -r "$persistent_cache" ]] && cache_json=$(<"$persistent_cache") && [[ -n "$cache_json" ]]; then
            cache_json=$(jq -cse 'if length == 1 and (.[0] | type) == "object" then .[0] else error("invalid") end' \
                         <<<"$cache_json" 2>/dev/null) || cache_json="{}"
        else
            cache_json="{}"
        fi
        echo "$cache_json" | jq --arg key "$cache_key" --arg val "$resolved_model" '.[$key] = $val' > "${persistent_cache}.tmp.$$" 2>/dev/null && mv "${persistent_cache}.tmp.$$" "$persistent_cache"
    fi

    echo "$resolved_model"
}

# ── Extracted from orchestrate.sh ──
# Validate model name to prevent shell injection and other malformed inputs
validate_model_name() {
    local model="$1"

    # Reject empty names
    [[ -z "$model" ]] && return 1
    [[ "$model" == *$'\n'* || "$model" == *$'\r'* ]] && return 1
    case "$model" in
        *\\*) return 1 ;;
    esac

    # Reject shell metacharacters and whitespace (v8.50.0 Security hardening).
    case "$model" in
        *[[:space:]]*|*\*|*";"*|*"|"*|*"&"*|*'$'*|*'`'*|*"'"*|*'"'*|*"("*|*")"*|*"<"*|*">"*|*"!"*|*"*"*|*"?"*|*"["*|*"]"*|*"{"*|*"}"*)
            return 1
            ;;
    esac

    # Reject names that look like absolute paths
    if [[ "$model" == /* ]]; then
        return 1
    fi

    return 0
}


# ── v2 agent helpers (moved from orchestrate.sh v9.22.1) ──
is_agent_available_v2() {
    local agent="$1"

    # Load config if needed
    [[ -z "$PROVIDER_CODEX_INSTALLED" ]] && load_providers_config

    # oco-cbb: skip a provider marked quota/auth-dead earlier this session.
    if declare -f octo_quota_is_dead >/dev/null 2>&1 && octo_quota_is_dead "${agent%%-*}"; then
        return 1
    fi

    if is_claude_agent_type "$agent"; then
        [[ "$PROVIDER_CLAUDE_INSTALLED" == "true" ]]
        return
    fi

    case "$agent" in
        codex|codex-standard|codex-mini|codex-max|codex-general|codex-review|codex-spark|codex-reasoning|codex-large-context)
            [[ "$PROVIDER_CODEX_INSTALLED" == "true" && "$PROVIDER_CODEX_AUTH_METHOD" != "none" ]]
            ;;
        gemini|gemini-fast|gemini-image|agy|agy-research|antigravity)
            command -v agy &>/dev/null
            ;;
        openrouter|openrouter-*)
            [[ "$PROVIDER_OPENROUTER_ENABLED" == "true" && "$PROVIDER_OPENROUTER_API_KEY_SET" == "true" ]]
            ;;
        orcarouter|orcarouter-*)
            [[ "$PROVIDER_ORCAROUTER_ENABLED" == "true" && "$PROVIDER_ORCAROUTER_API_KEY_SET" == "true" ]]
            ;;
        openai-compatible|openai-tools|openai-compatible-agent*)
            declare -f openai_compatible_is_available >/dev/null 2>&1 && openai_compatible_is_available
            ;;
        perplexity|perplexity-fast)
            [[ -n "${PERPLEXITY_API_KEY:-}" ]]
            ;;
        ollama*)
            command -v ollama &>/dev/null && curl -sf http://localhost:11434/api/tags &>/dev/null
            ;;
        copilot|copilot-research)
            declare -f copilot_is_available >/dev/null 2>&1 && copilot_is_available
            ;;
        qwen|qwen-research)
            command -v qwen &>/dev/null && {
                [[ -f "${HOME}/.qwen/oauth_creds.json" ]] || \
                [[ -f "${HOME}/.qwen/config.json" ]] || \
                [[ -n "${QWEN_API_KEY:-}" ]]
            }
            ;;
        opencode|opencode-fast|opencode-research)
            [[ "$PROVIDER_OPENCODE_INSTALLED" == "true" && "$PROVIDER_OPENCODE_AUTH_METHOD" != "none" ]]
            ;;
        cursor-agent|cursor-agent-*)
            declare -f cursor_agent_is_available >/dev/null 2>&1 && cursor_agent_is_available
            ;;
        grok|grok-*)
            declare -f grok_is_available >/dev/null 2>&1 && grok_is_available
            ;;
        commandcode|commandcode-*)
            local cc_bin="${OCTOPUS_COMMANDCODE_BIN:-}"
            [[ -z "$cc_bin" ]] && command -v command-code &>/dev/null && cc_bin="command-code"
            [[ -z "$cc_bin" ]] && command -v cmd &>/dev/null && cc_bin="cmd"
            [[ -n "$cc_bin" ]] && { [[ -x "$cc_bin" ]] || command -v "$cc_bin" &>/dev/null; } && \
                { [[ -n "${COMMAND_CODE_API_KEY:-}" ]] || "$cc_bin" status --json &>/dev/null; }
            ;;
        atlascloud|atlascloud-*)
            if [[ -z "${ATLASCLOUD_API_KEY:-}" ]] && declare -f resolve_provider_env >/dev/null 2>&1; then
                resolve_provider_env "ATLASCLOUD_API_KEY" 2>/dev/null || true
            fi
            [[ -n "${ATLASCLOUD_API_KEY:-}" ]] && \
                { [[ -n "${ATLASCLOUD_MODEL:-}" ]] || [[ -n "${OCTOPUS_ATLASCLOUD_MODEL:-}" ]] || [[ -n "${OPENAI_COMPAT_MODEL:-}" ]]; }
            ;;
        kimi|kimi-*)
            declare -f kimi_is_available >/dev/null 2>&1 && kimi_is_available
            ;;
        vibe|vibe-*)
            if [[ -z "${MISTRAL_API_KEY:-}" ]] && declare -f resolve_provider_env >/dev/null 2>&1; then
                resolve_provider_env "MISTRAL_API_KEY" 2>/dev/null || true
            fi
            command -v vibe &>/dev/null && {
                _octo_value_has_nonwhitespace "${MISTRAL_API_KEY:-}" || \
                _octo_assignment_has_nonempty_value "${HOME}/.vibe/.env" "MISTRAL_API_KEY" || \
                _octo_assignment_has_nonempty_value "${HOME}/.vibe/config.toml" "api_key"
            }
            ;;
        *)
            return 1  # Unknown agents fail closed (#799: was `return 0`, which
                      # could seat a provider with no availability contract and
                      # defer the failure until mid-workflow)
            ;;
    esac
}

# Print one verified available agent and return 0. If neither the preferred
# agent nor any fallback is available, print nothing and return non-zero.
get_fallback_agent() {
    local preferred="$1"
    local task_type="$2"
    local candidate=""

    if octo_fallback_agent_available "$preferred"; then
        echo "$preferred"
        return 0
    fi

    # Retired Gemini IDs remain compatibility aliases for Antigravity. Treat
    # the alias translation separately from fallback policy so the policy can
    # be fully configuration-driven.
    case "$preferred" in
        gemini|gemini-fast|gemini-image)
            if octo_fallback_agent_available "agy"; then
                echo "agy"
                return 0
            fi
            ;;
    esac

    # Unified fallback policy. routing.fallbackChains.default may override the
    # built-in role chain; role candidates resolve through routing.roles.
    if declare -f octo_fallback_first_available >/dev/null 2>&1; then
        candidate="$(octo_fallback_first_available default "$preferred" "" 2>/dev/null || true)"
    fi
    if [[ -n "$candidate" ]]; then
        [[ "${VERBOSE:-false}" == "true" ]] && log DEBUG "Fallback: $preferred -> $candidate (chain: default, task: $task_type)" || true
        echo "$candidate"
        return 0
    fi

    if declare -f log >/dev/null 2>&1; then
        log ERROR "No available agent for '$preferred' and fallback chain 'default'"
    else
        printf "No available agent for '%s' and fallback chain 'default'\n" "$preferred" >&2
    fi
    return 1
}
