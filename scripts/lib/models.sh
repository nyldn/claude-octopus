#!/usr/bin/env bash
# lib/models.sh — Model catalog: metadata, capabilities, listing
# Extracted from orchestrate.sh (Wave 1). Pure data lookup, zero global deps.

[[ -n "${_OCTOPUS_MODELS_LOADED:-}" ]] && return 0
_OCTOPUS_MODELS_LOADED=true

# ═══════════════════════════════════════════════════════════════════════════════
# MODEL CATALOG (v8.49.0)
# Centralized metadata: context window, capabilities, provider, tier, status.
# Used by capability-aware fallbacks and health checks.
# Format: context_k|tools|images|reasoning|provider|tier|status
# ═══════════════════════════════════════════════════════════════════════════════

# Get model capabilities metadata
# Returns: context_k|tools|images|reasoning|provider|tier|status
get_model_catalog() {
    local model="$1"
    case "$model" in
        # OpenAI GPT-5.x
        gpt-5.4)                echo "400|yes|yes|no|codex|premium|active" ;;
        gpt-5.4-pro)            echo "400|yes|yes|no|codex|premium|active" ;;
        gpt-5.3-codex)          echo "400|yes|yes|no|codex|standard|active" ;;
        gpt-5.3-codex-spark)    echo "128|yes|no|no|codex|standard|active" ;;
        gpt-5.2-codex)          echo "400|yes|yes|no|codex|standard|active" ;;
        gpt-5-codex-mini)       echo "400|yes|no|no|codex|budget|active" ;;
        gpt-5.1-codex-mini)     echo "400|yes|no|no|codex|budget|active" ;;
        gpt-5.1-codex-max)      echo "400|yes|yes|no|codex|standard|active" ;;
        # Reasoning models
        o3)                     echo "200|yes|no|yes|codex|premium|active" ;;
        o3-pro)                 echo "200|yes|no|yes|codex|premium|active" ;;
        o3-mini)                echo "200|yes|no|yes|codex|budget|active" ;;
        # Gemini
        gemini-3.1-pro-preview)   echo "1000|yes|yes|no|gemini|premium|active" ;;
        gemini-3-flash-preview) echo "1000|yes|no|no|gemini|budget|active" ;;
        gemini-3-pro-image-preview) echo "1000|yes|yes|no|gemini|premium|active" ;;
        # Claude
        claude-sonnet-4.6)      echo "200|yes|yes|no|claude|standard|active" ;;
        claude-opus-4.6)        echo "200|yes|yes|yes|claude|premium|active" ;;
        claude-opus-4.6-fast)   echo "200|yes|yes|yes|claude|premium|active" ;;
        # OpenRouter
        z-ai/glm-5)             echo "203|yes|no|no|openrouter|standard|active" ;;
        moonshotai/kimi-k2.5)   echo "262|yes|yes|no|openrouter|standard|active" ;;
        deepseek/deepseek-r1)   echo "164|yes|no|yes|openrouter|standard|active" ;;
        # Perplexity
        sonar-pro)              echo "128|no|no|no|perplexity|standard|active" ;;
        sonar)                  echo "128|no|no|no|perplexity|budget|active" ;;
        # GitHub Copilot (v9.8.0 - Issue #198)
        # Models accessed via GitHub Copilot API (bundled with subscription)
        copilot-premium)        echo "128|yes|yes|no|copilot|premium|active" ;;  # gpt-4.1 via Copilot
        copilot-fast)           echo "128|yes|no|yes|copilot|budget|active" ;;   # o3-mini via Copilot
        # Unknown
        *)                      echo "128|yes|no|no|unknown|standard|unknown" ;;
    esac
}

# Check if a model is known in the catalog
is_known_model() {
    local model="$1"
    local catalog
    catalog=$(get_model_catalog "$model")
    local status="${catalog##*|}"
    [[ "$status" != "unknown" ]]
}

# Get a specific capability from the catalog
# Usage: get_model_capability <model> <field>
# Fields: context_k, tools, images, reasoning, provider, tier, status
get_model_capability() {
    local model="$1"
    local field="$2"
    local catalog
    catalog=$(get_model_catalog "$model")

    case "$field" in
        context_k) echo "$catalog" | cut -d'|' -f1 ;;
        tools)     echo "$catalog" | cut -d'|' -f2 ;;
        images)    echo "$catalog" | cut -d'|' -f3 ;;
        reasoning) echo "$catalog" | cut -d'|' -f4 ;;
        provider)  echo "$catalog" | cut -d'|' -f5 ;;
        tier)      echo "$catalog" | cut -d'|' -f6 ;;
        status)    echo "$catalog" | cut -d'|' -f7 ;;
    esac
}

# List all known models for a provider, optionally filtered by capability
# Usage: list_models [provider] [--tools] [--images] [--reasoning] [--tier budget|standard|premium]
# Note: calls get_model_pricing() which remains in orchestrate.sh or lib/cost-tracking.sh
list_models() {
    local filter_provider="${1:-}"
    shift || true
    local require_tools="" require_images="" require_reasoning="" require_tier=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tools) require_tools="yes" ;;
            --images) require_images="yes" ;;
            --reasoning) require_reasoning="yes" ;;
            --tier) require_tier="${2:-}"; shift ;;
        esac
        shift
    done

    local -a all_models=(
        gpt-5.4 gpt-5.4-pro gpt-5.3-codex gpt-5.2-codex
        gpt-5-codex-mini gpt-5.1-codex-max
        o3 o3-pro o3-mini
        gemini-3.1-pro-preview gemini-3-flash-preview gemini-3-pro-image-preview
        claude-sonnet-4.6 claude-opus-4.6 claude-opus-4.6-fast
        z-ai/glm-5 moonshotai/kimi-k2.5 deepseek/deepseek-r1
        sonar-pro sonar
        copilot-premium copilot-fast
    )

    for model in "${all_models[@]}"; do
        local catalog
        catalog=$(get_model_catalog "$model")
        local ctx tools images reasoning provider tier status
        IFS='|' read -r ctx tools images reasoning provider tier status <<< "$catalog"

        # Apply filters
        [[ -n "$filter_provider" && "$provider" != "$filter_provider" ]] && continue
        [[ -n "$require_tools" && "$tools" != "yes" ]] && continue
        [[ -n "$require_images" && "$images" != "yes" ]] && continue
        [[ -n "$require_reasoning" && "$reasoning" != "yes" ]] && continue
        [[ -n "$require_tier" && "$tier" != "$require_tier" ]] && continue

        local pricing
        pricing=$(get_model_pricing "$model")
        local in_price="${pricing%%:*}"
        local out_price="${pricing##*:}"
        printf "%-25s %5sK  tools=%-3s img=%-3s rsn=%-3s  \$%s/\$%s MTok  [%s]\n" \
            "$model" "$ctx" "$tools" "$images" "$reasoning" "$in_price" "$out_price" "$tier"
    done
}
