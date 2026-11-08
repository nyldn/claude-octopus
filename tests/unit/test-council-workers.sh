#!/usr/bin/env bash
# Inert council worker lifecycle and admission regressions.
# Settings are consumed by sourced council functions.
# shellcheck disable=SC2034
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/council.sh"
test_suite "Council bounded workers"
COUNCIL_FIXTURE=""
COUNCIL_MAX_COST=5
COUNCIL_DEPTH=deep
COUNCIL_RESOLVED_MEMBERS=4
COUNCIL_TASK="test"
COUNCIL_ROSTER_JSON='[{"persona":"one","provider":"codex","seat":"member"},{"persona":"two","provider":"gemini","seat":"member"},{"persona":"three","provider":"codex","seat":"member"},{"persona":"four","provider":"gemini","seat":"member"}]'
OCTOPUS_COUNCIL_MAX_PARALLEL=2
OCTOPUS_COUNCIL_PROVIDER_MAX_PARALLEL=1
OCTOPUS_COUNCIL_REAP_GRACE_SECS=0
OCTOPUS_COUNCIL_DEADLINE_SECS=0
council_seat_timeout() {
    if [[ "${INERT_WAIT_TEST:-0}" == 1 ]]; then
        case "$1" in codex) echo 4 ;; *) echo 1 ;; esac
    else echo "${INERT_TIMEOUT:-10}"; fi
}
record_agent_call() {
    # Inert accounting helper, executed by the scheduler in production order.
    [[ "$2" == vendor/model:qualified && "$3" == $'prompt\n' ]] || return 75
    [[ "${INERT_RESERVATION_FAIL:-}" != "$7" ]] || return 74
    printf '%s %s %s\n' "$1" "$2" "$7" >> "$COUNCIL_RUN_DIR/reservations"
}
council_dispatch_member() {
    local persona provider
    persona="$(jq -r .persona <<< "$1")"; provider="$(jq -r .provider <<< "$1")"
    [[ "$persona" != one ]] || sleep "${INERT_PREPARE_FIRST:-0.2}"
    [[ "$persona" != two ]] || sleep "${INERT_PREPARE_SECOND:-0}"
    record_agent_call "$provider" "vendor/model:qualified" $'prompt\n' council "$persona" 0 "$persona"
    # One append per event, each comfortably under PIPE_BUF.
    printf 'start %s %s\n' "$persona" "$provider" >> "$COUNCIL_RUN_DIR/events"
    printf 'partial %s\n' "$persona"
    if [[ "${INERT_OVERLAP_BARRIER:-0}" == 1 && ( "$persona" == one || "$persona" == two ) ]]; then
        local ready=false attempt peer=one
        [[ "$persona" != one ]] || peer=two
        for ((attempt=0; attempt<200; attempt++)); do
            if grep -q "^start $peer " "$COUNCIL_RUN_DIR/events"; then ready=true; break; fi
            sleep 0.05
        done
        [[ "$ready" == true ]] || { printf 'overlap readiness timed out: %s\n' "$persona" >&2; return 76; }
    fi
    if [[ "$persona" == one ]]; then sleep "${INERT_SLEEP_FIRST:-${INERT_SLEEP:-1}}"; else sleep "${INERT_SLEEP:-1}"; fi
    printf 'end %s %s\n' "$persona" "$provider" >> "$COUNCIL_RUN_DIR/events"
    [[ "$persona" != "${INERT_FAIL:-}" ]] || return 7
    printf 'VERDICT: APPROVE\n'
}
prepare() {
    COUNCIL_RUN_DIR="$TEST_TMP_DIR/$1"
    mkdir -p "$COUNCIL_RUN_DIR/responses" "$COUNCIL_RUN_DIR/critiques" "$COUNCIL_RUN_DIR/revisions" "$COUNCIL_RUN_DIR/stderr"
}
check_events() {
    python3 - "$COUNCIL_RUN_DIR/events" "$1" "$2" <<'CHECK'
import sys
active = {}; peak = 0; starts = []
for line in open(sys.argv[1]):
    event, seat, provider = line.split()
    if event == 'start':
        active[provider] = active.get(provider, 0) + 1
        starts.append(seat)
    else:
        active[provider] -= 1
    assert max(active.values()) <= int(sys.argv[3]), active
    assert sum(active.values()) <= int(sys.argv[2]), active
    peak = max(peak, sum(active.values()))
assert sorted(starts) == ['four', 'one', 'three', 'two'], starts
assert peak == int(sys.argv[2]), peak
assert sum(active.values()) == 0
CHECK
}

test_case "explicit global, outer and provider limits resolve without octal arithmetic"
if [[ "$(OCTOPUS_COUNCIL_MAX_PARALLEL=08 MAX_PARALLEL=3 council_pool_global_limit)" == 3 && "$(OCTOPUS_COUNCIL_MAX_PARALLEL_CODEX=2 council_pool_provider_limit codex)" == 2 && "$(MAX_PARALLEL=1 council_pool_global_limit)" == 1 ]]; then test_pass; else test_fail "configured limits changed"; fi

