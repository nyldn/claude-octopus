#!/usr/bin/env bash
_profile_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octopus_resolve_reasoning_level >/dev/null 2>&1; then
    source "${_profile_lib_dir}/execution-profile.sh" 2>/dev/null || true
fi
# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION v3.0: Unified Model Resolver (v8.50.0)
# Consolidated logic for provider, phase, and role-based model selection.
# Precedence: Env Var > Session Override > Phase/Role Routing > Capability > Tier > Defaults
# Extracted from orchestrate.sh — v9.7.5
# ═══════════════════════════════════════════════════════════════════════════════

_model_resolver_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f _is_cursor_agent_binary >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/cursor-agent.sh" 2>/dev/null || true
fi
if ! declare -f fable5_maybe_reroute >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/fable5.sh" 2>/dev/null || true
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

# v9.42.0: Opus default picker — prefers 4.8 when host supports it, then 4.7,
# then 4.6. Respects OCTOPUS_OPUS_MODEL override (user-pinned version).
# v9.44.0: Claude Fable 5 (Mythos-class, $10/$50 MTok, 1M ctx) is opt-in only:
# pin OCTOPUS_OPUS_MODEL=claude-fable-5. Never auto-selected — 2x Opus 4.8 cost,
# and Anthropic retains prompts/outputs up to 30 days for safety classifiers.
opus_default_model() {
    if [[ -n "${OCTOPUS_OPUS_MODEL:-}" ]]; then
        echo "$OCTOPUS_OPUS_MODEL"
        return 0
    fi
    # SUPPORTS_OPUS_4_8 is detected from Claude Code v2.1.154+ — see lib/providers.sh
    if [[ "${SUPPORTS_OPUS_4_8:-false}" == "true" ]]; then
        echo "claude-opus-4.8"
    elif [[ "${SUPPORTS_OPUS_4_7:-false}" == "true" ]]; then
        echo "claude-opus-4.7"
    else
        echo "claude-opus-4.6"
    fi
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

    if ! command -v agy >/dev/null 2>&1; then
        log ERROR "Cannot validate OCTOPUS_AGY_MODEL because agy CLI is not installed"
        return 1
    fi

    local available_models=""
    if ! available_models="$(agy models </dev/null 2>/dev/null)" || [[ -z "$available_models" ]]; then
        log ERROR "Cannot validate OCTOPUS_AGY_MODEL because 'agy models' returned no models"
        return 1
    fi

    local line=""
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "$line" == "$model" ]]; then
            return 0
        fi
    done <<< "$available_models"

    log ERROR "Invalid OCTOPUS_AGY_MODEL: '$model'"
    printf 'Available agy models:\n%s\n' "$available_models" >&2
    return 1
}

validate_model_name_for_provider() {
    local provider="$1"
    local model="$2"

    case "$provider" in
        agy|agy-research|antigravity)
            validate_agy_model_name "$model"
            ;;
        *)
            validate_model_name "$model"
            ;;
    esac
}

