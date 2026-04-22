#!/usr/bin/env bash
# Claude Octopus — Workflow Verification Hook (v9.20.0)
# Fires on Stop event. Detects when a multi-LLM workflow command ran but
# orchestrate.sh was never called — meaning the agent bypassed multi-provider
# dispatch and used only Claude-native tools.
#
# Hook event: Stop
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


STATE_DIR="${HOME}/.claude-octopus/.octo"
SNAPSHOT="${STATE_DIR}/pre-compact-snapshot.json"
SESSION_FILE="${HOME}/.claude-octopus/session.json"

# Check if a workflow was active this session
workflow=""
if [[ -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
    workflow=$(jq -r '.workflow // empty' "$SESSION_FILE" 2>/dev/null)
fi
if [[ -z "$workflow" || "$workflow" == "null" ]] && [[ -f "$SNAPSHOT" ]]; then
    workflow=$(jq -r '.workflow // empty' "$SNAPSHOT" 2>/dev/null)
fi

# No workflow active — nothing to verify
[[ -z "$workflow" || "$workflow" == "null" ]] && exit 0

# Only check multi-LLM workflows (not quick mode, not single-phase)
case "${workflow}" in
    *embrace*|*multi*|*review*|*debate*|*security*|*factory*|*staged*)
        # These workflows MUST use orchestrate.sh or skill dispatch
        ;;
    *)
        exit 0
        ;;
esac

# Check if orchestrate.sh was called by looking for result files
RESULTS_DIR="${HOME}/.claude-octopus/results"
if [[ -d "$RESULTS_DIR" ]]; then
    # Look for result files created in the last 30 minutes
    now=$(date +%s)
    recent_results=0
    for f in "$RESULTS_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        if [[ "$(uname)" == "Darwin" ]]; then
            mod=$(stat -f %m "$f" 2>/dev/null || echo 0)
        else
            mod=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        fi
        age=$(( now - mod ))
        [[ $age -lt 1800 ]] && recent_results=$((recent_results + 1))
    done

    if [[ $recent_results -eq 0 ]]; then
        echo "⚠️  WORKFLOW VERIFICATION: The '${workflow}' workflow ran but produced no result files."
        echo "   This suggests orchestrate.sh was not called and multi-LLM dispatch did not execute."
        echo "   The agent may have used only Claude-native tools instead of dispatching to Codex/Gemini."
        echo "   Consider re-running with /octo:embrace to get proper multi-provider perspectives."
    fi
fi

exit 0
