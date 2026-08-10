#!/bin/bash
# Visual feedback hook for Claude Octopus
# Injects provider indicators when external CLIs execute
# This hook is called before Bash tool executes orchestrate.sh
# Returns additional context to inject into Claude's prompt

BASH_COMMAND="${1:-}"

# Detect provider from command
if [[ "$BASH_COMMAND" =~ orchestrate\.sh.*(probe|grasp|tangle|ink|embrace|grapple|squeeze) ]]; then
    cat <<EOF
{
  "octopus_active": true,
  "indicator": "🐙 Multi-provider orchestration active",
  "providers": ["codex", "agy"],
  "note": "This uses external CLI tools, not Claude subagents"
}
EOF
elif [[ "$BASH_COMMAND" =~ "codex exec" ]]; then
    echo '{"provider": "codex", "indicator": "🔴 Codex CLI executing"}'
elif [[ "$BASH_COMMAND" =~ (agy|antigravity|gemini) ]]; then
    echo '{"provider": "agy", "indicator": "🧭 Antigravity CLI executing"}'
fi

exit 0
