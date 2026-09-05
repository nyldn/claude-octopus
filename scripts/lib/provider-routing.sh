#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# lib/provider-routing.sh — Provider routing, config migration, lockout protocol
# Extracted from orchestrate.sh in v9.7.5
# ═══════════════════════════════════════════════════════════════════════════════
# Functions:
#   build_provider_env, resolve_provider_env, migrate_provider_config,
#   set_provider_model, reset_provider_model, is_api_based_provider,
#   lock_provider, is_provider_locked, get_alternate_provider,
#   reset_provider_lockouts, append_provider_history, read_provider_history,
#   build_provider_context
# ═══════════════════════════════════════════════════════════════════════════════

_provider_registry_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_provider_registry_dir}/provider-registry.sh" || { echo "provider-routing: failed to load provider-registry.sh" >&2; return 1 2>/dev/null || exit 1; }
source "${_provider_registry_dir}/kimi-env.sh" || { echo "provider-routing: failed to load kimi-env.sh" >&2; return 1 2>/dev/null || exit 1; }

# Providers accepted by set_provider_model / reset_provider_model.
#
# Single source of truth. This used to be four hand-maintained copies (two
# matchers plus two user-facing messages) and they had drifted: the reset error
# message omitted openai-compatible and openai-tools even though the matcher
# accepted them. Add a provider here and every site follows.
OCTO_MODEL_CONFIG_PROVIDERS="$(octo_provider_ids model-config)"

octo_model_config_provider_valid() {
    case " ${OCTO_MODEL_CONFIG_PROVIDERS} " in
        *" ${1:-} "*) return 0 ;;
    esac
    return 1
}

octo_model_config_provider_list() {
    printf '%s' "${OCTO_MODEL_CONFIG_PROVIDERS// /, }"
}

_provider_routing_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f octo_model_cache_file >/dev/null 2>&1; then
    source "${_provider_routing_lib_dir}/model-cache-path.sh" 2>/dev/null || true
fi
if ! declare -f octo_model_automatic_target_allowed >/dev/null 2>&1; then
    source "${_provider_routing_lib_dir}/models.sh" || { echo "provider-routing: failed to load models.sh" >&2; return 1 2>/dev/null || exit 1; }
fi

# [EXTRACTED to lib/persona-loader.sh] select_opus_mode()

