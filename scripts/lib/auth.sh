#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# v4.2 FEATURE: OPENAI AUTHENTICATION
# Manage Codex CLI authentication via OpenAI subscription
# Extracted from orchestrate.sh
# ═══════════════════════════════════════════════════════════════════════════════

_auth_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Check only for credential presence using Vibe's own Python environment.
# Never launch its interactive CLI, print a secret or migrate keyring entries.
_octo_vibe_keyring_has_key() {
    [[ "${1:-}" == selected ]] || return 1
    case "${OCTOPUS_SKIP_PROVIDER_PROBES:-false}" in true|1) return 1 ;; esac
    local binary shebang interpreter extra lib_dir name
    local -a probe_env
    binary="$(command -v vibe 2>/dev/null)" || return 1
    [[ -f "$binary" ]] || return 1
    shebang="$(head -c 512 "$binary" 2>/dev/null | head -n 1)"
    [[ "$shebang" == '#!'/* ]] || return 1
    read -r interpreter extra <<< "${shebang#\#!}"
    case "$interpreter" in
        /usr/bin/env|/bin/env)
            # Match the simple env shebang only. Resolve the same PATH entry as
            # the CLI without executing env, parsing options or evaluating text.
            [[ "$extra" =~ ^python(3(\.[0-9]+)?)?$ ]] || return 1
            interpreter="$(command -v "$extra" 2>/dev/null)" || return 1
            extra=""
            ;;
    esac
    [[ -z "$extra" && "$interpreter" == /* && -f "$interpreter" && -x "$interpreter" && "${interpreter##*/}" == python* ]] || return 1
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    source "$lib_dir/bounded-probe.sh" 2>/dev/null || return 1
    # A selected external package must not inherit other providers' credentials,
    # proxy settings or language-loader controls. Retain only local OS keyring
    # session information and ordinary runtime paths.
    probe_env=(env -i "PATH=/usr/bin:/bin:/usr/sbin:/sbin" "HOME=$HOME" "TMPDIR=${TMPDIR:-/tmp}")
    for name in USER LOGNAME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_CONFIG_HOME XDG_DATA_HOME VIBE_TEST_DISABLE_KEYRING; do
        [[ -z "${!name:-}" ]] || probe_env+=("${name}=${!name}")
    done
    # The shared supervisor includes termination and cleanup in the 3s budget.
    (
        cd / || exit 1
        _octo_run_bare_probe_with_timeout 3 2 1 \
            "${probe_env[@]}" "$interpreter" -I "$lib_dir/../helpers/vibe-keyring-check.py"
    ) </dev/null >/dev/null 2>&1
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

# Test each supported token separately; blank values do not mask later keys.
_octo_opencode_environment_auth_present() {
    local name
    for name in GITHUB_TOKEN OPENROUTER_API_KEY Z_AI_API_KEY MINIMAX_API_KEY; do
        _octo_value_has_nonwhitespace "${!name:-}" && return 0
    done
    return 1
}

# OpenCode v2 migrated local credentials into SQLite. Store presence is only
# configuration evidence; static discovery must not launch the CLI or open it.
_octo_opencode_auth_store_present() {
    local data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/opencode"
    local database="${OPENCODE_DB:-opencode.db}"
    [[ -f "${data_dir}/auth.json" ]] && return 0
    [[ "$database" != :memory: ]] || return 1
    [[ "$database" == /* ]] || database="${data_dir}/${database}"
    [[ -f "$database" ]] && return 0
    [[ -z "${OPENCODE_DB:-}" ]] || return 1
    for database in "$data_dir"/opencode-*.db; do
        [[ ! -f "$database" ]] || return 0
    done
    return 1
}

# Runtime-only, bounded version detection. Unknown generations cannot safely
# select private-server flags, so real dispatch fails closed.
_octo_opencode_cli_major() (
    # Version metadata needs neither model nor search credentials.
    unset MISTRAL_API_KEY KEENABLE_API_KEY || return 1
    local version
    case "${OCTOPUS_SKIP_PROVIDER_PROBES:-false}" in true|1) return 1 ;; esac
    if ! declare -f _octo_run_bare_probe_with_timeout >/dev/null 2>&1; then
        source "${_auth_lib_dir}/bounded-probe.sh" 2>/dev/null || return 1
    fi
    version="$(_octo_run_bare_probe_with_timeout 3 2 1 opencode --version </dev/null 2>/dev/null)" || return 1
    if [[ "$version" =~ ^(opencode[[:space:]]+)?v?([12])\.[0-9]+\.[0-9]+([+-][[:alnum:].-]+)?$ ]]; then
        printf '%s\n' "${BASH_REMATCH[2]}"
    else
        return 1
    fi
)

# Explicit live check only. Keep all account metadata private. V2 checks the
# same private-server environment used by dispatch, never the shared service.
_octo_opencode_has_saved_login() (
    # Environment-only login still needs Mistral; search credentials never do.
    unset KEENABLE_API_KEY || return 1
    local listing major
    declare -f _octo_run_bare_probe_with_timeout >/dev/null 2>&1 || source "${_auth_lib_dir}/bounded-probe.sh" || return 1
    major="$(_octo_opencode_cli_major)" || return 1
    if [[ "$major" == 2 ]]; then
        listing="$(_octo_run_bare_probe_with_timeout 3 2 1 opencode auth list --standalone --format json </dev/null 2>/dev/null)" || return 1
        if command -v jq >/dev/null 2>&1; then
            printf '%s\n' "$listing" | jq -e '
            type == "array" and any(.[];
                (.id | type == "string" and length > 0) and
                (.connections | type == "array" and any(.[];
                    .type == "credential" or .type == "environment")))' >/dev/null 2>&1
        elif command -v python3 >/dev/null 2>&1; then
            printf '%s\n' "$listing" | python3 -I -c '
import json
import sys

try:
    providers = json.load(sys.stdin)
    valid = isinstance(providers, list) and any(
        isinstance(provider, dict)
        and isinstance(provider.get("id"), str) and bool(provider["id"])
        and isinstance(provider.get("connections"), list)
        and any(isinstance(connection, dict)
                and connection.get("type") in ("credential", "environment")
                for connection in provider["connections"])
        for provider in providers)
except (ValueError, TypeError, RecursionError):
    valid = False
sys.exit(0 if valid else 1)
' >/dev/null 2>&1
        else
            return 1
        fi
    else
        listing="$(_octo_run_bare_probe_with_timeout 3 2 1 opencode auth list </dev/null 2>/dev/null)" || return 1
        listing="$(printf '%s\n' "$listing" | sed $'s/\033\\[[0-9;]*m//g')"
        printf '%s\n' "$listing" | grep -Ec '^[[:space:]│└]*[1-9][0-9]* (credentials?|environment variables?)[[:space:]]*$' >/dev/null
    fi
)
