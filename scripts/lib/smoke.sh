#!/usr/bin/env bash
# Claude Octopus â Provider Smoke Tests & Configuration
# Extracted from orchestrate.sh
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════════
# MULTI-PROVIDER SUBSCRIPTION-AWARE ROUTING (v4.8)
# Intelligent routing based on provider subscriptions, costs, and capabilities
# ═══════════════════════════════════════════════════════════════════════════════

PROVIDERS_CONFIG_FILE="${WORKSPACE_DIR:-$HOME/.claude-octopus}/.providers-config"

# Provider configuration variables (loaded from file)
PROVIDER_CODEX_INSTALLED="false"
PROVIDER_CODEX_AUTH_METHOD="none"
PROVIDER_CODEX_TIER="free"
PROVIDER_CODEX_COST_TIER="free"
PROVIDER_CODEX_PRIORITY=2

PROVIDER_GEMINI_INSTALLED="false"
PROVIDER_GEMINI_AUTH_METHOD="none"
PROVIDER_GEMINI_TIER="free"
PROVIDER_GEMINI_COST_TIER="free"
PROVIDER_GEMINI_PRIORITY=3

PROVIDER_CLAUDE_INSTALLED="false"
PROVIDER_CLAUDE_AUTH_METHOD="none"
PROVIDER_CLAUDE_TIER="pro"
PROVIDER_CLAUDE_COST_TIER="medium"
PROVIDER_CLAUDE_PRIORITY=1

PROVIDER_OPENCODE_INSTALLED="false"
PROVIDER_OPENCODE_AUTH_METHOD="none"
PROVIDER_OPENCODE_TIER="free"
PROVIDER_OPENCODE_COST_TIER="variable"
PROVIDER_OPENCODE_PRIORITY=4

PROVIDER_OPENROUTER_ENABLED="false"
PROVIDER_OPENROUTER_API_KEY_SET="false"
PROVIDER_OPENROUTER_ROUTING_PREF="default"
PROVIDER_OPENROUTER_PRIORITY=99

# Cost optimization strategy: cost-first, quality-first, balanced
COST_OPTIMIZATION_STRATEGY="balanced"

# CLI overrides for provider and routing
FORCE_PROVIDER=""
FORCE_COST_FIRST="false"
FORCE_QUALITY_FIRST="false"
OPENROUTER_ROUTING_OVERRIDE=""

# Provider capabilities matrix
# Format: provider:capability1,capability2,...

# Provider capabilities matrix
# Format: provider:capability1,capability2,...
get_provider_capabilities() {
    local provider="$1"
    case "$provider" in
        codex)
            echo "code,chat,review"
            ;;
        gemini)
            echo "code,chat,vision,long-context,analysis"
            ;;
        claude)
            echo "code,chat,analysis,long-context"
            ;;
        opencode)
            echo "code,chat,analysis"
            ;;
        openrouter)
            echo "code,chat,vision,analysis,long-context"
            ;;
        *)
            echo "general"
            ;;
    esac
}

# Get context limit for provider:tier combination
get_provider_context_limit() {
    local provider="$1"
    local tier="$2"

    case "$provider:$tier" in
        gemini:workspace|gemini:api-only)
            echo "2000000"  # 2M context
            ;;
        gemini:*)
            echo "1000000"  # 1M for free/google-one
            ;;
        claude:max-20x|claude:max-5x)
            echo "200000"
            ;;
        claude:*)
            echo "100000"
            ;;
        codex:pro|codex:api-only)
            echo "128000"
            ;;
        codex:*)
            echo "64000"
            ;;
        opencode:*)
            echo "128000"  # Varies by backend model (generic)
            ;;
        openrouter:*)
            echo "128000"  # Varies by model (generic)
            ;;
        openrouter-glm5:*)
            echo "203000"  # GLM-5: 203K context
            ;;
        openrouter-kimi:*)
            echo "262000"  # Kimi K2.5: 262K context
            ;;
        openrouter-deepseek:*)
            echo "164000"  # DeepSeek R1: 164K context
            ;;
        *)
            echo "32000"
            ;;
    esac
}

