#!/usr/bin/env bash
# cwd-changed.sh — Re-detect project context when working directory changes
# Hook event: CwdChanged (CC v2.1.83+)
# Outputs additionalContext with project type detection for the new directory.

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Read hook input from stdin (JSON with new_cwd field)
INPUT=$(cat 2>/dev/null) || INPUT=""
[[ -z "$INPUT" ]] && exit 0

# Extract new CWD — try jq first, fall back to regex
if command -v jq &>/dev/null; then
    NEW_CWD=$(echo "$INPUT" | jq -r '.new_cwd // empty' 2>/dev/null) || NEW_CWD=""
else
    # Fallback: extract with grep
    NEW_CWD=$(echo "$INPUT" | grep -o '"new_cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"new_cwd"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//' 2>/dev/null) || NEW_CWD=""
fi

[[ -z "$NEW_CWD" || ! -d "$NEW_CWD" ]] && exit 0

# Detect project characteristics
context_hints=""

# Check if it's a git repo
if [[ -d "$NEW_CWD/.git" ]]; then
    context_hints="git-repo"
fi

# Detect language/framework
if [[ -f "$NEW_CWD/package.json" ]]; then
    context_hints="${context_hints:+$context_hints, }node/js"
    if grep -q '"next"' "$NEW_CWD/package.json" 2>/dev/null; then
        context_hints="$context_hints, nextjs"
    fi
    if grep -q '"react"' "$NEW_CWD/package.json" 2>/dev/null; then
        context_hints="$context_hints, react"
    fi
elif [[ -f "$NEW_CWD/pyproject.toml" || -f "$NEW_CWD/setup.py" || -f "$NEW_CWD/requirements.txt" ]]; then
    context_hints="${context_hints:+$context_hints, }python"
elif [[ -f "$NEW_CWD/go.mod" ]]; then
    context_hints="${context_hints:+$context_hints, }go"
elif [[ -f "$NEW_CWD/Cargo.toml" ]]; then
    context_hints="${context_hints:+$context_hints, }rust"
fi

# Detect if it has Claude config
if [[ -d "$NEW_CWD/.claude" ]]; then
    context_hints="${context_hints:+$context_hints, }claude-configured"
fi

# Output context hint if we detected anything useful
if [[ -n "$context_hints" ]]; then
    echo "[octopus] Directory changed to: $NEW_CWD (detected: $context_hints)"
fi

exit 0
