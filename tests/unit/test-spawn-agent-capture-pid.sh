#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "spawn agent PID capture"

# Load only the helpers under test so the fixture controls spawn_agent and log.
eval "$(sed -n '/^_octopus_next_spawn_task_id() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"
eval "$(sed -n '/^spawn_agent_capture_pid() {/,/^}/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"

TEST_TMP_DIR="/tmp/octopus-tests-$$"
mkdir -p "$TEST_TMP_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

# Keep the permanent per-id reservation files (see _octopus_next_spawn_task_id)
# inside the test sandbox instead of the real ~/.claude-octopus.
export WORKSPACE_DIR="$TEST_TMP_DIR"

log() { printf '%s %s\n' "${1:-}" "${2:-}" >> "$TEST_TMP_DIR/log"; }

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

# A failed setup must fail dispatch. Returning the short-lived wrapper PID would
# make downstream wait loops report a false missing completion marker.
test_case "fails when spawn_agent exits without provider PID"
spawn_agent() {
    printf '%s\n' "setup failed before provider launch"
    return 1
}
export "OCTOPUS_SPAWN_PID_WAIT_ATTEMPTS=20"
if pid=$(spawn_agent_capture_pid codex prompt failed-task implementer tangle 2>/dev/null); then
    test_fail "expected failure, got wrapper/provider PID: ${pid:-empty}"
else
    test_pass
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

test_summary
