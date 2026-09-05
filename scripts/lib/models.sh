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
        gpt-6-astra)            echo "1050|yes|yes|yes|codex|premium|limited" ;;
        gpt-5.6|gpt-5.6-sol)    echo "1050|yes|yes|yes|codex|premium|active" ;;
        gpt-5.6-terra)          echo "1050|yes|yes|yes|codex|standard|active" ;;
        gpt-5.6-luna)           echo "1050|yes|yes|yes|codex|budget|active" ;;
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
        # Antigravity CLI (agy routes to the user's configured Antigravity default)
        agy/default|default)       echo "1000|yes|yes|no|agy|standard|active" ;;
        # GitHub Copilot CLI service-owned automatic model selection. Cursor CLI
        # shares the bare `auto` ID (its own service-side pick); pricing is
        # provider-aware so the cursor-agent route still bills as subscription.
        auto)                      echo "128|yes|no|no|copilot|standard|active" ;;
        # Claude
        claude-haiku-4.5)      echo "200|yes|yes|yes|claude|budget|active" ;;
        claude-sonnet-5)       echo "1000|yes|yes|yes|claude|standard|active" ;;
        claude-sonnet-4.6)      echo "200|yes|yes|no|claude|standard|active" ;;
        claude-fable-5-1)       echo "1000|yes|yes|yes|claude|premium|active" ;;
        claude-fable-5)         echo "1000|yes|yes|yes|claude|premium|active" ;;  # v9.44: Mythos-class, opt-in via OCTOPUS_OPUS_MODEL
        claude-opus-5)          echo "1000|yes|yes|yes|claude|premium|active" ;;
        claude-opus-5-fast)     echo "1000|yes|yes|yes|claude|premium|active" ;;
        claude-opus-4.8)        echo "1000|yes|yes|yes|claude|premium|active" ;;
        claude-opus-4.7)        echo "1000|yes|yes|yes|claude|premium|legacy" ;;
        claude-opus-4.6)        echo "200|yes|yes|yes|claude|premium|legacy" ;;
        claude-opus-4.8-fast)   echo "1000|yes|yes|yes|claude|premium|active" ;;
        claude-opus-4.6-fast)   echo "200|yes|yes|yes|claude|premium|legacy" ;;
        # Cursor CLI (`agent`) — Cursor subscription catalog. Curated subset of
        # `agent models`; any other flat ID from that list is accepted as a pin.
        composer-2.5)                    echo "200|yes|no|no|cursor-agent|standard|active" ;;
        composer-2.5-fast)               echo "200|yes|no|no|cursor-agent|standard|active" ;;
        cursor-grok-4.6-high)            echo "200|yes|no|yes|cursor-agent|standard|active" ;;
        cursor-grok-4.6-xhigh)           echo "200|yes|no|yes|cursor-agent|premium|active" ;;
        gpt-5.6-sol-high)                echo "1000|yes|yes|yes|cursor-agent|premium|active" ;;
        gpt-5.6-luna-high)               echo "1000|yes|yes|yes|cursor-agent|budget|active" ;;
        claude-sonnet-5-thinking-high)   echo "1000|yes|yes|yes|cursor-agent|standard|active" ;;
        claude-opus-5-thinking-high)     echo "1000|yes|yes|yes|cursor-agent|premium|active" ;;
        gemini-3.7-flash-high)           echo "1000|yes|yes|yes|cursor-agent|budget|active" ;;
        # OpenRouter
        z-ai/glm-5)             echo "203|yes|no|no|openrouter|standard|active" ;;
        moonshotai/kimi-k2.5)   echo "262|yes|yes|no|openrouter|standard|active" ;;
        deepseek/deepseek-v4-pro)  echo "1000|yes|no|yes|openrouter|standard|active" ;;
        deepseek/deepseek-r1-0528) echo "164|yes|no|yes|openrouter|standard|legacy" ;;
        # OrcaRouter (gateway exposes anthropic/* namespace)
        anthropic/claude-sonnet-4.6) echo "1000|yes|yes|no|orcarouter|standard|active" ;;
        anthropic/claude-opus-4.8)   echo "1000|yes|yes|yes|orcarouter|premium|active" ;;
        anthropic/claude-haiku-4.5)  echo "200|yes|yes|yes|orcarouter|budget|active" ;;
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

# Return routing policy metadata separate from the fixed seven-field capability
# catalog so existing catalog consumers remain compatible.
# Format: selection_policy|auto_eligible|max_auto_dispatches|max_escalated_dispatches|availability
get_model_policy() {
    local model="$1"
    case "$model" in
        claude-fable-5-1) echo "explicit|no|0|1|general" ;;
        claude-fable-5)   echo "explicit|no|0|0|general" ;;
        gpt-6-astra)      echo "explicit|no|0|0|limited" ;;
        *)
            if [[ "$(get_model_catalog "$model")" == *"|unknown" ]]; then
                echo "explicit|no|0|0|unknown"
            else
                echo "automatic|yes|unlimited|unlimited|general"
            fi
            ;;
    esac
}

# Automatic selectors can use this policy gate before admitting a model. Explicit
# pins remain valid even when a model is ineligible for defaults or fallbacks.
octo_model_auto_eligible() {
    local policy
    policy="$(get_model_policy "$1")"
    [[ "$(printf '%s\n' "$policy" | cut -d'|' -f2)" == "yes" ]]
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

# Print every canonical model ID, one per line. Consumers such as model-config
# must use this instead of maintaining another hand-written catalog.
octo_model_ids() {
    cat <<'EOF'
gpt-6-astra
gpt-5.6-sol
gpt-5.6-terra
gpt-5.6-luna
gpt-5.5
gpt-5.5-pro
gpt-5.4
gpt-5.4-pro
gpt-5.3-codex
gpt-5.3-codex-spark
gpt-5.2-codex
gpt-5.4-mini
gpt-5.1-codex-max
o3
o3-pro
o3-mini
agy/default
auto
claude-haiku-4.5
claude-sonnet-5
claude-sonnet-4.6
claude-fable-5-1
claude-fable-5
claude-opus-5
claude-opus-5-fast
claude-opus-4.8
claude-opus-4.8-fast
claude-opus-4.7
claude-opus-4.6
claude-opus-4.6-fast
composer-2.5
composer-2.5-fast
cursor-grok-4.6-high
cursor-grok-4.6-xhigh
gpt-5.6-sol-high
gpt-5.6-luna-high
claude-sonnet-5-thinking-high
claude-opus-5-thinking-high
gemini-3.7-flash-high
z-ai/glm-5
moonshotai/kimi-k2.5
deepseek/deepseek-v4-pro
deepseek/deepseek-r1-0528
opencode/deepseek-v4-flash-free
opencode/gpt-5.4
opencode/gpt-5.4-mini
opencode/glm-5.1
sonar-pro
sonar
EOF
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

    local model
    while IFS= read -r model; do
        [[ -n "$model" ]] || continue
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

        local pricing policy selection
        pricing=$(get_model_pricing "$model")
        policy=$(get_model_policy "$model")
        selection="${policy%%|*}"
        local in_price="${pricing%%:*}"
        local out_price="${pricing##*:}"
        printf "%-25s %5sK  tools=%-3s img=%-3s rsn=%-3s  \$%s/\$%s MTok  [%s; %s]\n" \
            "$model" "$ctx" "$tools" "$images" "$reasoning" "$in_price" "$out_price" "$tier" "$selection"
    done < <(octo_model_ids)
}
