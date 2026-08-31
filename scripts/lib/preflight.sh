#!/usr/bin/env bash
# lib/preflight.sh — Preflight checks and provider detection
# Extracted from orchestrate.sh (v9.7.x decomposition)
# shellcheck source=/dev/null
_preflight_registry_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_preflight_registry_dir}/provider-registry.sh" 2>/dev/null || true

for _preflight_dependency in provider-allowlist auth provider-routing qwen openai-compatible grok copilot quota-watcher events; do
    # shellcheck source=/dev/null
    source "${_preflight_registry_dir}/${_preflight_dependency}.sh" 2>/dev/null || true
done

if ! declare -f _is_cursor_agent_binary >/dev/null 2>&1; then
    _preflight_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_preflight_lib_dir}/cursor-agent.sh" 2>/dev/null || true
fi

_preflight_agy_configured_model() {
    local model="${OCTOPUS_AGY_MODEL:-}"
    local config_file="${HOME}/.claude-octopus/config/providers.json"
    if [[ -z "$model" && -f "$config_file" ]] && command -v jq >/dev/null 2>&1; then
        model=$(jq -r '.providers.agy.default // empty' "$config_file" 2>/dev/null || true)
    fi
    printf '%s\n' "${model:-default}"
}

_octo_readiness_json_field() {
    local readiness_json="$1" field="$2" jq_bin
    jq_bin="$(type -P jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" ]]; then
        printf '%s' "$readiness_json" | "$jq_bin" -r --arg field "$field" '.[$field] // empty'
        return
    fi

    OCTO_READINESS_JSON="$readiness_json" python3 - "$field" <<'PY'
import json
import os
import sys

value = json.loads(os.environ["OCTO_READINESS_JSON"]).get(sys.argv[1], "")
print("" if value is None else value)
PY
}

_preflight_env_value() {
    local env_text="$1" wanted="$2" key value
    while IFS='=' read -r key value; do
        if [[ "$key" == "$wanted" ]]; then
            printf '%s\n' "$value"
            return 0
        fi
    done <<< "$env_text"
    return 1
}

_preflight_agy_model_status() {
    local model
    model="$(_preflight_agy_configured_model)"
    if ! declare -f validate_agy_model_name >/dev/null 2>&1; then
        printf '%s\n' "unchecked"
        return 0
    fi
    if validate_agy_model_name "$model" >/dev/null 2>&1; then
        printf '%s\n' "ok"
    else
        printf '%s\n' "model-invalid"
    fi
}

_octo_provider_readiness_emit() {
    local provider="$1" status="$2" reason_code="$3" check_kind="$4"
    local checked_at="$5" duration_ms="$6" remediation="$7"

    if command -v jq >/dev/null 2>&1; then
        jq -cn \
            --arg provider "$provider" \
            --arg status "$status" \
            --arg reason_code "$reason_code" \
            --arg check_kind "$check_kind" \
            --arg checked_at "$checked_at" \
            --argjson duration_ms "$duration_ms" \
            --arg remediation "$remediation" \
            '{provider:$provider,status:$status,reason_code:$reason_code,
              check_kind:$check_kind,checked_at:$checked_at,
              duration_ms:$duration_ms,remediation:$remediation}'
        return
    fi

    OCTO_READINESS_PROVIDER="$provider" \
    OCTO_READINESS_STATUS="$status" \
    OCTO_READINESS_REASON="$reason_code" \
    OCTO_READINESS_KIND="$check_kind" \
    OCTO_READINESS_CHECKED_AT="$checked_at" \
    OCTO_READINESS_DURATION_MS="$duration_ms" \
    OCTO_READINESS_REMEDIATION="$remediation" \
        python3 - <<'PY'
import json
import os