# Load provider configuration from file
# Performance optimized: Single-pass parsing (saves ~200-500ms vs grep|sed chains)
load_providers_config() {
    if [[ ! -f "$PROVIDERS_CONFIG_FILE" ]]; then
        [[ "$VERBOSE" == "true" ]] && log DEBUG "No providers config found at $PROVIDERS_CONFIG_FILE" || true
        # Auto-detect and populate defaults
        auto_detect_provider_config
        return 0
    fi

    # Performance: Single-pass YAML parsing (reads file once, no subprocesses)
    local current_provider=""
    local key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Detect provider section headers (e.g., "  codex:")
        if [[ "$line" =~ ^[[:space:]]*(codex|gemini|claude|opencode|openrouter): ]]; then
            current_provider="${BASH_REMATCH[1]}"
            continue
        fi

        # Detect cost_optimization section
        if [[ "$line" =~ ^cost_optimization: ]]; then
            current_provider="cost_optimization"
            continue
        fi

        # Parse key: value pairs (handles quoted values)
        if [[ "$line" =~ ^[[:space:]]+(installed|auth_method|subscription_tier|cost_tier|priority|enabled|api_key_set|routing_preference|strategy):[[:space:]]*(.+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Remove quotes from value
            value="${value//\"/}"
            value="${value// /}"  # Trim spaces

            # Assign to appropriate variable based on current provider
            case "$current_provider" in
                codex)
                    case "$key" in
                        installed) PROVIDER_CODEX_INSTALLED="$value" ;;
                        auth_method) PROVIDER_CODEX_AUTH_METHOD="$value" ;;
                        subscription_tier) PROVIDER_CODEX_TIER="$value" ;;
                        cost_tier) PROVIDER_CODEX_COST_TIER="$value" ;;
                        priority) PROVIDER_CODEX_PRIORITY="$value" ;;
                    esac
                    ;;
                gemini)
                    case "$key" in
                        installed) PROVIDER_GEMINI_INSTALLED="$value" ;;
                        auth_method) PROVIDER_GEMINI_AUTH_METHOD="$value" ;;
                        subscription_tier) PROVIDER_GEMINI_TIER="$value" ;;
                        cost_tier) PROVIDER_GEMINI_COST_TIER="$value" ;;
                        priority) PROVIDER_GEMINI_PRIORITY="$value" ;;
                    esac
                    ;;
                claude)
                    case "$key" in
                        installed) PROVIDER_CLAUDE_INSTALLED="$value" ;;
                        auth_method) PROVIDER_CLAUDE_AUTH_METHOD="$value" ;;
                        subscription_tier) PROVIDER_CLAUDE_TIER="$value" ;;
                        cost_tier) PROVIDER_CLAUDE_COST_TIER="$value" ;;
                        priority) PROVIDER_CLAUDE_PRIORITY="$value" ;;
                    esac
                    ;;
                opencode)
                    case "$key" in
                        installed) PROVIDER_OPENCODE_INSTALLED="$value" ;;
                        auth_method) PROVIDER_OPENCODE_AUTH_METHOD="$value" ;;
                        subscription_tier) PROVIDER_OPENCODE_TIER="$value" ;;
                        cost_tier) PROVIDER_OPENCODE_COST_TIER="$value" ;;
                        priority) PROVIDER_OPENCODE_PRIORITY="$value" ;;
                    esac
                    ;;
                openrouter)
                    case "$key" in
                        enabled) PROVIDER_OPENROUTER_ENABLED="$value" ;;
                        api_key_set) PROVIDER_OPENROUTER_API_KEY_SET="$value" ;;
                        routing_preference) PROVIDER_OPENROUTER_ROUTING_PREF="$value" ;;
                        priority) PROVIDER_OPENROUTER_PRIORITY="$value" ;;
                    esac
                    ;;
                cost_optimization)
                    case "$key" in
                        strategy) COST_OPTIMIZATION_STRATEGY="$value" ;;
                    esac
                    ;;
            esac
        fi
    done < "$PROVIDERS_CONFIG_FILE"

    # Apply defaults for any missing values
    PROVIDER_CODEX_INSTALLED="${PROVIDER_CODEX_INSTALLED:-false}"
    PROVIDER_CODEX_AUTH_METHOD="${PROVIDER_CODEX_AUTH_METHOD:-none}"
    PROVIDER_CODEX_TIER="${PROVIDER_CODEX_TIER:-free}"
    PROVIDER_CODEX_COST_TIER="${PROVIDER_CODEX_COST_TIER:-free}"
    PROVIDER_CODEX_PRIORITY="${PROVIDER_CODEX_PRIORITY:-2}"

    PROVIDER_GEMINI_INSTALLED="${PROVIDER_GEMINI_INSTALLED:-false}"
    PROVIDER_GEMINI_AUTH_METHOD="${PROVIDER_GEMINI_AUTH_METHOD:-none}"
    PROVIDER_GEMINI_TIER="${PROVIDER_GEMINI_TIER:-free}"
    PROVIDER_GEMINI_COST_TIER="${PROVIDER_GEMINI_COST_TIER:-free}"
    PROVIDER_GEMINI_PRIORITY="${PROVIDER_GEMINI_PRIORITY:-3}"

    PROVIDER_CLAUDE_INSTALLED="${PROVIDER_CLAUDE_INSTALLED:-false}"
    PROVIDER_CLAUDE_AUTH_METHOD="${PROVIDER_CLAUDE_AUTH_METHOD:-oauth}"
    PROVIDER_CLAUDE_TIER="${PROVIDER_CLAUDE_TIER:-pro}"
    PROVIDER_CLAUDE_COST_TIER="${PROVIDER_CLAUDE_COST_TIER:-medium}"
    PROVIDER_CLAUDE_PRIORITY="${PROVIDER_CLAUDE_PRIORITY:-1}"

    PROVIDER_OPENCODE_INSTALLED="${PROVIDER_OPENCODE_INSTALLED:-false}"
    PROVIDER_OPENCODE_AUTH_METHOD="${PROVIDER_OPENCODE_AUTH_METHOD:-none}"
    PROVIDER_OPENCODE_TIER="${PROVIDER_OPENCODE_TIER:-free}"
    PROVIDER_OPENCODE_COST_TIER="${PROVIDER_OPENCODE_COST_TIER:-variable}"
    PROVIDER_OPENCODE_PRIORITY="${PROVIDER_OPENCODE_PRIORITY:-4}"

    PROVIDER_OPENROUTER_ENABLED="${PROVIDER_OPENROUTER_ENABLED:-false}"
    PROVIDER_OPENROUTER_API_KEY_SET="${PROVIDER_OPENROUTER_API_KEY_SET:-false}"
    PROVIDER_OPENROUTER_ROUTING_PREF="${PROVIDER_OPENROUTER_ROUTING_PREF:-default}"
    PROVIDER_OPENROUTER_PRIORITY="${PROVIDER_OPENROUTER_PRIORITY:-99}"

    COST_OPTIMIZATION_STRATEGY="${COST_OPTIMIZATION_STRATEGY:-balanced}"

    [[ "$VERBOSE" == "true" ]] && log DEBUG "Loaded providers config: codex=$PROVIDER_CODEX_TIER, gemini=$PROVIDER_GEMINI_TIER, strategy=$COST_OPTIMIZATION_STRATEGY" || true
}

