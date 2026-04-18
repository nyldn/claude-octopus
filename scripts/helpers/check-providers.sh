#!/usr/bin/env bash
# Claude Octopus — Provider Availability Check
# Single-source script for checking which AI providers are available.
# Used by skills (via Bash tool) to populate the activation banner.
#
# Output format: one line per provider, "name:available" or "name:missing"
# Exit code: always 0 (availability is informational, not an error)

echo "PROVIDER_CHECK_START"
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
printf "gemini:%s\n" "$(command -v gemini >/dev/null 2>&1 && echo available || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)"
printf "opencode:%s\n" "$(command -v opencode >/dev/null 2>&1 && echo available || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo available || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo available || echo missing)"
printf "cursor-agent:%s\n" "$(command -v agent >/dev/null 2>&1 && agent --version 2>&1 | grep -cE '^20[0-9]{2}\.' >/dev/null && echo available || echo missing)"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
printf "openrouter:%s\n" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)"
echo "PROVIDER_CHECK_END"
