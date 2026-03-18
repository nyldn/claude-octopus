#!/usr/bin/env bash
# Claude Octopus — SessionEnd Hook (v8.41.0)
# Fires when a Claude Code session ends. Finalizes metrics,
# cleans up session artifacts, and persists key preferences
# to auto-memory for cross-session continuity.
#
# Hook event: SessionEnd
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SESSION_FILE="${HOME}/.claude-octopus/session.json"
METRICS_DIR="${HOME}/.claude-octopus/metrics"
MEMORY_DIR="${HOME}/.claude/projects"

# --- 1. Finalize session metrics ---
if [[ -d "$METRICS_DIR" ]]; then
    SUMMARY="${METRICS_DIR}/session-summary-$(date +%Y%m%d-%H%M%S).json"
    if command -v jq &>/dev/null && [[ -f "$SESSION_FILE" ]]; then
        jq '{
            session_end: (now | tostring),
            phase: (.current_phase // .phase // "none"),
            workflow: (.workflow // "none"),
            completed_phases: (.completed_phases // []) | length,
            total_agent_calls: (.total_agent_calls // 0)
        }' "$SESSION_FILE" > "$SUMMARY" 2>/dev/null || true
    fi
fi

# --- 2. Persist preferences to auto-memory ---
# When native auto-memory is available, write key preferences so
# the next session starts with user context pre-loaded.
if [[ -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
    AUTONOMY=$(jq -r '.autonomy // empty' "$SESSION_FILE" 2>/dev/null)
    PROVIDERS=$(jq -r '.providers // empty' "$SESSION_FILE" 2>/dev/null)

    # Find the correct project memory directory
    # Priority: CLAUDE_PROJECT_DIR (set by CC) > CWD-based lookup > fallback scan
    TARGET_MEM_DIR=""

    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        # CC sets this to the project-specific config dir (e.g., ~/.claude/projects/-Users-foo-myproject/)
        TARGET_MEM_DIR="${CLAUDE_PROJECT_DIR}/memory"
    else
        # Derive from CWD: CC encodes paths as -Users-foo-myproject
        CWD_ENCODED=$(pwd | tr '/' '-' | sed 's/^-//')
        for candidate in "$MEMORY_DIR"/*"${CWD_ENCODED}"*/memory "$MEMORY_DIR"/*; do
            if [[ -d "$candidate" ]]; then
                TARGET_MEM_DIR="$candidate"
                # If candidate ends in /memory, use it directly; otherwise append
                [[ "$candidate" != */memory ]] && TARGET_MEM_DIR="${candidate}/memory"
                break
            fi
        done
    fi

    if [[ -n "$TARGET_MEM_DIR" && -n "$AUTONOMY" && "$AUTONOMY" != "null" ]]; then
        mkdir -p "$TARGET_MEM_DIR"
        OCTOPUS_MEM="${TARGET_MEM_DIR}/octopus-preferences.md"
        {
            echo "# Octopus User Preferences"
            echo ""
            echo "- Preferred autonomy: ${AUTONOMY}"
            [[ -n "$PROVIDERS" && "$PROVIDERS" != "null" ]] && echo "- Provider config: ${PROVIDERS}"
            echo "- Last updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } > "$OCTOPUS_MEM"
    fi
fi

# --- 3. Learnings layer — meta-reflection across sessions (v8.41.0) ---
# Appends session-level learnings (errors hit, patterns discovered, tools used)
# to octopus-learnings.md for cross-session meta-reflection.
if [[ -n "${TARGET_MEM_DIR:-}" ]] && [[ -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
    LEARNINGS_FILE="${TARGET_MEM_DIR}/octopus-learnings.md"
    # Extract session signals for learnings
    PHASE=$(jq -r '.current_phase // .phase // "none"' "$SESSION_FILE" 2>/dev/null)
    WORKFLOW=$(jq -r '.workflow // "none"' "$SESSION_FILE" 2>/dev/null)
    AGENT_CALLS=$(jq -r '.total_agent_calls // 0' "$SESSION_FILE" 2>/dev/null)
    ERRORS=$(jq -r '.errors // [] | length' "$SESSION_FILE" 2>/dev/null) || ERRORS=0
    DEBATE_USED=$(jq -r 'if .debate_rounds then "yes" else "no" end' "$SESSION_FILE" 2>/dev/null) || DEBATE_USED="no"

    # Only write if there's something meaningful to record
    if [[ "$AGENT_CALLS" -gt 0 || "$ERRORS" -gt 0 ]]; then
        # Create header if file doesn't exist
        if [[ ! -f "$LEARNINGS_FILE" ]]; then
            {
                echo "# Octopus Session Learnings"
                echo ""
                echo "Auto-captured meta-reflection across sessions. Most recent first."
                echo "Prune entries older than 30 days to keep this file lean."
                echo ""
            } > "$LEARNINGS_FILE"
        fi

        # Prepend new entry (most recent first, cap at 50 entries / ~200 lines)
        TEMP_LEARNINGS=$(mktemp)
        {
            head -5 "$LEARNINGS_FILE"  # Keep header
            echo "## $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            echo "- Workflow: ${WORKFLOW}, Phase reached: ${PHASE}"
            echo "- Agent calls: ${AGENT_CALLS}, Errors: ${ERRORS}, Debate: ${DEBATE_USED}"
            [[ "$ERRORS" -gt 0 ]] && echo "- Note: Session had errors — review metrics for details"
            echo ""
            # Keep existing entries (skip header)
            tail -n +6 "$LEARNINGS_FILE" | head -195
        } > "$TEMP_LEARNINGS"
        mv "$TEMP_LEARNINGS" "$LEARNINGS_FILE"
    fi
fi

# --- 4. Write session handoff file for cross-session resumption (v9.6.0) ---
if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/write-handoff.sh" ]]; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/write-handoff.sh" 2>/dev/null || true
fi

# --- 5. Clean up session artifacts ---
# Remove transient files but keep session.json for resume capability
rm -f "${HOME}/.claude-octopus/.octo/pre-compact-snapshot.json" 2>/dev/null || true
rm -f "${HOME}/.claude-octopus/.reload-signal" 2>/dev/null || true

# Session manager cleanup: retain 10 most recent sessions
if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/session-manager.sh" ]]; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/session-manager.sh" cleanup 2>/dev/null || true
fi

exit 0
