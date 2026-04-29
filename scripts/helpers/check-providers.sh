#!/usr/bin/env bash
# Claude Octopus — Provider Availability Check
# Single-source script for checking which AI providers are available.
# Used by skills (via Bash tool) to populate the activation banner.
#
# Output format: one line per provider, "name:available" or "name:missing"
# Exit code: always 0 (availability is informational, not an error)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cursor-agent.sh" 2>/dev/null || true

cursor_agent_status="missing"
if declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary && \
   { [ -n "${CURSOR_API_KEY:-}" ] || grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null; }; then
    cursor_agent_status="available"
fi

echo "PROVIDER_CHECK_START"
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
printf "gemini:%s\n" "$(command -v gemini >/dev/null 2>&1 && echo available || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)"
printf "opencode:%s\n" "$(command -v opencode >/dev/null 2>&1 && echo available || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo available || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo available || echo missing)"
printf "cursor-agent:%s\n" "$cursor_agent_status"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
printf "openrouter:%s\n" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)"
echo "PROVIDER_CHECK_END"
