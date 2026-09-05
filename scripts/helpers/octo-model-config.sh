#!/usr/bin/env bash
# Helper: /octo:model-config (v3.0 — hardened in v8.49.0)
# Manages model configuration, phase routing, and session overrides.

set -eo pipefail

CONFIG_FILE="${HOME}/.claude-octopus/config/providers.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/../lib/provider-allowlist.sh" || { echo "ERROR: failed to load provider-allowlist.sh" >&2; exit 1; }
source "${SCRIPT_DIR}/../lib/provider-registry.sh" || { echo "ERROR: failed to load provider-registry.sh" >&2; exit 1; }
source "${SCRIPT_DIR}/../lib/models.sh" || { echo "ERROR: failed to load models.sh" >&2; exit 1; }
source "${SCRIPT_DIR}/../lib/model-cache-path.sh" 2>/dev/null || true
# Must match the path lib/model-resolver.sh writes; this was hardcoded to /tmp
# while the resolver honoured $TMPDIR, so `clear_cache` was a no-op on macOS.
if declare -f octo_model_cache_file >/dev/null 2>&1; then
    CACHE_FILE="$(octo_model_cache_file 2>/dev/null || true)"
else
    CACHE_FILE="${TMPDIR:-/tmp}/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
fi

# Known providers and phases for validation
KNOWN_PROVIDERS="$(octo_provider_ids model-config)"
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
    echo "  show roles                  Show role routing override table"
    echo "  set <provider> <model>      Set default model for a provider"
    echo "  route <phase> <target>      Route a phase to a specific model/capability"
    echo "  route-role <role> <target>  Route a role/persona to a model/capability"
    echo "  unroute-role <role>         Remove an explicit role route override"
    echo "  cost-mode [mode|status]     Select budget, standard, or premium routing"
    echo "  tier <mode> <provider> <target>"
    echo "                              Configure a provider model/capability for a tier"
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
    echo "  OCTOPUS_AGY_MODEL           Override Antigravity model (default, agy/default, or exact agy models label)"
    echo "  OCTOPUS_CURSOR_AGENT_MODEL  Override cursor-agent model"
    echo "  OCTOPUS_GROK_MODEL          Override xAI Grok CLI model"
    echo "  OCTOPUS_KIMI_MODEL          Select a model alias declared in Kimi Code config.toml"
    echo "  OCTOPUS_COST_MODE           Set cost tier: budget, standard, premium"
    echo "  OCTO_ALLOWED_PROVIDERS      Override provider availability for this process"
    echo "  OCTOPUS_TRACE_MODELS=1      Debug model resolution precedence"
}

log_info() { echo -e "${GREEN}INFO:${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARN:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

automatic_target_allowed() {
    octo_model_automatic_target_allowed "${1:-}" "${2:-}"
}

# Ensure config file exists and is v3.0
ensure_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "3.0",
  "cost_mode": "standard",
  "providers": {
    "codex": {
      "default": "gpt-5.6-sol",
      "fallback": "gpt-5.6-terra",
      "spark": "gpt-5.6-luna",
      "mini": "gpt-5.6-luna",
      "reasoning": "gpt-5.6-sol",
      "large_context": "gpt-5.6-sol"
    },
    "agy": {
      "default": "Gemini 3.1 Pro (High)",
      "fallback": "Gemini 3.5 Flash (High)",
      "flash": "Gemini 3.5 Flash (Low)"
    },
    "claude": {
      "default": "claude-sonnet-5",
      "budget": "claude-haiku-4.5",
      "opus": "claude-opus-5"
    },
    "perplexity": {
      "default": "sonar-pro",
      "fast": "sonar"
    },
    "opencode": {
      "default": "opencode/deepseek-v4-flash-free",
      "fast": "opencode/deepseek-v4-flash-free",
      "research": "opencode/glm-5.1"
    },
    "openai-compatible-agent": {
      "default": "example/model-id",
      "base_url": "https://api.example.com/v1",
      "api_key_env": "OPENAI_COMPAT_API_KEY"
    }
  },
  "routing": {
    "phases": {
      "deliver": "codex:default",
      "review": "codex:default",
      "security": "codex:reasoning",
      "research": "agy"
    },
    "roles": {
      "researcher": "perplexity"
    }
  },
  "tiers": {
    "budget": { "codex": "mini", "claude": "budget", "agy": "flash", "opencode": "fast" },
    "standard": { "codex": "default", "claude": "default", "agy": "default", "opencode": "default" },
    "premium": { "codex": "default", "claude": "opus", "agy": "default", "opencode": "default" }
  },
  "overrides": {}
}
EOF
    fi

    if ! command -v jq &>/dev/null; then
        log_error "jq is not installed. Please install it (brew install jq or apt install jq)."
        exit 1
    fi

    migrate_retired_gemini_config
}

