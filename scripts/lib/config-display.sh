#!/usr/bin/env bash
# config-display.sh — Configuration display and mode toggle functions
# Extracted from orchestrate.sh (v9.7.4)

# Display comprehensive configuration summary with tier detection indicators
show_config_summary() {
    # Load current configuration
    load_providers_config

    echo ""
    octopus_header "CLAUDE OCTOPUS CONFIGURATION SUMMARY" "$CYAN"
    echo ""

    # Helper function to get tier detection indicator
    get_tier_indicator() {
        local provider="$1"
        if tier_cache_valid "$provider"; then
            echo "${YELLOW}[CACHED]${NC}"
        else
            echo "${GREEN}[AUTO-DETECTED]${NC}"
        fi
    }

    # Helper function to mask API key
    mask_api_key() {
        local key="$1"
        if [[ -n "$key" && ${#key} -gt 12 ]]; then
            echo "${key:0:7}...${key: -4}"
        else
            echo "***"
        fi
    }

    # Codex Status
    echo -e "  ${CYAN}┌─ CODEX (OpenAI)${NC}"
    if [[ "$PROVIDER_CODEX_INSTALLED" == "true" && "$PROVIDER_CODEX_AUTH_METHOD" != "none" ]]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC} Configured"
        echo -e "  ${CYAN}│${NC}  Auth:      ${GREEN}$PROVIDER_CODEX_AUTH_METHOD${NC}"
        local tier_indicator
        tier_indicator=$(get_tier_indicator "codex")
        echo -e "  ${CYAN}│${NC}  Tier:      ${GREEN}$PROVIDER_CODEX_TIER${NC} $tier_indicator"
        echo -e "  ${CYAN}│${NC}  Cost Tier: ${GREEN}$PROVIDER_CODEX_COST_TIER${NC}"
        if [[ "$PROVIDER_CODEX_AUTH_METHOD" == "api-key" && -n "${OPENAI_API_KEY:-}" ]]; then
            local masked_key
            masked_key=$(mask_api_key "$OPENAI_API_KEY")
            echo -e "  ${CYAN}│${NC}  API Key:   ${YELLOW}$masked_key${NC}"
        fi
    else
        echo -e "  ${CYAN}│${NC}  ${RED}✗${NC} Not configured"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Install: ${CYAN}npm install -g @openai/codex${NC}"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Configure: ${CYAN}codex login${NC}"
    fi
    echo ""

    # Antigravity Status (sole Google seat)
    echo -e "  ${CYAN}┌─ ANTIGRAVITY (Google)${NC}"
    if [[ "$PROVIDER_AGY_INSTALLED" == "true" && "$PROVIDER_AGY_AUTH_METHOD" != "none" ]]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC} Configured"
        echo -e "  ${CYAN}│${NC}  Auth:      ${GREEN}$PROVIDER_AGY_AUTH_METHOD${NC}"
        echo -e "  ${CYAN}│${NC}  Model:     ${GREEN}$(agy_current_model 2>/dev/null || echo default)${NC}"
    else
        echo -e "  ${CYAN}│${NC}  ${RED}✗${NC} Not configured"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Install the Antigravity CLI from Google"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Configure: launch plain ${CYAN}agy${NC} and complete browser sign-in"
    fi
    echo ""

    # Claude Status
    echo -e "  ${CYAN}┌─ CLAUDE (Anthropic)${NC}"
    if [[ "$PROVIDER_CLAUDE_INSTALLED" == "true" ]]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC} Configured"
        echo -e "  ${CYAN}│${NC}  Auth:      ${GREEN}$PROVIDER_CLAUDE_AUTH_METHOD${NC}"
        echo -e "  ${CYAN}│${NC}  Tier:      ${GREEN}$PROVIDER_CLAUDE_TIER${NC} ${YELLOW}[DEFAULT]${NC}"
        echo -e "  ${CYAN}│${NC}  Cost Tier: ${GREEN}$PROVIDER_CLAUDE_COST_TIER${NC}"
    else
        echo -e "  ${CYAN}│${NC}  ${YELLOW}○${NC} Available via Claude Code"
    fi
    echo ""

    # OpenCode Status
    echo -e "  ${CYAN}┌─ OPENCODE (Multi-Provider Router)${NC}"
    if [[ "$PROVIDER_OPENCODE_INSTALLED" == "true" && "$PROVIDER_OPENCODE_AUTH_METHOD" != "none" ]]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC} Configured"
        echo -e "  ${CYAN}│${NC}  Auth:      ${GREEN}$PROVIDER_OPENCODE_AUTH_METHOD${NC}"
        echo -e "  ${CYAN}│${NC}  Tier:      ${GREEN}$PROVIDER_OPENCODE_TIER${NC}"
        echo -e "  ${CYAN}│${NC}  Cost Tier: ${YELLOW}$PROVIDER_OPENCODE_COST_TIER${NC} (varies by backend model)"
    else
        echo -e "  ${CYAN}│${NC}  ${YELLOW}○${NC} Not configured (Optional)"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Install: ${CYAN}npm install -g opencode${NC}"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Configure: ${CYAN}opencode auth login${NC}"
    fi
    echo ""

    # OpenRouter Status
    echo -e "  ${CYAN}┌─ OPENROUTER (Universal Fallback)${NC}"
    if [[ "$PROVIDER_OPENROUTER_ENABLED" == "true" && "$PROVIDER_OPENROUTER_API_KEY_SET" == "true" ]]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC} Configured (Optional)"
        if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
            local masked_key
            masked_key=$(mask_api_key "$OPENROUTER_API_KEY")
            echo -e "  ${CYAN}│${NC}  API Key:   ${YELLOW}$masked_key${NC}"
        fi
    else
        echo -e "  ${CYAN}│${NC}  ${YELLOW}○${NC} Not configured (Optional)"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Sign up: ${CYAN}https://openrouter.ai${NC}"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Set: ${CYAN}export OPENROUTER_API_KEY='sk-or-...'${NC}"
    fi
    echo ""

    # OrcaRouter Status
    echo -e "  ${CYAN}┌─ ORCAROUTER (Universal Fallback)${NC}"
    if [[ "$PROVIDER_ORCAROUTER_ENABLED" == "true" && "$PROVIDER_ORCAROUTER_API_KEY_SET" == "true" ]]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC} Configured (Optional)"
        if [[ -n "${ORCAROUTER_API_KEY:-}" ]]; then
            local masked_orca_key
            masked_orca_key=$(mask_api_key "$ORCAROUTER_API_KEY")
            echo -e "  ${CYAN}│${NC}  API Key:   ${YELLOW}$masked_orca_key${NC}"
        fi
    else
        echo -e "  ${CYAN}│${NC}  ${YELLOW}○${NC} Not configured (Optional)"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Sign up: ${CYAN}https://www.orcarouter.ai${NC}"
        echo -e "  ${CYAN}│${NC}  ${YELLOW}→${NC} Set: ${CYAN}export ORCAROUTER_API_KEY='sk-orca-...'${NC}"
    fi
    echo ""

    # Cost Optimization Strategy
    echo -e "  ${CYAN}┌─ COST OPTIMIZATION${NC}"
    echo -e "  ${CYAN}│${NC}  Strategy:  ${GREEN}$COST_OPTIMIZATION_STRATEGY${NC}"
    echo ""

    # Configuration Files
    echo -e "  ${CYAN}┌─ CONFIGURATION FILES${NC}"
    echo -e "  ${CYAN}│${NC}  Config:    ${YELLOW}$PROVIDERS_CONFIG_FILE${NC}"
    if [[ -f "$TIER_CACHE_FILE" ]]; then
        echo -e "  ${CYAN}│${NC}  Tier Cache: ${YELLOW}$TIER_CACHE_FILE${NC} (24h TTL)"
    else
        echo -e "  ${CYAN}│${NC}  Tier Cache: ${YELLOW}(not yet created)${NC}"
    fi
    echo ""

    # Next Steps
    echo -e "  ${CYAN}┌─ NEXT STEPS${NC}"
    echo -e "  ${CYAN}│${NC}  ${GREEN}orchestrate.sh preflight${NC}     - Verify everything works"
    echo -e "  ${CYAN}│${NC}  ${GREEN}orchestrate.sh status${NC}        - View provider status"
    echo -e "  ${CYAN}│${NC}  ${GREEN}orchestrate.sh auto <prompt>${NC} - Smart task routing"
    echo -e "  ${CYAN}│${NC}  ${GREEN}orchestrate.sh embrace <prompt>${NC} - Full Double Diamond workflow"
    echo ""

    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