print(json.dumps({
    "provider": os.environ["OCTO_READINESS_PROVIDER"],
    "status": os.environ["OCTO_READINESS_STATUS"],
    "reason_code": os.environ["OCTO_READINESS_REASON"],
    "check_kind": os.environ["OCTO_READINESS_KIND"],
    "checked_at": os.environ["OCTO_READINESS_CHECKED_AT"],
    "duration_ms": int(os.environ["OCTO_READINESS_DURATION_MS"]),
    "remediation": os.environ["OCTO_READINESS_REMEDIATION"],
}, separators=(",", ":")))
PY
}

_octo_provider_static_readiness() {
    local provider="$1" status="missing" reason_code="not-installed" remediation=""
    local command_name=""

    if declare -f octo_provider_allowed >/dev/null 2>&1 && ! octo_provider_allowed "$provider"; then
        printf '%s|%s|%s\n' "missing" "disabled" "Enable $provider in the provider allowlist."
        return
    fi

    # Shell/profile fallback is local configuration metadata, not a live probe.
    # Resolve only the credential used by the provider currently being checked.
    if declare -f resolve_provider_env >/dev/null 2>&1; then
        case "$provider" in
            commandcode) [[ -n "${COMMAND_CODE_API_KEY:-}" ]] || resolve_provider_env COMMAND_CODE_API_KEY 2>/dev/null || true ;;
            orcarouter) [[ -n "${ORCAROUTER_API_KEY:-}" ]] || resolve_provider_env ORCAROUTER_API_KEY 2>/dev/null || true ;;
            atlascloud) [[ -n "${ATLASCLOUD_API_KEY:-}" ]] || resolve_provider_env ATLASCLOUD_API_KEY 2>/dev/null || true ;;
            grok) [[ -n "${XAI_API_KEY:-}" ]] || resolve_provider_env XAI_API_KEY 2>/dev/null || true ;;
            vibe) [[ -n "${MISTRAL_API_KEY:-}" ]] || resolve_provider_env MISTRAL_API_KEY 2>/dev/null || true ;;
        esac
    fi

    case "$provider" in
        codex)
            remediation="Install Codex, then run: codex login"
            if command -v codex >/dev/null 2>&1; then
                if [[ -f "${HOME}/.codex/auth.json" ]] || _octo_value_has_nonwhitespace "${OPENAI_API_KEY:-}"; then
                    status="available"; reason_code="ready"; remediation=""
                else
                    status="degraded"; reason_code="auth-missing"; remediation="Run: codex login, or set OPENAI_API_KEY."
                fi
            fi
            ;;
        commandcode)
            command_name="${OCTOPUS_COMMANDCODE_BIN:-}"
            if [[ -z "$command_name" ]]; then
                command -v command-code >/dev/null 2>&1 && command_name="command-code"
                [[ -z "$command_name" ]] && command -v cmd >/dev/null 2>&1 && command_name="cmd"
            fi
            remediation="Install Command Code and configure its API key or CLI session."
            if [[ -n "$command_name" ]] && { [[ -x "$command_name" ]] || command -v "$command_name" >/dev/null 2>&1; }; then
                if _octo_value_has_nonwhitespace "${COMMAND_CODE_API_KEY:-}"; then
                    status="available"; reason_code="ready"; remediation=""
                else
                    status="degraded"; reason_code="live-check-required"; remediation="Run a live preflight to verify the Command Code CLI session."
                fi
            fi
            ;;
        claude)
            remediation="Install Claude Code."
            if command -v claude >/dev/null 2>&1; then
                status="available"; reason_code="ready"; remediation=""
            fi
            ;;
        claude-sdk)
            remediation="Install claude-agent or Claude Code, then set CLAUDE_SDK_API_KEY."
            if command -v claude-agent >/dev/null 2>&1 || command -v claude >/dev/null 2>&1; then
                if _octo_value_has_nonwhitespace "${CLAUDE_SDK_API_KEY:-}"; then
                    status="available"; reason_code="ready"; remediation=""
                else
                    status="degraded"; reason_code="auth-missing"; remediation="Set CLAUDE_SDK_API_KEY."
                fi
            fi
            ;;
        agy)
            remediation="Install Antigravity CLI, then launch plain agy to sign in."
            if command -v agy >/dev/null 2>&1; then
                status="available"; reason_code="ready"; remediation=""
            fi
            ;;
        perplexity)
            remediation="Set PERPLEXITY_API_KEY."
            if _octo_value_has_nonwhitespace "${PERPLEXITY_API_KEY:-}"; then
                status="available"; reason_code="ready"; remediation=""
            fi
            ;;
        openrouter)
            remediation="Set OPENROUTER_API_KEY."
            if _octo_value_has_nonwhitespace "${OPENROUTER_API_KEY:-}"; then
                status="available"; reason_code="ready"; remediation=""
            fi
            ;;
        orcarouter)
            remediation="Set ORCAROUTER_API_KEY."
            if declare -f octo_api_key_provider_is_available >/dev/null 2>&1 &&
               octo_api_key_provider_is_available orcarouter ORCAROUTER_API_KEY; then
                status="available"; reason_code="ready"; remediation=""
            elif _octo_value_has_nonwhitespace "${ORCAROUTER_API_KEY:-}"; then
                status="missing"; reason_code="disabled"; remediation="Enable OrcaRouter in provider configuration."
            fi
            ;;
        atlascloud)
            remediation="Set ATLASCLOUD_API_KEY and ATLASCLOUD_MODEL."
            if _octo_value_has_nonwhitespace "${ATLASCLOUD_API_KEY:-}"; then
                if _octo_value_has_nonwhitespace "${ATLASCLOUD_MODEL:-${OCTOPUS_ATLASCLOUD_MODEL:-${OPENAI_COMPAT_MODEL:-}}}"; then
                    status="available"; reason_code="ready"; remediation=""
                else
                    status="degraded"; reason_code="model-missing"; remediation="Set ATLASCLOUD_MODEL or OCTOPUS_ATLASCLOUD_MODEL."
                fi
            fi
            ;;
        openai-compatible)
            remediation="Set OPENAI_COMPAT_BASE_URL and an API key."
            if declare -f openai_compatible_is_available >/dev/null 2>&1 && openai_compatible_is_available; then
                status="available"; reason_code="ready"; remediation=""
            elif _octo_value_has_nonwhitespace "${OPENAI_COMPAT_BASE_URL:-}" ||
                 _octo_value_has_nonwhitespace "${OPENAI_COMPAT_API_KEY:-}"; then
                status="degraded"; reason_code="config-incomplete"
            fi
            ;;
        cursor-agent)
            remediation="Install Cursor Agent, then run: agent login"
            if declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary; then
                if _octo_value_has_nonwhitespace "${CURSOR_API_KEY:-}" ||
                   grep -Ec '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" >/dev/null 2>&1; then
                    status="available"; reason_code="ready"; remediation=""
                else
                    status="degraded"; reason_code="auth-missing"; remediation="Run: agent login, or set CURSOR_API_KEY."
                fi
            fi
            ;;
        grok)
            remediation="Install Grok CLI, then run: grok login"
            if command -v grok >/dev/null 2>&1; then
                if _octo_value_has_nonwhitespace "${XAI_API_KEY:-}" || [[ -f "${HOME}/.grok/auth.json" ]]; then
                    status="available"; reason_code="ready"; remediation=""
                else
                    status="degraded"; reason_code="auth-missing"; remediation="Run: grok login, or set XAI_API_KEY."
                fi
            fi
            ;;
        qwen)
            remediation="Install Qwen, then set QWEN_API_KEY or configure Coding-Plan."
            if command -v qwen >/dev/null 2>&1; then
                if declare -f qwen_is_usable >/dev/null 2>&1 && qwen_is_usable; then
                    status="available"; reason_code="ready"; remediation=""
                elif [[ "$(qwen_auth_method 2>/dev/null || true)" == "oauth-expired" ]]; then
                    status="degraded"; reason_code="auth-expired"; remediation="Set QWEN_API_KEY or configure Coding-Plan; the retired free OAuth token cannot refresh."
                else
                    status="degraded"; reason_code="auth-missing"
                fi
            fi
            ;;
        ollama)
            remediation="Install Ollama and run: ollama serve"
            if command -v ollama >/dev/null 2>&1; then
                status="degraded"; reason_code="live-check-required"; remediation="Run an explicit live preflight to verify the local Ollama server."
            fi
            ;;
        copilot)
            remediation="Install Copilot CLI, then run: copilot login"
            if command -v copilot >/dev/null 2>&1; then
                if _octo_value_has_nonwhitespace "${COPILOT_GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}" ||
                   [[ -f "${HOME}/.copilot/config.json" ]]; then
                    status="available"; reason_code="ready"; remediation=""
                else
                    status="degraded"; reason_code="auth-missing"
                fi
            fi
            ;;
        vibe)
            remediation="Install Vibe, then run: vibe --setup"
            if command -v vibe >/dev/null 2>&1; then
                if _octo_value_has_nonwhitespace "${MISTRAL_API_KEY:-}" ||
                   _octo_assignment_has_nonempty_value "${HOME}/.vibe/.env" "MISTRAL_API_KEY" ||
                   _octo_assignment_has_nonempty_value "${HOME}/.vibe/config.toml" "api_key"; then
                    status="available"; reason_code="ready"; remediation=""
                else
                    status="degraded"; reason_code="auth-missing"
                fi
            fi
            ;;
        opencode)
            remediation="Install OpenCode, then run: opencode auth login"
            if command -v opencode >/dev/null 2>&1; then
                if [[ -f "${HOME}/.local/share/opencode/auth.json" ]] ||
                   _octo_value_has_nonwhitespace "${GITHUB_TOKEN:-${OPENROUTER_API_KEY:-${Z_AI_API_KEY:-${MINIMAX_API_KEY:-}}}}"; then
                    status="available"; reason_code="ready"; remediation=""
                else
                    status="degraded"; reason_code="auth-missing"
                fi
            fi
            ;;
        *)
            status="missing"; reason_code="unsupported"; remediation="Provider readiness is not registered."
            ;;
    esac

    if [[ "$status" == "available" ]] && declare -f octo_quota_is_dead >/dev/null 2>&1 && octo_quota_is_dead "$provider"; then
        status="degraded"
        reason_code="quota"
        remediation="Wait for the provider quota window to reset or choose another provider."
    fi

    printf '%s|%s|%s\n' "$status" "$reason_code" "$remediation"
}

