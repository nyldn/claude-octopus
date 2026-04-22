#!/usr/bin/env bash
# Claude Octopus — SessionStart Auto-Memory Loader (v8.41.0)
# Fires on SessionStart. Reads persisted preferences from auto-memory
# (written by session-end.sh) and pre-loads them into the session,
# skipping provider detection and preference questions for returning users.
#
# Hook event: SessionStart
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


# --- 0. First-run detection (v9.19.2) ---
# On very first install, auto-prompt the user to run /octo:setup
SETUP_MARKER="${HOME}/.claude-octopus/.setup-complete"
if [[ ! -f "$SETUP_MARKER" ]]; then
    mkdir -p "${HOME}/.claude-octopus"
    touch "$SETUP_MARKER"
    echo "[🐙] Welcome to Claude Octopus! Running /octo:setup for first-time configuration..."
    # This additionalContext triggers Claude to invoke the setup skill
    exit 0
fi

# --- 0b. Session sync (merged from session-sync.sh to reduce hook spawns) ---
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
    for mem_dir in "$MEMORY_DIR"/*"${CWD_ENCODED}"*/memory; do
        if [[ -f "${mem_dir}/octopus-preferences.md" ]]; then
            PREFS_FILE="${mem_dir}/octopus-preferences.md"
            break
        fi
    done
fi

SKIP_PREFS=0
if [[ -z "$PREFS_FILE" || ! -f "$PREFS_FILE" ]]; then
    # No persisted preferences — first session or memory cleared.
    # Skip prefs/managed-settings/claude-mem blocks but still run cache hygiene.
    SKIP_PREFS=1
fi

# --- 2. Parse preferences and inject into session ---
if [[ "$SKIP_PREFS" == "0" ]]; then
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

    echo "[🐙] restored: autonomy=${AUTONOMY}"
fi

# --- 4. Deploy managed-settings.d/ fragment (v9.19.0, CC v2.1.83+) ---
# Installs octopus-defaults.json with git instructions off + auto-memory dir
# Note: Generated dynamically (not copied) because JSON has no tilde expansion
if [[ "${SUPPORTS_MANAGED_SETTINGS_D:-false}" == "true" ]]; then
    SETTINGS_D="${HOME}/.claude/managed-settings.d"
    SETTINGS_DEST="${SETTINGS_D}/octopus-defaults.json"
    if [[ ! -f "$SETTINGS_DEST" ]] || ! grep -q "$HOME" "$SETTINGS_DEST" 2>/dev/null; then
        mkdir -p "$SETTINGS_D"
        _tmp="${SETTINGS_DEST}.tmp.$$"
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
fi  # end SKIP_PREFS guard

# --- 6. Cache hygiene advisory (v9.29.0) ---
# Notify when 3+ stale octo cache versions exist. Auto-clean only when explicitly
# opted in via OCTOPUS_AUTO_CLEAN_CACHE=1 — never delete without consent.
HYGIENE_LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/lib/cache-hygiene.sh"
if [[ -r "$HYGIENE_LIB" ]]; then
    # shellcheck disable=SC1090
    source "$HYGIENE_LIB"
    STALE_COUNT=$(octo_cache_stale 2>/dev/null | grep -c . || true)
    STALE_COUNT="${STALE_COUNT:-0}"
    if [[ "$STALE_COUNT" -ge 3 ]]; then
        STALE_BYTES=$(octo_cache_stale_bytes 2>/dev/null || echo 0)
        STALE_HUMAN=$(octo_cache_format_bytes "$STALE_BYTES" 2>/dev/null || echo "")
        if [[ "${OCTOPUS_AUTO_CLEAN_CACHE:-0}" == "1" ]]; then
            CLEANED=$(octo_cache_clean 2>/dev/null | grep -c '^removed:' || true)
            CLEANED="${CLEANED:-0}"
            [[ "$CLEANED" -gt 0 ]] && \
                echo "[🐙] Cleaned ${CLEANED} stale octo cache version(s) — ${STALE_HUMAN} reclaimed"
        else
            echo "[🐙] ${STALE_COUNT} stale octo cache version(s) (${STALE_HUMAN}). Run /octo:doctor to clean, or set OCTOPUS_AUTO_CLEAN_CACHE=1."
        fi
    fi
fi

exit 0
