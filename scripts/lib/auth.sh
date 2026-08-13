#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# v4.2 FEATURE: OPENAI AUTHENTICATION
# Manage Codex CLI authentication via OpenAI subscription
# Extracted from orchestrate.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Shared credential-value parsing. Provider admission surfaces must not trust a
# file merely because an assignment exists: blank and quoted-empty values are
# unauthenticated, while a # inside a quoted credential is data, not a comment.
_octo_value_has_nonwhitespace() {
    local value
    value="$(printf '%s\n' "${1:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -n "$value" ]]
}

_octo_strip_unquoted_comment() {
    local input="$1" output="" quote="" char
    local index=0 escaped=0 length=${#1}
    while (( index < length )); do
        char="${input:index:1}"
        if (( escaped )); then
            output="${output}${char}"
            escaped=0
        elif [[ "$quote" == '"' && "$char" == "\\" ]]; then
            output="${output}${char}"
            escaped=1
        elif [[ -z "$quote" && "$char" == "#" ]]; then
            break
        else
            output="${output}${char}"
            if [[ -z "$quote" && ( "$char" == '"' || "$char" == "'" ) ]]; then
                quote="$char"
            elif [[ -n "$quote" && "$char" == "$quote" ]]; then
                quote=""
            fi
        fi
        index=$((index + 1))
    done
    printf '%s\n' "$output"
}

_octo_assignment_has_nonempty_value() {
    local file="$1" key="$2" value
    [[ -f "$file" ]] || return 1

    value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$file" 2>/dev/null | tail -n 1)"
    value="$(printf '%s\n' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    value="$(_octo_strip_unquoted_comment "$value")"
    value="$(printf '%s\n' "$value" | sed 's/[[:space:]]*$//')"
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    _octo_value_has_nonwhitespace "$value"
}

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

# ─────────────────────────────────────────────────────────────────────────────
# Generic OAuth token expiry validator (oco-dar)
# Gemini-CLI-family credentials used by Qwen store `expiry_date` as epoch milliseconds.
# Codex stores `expires_at` as epoch seconds (handled by check_codex_auth above).
#
# Usage: octo_oauth_token_valid <creds_file> [skew_seconds]
# Returns 0 if the file exists AND the token is unexpired (with skew margin).
# Returns 1 if the file is missing, OR expiry_date is absent/unparseable
# (fail-closed: a malformed token must never be dispatched into an interactive
# device-auth flow that can hang a workflow — bug oco-dar).
#
# NOTE: this is a strict check. Use it only for providers whose refresh is NOT
# reliable (qwen free-tier OAuth was EOL'd 2026-04-15, so an expired access
# token never recovers). For refresh-capable providers, the universal hang
# protection is the process-group timeout kill in heartbeat.sh.
octo_oauth_token_valid() {
    local creds_file="$1"
    local skew="${2:-60}"
    [[ -f "$creds_file" ]] || return 1

    local expiry_ms=""
    if command -v jq &>/dev/null; then
        expiry_ms=$(jq -r 'if (.expiry_date | type) == "number" and (.expiry_date == (.expiry_date | floor)) then (.expiry_date | tostring) else empty end' "$creds_file" 2>/dev/null || true)
    elif command -v python3 &>/dev/null; then
        expiry_ms=$(python3 - "$creds_file" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

value = data.get("expiry_date")
if isinstance(value, int) and not isinstance(value, bool):
    print(value)
PY
)
    else
        return 1
    fi

    [[ "$expiry_ms" =~ ^[0-9]+$ ]] || return 1   # fail-closed on missing/garbage
    local expiry_s=$(( expiry_ms / 1000 ))
    local now
    now=$(date +%s)
    (( expiry_s - skew > now ))
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

            # Check Antigravity (the sole Google seat)
            echo ""
            if command -v agy &>/dev/null; then
                echo -e "  Antigravity: ${GREEN}✓ CLI installed${NC}"
                echo "               Launch plain 'agy' and complete browser sign-in if its session needs refreshing"
            else
                echo -e "  Antigravity: ${YELLOW}○ Not configured${NC}"
                echo "               Install agy from Google Antigravity"
            fi
            ;;

        *)
            echo "Unknown auth action: $action"
            echo "Usage: $(basename "$0") auth [login|logout|status]"
            exit 1
            ;;
    esac
}