octo_provider_readiness_result() {
    local requested="${1:-}" check_kind="${2:-static}" provider=""
    local auth_mode health_handler detect_handler static_state status reason_code remediation
    local checked_at started_at finished_at duration_ms=0 live_timeout live_rc=0

    provider="$(octo_provider_canonical "$requested" 2>/dev/null || true)"
    if [[ -z "$provider" ]]; then
        _octo_provider_readiness_emit "${requested:-unknown}" "missing" "unsupported" "$check_kind" \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" 0 "Use a provider registered in Provider Registry 2.0."
        return 0
    fi
    case "$check_kind" in static|live) ;; *) check_kind="static" ;; esac

    # These lookups are the authority for readiness participation and live-probe routing.
    auth_mode="$(octo_provider_auth_mode "$provider" 2>/dev/null || printf 'none')"
    health_handler="$(octo_provider_health_handler "$provider" 2>/dev/null || printf 'none')"
    detect_handler="$(octo_provider_detect_handler "$provider" 2>/dev/null || printf 'none')"
    checked_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    started_at="$(date +%s)"

    if [[ "$detect_handler" == "none" ]] || ! octo_provider_has_capability "$provider" detect; then
        status="missing"; reason_code="not-detectable"; remediation="This provider is not exposed by provider detection."
    else
        static_state="$(_octo_provider_static_readiness "$provider")"
        IFS='|' read -r status reason_code remediation <<EOF
