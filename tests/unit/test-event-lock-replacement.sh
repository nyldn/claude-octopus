#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/events.sh"
test_suite "Event lock directory replacement safety"
fixture="$TEST_TMP_DIR/event-lock-replacement"
mkdir -p "$fixture"

replace_foreign() {
    command mv "$lockdir" "$lockdir.old"
    command mkdir "$lockdir"
    builtin printf '%s\n' "$foreign_owner" > "$lockdir/pid"
    builtin printf '%s\n' '987654321' > "$lockdir/ts"
}

foreign_preserved() {
    [[ "$(cat "$lockdir/pid" 2>/dev/null)" == "$foreign_owner" ]] &&
        [[ "$(cat "$lockdir/ts" 2>/dev/null)" == 987654321 ]]
}

test_case "relative lock paths retain caller ownership and caller working directory"
(
    cd "$fixture"
    prior="$PWD" owner="${BASHPID:-$$}"
    _octo_event_lock relative
    [[ "$PWD" == "$prior" && "$(cat relative.lock/pid)" == "$owner" ]]
    _octo_event_unlock relative
    [[ ! -e relative.lock && "$PWD" == "$prior" ]]
) && test_pass || test_fail "relative lock changed directory or ownership"

test_case "failed PID write preserves a replacement live owner"
target="$fixture/pid-failure" lockdir="$fixture/pid-failure.lock" foreign_owner="${BASHPID:-$$}"
rc=0
(
    printf() { replace_foreign; return 74; }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 ]] && foreign_preserved; then test_pass
else test_fail "PID failure deleted replacement metadata"; fi

test_case "stale reclamation cleans only the inode it inspected"
target="$fixture/stale" lockdir="$fixture/stale.lock" foreign_owner="${BASHPID:-$$}"
mkdir "$lockdir"
printf '999999999\n' > "$lockdir/pid"
printf '1\n' > "$lockdir/ts"
rc=0
(
    date() { replace_foreign; builtin printf '100\n'; }
    OCTO_EVENT_LOCK_STALE_SECS=1 _octo_event_reclaim_stale_lock "$lockdir"
) || rc=$?
if [[ "$rc" == 1 ]] && foreign_preserved; then test_pass
else test_fail "stale reclaimer deleted a new live owner's metadata"; fi

test_case "timestamp failure preserves a replacement live owner"
target="$fixture/ts-failure" lockdir="$fixture/ts-failure.lock" foreign_owner="${BASHPID:-$$}"
rc=0
(
    date() { replace_foreign; return 74; }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 ]] && foreign_preserved; then test_pass
else test_fail "timestamp failure deleted replacement metadata"; fi

test_case "successful metadata writes cannot admit an owner of a replaced inode"
target="$fixture/ts-success" lockdir="$fixture/ts-success.lock" foreign_owner="${BASHPID:-$$}"
rc=0
(
    date() { replace_foreign; builtin printf '100\n'; }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 ]] && foreign_preserved; then test_pass
else test_fail "metadata writes admitted or damaged a replacement owner"; fi

test_case "an empty replacement before PID claim fails closed"
target="$fixture/empty" lockdir="$fixture/empty.lock"
rc=0
(
    cd() {
        builtin cd "$@" || return $?
        command mv "$lockdir" "$lockdir.old"
        command mkdir "$lockdir"
    }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 && ! -e "$lockdir" && ! -e "$lockdir.old/pid" ]]; then test_pass
else test_fail "empty replacement admitted a false owner"; fi

test_case "unlock from another live caller preserves ownership"
target="$fixture/unlock-foreign" lockdir="$fixture/unlock-foreign.lock"
_octo_event_lock "$target"
owner="$(cat "$lockdir/pid")"
(
    _octo_event_unlock "$target"
)
if [[ "$(cat "$lockdir/pid" 2>/dev/null)" == "$owner" ]]; then test_pass
else test_fail "another caller removed the live claim"; fi
_octo_event_unlock "$target"

test_case "unlock cleanup remains anchored after the public name changes"
target="$fixture/unlock-race" lockdir="$fixture/unlock-race.lock" foreign_owner="${BASHPID:-$$}"
(
    _octo_event_lock "$target"
    rm() { replace_foreign; command rm "$@"; }
    _octo_event_unlock "$target"
) && foreign_preserved && test_pass || test_fail "unlock removed replacement metadata"

test_case "a parent may still clean a finished subshell's abandoned claim"
target="$fixture/finished" lockdir="$fixture/finished.lock"
(
    _octo_event_lock "$target"
)
_octo_event_unlock "$target"
if [[ ! -e "$lockdir" ]]; then test_pass
else test_fail "finished subshell claim was not cleanable"; fi

