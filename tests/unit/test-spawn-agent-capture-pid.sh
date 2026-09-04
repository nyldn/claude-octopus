#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "spawn agent PID capture"

# Load only the helpers under test so the fixture controls spawn_agent and log.
eval "$(sed -n '/^_octopus_prune_task_id_reservations() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"
eval "$(sed -n '/^_octopus_next_spawn_task_id() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"
eval "$(sed -n '/^spawn_agent_capture_pid() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"

# Keep per-id reservation files inside the test sandbox instead of the real
# ~/.claude-octopus.
export WORKSPACE_DIR="$TEST_TMP_DIR"

log() { printf '%s %s\n' "${1:-}" "${2:-}" >> "$TEST_TMP_DIR/log"; }
source "$PROJECT_ROOT/scripts/lib/error-tracking.sh" >/dev/null 2>&1 || true

# The wrapper does meaningful setup before it can print the provider PID.
# Capture must wait for that PID rather than returning the wrapper PID.
test_case "returns delayed provider PID rather than wrapper PID"
spawn_agent() {
    sleep 0.3
    printf '%s\n' 424242
}
export "OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS=20"
pid=$(spawn_agent_capture_pid codex prompt delayed-task implementer tangle)
if [[ "$pid" == "424242" ]]; then
    test_pass
else
    test_fail "expected provider PID 424242, got: ${pid:-empty}"
fi

test_case "budget notice is replayed once without contaminating captured PID"
original_log="$(declare -f log)"
log() { printf '%s: %s\n' "$1" "$2" >&2; }
spawn_agent() {
    octo_notice_warn "Context budget: compressed reviewer/review"
    printf '%s\n' 424242
}
capture_notice_err="$TEST_TMP_DIR/capture-notice.err"
pid=$(spawn_agent_capture_pid codex prompt notice-task reviewer review 2>"$capture_notice_err")
eval "$original_log"
if [[ "$pid" == 424242 ]] &&
   [[ "$(grep -c '^WARN: Context budget: compressed reviewer/review$' "$capture_notice_err" || true)" -eq 1 ]]; then
    test_pass
else
    test_fail "PID was contaminated or notice count differed: pid='${pid:-empty}' notices='$(cat "$capture_notice_err")'"
fi

test_case "untrusted notice paths and inherited descriptor 8 cannot bypass stderr capture"
original_log="$(declare -f log)"
log() { printf '%s: %s\n' "$1" "$2" >&2; }
spawn_agent() {
    { printf 'descriptor bypass\n' >&8; } 2>/dev/null || true
    octo_notice_warn "Context budget: compressed reviewer/review"
    printf '%s\n' 424242
}
invalid_notice="$TEST_TMP_DIR/spawn-invalid-notice"
symlink_notice="$TEST_TMP_DIR/spawn-symlink-notice"
symlink_target="$TEST_TMP_DIR/spawn-symlink-target"
printf 'invalid sentinel\n' > "$invalid_notice"
chmod 644 "$invalid_notice"
printf 'symlink sentinel\n' > "$symlink_target"
ln -s "$symlink_target" "$symlink_notice"
capture_fallback_err="$TEST_TMP_DIR/capture-fallback.err"
fd8_target="$TEST_TMP_DIR/inherited-fd8"
: > "$capture_fallback_err"
: > "$fd8_target"
capture_fallback_ok=true
for notice_channel in "" "$invalid_notice" "$symlink_notice"; do
    pid="$(OCTOPUS_NOTICE_FILE="$notice_channel" \
        spawn_agent_capture_pid codex prompt notice-fallback reviewer review \
        8>>"$fd8_target" 2>>"$capture_fallback_err")"
    [[ "$pid" == 424242 ]] || capture_fallback_ok=false
done
eval "$original_log"
if [[ "$capture_fallback_ok" == true ]] &&
   [[ "$(grep -c '^WARN: Context budget: compressed reviewer/review$' "$capture_fallback_err" || true)" -eq 3 ]] &&
   [[ "$(cat "$invalid_notice")" == "invalid sentinel" ]] &&
   [[ "$(cat "$symlink_target")" == "symlink sentinel" ]] &&
   [[ ! -s "$fd8_target" ]] &&
   ! find "$TEST_TMP_DIR" \( -name 'octo-notice.*' -o -name 'octo-spawn-pid.*' -o -name 'octo-spawn-stderr.*' \) | grep -q .; then
    test_pass
else
    test_fail "captured PID or stderr was contaminated, an untrusted path changed, descriptor 8 leaked, or a temp file remained"
fi

