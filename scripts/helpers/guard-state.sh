#!/usr/bin/env bash
# Activate guard state using the same stable session identity as its hooks.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "$ROOT/scripts/lib/session-id.sh"
if [[ -z "${OCTOPUS_HOST:-}" && -z "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION:-}}}" && -n "${CODEX_PLUGIN_ROOT:-${CODEX_SESSION_ID:-${CODEX_TASK_ID:-}}}" ]]; then
    export OCTOPUS_HOST=codex
fi
sid="$(octo_resolve_session_id "")" || {
    echo 'ERROR: no stable host session ID; guard state was not changed.' >&2
    exit 2
}
[[ "$sid" =~ ^[A-Za-z0-9._:-]+$ ]] || { echo 'ERROR: invalid host session ID.' >&2; exit 2; }
action="${1:-}"
case "$action" in
    careful-on|careful-off|freeze-on|freeze-off|guard-on) ;;
    *) echo 'Usage: guard-state.sh careful-on|careful-off|freeze-on DIR|freeze-off|guard-on [DIR]' >&2; exit 2 ;;
esac
boundary=""
if [[ "$action" == freeze-on || ( "$action" == guard-on && -n "${2:-}" ) ]]; then
    [[ -n "${2:-}" ]] || { echo 'ERROR: directory required.' >&2; exit 2; }
    boundary="$(cd "$2" && pwd -P)" || { echo 'ERROR: freeze directory does not exist.' >&2; exit 2; }
fi
# write_state: Atomically publish private state; never move it into a directory.
write_state() {
    local kind="$1" value="$2" temporary
    umask 077
    temporary="$(mktemp "/tmp/octopus-${kind}-${sid}.XXXXXX")"
    if ! printf '%s\n' "$value" > "$temporary" || ! python3 - "$temporary" "/tmp/octopus-${kind}-${sid}.txt" <<'PYREPLACE'
import os
import sys

try:
    os.replace(sys.argv[1], sys.argv[2])
except OSError:
    raise SystemExit("Guard activation failed: state could not be replaced.")
PYREPLACE
    then
        rm -f "$temporary"
        return 1
    fi
}
case "$action" in
    careful-on) write_state careful active ;;
    careful-off) rm -f "/tmp/octopus-careful-${sid}.txt" ;;
    freeze-on) write_state freeze "$boundary" ;;
    freeze-off) rm -f "/tmp/octopus-freeze-${sid}.txt" ;;
    guard-on)
        write_state careful active
        if [[ -n "$boundary" ]]; then write_state freeze "$boundary"; fi
        ;;
esac
printf '%s for session %s\n' "$action" "$sid"