# Agent configurations
# Models (Mar 2026) - Premium defaults for Design Thinking workflows:
# - OpenAI GPT-5.x: gpt-5.6-sol (frontier), gpt-5.6-terra (balanced), gpt-5.6-luna (budget),
# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# NOTE: get_agent_command_array() removed in v9.7.7 — was dead code with broken
# `-m` flag (#183). Use get_agent_command() which uses the correct `--model` flag.

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Environment isolation for external CLI providers (v8.7.0)
# Populates PROVIDER_ENV_ARRAY with argv tokens that limit environment
# variables to essentials only. This stays safe when PATH contains spaces.
# ═══════════════════════════════════════════════════════════════════════════════
# `env -i` wipes WORKSPACE_DIR, and two shims that run under it mark a provider
# quota/auth-dead: provider adapters report terminal quota and auth failures
# `Individual quota reached`. `octo_quota_dead_file` derives its path from
# WORKSPACE_DIR with a `$HOME/.claude-octopus` fallback, so under `env -i` the
# shim writes the marker to the fallback while orchestrate.sh and
# check-providers.sh read it under `$CLAUDE_PLUGIN_DATA` (set by Claude Code
# v2.1.78+). The mark lands where nobody reads it: the provider keeps
# advertising `available`, is reseated every session, and the user is prompted
# for a retired provider's keychain entry every single run.
#
# Applied as a wrapper rather than per-arm because several arms `return 0` from
# inside the case and would skip a tail hook, and because a per-call-site fix is
# exactly what let the quota downgrade cover four of thirteen providers before
# it moved into `provider_status`.
_octo_provider_env_forward_workspace_dir() {
    [[ ${#PROVIDER_ENV_ARRAY[@]} -gt 0 ]] || return 0
    [[ "${PROVIDER_ENV_ARRAY[0]}" == "env" ]] || return 0
    local _entry
    for _entry in "${PROVIDER_ENV_ARRAY[@]}"; do
        [[ "$_entry" == WORKSPACE_DIR=* ]] && return 0
    done
    PROVIDER_ENV_ARRAY+=("WORKSPACE_DIR=${WORKSPACE_DIR:-$HOME/.claude-octopus}")
    return 0
}

build_provider_env() {
    _octo_build_provider_env_impl "$@"
    local _rc=$?
    _octo_provider_env_forward_workspace_dir
    return "$_rc"
}

_octo_build_provider_env_impl() {
    local provider
    provider="$(octo_provider_canonical "${1:-}" 2>/dev/null || printf '%s' "${1:-}")"
    PROVIDER_ENV_ARRAY=()

    if [[ "${OCTOPUS_SECURITY_V870:-true}" != "true" ]]; then
        return 0
    fi

    # v9.23: Propagate W3C trace headers into isolated env when present so
    # external CLIs (codex/agy/perplexity) participate in distributed traces.
    # SUPPORTS_TRACEPARENT was detected in v2.1.98+ (Bash subprocesses) and
    # v2.1.110+ added the same for SDK/headless sessions.
    local -a _trace_env=()
    if [[ -n "${TRACEPARENT:-}" ]]; then
        _trace_env+=("TRACEPARENT=${TRACEPARENT}")
    fi
    if [[ -n "${TRACESTATE:-}" ]]; then
        _trace_env+=("TRACESTATE=${TRACESTATE}")
    fi

    # v9.2.1: Try resolving env vars before building isolated env (Issue #177)
    case "$provider" in
        codex*)
            if [[ -z "${OPENAI_API_KEY:-}" ]]; then
                resolve_provider_env "OPENAI_API_KEY" 2>/dev/null || true
            fi

            # Preserve Codex CLI provider configuration while keeping env
            # isolation. Codex supports OpenAI-compatible providers via
            # config.toml, where env_key may name a provider-specific key
            # (for example a router/proxy key) rather than OPENAI_API_KEY.
            local _codex_config_home="${CODEX_HOME:-$HOME/.codex}"
            local _codex_config="${_codex_config_home}/config.toml"
            local _codex_env_key=""
            if [[ -f "$_codex_config" ]]; then
                _codex_env_key=$(sed -nE 's/^[[:space:]]*env_key[[:space:]]*=[[:space:]]*"([A-Za-z_][A-Za-z0-9_]*)".*/\1/p' "$_codex_config" | head -1)
                if [[ -n "$_codex_env_key" && "$_codex_env_key" != "OPENAI_API_KEY" ]]; then
                    resolve_provider_env "$_codex_env_key" 2>/dev/null || true
                fi
            fi

            PROVIDER_ENV_ARRAY=(env -i "PATH=$PATH" "HOME=$HOME" "OPENAI_API_KEY=${OPENAI_API_KEY:-}" "TMPDIR=${TMPDIR:-/tmp}")
            if [[ -n "${CODEX_HOME:-}" ]]; then
                PROVIDER_ENV_ARRAY+=("CODEX_HOME=${CODEX_HOME}")
            fi
            if [[ -n "$_codex_env_key" && "$_codex_env_key" != "OPENAI_API_KEY" && -n "${!_codex_env_key:-}" ]]; then
                PROVIDER_ENV_ARRAY+=("${_codex_env_key}=${!_codex_env_key}")
            fi
            # codex has NO flag to disable its OSS/local-model auto-download
            # (verified against `codex exec --help`). Octopus instead gates that
            # pull externally via helpers/codex-run.sh. That shim runs inside this
            # isolated env, so forward the pull-guard opt-in contract here —
            # otherwise `env -i` strips it and the shim would refuse every OSS
            # dispatch (or, worse if absent, never see the user's opt-in/cap).
            local _oss_var
            for _oss_var in OCTOPUS_OLLAMA_ALLOW_PULL OCTOPUS_OLLAMA_MAX_PULL_GB OCTOPUS_OLLAMA_BIN OCTOPUS_CODEX_OSS_PATTERNS; do
                if [[ -n "${!_oss_var:-}" ]]; then
                    PROVIDER_ENV_ARRAY+=("${_oss_var}=${!_oss_var}")
                fi
            done
            if [[ ${#_trace_env[@]} -gt 0 ]]; then
                PROVIDER_ENV_ARRAY+=("${_trace_env[@]}")
            fi
            ;;
        commandcode*)
            if [[ -z "${COMMAND_CODE_API_KEY:-}" ]]; then
                resolve_provider_env "COMMAND_CODE_API_KEY" 2>/dev/null || true
            fi
            PROVIDER_ENV_ARRAY=(env -i "PATH=$PATH" "HOME=$HOME" "TMPDIR=${TMPDIR:-/tmp}")
            [[ -n "${COMMAND_CODE_API_KEY:-}" ]] && PROVIDER_ENV_ARRAY+=("COMMAND_CODE_API_KEY=${COMMAND_CODE_API_KEY}")
            [[ -n "${CMD_ZDR:-}" ]] && PROVIDER_ENV_ARRAY+=("CMD_ZDR=${CMD_ZDR}")
            [[ -n "${OCTOPUS_COMMANDCODE_BIN:-}" ]] && PROVIDER_ENV_ARRAY+=("OCTOPUS_COMMANDCODE_BIN=${OCTOPUS_COMMANDCODE_BIN}")
            [[ ${#_trace_env[@]} -gt 0 ]] && PROVIDER_ENV_ARRAY+=("${_trace_env[@]}")
            return 0
            ;;
        agy*|antigravity)
            # Antigravity defaults to a minimal environment. Users who need
            # desktop/session inheritance can explicitly allow the full env.
            if [[ "${OCTOPUS_ALLOW_FULL_AGY_ENV:-false}" == "true" ]]; then
                if [[ "${OCTOPUS_SECURITY_V870:-true}" == "true" ]] && declare -f log_warn >/dev/null 2>&1; then
                    log_warn "Antigravity CLI inherits the parent shell environment because OCTOPUS_ALLOW_FULL_AGY_ENV=true."
                fi
                PROVIDER_ENV_ARRAY=()
            else
                PROVIDER_ENV_ARRAY=(env -i "PATH=$PATH" "HOME=$HOME" "TERM=${TERM:-dumb}" "TMPDIR=${TMPDIR:-/tmp}")
                if [[ -n "${AGY_AUTH_TOKEN:-}" ]]; then
                    PROVIDER_ENV_ARRAY+=("AGY_AUTH_TOKEN=${AGY_AUTH_TOKEN}")
                fi
                if [[ -n "${AGY_CONFIG:-}" ]]; then
                    PROVIDER_ENV_ARRAY+=("AGY_CONFIG=${AGY_CONFIG}")
                fi
                if [[ -n "${ANTIGRAVITY_API_KEY:-}" ]]; then
                    PROVIDER_ENV_ARRAY+=("ANTIGRAVITY_API_KEY=${ANTIGRAVITY_API_KEY}")
                fi
                # The bundled agy adapter runs inside this isolated environment,
                # so its documented safety and behavior controls must cross the
                # env -i boundary. These are configuration values, never ambient
                # credentials or arbitrary parent-shell state.
                local _agy_adapter_var
                for _agy_adapter_var in \
                    OCTOPUS_AGY_MODEL \
                    OCTOPUS_AGY_PRINT_TIMEOUT \
                    OCTOPUS_AGY_MAX_PAYLOAD_BYTES \
                    OCTOPUS_AGY_FORCE_INLINE \
                    OCTOPUS_AGY_NO_PTY_FALLBACK \
                    OCTOPUS_AGY_NO_RETRY \
                    OCTOPUS_AGY_SANDBOX \
                    OCTOPUS_AGY_INCLUDE_DIRS; do
                    if [[ -n "${!_agy_adapter_var:-}" ]]; then
                        PROVIDER_ENV_ARRAY+=("${_agy_adapter_var}=${!_agy_adapter_var}")
                    fi
                done
                if [[ ${#_trace_env[@]} -gt 0 ]]; then
                    PROVIDER_ENV_ARRAY+=("${_trace_env[@]}")
                fi
            fi
            ;;
        kimi*)
            # Kimi defaults to a minimal environment (parity with codex/grok/agy).
            if [[ "${OCTOPUS_ALLOW_FULL_KIMI_ENV:-false}" == "true" ]]; then
                if [[ "${OCTOPUS_SECURITY_V870:-true}" == "true" ]] && declare -f log_warn >/dev/null 2>&1; then
                    log_warn "Kimi Code CLI inherits the parent shell environment because OCTOPUS_ALLOW_FULL_KIMI_ENV=true."
                fi
                PROVIDER_ENV_ARRAY=()
            else
                octopus_build_kimi_provider_env
                PROVIDER_ENV_ARRAY=("${KIMI_PROVIDER_ENV_ARRAY[@]}")
                if [[ ${#_trace_env[@]} -gt 0 ]]; then
                    PROVIDER_ENV_ARRAY+=("${_trace_env[@]}")
                fi
            fi
            ;;
        grok*)
            # Grok defaults to a minimal environment (parity with codex/agy).
            # Users needing full desktop/session inheritance can opt out.
            if [[ "${OCTOPUS_ALLOW_FULL_GROK_ENV:-false}" == "true" ]]; then
                if [[ "${OCTOPUS_SECURITY_V870:-true}" == "true" ]] && declare -f log_warn >/dev/null 2>&1; then
                    log_warn "Grok CLI inherits the parent shell environment because OCTOPUS_ALLOW_FULL_GROK_ENV=true."
                fi
                PROVIDER_ENV_ARRAY=()
            else
                if [[ -z "${XAI_API_KEY:-}" ]] && declare -f resolve_provider_env >/dev/null 2>&1; then
                    resolve_provider_env "XAI_API_KEY" 2>/dev/null || true
                fi
                PROVIDER_ENV_ARRAY=(env -i "PATH=$PATH" "HOME=$HOME" "TERM=${TERM:-dumb}" "TMPDIR=${TMPDIR:-/tmp}")
                if [[ -n "${XAI_API_KEY:-}" ]]; then
                    PROVIDER_ENV_ARRAY+=("XAI_API_KEY=${XAI_API_KEY}")
                fi
                if [[ ${#_trace_env[@]} -gt 0 ]]; then
                    PROVIDER_ENV_ARRAY+=("${_trace_env[@]}")
                fi
            fi
            ;;
        cursor-agent*)
            # Cursor CLI defaults to a minimal environment (parity with codex/agy/grok).
            # HOME must cross the boundary: `agent login` session state lives under
            # ~/.cursor. Users needing full desktop/session inheritance can opt out.
            if [[ "${OCTOPUS_ALLOW_FULL_CURSOR_AGENT_ENV:-false}" == "true" ]]; then
                if [[ "${OCTOPUS_SECURITY_V870:-true}" == "true" ]] && declare -f log_warn >/dev/null 2>&1; then
                    log_warn "Cursor CLI inherits the parent shell environment because OCTOPUS_ALLOW_FULL_CURSOR_AGENT_ENV=true."
                fi
                PROVIDER_ENV_ARRAY=()
            else
                if [[ -z "${CURSOR_API_KEY:-}" ]] && declare -f resolve_provider_env >/dev/null 2>&1; then
                    resolve_provider_env "CURSOR_API_KEY" 2>/dev/null || true
                fi
                PROVIDER_ENV_ARRAY=(env -i "PATH=$PATH" "HOME=$HOME" "TERM=${TERM:-dumb}" "TMPDIR=${TMPDIR:-/tmp}")
                if [[ -n "${CURSOR_API_KEY:-}" ]]; then
                    PROVIDER_ENV_ARRAY+=("CURSOR_API_KEY=${CURSOR_API_KEY}")
                fi
                # Cursor adapter controls are configuration, never credentials.
                local _cursor_adapter_var
                for _cursor_adapter_var in \
                    OCTOPUS_CURSOR_AGENT_MODEL \
                    OCTOPUS_CURSOR_AGENT_MODE \
                    OCTOPUS_CURSOR_AGENT_TIMEOUT \
                    OCTOPUS_CURSOR_AGENT_PROBE_TIMEOUT; do
                    if [[ -n "${!_cursor_adapter_var:-}" ]]; then
                        PROVIDER_ENV_ARRAY+=("${_cursor_adapter_var}=${!_cursor_adapter_var}")
                    fi
                done
                if [[ ${#_trace_env[@]} -gt 0 ]]; then
                    PROVIDER_ENV_ARRAY+=("${_trace_env[@]}")
                fi
            fi
            ;;
        perplexity*)
            # perplexity_execute is a shell function — env -i cannot exec it (#300)
            if [[ -z "${PERPLEXITY_API_KEY:-}" ]]; then
                resolve_provider_env "PERPLEXITY_API_KEY" 2>/dev/null || true
            fi
            return 0
            ;;
        openrouter*)
            # openrouter_execute is a shell function — env -i cannot exec it (#300)
            if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
                resolve_provider_env "OPENROUTER_API_KEY" 2>/dev/null || true
            fi
            return 0
            ;;
        orcarouter*)
            # orcarouter_execute is a shell function — env -i cannot exec it (#300)
            if [[ -z "${ORCAROUTER_API_KEY:-}" ]]; then
                resolve_provider_env "ORCAROUTER_API_KEY" 2>/dev/null || true
            fi
            return 0
            ;;
        claude-sdk*)
            # v9.50.0: Agent SDK seat — the shim strips session markers and sets
            # ANTHROPIC_API_KEY itself; just make sure the SDK key is resolvable.
            if [[ -z "${CLAUDE_SDK_API_KEY:-}" ]] && declare -f resolve_provider_env >/dev/null 2>&1; then
                resolve_provider_env "CLAUDE_SDK_API_KEY" 2>/dev/null || true
            fi
            return 0
            ;;
        claude*)
            # A headless claude (or clarp wrapping it) must NOT inherit the parent
            # Claude Code session markers, or the inner `claude` hangs thinking it
            # is a nested child (council/agent-sync seat stalls at 0 bytes until
            # timeout). Strip them; keep the rest of the env (PATH/HOME/auth).
            PROVIDER_ENV_ARRAY=(env -u CLAUDECODE -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH)
            if [[ ${#_trace_env[@]} -gt 0 ]]; then
                PROVIDER_ENV_ARRAY+=("${_trace_env[@]}")
            fi
            ;;
        *)
            # Other providers: no isolation needed
            return 0
            ;;
    esac
}

# Extracted to lib/models.sh: get_model_catalog, is_known_model, get_model_capability, list_models

# ═══════════════════════════════════════════════════════════════════════════════
# PRE-DISPATCH HEALTH CHECKS (v8.49.0)
# Verify provider CLI availability and credentials before running agents.
# ═══════════════════════════════════════════════════════════════════════════════

# v9.2.1: Resolve provider env vars that may be missing in non-interactive shells.
# On Ubuntu/Debian, ~/.bashrc has an interactive guard that skips env var exports
# when running from non-interactive shells (e.g. Claude Code's Bash tool).
# This function tries common alternative sources before giving up.
resolve_provider_env() {
    local var_name="$1"

    # var_name is interpolated into a `bash -c` program and into `export
    # "$var_name=..."` below. Today's only dynamic caller (the Codex config.toml
    # env_key path) filters it first, but validate here too so this stays safe
    # if a future caller passes something less controlled.
    if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        log DEBUG "resolve_provider_env: refusing invalid variable name '$var_name'"
        return 1
    fi

    # Already set — nothing to do
    [[ -n "${!var_name:-}" ]] && return 0

    # Try sourcing from ~/.profile (login shell config, no interactive guard)
    # Use a sentinel to isolate the var value from any stdout the profile may emit
    if [[ -f "$HOME/.profile" ]]; then
        local val
        val=$(bash -c "source \"\$HOME/.profile\" >/dev/null 2>&1; echo \"__OCTOPUS_ENV__\${${var_name}:-}\"" 2>/dev/null | grep '^__OCTOPUS_ENV__' | sed 's/^__OCTOPUS_ENV__//')
        if [[ -n "$val" ]]; then
            export "$var_name=$val"
            log DEBUG "Resolved $var_name from ~/.profile (non-interactive shell fallback)"
            return 0
        fi
    fi

    # Try static assignments from project/user env files and legacy shell rc
    # files. Do not source .bashrc/.zshrc: they may contain interactive commands
    # or arbitrary startup code. Reject dynamic values rather than evaluating
    # substitutions while recovering credentials from older installations.
    local env_file
    for env_file in "$PWD/.env" "$HOME/.env" "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$env_file" ]]; then
            local assignment val
            assignment=$(grep -m1 -E "^[[:space:]]*(export[[:space:]]+)?${var_name}=" "$env_file" 2>/dev/null || true)
            val="${assignment#*=}"
            val=$(printf '%s' "$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["'\'']\|["'\''"]$//g')
            if [[ "$val" == *'$'* || "$val" == *'`'* ]]; then
                continue
            fi
            if [[ -n "$val" ]]; then
                export "$var_name=$val"
                log DEBUG "Resolved $var_name from $env_file (non-interactive shell fallback)"
                return 0
            fi
        fi
    done

    return 1
}

# API-key providers are dispatchable only when the key exists and an explicit
# providers-config entry has both availability flags enabled. A missing provider
# section remains backward compatible with pre-provider config files: the live
# key is authoritative until the user explicitly configures the provider.
octo_api_key_provider_is_available() {
    local provider="$1"
    local env_var="$2"
    local config_file="${PROVIDERS_CONFIG_FILE:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}/.providers-config}"
    local configured_state="absent"

    provider="$(octo_provider_canonical "$provider" 2>/dev/null || printf '%s' "$provider")"
    if declare -f octo_provider_allowed >/dev/null 2>&1 && ! octo_provider_allowed "$provider"; then
        return 1
    fi
    if [[ -z "${!env_var:-}" ]]; then
        resolve_provider_env "$env_var" 2>/dev/null || true
    fi
    [[ -n "${!env_var:-}" ]] || return 1

    if [[ -f "$config_file" ]]; then
        configured_state="$(awk -v target="$provider" '
            /^  [[:alnum:]_-]+:[[:space:]]*$/ {
                section = $0
                sub(/^  /, "", section)
                sub(/:[[:space:]]*$/, "", section)
                in_target = (section == target)
                if (in_target) seen = 1
                next
            }
            in_target && /^    enabled:[[:space:]]*/ {
                enabled = $0
                sub(/^    enabled:[[:space:]]*/, "", enabled)
                gsub(/[[:space:]\"]/, "", enabled)
            }
            in_target && /^    api_key_set:[[:space:]]*/ {
                key_set = $0
                sub(/^    api_key_set:[[:space:]]*/, "", key_set)
                gsub(/[[:space:]\"]/, "", key_set)
            }
            END {
                if (seen) print enabled "|" key_set
                else print "absent"
            }
        ' "$config_file" 2>/dev/null)" || return 1
    fi

    [[ "$configured_state" == "absent" || "$configured_state" == "true|true" ]]
}

# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# Migrate stale model names and structural config changes
# Runs once per session; rewrites config file in-place if migration needed.
_PROVIDER_CONFIG_MIGRATED="${_PROVIDER_CONFIG_MIGRATED:-false}"
migrate_provider_config() {
    [[ "$_PROVIDER_CONFIG_MIGRATED" == "true" ]] && return 0
    _PROVIDER_CONFIG_MIGRATED=true

    local config_file="${HOME}/.claude-octopus/config/providers.json"
    [[ -f "$config_file" ]] || return 0
    command -v jq &>/dev/null || return 0

    local version
    version=$(jq -r '.version // "1.0"' "$config_file" 2>/dev/null)

    # v3.0 Migration (structural refactor)
    if [[ "$version" != "3.0" ]]; then
        log "INFO" "Migrating provider config from v$version to v3.0 schema"
        local tmp_file="${config_file}.tmp.$$"
        
        # Extract existing model preferences to seed v3.0
        local codex_model
        codex_model=$(jq -r '.providers.codex.model // .providers.codex.default // "gpt-5.6-sol"' "$config_file")
        
        cat > "$tmp_file" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": {
      "default": "$codex_model",
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
    "budget": { "codex": "mini", "claude": "budget", "agy": "flash" },
    "standard": { "codex": "default", "claude": "default", "agy": "default" },
    "premium": { "codex": "default", "claude": "opus", "agy": "default" }
  },
  "overrides": {}
}
EOF
        # Preserve overrides if they exist (v8.49.0: use --argjson for safe merge)
        local overrides
        overrides=$(jq -c '.overrides // {}' "$config_file")
        jq --argjson ovr "$overrides" '.overrides = $ovr' "$tmp_file" > "${tmp_file}.2" && mv "${tmp_file}.2" "$config_file"
        rm -f "$tmp_file"
        log "INFO" "Migration to v3.0 complete"

        # v8.49.0: Clear stale model cache after migration
        _octo_cache_to_clear="$(octo_model_cache_file 2>/dev/null)" || _octo_cache_to_clear=""
        [[ -n "$_octo_cache_to_clear" ]] && rm -f "$_octo_cache_to_clear" 2>/dev/null
        unset _octo_cache_to_clear
    fi

    local changed=false
    local tmp_file="${config_file}.tmp.$$"
    local content
    content=$(<"$config_file")

    # Gemini CLI no longer serves individual Google seats. Keep old provider
    # IDs as input aliases, but rewrite persisted config so no future process
    # can rediscover or launch the retired executable. Direct Gemini model IDs
    # are not valid Antigravity CLI labels, so stale exact-model overrides are
    # intentionally reset to Antigravity defaults/capabilities.
    if echo "$content" | jq -e '
        (.providers.gemini? != null) or
        (.overrides.gemini? != null) or
        ([.tiers[]?.gemini?] | any(. != null)) or
        ([.routing.phases[]?, .routing.roles[]?] | any(
            (type == "string" and (startswith("gemini"))) or
            (type == "object" and .provider? == "gemini")
        ))
    ' >/dev/null 2>&1; then
        content=$(echo "$content" | jq '
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
        ' 2>/dev/null) || return 0
        changed=true
        log "INFO" "Migrating retired Gemini provider settings to Antigravity"
    fi

    # Map of paths to check for stale models
    local -a stale_paths=(
        '.providers.codex.default'
        '.providers.codex.fallback'
        '.providers.codex.mini'
        '.overrides.codex'
    )

    for path in "${stale_paths[@]}"; do
        local current_val
        current_val=$(echo "$content" | jq -r "$path // empty" 2>/dev/null) || continue
        [[ -z "$current_val" || "$current_val" == "null" ]] && continue

        local replacement=""
        case "$current_val" in
            gpt-5-codex-mini|gpt-5.1-codex-mini)
                if [[ "$path" == '.providers.codex.mini' ]]; then replacement="gpt-5.6-luna"; fi ;;
            claude-sonnet-4-5|claude-sonnet-4-5-20250514|claude-3-5-sonnet*|claude-sonnet-4*)
                if [[ "$path" == *codex* ]]; then replacement="gpt-5.6-sol"; fi ;;
            gpt-4o*|gpt-4-turbo*|gpt-4-*|o1-*|chatgpt-*)
                replacement="gpt-5.6-sol" ;;
            gpt-5.5|gpt-5.5-pro|gpt-5.4|gpt-5.4-pro|gpt-5.3-codex|gpt-5.2-codex|gpt-5.1-codex-max)
                replacement="gpt-5.6-sol" ;;  # gpt-5.x line predates GPT-5.6 (#798). Exact names, not wildcards —
                                               # gpt-5.4-mini/gpt-5.3-codex-spark are distinct current tiers, not stale
        esac

        if [[ -n "$replacement" ]]; then
            log "WARN" "Migrating stale model in config: ${path} '${current_val}' → '${replacement}'"
            # v8.49.0: Use --arg to prevent injection via model names
            content=$(echo "$content" | jq --arg val "$replacement" "${path} = \$val" 2>/dev/null) || continue
            changed=true
        fi
    done

    if [[ "$changed" == "true" ]]; then
        echo "$content" > "$tmp_file" && mv "$tmp_file" "$config_file"
        log "INFO" "Updated ${config_file} with current model names"
        # v8.49.0: Clear model cache after stale name migration
        _octo_cache_to_clear="$(octo_model_cache_file 2>/dev/null)" || _octo_cache_to_clear=""
        [[ -n "$_octo_cache_to_clear" ]] && rm -f "$_octo_cache_to_clear" 2>/dev/null
        unset _octo_cache_to_clear
    fi
}

# Set provider model in config file
# Usage: set_provider_model <provider> <model> [--session]
set_provider_model() {
    local provider
    provider="$(octo_provider_canonical "${1:-}" 2>/dev/null || printf '%s' "${1:-}")"
    local model="$2"
    local session_only="${3:-}"
    local config_file="${HOME}/.claude-octopus/config/providers.json"

    # v8.49.0: Provider whitelist validation
    if ! octo_model_config_provider_valid "$provider"; then
        if [[ "${4:-}" != "--force" ]]; then
            echo "ERROR: Unknown provider '$provider'. Valid: $(octo_model_config_provider_list)" >&2
            echo "  Use --force to set a custom provider (e.g., for local proxies)" >&2
            return 1
        fi
        # With --force, still validate format
        if [[ ! "$provider" =~ ^[a-z0-9-]+$ ]]; then
            echo "ERROR: Invalid provider name format (must be lowercase alphanumeric with hyphens)" >&2
            return 1
        fi
    fi

    # Validate model name (v8.49.0 hardened)
    if ! validate_model_name "$model"; then
        echo "ERROR: Invalid model name: '$model'" >&2
        echo "  Model names must not contain shell metacharacters (spaces, ;, |, &, \$, \`, quotes)" >&2
        echo "  Examples: gpt-5.6-sol, default, claude-opus-5" >&2
        return 1
    fi
    if ! octo_model_automatic_target_allowed "$model"; then
        echo "ERROR: '$model' is explicit-only and cannot be stored in providers.json" >&2
        echo "  Use a one-command environment pin or an exact model-qualified seat" >&2
        return 1
    fi

    # Ensure config file exists and is v3.0
    if [[ ! -f "$config_file" ]]; then
        mkdir -p "$(dirname "$config_file")"
        cat > "$config_file" << 'EOF'
{
  "version": "3.0",
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
    }
  },
  "routing": {
    "phases": {
      "deliver": "codex:default",
      "review": "codex:default",
      "security": "codex:reasoning",
      "research": "agy"
    }
  },
  "tiers": {
    "budget": { "codex": "mini", "claude": "budget", "agy": "flash" },
    "standard": { "codex": "default", "claude": "default", "agy": "default" },
    "premium": { "codex": "default", "claude": "opus", "agy": "default" }
  },
  "overrides": {}
}
EOF
    else
        migrate_provider_config
    fi

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq is required for model configuration" >&2
        return 1
    fi

    # Update config file (v8.49.0: atomic + jq --arg for injection safety)
    if [[ "$session_only" == "--session" ]]; then
        atomic_json_update "$config_file" '.overrides[$p] = $m' --arg p "$provider" --arg m "$model"
        echo "✓ Set session override: $provider → $model"
    else
        atomic_json_update "$config_file" '.providers[$p].default = $m' --arg p "$provider" --arg m "$model"
        echo "✓ Set default model: $provider → $model"
    fi

    # v8.49.0: Clear model resolution cache after config change
    local persistent_cache
    persistent_cache="$(octo_model_cache_file 2>/dev/null)" || persistent_cache=""
    rm -f "$persistent_cache"
}

# Reset provider model to defaults
# Usage: reset_provider_model <provider|all>
reset_provider_model() {
    local provider="${1:-}"
    if [[ "$provider" != "all" ]]; then
        provider="$(octo_provider_canonical "$provider" 2>/dev/null || printf '%s' "$provider")"
    fi
    local config_file="${HOME}/.claude-octopus/config/providers.json"

    if [[ ! -f "$config_file" ]]; then
        echo "No configuration file found"
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq is required for model configuration" >&2
        return 1
    fi

    if [[ "$provider" == "all" ]]; then
        # Clear all overrides (v8.49.0: atomic)
        atomic_json_update "$config_file" '.overrides = {}'
        echo "✓ Cleared all model overrides"
    elif octo_model_config_provider_valid "$provider"; then
        # Clear specific override (v8.49.0: atomic + jq --arg)
        atomic_json_update "$config_file" 'del(.overrides[$p])' --arg p "$provider"
        echo "✓ Cleared $provider override"
    else
        echo "ERROR: Invalid provider '$provider'. Use one of: $(octo_model_config_provider_list), or 'all'" >&2
        return 1
    fi

    # v8.49.0: Clear model resolution cache after config change
    local persistent_cache
    persistent_cache="$(octo_model_cache_file 2>/dev/null)" || persistent_cache=""
    rm -f "$persistent_cache"
}

# Provider lockout + history protocol has a single owner: lib/provider-lockout.sh.
# It was previously defined here AND in the sibling file, differing only in the
# fallback provider, so source order silently decided routing behaviour.
if ! declare -f get_alternate_provider >/dev/null 2>&1; then
    _lockout_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    source "${_lockout_dir}/provider-lockout.sh" 2>/dev/null || true
fi




# ═══════════════════════════════════════════════════════════════════════════════
# COST TRANSPARENCY (v7.18.0 - P0.0, enhanced v8.5)
# ═══════════════════════════════════════════════════════════════════════════════

# Check if provider is using API keys (costs money per call)
is_api_based_provider() {
    local provider cost_class
    provider="$(octo_provider_canonical "${1:-}" 2>/dev/null || printf '%s' "${1:-}")"
    cost_class="$(octo_provider_cost_class "$provider" 2>/dev/null || printf '%s' metered)"

    case "$cost_class" in
        metered) return 0 ;;
        bundled|local) return 1 ;;
        variable) ;;
        *) return 0 ;;  # Unknown metadata remains cost-conservative.
    esac

    # Variable providers can use either a subscription/session or a metered
    # credential. Keep only auth-state decisions here; the provider inventory
    # and its base cost policy remain registry-owned.
    case "$provider" in
        codex) [[ -n "${OPENAI_API_KEY:-}" ]] ;;
        commandcode) [[ -n "${COMMAND_CODE_API_KEY:-}" ]] ;;
        qwen)
            if declare -f qwen_auth_method >/dev/null 2>&1 && [[ "$(qwen_auth_method 2>/dev/null || true)" == "oauth" ]]; then
                return 1
            fi
            return 0
            ;;
        *) return 0 ;;  # Variable backend is unknown: assume metered.
    esac
}