test_case "fallback JSON quoting preserves UTF-8 and escapes controls"
unicode_value=$'é-🐙\n\t\001'
quoted_value="$(octo_json_quote "$unicode_value")"
if jq -ne --arg expected "$unicode_value" --argjson actual "$quoted_value" \
    '$actual == $expected' >/dev/null 2>&1; then
    test_pass
else
    test_fail "fallback JSON encoder corrupted UTF-8 or controls: $quoted_value"
fi

test_case "writes the provider PID to the opt-in signal handoff"
handoff_file="$TEST_TMP_DIR/provider-pid-handoff"
pid=$(OCTOPUS_SPAWN_PID_HANDOFF_FD=9 \
    spawn_agent_capture_pid codex prompt handoff-task implementer tangle \
    9>"$handoff_file")
if [[ "$pid" == "424242" ]] &&
   grep -Eq '^capture-file:.*/octo-spawn-pid\.' "$handoff_file" &&
   grep -Eq '^wrapper:[1-9][0-9]*$' "$handoff_file" &&
   grep -qx 'provider:424242' "$handoff_file"; then
    test_pass
else
    test_fail "provider PID was not published through both capture channels"
fi

# A failed setup must fail dispatch. Returning the short-lived wrapper PID would
# make downstream wait loops report a false missing completion marker.
test_case "fails when spawn_agent exits without provider PID"
spawn_agent() {
    printf '%s\n' "setup failed before provider launch"
    return 1
}
export "OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS=20"
failed_capture_err="$TEST_TMP_DIR/failed-capture.err"
if pid=$(spawn_agent_capture_pid codex prompt failed-task implementer tangle 2>"$failed_capture_err"); then
    test_fail "expected failure, got wrapper/provider PID: ${pid:-empty}"
elif [[ "$(grep -c '^setup failed before provider launch$' "$failed_capture_err" || true)" -eq 1 ]] &&
     ! find "$TEST_TMP_DIR" \( -name 'octo-spawn-pid.*' -o -name 'octo-spawn-stderr.*' \) | grep -q .; then
    test_pass
else
    test_fail "failed spawn stderr was altered or capture temp files remained"
fi

test_case "implementation has no wrapper PID fallback"
if grep -q 'tracking wrapper PID' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
    test_fail "unsafe wrapper PID fallback still present"
else
    test_pass
fi

# Regression for #661: two concurrent spawns with no explicit task_id must not
# collide on the same-second `date +%s` value, or their result/temp files
# interleave and get attributed to the wrong provider. Tests the real,
# named _octopus_next_spawn_task_id() helper directly (both spawn_agent and
# spawn_agent_capture_pid delegate their default to it), rather than a
# sed line-range or a hand-copied reimplementation that could drift from
# the source or silently start exercising the wrong lines.
test_case "shared task_id helper does not collide across concurrent same-second calls"
date() { echo 1234567890; }  # freeze every call to the same second
: > "$TEST_TMP_DIR/task_ids"
{ _octopus_next_spawn_task_id >> "$TEST_TMP_DIR/task_ids"; } &
first_call=$!
{ _octopus_next_spawn_task_id >> "$TEST_TMP_DIR/task_ids"; } &
second_call=$!
wait "$first_call"
wait "$second_call"
unset -f date
first_id=$(sed -n '1p' "$TEST_TMP_DIR/task_ids")
second_id=$(sed -n '2p' "$TEST_TMP_DIR/task_ids")
if [[ -n "$first_id" && -n "$second_id" && "$first_id" != "$second_id" ]]; then
    test_pass
else
    test_fail "expected distinct default task_ids, got '$first_id' and '$second_id'"
fi

# Structural check independent of concurrency/timing: the id should be
# 'timestamp-<mktemp suffix>', keeping the two components unambiguously
# separated rather than free-form concatenation.
test_case "task_id fields are unambiguously delimited"
id=$(_octopus_next_spawn_task_id)
if [[ "$id" =~ ^[0-9]+-[A-Za-z0-9]+$ ]]; then
    test_pass
else
    test_fail "expected 'timestamp-suffix' shape, got: $id"
fi

# The whole point of switching to mktemp is a real OS-level uniqueness
# guarantee, not just low collision probability — so directly checking two
# fresh ids never repeats is a stronger assertion than only proving they
# survive a same-second race.
test_case "task_id helper never repeats across many calls"
: > "$TEST_TMP_DIR/many_ids"
for _ in $(seq 1 20); do
    _octopus_next_spawn_task_id >> "$TEST_TMP_DIR/many_ids"
done
total=$(wc -l < "$TEST_TMP_DIR/many_ids" | tr -d ' ')
unique=$(sort -u "$TEST_TMP_DIR/many_ids" | wc -l | tr -d ' ')
if [[ "$unique" == "$total" ]]; then
    test_pass