$static_state
EOF
    fi

    if [[ "$check_kind" == "live" && "$health_handler" != "none" ]] &&
       { [[ "$status" == "available" ]] || [[ "$reason_code" == "live-check-required" ]]; }; then
        # Live mode is explicit. Execute the registry-selected health handler in
        # a fresh bounded shell so a provider CLI cannot stall setup or Doctor.
        source "${_preflight_registry_dir}/providers.sh" 2>/dev/null || true
        live_timeout="${OCTOPUS_PROVIDER_LIVE_TIMEOUT:-5}"
        case "$live_timeout" in ''|*[!0-9]*) live_timeout=5 ;; esac
        (( live_timeout > 30 )) && live_timeout=30
        (( live_timeout < 1 )) && live_timeout=1
        if declare -f _octo_run_bare_probe_with_timeout >/dev/null 2>&1; then
            _octo_run_bare_probe_with_timeout "$live_timeout" "$live_timeout" 0 \
                bash -c 'source "$1" 2>/dev/null; "$2" "$3"' _ \
                "${_preflight_registry_dir}/providers.sh" "$health_handler" "$provider" \
                >/dev/null || live_rc=$?
        else
            live_rc=125
        fi
        if [[ "$live_rc" -eq 0 ]]; then
            status="available"
            reason_code="ready"
            remediation=""
            case "$provider" in
                perplexity|openrouter|orcarouter)
                    _octo_run_bare_probe_with_timeout "$live_timeout" "$live_timeout" 0 \
                        bash -c 'source "$1" 2>/dev/null; octo_provider_probe "$2"' _ \
                        "${_preflight_registry_dir}/quota-watcher.sh" "$provider" \
                        >/dev/null || live_rc=$?
                    if [[ "$live_rc" -ne 0 ]]; then
                        status="degraded"
                        reason_code="quota"
                        remediation="Verify the provider credential or wait for its quota window to reset."
                    fi
                    ;;
            esac
        fi
        if [[ "$live_rc" -ne 0 && "$reason_code" != "quota" ]]; then
            status="degraded"
            reason_code="health-failed"
            remediation="Run the provider's authentication or service check, then retry the live preflight."
        fi
        if [[ "$live_rc" -ne 0 ]]; then
            printf 'provider live check failed: %s (exit %s)\n' "$provider" "$live_rc" >&2
        fi
    fi

    # auth_mode is intentionally consulted even though credentials never enter output.
    : "$auth_mode"
    finished_at="$(date +%s)"
    duration_ms=$(( (finished_at - started_at) * 1000 ))
    _octo_provider_readiness_emit "$provider" "$status" "$reason_code" "$check_kind" \
        "$checked_at" "$duration_ms" "$remediation"
}