test_case "independent seats overlap within caps and reserve each provider in FIFO order"
prepare overlap
INERT_OVERLAP_BARRIER=1 INERT_PREPARE_SECOND=0.3 INERT_SLEEP_FIRST=0.02 INERT_SLEEP=0.02 INERT_TIMEOUT=20 council_run_seat_pool independent-advice responses
if check_events 2 1 && python3 - "$COUNCIL_RUN_DIR/reservations" <<'CHECK'
import sys
rows = [line.split() for line in open(sys.argv[1])]
seats = [row[2] for row in rows]
assert sorted(seats) == ['four', 'one', 'three', 'two'], seats
for provider, expected in [('codex', ['one', 'three']), ('gemini', ['two', 'four'])]:
    actual = [row[2] for row in rows if row[0] == provider]
    assert actual == expected, (provider, actual)
CHECK
then
    if [[ "$(find "$COUNCIL_RUN_DIR/responses" -name '*.admitted' | wc -l | tr -d ' ')" == 4 ]]; then test_pass; else test_fail "missing admission record"; fi
else test_fail "overlap/cap/provider FIFO mismatch"; fi

test_case "a capped provider does not block a later eligible seat"
prepare provider-gap
roster_before="$COUNCIL_ROSTER_JSON"
COUNCIL_ROSTER_JSON='[{"persona":"one","provider":"codex","seat":"member"},{"persona":"two","provider":"codex","seat":"member"},{"persona":"three","provider":"gemini","seat":"member"}]'
INERT_SLEEP_FIRST=1.5 INERT_SLEEP=0.1 council_run_seat_pool independent-advice responses
if python3 - "$COUNCIL_RUN_DIR" <<'CHECK'
from pathlib import Path
import sys
root = Path(sys.argv[1])
events = root.joinpath('events').read_text().splitlines()
assert events.index('end three gemini') < events.index('end one codex'), events
assert events.index('start two codex') > events.index('end one codex'), events
assert [line.split()[-1] for line in root.joinpath('reservations').read_text().splitlines()] == ['one', 'three', 'two']
assert all(path.read_text().splitlines()[0] == '0' for path in root.joinpath('responses').glob('*.pool-result'))
CHECK
then test_pass; else test_fail "eligible provider starved or accounting order changed"; fi
test_case "an aggregate deadline retains the eligible provider without charging a queued seat"
prepare provider-gap-deadline
COUNCIL_RUN_START_EPOCH="$(date +%s)" OCTOPUS_COUNCIL_DEADLINE_SECS=4 OCTOPUS_COUNCIL_DEADLINE_SEAT_FLOOR_SECS=1 INERT_SLEEP_FIRST=8 INERT_SLEEP=0.1 \
    council_run_seat_pool independent-advice responses
if grep -q '^end three gemini$' "$COUNCIL_RUN_DIR/events" &&
   [[ ! -e "$COUNCIL_RUN_DIR/responses/01-two.md.admitted" ]] &&
   [[ "$(awk '{print $3}' "$COUNCIL_RUN_DIR/reservations" | tr '\n' ' ')" == "one three " ]]; then
    test_pass
else test_fail "deadline starved the eligible provider or charged a queued seat"; fi
COUNCIL_ROSTER_JSON="$roster_before"

test_case "queued reservation time does not consume a later provider's timeout"
prepare preparation-wait
roster_before="$COUNCIL_ROSTER_JSON"
COUNCIL_ROSTER_JSON='[{"persona":"one","provider":"codex","seat":"member"},{"persona":"two","provider":"gemini","seat":"member"}]'
INERT_WAIT_TEST=1 INERT_PREPARE_FIRST=2 INERT_SLEEP=0.7 council_run_seat_pool independent-advice responses
if [[ "$(head -1 "$COUNCIL_RUN_DIR/responses/00-one.md.pool-result")" == 0 && "$(head -1 "$COUNCIL_RUN_DIR/responses/01-two.md.pool-result")" == 0 ]] &&
   grep -c '^end two ' "$COUNCIL_RUN_DIR/events" >/dev/null; then test_pass; else test_fail "reservation waiting exhausted the provider budget"; fi
COUNCIL_ROSTER_JSON="$roster_before"

test_case "a reservation wait exits when its scheduler disappears"
prepare orphaned-reservation
sleep 20 & scheduler=$!
(
    _COUNCIL_POOL_PID="$scheduler"
    result=0
    council_pool_request_reservation "$COUNCIL_RUN_DIR/orphan" inert || result=$?
    printf '%s\n' "$result" > "$COUNCIL_RUN_DIR/orphan-result"
) & waiter=$!
for attempt in {1..100}; do
    [[ -f "$COUNCIL_RUN_DIR/orphan.reserve" ]] && break
    sleep 0.02
done
kill -KILL "$scheduler"; wait "$scheduler" 2>/dev/null || true
for attempt in {1..100}; do
    [[ -f "$COUNCIL_RUN_DIR/orphan-result" ]] && break
    sleep 0.02
