#!/usr/bin/env bash
# Helper: /octo:model-config (v3.0 — hardened in v8.49.0)
# Manages model configuration, phase routing, and session overrides.

set -eo pipefail

CONFIG_FILE="${HOME}/.claude-octopus/config/providers.json"
CACHE_FILE="/tmp/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/../lib/provider-allowlist.sh" 2>/dev/null || true

# Known providers and phases for validation
KNOWN_PROVIDERS="codex gemini agy claude perplexity openrouter opencode copilot ollama qwen cursor-agent vibe"
KNOWN_PHASES="discover define develop deliver quick debate review security research"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo -e "${CYAN}Usage:${NC} octo-model-config <command> [args]"
    echo ""
    echo "Commands:"
    echo "  list                        List current configuration"
    echo "  show phases                 Show phase routing table"
    echo "  set <provider> <model>      Set default model for a provider"
    echo "  route <phase> <target>      Route a phase to a specific model/capability"
    echo "  reset [provider|all]        Reset configuration to defaults"
    echo "  models [filter]             List all known models with capabilities"
    echo "  providers                   Show active provider allowlist"
    echo "  allow <providers...>        Allow only these providers (session by default)"
    echo "  enable <providers...>       Add providers to the active allowlist"
    echo "  disable <providers...>      Remove providers from the active allowlist"
    echo "  clear-allowlist             Clear the provider allowlist"
    echo "  verify                      Verify model accessibility"
    echo ""
    echo "Options:"
    echo "  --session                   Apply change only to current session"
    echo "  --force                     Allow custom/unrecognized provider names"
    echo ""
    echo "Environment Variables:"
    echo "  OCTOPUS_CODEX_MODEL         Override codex model (highest priority)"
    echo "  OCTOPUS_GEMINI_MODEL        Override gemini model"
    echo "  OCTOPUS_AGY_MODEL           Override Antigravity CLI model"
    echo "  OCTOPUS_CURSOR_AGENT_MODEL  Override cursor-agent model"
    echo "  OCTOPUS_COST_MODE           Set cost tier: budget, standard, premium"
    echo "  OCTO_ALLOWED_PROVIDERS      Override provider availability for this process"
    echo "  OCTOPUS_TRACE_MODELS=1      Debug model resolution precedence"
}

log_info() { echo -e "${GREEN}INFO:${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARN:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

# Ensure config file exists and is v3.0
ensure_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "3.0",
  "providers": {
    "codex": {
      "default": "gpt-5.4",
      "fallback": "gpt-5.4",
      "spark": "gpt-5.4",
      "mini": "gpt-5.4-mini",
      "reasoning": "o3",
      "large_context": "gpt-5.4"
    },
    "gemini": {
      "default": "gemini-3.1-pro-preview",
      "fallback": "gemini-3.5-flash",
      "flash": "gemini-3.5-flash",
      "image": "gemini-3-pro-image-preview"
    },
    "claude": {
      "default": "claude-sonnet-4.6",
      "opus": "claude-opus-4.8"
    },
    "perplexity": {
      "default": "sonar-pro",
      "fast": "sonar"
    },
    "opencode": {
      "default": "opencode/deepseek-v4-flash-free",
      "fast": "opencode/deepseek-v4-flash-free",
      "research": "opencode/glm-5.1"
    }
  },
  "routing": {
    "phases": {
      "deliver": "codex:default",
      "review": "codex:default",
      "security": "codex:reasoning",
      "research": "gemini:default"
    },
    "roles": {
      "researcher": "perplexity"
    }
  },
  "tiers": {
    "budget": { "codex": "mini", "gemini": "flash", "opencode": "fast" },
    "standard": { "codex": "default", "gemini": "default", "opencode": "default" },
    "premium": { "codex": "default", "gemini": "default", "opencode": "default" }
  },
  "overrides": {}
}
EOF
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq is not installed. Please install it (brew install jq or apt install jq)."
        exit 1
    fi
}