_octo_is_known_provider_name() {
    case "$1" in
        codex|gemini|claude|perplexity|qwen|copilot|opencode|ollama|openrouter|cursor-agent|vibe|agy|agy-research|antigravity)
            return 0 ;;
        *)
            return 1 ;;
    esac
}
# resolve_octopus_model <provider> <agent_type> <phase> <role>
resolve_octopus_model() {
    local provider="$1"
    local agent_type="$2"
    local phase="${3:-}"
    local role="${4:-}"
    local config_file="${HOME}/.claude-octopus/config/providers.json"
    local resolved_model=""

    # Env overrides must bypass caches. A prior default resolution can be cached
    # for the same provider/agent/phase tuple, but explicit user overrides are
    # session state and take precedence over any cached value.
    local canonical_provider="$provider"
    case "$canonical_provider" in
        antigravity|agy-research) canonical_provider="agy" ;;
    esac
    local env_var="OCTOPUS_$(echo "$canonical_provider" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_MODEL"
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
    local safe_cfg="no_config"
    if [[ -f "$config_file" ]]; then
        safe_cfg="$(cksum < "$config_file" 2>/dev/null | awk '{print $1 "_" $2}')"
        safe_cfg="${safe_cfg//[^a-zA-Z0-9_]/_}"
    fi
    cache_key="MC_${safe_p}_A_${safe_a}_P_${safe_ph}_R_${safe_r}_C_${safe_cfg}"
    local cached_val
    eval "cached_val=\"\${_OCTO_MODEL_CACHE_${cache_key}:-}\""
    if [[ -n "$cached_val" ]]; then
        if validate_model_name_for_provider "$canonical_provider" "$cached_val"; then
            echo "$cached_val"
            return 0
        fi
        log ERROR "Invalid model name in memory cache for $provider/$agent_type"
        eval "unset _OCTO_MODEL_CACHE_${cache_key}"
        cached_val=""
    fi

    # Persistent File Cache (optional, for parallel execution speed)
    local cache_dir="${TMPDIR:-/tmp}"
    local persistent_cache=""
    if mkdir -p "$cache_dir" 2>/dev/null && [[ -d "$cache_dir" && -w "$cache_dir" ]]; then
        persistent_cache="${cache_dir%/}/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
    elif mkdir -p /tmp 2>/dev/null && [[ -d /tmp && -w /tmp ]]; then
        persistent_cache="/tmp/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
    fi
    # v8.49.0: Invalidate cache if config file changed since cache was written
    if [[ -n "$persistent_cache" && -f "$persistent_cache" && -f "$config_file" && "$config_file" -nt "$persistent_cache" ]]; then
        rm -f "$persistent_cache"
    fi
    if [[ -n "$persistent_cache" && -f "$persistent_cache" ]] && command -v jq &>/dev/null; then
        cached_val=$(jq -r ".\"$cache_key\" // empty" "$persistent_cache" 2>/dev/null)
        if [[ -n "$cached_val" && "$cached_val" != "null" ]]; then
            # Reject invalid cached model names instead of mutating them into a
            # different model string before eval.
            if validate_model_name_for_provider "$canonical_provider" "$cached_val"; then
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
    if [[ -z "$resolved_model" && -f "$config_file" ]] && command -v jq &> /dev/null; then
        # Load config once for this resolution tree
        local config_data
        config_data=$(<"$config_file")

        # Priority 1b: Session-only config overrides
        resolved_model=$(echo "$config_data" | jq -r --arg p "$canonical_provider" '.overrides[$p] // empty' 2>/dev/null)
        if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 2 (session override): $resolved_model ← SELECTED" >&2
        else
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 2 (session override): —" >&2
        fi

        # 2. Role/Phase Routing
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
                    if [[ -n "$role_route_provider" && "$role_route_provider" != "$provider" ]]; then
                        [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (role routing): SKIP (role route $routed targets $role_route_provider, resolving for $provider); checking phase route" >&2
                        routed=""
                    elif [[ -z "$role_route_provider" && -n "$phase_routed" && "$phase_routed" != "null" ]]; then
                        [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (role routing): SKIP (bare role route $routed is unscoped and phase route exists); checking phase route" >&2
                        routed=""
                    fi
                fi
            fi
            if [[ -z "$routed" || "$routed" == "null" ]] && [[ -n "$phase_routed" && "$phase_routed" != "null" ]]; then
                routed="$phase_routed"
            fi

            # Handle recursive reference (e.g. "codex:spark")
            # v9.17.1: Skip cross-provider routing — if route targets a different provider,
            # don't apply its model to the current provider (fixes #235 item 3)
            if [[ -n "$routed" && "$routed" != "null" ]]; then
                if [[ "$routed" == *:* ]]; then
                    local ref_provider="${routed%%:*}"
                    local ref_type="${routed#*:}"
                    if [[ "$ref_provider" != "$provider" ]]; then
                        # Route targets a different provider — skip for this resolution
                        [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): SKIP (route $routed targets $ref_provider, resolving for $provider)" >&2
                        routed=""
                    else
                        if ! resolved_model=$(resolve_octopus_model "$ref_provider" "$ref_type" "" ""); then
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
                    fi
                fi
                if [[ -n "$routed" ]]; then
                    [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): $resolved_model ← SELECTED (route: $routed)" >&2
                fi
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): —" >&2
            fi
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
            fi
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 4 (capability map): $resolved_model ← SELECTED (cap: ${capability:-none})" >&2
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 4 (capability map): —" >&2
            fi
        fi

        # 4. Tier Mapping
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            if [[ -n "${OCTOPUS_COST_MODE:-}" && "${OCTOPUS_COST_MODE:-}" != "standard" ]]; then
                resolved_model=$(echo "$config_data" | jq -r --arg mode "$OCTOPUS_COST_MODE" --arg p "$canonical_provider" '.tiers[$mode][$p] // empty' 2>/dev/null)
                if [[ -n "$resolved_model" && "$resolved_model" =~ ^[a-z_]+$ ]]; then
                    # Capability ref in tier map
                    local tier_mapped_model
                    tier_mapped_model=$(echo "$config_data" | jq -r --arg p "$canonical_provider" --arg model "$resolved_model" '.providers[$p][$model] // .providers[$p][($model + "_model")] // empty' 2>/dev/null)
                    [[ -n "$tier_mapped_model" && "$tier_mapped_model" != "null" ]] && resolved_model="$tier_mapped_model"
                fi
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 5 (cost mode ${OCTOPUS_COST_MODE}): ${resolved_model:-—}" >&2
            fi
        fi

        # 5. Global Defaults
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            resolved_model=$(echo "$config_data" | jq -r --arg p "$canonical_provider" '.providers[$p].default // .providers[$p].model // empty' 2>/dev/null)
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 6 (config default): $resolved_model ← SELECTED" >&2
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 6 (config default): —" >&2
            fi
        fi
    fi

    # Fallback to hard-coded defaults (Priority 7)
    if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
        case "$agent_type" in
            codex*)          resolved_model="gpt-5.5" ;;
            gemini-image)    resolved_model="gemini-3-pro-image" ;;  # image, not text — must precede gemini* (codex review)
            gemini-fast|gemini-flash) resolved_model="gemini-3-flash-preview" ;;
            gemini*)         resolved_model="gemini-3.1-pro-preview" ;;
            agy*|antigravity) resolved_model="default" ;;
            claude-sdk*)     resolved_model="${OCTOPUS_CLAUDE_SDK_MODEL:-claude-opus-4-8}" ;;  # v9.50.0: must precede claude* glob
            claude-opus-legacy*) resolved_model="claude-opus-4.6" ;;
            claude-opus*)    resolved_model="$(opus_default_model)" ;;
            claude*)         resolved_model="claude-sonnet-4.6" ;;
            perplexity-fast)  resolved_model="sonar" ;;
            perplexity*)       resolved_model="sonar-pro" ;;
            openrouter-glm52*) resolved_model="z-ai/glm-5.2" ;;
            openrouter-kimi-k3*) resolved_model="moonshotai/kimi-k3" ;;
            openrouter-glm*)  resolved_model="z-ai/glm-5" ;;
            openrouter-kimi*) resolved_model="moonshotai/kimi-k2.5" ;;
            openrouter-deepseek*) resolved_model="deepseek/deepseek-r1-0528" ;;
            openai-compatible|openai-tools|openai-compatible-agent*) resolved_model="${OPENAI_COMPAT_MODEL:-gpt-5.4}" ;;
            ollama*)         resolved_model="llama3.3" ;;
            copilot*)        resolved_model="claude-sonnet-4.5" ;; # Copilot default; actual model selected by copilot CLI
            qwen*)           resolved_model="qwen3-coder" ;;
            cursor-agent*)   resolved_model="grok-4-20" ;;
            opencode-research*) resolved_model="opencode/glm-5.1" ;;
            opencode-fast*)  resolved_model="opencode/deepseek-v4-flash-free" ;;
            opencode*)       resolved_model="opencode/deepseek-v4-flash-free" ;;
            *)              resolved_model="gpt-5.5" ;; # Safest universal fallback
        esac
        [[ -n "$_trace" ]] && echo "[model-trace] Tier 7 (hardcoded fallback): $resolved_model ← SELECTED" >&2
    fi

    # v9.51: Fable 5 security reroute — security dispatches never run on
    # claude-fable-5 (safety classifiers can refuse adversarial phrasing).
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
        gemini|gemini-fast|gemini-image)
            [[ "$PROVIDER_GEMINI_INSTALLED" == "true" && "$PROVIDER_GEMINI_AUTH_METHOD" != "none" ]]
            ;;
        agy|agy-research|antigravity)
            command -v agy &>/dev/null
            ;;
        openrouter|openrouter-*)
            [[ "$PROVIDER_OPENROUTER_ENABLED" == "true" && "$PROVIDER_OPENROUTER_API_KEY_SET" == "true" ]]
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
            command -v copilot &>/dev/null && {
                [[ -n "${COPILOT_GITHUB_TOKEN:-}" ]] || [[ -n "${GH_TOKEN:-}" ]] || \
                [[ -n "${GITHUB_TOKEN:-}" ]] || [[ -f "${HOME}/.copilot/config.json" ]] || \
                { command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; }
            }
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
            declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary && {
                [[ -n "${CURSOR_API_KEY:-}" ]] || \
                grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null
            }
            ;;
        *)
            return 0  # Unknown agents assumed available
            ;;
    esac
}

