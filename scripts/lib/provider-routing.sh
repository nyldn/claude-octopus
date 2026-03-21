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

# [EXTRACTED to lib/persona-loader.sh] select_opus_mode()

# Agent configurations
# Models (Mar 2026) - Premium defaults for Design Thinking workflows:
# - OpenAI GPT-5.x: gpt-5.4 (premium, OAuth+API), gpt-5.4-pro (API-key only), gpt-5.3-codex, gpt-5.3-codex-spark (fast),
# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# NOTE: get_agent_command_array() removed in v9.7.7 — was dead code with broken
# `-m` flag (#183). Use get_agent_command() which uses the correct `--model` flag.

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Environment isolation for external CLI providers (v8.7.0)
# Returns env prefix that limits environment variables to essentials only
# ═══════════════════════════════════════════════════════════════════════════════
build_provider_env() {
    local provider="$1"

    if [[ "${OCTOPUS_SECURITY_V870:-true}" != "true" ]]; then
        return 0
    fi

    # v9.2.1: Try resolving env vars before building isolated env (Issue #177)
    case "$provider" in
        codex*)
            [[ -z "${OPENAI_API_KEY:-}" ]] && resolve_provider_env "OPENAI_API_KEY" 2>/dev/null
            echo "env -i PATH=$PATH HOME=$HOME OPENAI_API_KEY=${OPENAI_API_KEY:-} TMPDIR=${TMPDIR:-/tmp}"
            ;;
        gemini*)
            [[ -z "${GEMINI_API_KEY:-}" ]] && resolve_provider_env "GEMINI_API_KEY" 2>/dev/null
            [[ -z "${GOOGLE_API_KEY:-}" ]] && resolve_provider_env "GOOGLE_API_KEY" 2>/dev/null
            echo "env -i PATH=$PATH HOME=$HOME GEMINI_API_KEY=${GEMINI_API_KEY:-} GOOGLE_API_KEY=${GOOGLE_API_KEY:-} NODE_NO_WARNINGS=1 TMPDIR=${TMPDIR:-/tmp}"
            ;;
        perplexity*)
            [[ -z "${PERPLEXITY_API_KEY:-}" ]] && resolve_provider_env "PERPLEXITY_API_KEY" 2>/dev/null
            echo "env -i PATH=$PATH HOME=$HOME PERPLEXITY_API_KEY=${PERPLEXITY_API_KEY:-} TMPDIR=${TMPDIR:-/tmp}"
            ;;
        *)
            # Claude and other providers: no isolation needed
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

    # Try sourcing from project .env or ~/.env
    local env_file
    for env_file in "$PWD/.env" "$HOME/.env"; do
        if [[ -f "$env_file" ]]; then
            local val
            val=$(grep -m1 -E "^${var_name}=" "$env_file" 2>/dev/null | cut -d= -f2- | sed 's/^["'\'']\|["'\''"]$//g')
            if [[ -n "$val" ]]; then
                export "$var_name=$val"
                log DEBUG "Resolved $var_name from $env_file (non-interactive shell fallback)"
                return 0
            fi
        fi
    done

    return 1
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
        local codex_model gemini_model
        codex_model=$(jq -r '.providers.codex.model // .providers.codex.default // "gpt-5.4"' "$config_file")
        gemini_model=$(jq -r '.providers.gemini.model // .providers.gemini.default // "gemini-3.1-pro-preview"' "$config_file")
        
        cat > "$tmp_file" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": {
      "default": "$codex_model",
      "fallback": "gpt-5.4",
      "spark": "gpt-5.4",
      "mini": "gpt-5-codex-mini",
      "reasoning": "o3",
      "large_context": "gpt-5.4"
    },
    "gemini": {
      "default": "$gemini_model",
      "fallback": "gemini-3-flash-preview",
      "flash": "gemini-3-flash-preview",
      "image": "gemini-3-pro-image-preview"
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
    "budget": { "codex": "mini", "gemini": "flash" },
    "standard": { "codex": "default", "gemini": "default" },
    "premium": { "codex": "default", "gemini": "default" }
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
        rm -f "/tmp/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
    fi

    local changed=false
    local tmp_file="${config_file}.tmp.$$"
    local content
    content=$(<"$config_file")

    # Map of paths to check for stale models
    local -a stale_paths=(
        '.providers.codex.default'
        '.providers.codex.fallback'
        '.providers.gemini.default'
        '.providers.gemini.fallback'
        '.overrides.codex'
        '.overrides.gemini'
    )

    for path in "${stale_paths[@]}"; do
        local current_val
        current_val=$(echo "$content" | jq -r "$path // empty" 2>/dev/null) || continue
        [[ -z "$current_val" || "$current_val" == "null" ]] && continue

        local replacement=""
        case "$current_val" in
            claude-sonnet-4-5|claude-sonnet-4-5-20250514|claude-3-5-sonnet*|claude-sonnet-4*)
                if [[ "$path" == *codex* ]]; then replacement="gpt-5.4"; fi ;;
            gemini-2.0-flash-thinking*|gemini-2.0-flash-exp*|gemini-exp-*)
                replacement="gemini-3-flash-preview" ;;
            gemini-2.0-pro*|gemini-1.5-pro*|gemini-pro)
                replacement="gemini-3.1-pro-preview" ;;
            gpt-4o*|gpt-4-turbo*|gpt-4-*|o1-*|chatgpt-*)
                replacement="gpt-5.4" ;;
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
        rm -f "/tmp/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
    fi
}

