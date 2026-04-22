#!/usr/bin/env bash
# Claude Octopus — PostCompact Hook (v9.19.0)
# Fires AFTER context compaction completes. Reads state persisted by
# pre-compact.sh and re-injects critical workflow context that compaction dropped.
#
# Hook event: PostCompact (CC v2.1.76+, SUPPORTS_POST_COMPACT_HOOK)
# Companion: pre-compact.sh (PreCompact) saves the snapshot this hook reads
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

# Nothing to recover if pre-compact didn't save a snapshot
[[ -f "$SNAPSHOT" ]] || exit 0

# Only inject if snapshot is <10 min old (avoid stale re-injection from old sessions)
now=$(date +%s)
if [[ "$(uname)" == "Darwin" ]]; then
    mod=$(stat -f %m "$SNAPSHOT" 2>/dev/null || echo 0)
else
    mod=$(stat -c %Y "$SNAPSHOT" 2>/dev/null || echo 0)
fi
age=$(( now - mod ))
[[ $age -gt 600 ]] && exit 0

# Guard: require jq for structured reads
command -v jq &>/dev/null || exit 0

# Output context for Claude to see after compaction
phase=$(jq -r '.phase // empty' "$SNAPSHOT" 2>/dev/null)
workflow=$(jq -r '.workflow // empty' "$SNAPSHOT" 2>/dev/null)
autonomy=$(jq -r '.autonomy // empty' "$SNAPSHOT" 2>/dev/null)
completed=$(jq -r '.completed_phases // [] | join(", ")' "$SNAPSHOT" 2>/dev/null)
blockers=$(jq -r '.blockers // [] | join("; ")' "$SNAPSHOT" 2>/dev/null)

if [[ -n "$phase" && "$phase" != "null" ]]; then
    echo "[Octopus PostCompact] Context recovered after compaction:"
    echo "  Phase: ${phase} | Workflow: ${workflow:-unknown} | Autonomy: ${autonomy:-supervised}"
    [[ -n "$completed" && "$completed" != "null" ]] && echo "  Completed: $completed"
    [[ -n "$blockers" && "$blockers" != "null" ]] && echo "  Blockers: $blockers"

    # v9.20.0: Re-inject execution enforcement for active multi-LLM workflows
    # Without this, compaction drops the skill instructions that mandate orchestrate.sh dispatch,
    # and the agent falls back to Claude-native tools (Agent, WebFetch, Write) — silently
    # breaking multi-LLM orchestration.
    case "${workflow:-}" in
        *embrace*|*discover*|*define*|*develop*|*deliver*|*review*|*debate*|*multi*|*security*|*factory*|*research*|*staged*)
            echo ""
            echo "  ⚠️  EXECUTION ENFORCEMENT (re-injected after compaction):"
            echo "  You are mid-workflow. Each remaining phase MUST use orchestrate.sh or"
            echo "  invoke the phase skill (/octo:discover, /octo:define, /octo:develop, /octo:deliver)."
            echo "  You are PROHIBITED from substituting Claude-native tools (Agent, WebFetch, Write)"
            echo "  for multi-provider dispatch. The purpose of this workflow is multi-LLM orchestration."
            echo "  If you find yourself researching or implementing directly without calling"
            echo "  orchestrate.sh or a /octo: skill, STOP — you are violating the workflow contract."
            ;;
    esac

    echo "  Tip: Run /octo:resume if you need to rebuild full workflow context."
fi

exit 0