octo_provider_readiness_all() {
    local check_kind="${1:-static}" provider result
    for provider in $(octo_provider_ids detect); do
        result="$(octo_provider_readiness_result "$provider" "$check_kind" 2> >(cat >&2))" || result=""
        if [[ -n "$result" ]]; then
            printf '%s\n' "$result"
        else
            _octo_provider_readiness_emit "$provider" "degraded" "check-failed" "$check_kind" \
                "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" 0 "Retry preflight and inspect stderr diagnostics."
        fi
    done
}

octo_provider_readiness_legacy() {
    local check_kind="${1:-static}" result provider status
    printf '%s\n' "PROVIDER_CHECK_START"
    while IFS= read -r result; do
        [[ -n "$result" ]] || continue
        provider="$(_octo_readiness_json_field "$result" provider)"
        status="$(_octo_readiness_json_field "$result" status)"
        printf '%s:%s\n' "$provider" "$status"
        if declare -f octo_event_emit >/dev/null 2>&1; then
            octo_event_emit "provider.status" provider="$provider" status="$status" source="check-providers" || true
        fi
    done < <(octo_provider_readiness_all "$check_kind")
    printf '%s\n' "PROVIDER_CHECK_END"
}

# Command: detect-providers
# Output parseable provider status for Claude Code skill
cmd_detect_providers() {
    local readiness_result provider status reason_code env_name env_status
    local cache_file="${WORKSPACE_DIR}/.provider-cache"
    local version_output claude_status claude_version min_version

    echo "Detecting Claude Code version..."
    echo ""
    if declare -f check_claude_version >/dev/null 2>&1; then
        version_output="$(check_claude_version)"
    else
        version_output=$'CLAUDE_CODE_VERSION=unknown\nCLAUDE_CODE_STATUS=unknown\nCLAUDE_CODE_MINIMUM=2.1.14'
    fi
    printf '%s\n' "$version_output"
    echo ""

    claude_status="$(_preflight_env_value "$version_output" CLAUDE_CODE_STATUS 2>/dev/null || printf unknown)"
    claude_version="$(_preflight_env_value "$version_output" CLAUDE_CODE_VERSION 2>/dev/null || printf unknown)"
    min_version="$(_preflight_env_value "$version_output" CLAUDE_CODE_MINIMUM 2>/dev/null || printf 2.1.14)"

    if [[ "$claude_status" == "outdated" ]]; then
        echo "⚠️  WARNING: Claude Code is outdated!"
        echo ""
        echo "  Current version: $claude_version"
        echo "  Required version: $min_version or higher"
        echo ""
        echo "How to update:"
        echo "  npm: npm update -g @anthropic/claude-code"
        echo "  Homebrew: brew upgrade claude-code"
        echo "  Download: https://github.com/anthropics/claude-code/releases"
        echo ""
        echo "After updating, restart Claude Code."
        echo ""
    elif [[ "$claude_status" == "ok" ]]; then
        echo "✓ Claude Code version: $claude_version (meets minimum $min_version)"
        echo ""
    fi

    echo "Detecting providers from shared readiness contract..."
    echo ""
    mkdir -p "$WORKSPACE_DIR"
    {
        printf '# Auto-generated on %s\n' "$(date)"
        printf '# Generated from Provider Registry 2.0 readiness results\n\n'
        printf '%s\n\n' "$version_output"
    } > "$cache_file"
    {
        while IFS= read -r readiness_result; do
            [[ -n "$readiness_result" ]] || continue
            provider="$(_octo_readiness_json_field "$readiness_result" provider)"
            status="$(_octo_readiness_json_field "$readiness_result" status)"
            reason_code="$(_octo_readiness_json_field "$readiness_result" reason_code)"
            env_name="$(printf '%s' "$provider" | tr '[:lower:]-' '[:upper:]_')"
            case "$status" in
                available) env_status="ok" ;;
                degraded)
                    case "$reason_code" in
                        auth-missing|live-check-required) env_status="unauthenticated" ;;
                        *) env_status="$reason_code" ;;
                    esac
                    ;;
                *) env_status="not-installed" ;;
            esac
            printf '%s_STATUS=%s\n' "$env_name" "$env_status"
            if [[ "$provider" == "agy" ]]; then
                printf 'AGY_AUTH=%s\n' "$([[ "$status" == "available" ]] && printf cli || printf none)"
                printf 'AGY_MODEL=%s\n' "$(_preflight_agy_configured_model)"
            fi
            if [[ "$provider" == "commandcode" ]]; then
                printf 'COMMANDCODE_AUTH=%s\n' "$([[ "$status" == "available" ]] && printf api-key || printf none)"
            fi
        done < <(octo_provider_readiness_all static)
        printf '\nCACHE_TIME=%s\n' "$(date +%s)"
    } | tee -a "$cache_file"
    echo ""
    echo "Detection complete. Cache written to $cache_file"
    return 0
}