# Set provider model in config file
# Usage: set_provider_model <provider> <model> [--session]
set_provider_model() {
    local provider="$1"
    local model="$2"
    local session_only="${3:-}"
    local config_file="${HOME}/.claude-octopus/config/providers.json"

    # v8.49.0: Provider whitelist validation
    case "$provider" in
        codex|gemini|claude|perplexity|openrouter) ;;
        *)
            if [[ "${4:-}" != "--force" ]]; then
                echo "ERROR: Unknown provider '$provider'. Valid: codex, gemini, claude, perplexity, openrouter" >&2
                echo "  Use --force to set a custom provider (e.g., for local proxies)" >&2
                return 1
            fi
            # With --force, still validate format
            if [[ ! "$provider" =~ ^[a-z0-9-]+$ ]]; then
                echo "ERROR: Invalid provider name format (must be lowercase alphanumeric with hyphens)" >&2
                return 1
            fi
            ;;
    esac

    # Validate model name (v8.49.0 hardened)
    if ! validate_model_name "$model"; then
        echo "ERROR: Invalid model name: '$model'" >&2
        echo "  Model names must not contain shell metacharacters (spaces, ;, |, &, \$, \`, quotes)" >&2
        echo "  Examples: gpt-5.4, gemini-3.1-pro-preview, claude-opus-4.6" >&2
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
      "default": "gpt-5.4",
      "fallback": "gpt-5.4",
      "spark": "gpt-5.4",
      "mini": "gpt-5-codex-mini",
      "reasoning": "o3",
      "large_context": "gpt-5.4"
    },
    "gemini": {
      "default": "gemini-3.1-pro-preview",
      "fallback": "gemini-3-flash-preview",
      "flash": "gemini-3-flash-preview",
      "image": "gemini-3-pro-image-preview"
    }
  },
  "routing": {
    "phases": {
      "deliver": "codex:default",
      "review": "codex:default",
      "security": "codex:reasoning",
      "research": "gemini:default"
    }
  },
  "tiers": {
    "budget": { "codex": "mini", "gemini": "flash" },
    "standard": { "codex": "default", "gemini": "default" },
    "premium": { "codex": "default", "gemini": "default" }
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
    local persistent_cache="/tmp/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
    rm -f "$persistent_cache"
}

# Reset provider model to defaults
# Usage: reset_provider_model <provider|all>
reset_provider_model() {
    local provider="$1"
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
    elif [[ "$provider" =~ ^(codex|gemini|claude|perplexity|openrouter)$ ]]; then
        # Clear specific override (v8.49.0: atomic + jq --arg)
        atomic_json_update "$config_file" 'del(.overrides[$p])' --arg p "$provider"
        echo "✓ Cleared $provider override"
    else
        echo "ERROR: Invalid provider '$provider'. Use 'codex', 'gemini', 'claude', 'perplexity', 'openrouter', or 'all'" >&2
        return 1
    fi

    # v8.49.0: Clear model resolution cache after config change
    local persistent_cache="/tmp/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
    rm -f "$persistent_cache"
}

