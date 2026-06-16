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
        gpt-5.5)                echo "400|yes|yes|no|codex|premium|active" ;;
        gpt-5.5-pro)            echo "400|yes|yes|no|codex|premium|active" ;;
        gpt-5.4)                echo "400|yes|yes|no|codex|premium|active" ;;
        gpt-5.4-pro)            echo "400|yes|yes|no|codex|premium|active" ;;
        gpt-5.3-codex)          echo "400|yes|yes|no|codex|standard|active" ;;
        gpt-5.3-codex-spark)    echo "128|yes|no|no|codex|standard|active" ;;
        gpt-5.2-codex)          echo "400|yes|yes|no|codex|standard|active" ;;
        gpt-5.4-mini)           echo "400|yes|no|no|codex|budget|active" ;;
        gpt-5.1-codex-max)      echo "400|yes|yes|no|codex|standard|active" ;;
        # Reasoning models
        o3)                     echo "200|yes|no|yes|codex|premium|active" ;;
        o3-pro)                 echo "200|yes|no|yes|codex|premium|active" ;;
        o3-mini)                echo "200|yes|no|yes|codex|budget|active" ;;
        # Gemini
        gemini-3.1-pro-preview)   echo "1000|yes|yes|no|gemini|premium|active" ;;
        gemini-3.5-flash)       echo "1000|yes|no|no|gemini|budget|active" ;;   # GA fast (supersedes gemini-3-flash-preview)
        gemini-3.1-flash-lite)  echo "1000|yes|no|no|gemini|budget|active" ;;   # fastest/cheapest tier
        gemini-3-flash-preview) echo "1000|yes|no|no|gemini|budget|active" ;;
        gemini-3-pro-image-preview) echo "1000|yes|yes|no|gemini|premium|active" ;;  # image: shutdown 2026-06-25 (oco-803), migrate to Nano Banana Pro
        # Antigravity CLI (agy routes to the user's configured Antigravity default)
        agy/default|default)       echo "1000|yes|yes|no|agy|standard|active" ;;
        # Claude
        claude-sonnet-4.6)      echo "200|yes|yes|no|claude|standard|active" ;;
        claude-fable-5)         echo "1000|yes|yes|yes|claude|premium|active" ;;  # v9.44: Mythos-class, opt-in via OCTOPUS_OPUS_MODEL
        claude-opus-4.8)        echo "1000|yes|yes|yes|claude|premium|active" ;;
        claude-opus-4.7)        echo "1000|yes|yes|yes|claude|premium|legacy" ;;
        claude-opus-4.6)        echo "200|yes|yes|yes|claude|premium|legacy" ;;
        claude-opus-4.8-fast)   echo "1000|yes|yes|yes|claude|premium|active" ;;
        claude-opus-4.6-fast)   echo "200|yes|yes|yes|claude|premium|legacy" ;;
        # Cursor Agent (Grok via Cursor subscription)
        grok-4-20)              echo "200|yes|no|no|cursor-agent|standard|active" ;;
        grok-4-20-thinking)     echo "200|yes|no|yes|cursor-agent|premium|active" ;;
        composer-2-fast)        echo "200|yes|no|no|cursor-agent|standard|active" ;;
        composer-2)             echo "200|yes|no|no|cursor-agent|premium|active" ;;
        # OpenRouter
        z-ai/glm-5)             echo "203|yes|no|no|openrouter|standard|active" ;;
        moonshotai/kimi-k2.5)   echo "262|yes|yes|no|openrouter|standard|active" ;;
        deepseek/deepseek-r1-0528) echo "164|yes|no|yes|openrouter|standard|active" ;;
        # OpenCode (multi-provider router — models use opencode/<model> namespace)
        opencode/deepseek-v4-flash-free) echo "128|yes|no|no|opencode|budget|active" ;;
        opencode/gpt-5.4)       echo "400|yes|yes|no|opencode|premium|active" ;;
        opencode/gpt-5.4-mini)  echo "400|yes|no|no|opencode|budget|active" ;;
        opencode/glm-5.1)       echo "203|yes|no|no|opencode|standard|active" ;;
        # Perplexity
        sonar-pro)              echo "128|no|no|no|perplexity|standard|active" ;;
        sonar)                  echo "128|no|no|no|perplexity|budget|active" ;;
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
        gpt-5.5 gpt-5.5-pro gpt-5.4 gpt-5.4-pro gpt-5.3-codex gpt-5.2-codex
        gpt-5.4-mini gpt-5.1-codex-max
        o3 o3-pro o3-mini
        gemini-3.1-pro-preview gemini-3.5-flash gemini-3.1-flash-lite gemini-3-flash-preview gemini-3-pro-image-preview
        agy/default
        claude-sonnet-4.6 claude-fable-5 claude-opus-4.8 claude-opus-4.8-fast claude-opus-4.7 claude-opus-4.6 claude-opus-4.6-fast
        grok-4-20 grok-4-20-thinking composer-2-fast composer-2
        z-ai/glm-5 moonshotai/kimi-k2.5 deepseek/deepseek-r1-0528
        opencode/deepseek-v4-flash-free opencode/gpt-5.4 opencode/gpt-5.4-mini opencode/glm-5.1
        sonar-pro sonar
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