# Pre-flight dependency validation
# Performance: Uses 1-hour cache to avoid repeated CLI checks
# Supports single-provider mode (only need one of Codex, AGY, or Cursor Agent).
preflight_check() {
    local force_check="${1:-false}"

    # Performance: Return cached result if valid (unless forced)
    if [[ "$force_check" != "true" ]] && preflight_cache_valid; then
        local cached_status
        cached_status=$(preflight_cache_read)
        if [[ "$cached_status" == "0" ]]; then
            log DEBUG "Preflight check: using cached result (passed)"
            return 0
        fi
    fi

    log INFO "Running pre-flight checks... 🐙"
    local errors=0
    local has_codex=false
    local has_agy=false
    local has_cursor_agent=false
    local codex_auth=false
    local agy_auth=false
    local cursor_agent_auth=false
    local readiness status reason remediation

    readiness="$(octo_provider_readiness_result codex static)"
    status="$(_octo_readiness_json_field "$readiness" status)"
    if [[ "$status" != "missing" ]]; then
        has_codex=true
        [[ "$status" == "available" ]] && codex_auth=true
    fi

    readiness="$(octo_provider_readiness_result agy static)"
    status="$(_octo_readiness_json_field "$readiness" status)"
    if [[ "$status" != "missing" ]]; then
        has_agy=true
        [[ "$status" == "available" ]] && agy_auth=true
    fi

    readiness="$(octo_provider_readiness_result cursor-agent static)"
    status="$(_octo_readiness_json_field "$readiness" status)"
    if [[ "$status" != "missing" ]]; then
        has_cursor_agent=true
        [[ "$status" == "available" ]] && cursor_agent_auth=true
    fi

    # v7.9.1: Only need ONE provider to work
    if [[ "$has_codex" == "false" && "$has_agy" == "false" && "$has_cursor_agent" == "false" ]]; then
        echo ""
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ❌ NO AI PROVIDERS FOUND                                     ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "Claude Octopus needs at least ${YELLOW}ONE${NC} external AI provider."
        echo ""
        echo -e "${CYAN}Option 1: Install Codex CLI (OpenAI)${NC}"
        echo -e "  npm install -g @openai/codex"
        echo -e "  codex login  ${DIM}# OAuth recommended${NC}"
        echo ""
        echo -e "${CYAN}Option 2: Install Antigravity CLI (Google)${NC}"
        echo -e "  agy          ${DIM}# complete browser sign-in when prompted${NC}"
        echo ""
        echo -e "${CYAN}Option 3: Install Cursor Agent CLI${NC}"
        echo -e "  curl -fsSL https://cursor.com/install | bash"
        echo -e "  agent login  ${DIM}# Cursor session${NC}"
        echo ""
        echo -e "Run ${GREEN}/octo:setup${NC} for guided configuration."
        echo ""
        preflight_cache_write "1"
        return 1
    fi

    # Check if at least one provider is authenticated
    if [[ "$codex_auth" == "false" && "$agy_auth" == "false" && "$cursor_agent_auth" == "false" ]]; then
        echo ""
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  ⚠️  PROVIDERS FOUND BUT NOT READY                            ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        for provider in codex agy cursor-agent; do
            readiness="$(octo_provider_readiness_result "$provider" static)"
            status="$(_octo_readiness_json_field "$readiness" status)"
            [[ "$status" == "degraded" ]] || continue
            remediation="$(_octo_readiness_json_field "$readiness" remediation)"
            echo -e "${CYAN}${provider}:${NC} ${remediation}"
        done
        echo ""
        echo -e "Run ${GREEN}/octo:setup${NC} for guided configuration."
        echo ""
        preflight_cache_write "1"
        return 1
    fi

    # Show what's available
    local available_providers=""
    [[ "$codex_auth" == "true" ]] && available_providers="${available_providers}Codex "
    [[ "$agy_auth" == "true" ]] && available_providers="${available_providers}Antigravity "
    [[ "$cursor_agent_auth" == "true" ]] && available_providers="${available_providers}Cursor-Agent "
    log INFO "Available providers: $available_providers"

    # v8.48: Codex OAuth token freshness check (P1-A)
    # Warn early if token is expired/expiring — saves a failed smoke test round-trip
    if [[ "$codex_auth" == "true" ]]; then
        if ! check_codex_auth_freshness; then
            # Token expired but another authenticated provider may still work — degrade gracefully
            if [[ "$agy_auth" == "true" ]] || [[ "$cursor_agent_auth" == "true" ]]; then
                if [[ "$agy_auth" == "true" && "$cursor_agent_auth" == "true" ]]; then
                    log WARN "Codex OAuth expired; continuing with Antigravity/Cursor Agent only"
                elif [[ "$agy_auth" == "true" ]]; then
                    log WARN "Codex OAuth expired; continuing with Antigravity only"
                else
                    log WARN "Codex OAuth expired; continuing with Cursor Agent only"
                fi
            else
                log ERROR "Codex OAuth expired and no other authenticated provider"
                preflight_cache_write "1"
                return 1
            fi
        fi
    fi

    # Check Claude CLI (optional - for grapple/squeeze)
    if command -v claude &>/dev/null; then
        log DEBUG "Claude CLI: $(command -v claude)"
    fi

    # v8.16: Detect enterprise backend
    detect_enterprise_backend

    # Check workspace
    if [[ ! -d "$WORKSPACE_DIR" ]]; then
        log WARN "Workspace not initialized. Running init..."
        init_workspace
    fi

    # Legacy plugin name warning (Issue #196)
    # Detect if user still has the old "claude-octopus" install alongside or instead of "octo"
    local claude_plugins_dir="$HOME/.claude/plugins"
    if [[ -d "$claude_plugins_dir/cache/nyldn-plugins/claude-octopus" ]]; then
        log WARN "Legacy install detected: 'claude-octopus' (renamed to 'octo' in v9.0)"
        echo -e "${YELLOW}⚠${NC}  You have a leftover 'claude-octopus' install that causes 'not found in marketplace'."
        echo -e "   Fix: ${CYAN}claude plugin uninstall claude-octopus && claude plugin install octo@nyldn-plugins${NC}"
    fi

    # Check for potentially conflicting plugins (informational only)
    local conflicts=0

    if [[ -d "$claude_plugins_dir/oh-my-claude-code" ]]; then
        log WARN "Detected: oh-my-claude-code (has own cost-aware routing)"
        ((conflicts++)) || true
    fi

    if [[ -d "$claude_plugins_dir/claude-flow" ]]; then
        log WARN "Detected: claude-flow (may spawn competing subagents)"
        ((conflicts++)) || true
    fi

    if [[ -d "$claude_plugins_dir/agents" ]] || [[ -d "$claude_plugins_dir/wshobson-agents" ]]; then
        log WARN "Detected: wshobson/agents (large context consumption)"
        ((conflicts++)) || true
    fi

    if [[ $conflicts -gt 0 ]]; then
        log INFO "Found $conflicts potentially overlapping orchestrator(s)"
        log INFO "  Claude Octopus uses external CLIs, so conflicts are unlikely"
    fi

    if [[ $errors -gt 0 ]]; then
        log ERROR "$errors pre-flight check(s) failed"
        preflight_cache_write "1"  # Cache failure
        return 1
    fi

    log INFO "Pre-flight checks passed 🐙"
    echo -e "${GREEN}✓${NC} All 8 tentacles accounted for and ready to work!"

    # v8.19: Provider smoke test (Issue #34)
    if ! provider_smoke_test "$force_check"; then
        log ERROR "Provider smoke test failed"
        preflight_cache_write "1"
        return 1
    fi

    preflight_cache_write "0"  # Cache success
    return 0
}
