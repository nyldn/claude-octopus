#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# v4.2 FEATURE: OPENAI AUTHENTICATION
# Manage Codex CLI authentication via OpenAI subscription
# Extracted from orchestrate.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Check if Codex is authenticated
# Returns auth method: "api_key", "oauth", or "none"
# Always returns 0 (success) - use the output to determine status
check_codex_auth() {
    # Check for API key first
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo "api_key"
        return 0
    fi

    # Check for Codex CLI auth token
    local auth_file="${HOME}/.codex/auth.json"
    if [[ -f "$auth_file" ]]; then
        # Check if token exists and is not expired
        if command -v jq &> /dev/null; then
            local expires_at
            expires_at=$(jq -r '.expires_at // empty' "$auth_file" 2>/dev/null)
            if [[ -n "$expires_at" ]]; then
                local now
                now=$(date +%s)
                if [[ "$expires_at" -gt "$now" ]]; then
                    echo "oauth"
                    return 0
                fi
            fi
        else
            # No jq, just check file exists
            echo "oauth"
            return 0
        fi
    fi

    echo "none"
    return 0  # Always return 0; caller checks the output string
}

# Handle auth commands
handle_auth_command() {
    local action="${1:-status}"
    shift || true

    case "$action" in
        login)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🔐 Claude Octopus - OpenAI Authentication                ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo ""

            # Check if already authenticated
            local auth_status
            auth_status=$(check_codex_auth)
            if [[ "$auth_status" != "none" ]]; then
                echo -e "${YELLOW}Already authenticated via $auth_status${NC}"
                echo "Use 'logout' to switch accounts."
                return 0
            fi

            # Check if Codex CLI is available
            if ! command -v codex &> /dev/null; then
                echo -e "${RED}Codex CLI not found.${NC}"
                echo "Install it first: npm install -g @openai/codex"
                return 1
            fi

            echo "Starting OpenAI OAuth login..."
            echo "This will open your browser for authentication."
            echo ""

            # Run codex login
            if codex login; then
                echo ""
                echo -e "${GREEN}✓ Successfully authenticated with OpenAI${NC}"
                echo ""
                echo "You can now use Claude Octopus with your OpenAI subscription."
            else
                echo ""
                echo -e "${RED}✗ Authentication failed${NC}"
                echo ""
                echo "Alternative: Set OPENAI_API_KEY environment variable"
                echo "  export OPENAI_API_KEY=\"sk-...\""
                return 1
            fi
            ;;

        logout)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🔐 Claude Octopus - Logout                               ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo ""

            local auth_file="${HOME}/.codex/auth.json"
            if [[ -f "$auth_file" ]]; then
                rm -f "$auth_file"
                echo -e "${GREEN}✓ Logged out from OpenAI OAuth${NC}"
            else
                echo "No OAuth session found."
            fi

            if [[ -n "$OPENAI_API_KEY" ]]; then
                echo ""
                echo -e "${YELLOW}Note: OPENAI_API_KEY is still set in your environment.${NC}"
                echo "Unset it with: unset OPENAI_API_KEY"
            fi
            ;;

        status)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🔐 Claude Octopus - Authentication Status                ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo ""

            local auth_status
            auth_status=$(check_codex_auth)

            case "$auth_status" in
                api_key)
                    echo -e "  OpenAI:  ${GREEN}✓ Authenticated (API Key)${NC}"
                    local key_preview="${OPENAI_API_KEY:0:8}...${OPENAI_API_KEY: -4}"
                    echo -e "  Key:     $key_preview"
                    ;;
                oauth)
                    echo -e "  OpenAI:  ${GREEN}✓ Authenticated (OAuth)${NC}"
                    local auth_file="${HOME}/.codex/auth.json"
                    if command -v jq &> /dev/null && [[ -f "$auth_file" ]]; then
                        local email
                        email=$(jq -r '.email // "unknown"' "$auth_file" 2>/dev/null)
                        echo -e "  Account: $email"
                    fi
                    ;;
                none)
                    echo -e "  OpenAI:  ${RED}✗ Not authenticated${NC}"
                    echo ""
                    echo "  To authenticate:"
                    echo "    • Run: $(basename "$0") login"
                    echo "    • Or set: export OPENAI_API_KEY=\"sk-...\""
                    ;;
            esac

            # Check Gemini
            echo ""
            if [[ -f "$HOME/.gemini/oauth_creds.json" ]]; then
                echo -e "  Gemini:  ${GREEN}✓ Authenticated (OAuth)${NC}"
                local auth_type
                auth_type=$(grep -o '"selectedType"[[:space:]]*:[[:space:]]*"[^"]*"' ~/.gemini/settings.json 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/' || echo "oauth")
                echo -e "  Type:    $auth_type"
            elif [[ -n "$GEMINI_API_KEY" ]]; then
                local gemini_preview="${GEMINI_API_KEY:0:8}...${GEMINI_API_KEY: -4}"
                echo -e "  Gemini:  ${GREEN}✓ Authenticated (API Key)${NC}"
                echo -e "  Key:     $gemini_preview"
            else
                echo -e "  Gemini:  ${YELLOW}○ Not configured${NC}"
                echo "           Run 'gemini' to login OR set GEMINI_API_KEY"
            fi
            ;;

        *)
            echo "Unknown auth action: $action"
            echo "Usage: $(basename "$0") auth [login|logout|status]"
            exit 1
            ;;
    esac
}