toggle_knowledge_work_mode() {
    local action="${1:-status}"

    KNOWLEDGE_WORK_MODE="auto"
    if [[ -f "$USER_CONFIG_FILE" ]]; then
        KNOWLEDGE_WORK_MODE=$(grep "^knowledge_work_mode:" "$USER_CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo "auto")
    fi

    if [[ "$action" == "status" ]]; then
        echo ""
        case "$KNOWLEDGE_WORK_MODE" in
            true|on)
                echo -e "  ${MAGENTA}🎓 Knowledge Mode${NC} ${GREEN}FORCED${NC}"
                echo ""
                echo -e "  ${CYAN}Best for:${NC} User research, strategy analysis, literature reviews"
                echo -e "  ${DIM}Switch:${NC} /octo:km off (dev) | /octo:km auto (auto-detect)"
                ;;
            false|off)
                echo -e "  ${GREEN}🔧 Dev Mode${NC} ${CYAN}FORCED${NC}"
                echo ""
                echo -e "  ${CYAN}Best for:${NC} Building features, debugging code, implementing APIs"
                echo -e "  ${DIM}Switch:${NC} /octo:km on (knowledge) | /octo:km auto (auto-detect)"
                ;;
            *)
                echo -e "  ${YELLOW}🐙 Auto-Detect Mode${NC} ${CYAN}ACTIVE${NC} (v7.8+)"
                echo ""
                echo -e "  ${CYAN}How it works:${NC} Context detected from prompt + project type"
                echo -e "  ${DIM}Override:${NC} /octo:km on (knowledge) | /octo:km off (dev)"
                ;;
        esac
        echo ""
        return 0
    fi

    local new_mode="$KNOWLEDGE_WORK_MODE"
    case "$action" in
        on|enable)
            new_mode="true"
            ;;
        off|disable)
            new_mode="false"
            ;;
        auto)
            new_mode="auto"
            ;;
        toggle)
            case "$KNOWLEDGE_WORK_MODE" in
                true|on) new_mode="false" ;;
                false|off) new_mode="auto" ;;
                *) new_mode="true" ;;
            esac
            ;;
        *)
            echo ""
            echo -e "${RED}✗${NC} Invalid action: ${BOLD}$action${NC}"
            echo -e "  ${DIM}Use:${NC} on | off | auto | status | toggle"
            echo ""
            exit 1
            ;;
    esac

    if [[ "$new_mode" == "$KNOWLEDGE_WORK_MODE" ]]; then
        echo ""
        case "$new_mode" in
            true|on) echo -e "  ${YELLOW}ℹ${NC}  Already in ${MAGENTA}Knowledge Mode${NC} (forced)" ;;
            false|off) echo -e "  ${YELLOW}ℹ${NC}  Already in ${GREEN}Dev Mode${NC} (forced)" ;;
            *) echo -e "  ${YELLOW}ℹ${NC}  Already in ${YELLOW}Auto-Detect Mode${NC}" ;;
        esac
        echo ""
        return 0
    fi

    update_knowledge_mode_config "$new_mode"
    KNOWLEDGE_WORK_MODE="$new_mode"

    echo ""
    case "$new_mode" in
        true|on)
            echo -e "  ${GREEN}✓${NC} Switched to ${MAGENTA}🎓 Knowledge Mode${NC} (forced)"
            echo ""
            echo -e "  ${DIM}Personas optimized for:${NC}"
            echo -e "    • User research and UX analysis"
            echo -e "    • Strategy and market analysis"
            echo -e "    • Literature review and synthesis"
            echo ""
            local first_time_flag="${WORKSPACE_DIR}/.knowledge-mode-setup-done"
            if [[ ! -f "$first_time_flag" ]]; then
                show_document_skills_info
                mkdir -p "$(dirname "$first_time_flag")"
                touch "$first_time_flag"
            fi
            ;;
        false|off)
            echo -e "  ${GREEN}✓${NC} Switched to ${GREEN}🔧 Dev Mode${NC} (forced)"
            echo ""
            echo -e "  ${DIM}Personas optimized for:${NC}"
            echo -e "    • Building features and implementing APIs"
            echo -e "    • Debugging code and fixing bugs"
            echo -e "    • Technical architecture and code review"
            ;;
        *)
            echo -e "  ${GREEN}✓${NC} Switched to ${YELLOW}🐙 Auto-Detect Mode${NC}"
            echo ""
            echo -e "  ${DIM}Context will be detected from:${NC}"
            echo -e "    • Your prompt (strongest signal)"
            echo -e "    • Project type (package.json, etc.)"
            ;;
    esac
    echo ""
    echo -e "  ${DIM}Setting persists across sessions${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SETUP WIZARD — Interactive configuration for first-time users
