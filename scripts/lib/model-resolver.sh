#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION v3.0: Unified Model Resolver (v8.50.0)
# Consolidated logic for provider, phase, and role-based model selection.
# Precedence: Env Var > Session Override > Phase/Role Routing > Capability > Tier > Defaults
# Extracted from orchestrate.sh — v9.7.5
# ═══════════════════════════════════════════════════════════════════════════════

# resolve_octopus_model <provider> <agent_type> <phase> <role>
resolve_octopus_model() {
    local provider="$1"
    local agent_type="$2"
    local phase="${3:-}"
    local role="${4:-}"
    local config_file="${HOME}/.claude-octopus/config/providers.json"
    local resolved_model=""

    # 0. Session Cache (v8.53.0)
    # Uses a process-local memory cache + optional file-based cache for cross-process speed
    local cache_key
    # v8.49.0: Field-delimited cache key prevents collisions
    # (e.g., provider="codex" + type="spark" must differ from type="codex-spark")
    local safe_p="${provider//[^a-zA-Z0-9]/_}"
    local safe_a="${agent_type//[^a-zA-Z0-9]/_}"
    local safe_ph="${phase//[^a-zA-Z0-9]/_}"
    local safe_r="${role//[^a-zA-Z0-9]/_}"
    cache_key="MC_${safe_p}_A_${safe_a}_P_${safe_ph}_R_${safe_r}"
    local cached_val
    eval "cached_val=\"\${_OCTO_MODEL_CACHE_${cache_key}:-}\""
    if [[ -n "$cached_val" ]]; then
        echo "$cached_val"
        return 0
    fi

    # Persistent File Cache (optional, for parallel execution speed)
    local persistent_cache="/tmp/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
    # v8.49.0: Invalidate cache if config file changed since cache was written
    if [[ -f "$persistent_cache" && -f "$config_file" && "$config_file" -nt "$persistent_cache" ]]; then
        rm -f "$persistent_cache"
    fi
    if [[ -f "$persistent_cache" ]] && command -v jq &>/dev/null; then
        cached_val=$(jq -r ".\"$cache_key\" // empty" "$persistent_cache" 2>/dev/null)
        if [[ -n "$cached_val" && "$cached_val" != "null" ]]; then
            eval "_OCTO_MODEL_CACHE_${cache_key}=\"$cached_val\""
            echo "$cached_val"
            return 0
        fi
    fi

    # v8.49.0: Resolution trace for debugging model selection
    local _trace="${OCTOPUS_TRACE_MODELS:-}"
    [[ -n "$_trace" ]] && echo "[model-trace] Resolving: provider=$provider type=$agent_type phase=${phase:-<none>} role=${role:-<none>}" >&2

    # 1. Force/Session Overrides (Env vars)
    local env_var="OCTOPUS_$(echo "$provider" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_MODEL"
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
                    resolved_model="$routed"
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
            codex*)          resolved_model="gpt-5.4" ;;
            gemini-fast|gemini-flash) resolved_model="gemini-3-flash-preview" ;;
            gemini*)         resolved_model="gemini-3.1-pro-preview" ;;
            claude-opus*)    resolved_model="claude-opus-4.6" ;;
            claude*)         resolved_model="claude-sonnet-4.6" ;;
            perplexity-fast)  resolved_model="sonar" ;;
            perplexity*)       resolved_model="sonar-pro" ;;
            openrouter-glm*)  resolved_model="z-ai/glm-5" ;;
            openrouter-kimi*) resolved_model="moonshotai/kimi-k2.5" ;;
            openrouter-deepseek*) resolved_model="deepseek/deepseek-r1-0528" ;;
            ollama*)         resolved_model="llama3.3" ;;
            copilot*)        resolved_model="claude-sonnet-4.5" ;; # Copilot default; actual model selected by copilot CLI
            qwen*)           resolved_model="qwen3-coder" ;;
            opencode-research*) resolved_model="z-ai/glm-5.1" ;;
            opencode-fast*)  resolved_model="google/gemini-2.5-flash" ;;
            opencode*)       resolved_model="google/gemini-2.5-flash" ;;
            *)              resolved_model="gpt-5.4" ;; # Safest universal fallback
        esac
        [[ -n "$_trace" ]] && echo "[model-trace] Tier 7 (hardcoded fallback): $resolved_model ← SELECTED" >&2
    fi

    [[ -n "$_trace" ]] && echo "[model-trace] ► Result: $resolved_model" >&2

    # Update memory and persistent cache
    eval "_OCTO_MODEL_CACHE_${cache_key}=\"$resolved_model\""
    if command -v jq &>/dev/null; then
        local cache_json="{}"
        # Self-heal: reject unreadable, concatenated-JSON, or non-object payloads.
        # Plain `jq -e .` accepts `{}\n{}` as a valid stream — the exact
        # concurrent-writer artifact this gate exists to heal. Slurp to count.
        if cache_json=$(<"$persistent_cache") 2>/dev/null && [[ -n "$cache_json" ]]; then
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

