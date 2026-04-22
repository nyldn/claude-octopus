#!/usr/bin/env bash
# Claude Octopus WorktreeCreate Hook Handler
# Triggered when Claude Code creates a worktree for an isolated agent (v2.1.50+)
#
# v8.29.0: Version-aware worktree setup
# - v2.1.63+: Project configs natively shared — skip .octo/state.json copy
# - v2.1.50-2.1.62: Copy .octo/state.json for workflow state continuity
# - All versions: Inject .octopus-env with provider API keys (always needed)

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

SESSION_ID="${CLAUDE_SESSION_ID:-}"
WORKFLOW_PHASE="${OCTOPUS_WORKFLOW_PHASE:-unknown}"

# Extract worktree path from payload
WORKTREE_PATH=""
if [[ -n "$WORKTREE_DATA" ]]; then
    WORKTREE_PATH=$(echo "$WORKTREE_DATA" | grep -o '"worktreePath"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null || true)
fi

if [[ -z "$WORKTREE_PATH" || ! -d "$WORKTREE_PATH" ]]; then
    echo '{"decision": "continue"}'
    exit 0
fi

# Refuse to write outside expected sandbox roots (defense-in-depth — CC-supplied path)
case "$WORKTREE_PATH" in
    "$HOME"/*|/tmp/*|/private/tmp/*|/var/folders/*) : ;;
    *)
        echo "worktree-setup: refusing to write outside \$HOME, /tmp, or macOS temp dirs: $WORKTREE_PATH" >&2
        echo '{"decision": "continue"}'
        exit 0
        ;;
esac

# v2.1.63+: Skip .octo/state.json copy — project configs are natively shared across worktrees
# v2.1.50-2.1.62: Copy state for workflow continuity (SUPPORTS_WORKTREE_SHARED_CONFIG exported by orchestrate.sh)
if [[ "${SUPPORTS_WORKTREE_SHARED_CONFIG:-false}" != "true" ]]; then
    if [[ -d ".octo" ]]; then
        mkdir -p "$WORKTREE_PATH/.octo"
        if [[ -f ".octo/state.json" ]]; then
            cp ".octo/state.json" "$WORKTREE_PATH/.octo/state.json" 2>/dev/null || true
        fi
    fi
fi

# Always inject .octopus-env — provider API keys are not shared by Claude Code's native worktree support
# umask 077 so the credential file is owner-only before the redirection creates it
(
    umask 077
    {
        [[ -n "${OPENAI_API_KEY:-}" ]] && echo "export OPENAI_API_KEY=\"${OPENAI_API_KEY}\""
        [[ -n "${GEMINI_API_KEY:-}" ]] && echo "export GEMINI_API_KEY=\"${GEMINI_API_KEY}\""
        [[ -n "${PERPLEXITY_API_KEY:-}" ]] && echo "export PERPLEXITY_API_KEY=\"${PERPLEXITY_API_KEY}\""
        [[ -n "${OCTOPUS_WORKFLOW_PHASE:-}" ]] && echo "export OCTOPUS_WORKFLOW_PHASE=\"${OCTOPUS_WORKFLOW_PHASE}\""
        echo "# Worktree created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "# Session: ${SESSION_ID}"
    } > "$WORKTREE_PATH/.octopus-env" 2>/dev/null || true
)
chmod 600 "$WORKTREE_PATH/.octopus-env" 2>/dev/null || true

echo '{"decision": "continue"}'
exit 0