else
    test_fail "expected $total distinct task_ids, got only $unique unique"
fi

test_case "task_id helper prunes expired reservations"
reservation_dir="$WORKSPACE_DIR/.octo/task-ids"
expired_reservation="$reservation_dir/expired-reservation"
mkdir -p "$reservation_dir"
find "$reservation_dir" -type f -name '.pruned-*' -delete 2>/dev/null || true
: > "$expired_reservation"
touch -t 202001010000 "$expired_reservation"
_octopus_next_spawn_task_id >/dev/null
if [[ ! -e "$expired_reservation" ]]; then
    test_pass
else
    test_fail "expired task-id reservation was not pruned"
fi

# The PID/RANDOM fallback only fires when mktemp itself can't run (e.g. no
# writable tmp). Force that path and confirm it still produces a validly
# shaped, non-empty id instead of failing silently or breaking the caller.
test_case "falls back to PID/RANDOM when mktemp is unavailable"
mktemp() { return 1; }
fallback_id=$(_octopus_next_spawn_task_id)
unset -f mktemp
if [[ "$fallback_id" =~ ^[0-9]+-[A-Za-z0-9]+$ ]]; then
    test_pass
else
    test_fail "expected a valid 'timestamp-suffix' id from the fallback path, got: $fallback_id"
fi

# spawn_agent_capture_pid must actually use the shared helper when task_id is
# omitted, not a stale copy — exercised end to end through the real call path.
test_case "capture_pid uses the shared helper for an omitted task_id"
spawn_agent() {
    printf '%s\n' "$3" >> "$TEST_TMP_DIR/capture_pid_task_id"
    printf '%s\n' 424242
}
export "OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS=20"
: > "$TEST_TMP_DIR/capture_pid_task_id"
spawn_agent_capture_pid codex prompt >/dev/null
captured_id=$(cat "$TEST_TMP_DIR/capture_pid_task_id")
if [[ "$captured_id" =~ ^[0-9]+-[A-Za-z0-9]+$ ]]; then
    test_pass
else
    test_fail "expected capture_pid's omitted task_id to match the shared helper's shape, got: $captured_id"
fi

# Regression for #736 (root cause 3): when the PID-wait budget expires,
# $wrapper_pid may already have forked a real descendant (e.g. mid-pipeline
# provider call). A bare `kill "$wrapper_pid"` only signals that one process,
# orphaning the descendant. Load review.sh's tree-kill helper the same way
# spawn.sh's fixed code path resolves it, and prove the descendant is reaped.
test_case "descendant of a failed spawn is reaped, not left orphaned (#736)"
eval "$(sed -n '/^review_child_pids() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/review.sh")"
eval "$(sed -n '/^review_process_tree_depth_first() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/review.sh")"
eval "$(sed -n '/^review_terminate_process_tree() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/review.sh")"
eval "$(sed -n '/^review_process_is_running() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/review.sh")"
: > "$TEST_TMP_DIR/leaked_child_pid"
spawn_agent() {
    # Simulate a wrapper that has already forked a long-running child (the
    # provider pipeline) before the PID-wait budget runs out, then blocks
    # without ever printing a provider PID.
    ( sleep 30 & echo $! > "$TEST_TMP_DIR/leaked_child_pid"; wait )
}
# 3s of headroom (not the 0.3s a tight 3-attempt budget would give) so a
# loaded CI runner has time to schedule the fixture's fork before the
# wait budget expires — a slow scheduler shouldn't read as "cleanup
# didn't run" when the real gap is "the descendant was never forked yet".
export "OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS=30"
pid=$(spawn_agent_capture_pid codex prompt orphan-task implementer tangle 2>/dev/null) || true
for _ in $(seq 1 50); do
    [[ -s "$TEST_TMP_DIR/leaked_child_pid" ]] && break
    sleep 0.1
done
leaked_pid=$(cat "$TEST_TMP_DIR/leaked_child_pid" 2>/dev/null || true)
if [[ -z "$leaked_pid" ]]; then
    test_fail "descendant PID was never recorded — fixture did not exercise the timeout path"
else
    # kill -0 alone would false-positive on an unreaped zombie (the PID slot
    # stays allocated until something waits on it). review_process_is_running
    # also checks `ps` state for 'Z' so a killed-but-not-yet-reaped descendant
    # doesn't read as "still alive".
    still_running=false
    for _ in $(seq 1 20); do
        review_process_is_running "$leaked_pid" || { still_running=false; break; }
        still_running=true
        sleep 0.1
    done
    if [[ "$still_running" == "true" ]]; then
        test_fail "descendant PID $leaked_pid survived spawn_agent_capture_pid's timeout cleanup"
    else
        test_pass
    fi
fi

test_summary