# Auto-detect provider configuration from installed CLIs and auth
auto_detect_provider_config() {
    local detected
    detected=$(detect_providers)

    # Process detected providers
    for entry in $detected; do
        local provider="${entry%%:*}"
        local auth="${entry##*:}"

        case "$provider" in
            codex)
                PROVIDER_CODEX_INSTALLED="true"
                PROVIDER_CODEX_AUTH_METHOD="$auth"
                # Detect tier via API test or fallback to auth-based default
                PROVIDER_CODEX_TIER=$(detect_tier_openai "$auth")
                PROVIDER_CODEX_COST_TIER=$(get_cost_tier_for_subscription "codex" "$PROVIDER_CODEX_TIER")
                ;;
            gemini)
                PROVIDER_GEMINI_INSTALLED="true"
                PROVIDER_GEMINI_AUTH_METHOD="$auth"
                # Detect tier via workspace check or fallback to auth-based default
                PROVIDER_GEMINI_TIER=$(detect_tier_gemini "$auth")
                PROVIDER_GEMINI_COST_TIER=$(get_cost_tier_for_subscription "gemini" "$PROVIDER_GEMINI_TIER")
                ;;
            claude)
                PROVIDER_CLAUDE_INSTALLED="true"
                PROVIDER_CLAUDE_AUTH_METHOD="$auth"
                # Detect tier (defaults to pro for Claude Code users)
                PROVIDER_CLAUDE_TIER=$(detect_tier_claude)
                PROVIDER_CLAUDE_COST_TIER=$(get_cost_tier_for_subscription "claude" "$PROVIDER_CLAUDE_TIER")
                ;;
            opencode)
                PROVIDER_OPENCODE_INSTALLED="true"
                PROVIDER_OPENCODE_AUTH_METHOD="$auth"
                PROVIDER_OPENCODE_TIER=$(detect_tier_opencode "$auth")
                PROVIDER_OPENCODE_COST_TIER=$(get_cost_tier_for_subscription "opencode" "$PROVIDER_OPENCODE_TIER")
                ;;
            openrouter)
                PROVIDER_OPENROUTER_ENABLED="true"
                PROVIDER_OPENROUTER_API_KEY_SET="true"
                ;;
        esac
    done

    [[ "$VERBOSE" == "true" ]] && log DEBUG "Auto-detected providers: $detected" || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# TIER DETECTION - Auto-detect subscription tiers via API calls (v4.8.3)
# ═══════════════════════════════════════════════════════════════════════════════

# Tier cache file location
TIER_CACHE_FILE="${WORKSPACE_DIR:-$HOME/.claude-octopus}/.tier-cache"
TIER_CACHE_TTL=86400  # 24 hours in seconds

# Check if tier cache is valid for a provider (not expired)
tier_cache_valid() {
    local provider="$1"
    [[ ! -f "$TIER_CACHE_FILE" ]] && return 1

    local cache_line
    cache_line=$(grep "^${provider}:" "$TIER_CACHE_FILE" 2>/dev/null || echo "")
    [[ -z "$cache_line" ]] && return 1

    local timestamp
    timestamp=$(echo "$cache_line" | cut -d: -f3)
    [[ -z "$timestamp" ]] && return 1

    local current_time age
    current_time=$(date +%s)
    age=$((current_time - timestamp))

    # Cache valid if less than TTL (24 hours)
    [[ $age -lt $TIER_CACHE_TTL ]] && return 0
    return 1
}

# Read tier from cache for a provider
tier_cache_read() {
    local provider="$1"
    local cache_line
    cache_line=$(grep "^${provider}:" "$TIER_CACHE_FILE" 2>/dev/null || echo "")

    if [[ -z "$cache_line" ]]; then
        echo ""
        return 1
    fi

    # Extract tier from format: provider:tier:timestamp
    local tier
    tier=$(echo "$cache_line" | cut -d: -f2)

    # Validate tier value (must be one of the expected values)
    case "$tier" in
        free|plus|pro|team|enterprise|api-only)
            echo "$tier"
            return 0
            ;;
        *)
            # Invalid or corrupted tier value
            [[ -n "$tier" ]] && log WARN "Invalid tier in cache for $provider: $tier"
            # Remove corrupted entry
            local temp_file
            temp_file=$(secure_tempfile "tier-cache")
            grep -v "^${provider}:" "$TIER_CACHE_FILE" > "$temp_file" 2>/dev/null || true
            mv "$temp_file" "$TIER_CACHE_FILE" 2>/dev/null || true
            return 1
            ;;
    esac
}

# Write tier to cache for a provider
tier_cache_write() {
    local provider="$1"
    local tier="$2"

    mkdir -p "$(dirname "$TIER_CACHE_FILE")"

    # Remove old entry if it exists
    if [[ -f "$TIER_CACHE_FILE" ]]; then
        grep -v "^${provider}:" "$TIER_CACHE_FILE" > "${TIER_CACHE_FILE}.tmp" 2>/dev/null || true
        mv "${TIER_CACHE_FILE}.tmp" "$TIER_CACHE_FILE" 2>/dev/null || true
    fi

    # Append new entry with current timestamp
    local timestamp
    timestamp=$(date +%s)
    echo "${provider}:${tier}:${timestamp}" >> "$TIER_CACHE_FILE"

    [[ "$VERBOSE" == "true" ]] && log DEBUG "Tier cached for $provider: $tier" || true
}

# Invalidate tier cache (call after config changes)
tier_cache_invalidate() {
    rm -f "$TIER_CACHE_FILE" 2>/dev/null || true
    [[ "$VERBOSE" == "true" ]] && log DEBUG "Tier cache invalidated" || true
}

# Detect OpenAI/Codex subscription tier via test API call
detect_tier_openai() {
    local auth_method="$1"
    local fallback_tier="api-only"

    # Check cache first
    if tier_cache_valid "codex"; then
        local cached_tier
        cached_tier=$(tier_cache_read "codex")
        if [[ -n "$cached_tier" ]]; then
            [[ "$VERBOSE" == "true" ]] && log DEBUG "Using cached Codex tier: $cached_tier" || true
            echo "$cached_tier"
            return 0
        fi
    fi

    # Set fallback based on auth method
    if [[ "$auth_method" == "oauth" ]]; then
        fallback_tier="plus"
    fi

    # Attempt API detection with minimal test call
    if command -v codex &>/dev/null; then
        local test_response
        # Use 5-second timeout for minimal "ok" prompt (3 tokens)
        test_response=$(run_with_timeout 5 codex exec --skip-git-repo-check "ok" 2>&1 || echo "")

        # Check for tier indicators in response
        # o3-mini/gpt-4 access suggests plus tier
        if [[ "$test_response" =~ (o3-mini|gpt-4|o1-preview) ]]; then
            tier_cache_write "codex" "plus"
            echo "plus"
            return 0
        # Rate limit or error suggests falling back to auth-based default
        elif [[ "$test_response" =~ (rate_limit|429|invalid|unauthorized) ]]; then
            [[ "$VERBOSE" == "true" ]] && log DEBUG "Codex API test failed, using fallback: $fallback_tier" || true
            tier_cache_write "codex" "$fallback_tier"
            echo "$fallback_tier"
            return 0
        fi
    fi

    # Default fallback
    tier_cache_write "codex" "$fallback_tier"
    echo "$fallback_tier"
    return 0
}