test_case "failed BSD stat output does not contaminate GNU mtime fallback"
target="$fixture/stat-fallback" lockdir="$fixture/stat-fallback.lock"
mkdir "$lockdir"
(
    stat() {
        if [[ "$1" == -f ]]; then builtin printf 'filesystem diagnostics\n'; return 1; fi
        builtin printf '946684800\n'
    }
    OCTO_EVENT_LOCK_STALE_SECS=1 _octo_event_reclaim_stale_lock "$lockdir"
) && [[ ! -e "$lockdir" ]] && test_pass || test_fail "failed stat stdout hid a valid stale timestamp"

test_case "the native host stat can reclaim an aged bare directory"
target="$fixture/native-stat" lockdir="$fixture/native-stat.lock"
mkdir "$lockdir"
touch -t 200001010000 "$lockdir"
OCTO_EVENT_LOCK_STALE_SECS=1 _octo_event_reclaim_stale_lock "$lockdir" &&
    [[ ! -e "$lockdir" ]] && test_pass || test_fail "native stat could not reclaim bare directory"

test_case "symlink owner and timestamp metadata remain untouched"
(
    for metadata in pid ts; do
        target="$fixture/link-$metadata" lockdir="$fixture/link-$metadata.lock"
        mkdir "$lockdir"
        printf '999999999\n' > "$lockdir/pid"
        printf '1\n' > "$lockdir/ts"
        printf 'foreign\n' > "$fixture/backing-$metadata"
        rm "$lockdir/$metadata"
        ln -s "$fixture/backing-$metadata" "$lockdir/$metadata"
        rc=0
        OCTO_EVENT_LOCK_STALE_SECS=1 _octo_event_reclaim_stale_lock "$lockdir" || rc=$?
        [[ "$rc" == 1 && -L "$lockdir/$metadata" && "$(cat "$fixture/backing-$metadata")" == foreign ]] || exit 1
        _octo_event_unlock "$target"
        [[ -L "$lockdir/$metadata" && "$(cat "$fixture/backing-$metadata")" == foreign ]] || exit 1
    done
) && test_pass || test_fail "metadata link followed or removed"

test_case "a false-success utility cannot publish a live claim during stale cleanup"
target="$fixture/same-inode" lockdir="$fixture/same-inode.lock"
mkdir "$lockdir"
printf '999999999\n' > "$lockdir/pid"
printf '1\n' > "$lockdir/ts"
(
    while [[ ! -e "$fixture/reclaim-gap" ]]; do command sleep 0.001; done
    mkdir() { return 0; }
    sleep() { :; }
    date() { builtin printf '100\n'; }
    _octo_event_reclaim_stale_lock() { return 75; }
    rc=0; _octo_event_lock "$target" || rc=$?
    builtin printf '%s\n' "$rc" > "$fixture/contender-status"
    if [[ "$rc" == 0 ]]; then
        while [[ ! -e "$fixture/finish-contender" ]]; do command sleep 0.001; done
        _octo_event_unlock "$target"
    fi
) & contender=$!
rc=0
(
    date() {
        command rm "$lockdir/pid" "$lockdir/ts"
        touch "$fixture/reclaim-gap"
        for ((attempt=0; attempt<10000; attempt++)); do
            [[ -e "$fixture/contender-status" ]] && break
            command sleep 0.001
        done
        [[ -e "$fixture/contender-status" ]] || return 1
        builtin printf '100\n'
    }
    OCTO_EVENT_LOCK_STALE_SECS=1 _octo_event_reclaim_stale_lock "$lockdir"
) || rc=$?
contender_status="$(cat "$fixture/contender-status" 2>/dev/null || true)"
touch "$fixture/finish-contender"
wait "$contender"
if [[ "$rc" == 0 && "$contender_status" == 75 ]]; then test_pass
else test_fail "a contender entered the extant inode during stale cleanup"; fi

test_case "missing Python stops lock admission before creating metadata"
target="$fixture/no-python" lockdir="$fixture/no-python.lock"
mkdir "$fixture/no-python-bin"
for program in mkdir sleep date rm rmdir dirname wc tr; do
    ln -s "$(command -v "$program")" "$fixture/no-python-bin/$program"
done
rc=0
(
    PATH="$fixture/no-python-bin"
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 && ! -e "$lockdir" ]]; then test_pass
else test_fail "unavailable Python admitted a lock or changed failure status"; fi

test_case "optional event logging keeps its unlocked fallback without Python"
target="$fixture/no-python-events.jsonl"
(
    PATH="$fixture/no-python-bin"
    OCTO_EVENT_LOG="$target" octo_event_emit event.test source=fixture
) && [[ -s "$target" && ! -e "$target.lock" ]] && test_pass || test_fail "missing Python suppressed optional event logging"

test_case "kernel creation errors stop promptly without retry sleeps"
target="$fixture/missing-parent/event" lockdir="$fixture/missing-parent/event.lock"
rc=0
(
    sleep() { touch "$fixture/unexpected-sleep"; return 1; }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 && ! -e "$lockdir" && ! -e "$fixture/unexpected-sleep" ]]; then test_pass
else test_fail "infrastructure creation error was retried or admitted"; fi

test_summary
