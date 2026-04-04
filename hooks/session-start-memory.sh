#!/usr/bin/env bash
# Claude Octopus — SessionStart Auto-Memory Loader (v8.41.0)
# Fires on SessionStart. Reads persisted preferences from auto-memory
# (written by session-end.sh) and pre-loads them into the session,
# skipping provider detection and preference questions for returning users.
#
# Hook event: SessionStart
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# --- 0. Session sync (merged from session-sync.sh to reduce hook spawns) ---
export CLAUDE_OCTOPUS_SESSION_ID="${CLAUDE_SESSION_ID:-}"

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
        # Create initial session with restored preferences (jq --arg for safe escaping)
        jq -n \
            --arg autonomy "$AUTONOMY" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{"autonomy": $autonomy, "restored_from_memory": true, "session_start": $ts}' \
            > "$SESSION_FILE" 2>/dev/null || true
    fi

    echo "[Octopus] Restored preferences from auto-memory: autonomy=${AUTONOMY}"
fi

# --- 4. Deploy managed-settings.d/ fragment (v9.19.0, CC v2.1.83+) ---
# Installs octopus-defaults.json with git instructions off + auto-memory dir
# Note: Generated dynamically (not copied) because JSON has no tilde expansion
if [[ "${SUPPORTS_MANAGED_SETTINGS_D:-false}" == "true" ]]; then
    SETTINGS_D="${HOME}/.claude/managed-settings.d"
    SETTINGS_DEST="${SETTINGS_D}/octopus-defaults.json"
    if [[ ! -f "$SETTINGS_DEST" ]] || ! grep -q "$HOME" "$SETTINGS_DEST" 2>/dev/null; then
        mkdir -p "$SETTINGS_D"
        local _tmp="${SETTINGS_DEST}.tmp.$$"
        cat > "$_tmp" <<EOFSET
{
  "includeGitInstructions": false,
  "autoMemoryDirectory": "${HOME}/.claude-octopus/memory/"
}
EOFSET
        mv "$_tmp" "$SETTINGS_DEST" 2>/dev/null || rm -f "$_tmp"
    fi
fi

# --- 5. Query claude-mem for recent project context (v8.57.0) ---
BRIDGE_SCRIPT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/claude-mem-bridge.sh"
if [[ -x "$BRIDGE_SCRIPT" ]]; then
    MEM_CONTEXT=$("$BRIDGE_SCRIPT" context "" 3 2>/dev/null || echo "")
    if [[ -n "$MEM_CONTEXT" ]]; then
        echo "[Octopus] claude-mem context available:"
        echo "$MEM_CONTEXT"
    fi
fi

exit 0
