#!/usr/bin/env bash
# Claude Octopus — SessionStart Auto-Memory Loader (v8.41.0)
# Fires on SessionStart. Reads persisted preferences from auto-memory
# (written by session-end.sh) and pre-loads them into the session,
# skipping provider detection and preference questions for returning users.
#
# Hook event: SessionStart
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SESSION_FILE="${HOME}/.claude-octopus/session.json"
MEMORY_DIR="${HOME}/.claude/projects"

# --- 1. Find and read persisted preferences from auto-memory ---
# Priority: CLAUDE_PROJECT_DIR (set by CC) > CWD-based lookup > fallback scan
PREFS_FILE=""

if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -f "${CLAUDE_PROJECT_DIR}/memory/octopus-preferences.md" ]]; then
    PREFS_FILE="${CLAUDE_PROJECT_DIR}/memory/octopus-preferences.md"
else
    # CWD-based lookup then fallback scan
    CWD_ENCODED=$(pwd | tr '/' '-' | sed 's/^-//')
    for mem_dir in "$MEMORY_DIR"/*"${CWD_ENCODED}"*/memory "$MEMORY_DIR"/*/memory; do
        if [[ -f "${mem_dir}/octopus-preferences.md" ]]; then
            PREFS_FILE="${mem_dir}/octopus-preferences.md"
            break
        fi
    done
fi

if [[ -z "$PREFS_FILE" || ! -f "$PREFS_FILE" ]]; then
    # No persisted preferences — first session or memory cleared
    exit 0
fi

# --- 2. Parse preferences and inject into session ---
AUTONOMY=""
PROVIDERS=""

while IFS= read -r line; do
    case "$line" in
        *"Preferred autonomy:"*)
            AUTONOMY="${line##*: }"
            ;;
        *"Provider config:"*)
            PROVIDERS="${line##*: }"
            ;;
    esac
done < "$PREFS_FILE"

# --- 3. Apply preferences to current session ---
if [[ -n "$AUTONOMY" ]] && command -v jq &>/dev/null; then
    mkdir -p "$(dirname "$SESSION_FILE")"

    if [[ -f "$SESSION_FILE" ]]; then
        TMP="${SESSION_FILE}.tmp"
        jq --arg autonomy "$AUTONOMY" \
           --arg providers "${PROVIDERS:-}" \
           '.autonomy = $autonomy | .restored_from_memory = true | if $providers != "" then .providers = $providers else . end' \
           "$SESSION_FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$SESSION_FILE" 2>/dev/null || rm -f "$TMP"
    else
        # Create initial session with restored preferences
        cat > "$SESSION_FILE" <<EOFJSON
{
  "autonomy": "$AUTONOMY",
  "restored_from_memory": true,
  "session_start": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOFJSON
    fi

    echo "[Octopus] Restored preferences from auto-memory: autonomy=${AUTONOMY}"
fi

# --- 4. Query claude-mem for recent project context (v8.57.0) ---
BRIDGE_SCRIPT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/claude-mem-bridge.sh"
if [[ -x "$BRIDGE_SCRIPT" ]]; then
    MEM_CONTEXT=$("$BRIDGE_SCRIPT" context "" 3 2>/dev/null || echo "")
    if [[ -n "$MEM_CONTEXT" ]]; then
        echo "[Octopus] claude-mem context available:"
        echo "$MEM_CONTEXT"
    fi
fi

exit 0