# Detect Gemini subscription tier via workspace domain check
detect_tier_gemini() {
    local auth_method="$1"
    local fallback_tier="api-only"

    # Check cache first
    if tier_cache_valid "gemini"; then
        local cached_tier
        cached_tier=$(tier_cache_read "gemini")
        if [[ -n "$cached_tier" ]]; then
            [[ "$VERBOSE" == "true" ]] && log DEBUG "Using cached Gemini tier: $cached_tier" || true
            echo "$cached_tier"
            return 0
        fi
    fi

    # Set fallback based on auth method
    if [[ "$auth_method" == "oauth" ]]; then
        fallback_tier="free"
    fi

    # Attempt workspace detection from OAuth settings
    if [[ -f "$HOME/.gemini/settings.json" ]]; then
        local settings_content
        settings_content=$(cat "$HOME/.gemini/settings.json" 2>/dev/null || echo "")

        # Check for workspace domain (non-gmail email suggests workspace)
        if [[ "$settings_content" =~ \"email\":\"[^\"]+@([^\"]+)\" ]]; then
            local domain="${BASH_REMATCH[1]}"
            if [[ "$domain" != "gmail.com" && "$domain" != "googlemail.com" ]]; then
                tier_cache_write "gemini" "workspace"
                echo "workspace"
                return 0
            fi
        fi
    fi

    # Default fallback
    tier_cache_write "gemini" "$fallback_tier"
    echo "$fallback_tier"
    return 0
}

# Detect Claude subscription tier (defaults to pro for Claude Code users)
detect_tier_claude() {
    # Check cache first
    if tier_cache_valid "claude"; then
        local cached_tier
        cached_tier=$(tier_cache_read "claude")
        if [[ -n "$cached_tier" ]]; then
            [[ "$VERBOSE" == "true" ]] && log DEBUG "Using cached Claude tier: $cached_tier" || true
            echo "$cached_tier"
            return 0
        fi
    fi

    # Default to "pro" for Claude Code users (most common)
    # Phase 3: Add usage API check if available
    local tier="pro"
    tier_cache_write "claude" "$tier"
    echo "$tier"
    return 0
}

# Detect OpenCode subscription tier via auth list
detect_tier_opencode() {
    local auth_method="$1"
    local fallback_tier="free"

    # Check cache first
    if tier_cache_valid "opencode"; then
        local cached_tier
        cached_tier=$(tier_cache_read "opencode")
        if [[ -n "$cached_tier" ]]; then
            [[ "$VERBOSE" == "true" ]] && log DEBUG "Using cached OpenCode tier: $cached_tier" || true
            echo "$cached_tier"
            return 0
        fi
    fi

    # OpenCode supports multiple backend providers; tier depends on configured backends
    if [[ "$auth_method" == "oauth" || "$auth_method" == "multi" ]]; then
        fallback_tier="free"
    elif [[ "$auth_method" == "api-key" ]]; then
        fallback_tier="api-only"
    fi

    tier_cache_write "opencode" "$fallback_tier"
    echo "$fallback_tier"
    return 0
}

# Save provider configuration to file
save_providers_config() {
    mkdir -p "$(dirname "$PROVIDERS_CONFIG_FILE")"

    cat > "$PROVIDERS_CONFIG_FILE" << EOF
version: "2.0"
created_at: "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
updated_at: "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"

# Multi-Provider Subscription-Aware Configuration (v4.8)
providers:
  codex:
    installed: $PROVIDER_CODEX_INSTALLED
    auth_method: "$PROVIDER_CODEX_AUTH_METHOD"
    subscription_tier: "$PROVIDER_CODEX_TIER"
    cost_tier: "$PROVIDER_CODEX_COST_TIER"
    priority: $PROVIDER_CODEX_PRIORITY

  gemini:
    installed: $PROVIDER_GEMINI_INSTALLED
    auth_method: "$PROVIDER_GEMINI_AUTH_METHOD"
    subscription_tier: "$PROVIDER_GEMINI_TIER"
    cost_tier: "$PROVIDER_GEMINI_COST_TIER"
    priority: $PROVIDER_GEMINI_PRIORITY

  claude:
    installed: $PROVIDER_CLAUDE_INSTALLED
    auth_method: "$PROVIDER_CLAUDE_AUTH_METHOD"
    subscription_tier: "$PROVIDER_CLAUDE_TIER"
    cost_tier: "$PROVIDER_CLAUDE_COST_TIER"
    priority: $PROVIDER_CLAUDE_PRIORITY

  opencode:
    installed: $PROVIDER_OPENCODE_INSTALLED
    auth_method: "$PROVIDER_OPENCODE_AUTH_METHOD"
    subscription_tier: "$PROVIDER_OPENCODE_TIER"
    cost_tier: "$PROVIDER_OPENCODE_COST_TIER"
    priority: $PROVIDER_OPENCODE_PRIORITY

  openrouter:
    enabled: $PROVIDER_OPENROUTER_ENABLED
    api_key_set: $PROVIDER_OPENROUTER_API_KEY_SET
    routing_preference: "$PROVIDER_OPENROUTER_ROUTING_PREF"
    priority: $PROVIDER_OPENROUTER_PRIORITY

cost_optimization:
  strategy: "$COST_OPTIMIZATION_STRATEGY"
EOF

    log INFO "Providers config saved to $PROVIDERS_CONFIG_FILE"
    tier_cache_invalidate  # Invalidate tier cache after config change
}

# Score a provider for a given task type and complexity
# Returns: 0-150 score (higher is better), or -1 if provider can't handle task
score_provider() {
    local provider="$1"
    local task_type="$2"
    local complexity="${3:-2}"
    local score=50  # Base score

    # Check if provider is available
    local is_available="false"
    local cost_tier=""
    local sub_tier=""
    local priority=50

    case "$provider" in
        codex)
            [[ "$PROVIDER_CODEX_INSTALLED" == "true" && "$PROVIDER_CODEX_AUTH_METHOD" != "none" ]] && is_available="true"
            cost_tier="$PROVIDER_CODEX_COST_TIER"
            sub_tier="$PROVIDER_CODEX_TIER"
            priority="$PROVIDER_CODEX_PRIORITY"
            ;;
        gemini)
            [[ "$PROVIDER_GEMINI_INSTALLED" == "true" && "$PROVIDER_GEMINI_AUTH_METHOD" != "none" ]] && is_available="true"
            cost_tier="$PROVIDER_GEMINI_COST_TIER"
            sub_tier="$PROVIDER_GEMINI_TIER"
            priority="$PROVIDER_GEMINI_PRIORITY"
            ;;
        claude)
            [[ "$PROVIDER_CLAUDE_INSTALLED" == "true" ]] && is_available="true"
            cost_tier="$PROVIDER_CLAUDE_COST_TIER"
            sub_tier="$PROVIDER_CLAUDE_TIER"
            priority="$PROVIDER_CLAUDE_PRIORITY"
            ;;
        opencode)
            [[ "$PROVIDER_OPENCODE_INSTALLED" == "true" && "$PROVIDER_OPENCODE_AUTH_METHOD" != "none" ]] && is_available="true"
            cost_tier="$PROVIDER_OPENCODE_COST_TIER"
            sub_tier="$PROVIDER_OPENCODE_TIER"
            priority="$PROVIDER_OPENCODE_PRIORITY"
            ;;
        openrouter)
            [[ "$PROVIDER_OPENROUTER_ENABLED" == "true" && "$PROVIDER_OPENROUTER_API_KEY_SET" == "true" ]] && is_available="true"
            cost_tier="pay-per-use"
            sub_tier="api-only"
            priority="$PROVIDER_OPENROUTER_PRIORITY"
            ;;
    esac

    if [[ "$is_available" != "true" ]]; then
        echo "-1"
        return
    fi

    # Check capability match
    local capabilities
    capabilities=$(get_provider_capabilities "$provider")
    local required_capability=""

    case "$task_type" in
        image)
            required_capability="vision"
            ;;
        research|design|copywriting)
            required_capability="analysis"
            ;;
        coding|review)
            required_capability="code"
            ;;
        *)
            required_capability="general"
            ;;
    esac

    # Vision tasks require vision capability
    if [[ "$required_capability" == "vision" && ! "$capabilities" =~ vision ]]; then
        echo "-1"
        return
    fi

    # Apply cost scoring based on strategy
    local cost_value
    cost_value=$(get_cost_tier_value "$cost_tier")

    local effective_strategy="$COST_OPTIMIZATION_STRATEGY"
    [[ "$FORCE_COST_FIRST" == "true" ]] && effective_strategy="cost-first"
    [[ "$FORCE_QUALITY_FIRST" == "true" ]] && effective_strategy="quality-first"

    case "$effective_strategy" in
        cost-first)
            # Heavily prefer cheaper options
            score=$((score + (5 - cost_value) * 15))  # free=+75, bundled=+60, low=+45, medium=+30, high=+15
            ;;
        quality-first)
            # Prefer higher-tier subscriptions
            case "$sub_tier" in
                max-20x|pro|workspace) score=$((score + 40)) ;;
                max-5x|plus|google-one) score=$((score + 25)) ;;
                free) score=$((score + 5)) ;;
                api-only) score=$((score + 20)) ;;  # API is still high quality
            esac
            ;;
        balanced|*)
            # Moderate preference for cost, with some quality bonus
            score=$((score + (5 - cost_value) * 8))  # free=+40, bundled=+32, etc.
            case "$sub_tier" in
                max-20x|pro|workspace) score=$((score + 15)) ;;
                max-5x|plus|google-one) score=$((score + 10)) ;;
            esac
            ;;
    esac

    # Complexity matching bonus
    case "$complexity" in
        3)  # Complex tasks prefer higher tiers
            case "$sub_tier" in
                max-20x|pro|workspace) score=$((score + 20)) ;;
                max-5x|plus|google-one) score=$((score + 10)) ;;
            esac
            ;;
        1)  # Trivial tasks prefer cheaper options
            case "$cost_tier" in
                free|bundled) score=$((score + 15)) ;;
            esac
            ;;
    esac

    # Special capability bonuses
    case "$task_type" in
        research)
            # Long context is valuable for research
            if [[ "$capabilities" =~ long-context ]]; then
                score=$((score + 15))
            fi
            ;;
        image)
            if [[ "$capabilities" =~ vision ]]; then
                score=$((score + 20))
            fi
            ;;
    esac

    # Apply priority penalty (lower priority number = higher preference)
    score=$((score - priority * 2))

    echo "$score"
}

