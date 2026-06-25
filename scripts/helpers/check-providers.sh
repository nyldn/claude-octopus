#!/usr/bin/env bash
set -euo pipefail

# Claude Octopus — Provider Availability Check
# Single-source script for checking which AI providers are available.
# Used by skills (via Bash tool) to populate the activation banner.
#
# Output format: one line per provider:
#   name:available — provider can be dispatched
#   name:missing   — provider is absent, disallowed, or lacks required config
#   name:degraded  — provider binary exists but fails a health/auth gate
# Consumers that dispatch providers should match only ":available".
# Exit code: always 0 (availability is informational, not an error)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Self-heal: ensure ~/.claude-octopus/plugin symlink exists before proceeding.
# Marketplace installs may not have the symlink yet if SessionStart hook hasn't
# fired. This is a no-op when the symlink is already healthy. (fixes #377)
bash "${SCRIPT_DIR}/ensure-plugin-root.sh" 2>/dev/null || true

source "${SCRIPT_DIR}/../lib/cursor-agent.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/provider-allowlist.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/auth.sh" 2>/dev/null || true   # octo_oauth_token_valid (oco-dar)
source "${SCRIPT_DIR}/../lib/qwen.sh" 2>/dev/null || true   # qwen_is_usable (oco-dar)
source "${SCRIPT_DIR}/../lib/events.sh" 2>/dev/null || true  # opt-in JSONL lifecycle stream
source "${SCRIPT_DIR}/../lib/quota-watcher.sh" 2>/dev/null || true  # octo_quota_is_dead (oco-cbb)

# oco-cbb: report degraded when a key/binary-present provider was marked
# quota/auth-dead earlier this session (perplexity 401, gemini exhausted), so it
# is skipped instead of re-dispatched into the same failure + timeout.
_octo_provider_state() {
    local provider="$1" present_state="$2"
    if [[ "$present_state" == "available" ]] && declare -f octo_quota_is_dead >/dev/null 2>&1 \
       && octo_quota_is_dead "$provider"; then
        echo "degraded"
    else
        echo "$present_state"
    fi
}

provider_status() {
    local provider="$1"
    local status="$2"
    if declare -f octo_provider_allowed >/dev/null 2>&1 && ! octo_provider_allowed "$provider"; then
        status="missing"
    fi
    printf "%s:%s\n" "$provider" "$status"
    if declare -f octo_event_emit >/dev/null 2>&1; then
        octo_event_emit "provider.status" provider="$provider" status="$status" source="check-providers" || true
    fi
}

cursor_agent_status="missing"
if { ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed "cursor-agent"; } && \
   declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary && \
   { [ -n "${CURSOR_API_KEY:-}" ] || grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null; }; then
    cursor_agent_status="available"
fi

echo "PROVIDER_CHECK_START"
provider_status "codex" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
provider_status "gemini" "$(_octo_provider_state gemini "$(command -v gemini >/dev/null 2>&1 && echo available || echo missing)")"
provider_status "agy" "$(command -v agy >/dev/null 2>&1 && echo available || echo missing)"
# oco-cbb: opt-in proactive probe for API-key providers (perplexity, openrouter).
# Only runs when OCTOPUS_PREFLIGHT_PROBE=1; result cached via quota-dead marker
# so subsequent octo_quota_is_dead reads pick it up automatically.
if [[ "${OCTOPUS_PREFLIGHT_PROBE:-0}" == "1" ]] && declare -f octo_provider_probe >/dev/null 2>&1 \
   && { ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed "perplexity"; }; then
    [ -n "${PERPLEXITY_API_KEY:-}" ] && octo_provider_probe "perplexity" || true
fi
provider_status "perplexity" "$(_octo_provider_state perplexity "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)")"
provider_status "opencode" "$(command -v opencode >/dev/null 2>&1 && echo available || echo missing)"
provider_status "copilot" "$(command -v copilot >/dev/null 2>&1 && echo available || echo missing)"
# qwen: binary-only is not enough — an expired OAuth token (free tier EOL
# 2026-04-15) would dispatch and hang on interactive device-auth (oco-dar).
# Report "degraded" when the binary is present but auth is expired/missing so
# consumers (which match ":available") skip it and the banner can say why.
qwen_state="missing"
if command -v qwen >/dev/null 2>&1; then
    if declare -f qwen_is_usable >/dev/null 2>&1; then
        qwen_is_usable && qwen_state="available" || qwen_state="degraded"
    else
        qwen_state="degraded"   # validator unavailable: fail closed
    fi
fi
provider_status "qwen" "$qwen_state"
provider_status "cursor-agent" "$cursor_agent_status"
provider_status "grok" "$({ ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed grok; } && command -v grok >/dev/null 2>&1 && { [ -n "${XAI_API_KEY:-}" ] || [ -f "${HOME}/.grok/auth.json" ]; } && echo available || echo missing)"
provider_status "ollama" "$({ ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed "ollama"; } && command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
if [[ "${OCTOPUS_PREFLIGHT_PROBE:-0}" == "1" ]] && declare -f octo_provider_probe >/dev/null 2>&1 \
   && { ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed "openrouter"; }; then
    [ -n "${OPENROUTER_API_KEY:-}" ] && octo_provider_probe "openrouter" || true
fi
provider_status "openrouter" "$(_octo_provider_state openrouter "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)")"
echo "PROVIDER_CHECK_END"
