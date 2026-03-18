#!/usr/bin/env bash
# Claude Octopus Statusline - Context & Cost Monitoring
# Requires Claude Code v2.1.33+ (statusline API with context_window data)
# ═══════════════════════════════════════════════════════════════════════════════
#
# v8.5: Delegates to Node.js HUD (octopus-hud.mjs) when available for richer
# display including agent tracking, quality gates, and provider indicators.
# Falls back to bash implementation when Node.js is not available.
#
# Displays: [Octopus] Phase: <phase> | Context: <pct>% | Cost: $<cost>
# Changes color based on context window usage:
#   Green  (<70%) - Safe
#   Yellow (70-89%) - Warning
#   Red    (>=90%) - Critical (auto-compaction imminent)

set -euo pipefail

# Read stdin once and store it
input=$(timeout 3 cat 2>/dev/null || true); [[ -z "$input" ]] && input='{}'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUD_MJS="${SCRIPT_DIR}/octopus-hud.mjs"

# v8.5: Delegate to Node.js HUD if available
if command -v node &>/dev/null && [[ -f "$HUD_MJS" ]]; then
    output=$(echo "$input" | node "$HUD_MJS" 2>/dev/null) || output=""
    if [[ -n "$output" ]]; then
        echo "$output"
        exit 0
    fi
    # Fall through to bash implementation if Node.js HUD returned empty
fi

# ═══════════════════════════════════════════════════════════════════════════════
# BASH FALLBACK - Original statusline implementation
# ═══════════════════════════════════════════════════════════════════════════════

SESSION_FILE="${HOME}/.claude-octopus/session.json"

# Extract statusline data
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Context bridge for agent awareness
_BRIDGE="/tmp/octopus-ctx-${CLAUDE_SESSION_ID:-unknown}.json"
printf '{"session_id":"%s","used_pct":%s,"remaining_pct":%s,"ts":%s}\n' \
    "${CLAUDE_SESSION_ID:-unknown}" "$PCT" "$((100-PCT))" "$(date +%s)" \
    > "$_BRIDGE" 2>/dev/null || true
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# v8.35.0: Extract worktree info (Claude Code v2.1.69+ provides worktree field)
WORKTREE=$(echo "$input" | jq -r '.worktree // empty' 2>/dev/null)
WORKTREE_BRANCH=""
if [[ -n "$WORKTREE" && "$WORKTREE" != "null" ]]; then
    # Extract branch name from worktree path (last component)
    WORKTREE_BRANCH=$(basename "$WORKTREE" 2>/dev/null)
fi

# Colors
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
RESET='\033[0m'

# Pick color based on context usage
if [ "$PCT" -ge 90 ]; then
    BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then
    BAR_COLOR="$YELLOW"
else
    BAR_COLOR="$GREEN"
fi

# Build context bar
BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && BAR=$(printf "%${FILLED}s" | tr ' ' '█')
[ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf "%${EMPTY}s" | tr ' ' '░')"

# Format cost
COST_FMT=$(printf '$%.2f' "$COST")

# Get active phase from session file (if workflow is running)
PHASE=""
if [[ -f "$SESSION_FILE" ]] && command -v jq &>/dev/null; then
    PHASE=$(jq -r '.current_phase // .phase // empty' "$SESSION_FILE" 2>/dev/null)
fi

if [[ -n "$PHASE" && "$PHASE" != "null" ]]; then
    # Active workflow - show phase info
    PHASE_EMOJI=""
    case "$PHASE" in
        probe)    PHASE_EMOJI="🔍" ;;
        grasp)    PHASE_EMOJI="🎯" ;;
        tangle)   PHASE_EMOJI="🛠️" ;;
        ink)      PHASE_EMOJI="✅" ;;
        complete) PHASE_EMOJI="🐙" ;;
        *)        PHASE_EMOJI="🐙" ;;
    esac

    # v8.35.0: Append worktree branch when running in isolation
    local wt_suffix=""
    if [[ -n "$WORKTREE_BRANCH" ]]; then
        wt_suffix=" | 🌿 ${WORKTREE_BRANCH}"
    fi

    echo -e "${CYAN}[🐙 Octopus]${RESET} ${PHASE_EMOJI} ${PHASE} | ${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET}${wt_suffix}"
else
    # No active workflow - compact display
    local wt_suffix=""
    if [[ -n "$WORKTREE_BRANCH" ]]; then
        wt_suffix=" | 🌿 ${WORKTREE_BRANCH}"
    fi

    echo -e "${CYAN}[🐙]${RESET} ${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET}${wt_suffix}"
fi
