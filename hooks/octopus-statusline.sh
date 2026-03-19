#!/usr/bin/env bash
# Claude Octopus Statusline — 3-tier adaptive display
# ═══════════════════════════════════════════════════════════════════════════════
#
# Tier 1: Node.js 16+ HUD (octopus-hud.mjs) — smart columns, OAuth API,
#          agent tracking, Tailwind colors, configurable layout
# Tier 2: Bash + jq — formatted statusline with context bar, cost, phase
# Tier 3: Pure bash (grep/cut) — zero external deps, minimal display
#
# Claude Code cancels in-flight statusline scripts on new updates, so
# timeout guards are unnecessary here (unlike hooks which need them).
# See: https://code.claude.com/docs/en/statusline

set -euo pipefail

# Read stdin — Claude Code always closes the pipe, no timeout needed
input=$(cat 2>/dev/null || true)
[[ -z "$input" ]] && input='{}'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUD_MJS="${SCRIPT_DIR}/octopus-hud.mjs"

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 1: Node.js HUD — requires Node 16+ (for node: protocol imports)
# ═══════════════════════════════════════════════════════════════════════════════

if command -v node &>/dev/null && [[ -f "$HUD_MJS" ]]; then
    # Check Node version >= 16 (node: protocol imports require it)
    NODE_MAJOR=$(node -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null) || NODE_MAJOR=0
    if [[ "$NODE_MAJOR" -ge 16 ]]; then
        output=$(echo "$input" | node "$HUD_MJS" 2>/dev/null) || output=""
        if [[ -n "$output" ]]; then
            echo "$output"
            exit 0
        fi
    fi
    # Fall through to Tier 2/3 if Node too old or HUD returned empty
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 2: Bash + jq — formatted statusline with colors and context bar
# ═══════════════════════════════════════════════════════════════════════════════

if command -v jq &>/dev/null; then
    SESSION_FILE="${HOME}/.claude-octopus/session.json"

    MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
    PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

    # Context bridge for cross-hook awareness
    _SESSION_ID=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
    _SESSION_ID="${_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
    _BRIDGE="/tmp/octopus-ctx-${_SESSION_ID}.json"
    (umask 0177; printf '{"session_id":"%s","used_pct":%s,"remaining_pct":%s,"ts":%s}\n' \
        "$_SESSION_ID" "$PCT" "$((100-PCT))" "$(date +%s)" \
        > "$_BRIDGE") 2>/dev/null || true

    COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

    # Worktree branch
    WORKTREE=$(echo "$input" | jq -r '.worktree.branch // empty' 2>/dev/null)

    # Colors
    GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
    CYAN='\033[36m'; RESET='\033[0m'

    if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
    elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
    else BAR_COLOR="$GREEN"; fi

    # Context bar
    BAR_WIDTH=10
    FILLED=$((PCT * BAR_WIDTH / 100))
    EMPTY=$((BAR_WIDTH - FILLED))
    BAR=""
    [ "$FILLED" -gt 0 ] && BAR=$(printf "%${FILLED}s" | tr ' ' '▰')
    [ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf "%${EMPTY}s" | tr ' ' '▱')"

    WARN_PREFIX=""
    [ "$PCT" -ge 90 ] && WARN_PREFIX="💀 "
    [ "$PCT" -ge 80 ] && [ "$PCT" -lt 90 ] && WARN_PREFIX="⚠️ "

    COST_FMT=$(printf '$%.2f' "$COST")
    wt_suffix=""
    [[ -n "$WORKTREE" && "$WORKTREE" != "null" ]] && wt_suffix=" | 🌿 ${WORKTREE}"

    # Check for active workflow phase
    PHASE=""
    if [[ -f "$SESSION_FILE" ]]; then
        PHASE=$(jq -r '.current_phase // .phase // empty' "$SESSION_FILE" 2>/dev/null) || PHASE=""
    fi

    if [[ -n "$PHASE" && "$PHASE" != "null" ]]; then
        PHASE_EMOJI="🐙"
        case "$PHASE" in
            probe) PHASE_EMOJI="🔍" ;; grasp) PHASE_EMOJI="🎯" ;;
            tangle) PHASE_EMOJI="🛠️" ;; ink) PHASE_EMOJI="✅" ;;
        esac
        echo -e "${CYAN}[🐙 Octopus]${RESET} ${PHASE_EMOJI} ${PHASE} | ${WARN_PREFIX}${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET}${wt_suffix}"
    else
        echo -e "${CYAN}[🐙]${RESET} ${WARN_PREFIX}${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET}${wt_suffix}"
    fi
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TIER 3: Pure bash — zero external deps (no jq, no node, no python)
# Uses grep/cut to extract JSON fields. Fragile but works everywhere.
# ═══════════════════════════════════════════════════════════════════════════════

# Extract fields with grep/cut (handles simple JSON, not nested arrays)
_json_val() {
    echo "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | cut -d'"' -f4
}
_json_num() {
    echo "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9.]*" | head -1 | grep -o '[0-9.]*$'
}

MODEL=$(_json_val "display_name")
[[ -z "$MODEL" ]] && MODEL="Claude"
PCT=$(_json_num "used_percentage")
[[ -z "$PCT" ]] && PCT=0
PCT=${PCT%%.*}  # truncate decimal

echo "[🐙 $MODEL] ${PCT}% context"
