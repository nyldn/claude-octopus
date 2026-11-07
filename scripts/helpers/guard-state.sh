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
# write_state: Stage related writes and restore prior files if publication fails.
write_state() {
    umask 077
    python3 - "$sid" "$@" <<'PYREPLACE'
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile

staging = Path(tempfile.mkdtemp(prefix="octopus-guard-state-", dir="/tmp"))
preserve_backup = False
try:
    entries = []
    for index, (kind, value) in enumerate(zip(sys.argv[2::2], sys.argv[3::2])):
        destination = Path(f"/tmp/octopus-{kind}-{sys.argv[1]}.txt")
        backup = staging / f"previous-{index}"
        try:
            if stat.S_ISDIR(destination.lstat().st_mode):
                raise IsADirectoryError("guard state destination is a directory")
            # Snapshot the inode without reading state or following symlinks.
            os.link(destination, backup, follow_symlinks=False)
        except FileNotFoundError:
            backup = None
        candidate = staging / f"candidate-{index}"
        candidate.write_text(value + "\n", encoding="utf-8", errors="surrogateescape")
        entries.append((destination, candidate, backup))

    published = []
    try:
        for destination, candidate, backup in entries:
            identity = candidate.stat()
            os.replace(candidate, destination)
            published.append((destination, backup, identity))
    except OSError:
        for destination, backup, identity in reversed(published):
            try:
                current = destination.lstat()
                if (current.st_dev, current.st_ino) != (identity.st_dev, identity.st_ino):
                    raise OSError("state changed during rollback")
                if backup is None:
                    destination.unlink()
                else:
                    os.replace(backup, destination)
            except OSError:
                preserve_backup = True
        raise
except OSError:
    if preserve_backup:
        raise SystemExit(f"Guard rollback was blocked; prior state is preserved in {staging}.")
    raise SystemExit("Guard activation failed: state could not be replaced.")
finally:
    if not preserve_backup:
        shutil.rmtree(staging)
PYREPLACE
}
case "$action" in
    careful-on) write_state careful active ;;
    careful-off) rm -f "/tmp/octopus-careful-${sid}.txt" ;;
    freeze-on) write_state freeze "$boundary" ;;
    freeze-off) rm -f "/tmp/octopus-freeze-${sid}.txt" ;;
    guard-on)
        if [[ -n "$boundary" ]]; then
            write_state careful active freeze "$boundary"
        else
            write_state careful active
        fi
        ;;
esac
printf '%s for session %s\n' "$action" "$sid"