lock_provider() {
    local provider="$1"
    # v9.5: bash builtin word check (zero subshells)
    if [[ " $LOCKED_PROVIDERS " != *" $provider "* ]]; then
        LOCKED_PROVIDERS="${LOCKED_PROVIDERS:+$LOCKED_PROVIDERS }$provider"
        log WARN "Provider locked out: $provider (will not self-revise)"
    fi
}

is_provider_locked() {
    local provider="$1"
    [[ " $LOCKED_PROVIDERS " == *" $provider "* ]]
}

get_alternate_provider() {
    local locked_provider="$1"
    case "$locked_provider" in
        codex|codex-fast|codex-mini)
            if ! is_provider_locked "gemini"; then
                echo "gemini"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            else
                echo "$locked_provider"  # All locked, use original
            fi
            ;;
        gemini|gemini-fast)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            else
                echo "$locked_provider"
            fi
            ;;
        claude-sonnet|claude*)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "gemini"; then
                echo "gemini"
            else
                echo "$locked_provider"
            fi
            ;;
        *)
            echo "$locked_provider"
            ;;
    esac
}

reset_provider_lockouts() {
    if [[ -n "$LOCKED_PROVIDERS" ]]; then
        log INFO "Resetting provider lockouts (were: $LOCKED_PROVIDERS)"
    fi
    LOCKED_PROVIDERS=""
}

# v8.18.0 Feature: Per-Provider History Files
# Each provider accumulates project-specific knowledge in .octo/providers/{name}-history.md

append_provider_history() {
    local provider="$1"
    local phase="$2"
    local task_brief="$3"
    local learned="$4"

    local history_dir="${WORKSPACE_DIR}/.octo/providers"
    local history_file="$history_dir/${provider}-history.md"
    mkdir -p "$history_dir"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Append structured entry
    cat >> "$history_file" << HISTEOF
### ${phase} | ${timestamp}
**Task:** ${task_brief:0:100}
**Learned:** ${learned:0:200}
---
HISTEOF

    # Cap at 50 entries: count entries and trim oldest if exceeded
    local entry_count
    entry_count=$(grep -c "^### " "$history_file" 2>/dev/null || echo "0")
    if [[ "$entry_count" -gt 50 ]]; then
        local excess=$((entry_count - 50))
        # Remove oldest entries (from top of file)
        local trim_line
        trim_line=$(grep -n "^### " "$history_file" | sed -n "$((excess + 1))p" | cut -d: -f1)
        if [[ -n "$trim_line" && "$trim_line" -gt 1 ]]; then
            tail -n "+$trim_line" "$history_file" > "$history_file.tmp" && mv "$history_file.tmp" "$history_file"
        fi
    fi

    log DEBUG "Appended provider history for $provider (phase: $phase)"
}

read_provider_history() {
    local provider="$1"
    local history_file="${WORKSPACE_DIR}/.octo/providers/${provider}-history.md"

    if [[ -f "$history_file" ]]; then
        cat "$history_file"
    fi
}

build_provider_context() {
    local agent_type="$1"
    local base_provider="${agent_type%%-*}"  # codex-fast -> codex
    local history
    history=$(read_provider_history "$base_provider")

    if [[ -z "$history" ]]; then
        return
    fi

    # Truncate to max 2000 chars for prompt injection
    if [[ ${#history} -gt 2000 ]]; then
        history="${history:0:2000}..."
    fi

    echo "## Provider History (${base_provider})
Recent learnings from this project:
${history}"
}


# ═══════════════════════════════════════════════════════════════════════════════
# COST TRANSPARENCY (v7.18.0 - P0.0, enhanced v8.5)
# ═══════════════════════════════════════════════════════════════════════════════

# Check if provider is using API keys (costs money per call)
is_api_based_provider() {
    local provider="$1"

    case "$provider" in
        codex)
            # Check if using API key (OPENAI_API_KEY) vs auth
            [[ -n "${OPENAI_API_KEY:-}" ]] && return 0
            return 1
            ;;
        gemini)
            # Check if using API key (GEMINI_API_KEY) vs auth
            [[ -n "${GEMINI_API_KEY:-}" ]] && return 0
            return 1
            ;;
        claude)
            # Claude Code is subscription-based, not per-call
            return 1
            ;;
        perplexity)
            # v8.24.0: Perplexity Sonar API (Issue #22)
            [[ -n "${PERPLEXITY_API_KEY:-}" ]] && return 0
            return 1
            ;;
        *)
            # Unknown provider, assume API-based for safety
            return 0
            ;;
    esac
}