# Select best provider for a task using scoring
# Returns: provider name (codex, gemini, claude, openrouter)
select_provider() {
    local task_type="$1"
    local complexity="${2:-2}"

    # Check for force override
    if [[ -n "$FORCE_PROVIDER" ]]; then
        echo "$FORCE_PROVIDER"
        return 0
    fi

    # Load config if needed
    [[ -z "$PROVIDER_CODEX_INSTALLED" || "$PROVIDER_CODEX_INSTALLED" == "false" ]] && load_providers_config

    local best_provider=""
    local best_score=-1

    for provider in codex gemini claude opencode openrouter; do
        local score
        score=$(score_provider "$provider" "$task_type" "$complexity")

        [[ "$VERBOSE" == "true" ]] && log DEBUG "Provider score: $provider = $score (task=$task_type, complexity=$complexity)" || true

        if [[ "$score" -gt "$best_score" ]]; then
            best_score="$score"
            best_provider="$provider"
        fi
    done

    if [[ -z "$best_provider" || "$best_score" -lt 0 ]]; then
        # No suitable provider found, return first available
        if [[ "$PROVIDER_CODEX_INSTALLED" == "true" && "$PROVIDER_CODEX_AUTH_METHOD" != "none" ]]; then
            echo "codex"
        elif [[ "$PROVIDER_GEMINI_INSTALLED" == "true" && "$PROVIDER_GEMINI_AUTH_METHOD" != "none" ]]; then
            echo "gemini"
        elif [[ "$PROVIDER_OPENROUTER_ENABLED" == "true" ]]; then
            echo "openrouter"
        else
            echo "codex"  # Default fallback
        fi
        return 1
    fi

    echo "$best_provider"
}

