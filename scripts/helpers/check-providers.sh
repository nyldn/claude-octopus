#!/usr/bin/env bash
# Claude Octopus — Provider Availability Check
# Single-source script for checking which AI providers are available.
# Used by skills (via Bash tool) to populate the activation banner.
#
# Output format: one line per provider, "name:available" or "name:missing"
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

provider_status() {
    local provider="$1"
    local status="$2"
    if declare -f octo_provider_allowed >/dev/null 2>&1 && ! octo_provider_allowed "$provider"; then
        status="missing"
    fi
    printf "%s:%s\n" "$provider" "$status"
}

cursor_agent_status="missing"
if { ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed "cursor-agent"; } && \
   declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary && \
   { [ -n "${CURSOR_API_KEY:-}" ] || grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null; }; then
    cursor_agent_status="available"
fi

echo "PROVIDER_CHECK_START"
provider_status "codex" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
provider_status "gemini" "$(command -v gemini >/dev/null 2>&1 && echo available || echo missing)"
provider_status "perplexity" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)"
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
        qwen_state="available"   # validator unavailable: legacy behavior
    fi
fi
provider_status "qwen" "$qwen_state"
provider_status "cursor-agent" "$cursor_agent_status"
provider_status "ollama" "$({ ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed "ollama"; } && command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
provider_status "openrouter" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)"
echo "PROVIDER_CHECK_END"
