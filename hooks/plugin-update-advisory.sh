#!/usr/bin/env bash
# SessionStart advisory for stale or non-updating Claude Octopus installs.
# Local inspection only: this hook must never invoke a package manager, perform
# network I/O, update a cache, or trigger authentication.

set -euo pipefail
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT

HOOK_DIR="$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$HOOK_DIR/.." 2>/dev/null && pwd)}"
UPDATE_LIB="$PLUGIN_ROOT/scripts/lib/plugin-update.sh"
STATE_DIR="${OCTOPUS_UPDATE_STATE_DIR:-${OCTOPUS_STATE_DIR:-${HOME}/.claude-octopus}}"
STATE_FILE="$STATE_DIR/update-advisory.json"
SETUP_MARKER="$STATE_DIR/.setup-complete"

[[ -r "$UPDATE_LIB" && -f "$SETUP_MARKER" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
# shellcheck source=../scripts/lib/plugin-update.sh
source "$UPDATE_LIB" 2>/dev/null || exit 0
octo_plugin_update_load "$PLUGIN_ROOT" claude

if [[ "$OCTO_PLUGIN_AUTO_UPDATE" == "enabled" \
      && "$OCTO_PLUGIN_UPDATE_AVAILABLE" != "true" \
      && "$OCTO_PLUGIN_RELOAD_REQUIRED" != "true" ]]; then
    exit 0
fi

NOW="${OCTOPUS_UPDATE_NOW:-$(date +%s)}"
COOLDOWN="${OCTOPUS_UPDATE_ADVISORY_COOLDOWN:-2592000}"
[[ "$NOW" =~ ^[0-9]+$ ]] || NOW=0
[[ "$COOLDOWN" =~ ^[0-9]+$ ]] || COOLDOWN=2592000
FINGERPRINT="${OCTO_PLUGIN_LOADED_VERSION}|${OCTO_PLUGIN_INSTALLED_VERSION}|${OCTO_PLUGIN_CATALOG_VERSION}|${OCTO_PLUGIN_CACHE_VERSION}|${OCTO_PLUGIN_AUTO_UPDATE}"
LAST_FINGERPRINT=""
LAST_NOTIFIED=0
if [[ -r "$STATE_FILE" ]] && jq -e . "$STATE_FILE" >/dev/null 2>&1; then
    LAST_FINGERPRINT="$(jq -r '.fingerprint // empty' "$STATE_FILE" 2>/dev/null || true)"
    LAST_NOTIFIED="$(jq -r '.notified_at // 0' "$STATE_FILE" 2>/dev/null || printf '0\n')"
    [[ "$LAST_NOTIFIED" =~ ^[0-9]+$ ]] || LAST_NOTIFIED=0
fi
if [[ "$LAST_FINGERPRINT" == "$FINGERPRINT" ]] && (( NOW - LAST_NOTIFIED < COOLDOWN )); then
    exit 0
fi

MESSAGE="Claude Octopus update health needs attention (loaded ${OCTO_PLUGIN_LOADED_VERSION}; installed ${OCTO_PLUGIN_INSTALLED_VERSION}; newest local ${OCTO_PLUGIN_NEWEST_VERSION}; auto-update ${OCTO_PLUGIN_AUTO_UPDATE})."
if [[ "$OCTO_PLUGIN_AUTO_UPDATE" != "enabled" ]]; then
    MESSAGE="${MESSAGE}
Enable auto-update in /plugin → Marketplaces → nyldn-plugins → Enable auto-update."
fi
if [[ "$OCTO_PLUGIN_UPDATE_AVAILABLE" == "true" ]]; then
    MESSAGE="${MESSAGE}
A newer version is already known locally. Run /octo:doctor to review the explicit update path; this startup hook never updates by itself."
fi
MESSAGE="${MESSAGE}
After an update, run /reload-plugins or restart Claude Code so this session stops using the stale loaded copy."

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
TMP_FILE="$(mktemp "${STATE_FILE}.XXXXXX" 2>/dev/null || true)"
if [[ -n "$TMP_FILE" ]]; then
    if jq -cn --arg fingerprint "$FINGERPRINT" --argjson notified_at "$NOW" \
        '{fingerprint:$fingerprint,notified_at:$notified_at}' > "$TMP_FILE" 2>/dev/null; then
        mv "$TMP_FILE" "$STATE_FILE" 2>/dev/null || true
    else
        rm -f "$TMP_FILE" 2>/dev/null || true
    fi
fi

jq -cn --arg msg "$MESSAGE" '{systemMessage:$msg}'
exit 0