# Display provider status with subscription tiers
show_provider_status() {
    load_providers_config

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ${GREEN}PROVIDER STATUS${CYAN}                                              ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"

    # Codex
    local codex_status="${RED}✗${NC}"
    [[ "$PROVIDER_CODEX_INSTALLED" == "true" && "$PROVIDER_CODEX_AUTH_METHOD" != "none" ]] && codex_status="${GREEN}✓${NC}"
    echo -e "${CYAN}║${NC}  Codex/OpenAI:   $codex_status  [$PROVIDER_CODEX_AUTH_METHOD]  $PROVIDER_CODEX_TIER ($PROVIDER_CODEX_COST_TIER)  ${CYAN}║${NC}"

    # Gemini
    local gemini_status="${RED}✗${NC}"
    [[ "$PROVIDER_GEMINI_INSTALLED" == "true" && "$PROVIDER_GEMINI_AUTH_METHOD" != "none" ]] && gemini_status="${GREEN}✓${NC}"
    echo -e "${CYAN}║${NC}  Gemini:         $gemini_status  [$PROVIDER_GEMINI_AUTH_METHOD]  $PROVIDER_GEMINI_TIER ($PROVIDER_GEMINI_COST_TIER)  ${CYAN}║${NC}"

    # Claude
    local claude_status="${RED}✗${NC}"
    [[ "$PROVIDER_CLAUDE_INSTALLED" == "true" ]] && claude_status="${GREEN}✓${NC}"
    local agent_teams_info=""
    if [[ "$SUPPORTS_AGENT_TEAMS" == "true" ]]; then
        agent_teams_info="  [Agent Teams: available]"
    fi
    echo -e "${CYAN}║${NC}  Claude:         $claude_status  [$PROVIDER_CLAUDE_AUTH_METHOD]  $PROVIDER_CLAUDE_TIER ($PROVIDER_CLAUDE_COST_TIER)${agent_teams_info}  ${CYAN}║${NC}"

    # OpenCode
    local opencode_status="${RED}✗${NC}"
    [[ "$PROVIDER_OPENCODE_INSTALLED" == "true" && "$PROVIDER_OPENCODE_AUTH_METHOD" != "none" ]] && opencode_status="${GREEN}✓${NC}"
    echo -e "${CYAN}║${NC}  OpenCode:       $opencode_status  [$PROVIDER_OPENCODE_AUTH_METHOD]  $PROVIDER_OPENCODE_TIER ($PROVIDER_OPENCODE_COST_TIER)  ${CYAN}║${NC}"

    # OpenRouter
    local openrouter_status="${RED}✗${NC}"
    [[ "$PROVIDER_OPENROUTER_ENABLED" == "true" ]] && openrouter_status="${GREEN}✓${NC}"
    echo -e "${CYAN}║${NC}  OpenRouter:     $openrouter_status  [api-key]  $PROVIDER_OPENROUTER_ROUTING_PREF (pay-per-use)  ${CYAN}║${NC}"

    # Perplexity (v8.24.0)
    local perplexity_status="${RED}✗${NC}"
    [[ -n "${PERPLEXITY_API_KEY:-}" ]] && perplexity_status="${GREEN}✓${NC}"
    echo -e "${CYAN}║${NC}  Perplexity:     $perplexity_status  [api-key]  sonar-pro (pay-per-use)  ${CYAN}║${NC}"

    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Cost Strategy:  $COST_OPTIMIZATION_STRATEGY  ${CYAN}║${NC}"

    # v8.5: Show /fast mode and Opus mode status
    local fast_info=""
    if [[ "$USER_FAST_MODE" == "true" ]]; then
        fast_info="${YELLOW}⚡ ON${NC} (6x cost for lower latency)"
    else
        fast_info="${DIM}off${NC}"
    fi
    echo -e "${CYAN}║${NC}  /fast Mode:     $fast_info  ${CYAN}║${NC}"

    local opus_mode_info=""
    case "$OCTOPUS_OPUS_MODE" in
        fast)     opus_mode_info="${YELLOW}fast (forced)${NC}" ;;
        standard) opus_mode_info="${GREEN}standard (forced)${NC}" ;;
        auto)     opus_mode_info="${DIM}auto${NC}" ;;
    esac
    echo -e "${CYAN}║${NC}  Opus Mode:      $opus_mode_info  ${CYAN}║${NC}"

    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROVIDER SMOKE TEST (v8.19.0 - Issue #34)
# Fast parallel test that catches real provider failures before workflow starts
# ═══════════════════════════════════════════════════════════════════════════════

SMOKE_TEST_CACHE_FILE="${WORKSPACE_DIR:-$HOME/.claude-octopus}/.smoke-test-cache"

# Compute cache key from current model config (auto-invalidates on config change)
smoke_test_cache_key() {
    local codex_model gemini_model codex_sandbox gemini_sandbox
    codex_model=$(get_agent_model "codex" 2>/dev/null || echo "default")
    gemini_model=$(get_agent_model "gemini" 2>/dev/null || echo "default")
    codex_sandbox="${OCTOPUS_CODEX_SANDBOX:-workspace-write}"
    gemini_sandbox="${OCTOPUS_GEMINI_SANDBOX:-headless}"
    echo "${codex_model}:${gemini_model}:${codex_sandbox}:${gemini_sandbox}"
}

# Check if smoke test cache is still valid (same config, within TTL)
smoke_test_cache_valid() {
    [[ -f "$SMOKE_TEST_CACHE_FILE" ]] || return 1

    local cache_time cache_key cache_status current_time cache_age
    cache_time=$(head -1 "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || echo "0")
    cache_key=$(sed -n '2p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || echo "")
    cache_status=$(sed -n '3p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || echo "1")
    current_time=$(date +%s)
    cache_age=$((current_time - cache_time))

    # Invalid if expired or config changed
    [[ $cache_age -lt $PREFLIGHT_CACHE_TTL ]] || return 1
    [[ "$cache_key" == "$(smoke_test_cache_key)" ]] || return 1

    # Return cached status (0=passed, 1=failed)
    return "$cache_status"
}

# Write smoke test cache (stores timestamp, config key, and status)
smoke_test_cache_write() {
    local status="$1"
    mkdir -p "$(dirname "$SMOKE_TEST_CACHE_FILE")"
    {
        date +%s
        smoke_test_cache_key
        echo "$status"
    } > "$SMOKE_TEST_CACHE_FILE"
}

# Classify provider error from stderr output
_classify_smoke_error() {
    local stderr_output="$1"
    # Subshell isolates nocasematch — no leak risk on early exit
    (
        shopt -s nocasematch
        local _re_model='model.*not (found|available|exist)|does not exist|unknown model|invalid model|no such model|ModelNotFoundError|404'
        local _re_auth='auth|unauthorized|forbidden|401|403|invalid.*key|expired.*token|login required'
        local _re_rate='rate.?limit|429|too many requests|quota'
        local _re_policy='policy|blocked|safety|filtered|content.?filter|recitation'
        local _re_gitrepo='not inside a trusted directory|skip-git-repo-check|not a git repository'
        if [[ "$stderr_output" =~ $_re_gitrepo ]]; then
            echo "GIT_REPO_REQUIRED"
        elif [[ "$stderr_output" =~ $_re_model ]]; then
            echo "MODEL_NOT_FOUND"
        elif [[ "$stderr_output" =~ $_re_auth ]]; then
            echo "AUTH_FAILURE"
        elif [[ "$stderr_output" =~ $_re_rate ]]; then
            echo "RATE_LIMITED"
        elif [[ "$stderr_output" =~ $_re_policy ]]; then
            echo "POLICY_BLOCKED"
        else
            echo "UNKNOWN"
        fi
    )
}

# Display actionable error message for a smoke test failure
_display_smoke_test_error() {
    local provider="$1"
    local error_type="$2"
    local model="${3:-}"

    case "$error_type" in
        MODEL_NOT_FOUND)
            echo -e "  ${RED}✗${NC} ${provider}: Model '${model}' not available"
            if [[ "$provider" == "codex" ]]; then
                echo -e "    ${DIM}Fix: export OCTOPUS_CODEX_MODEL=gpt-5.4${NC}"
            else
                echo -e "    ${DIM}Fix: export OCTOPUS_GEMINI_MODEL=gemini-3.1-pro-preview${NC}"
            fi
            ;;
        AUTH_FAILURE)
            echo -e "  ${RED}✗${NC} ${provider}: Authentication failed"
            if [[ "$provider" == "codex" ]]; then
                echo -e "    ${DIM}Fix: codex login  OR  export OPENAI_API_KEY=\"sk-...\"${NC}"
            else
                echo -e "    ${DIM}Fix: gemini  (OAuth)  OR  export GEMINI_API_KEY=\"...\"${NC}"
            fi
            ;;
        RATE_LIMITED)
            echo -e "  ${YELLOW}⚠${NC} ${provider}: Rate limited (429). Wait and retry."
            ;;
        POLICY_BLOCKED)
            echo -e "  ${RED}✗${NC} ${provider}: Request blocked by policy"
            if [[ "$provider" == "gemini" ]]; then
                echo -e "    ${DIM}Fix: Check Gemini safety settings / API restrictions${NC}"
            else
                echo -e "    ${DIM}Fix: Check OpenAI usage policy / content filter settings${NC}"
            fi
            ;;
        TIMEOUT)
            echo -e "  ${YELLOW}⚠${NC} ${provider}: Smoke test timed out. Provider may be slow or down."
            ;;
        GIT_REPO_REQUIRED)
            echo -e "  ${YELLOW}⚠${NC} ${provider}: Requires a git repository (configuration issue, not a provider failure)"
            echo -e "    ${DIM}Fix: Run from a git repo or use 'codex exec --skip-git-repo-check'${NC}"
            ;;
        UNKNOWN)
            echo -e "  ${RED}✗${NC} ${provider}: Smoke test failed (unknown error)"
            echo -e "    ${DIM}Run with VERBOSE=true for details${NC}"
            ;;
    esac
}

