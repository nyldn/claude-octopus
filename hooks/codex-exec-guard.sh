#!/bin/bash
# Codex exec guard — blocks bare `codex "prompt"` calls (missing `exec` subcommand)
# PreToolUse hook on Bash. Returns block decision with correction message.
# WHY: `codex "prompt"` launches interactive TUI which fails in non-TTY (Claude Code Bash tool).
#      `codex exec "prompt"` is the correct non-interactive mode.
set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Note: this gate guards correctness (bare `codex "prompt"` hangs in non-TTY),
# not user permission policy — so it runs regardless of bypassPermissions.

INPUT=$(cat 2>/dev/null || true)
[[ -z "$INPUT" ]] && echo '{"decision":"allow"}' && exit 0

# Extract command
if command -v jq &>/dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
else
    COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | cut -d'"' -f4)
fi
[[ -z "$COMMAND" ]] && echo '{"decision":"allow"}' && exit 0

# Match: starts with `codex` but NOT `codex exec`, `codex --version`, `codex --help`, `codex login`, `codex auth`
# Also allow: `which codex`, `command -v codex`, variable assignments containing "codex"
if echo "$COMMAND" | grep -qE '^\s*codex\s' && \
   ! echo "$COMMAND" | grep -qE '^\s*codex\s+(exec|--version|--help|-h|login|auth|completion)\b'; then
    cat <<'BLOCK'
{"permissionDecision":"block","message":"BLOCKED: bare `codex \"prompt\"` launches interactive TUI and fails without a TTY.\n\nUse `codex exec` instead:\n```bash\ncodex exec --full-auto \"YOUR PROMPT\"\n```\n\nWith model: `codex exec --full-auto --model gpt-5.4 \"YOUR PROMPT\"`\n\nSee skill-debate.md lines 53-62 for correct syntax."}
BLOCK
    exit 0
fi

echo '{"decision":"allow"}'
