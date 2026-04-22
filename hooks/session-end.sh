#!/usr/bin/env bash
# Claude Octopus — SessionEnd Hook (v8.41.0)
# Fires when a Claude Code session ends. Finalizes metrics,
# cleans up session artifacts, and persists key preferences
# to auto-memory for cross-session continuity.
#
# Hook event: SessionEnd
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


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

# --- 4. Cross-task learning extraction (v9.8.0) ---
# Extracts structured learnings from the session and persists them as individual
# JSON files in .claude-octopus/learnings/. Capped at 5 learnings per session
# to stay within budget. These are consumed at session start for relevance matching.
LEARNINGS_DIR="${HOME}/.claude-octopus/learnings"
if [[ -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
    mkdir -p "$LEARNINGS_DIR"

    # Extract session signals for cross-task learning
    SESSION_WORKFLOW=$(jq -r '.workflow // "none"' "$SESSION_FILE" 2>/dev/null)
    SESSION_PHASE=$(jq -r '.current_phase // .phase // "none"' "$SESSION_FILE" 2>/dev/null)
    SESSION_ERRORS=$(jq -r '.errors // [] | length' "$SESSION_FILE" 2>/dev/null) || SESSION_ERRORS=0
    SESSION_AGENTS=$(jq -r '.total_agent_calls // 0' "$SESSION_FILE" 2>/dev/null)

    # Determine task_type from workflow/phase
    case "$SESSION_WORKFLOW" in
        probe|discover|research) TASK_TYPE="research" ;;
        tangle|develop|build)    TASK_TYPE="implementation" ;;
        ink|deliver|review)      TASK_TYPE="review" ;;
        debug|fix)               TASK_TYPE="debugging" ;;
        *)                       TASK_TYPE="general" ;;
    esac

    # Determine outcome from error count and phase
    if [[ "$SESSION_ERRORS" -gt 0 ]]; then
        OUTCOME="partial"
    elif [[ "$SESSION_PHASE" == "none" ]]; then
        OUTCOME="incomplete"
    else
        OUTCOME="success"
    fi

    # Build approach summary from session signals
    APPROACH="Workflow: ${SESSION_WORKFLOW}, reached phase: ${SESSION_PHASE}, agents used: ${SESSION_AGENTS}"

    # Build lesson from error/success patterns
    if [[ "$SESSION_ERRORS" -gt 0 ]]; then
        LESSON="Session encountered ${SESSION_ERRORS} error(s) during ${SESSION_WORKFLOW} — check provider auth and context budget"
    elif [[ "$SESSION_AGENTS" -gt 3 ]]; then
        LESSON="Multi-agent workflow (${SESSION_AGENTS} agents) completed successfully — parallel dispatch effective"
    else
        LESSON="Standard ${SESSION_WORKFLOW} workflow completed cleanly"
    fi

    # Only persist if there's meaningful activity (at least 1 agent call or errors)
    if [[ "$SESSION_AGENTS" -gt 0 || "$SESSION_ERRORS" -gt 0 ]]; then
        DATE_STAMP=$(date +%Y-%m-%d)
        TIME_STAMP=$(date +%H%M%S)
        LEARNING_SLUG=$(echo "$SESSION_WORKFLOW" | tr '[:upper:]/ ' '[:lower:]--' | head -c 30)
        LEARNING_FILE="${LEARNINGS_DIR}/${DATE_STAMP}-${LEARNING_SLUG}-${TIME_STAMP}.json"

        # Cap at 5 learnings per session — count files written today
        TODAY_COUNT=$(find "$LEARNINGS_DIR" -name "${DATE_STAMP}-*" -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$TODAY_COUNT" -lt 5 ]]; then
            jq -n \
                --arg date "$DATE_STAMP" \
                --arg task_type "$TASK_TYPE" \
                --arg approach "$APPROACH" \
                --arg outcome "$OUTCOME" \
                --arg lesson "$LESSON" \
                '{date: $date, task_type: $task_type, approach: $approach, outcome: $outcome, lesson: $lesson}' \
                > "$LEARNING_FILE" 2>/dev/null || true
        fi

        # Prune old learnings — keep at most 50 files, remove oldest beyond that
        TOTAL_LEARNINGS=$(find "$LEARNINGS_DIR" -name "*.json" -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$TOTAL_LEARNINGS" -gt 50 ]]; then
            # Remove oldest files beyond the cap
            find "$LEARNINGS_DIR" -name "*.json" -maxdepth 1 -print0 2>/dev/null \
                | xargs -0 ls -1t 2>/dev/null \
                | tail -n +51 \
                | xargs rm -f 2>/dev/null || true
        fi
    fi
fi

# --- 5. Write session handoff file for cross-session resumption (v9.6.0) ---
if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/write-handoff.sh" ]]; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/write-handoff.sh" 2>/dev/null || true
fi

# --- 6. Clean up session artifacts ---
# Remove transient files but keep session.json for resume capability
rm -f "${HOME}/.claude-octopus/.octo/pre-compact-snapshot.json" 2>/dev/null || true
rm -f "${HOME}/.claude-octopus/.reload-signal" 2>/dev/null || true

# Clean up session title sentinel files (from user-prompt-submit.sh auto-titling)
# Keep last 20 (by mtime), remove the rest to prevent accumulation
find "${HOME}/.claude-octopus/" -maxdepth 1 -name ".session-titled-*" -type f 2>/dev/null \
    | xargs ls -t 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null || true

# Session manager cleanup: retain 10 most recent sessions
if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/session-manager.sh" ]]; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/session-manager.sh" cleanup 2>/dev/null || true
fi

exit 0
