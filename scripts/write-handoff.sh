#!/usr/bin/env bash
# write-handoff.sh — Writes .octo-continue.md session handoff file
# Called by pre-compact.sh and session-end.sh for cross-session resumption.
# Reads: session.json, .octo/STATE.md, progress file
# Writes: .octo-continue.md in CWD

set -euo pipefail

SESSION_FILE="${HOME}/.claude-octopus/session.json"
STATE_FILE=".octo/STATE.md"
HANDOFF_FILE=".octo-continue.md"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
PROGRESS_FILE="${HOME}/.claude-octopus/progress-${SESSION_ID}.json"

# Only write if there's session state worth preserving
[[ -f "$SESSION_FILE" ]] || exit 0
command -v jq &>/dev/null || exit 0

# Extract session fields
PHASE=$(jq -r '.current_phase // .phase // "none"' "$SESSION_FILE" 2>/dev/null) || PHASE="none"
WORKFLOW=$(jq -r '.workflow // "none"' "$SESSION_FILE" 2>/dev/null) || WORKFLOW="none"
AUTONOMY=$(jq -r '.autonomy // "supervised"' "$SESSION_FILE" 2>/dev/null) || AUTONOMY="supervised"
STATUS=$(jq -r '.status // "unknown"' "$SESSION_FILE" 2>/dev/null) || STATUS="unknown"
COMPLETED=$(jq -r '.completed_phases // 0' "$SESSION_FILE" 2>/dev/null) || COMPLETED=0
TOTAL=$(jq -r '.total_phases // 4' "$SESSION_FILE" 2>/dev/null) || TOTAL=4

# Extract decisions array (up to 5)
DECISIONS=$(jq -r '(.decisions // [])[:5][] | "- " + .' "$SESSION_FILE" 2>/dev/null) || DECISIONS=""

# Extract blockers
BLOCKERS=$(jq -r '(.blockers // [])[:3][] | "- " + .' "$SESSION_FILE" 2>/dev/null) || BLOCKERS=""

# Extract pending tasks from STATE.md if available
PENDING=""
if [[ -f "$STATE_FILE" ]]; then
    PENDING=$(grep -A 20 '## Pending\|## Tasks\|## Remaining' "$STATE_FILE" 2>/dev/null | grep '^\s*-' | head -5) || PENDING=""
fi

# Get active agent name from progress file
ACTIVE_AGENT=""
if [[ -f "$PROGRESS_FILE" ]]; then
    ACTIVE_AGENT=$(jq -r '[.agents // {} | to_entries[] | select(.value.status == "running") | .key] | first // empty' "$PROGRESS_FILE" 2>/dev/null) || ACTIVE_AGENT=""
fi

# Write handoff file
{
    echo "# 🐙 Octopus Session Handoff"
    echo ""
    echo "**Session:** ${SESSION_ID} | **Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "## Current State"
    echo "- **Workflow:** ${WORKFLOW} (phase ${COMPLETED}/${TOTAL} — ${PHASE})"
    echo "- **Status:** ${STATUS} | **Autonomy:** ${AUTONOMY}"
    [[ -n "$ACTIVE_AGENT" ]] && echo "- **Active Agent:** ${ACTIVE_AGENT}"
    echo ""

    if [[ -n "$PENDING" ]]; then
        echo "## Pending Work"
        echo "$PENDING"
        echo ""
    fi

    if [[ -n "$DECISIONS" ]]; then
        echo "## Key Decisions"
        echo "$DECISIONS"
        echo ""
    fi

    if [[ -n "$BLOCKERS" ]]; then
        echo "## Blockers"
        echo "$BLOCKERS"
        echo ""
    fi

    echo "## Resume"
    echo "Run \`/octo:resume\` to continue from the **${PHASE}** phase."
} > "$HANDOFF_FILE" 2>/dev/null || exit 0
