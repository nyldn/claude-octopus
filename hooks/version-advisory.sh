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
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


STATE_DIR="${OCTOPUS_STATE_DIR:-${HOME}/.claude-octopus}"
STATE_FILE="${STATE_DIR}/state.json"
SETUP_MARKER="${STATE_DIR}/.setup-complete"
PLUGIN_MANIFEST="${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json"

# Progressive feature disclosure (scripts/lib/features.sh). Sourced defensively:
# this hook must never block or noisily fail a session, so a missing library just
# means the advisory keeps its pre-existing one-line form.
_HOOK_DIR="$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || _HOOK_DIR=""
for _feat_lib in \
    "${CLAUDE_PLUGIN_ROOT:-}/scripts/lib/features.sh" \
    "${_HOOK_DIR}/../scripts/lib/features.sh"
do
    if [[ -n "$_feat_lib" && -f "$_feat_lib" ]]; then
        # shellcheck source=../scripts/lib/features.sh
        source "$_feat_lib" 2>/dev/null || true
        break
    fi
done

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

# Seed the disclosure watermark from the version the user is coming FROM, not the
# one they are moving to. Seeding from CURRENT_VERSION would place every feature
# shipped in this release below the watermark, so nothing would ever be offered.
FEATURE_LINE=""
if declare -f octo_features_seed_watermark >/dev/null 2>&1; then
    export OCTOPUS_STATE_DIR="$STATE_DIR"
    octo_features_seed_watermark "$LAST_SEEN" 2>/dev/null || true
    _actionable="$(octo_features_actionable_count 2>/dev/null || echo 0)"
    if [[ "$_actionable" =~ ^[0-9]+$ ]] && (( _actionable > 0 )); then
        _noun="features are"; [[ "$_actionable" == "1" ]] && _noun="feature is"
        _plural="s"; [[ "$_actionable" == "1" ]] && _plural=""

        # SessionStart must not interrupt unrelated work or cause model actions.
        # Surface a compact user-visible pointer only.
        FEATURE_LINE="
   ${_actionable} new ${_noun} available to review explicitly: /octo:whats-new"
    fi
fi

# Version changed — advisory. Use systemMessage so the user sees it without
# injecting instructions into the model or taking over the first prompt.
jq -cn --arg msg "🐙 Claude Octopus updated: ${LAST_SEEN} → ${CURRENT_VERSION}
   Review changes with /octo:whats-new or CHANGELOG. Octopus stays dormant until you run /octo:*; optional automation is opt-in.${FEATURE_LINE}" \
    '{systemMessage:$msg}'

# Persist new version so we don't advise again next session
TMP=$(mktemp "${STATE_FILE}.XXXXXX")
jq --arg v "$CURRENT_VERSION" '.last_seen_version = $v' "$STATE_FILE" > "$TMP" \
    && mv "$TMP" "$STATE_FILE"

exit 0
