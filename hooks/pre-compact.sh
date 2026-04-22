#!/usr/bin/env bash
# Claude Octopus — PreCompact Hook (v8.41.0)
# Fires before context compaction. Persists workflow state so progress
# context survives automatic or manual compaction.
#
# Hook event: PreCompact (available in all CC versions that support hooks)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


SESSION_FILE="${HOME}/.claude-octopus/session.json"
STATE_DIR="${HOME}/.claude-octopus/.octo"

# Nothing to persist if no active session
if [[ ! -f "$SESSION_FILE" ]]; then
    exit 0
fi

# Snapshot current workflow state before compaction wipes context
mkdir -p "$STATE_DIR"

SNAPSHOT="${STATE_DIR}/pre-compact-snapshot.json"

if command -v jq &>/dev/null; then
    # Capture phase, workflow, decisions, blockers for post-compaction recovery
    jq '{
        phase: (.current_phase // .phase // null),
        workflow: (.workflow // null),
        autonomy: (.autonomy // "supervised"),
        effort_level: (.effort_level // null),
        completed_phases: (.completed_phases // []),
        decisions: (.decisions // []),
        blockers: (.blockers // []),
        snapshot_time: now | tostring
    }' "$SESSION_FILE" > "$SNAPSHOT" 2>/dev/null || true
fi

# v9.6.0: Write session handoff file for cross-session resumption
if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/write-handoff.sh" ]]; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/write-handoff.sh" 2>/dev/null || true
fi

# v9.23: On Claude Code v2.1.105+, PreCompact hooks can block compaction by
# emitting {"decision":"block"} on stdout. Veto mid-tangle compaction when
# active agents haven't finished — losing their context would corrupt the
# workflow. Guarded by OCTOPUS_PRECOMPACT_BLOCK (default on) so users can opt out.
_block_compaction=false
if [[ "${OCTOPUS_PRECOMPACT_BLOCK:-on}" != "off" ]] && [[ "${SUPPORTS_PRECOMPACT_BLOCKING:-false}" == "true" ]]; then
    if command -v jq &>/dev/null && [[ -f "$SNAPSHOT" ]]; then
        _phase=$(jq -r '.phase // empty' "$SNAPSHOT" 2>/dev/null)
        _active=$(jq -r '(.active_agents // 0) | tostring' "$SESSION_FILE" 2>/dev/null)
        case "$_phase" in
            tangle|develop|ink|deliver|discover-dispatch)
                if [[ -n "$_active" && "$_active" != "0" && "$_active" != "null" ]]; then
                    _block_compaction=true
                fi
                ;;
        esac
    fi
fi

if $_block_compaction; then
    printf '{"decision":"block","reason":"Claude Octopus — %d agent(s) in flight during %s phase; compaction would discard in-progress work. Set OCTOPUS_PRECOMPACT_BLOCK=off to override."}\n' \
        "${_active}" "${_phase}"
    exit 0
fi

# Output context for post-compaction prompt injection (non-blocking path)
if [[ -f "$SNAPSHOT" ]]; then
    phase=$(jq -r '.phase // empty' "$SNAPSHOT" 2>/dev/null)
    workflow=$(jq -r '.workflow // empty' "$SNAPSHOT" 2>/dev/null)
    if [[ -n "$phase" && "$phase" != "null" ]]; then
        echo "[Octopus PreCompact] Workflow state preserved: phase=${phase}, workflow=${workflow:-unknown}"
    fi
fi

exit 0
