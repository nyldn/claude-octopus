#!/usr/bin/env bash
# Claude Octopus Statusline - Context & Cost Monitoring
# Requires Claude Code v2.1.33+ (statusline API with context_window data)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Displays: [Octopus] Phase: <phase> | Context: <pct>% | Cost: $<cost>
# Changes color based on context window usage:
#   Green  (<70%) - Safe
#   Yellow (70-89%) - Warning
#   Red    (>=90%) - Critical (auto-compaction imminent)

set -euo pipefail

input=$(cat)

SESSION_FILE="${HOME}/.claude-octopus/session.json"

# Extract statusline data
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

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
    PHASE=$(jq -r '.phase // empty' "$SESSION_FILE" 2>/dev/null)
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

    echo -e "${CYAN}[🐙 Octopus]${RESET} ${PHASE_EMOJI} ${PHASE} | ${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET}"
else
    # No active workflow - compact display
    echo -e "${CYAN}[🐙]${RESET} ${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET}"
fi
