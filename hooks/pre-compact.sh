#!/usr/bin/env bash
# Claude Octopus — PreCompact Hook (v8.41.0)
# Fires before context compaction. Persists workflow state so progress
# context survives automatic or manual compaction.
#
# Hook event: PreCompact (available in all CC versions that support hooks)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

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

# Output context for post-compaction prompt injection
if [[ -f "$SNAPSHOT" ]]; then
    phase=$(jq -r '.phase // empty' "$SNAPSHOT" 2>/dev/null)
    workflow=$(jq -r '.workflow // empty' "$SNAPSHOT" 2>/dev/null)
    if [[ -n "$phase" && "$phase" != "null" ]]; then
        echo "[Octopus PreCompact] Workflow state preserved: phase=${phase}, workflow=${workflow:-unknown}"
    fi
fi

exit 0