# Test a single provider by sending a trivial prompt
_smoke_test_provider() {
    local provider="$1"
    local smoke_timeout="${2:-10}"
    local result_file="$3"
    local agent_type model cmd stderr_file exit_code

    # Determine agent type and get model
    case "$provider" in
        codex) agent_type="codex" ;;
        gemini) agent_type="gemini" ;;
        *) echo "SKIP" > "$result_file"; return 0 ;;
    esac

    model=$(get_agent_model "$agent_type" 2>/dev/null || echo "")
    stderr_file=$(secure_tempfile "smoke-stderr-${provider}")

    log DEBUG "Smoke test ${provider}: model=${model}"

    # Build and execute command with trivial prompt
    local cmd_str
    cmd_str=$(get_agent_command "$agent_type")

    if [[ -z "$cmd_str" ]]; then
        echo "SKIP" > "$result_file"
        return 0
    fi

    # Send trivial prompt with timeout
    local smoke_exit=0
    if [[ "$provider" == "codex" ]]; then
        # Codex requires a git repo — use a temp one to avoid false negatives (#202)
        local smoke_dir
        smoke_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'octo-smoke')
        git -C "$smoke_dir" init -q 2>/dev/null || true
        pushd "$smoke_dir" >/dev/null 2>&1
        # codex cmd_str ends with `-` (stdin prompt); arg form is rejected.
        echo "Reply with exactly: ok" | run_with_timeout "$smoke_timeout" \
            $cmd_str \
            >/dev/null 2>"$stderr_file" || smoke_exit=$?
        popd >/dev/null 2>&1
        rm -rf "$smoke_dir" 2>/dev/null
    else
        # Gemini: prompt via stdin with -p "" for headless trigger
        echo "Reply with exactly: ok" | run_with_timeout "$smoke_timeout" \
            $cmd_str -p "" \
            >/dev/null 2>"$stderr_file" || smoke_exit=$?
    fi

    if [[ $smoke_exit -eq 0 ]]; then
        echo "PASS" > "$result_file"
        log DEBUG "Smoke test ${provider}: passed"
    elif [[ $smoke_exit -eq 124 ]]; then
        # 124 = timeout exit code from GNU timeout / run_with_timeout
        echo "TIMEOUT:${model}" > "$result_file"
        log DEBUG "Smoke test ${provider}: timed out"
    else
        local error_type
        error_type=$(_classify_smoke_error "$(cat "$stderr_file" 2>/dev/null)")
        echo "${error_type}:${model}" > "$result_file"
        log DEBUG "Smoke test ${provider}: failed (${error_type})"
        [[ "$VERBOSE" == "true" ]] && cat "$stderr_file" >&2
    fi

    rm -f "$stderr_file" 2>/dev/null
}

