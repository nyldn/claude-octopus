#!/usr/bin/env bash
# Claude Octopus — InstructionsLoaded Hook (v8.35.0)
# Fires when CLAUDE.md instructions are loaded into a session.
# Injects dynamic workflow context so agents start with awareness of:
#   - Current workflow phase (if any)
#   - Active/recent agent results
#   - Session effort level
#
# Requires Claude Code v2.1.69+ (InstructionsLoaded hook event)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


SESSION_FILE="${HOME}/.claude-octopus/session.json"
RESULTS_DIR="${HOME}/.claude-octopus/results"

# No session file — nothing to inject
if [[ ! -f "$SESSION_FILE" ]]; then
    exit 0
fi

# Only inject context if jq is available (required for JSON parsing)
if ! command -v jq &>/dev/null; then
    exit 0
fi

# Extract current workflow state
PHASE=$(jq -r '.current_phase // .phase // empty' "$SESSION_FILE" 2>/dev/null)
WORKFLOW=$(jq -r '.workflow // empty' "$SESSION_FILE" 2>/dev/null)
AUTONOMY=$(jq -r '.autonomy // "supervised"' "$SESSION_FILE" 2>/dev/null)
EFFORT=$(jq -r '.effort_level // empty' "$SESSION_FILE" 2>/dev/null)

# v8.41.0: Check for pre-compact snapshot (written by PreCompact hook before compaction)
# If session.json has no phase but a snapshot exists, restore from snapshot
SNAPSHOT_FILE="${HOME}/.claude-octopus/.octo/pre-compact-snapshot.json"
if [[ -z "$PHASE" || "$PHASE" == "null" ]] && [[ -f "$SNAPSHOT_FILE" ]]; then
    PHASE=$(jq -r '.phase // empty' "$SNAPSHOT_FILE" 2>/dev/null)
    WORKFLOW=$(jq -r '.workflow // empty' "$SNAPSHOT_FILE" 2>/dev/null)
    AUTONOMY=$(jq -r '.autonomy // "supervised"' "$SNAPSHOT_FILE" 2>/dev/null)
    EFFORT=$(jq -r '.effort_level // empty' "$SNAPSHOT_FILE" 2>/dev/null)
fi

# No active workflow — skip injection
if [[ -z "$PHASE" || "$PHASE" == "null" ]]; then
    exit 0
fi

# Build context summary
context="[Octopus Context] Phase: ${PHASE}"

if [[ -n "$WORKFLOW" && "$WORKFLOW" != "null" ]]; then
    context="${context} | Workflow: ${WORKFLOW}"
fi

if [[ -n "$EFFORT" && "$EFFORT" != "null" ]]; then
    context="${context} | Effort: ${EFFORT}"
fi

context="${context} | Autonomy: ${AUTONOMY}"

# Check for recent results (last 3 files, newest first)
if [[ -d "$RESULTS_DIR" ]]; then
    recent_results=$(ls -t "$RESULTS_DIR"/*.md 2>/dev/null | head -3)
    if [[ -n "$recent_results" ]]; then
        result_names=""
        while IFS= read -r f; do
            result_names="${result_names}$(basename "$f" .md), "
        done <<< "$recent_results"
        # Trim trailing comma+space
        result_names="${result_names%, }"
        context="${context} | Recent results: ${result_names}"
    fi
fi

# Output as a prompt injection (type: prompt hook response)
echo "$context"