# v8.49.0: Validate model name for shell safety
validate_model() {
    local model="$1"
    [[ -z "$model" ]] && return 1
    # Reject shell metacharacters
    if [[ "$model" =~ [[:space:]\;\|\&\$\`\'\"()\<\>\!*?\[\]\{\}] ]]; then
        return 1
    fi
    [[ "$model" == /* ]] && return 1
    return 0
}

canonical_provider() {
    local provider
    provider="$(octo_normalize_provider_name "${1:-}")"
    case "$provider" in
        anthropic|sonnet) echo "claude" ;;
        openai) echo "codex" ;;
        google) echo "gemini" ;;
        cursor|xai) echo "cursor-agent" ;;
        local) echo "ollama" ;;
        *) echo "$provider" ;;
    esac
}

provider_known() {
    local provider="$1"
    echo "$KNOWN_PROVIDERS" | grep -qw "$provider"
}

unique_provider_list() {
    local seen="" out="" provider
    for provider in "$@"; do
        [[ -n "$provider" ]] || continue
        if [[ " $seen " == *" $provider "* ]]; then
            continue
        fi
        seen="${seen:+$seen }$provider"
        out="${out:+$out }$provider"
    done
    printf '%s\n' "$out"
}

parse_provider_args() {
    local providers=()
    local arg provider
    for arg in "$@"; do
        case "$arg" in
            --session|--global|--force) continue ;;
        esac
        provider="$(canonical_provider "$arg")"
        if ! provider_known "$provider"; then
            log_error "Unknown provider '$arg'. Valid: $KNOWN_PROVIDERS"
            exit 1
        fi
        providers+=("$provider")
    done

    if [[ ${#providers[@]} -eq 0 ]]; then
        log_error "At least one provider is required"
        exit 1
    fi

    unique_provider_list "${providers[@]}"
}

current_provider_allowlist_or_all() {
    local current
    if declare -f octo_provider_allowlist_value >/dev/null 2>&1; then
        current="$(octo_provider_allowlist_value)"
    else
        current="${OCTO_ALLOWED_PROVIDERS:-}"
    fi
    if [[ -z "$current" ]]; then
        printf '%s\n' "$KNOWN_PROVIDERS"
    else
        local providers=() token
        # shellcheck disable=SC2086 # Intentional word splitting: provider allowlist syntax.
        for token in ${current//,/ }; do
            providers+=("$(canonical_provider "$token")")
        done
        unique_provider_list "${providers[@]}"
    fi
}

allowlist_target_file() {
    local scope="$1"
    case "$scope" in
        global) octo_provider_allowlist_global_file ;;
        *) octo_provider_allowlist_session_file ;;
    esac
}

write_provider_allowlist() {
    local scope="$1"
    local providers="$2"
    local file
    file="$(allowlist_target_file "$scope")"
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$providers" > "$file"
    clear_cache
    log_info "Provider allowlist ($scope): ${providers:-none}"
    echo "  File: $file"
}

cmd_provider_allowlist() {
    local source="unset" value=""
    if declare -f octo_provider_allowlist_source >/dev/null 2>&1; then
        source="$(octo_provider_allowlist_source)"
        value="$(octo_provider_allowlist_value)"
    else
        value="${OCTO_ALLOWED_PROVIDERS:-}"
        [[ -n "$value" ]] && source="env:OCTO_ALLOWED_PROVIDERS"
    fi

    echo -e "${CYAN}Provider Allowlist${NC}"
    echo "----------------------------------------"
    echo "  Source: $source"
    if [[ -z "$value" ]]; then
        echo "  Allowed: all providers"
    else
        echo "  Allowed: $(unique_provider_list ${value//,/ })"
    fi
    echo ""
    echo "  Session command examples:"
    echo "    octo-model-config allow claude gemini --session"
    echo "    octo-model-config disable codex --session"
    echo "    octo-model-config clear-allowlist --session"
}

cmd_allow() {
    local scope="session" arg
    for arg in "$@"; do
        [[ "$arg" == "--global" ]] && scope="global"
    done
    local providers
    providers="$(parse_provider_args "$@")"
    write_provider_allowlist "$scope" "$providers"
}

cmd_enable() {
    local scope="session" arg
    for arg in "$@"; do
        [[ "$arg" == "--global" ]] && scope="global"
    done
    local existing add merged
    existing="$(current_provider_allowlist_or_all)"
    add="$(parse_provider_args "$@")"
    merged="$(unique_provider_list $existing $add)"
    write_provider_allowlist "$scope" "$merged"
}

cmd_disable() {
    local scope="session" arg
    for arg in "$@"; do
        [[ "$arg" == "--global" ]] && scope="global"
    done

    local existing remove keep="" token blocked should_remove
    existing="$(current_provider_allowlist_or_all)"
    remove="$(parse_provider_args "$@")"

    for token in $existing; do
        should_remove=false
        for blocked in $remove; do
            if [[ "$token" == "$blocked" ]]; then
                should_remove=true
                break
            fi
        done
        [[ "$should_remove" == "true" ]] && continue
        keep="${keep:+$keep }$token"
    done

    write_provider_allowlist "$scope" "$keep"
}

cmd_clear_allowlist() {
    local scope="session" arg
    for arg in "$@"; do
        [[ "$arg" == "--global" ]] && scope="global"
    done
    local file
    file="$(allowlist_target_file "$scope")"
    rm -f "$file"
    clear_cache
    log_info "Cleared provider allowlist ($scope)"
    echo "  File: $file"
}

# v8.49.0: Invalidate model resolution cache after config changes
clear_cache() {
    rm -f "$CACHE_FILE"
}

cmd_list() {
    ensure_config
    echo -e "${CYAN}Current Model Configuration (v3.0)${NC}"
    echo "----------------------------------------"

    # Environment overrides
    echo -e "\n${YELLOW}Environment Overrides:${NC}"
    local has_env=false
    for var in OCTOPUS_CODEX_MODEL OCTOPUS_GEMINI_MODEL OCTOPUS_AGY_MODEL OCTOPUS_CURSOR_AGENT_MODEL OCTOPUS_PERPLEXITY_MODEL OCTOPUS_OPENCODE_MODEL OCTOPUS_COST_MODE OCTO_ALLOWED_PROVIDERS OCTOPUS_TRACE_MODELS; do
        if [[ -n "${!var:-}" ]]; then
            echo "  $var=${!var}"
            has_env=true
        fi
    done
    [[ "$has_env" == "false" ]] && echo "  (none)"

    # Providers
    echo -e "\n${YELLOW}Providers:${NC}"
    jq -r '.providers | to_entries[] | "  \(.key): \(.value.default // "n/a") (fallback: \(.value.fallback // "n/a"))"' "$CONFIG_FILE"

    # Phase routing
    echo -e "\n${YELLOW}Phase Routing:${NC}"
    local phases
    phases=$(jq -r '.routing.phases // {} | to_entries[] | "  \(.key) → \(.value)"' "$CONFIG_FILE" 2>/dev/null || true)
    if [[ -z "$phases" ]]; then echo "  (none — using defaults)"; else echo "$phases"; fi

    # Role routing
    echo -e "\n${YELLOW}Role Routing:${NC}"
    local roles
    roles=$(jq -r '.routing.roles // {} | to_entries[] | "  \(.key) → \(.value)"' "$CONFIG_FILE" 2>/dev/null || true)
    if [[ -z "$roles" ]]; then echo "  (none)"; else echo "$roles"; fi

    # Cost mode
    echo -e "\n${YELLOW}Cost Mode:${NC}"
    echo "  ${OCTOPUS_COST_MODE:-standard} (set via OCTOPUS_COST_MODE env var)"

    # Provider allowlist
    echo -e "\n${YELLOW}Provider Allowlist:${NC}"
    local allowlist_source allowlist_value
    if declare -f octo_provider_allowlist_source >/dev/null 2>&1; then
        allowlist_source="$(octo_provider_allowlist_source)"
        allowlist_value="$(octo_provider_allowlist_value)"
    else
        allowlist_source="env"
        allowlist_value="${OCTO_ALLOWED_PROVIDERS:-}"
    fi
    echo "  Source: $allowlist_source"
    if [[ -z "$allowlist_value" ]]; then
        echo "  Allowed: all providers"
    else
        echo "  Allowed: $(unique_provider_list ${allowlist_value//,/ })"
    fi

    # Session overrides
    echo -e "\n${YELLOW}Session Overrides:${NC}"
    local overrides
    overrides=$(jq -r '.overrides // {} | to_entries[] | "  \(.key): \(.value)"' "$CONFIG_FILE" 2>/dev/null || true)
    if [[ -z "$overrides" ]]; then echo "  (none)"; else echo "$overrides"; fi

    # Config version
    echo -e "\n${YELLOW}Config:${NC}"
    echo "  File: $CONFIG_FILE"
    echo "  Version: $(jq -r '.version // "unknown"' "$CONFIG_FILE")"
    echo "  Trace: ${OCTOPUS_TRACE_MODELS:-off} (set OCTOPUS_TRACE_MODELS=1 to debug)"
}

cmd_show_phases() {
    ensure_config
    echo -e "${CYAN}Phase Routing Configuration${NC}"
    echo "─────────────────────────────────────────────────"
    printf "  %-12s %-25s %s\n" "Phase" "Model/Target" "Source"
    echo "  ────────────────────────────────────────────────"

    for phase in $KNOWN_PHASES; do
        local target
        target=$(jq -r --arg p "$phase" '.routing.phases[$p] // empty' "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$target" ]]; then
            printf "  %-12s %-25s %s\n" "$phase" "$target" "(configured)"
        else
            local default_target="codex:default"
            case "$phase" in
                deliver|review|quick) default_target="codex:spark" ;;
                security) default_target="codex:reasoning" ;;
                research) default_target="gemini:default" ;;
            esac
            printf "  %-12s %-25s %s\n" "$phase" "$default_target" "(default)"
        fi
    done
}

cmd_verify() {
    ensure_config
    log_info "Verifying model accessibility..."

    local errors=0
    for cli in codex gemini claude opencode; do
        if command -v "$cli" &>/dev/null; then
            local model
            model=$(jq -r --arg p "$cli" '.providers[$p].default // "n/a"' "$CONFIG_FILE")
            log_info "$cli: Found CLI. Default model: $model"
        else
            log_warn "$cli: CLI not found in PATH."
            ((errors++)) || true
        fi
    done

    if [[ $errors -eq 0 ]]; then
        log_info "Verification complete. All configured CLIs are available."
    else
        log_warn "Verification complete with $errors warnings."
    fi
}

cmd_set() {
    local provider_arg="$1"
    local model="$2"
    local session=false
    local force=false
    local provider="$provider_arg"
    local capability=""

    # Parse dot syntax: provider.capability (e.g., opencode.research)
    if [[ "$provider_arg" == *.* ]]; then
        provider="${provider_arg%%.*}"
        capability="${provider_arg#*.}"
    fi

    for arg in "${@:3}"; do
        [[ "$arg" == "--session" ]] && session=true
        [[ "$arg" == "--force" ]] && force=true
    done

    [[ -z "$provider" || -z "$model" ]] && { usage; exit 1; }

    # v8.49.0: Provider whitelist validation
    if ! echo "$KNOWN_PROVIDERS" | grep -qw "$provider"; then
        if [[ "$force" != "true" ]]; then
            log_error "Unknown provider '$provider'. Valid: $KNOWN_PROVIDERS"
            echo "  Use --force to set a custom provider (e.g., for local proxies)" >&2
            exit 1
        fi
    fi

    # v8.49.0: Model name validation
    if ! validate_model "$model"; then
        log_error "Invalid model name: '$model'"
        echo "  Model names must not contain shell metacharacters" >&2
        exit 1
    fi

    ensure_config

    # v8.49.0: Use jq --arg for injection safety
    if [[ -n "$capability" ]]; then
        jq --arg p "$provider" --arg c "$capability" --arg m "$model" \
            '.providers[$p][$c] = $m' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
        log_info "Set capability model: ${provider}.${capability} → $model"
    elif [[ "$session" == "true" ]]; then
        jq --arg p "$provider" --arg m "$model" '.overrides[$p] = $m' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
        log_info "Set session override: $provider → $model"
    else
        jq --arg p "$provider" --arg m "$model" '.providers[$p].default = $m' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
        log_info "Set default model: $provider → $model"
    fi
    clear_cache
}

cmd_route() {
    local phase="$1"
    local target="$2"

    [[ -z "$phase" || -z "$target" ]] && { usage; exit 1; }

    # v8.49.0: Validate phase name
    if ! echo "$KNOWN_PHASES" | grep -qw "$phase"; then
        log_error "Unknown phase '$phase'. Valid phases: $KNOWN_PHASES"
        exit 1
    fi

    if ! validate_model "$target"; then
        log_error "Invalid target: '$target'"
        exit 1
    fi

    ensure_config
    # v8.49.0: Use jq --arg for injection safety
    jq --arg p "$phase" --arg t "$target" '.routing.phases[$p] = $t' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
    log_info "Routed phase '$phase' → '$target'"
    clear_cache
}

cmd_models() {
    local filter="${1:-}"
    echo -e "${CYAN}Model Catalog${NC}"
    echo "───────────────────────────────────────────────────────────────────────────"
    printf "  %-24s %-8s %-6s %-6s %-5s %-10s %-8s %s\n" "Model" "Ctx(K)" "Tools" "Image" "Reas" "Provider" "Tier" "Status"
    echo "  ───────────────────────────────────────────────────────────────────────────"

    # Inline catalog (matches orchestrate.sh get_model_catalog)
    local -a models=(
        "gpt-5.4|400|yes|yes|no|codex|standard|active"
        "gpt-5.4-pro|400|yes|yes|no|codex|premium|active"
        "gpt-5.3-codex|400|yes|yes|no|codex|standard|active"
        "gpt-5.2-codex|400|yes|yes|no|codex|standard|active"
        "gpt-5.4-mini|400|yes|no|no|codex|budget|active"
        "gpt-5.1-codex-max|400|yes|yes|no|codex|premium|active"
        "o3|200|yes|no|yes|codex|premium|active"
        "o3-mini|200|yes|no|yes|codex|budget|active"
        "gemini-3.1-pro-preview|1000|yes|yes|no|gemini|premium|active"
        "gemini-3.5-flash|1000|yes|no|no|gemini|standard|active"
        "gemini-3.1-flash-lite|1000|yes|no|no|gemini|budget|active"
        "gemini-3-flash-preview|1000|yes|no|no|gemini|budget|legacy"
        "gemini-3-pro-image-preview|1000|yes|yes|no|gemini|premium|legacy"
        "claude-sonnet-4.6|200|yes|yes|no|claude|standard|active"
        "claude-opus-4.8|1000|yes|yes|yes|claude|premium|active"
        "claude-opus-4.7|1000|yes|yes|yes|claude|premium|legacy"
        "claude-opus-4.6|200|yes|yes|yes|claude|premium|legacy"
        "grok-4-20|200|yes|no|no|cursor-agent|standard|active"
        "grok-4-20-thinking|200|yes|no|yes|cursor-agent|premium|active"
        "composer-2-fast|200|yes|no|no|cursor-agent|standard|active"
        "composer-2|200|yes|no|no|cursor-agent|premium|active"
        "sonar-pro|128|no|no|no|perplexity|standard|active"
        "sonar|128|no|no|no|perplexity|budget|active"
        "z-ai/glm-5|203|yes|no|no|openrouter|standard|active"
        "moonshotai/kimi-k2.5|262|yes|yes|no|openrouter|standard|active"
        "deepseek/deepseek-r1-0528|164|yes|no|yes|openrouter|standard|active"
        "opencode/deepseek-v4-flash-free|128|yes|no|no|opencode|budget|active"
        "opencode/gpt-5.4|400|yes|yes|no|opencode|premium|active"
        "opencode/gpt-5.4-mini|400|yes|no|no|opencode|budget|active"
        "opencode/glm-5.1|203|yes|no|no|opencode|standard|active"
    )

    for entry in "${models[@]}"; do
        local name ctx tools images reasoning provider tier status
        IFS='|' read -r name ctx tools images reasoning provider tier status <<< "$entry"

        # Apply filter
        if [[ -n "$filter" ]]; then
            case "$filter" in
                --tools)     [[ "$tools" != "yes" ]] && continue ;;
                --images)    [[ "$images" != "yes" ]] && continue ;;
                --reasoning) [[ "$reasoning" != "yes" ]] && continue ;;
                --budget)    [[ "$tier" != "budget" ]] && continue ;;
                --premium)   [[ "$tier" != "premium" ]] && continue ;;
                *)           echo "$name" | grep -qi "$filter" || continue ;;
            esac
        fi

        printf "  %-24s %-8s %-6s %-6s %-5s %-10s %-8s %s\n" \
            "$name" "${ctx}K" "$tools" "$images" "$reasoning" "$provider" "$tier" "$status"
    done
    echo ""
    echo "  Filters: --tools, --images, --reasoning, --budget, --premium, or text search"
}

cmd_reset() {
    local provider="${1:-all}"
    if [[ "$provider" == "all" ]]; then
        rm -f "$CONFIG_FILE"
        ensure_config
        log_info "Reset all configuration to defaults"
    else
        ensure_config
        jq --arg p "$provider" 'del(.providers[$p]) | del(.overrides[$p])' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
        log_info "Reset configuration for provider: $provider"
    fi
    clear_cache
}

# Main
COMMAND="${1:-list}"
shift || true

case "$COMMAND" in
    list) cmd_list ;;
    show)
        case "${1:-}" in
            phases) cmd_show_phases ;;
            *) cmd_list ;;
        esac
        ;;
    set) cmd_set "$@" ;;
    route) cmd_route "$@" ;;
    reset) cmd_reset "$@" ;;
    models) cmd_models "$@" ;;
    providers|allowlist) cmd_provider_allowlist ;;
    allow|set-allowlist) cmd_allow "$@" ;;
    enable) cmd_enable "$@" ;;
    disable|block) cmd_disable "$@" ;;
    clear-allowlist|reset-allowlist) cmd_clear_allowlist "$@" ;;
    verify) cmd_verify ;;
    help|--help|-h) usage ;;
    *) usage; exit 1 ;;
esac
