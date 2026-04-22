#!/usr/bin/env bash
# Claude Octopus WorktreeRemove Hook Handler
# Triggered when Claude Code removes a worktree after agent completes (v2.1.50+)
# Cleans up Octopus artifacts from the worktree path

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# Read worktree info from stdin (JSON payload from Claude Code)
WORKTREE_DATA=""
if [[ ! -t 0 ]]; then
    WORKTREE_DATA="$(cat)"
fi

# Extract worktree path from payload
WORKTREE_PATH=""
if [[ -n "$WORKTREE_DATA" ]]; then
    WORKTREE_PATH=$(echo "$WORKTREE_DATA" | grep -o '"worktreePath"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null || true)
fi

if [[ -z "$WORKTREE_PATH" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

# Remove Octopus artifacts from worktree
if [[ -d "$WORKTREE_PATH" ]]; then
    rm -f "$WORKTREE_PATH/.octopus-env" 2>/dev/null || true
    rm -rf "$WORKTREE_PATH/.octo" 2>/dev/null || true
fi

echo '{"decision": "continue"}'
exit 0