# Extracted from orchestrate.sh (v9.7.8)
# ═══════════════════════════════════════════════════════════════════════════════

# Persist one provider secret without echoing it to the terminal. The existing
# non-interactive resolver reads ~/.env, so values stored here are also visible
# to health checks and provider detection in later sessions.
persist_provider_secret() (
    local var_name="$1"
    local value="$2"
    local env_file="${OCTOPUS_SECRET_ENV_FILE:-${HOME}/.env}"
    local env_dir=""
    local temp_file=""

    [[ "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1

    env_dir=$(dirname "$env_file")
    umask 077
    mkdir -p "$env_dir" || return 1
    temp_file=$(mktemp "${env_file}.tmp.XXXXXX") || return 1

    if [[ -f "$env_file" ]]; then
        awk -v name="$var_name" '
            {
                assignment = $0
                sub(/^[[:space:]]+/, "", assignment)
                sub(/^export[[:space:]]+/, "", assignment)
                if (index(assignment, name "=") != 1) print
            }
        ' \
            "$env_file" > "$temp_file" || {
            rm -f "$temp_file"
            return 1
        }
    fi
    printf '%s=%s\n' "$var_name" "$value" >> "$temp_file" || {
        rm -f "$temp_file"
        return 1
    }
    chmod 600 "$temp_file" || {
        rm -f "$temp_file"
        return 1
    }
    mv -f "$temp_file" "$env_file"
)

# Interactive setup wizard
setup_wizard() {
    # Detect if running in non-interactive mode (e.g., called by Claude Code)
    local NON_INTERACTIVE=false
    if [[ ! -t 0 ]] || [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
        NON_INTERACTIVE=true
        echo -e "${YELLOW}⚠ Non-interactive mode detected. Using auto-detected defaults.${NC}"
        echo ""
    fi

    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}        🐙 Claude Octopus Configuration Wizard 🐙${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Welcome! Let's get all 8 tentacles connected and ready to work."
    echo -e "  This wizard will help you install dependencies and configure API keys."
    echo ""

    local total_steps=11
    local current_step=0
    local shell_profile=""
    local keys_to_add=""

    # Initialize provider config variables
    PROVIDER_CODEX_INSTALLED="false"
    PROVIDER_CODEX_AUTH_METHOD="none"
    PROVIDER_CODEX_TIER="free"
    PROVIDER_CODEX_COST_TIER="free"
    PROVIDER_AGY_INSTALLED="false"
    PROVIDER_AGY_AUTH_METHOD="none"
    PROVIDER_AGY_TIER="subscription"
    PROVIDER_AGY_COST_TIER="bundled"
    PROVIDER_CLAUDE_INSTALLED="true"
    PROVIDER_CLAUDE_AUTH_METHOD="oauth"
    PROVIDER_CLAUDE_TIER="pro"
    PROVIDER_CLAUDE_COST_TIER="medium"
    PROVIDER_OPENROUTER_ENABLED="false"
    PROVIDER_OPENROUTER_API_KEY_SET="false"
    PROVIDER_ORCAROUTER_ENABLED="false"
    PROVIDER_ORCAROUTER_API_KEY_SET="false"
    COST_OPTIMIZATION_STRATEGY="balanced"

    # Detect shell profile
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == *"zsh"* ]]; then
        shell_profile="$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == *"bash"* ]]; then
        shell_profile="$HOME/.bashrc"
    else
        shell_profile="$HOME/.profile"
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 1: Check/Install Codex CLI
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    echo -e "${CYAN}Step $current_step/$total_steps: Codex CLI (Tentacles 1-4)${NC}"
    echo -e "  OpenAI's Codex CLI powers our coding tentacles."
    echo ""

    if command -v codex &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Codex CLI already installed: $(command -v codex)"
    else
        echo -e "  ${YELLOW}✗${NC} Codex CLI not found"
        echo ""
        read -p "  Install Codex CLI now? (requires npm) [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo -e "  ${CYAN}→${NC} Installing Codex CLI..."
            if npm install -g @openai/codex 2>&1 | sed 's/^/    /'; then
                echo -e "  ${GREEN}✓${NC} Codex CLI installed successfully"
            else
                echo -e "  ${RED}✗${NC} Installation failed. Try manually: npm install -g @openai/codex"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} Skipped. Install later: npm install -g @openai/codex"
        fi
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 2: Check Antigravity CLI
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    echo -e "${CYAN}Step $current_step/$total_steps: Antigravity CLI (Google seat)${NC}"
    echo -e "  Antigravity is the supported Google seat for Octopus workflows."
    echo ""

    if command -v agy &>/dev/null; then
        PROVIDER_AGY_INSTALLED="true"
        PROVIDER_AGY_AUTH_METHOD="cli"
        echo -e "  ${GREEN}✓${NC} Antigravity CLI already installed: $(command -v agy)"
    else
        echo -e "  ${YELLOW}✗${NC} Antigravity CLI not found"
        echo -e "  Install ${CYAN}agy${NC} from Google Antigravity, then launch it and complete browser sign-in."
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 3: OpenAI API Key
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    echo -e "${CYAN}Step $current_step/$total_steps: OpenAI API Key${NC}"
    echo -e "  Required for Codex CLI (GPT models for coding tasks)."
    echo ""

    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} OPENAI_API_KEY already set (${#OPENAI_API_KEY} chars)"
    else
        echo -e "  ${YELLOW}✗${NC} OPENAI_API_KEY not set"
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            echo ""
            echo -e "  ${CYAN}→${NC} To configure: export OPENAI_API_KEY=\"sk-...\""
            echo -e "  ${CYAN}→${NC} Get your key from: https://platform.openai.com/api-keys"
        else
            echo ""
            read -p "  Open OpenAI platform to get an API key? [Y/n] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                echo -e "  ${CYAN}→${NC} Opening https://platform.openai.com/api-keys ..."
                open_browser "https://platform.openai.com/api-keys"
                sleep 1
            fi
            echo ""
            echo -e "  Paste your OpenAI API key (starts with 'sk-'):"
            read -p "  → " openai_key
            if [[ -n "$openai_key" ]]; then
                export OPENAI_API_KEY="$openai_key"
                keys_to_add="${keys_to_add}export OPENAI_API_KEY=\"$openai_key\"\n"
                echo -e "  ${GREEN}✓${NC} OPENAI_API_KEY set for this session"
            else
                echo -e "  ${YELLOW}⚠${NC} Skipped. Set later: export OPENAI_API_KEY=\"your-key\""
            fi
        fi
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 4: Antigravity Authentication
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    echo -e "${CYAN}Step $current_step/$total_steps: Antigravity Authentication${NC}"
    echo -e "  AGY owns Google-seat authentication."
    echo ""

    if command -v agy &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Antigravity CLI is available"
        echo -e "  If needed, refresh its session by launching plain ${CYAN}agy${NC} and completing browser sign-in."
    else
        echo -e "  ${YELLOW}✗${NC} Antigravity CLI is not installed"
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 5: Codex/OpenAI Subscription Tier (v4.8)
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    if command -v codex &>/dev/null && [[ -f "$HOME/.codex/auth.json" || -n "${OPENAI_API_KEY:-}" ]]; then
        PROVIDER_CODEX_INSTALLED="true"
        [[ -f "$HOME/.codex/auth.json" ]] && PROVIDER_CODEX_AUTH_METHOD="oauth" || PROVIDER_CODEX_AUTH_METHOD="api-key"

        echo -e "${CYAN}Step $current_step/$total_steps: Codex/OpenAI Subscription Tier${NC}"

        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            # Auto-detect based on API key presence
            codex_tier_choice=2  # Default to Plus tier
            echo -e "  ${GREEN}✓${NC} Auto-detected: Plus tier (default for API key users)"
        else
            echo -e "  ${YELLOW}This helps us optimize cost vs quality for your budget.${NC}"
            echo ""
            echo -e "  ${GREEN}[1]${NC} Free         ${CYAN}(Limited usage, free tier)${NC}"
            echo -e "  ${GREEN}[2]${NC} Plus (\$20/mo) ${CYAN}(ChatGPT Plus subscriber)${NC}"
            echo -e "  ${GREEN}[3]${NC} Pro (\$200/mo) ${CYAN}(ChatGPT Pro subscriber)${NC}"
            echo -e "  ${GREEN}[4]${NC} API Only     ${CYAN}(Pay-per-use, no subscription)${NC}"
            echo ""
            read -p "  Enter choice [1-4, default 2]: " codex_tier_choice
            codex_tier_choice="${codex_tier_choice:-2}"
        fi

        case "$codex_tier_choice" in
            1) PROVIDER_CODEX_TIER="free"; PROVIDER_CODEX_COST_TIER="free" ;;
            2) PROVIDER_CODEX_TIER="plus"; PROVIDER_CODEX_COST_TIER="low" ;;
            3) PROVIDER_CODEX_TIER="pro"; PROVIDER_CODEX_COST_TIER="medium" ;;
            4) PROVIDER_CODEX_TIER="api-only"; PROVIDER_CODEX_COST_TIER="pay-per-use" ;;
            *) PROVIDER_CODEX_TIER="plus"; PROVIDER_CODEX_COST_TIER="low" ;;
        esac
        echo -e "  ${GREEN}✓${NC} Codex tier set to: $PROVIDER_CODEX_TIER ($PROVIDER_CODEX_COST_TIER)"
    else
        echo -e "${CYAN}Step $current_step/$total_steps: Codex/OpenAI Subscription Tier${NC}"
        echo -e "  ${YELLOW}⚠${NC} Codex not available, skipping tier configuration"
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6: Antigravity Model
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    if command -v agy &>/dev/null; then
        echo -e "${CYAN}Step $current_step/$total_steps: Antigravity Model${NC}"
        echo -e "  ${GREEN}✓${NC} Current model: $(agy_current_model 2>/dev/null || echo default)"
        echo -e "  Change it in AGY or set ${CYAN}OCTOPUS_AGY_MODEL${NC} to an exact ${CYAN}agy models${NC} label."
    else
        echo -e "${CYAN}Step $current_step/$total_steps: Antigravity Model${NC}"
        echo -e "  ${YELLOW}⚠${NC} AGY not available, skipping model display"
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 7: OpenRouter Fallback Configuration (v4.8)
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    echo -e "${CYAN}Step $current_step/$total_steps: OpenRouter (Universal Fallback)${NC}"
    echo -e "  ${YELLOW}OpenRouter provides 400+ models as a backup when other CLIs unavailable.${NC}"
    echo ""

    if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        PROVIDER_OPENROUTER_ENABLED="true"
        PROVIDER_OPENROUTER_API_KEY_SET="true"
        echo -e "  ${GREEN}✓${NC} OPENROUTER_API_KEY already set"
    else
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            echo -e "  ${YELLOW}⚠${NC} OpenRouter not configured (optional - skipping in auto mode)"
        else
            echo -e "  ${YELLOW}✗${NC} OPENROUTER_API_KEY not set (optional)"
            echo ""
            echo -e "  ${CYAN}OpenRouter is optional.${NC} It provides:"
            echo -e "    - Universal fallback when Codex/Antigravity unavailable"
            echo -e "    - Access to 400+ models (Claude, GPT, Gemini, Llama, etc.)"
            echo -e "    - Pay-per-use pricing with routing optimization"
            echo ""
            read -p "  Configure OpenRouter? [y/N] " -n 1 -r
            echo
        fi
        if [[ "${NON_INTERACTIVE}" != "true" ]] && [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "  ${CYAN}→${NC} Get an API key from: https://openrouter.ai/keys"
            echo ""
            read -p "  Paste your OpenRouter API key (starts with 'sk-or-'): " openrouter_key
            if [[ -n "$openrouter_key" ]]; then
                export OPENROUTER_API_KEY="$openrouter_key"
                keys_to_add="${keys_to_add}export OPENROUTER_API_KEY=\"$openrouter_key\"\n"
                PROVIDER_OPENROUTER_ENABLED="true"
                PROVIDER_OPENROUTER_API_KEY_SET="true"
                echo -e "  ${GREEN}✓${NC} OPENROUTER_API_KEY set for this session"

                echo ""
                echo -e "  ${YELLOW}Routing preference:${NC}"
                echo -e "  ${GREEN}[1]${NC} Default    ${CYAN}(Balanced speed/cost)${NC}"
                echo -e "  ${GREEN}[2]${NC} Nitro      ${CYAN}(Fastest response, higher cost)${NC}"
                echo -e "  ${GREEN}[3]${NC} Floor      ${CYAN}(Cheapest option, may be slower)${NC}"
                read -p "  Enter choice [1-3, default 1]: " routing_choice
                case "$routing_choice" in
                    2) PROVIDER_OPENROUTER_ROUTING_PREF="nitro" ;;
                    3) PROVIDER_OPENROUTER_ROUTING_PREF="floor" ;;
                    *) PROVIDER_OPENROUTER_ROUTING_PREF="default" ;;
                esac
                echo -e "  ${GREEN}✓${NC} OpenRouter routing: $PROVIDER_OPENROUTER_ROUTING_PREF"
            else
                echo -e "  ${YELLOW}⚠${NC} Skipped OpenRouter configuration"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} OpenRouter skipped. Add later: export OPENROUTER_API_KEY=\"your-key\""
        fi
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 8b: OrcaRouter (Universal Fallback, OpenAI-compatible)
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    echo -e "${CYAN}Step $current_step/$total_steps: OrcaRouter (Universal Fallback)${NC}"
    echo -e "  ${YELLOW}OrcaRouter provides a single gateway to many models as a backup when other CLIs are unavailable.${NC}"
    echo ""

    if [[ -n "${ORCAROUTER_API_KEY:-}" ]]; then
        PROVIDER_ORCAROUTER_ENABLED="true"
        PROVIDER_ORCAROUTER_API_KEY_SET="true"
        echo -e "  ${GREEN}✓${NC} ORCAROUTER_API_KEY already set"
    else
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            echo -e "  ${YELLOW}⚠${NC} OrcaRouter not configured (optional - skipping in auto mode)"
        else
            echo -e "  ${YELLOW}✗${NC} ORCAROUTER_API_KEY not set (optional)"
            echo ""
            read -p "  Configure OrcaRouter? [y/N] " -n 1 -r
            echo
        fi
        if [[ "${NON_INTERACTIVE}" != "true" ]] && [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "  ${CYAN}→${NC} Get an API key from: https://www.orcarouter.ai"
            echo ""
            read -r -s -p "  Paste your OrcaRouter API key (starts with 'sk-orca-'): " orcarouter_key
            echo
            if [[ -n "$orcarouter_key" ]]; then
                export "ORCAROUTER_API_KEY=${orcarouter_key}"
                PROVIDER_ORCAROUTER_ENABLED="true"
                PROVIDER_ORCAROUTER_API_KEY_SET="true"
                echo -e "  ${GREEN}✓${NC} ORCAROUTER_API_KEY set for this session"
                read -p "  Save it to ~/.env with mode 600? [Y/n] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    if persist_provider_secret "ORCAROUTER_API_KEY" "$orcarouter_key"; then
                        echo -e "  ${GREEN}✓${NC} Saved ORCAROUTER_API_KEY securely to ~/.env"
                    else
                        echo -e "  ${RED}✗${NC} Could not persist ORCAROUTER_API_KEY" >&2
                    fi
                fi
            else
                echo -e "  ${YELLOW}⚠${NC} Skipped OrcaRouter configuration"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} OrcaRouter skipped. Add later: export \"ORCAROUTER_API_KEY=your-key\""
        fi
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 8: User Intent (moved from original step 6)
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    init_step_intent

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 9: Claude Tier / Cost Strategy (moved from original step 7)
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    echo ""
    echo -e "${CYAN}Step $current_step/$total_steps: Claude Subscription & Cost Strategy${NC}"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        claude_tier_choice=1  # Default to Pro
        echo -e "  ${GREEN}✓${NC} Auto-detected: Pro tier (default)"
    else
        echo -e "  ${YELLOW}This affects which Claude tier you're using and overall cost optimization.${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} Pro (\$20/mo)       ${CYAN}(Claude Pro subscriber)${NC}"
        echo -e "  ${GREEN}[2]${NC} Max 5x (\$100/mo)   ${CYAN}(5x Pro usage limit)${NC}"
        echo -e "  ${GREEN}[3]${NC} Max 20x (\$200/mo)  ${CYAN}(20x Pro usage limit)${NC}"
        echo -e "  ${GREEN}[4]${NC} API Only           ${CYAN}(No Claude subscription, pay-per-use)${NC}"
        echo ""
        read -p "  Enter choice [1-4, default 1]: " claude_tier_choice
        claude_tier_choice="${claude_tier_choice:-1}"
    fi

    case "$claude_tier_choice" in
        1) PROVIDER_CLAUDE_TIER="pro"; PROVIDER_CLAUDE_COST_TIER="medium" ;;
        2) PROVIDER_CLAUDE_TIER="max-5x"; PROVIDER_CLAUDE_COST_TIER="medium" ;;
        3) PROVIDER_CLAUDE_TIER="max-20x"; PROVIDER_CLAUDE_COST_TIER="high" ;;
        4) PROVIDER_CLAUDE_TIER="api-only"; PROVIDER_CLAUDE_COST_TIER="pay-per-use" ;;
        *) PROVIDER_CLAUDE_TIER="pro"; PROVIDER_CLAUDE_COST_TIER="medium" ;;
    esac
    echo -e "  ${GREEN}✓${NC} Claude tier set to: $PROVIDER_CLAUDE_TIER"

    echo ""
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        COST_OPTIMIZATION_STRATEGY="balanced"
        echo -e "  ${GREEN}✓${NC} Cost strategy: balanced (default)"
    else
        echo -e "  ${YELLOW}Cost optimization strategy:${NC}"
        echo -e "  ${GREEN}[1]${NC} Balanced (Recommended) ${CYAN}(Smart mix of cost and quality)${NC}"
        echo -e "  ${GREEN}[2]${NC} Cost-First              ${CYAN}(Prefer cheapest capable provider)${NC}"
        echo -e "  ${GREEN}[3]${NC} Quality-First           ${CYAN}(Prefer highest-tier provider)${NC}"
        read -p "  Enter choice [1-3, default 1]: " strategy_choice
        case "$strategy_choice" in
            2) COST_OPTIMIZATION_STRATEGY="cost-first" ;;
            3) COST_OPTIMIZATION_STRATEGY="quality-first" ;;
            *) COST_OPTIMIZATION_STRATEGY="balanced" ;;
        esac
    fi
    echo -e "  ${GREEN}✓${NC} Cost strategy: $COST_OPTIMIZATION_STRATEGY"
    echo ""

    # Save provider configuration
    save_providers_config
    preflight_cache_invalidate  # Invalidate cache after config change
    echo -e "  ${GREEN}✓${NC} Provider configuration saved"

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 10: Essential Developer Tools (v4.8.2)
    # ═══════════════════════════════════════════════════════════════════════════
    ((++current_step))
    echo ""
    echo -e "${CYAN}Step $current_step/$total_steps: Essential Developer Tools${NC}"
    echo -e "  ${YELLOW}Tools that AI coding assistants rely on for auditing, QA, and browser work.${NC}"
    echo ""

    # Detect tool status
    local missing_tools=()
    local installed_tools=()
    local tool desc

    for tool in jq shellcheck gh imagemagick playwright; do
        desc=$(get_tool_description "$tool")

        if is_tool_installed "$tool"; then
            installed_tools+=("$tool")
            echo -e "  ${GREEN}✓${NC} $tool - $desc"
        else
            missing_tools+=("$tool")
            echo -e "  ${YELLOW}✗${NC} $tool - $desc"
        fi
    done

    echo ""

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}${#missing_tools[@]} tools missing.${NC} These improve AI agent capabilities:"
        echo ""
        echo -e "  ${CYAN}Why these tools matter:${NC}"
        echo -e "    • ${GREEN}jq${NC}       - Parse JSON from API responses (critical!)"
        echo -e "    • ${GREEN}shellcheck${NC} - Validate shell scripts before running"
        echo -e "    • ${GREEN}gh${NC}        - Create PRs/issues directly from CLI"
        echo -e "    • ${GREEN}imagemagick${NC} - Compress screenshots for API limits (5MB)"
        echo -e "    • ${GREEN}playwright${NC} - Browser automation, screenshots, QA testing"
        echo ""

        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            tools_choice=3  # Skip in non-interactive mode
            echo -e "  ${YELLOW}⚠${NC} Skipping tool installation in auto mode."
            echo -e "  ${CYAN}→${NC} To install manually: brew install jq shellcheck gh imagemagick"
        else
            echo -e "  ${GREEN}[1]${NC} Install all missing tools ${CYAN}(Recommended)${NC}"
            echo -e "  ${GREEN}[2]${NC} Install critical only (jq, shellcheck)"
            echo -e "  ${GREEN}[3]${NC} Skip for now"
            echo ""
            read -p "  Enter choice [1-3, default 1]: " tools_choice
            tools_choice="${tools_choice:-1}"
        fi

        local tools_to_install=()
        case "$tools_choice" in
            1)
                tools_to_install=("${missing_tools[@]}")
                ;;
            2)
                for tool in jq shellcheck; do
                    # Plain substring membership test, not a regex match.
                    if [[ " ${missing_tools[*]} " == *" $tool "* ]]; then
                        tools_to_install+=("$tool")
                    fi
                done
                ;;
            3)
                echo -e "  ${YELLOW}⚠${NC} Skipped. Some AI features may be limited."
                ;;
        esac

        if [[ ${#tools_to_install[@]} -gt 0 ]]; then
            echo ""
            echo -e "  ${CYAN}Installing ${#tools_to_install[@]} tools...${NC}"
            echo ""

            local installed_count=0
            for tool in "${tools_to_install[@]}"; do
                if install_tool "$tool"; then
                    ((installed_count++)) || true
                fi
            done

            echo ""
            echo -e "  ${GREEN}✓${NC} Installed $installed_count/${#tools_to_install[@]} tools"
        fi
    else
        echo -e "  ${GREEN}All essential tools already installed!${NC}"
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # SUMMARY & PERSISTENCE
    # ═══════════════════════════════════════════════════════════════════════════

    # Determine if all required components are configured
    local all_good=true
    if ! command -v codex &>/dev/null && ! command -v agy &>/dev/null; then
        all_good=false
    fi

    # Display beautiful configuration summary with tier detection
    show_config_summary

    # Offer to persist keys
    if [[ -n "$keys_to_add" ]]; then
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            echo -e "  ${YELLOW}⚠${NC} To persist API keys, add to $shell_profile:"
            echo ""
            echo -e "$keys_to_add" | sed 's/^/    /'
            echo ""
        else
            echo -e "  ${YELLOW}To persist API keys across sessions, add to $shell_profile:${NC}"
            echo ""
            echo -e "$keys_to_add" | sed 's/^/    /'
            echo ""
            read -p "  Add these to $shell_profile automatically? [Y/n] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                echo "" >> "$shell_profile"
                echo "# Claude Octopus API Keys (added by configuration wizard)" >> "$shell_profile"
                echo -e "$keys_to_add" >> "$shell_profile"
                echo -e "  ${GREEN}✓${NC} Added to $shell_profile"
                echo -e "  ${CYAN}→${NC} Run 'source $shell_profile' or restart your terminal"
            fi
            echo ""
        fi
    fi

    # Initialize workspace
    if [[ ! -d "$WORKSPACE_DIR" ]]; then
        init_workspace
    fi

    # Mark setup as complete
    mkdir -p "$WORKSPACE_DIR"
    date '+%Y-%m-%d %H:%M:%S' > "$SETUP_CONFIG_FILE"

    # Final message
    if $all_good; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  🐙 All 8 tentacles are connected and ready to work! 🐙${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${CYAN}What you can do now (just talk naturally in Claude Code):${NC}"
        echo ""
        echo -e "  Research & Exploration:"
        echo -e "    • \"Research OAuth authentication patterns\""
        echo -e "    • \"Explore database architectures for multi-tenant SaaS\""
        echo ""
        echo -e "  Implementation:"
        echo -e "    • \"Build a user authentication system with JWT\""
        echo -e "    • \"Implement rate limiting middleware\""
        echo ""
        echo -e "  Code Review:"
        echo -e "    • \"Review this code for security vulnerabilities\""
        echo -e "    • \"Use adversarial review to critique my implementation\""
        echo ""
        echo -e "  Full Workflows:"
        echo -e "    • \"Research, design, and build a complete dashboard feature\""
        echo ""
        echo -e "  ${YELLOW}Advanced:${NC} You can also run commands directly:"
        echo -e "    ${CYAN}./scripts/orchestrate.sh preflight${NC}  - Verify setup"
        echo -e "    ${CYAN}./scripts/orchestrate.sh status${NC}     - Check providers"
        echo ""
    else
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  🐙 Some tentacles need attention! Run setup again when ready.${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        return 1
    fi

    return 0
}


# ═══════════════════════════════════════════════════════════════════════════════
# FIRST-RUN CHECK & PREFLIGHT CACHE
# ═══════════════════════════════════════════════════════════════════════════════

check_first_run() {
    if [[ ! -f "$SETUP_CONFIG_FILE" ]]; then
        # Check if any required component is missing
        if ! command -v codex &>/dev/null && ! command -v agy &>/dev/null; then
            echo ""
            echo -e "${YELLOW}🐙 First time? Run the configuration wizard to get started:${NC}"
            echo -e "   ${CYAN}./scripts/orchestrate.sh octopus-configure${NC}"
            echo ""
            return 1
        fi
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE: Preflight check caching (saves ~50-200ms per command invocation)
# ═══════════════════════════════════════════════════════════════════════════════

# Check if preflight cache is valid (not expired)
preflight_cache_valid() {
    # Atomic read to prevent TOCTOU race conditions
    local cache_content cache_time current_time cache_age

    cache_content=$(cat "$PREFLIGHT_CACHE_FILE" 2>/dev/null) || return 1
    cache_time=$(echo "$cache_content" | head -1)
    [[ -z "$cache_time" ]] && return 1

    current_time=$(date +%s)
    cache_age=$((current_time - cache_time))

    # Cache valid if less than TTL
    [[ $cache_age -lt $PREFLIGHT_CACHE_TTL ]]
}

# Write preflight cache (stores timestamp and status)
preflight_cache_write() {
    local status="$1"
    mkdir -p "$(dirname "$PREFLIGHT_CACHE_FILE")"
    {
        date +%s
        echo "$status"
    } > "$PREFLIGHT_CACHE_FILE"
}

# Read cached preflight status (0=passed, 1=failed)
preflight_cache_read() {
    tail -1 "$PREFLIGHT_CACHE_FILE" 2>/dev/null || echo "1"
}

# Invalidate preflight cache (call after setup or config changes)
preflight_cache_invalidate() {
    rm -f "$PREFLIGHT_CACHE_FILE" 2>/dev/null || true
    rm -f "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# CODEX OAUTH TOKEN FRESHNESS CHECK
# ═══════════════════════════════════════════════════════════════════════════════


check_codex_auth_freshness() {
    local auth_file="$HOME/.codex/auth.json"

    # Skip if no auth file (API key auth or no codex — handled elsewhere)
    [[ -f "$auth_file" ]] || return 0

    local expires_at=""

    # Parse token expiry: prefer jq, fall back to grep
    if command -v jq &>/dev/null; then
        expires_at=$(jq -r '.expires_at // .expiry // empty' "$auth_file" 2>/dev/null || true)
    fi

    # grep fallback if jq unavailable or returned empty
    if [[ -z "$expires_at" ]]; then
        # Handles both "expires_at" and "expiry" keys, numeric or quoted values
        expires_at=$(grep -oE '"(expires_at|expiry)"\s*:\s*"?([0-9]+)"?' "$auth_file" 2>/dev/null \
            | head -1 | grep -oE '[0-9]+' | tail -1 || true)
    fi

    # If we couldn't parse expiry, skip silently (don't block workflows)
    [[ -n "$expires_at" ]] || return 0

    local current_time
    current_time=$(date +%s)
    local remaining=$((expires_at - current_time))

    if [[ $remaining -le 0 ]]; then
        log ERROR "Codex OAuth token is EXPIRED (expired $((-remaining))s ago)"
        echo -e "  ${RED}✗${NC} Codex OAuth token expired. Run ${CYAN}codex auth${NC} to refresh."
        return 1
    elif [[ $remaining -le 600 ]]; then
        # Token expires within 10 minutes
        local mins_remaining=$((remaining / 60))
        log WARN "Codex OAuth token expires in ${mins_remaining}m. Run 'codex auth' to refresh."
        echo -e "  ${YELLOW}⚠${NC} Codex OAuth token expires in ${mins_remaining}m. Run ${CYAN}codex auth${NC} to refresh."
    else
        log DEBUG "Codex OAuth token valid (expires in $((remaining / 60))m)"
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG UPDATE HELPERS — Fast in-place config field updates
# ═══════════════════════════════════════════════════════════════════════════════

# Updates only the knowledge_work_mode field for instant switching
update_knowledge_mode_config() {
    local new_mode="$1"

    mkdir -p "$(dirname "$USER_CONFIG_FILE")"

    # If config exists, update only the knowledge_work_mode line (fast)
    if [[ -f "$USER_CONFIG_FILE" ]]; then
        # Use sed to update in-place (BSD sed compatible)
        if [[ "$OCTOPUS_PLATFORM" == "Darwin" ]]; then
            # macOS
            sed -i '' "s/^knowledge_work_mode:.*$/knowledge_work_mode: \"$new_mode\"/" "$USER_CONFIG_FILE" 2>/dev/null || {
                # If sed fails, regenerate the file
                load_user_config || true
                save_user_config "${USER_INTENT_PRIMARY:-general}" "${USER_INTENT_ALL:-general}" "${USER_RESOURCE_TIER:-standard}" "$new_mode"
            }
        else
            # Linux
            sed -i "s/^knowledge_work_mode:.*$/knowledge_work_mode: \"$new_mode\"/" "$USER_CONFIG_FILE" 2>/dev/null || {
                # If sed fails, regenerate the file
                load_user_config || true
                save_user_config "${USER_INTENT_PRIMARY:-general}" "${USER_INTENT_ALL:-general}" "${USER_RESOURCE_TIER:-standard}" "$new_mode"
            }
        fi
    else
        # No config exists - create minimal config with just knowledge mode
        cat > "$USER_CONFIG_FILE" << EOF
version: "1.1"
created_at: "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
updated_at: "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"

# User intent - affects persona selection and task routing
intent:
  primary: "general"
  all: [general]

# Resource tier - affects model selection
resource_tier: "standard"

# Knowledge Work Mode (v6.0) - prioritizes research/consulting/writing workflows
knowledge_work_mode: "$new_mode"

# Available API keys (auto-detected)
available_keys:
  openai: false
  agy: false

# Derived settings (auto-configured based on tier + keys)
settings:
  opus_budget: "balanced"
  default_complexity: 2
  prefer_agy_for_analysis: false
  max_parallel_agents: 3
EOF
    fi
}

# Show document-skills recommendation for knowledge mode users (v7.2.2)
# Only shown once to avoid annoyance
show_document_skills_info() {
    cat << 'EOF'

  📄 Recommended for Knowledge Mode:

    document-skills@anthropic-agent-skills provides:
      • PDF reading and analysis
      • DOCX document creation/editing
      • PPTX presentation generation
      • XLSX spreadsheet handling

    To install in Claude Code:
      /plugin install document-skills@anthropic-agent-skills

EOF
}

# Fast update of user intent in config (v7.2.3 - performance optimization)
# Updates only the intent fields for instant configuration
update_intent_config() {
    local new_intent_primary="$1"
    local new_intent_all="${2:-$new_intent_primary}"

    mkdir -p "$(dirname "$USER_CONFIG_FILE")"

    # If config exists, update only the intent lines (fast)
    if [[ -f "$USER_CONFIG_FILE" ]]; then
        # Use sed to update in-place (BSD sed compatible)
        if [[ "$OCTOPUS_PLATFORM" == "Darwin" ]]; then
            # macOS
            sed -i '' "s/^  primary:.*$/  primary: \"$new_intent_primary\"/" "$USER_CONFIG_FILE" 2>/dev/null || {
                # If sed fails, regenerate the file
                load_user_config || true
                save_user_config "$new_intent_primary" "$new_intent_all" "${USER_RESOURCE_TIER:-standard}" "${KNOWLEDGE_WORK_MODE:-false}"
            }
            sed -i '' "s/^  all:.*$/  all: [$new_intent_all]/" "$USER_CONFIG_FILE" 2>/dev/null
        else
            # Linux
            sed -i "s/^  primary:.*$/  primary: \"$new_intent_primary\"/" "$USER_CONFIG_FILE" 2>/dev/null || {
                # If sed fails, regenerate the file
                load_user_config || true
                save_user_config "$new_intent_primary" "$new_intent_all" "${USER_RESOURCE_TIER:-standard}" "${KNOWLEDGE_WORK_MODE:-false}"
            }
            sed -i "s/^  all:.*$/  all: [$new_intent_all]/" "$USER_CONFIG_FILE" 2>/dev/null
        fi
    else
        # No config exists - create full config
        save_user_config "$new_intent_primary" "$new_intent_all" "standard" "false"
    fi
}


# Fast update of resource tier in config (v7.2.3 - performance optimization)
# Updates only the resource_tier field for instant configuration
update_resource_tier_config() {
    local new_tier="$1"

    mkdir -p "$(dirname "$USER_CONFIG_FILE")"

    # If config exists, update only the resource_tier line (fast)
    if [[ -f "$USER_CONFIG_FILE" ]]; then
        # Use sed to update in-place (BSD sed compatible)
        if [[ "$OCTOPUS_PLATFORM" == "Darwin" ]]; then
            # macOS
            sed -i '' "s/^resource_tier:.*$/resource_tier: \"$new_tier\"/" "$USER_CONFIG_FILE" 2>/dev/null || {
                # If sed fails, regenerate the file
                load_user_config || true
                save_user_config "${USER_INTENT_PRIMARY:-general}" "${USER_INTENT_ALL:-general}" "$new_tier" "${KNOWLEDGE_WORK_MODE:-false}"
            }
        else
            # Linux
            sed -i "s/^resource_tier:.*$/resource_tier: \"$new_tier\"/" "$USER_CONFIG_FILE" 2>/dev/null || {
                # If sed fails, regenerate the file
                load_user_config || true
                save_user_config "${USER_INTENT_PRIMARY:-general}" "${USER_INTENT_ALL:-general}" "$new_tier" "${KNOWLEDGE_WORK_MODE:-false}"
            }
        fi
    else
        # No config exists - create full config
        save_user_config "general" "general" "$new_tier" "false"
    fi
}