# Orchestrate parallel smoke tests for all available providers
provider_smoke_test() {
    local force_check="${1:-false}"

    # Skip if user opted out
    if [[ "$SKIP_SMOKE_TEST" == "true" ]]; then
        log DEBUG "Smoke test: skipped (--skip-smoke-test)"
        return 0
    fi

    # Return cached result if valid (unless forced)
    if [[ "$force_check" != "true" ]] && smoke_test_cache_valid; then
        log DEBUG "Smoke test: using cached result (passed)"
        return 0
    fi

    log INFO "Running provider smoke test... 🐙"

    # Determine which providers are available (from preflight state)
    local has_codex=false has_gemini=false
    command -v codex &>/dev/null && has_codex=true
    command -v gemini &>/dev/null && has_gemini=true

    if [[ "$has_codex" == "false" && "$has_gemini" == "false" ]]; then
        log WARN "Smoke test: no providers to test"
        return 0
    fi

    # Launch parallel smoke tests
    local codex_result_file gemini_result_file
    codex_result_file=$(secure_tempfile "smoke-codex")
    gemini_result_file=$(secure_tempfile "smoke-gemini")
    local pids=()

    if [[ "$has_codex" == "true" ]]; then
        _smoke_test_provider "codex" "${OCTOPUS_CODEX_SMOKE_TIMEOUT:-45}" "$codex_result_file" &
        pids+=($!)
    else
        echo "SKIP" > "$codex_result_file"
    fi

    if [[ "$has_gemini" == "true" ]]; then
        _smoke_test_provider "gemini" "${OCTOPUS_GEMINI_SMOKE_TIMEOUT:-30}" "$gemini_result_file" &
        pids+=($!)
    else
        echo "SKIP" > "$gemini_result_file"
    fi

    # Wait for all background tests
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Collect results
    local codex_result gemini_result
    codex_result=$(cat "$codex_result_file" 2>/dev/null || echo "SKIP")
    gemini_result=$(cat "$gemini_result_file" 2>/dev/null || echo "SKIP")
    rm -f "$codex_result_file" "$gemini_result_file" 2>/dev/null

    local pass_count=0 fail_count=0 skip_count=0

    for result in "$codex_result" "$gemini_result"; do
        case "${result%%:*}" in
            PASS) ((++pass_count)) ;;
            SKIP) ((++skip_count)) ;;
            *) ((++fail_count)) ;;
        esac
    done

    # Display results
    if [[ $fail_count -gt 0 ]]; then
        echo ""
        if [[ "$codex_result" != "PASS" && "$codex_result" != "SKIP" ]]; then
            local codex_error="${codex_result%%:*}"
            local codex_model="${codex_result#*:}"
            _display_smoke_test_error "Codex" "$codex_error" "$codex_model"
        fi
        if [[ "$gemini_result" != "PASS" && "$gemini_result" != "SKIP" ]]; then
            local gemini_error="${gemini_result%%:*}"
            local gemini_model="${gemini_result#*:}"
            _display_smoke_test_error "Gemini" "$gemini_error" "$gemini_model"
        fi
        echo ""
    fi

    # Pass if at least one provider succeeds (consistent with v7.9.1 single-provider mode)
    if [[ $pass_count -gt 0 ]]; then
        if [[ $fail_count -gt 0 ]]; then
            log WARN "Smoke test: degraded mode ($pass_count/$((pass_count + fail_count)) providers passed)"
        else
            log INFO "Smoke test passed ($pass_count provider(s) verified)"
        fi
        smoke_test_cache_write "0"
        return 0
    fi

    # All providers failed
    log ERROR "Smoke test failed: no providers responded successfully"
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ❌ PROVIDER SMOKE TEST FAILED                                ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "No AI providers could process a test request."
    echo -e "This means workflows will produce ${YELLOW}empty results${NC}."
    echo ""
    echo -e "${DIM}Skip with: --skip-smoke-test  (not recommended)${NC}"
    echo -e "${DIM}Re-test:   bash orchestrate.sh doctor smoke${NC}"
    echo ""
    smoke_test_cache_write "1"
    return 1
}