migrate_retired_gemini_config() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    if ! jq -e '
        (.providers.gemini? != null) or
        (.overrides.gemini? != null) or
        ([.tiers[]?.gemini?] | any(. != null)) or
        ([.routing.phases[]?, .routing.roles[]?] | any(
            (type == "string" and startswith("gemini")) or
            (type == "object" and .provider? == "gemini")
        ))
    ' "$CONFIG_FILE" >/dev/null 2>&1; then
        return 0
    fi

    jq '
        def migrate_google_target:
            if type == "string" then
                if . == "gemini" then "agy"
                elif startswith("gemini:") then
                    (split(":")[1]) as $cap |
                    if ($cap == "default" or $cap == "flash" or $cap == "fallback")
                    then "agy:" + $cap else "agy" end
                else . end
            elif type == "object" and .provider? == "gemini" then
                .provider = "agy" | if .model? then .model = "default" else . end
            else . end;
        .providers.agy //= {
            "default": "Gemini 3.1 Pro (High)",
            "fallback": "Gemini 3.5 Flash (High)",
            "flash": "Gemini 3.5 Flash (Low)"
        } |
        del(.providers.gemini) |
        if .overrides.gemini? != null and .overrides.agy? == null
            then .overrides.agy = "default" else . end |
        del(.overrides.gemini) |
        .tiers = ((.tiers // {}) | with_entries(
            .value |= (
                if .gemini? != null and .agy? == null then .agy = .gemini else . end |
                del(.gemini)
            )
        )) |
        .routing = (.routing // {}) |
        .routing.phases = ((.routing.phases // {}) | with_entries(.value |= migrate_google_target)) |
        .routing.roles = ((.routing.roles // {}) | with_entries(.value |= migrate_google_target))
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
    log_info "Migrated retired Gemini provider settings to Antigravity"
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

validate_role_name() {
    local role="$1"
    [[ -z "$role" ]] && return 1
    [[ "$role" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
    [[ "$role" == .* || "$role" == *..* || "$role" == /* ]] && return 1
    return 0
}

canonical_provider() {
    local provider
    provider="$(octo_normalize_provider_name "${1:-}")"
    case "$provider" in
        anthropic|sonnet) echo "claude" ;;
        openai) echo "codex" ;;
        google) echo "agy" ;;
        cursor|xai) echo "cursor-agent" ;;
        local) echo "ollama" ;;
        *) octo_provider_canonical "$provider" 2>/dev/null || echo "$provider" ;;
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
    echo "    octo-model-config allow claude agy --session"
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
    [[ -n "${CACHE_FILE:-}" ]] || return 0
    rm -f "$CACHE_FILE"
}

validate_cost_mode() {
    case "${1:-}" in
        budget|standard|premium) return 0 ;;
        *) return 1 ;;
    esac
}

configured_cost_mode() {
    ensure_config
    jq -r '.cost_mode // "standard"' "$CONFIG_FILE" 2>/dev/null || echo "standard"
}

cmd_cost_mode() {
    local mode="${1:-status}"
    ensure_config

    if [[ "$mode" == "status" || -z "$mode" ]]; then
        if [[ -n "${OCTOPUS_COST_MODE:-}" ]]; then
            echo -e "${CYAN}Cost Mode${NC}"
            echo "  ${OCTOPUS_COST_MODE} (environment: OCTOPUS_COST_MODE)"
        else
            echo -e "${CYAN}Cost Mode${NC}"
            echo "  $(configured_cost_mode) (providers.json)"
        fi
        return 0
    fi

    if ! validate_cost_mode "$mode"; then
        log_error "Invalid cost mode '$mode'. Valid modes: budget, standard, premium"
        return 1
    fi

    local tmp_file="${CONFIG_FILE}.tmp.$$"
    if ! jq --arg mode "$mode" '.cost_mode = $mode' "$CONFIG_FILE" > "$tmp_file" ||
       ! mv "$tmp_file" "$CONFIG_FILE"; then
        rm -f "$tmp_file"
        log_error "Failed to persist cost mode"
        return 1
    fi

    clear_cache
    log_info "Cost mode → $mode"
    echo "  Saved: $CONFIG_FILE"
    if [[ -n "${OCTOPUS_COST_MODE:-}" && "${OCTOPUS_COST_MODE}" != "$mode" ]]; then
        log_warn "OCTOPUS_COST_MODE=${OCTOPUS_COST_MODE} still overrides the saved mode in this environment"
    fi
}

cmd_tier() {
    local mode="${1:-}"
    local provider="${2:-}"
    local target="${3:-}"

    if ! validate_cost_mode "$mode"; then
        log_error "Invalid cost mode '$mode'. Valid modes: budget, standard, premium"
        return 1
    fi

    provider="$(canonical_provider "$provider")"
    if ! provider_known "$provider"; then
        log_error "Unknown provider '${2:-}'. Valid: $KNOWN_PROVIDERS"
        return 1
    fi

    if ! validate_model "$target"; then
        log_error "Invalid tier target: '$target'"
        return 1
    fi
    if ! automatic_target_allowed "$target" "$provider"; then
        log_error "$target is explicit-only and cannot be assigned to an automatic cost tier"
        return 1
    fi

    ensure_config
    local tmp_file="${CONFIG_FILE}.tmp.$$"
    if ! jq --arg mode "$mode" --arg provider "$provider" --arg target "$target" \
        '.tiers[$mode][$provider] = $target' "$CONFIG_FILE" > "$tmp_file" ||
       ! mv "$tmp_file" "$CONFIG_FILE"; then
        rm -f "$tmp_file"
        log_error "Failed to persist tier mapping"
        return 1
    fi

    clear_cache
    log_info "Cost tier ${mode}.${provider} → $target"
}

cmd_list() {
    ensure_config
    echo -e "${CYAN}Current Model Configuration (v3.0)${NC}"
    echo "----------------------------------------"

    # Environment overrides
    echo -e "\n${YELLOW}Environment Overrides:${NC}"
    local has_env=false
    for var in OCTOPUS_CODEX_MODEL OCTOPUS_AGY_MODEL OCTOPUS_GROK_MODEL OCTOPUS_KIMI_MODEL OCTOPUS_CURSOR_AGENT_MODEL OCTOPUS_PERPLEXITY_MODEL OCTOPUS_OPENCODE_MODEL OCTOPUS_COST_MODE OCTO_ALLOWED_PROVIDERS OCTOPUS_TRACE_MODELS; do
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
    if [[ -n "${OCTOPUS_COST_MODE:-}" ]]; then
        echo "  ${OCTOPUS_COST_MODE} (environment: OCTOPUS_COST_MODE)"
    else
        echo "  $(configured_cost_mode) (providers.json)"
    fi

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
                research) default_target="agy" ;;
            esac
            printf "  %-12s %-25s %s\n" "$phase" "$default_target" "(default)"
        fi
    done
}

cmd_show_roles() {
    ensure_config
    echo -e "${CYAN}Role Routing Overrides${NC}"
    echo "─────────────────────────────────────────────────"
    printf "  %-28s %s\n" "Role" "Target"
    echo "  ────────────────────────────────────────────────"

    local roles
    roles=$(jq -r '.routing.roles // {} | to_entries | sort_by(.key)[] | "\(.key)	\(.value)"' "$CONFIG_FILE" 2>/dev/null || true)
    if [[ -z "$roles" ]]; then
        echo "  (none — using provider/persona defaults)"
    else
        echo "$roles" | while IFS=$'	' read -r role target; do
            printf "  %-28s %s\n" "$role" "$target"
        done
    fi
}

cmd_verify() {
    ensure_config
    log_info "Verifying model accessibility..."

    local errors=0
    for cli in codex agy claude opencode; do
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
    provider="$(canonical_provider "$provider")"

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

    if [[ -n "$capability" ]] && ! automatic_target_allowed "$model" "$provider"; then
        log_error "$model is explicit-only and cannot be assigned to an automatic capability"
        exit 1
    fi

    ensure_config

    if [[ -z "$capability" ]] && ! automatic_target_allowed "$model" "$provider"; then
        log_error "$model is explicit-only; use a one-command environment pin or an exact model-qualified seat"
        exit 1
    fi

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
    if ! automatic_target_allowed "$target"; then
        log_error "$target is explicit-only and cannot be assigned to an automatic phase route"
        exit 1
    fi

    ensure_config
    # v8.49.0: Use jq --arg for injection safety
    jq --arg p "$phase" --arg t "$target" '.routing.phases[$p] = $t' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
    log_info "Routed phase '$phase' → '$target'"
    clear_cache
}

cmd_route_role() {
    local role="$1"
    local target="$2"

    [[ -z "$role" || -z "$target" ]] && { usage; exit 1; }

    if ! validate_role_name "$role"; then
        log_error "Invalid role: '$role'"
        log_warn "Role names may contain only letters, digits, dot, underscore, and hyphen."
        exit 1
    fi

    if ! validate_model "$target"; then
        log_error "Invalid target: '$target'"
        exit 1
    fi
    if ! automatic_target_allowed "$target"; then
        log_error "$target is explicit-only and cannot be assigned to an automatic role route"
        exit 1
    fi

    ensure_config
    jq --arg r "$role" --arg t "$target" '.routing.roles[$r] = $t' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
    log_info "Routed role '$role' → '$target'"
    clear_cache
}

cmd_unroute_role() {
    local role="$1"

    [[ -z "$role" ]] && { usage; exit 1; }

    if ! validate_role_name "$role"; then
        log_error "Invalid role: '$role'"
        log_warn "Role names may contain only letters, digits, dot, underscore, and hyphen."
        exit 1
    fi

    ensure_config
    jq --arg r "$role" 'del(.routing.roles[$r])' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
    log_info "Removed role route override: $role"
    clear_cache
}

cmd_models() {
    local filter="${1:-}"
    echo -e "${CYAN}Model Catalog${NC}"
    echo "───────────────────────────────────────────────────────────────────────────"
    printf "  %-24s %-8s %-6s %-6s %-5s %-10s %-8s %-10s %s\n" "Model" "Ctx(K)" "Tools" "Image" "Reas" "Provider" "Tier" "Policy" "Status"
    echo "  ──────────────────────────────────────────────────────────────────────────────────────"

    local name catalog ctx tools images reasoning provider tier status policy selection
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        catalog="$(get_model_catalog "$name")"
        IFS='|' read -r ctx tools images reasoning provider tier status <<< "$catalog"
        policy="$(get_model_policy "$name")"
        selection="${policy%%|*}"

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

        printf "  %-24s %-8s %-6s %-6s %-5s %-10s %-8s %-10s %s\n" \
            "$name" "${ctx}K" "$tools" "$images" "$reasoning" "$provider" "$tier" "$selection" "$status"
    done < <(octo_model_ids)
    echo ""
    echo "  Filters: --tools, --images, --reasoning, --budget, --premium, or text search"
}

cmd_reset() {
    local provider="${1:-all}"
    if [[ "$provider" != "all" ]]; then
        provider="$(canonical_provider "$provider")"
    fi
    if [[ "$provider" == "all" ]]; then
        rm -f "$CONFIG_FILE"
        ensure_config
        log_info "Reset all configuration to defaults"
    else
        ensure_config
        local reset_tmp="${CONFIG_FILE}.tmp.$$"
        if ! jq --arg p "$provider" '
            del(.providers[$p])
            | del(.overrides[$p])
            | .tiers = ((.tiers // {}) | with_entries(.value |= del(.[$p])))
        ' "$CONFIG_FILE" > "$reset_tmp"; then
            rm -f "$reset_tmp"
            log_error "Failed to rewrite configuration while resetting provider: $provider"
            return 1
        fi
        if ! mv "$reset_tmp" "$CONFIG_FILE"; then
            rm -f "$reset_tmp"
            log_error "Failed to install reset configuration for provider: $provider"
            return 1
        fi
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
            roles) cmd_show_roles ;;
            *) cmd_list ;;
        esac
        ;;
    set) cmd_set "$@" ;;
    route) cmd_route "$@" ;;
    route-role|role-route) cmd_route_role "$@" ;;
    unroute-role|role-unroute) cmd_unroute_role "$@" ;;
    cost-mode|mode) cmd_cost_mode "$@" ;;
    tier|set-tier) cmd_tier "$@" ;;
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
