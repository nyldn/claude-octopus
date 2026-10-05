#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/events.sh"
test_suite "Exclusive event lock admission"
fixture="$TEST_TMP_DIR/event-lock-admission"
mkdir -p "$fixture"

test_case "successful lock records the live caller rather than the claim subshell"
target="$fixture/caller"
_octo_event_lock "$target"
owner="$(cat "$target.lock/pid")"
if [[ "$owner" == "${BASHPID:-$$}" ]] && kill -0 "$owner"; then test_pass
else test_fail "lock recorded a dead claim process"; fi
_octo_event_unlock "$target"

test_case "false mkdir success cannot replace a live owner or its timestamp"
target="$fixture/foreign"
mkdir "$target.lock"
sleep 30 & holder=$!
printf '%s\n' "$holder" > "$target.lock/pid"
printf '1\n' > "$target.lock/ts"
rc=0
(
    mkdir() { return 0; }
    sleep() { :; }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 75 && "$(cat "$target.lock/pid")" == "$holder" && "$(cat "$target.lock/ts")" == 1 ]]; then test_pass
else test_fail "false-success contender admitted or replaced foreign metadata"; fi
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true
rm -f "$target.lock/pid" "$target.lock/ts"
rmdir "$target.lock"

test_case "ordinary contention keeps its fifty attempts and forty-nine waits"
target="$fixture/attempts"
mkdir "$target.lock"
printf '%s\n' "$$" > "$target.lock/pid"
printf '1\n' > "$target.lock/ts"
(
    attempts=0 waits=0
    _octo_event_mkdir() { attempts=$((attempts + 1)); return 75; }
    sleep() { [[ "$1" == 0.02 ]] || return 1; waits=$((waits + 1)); }
    rc=0; _octo_event_lock "$target" || rc=$?
    [[ "$rc" == 75 && "$attempts" == 50 && "$waits" == 49 ]]
) && test_pass || test_fail "contention deadline or status changed"
rm -f "$target.lock/pid" "$target.lock/ts"
rmdir "$target.lock"

test_case "stale bare directories remain reclaimable"
target="$fixture/bare"
mkdir "$target.lock"
touch -t 200001010000 "$target.lock"
# Supply the portable stat result explicitly. The host's stat -f behavior is
# unrelated to admission and differs between BSD and uutils implementations.
(
    stat() { printf '946684800\n'; }
    OCTO_EVENT_LOCK_STALE_SECS=1 _octo_event_lock "$target"
) && test_pass || test_fail "stale bare lock did not recover"
_octo_event_unlock "$target"

test_case "unavailable bare-directory metadata preserves failure and the directory"
target="$fixture/bare-unreadable"
mkdir "$target.lock"
rc=0
(
    stat() { return 1; }
    sleep() { :; }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 && -d "$target.lock" ]]; then test_pass
else test_fail "unreadable bare lock changed status or was removed"; fi
rmdir "$target.lock"

test_case "malformed foreign owner metadata fails without deletion"
target="$fixture/malformed"
mkdir "$target.lock" "$target.lock/pid"
printf 'foreign\n' > "$target.lock/pid/evidence"
rc=0
(
    sleep() { :; }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 && "$(cat "$target.lock/pid/evidence")" == foreign ]]; then test_pass
else test_fail "malformed owner was admitted or deleted"; fi

test_case "failed initial PID writes return failure and remove only the empty claim"
target="$fixture/write-failure"
rc=0
(
    printf() { return 74; }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 && ! -e "$target.lock" ]]; then test_pass
else test_fail "failed PID write leaked a claim or changed status"; fi

test_case "failed timestamp writes release the acquired claim"
target="$fixture/date-failure"
rc=0
(
    date() { return 74; }
    _octo_event_lock "$target"
) || rc=$?
if [[ "$rc" == 1 && ! -e "$target.lock" ]]; then test_pass
else test_fail "failed timestamp write leaked a claim or changed status"; fi

test_case "parallel owners never overlap before unlock"
overlaps=0
for trial in $(seq 1 50); do
    target="$fixture/concurrent-$trial"
    mkdir "$target"
    for seat in one two; do
        (
            while [[ ! -e "$target/start" ]]; do sleep 0.001; done
            _octo_event_lock "$target/event"
            touch "$target/active-$seat"
            if [[ -e "$target/active-one" && -e "$target/active-two" ]]; then touch "$target/overlap"; fi
            sleep 0.05
            rm "$target/active-$seat"
            _octo_event_unlock "$target/event"
        ) &
        if [[ "$seat" == one ]]; then first=$!; else second=$!; fi
    done
    touch "$target/start"
    wait "$first"; wait "$second"
    if [[ -e "$target/overlap" ]]; then overlaps=$((overlaps + 1)); fi
done
if [[ "$overlaps" == 0 ]]; then test_pass
else test_fail "simultaneous active owners in $overlaps of fifty trials"; fi

test_summary