get_fallback_agent() {
    local preferred="$1"
    local task_type="$2"

    if is_agent_available "$preferred"; then
        echo "$preferred"
        return 0
    fi

    # Fallback logic (v8.9.0: extended with spark, reasoning, large-context fallbacks)
    case "$preferred" in
        gemini|gemini-fast)
            # Gemini unavailable, try codex
            if is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> codex (no Gemini)" || true
                echo "codex"
            else
                echo "$preferred"  # Return anyway, will error
            fi
            ;;
        codex|codex-standard|codex-mini)
            # Codex unavailable, try gemini
            if is_agent_available "agy"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> agy (no OpenAI)" || true
                echo "agy"
            else
                echo "$preferred"
            fi
            ;;
        codex-spark)
            # Spark unavailable or unsupported → fall back to standard codex → gemini
            if is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-spark -> codex (spark unavailable)" || true
                echo "codex"
            elif is_agent_available "agy"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-spark -> agy (no OpenAI)" || true
                echo "agy"
            else
                echo "$preferred"
            fi
            ;;
        codex-reasoning)
            # Reasoning model unavailable → fall back to codex (deep reasoning) → gemini
            if is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-reasoning -> codex (reasoning unavailable)" || true
                echo "codex"
            elif is_agent_available "agy"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-reasoning -> agy (no OpenAI)" || true
                echo "agy"
            else
                echo "$preferred"
            fi
            ;;
        codex-large-context)
            # Large context unavailable → fall back to codex (400K ctx) → gemini
            if is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-large-context -> codex (large-ctx unavailable)" || true
                echo "codex"
            elif is_agent_available "agy"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-large-context -> agy (no OpenAI)" || true
                echo "agy"
            else
                echo "$preferred"
            fi
            ;;
        openrouter-*)
            # v8.11.0: Model-specific OpenRouter → generic openrouter → codex → gemini
            if is_agent_available "openrouter"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> openrouter (model-specific unavailable)" || true
                echo "openrouter"
            elif is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> codex (no OpenRouter)" || true
                echo "codex"
            elif is_agent_available "agy"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> agy (no OpenRouter/OpenAI)" || true
                echo "agy"
            else
                echo "$preferred"
            fi
            ;;
        *)
            echo "$preferred"
            ;;
    esac
}