done
if [[ -f "$COUNCIL_RUN_DIR/orphan-result" && "$(cat "$COUNCIL_RUN_DIR/orphan-result")" == 75 ]]; then test_pass; else
    kill "$waiter" 2>/dev/null || true
    test_fail "reservation worker outlived its missing scheduler"
fi
wait "$waiter" 2>/dev/null || true

test_case "serial configuration keeps the inline collector behavior"
prepare serial
OCTOPUS_COUNCIL_MAX_PARALLEL=1 council_run_seat_pool independent-advice responses
index=0
while IFS= read -r member; do
    persona="$(jq -r .persona <<< "$member")"
    council_collect_seat "$member" independent-advice "$COUNCIL_RUN_DIR/responses/$index-$persona.md"
    index=$((index + 1))
done < <(jq -c '.[]' <<< "$COUNCIL_ROSTER_JSON")
if check_events 1 1; then test_pass; else test_fail "serial cap mismatch"; fi

test_case "failed seats retain their nonzero result"
prepare failure
INERT_FAIL=two council_run_seat_pool cross-critique critiques
rc=0
council_collect_seat '{}' cross-critique "$COUNCIL_RUN_DIR/critiques/01-two.md" || rc=$?
if [[ "$rc" == 7 ]]; then test_pass; else test_fail "failed worker became rc=$rc"; fi

test_case "watchdog cancels owned descendants, retains partial output, and prevents late publication"
prepare timeout
sleep 20 &
unrelated=$!
INERT_SLEEP=5 INERT_TIMEOUT=1 council_run_seat_pool independent-advice responses
rc=0
council_collect_seat '{}' independent-advice "$COUNCIL_RUN_DIR/responses/00-one.md" || rc=$?
if [[ "$rc" == 137 && -s "$COUNCIL_RUN_DIR/responses/00-one.md.partial" && ! -e "$COUNCIL_RUN_DIR/responses/00-one.md" ]] && kill -0 "$unrelated"; then test_pass; else test_fail "timeout evidence or ownership mismatch"; fi
kill "$unrelated"; wait "$unrelated" 2>/dev/null || true

test_case "interruption cancels only the pool and retains unfinished evidence"
prepare interrupted
(
    INERT_SLEEP=10 council_run_seat_pool independent-advice responses
) &
runner=$!
for attempt in {1..100}; do
    [[ -s "$COUNCIL_RUN_DIR/responses/01-two.md.partial" ]] && break
    sleep 0.05
done
kill -TERM "$runner"
rc=0
wait "$runner" || rc=$?
if [[ "$rc" == 143 && -s "$COUNCIL_RUN_DIR/responses/00-one.md.partial" && ! -e "$COUNCIL_RUN_DIR/responses/00-one.md" && -s "$COUNCIL_RUN_DIR/responses/01-two.md.pool-result" ]]; then test_pass; else test_fail "interrupted pool rc=$rc"; fi

test_case "aggregate deadline stops queued seats and cancels active seats"
prepare deadline
COUNCIL_RUN_START_EPOCH="$(date +%s)" OCTOPUS_COUNCIL_DEADLINE_SECS=5 OCTOPUS_COUNCIL_DEADLINE_SEAT_FLOOR_SECS=2 INERT_SLEEP=8 INERT_TIMEOUT=3 \
    council_run_seat_pool independent-advice responses
if [[ ! -e "$COUNCIL_RUN_DIR/responses/03-four.md.admitted" && -s "$COUNCIL_RUN_DIR/responses/00-one.md.partial" ]]; then test_pass; else test_fail "aggregate deadline evidence mismatch"; fi

test_case "cost rejection launches no seats"
prepare budget
rc=0
COUNCIL_MAX_COST=0 council_run_seat_pool independent-advice responses || rc=$?
if [[ "$rc" != 0 && ! -e "$COUNCIL_RUN_DIR/events" ]]; then test_pass; else test_fail "budget admitted a worker"; fi

test_case "a rejected reservation blocks the provider and cancels other owned work"
prepare rejected
rc=0
INERT_RESERVATION_FAIL=two council_run_seat_pool independent-advice responses || rc=$?
if [[ "$rc" != 0 ]] && ! grep -q '^start two ' "$COUNCIL_RUN_DIR/events" 2>/dev/null; then test_pass; else test_fail "unreserved provider launched"; fi

test_case "batched fields preserve null, empty, newlines, and qualified models"
member='{"persona":"line\nend\n","seat":null,"agent_spec":"openrouter:vendor/model:qualified","provider_org":"","model":"model\n","model_family":null}'
persona=''; seat=''; mprovider_spec=''; seat_org=x; seat_model=''; seat_model_family=x
council_read_seat_fields "$member"
if [[ "$persona" == $'line\nend\n' && "$seat" == null && "$mprovider_spec" == openrouter:vendor/model:qualified && -z "$seat_org" && "$seat_model" == $'model\n' && -z "$seat_model_family" ]]; then test_pass; else test_fail "field extraction changed values"; fi

test_summary
