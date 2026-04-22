#!/usr/bin/env bash
# Claude Octopus — SessionStart Version Advisory (v9.29.0+)
#
# When the plugin version jumps between sessions, emit a ONE-LINE advisory
# so existing users find out about behavioral changes (e.g. role routing,
# default model shifts) without having to manually run /octo:setup.
#
# This hook:
#   1. Reads the current plugin version from .claude-plugin/plugin.json
#   2. Compares it to the `last_seen_version` stored in ~/.claude-octopus/state.json
#   3. If different (and not first-run), emits a one-line advisory referencing
#      the CHANGELOG entry for the target version
#   4. Updates `last_seen_version` in state.json
#   5. Stays silent on no-change or first-run (session-start-memory.sh handles first-run)
#
# Hook event: SessionStart (runs after session-start-memory.sh first-run gate)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

STATE_DIR="${HOME}/.claude-octopus"
STATE_FILE="${STATE_DIR}/state.json"
SETUP_MARKER="${STATE_DIR}/.setup-complete"
PLUGIN_MANIFEST="${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json"

# Silent exit on missing prereqs — never block session start
[[ ! -f "$PLUGIN_MANIFEST" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# First-run is handled by session-start-memory.sh — don't double-prompt
[[ ! -f "$SETUP_MARKER" ]] && exit 0

CURRENT_VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_MANIFEST" 2>/dev/null || echo "unknown")
[[ "$CURRENT_VERSION" == "unknown" || -z "$CURRENT_VERSION" ]] && exit 0

# Read (or seed) last_seen_version
mkdir -p "$STATE_DIR"
if [[ ! -f "$STATE_FILE" ]]; then
    echo '{}' > "$STATE_FILE"
fi

LAST_SEEN=$(jq -r '.last_seen_version // empty' "$STATE_FILE" 2>/dev/null)

# Already up to date — stay quiet
if [[ "$LAST_SEEN" == "$CURRENT_VERSION" ]]; then
    exit 0
fi

# First time we're recording a version (not a real upgrade) — seed silently
if [[ -z "$LAST_SEEN" ]]; then
    TMP=$(mktemp "${STATE_FILE}.XXXXXX")
    jq --arg v "$CURRENT_VERSION" '. + {last_seen_version: $v}' "$STATE_FILE" > "$TMP" \
        && mv "$TMP" "$STATE_FILE"
    exit 0
fi

# Version changed — advisory. Keep it to one or two lines, non-blocking.
# We echo to stdout so Claude Code surfaces it as session context.
cat <<EOF
🐙 Claude Octopus updated: ${LAST_SEEN} → ${CURRENT_VERSION}
   Review changes: /octo:setup (or see CHANGELOG for role routing / default model shifts).
   Opt out of new routing: export OCTOPUS_LEGACY_ROLES=1
EOF

# Persist new version so we don't advise again next session
TMP=$(mktemp "${STATE_FILE}.XXXXXX")
jq --arg v "$CURRENT_VERSION" '.last_seen_version = $v' "$STATE_FILE" > "$TMP" \
    && mv "$TMP" "$STATE_FILE"

exit 0
