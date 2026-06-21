#!/usr/bin/env bash
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
if ! declare -f is_claude_agent_type >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/routing.sh" 2>/dev/null || true
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
        antigravity) canonical_provider="agy" ;;
    esac
    local env_var="OCTOPUS_$(echo "$canonical_provider" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_MODEL"
    if [[ -n "${!env_var:-}" ]]; then
        echo "${!env_var}"
        return 0
    fi

    # 0. Session Cache (v8.53.0)
    # Uses a process-local memory cache + optional file-based cache for cross-process speed
    local cache_key
    # v8.49.0: Field-delimited cache key prevents collisions
    # (e.g., provider="codex" + type="spark" must differ from type="codex-spark")
    local safe_p="${provider//[^a-zA-Z0-9]/_}"
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
        echo "$cached_val"
        return 0
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
            # Sanitize before eval: strip shell metacharacters (model names are alphanumeric + .:/-_)
            cached_val="${cached_val//[^a-zA-Z0-9._:\/\-]/}"
            eval "_OCTO_MODEL_CACHE_${cache_key}=\"\$cached_val\""
            echo "$cached_val"
            return 0
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
        resolved_model=$(echo "$config_data" | jq -r ".overrides.${provider} // empty" 2>/dev/null)
        if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 2 (session override): $resolved_model ← SELECTED" >&2
        else
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 2 (session override): —" >&2
        fi

        # 2. Phase/Role Routing
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            local routed=""
            if [[ -n "$phase" ]]; then
                routed=$(echo "$config_data" | jq -r ".routing.phases.\"${phase}\" // empty" 2>/dev/null)
            fi
            if [[ -z "$routed" || "$routed" == "null" ]] && [[ -n "$role" ]]; then
                routed=$(echo "$config_data" | jq -r ".routing.roles.\"${role}\" // empty" 2>/dev/null)
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
                        resolved_model=$(resolve_octopus_model "$ref_provider" "$ref_type" "" "")
                    fi
                else
                    # Bare provider names in routing values are provider routes, not
                    # model names. "researcher": "perplexity" means "route this role
                    # to the perplexity provider" — it must never become
                    # `codex exec --model perplexity` (bug 260609). Treat a bare
                    # provider name like "provider:" with no model: skip for other
                    # providers, fall through to lower tiers for the provider itself.
                    case "$routed" in
                        codex|gemini|claude|perplexity|qwen|copilot|opencode|ollama|openrouter|cursor-agent|vibe|agy|agy-research|antigravity)
                            [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): SKIP (route '$routed' is a provider name, not a model — resolving for $provider)" >&2
                            routed=""
                            ;;
                        *)
                            resolved_model="$routed"
                            ;;
                    esac
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

            if [[ -n "$capability" && "$capability" != "$provider" ]]; then
                # Support both short capability (spark) and full model aliases (spark_model)
                resolved_model=$(echo "$config_data" | jq -r ".providers.${provider}.\"${capability}\" // .providers.${provider}.\"${capability}_model\" // empty" 2>/dev/null)
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
                resolved_model=$(echo "$config_data" | jq -r ".tiers.\"${OCTOPUS_COST_MODE}\".\"${provider}\" // empty" 2>/dev/null)
                if [[ -n "$resolved_model" && "$resolved_model" =~ ^[a-z_]+$ ]]; then
                    # Capability ref in tier map
                    local tier_mapped_model
                    tier_mapped_model=$(echo "$config_data" | jq -r ".providers.\"${provider}\".\"${resolved_model}\" // .providers.\"${provider}\".\"${resolved_model}_model\" // empty" 2>/dev/null)
                    [[ -n "$tier_mapped_model" && "$tier_mapped_model" != "null" ]] && resolved_model="$tier_mapped_model"
                fi
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 5 (cost mode ${OCTOPUS_COST_MODE}): ${resolved_model:-—}" >&2
            fi
        fi

        # 5. Global Defaults
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            resolved_model=$(echo "$config_data" | jq -r ".providers.${provider}.default // .providers.${provider}.model // empty" 2>/dev/null)
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
            gemini-fast|gemini-flash) resolved_model="gemini-3-flash-preview" ;;
            gemini*)         resolved_model="gemini-3.1-pro-preview" ;;
            agy*|antigravity) resolved_model="default" ;;
            claude-opus-legacy*) resolved_model="claude-opus-4.6" ;;
            claude-opus*)    resolved_model="$(opus_default_model)" ;;
            claude*)         resolved_model="claude-sonnet-4.6" ;;
            perplexity-fast)  resolved_model="sonar" ;;
            perplexity*)       resolved_model="sonar-pro" ;;
            openrouter-glm*)  resolved_model="z-ai/glm-5" ;;
            openrouter-kimi*) resolved_model="moonshotai/kimi-k2.5" ;;
            openrouter-deepseek*) resolved_model="deepseek/deepseek-r1-0528" ;;
            openai-compatible-agent*) resolved_model="${OPENAI_COMPAT_MODEL:-gpt-5.4}" ;;
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

    [[ -n "$_trace" ]] && echo "[model-trace] ► Result: $resolved_model" >&2

    # Update memory and persistent cache
    # Use \$var to prevent double-expansion; resolved_model is internally computed but defensive quoting is cheap
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
    
    # Reject names with shell meta-characters (v8.50.0 Security hardening)
    if [[ "$model" =~ [[:space:]\;\|\&\$\`\'\"()\<\>\!*?\[\]\{\}$'\n'$'\r'] ]]; then
        return 1
    fi
    
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
        openai-compatible-agent*)
            local compat_key_env="${OPENAI_COMPAT_API_KEY_ENV:-OPENAI_API_KEY}"
            [[ -n "${OPENAI_COMPAT_BASE_URL:-}" && ( -n "${OPENAI_COMPAT_API_KEY:-}" || -n "${!compat_key_env:-}" ) ]]
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
        openrouter-glm5|openrouter-kimi|openrouter-deepseek)
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
