#!/usr/bin/env bash
# Chair fallback dispatches at most OCTOPUS_COUNCIL_CHAIR_FALLBACK_MAX attempts.
#
# When the chair's answer was not accepted, council_run_chair_fallback re-ran the
# full advice prompt under up to five synthesis-capable personas in turn. Each
# had the same prompt and evidence, so a chair rejected as blind was followed by
# rejected attempts that never reached seats[]: a live quick council spent
# $0.77 of $1.23 on five of them. Attempts are now capped (default 1) and
# counted in summary.json quorum.chair_fallback_attempts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Council chair fallback cap"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/council.sh"

# Every dispatched attempt answers without a verdict or evidence, so it is
# rejected; the call counter shows how many attempts ran.
run_fallback() {
    local d; d="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/chair-cap.XXXXXX")"
    mkdir -p "$d/responses" "$d/stderr"
    COUNCIL_RUN_DIR="$d"
    COUNCIL_SEAT_RECORDS_JSON='[{"persona":"strategy-analyst","seat":"chair","status":"blind"}]'
    COUNCIL_PROVIDER_STATUS_JSON='{"claude":"available"}'
    COUNCIL_TIMEOUT_WARNINGS="" COUNCIL_QUOTA_LIMITED_SEATS=""
    COUNCIL_CHAIR_RESPONSE_RECEIVED="false" COUNCIL_CHAIR_FALLBACK_USED="false"
    COUNCIL_CHAIR_FALLBACK_PERSONA="" COUNCIL_CHAIR_FALLBACK_ATTEMPTS=0
    printf '0' > "$d/calls"
    council_pick_provider() { printf 'claude'; }
    council_roster_entry_json() {
        jq -cn --arg persona "$1" --arg provider "$2" '{persona:$persona,provider:$provider,provider_org:"anthropic",model:"sonnet",seat:"member"}'
    }
    council_dispatch_member_detached() {
        printf '%s' "$(( $(cat "$COUNCIL_RUN_DIR/calls") + 1 ))" > "$COUNCIL_RUN_DIR/calls"
        printf 'ok\n' > "$3"
        return 0
    }
    council_run_chair_fallback sha256:test 2> "$d/err" || true
    unset -f council_pick_provider council_roster_entry_json council_dispatch_member_detached
    CALLS="$(cat "$d/calls")"
    ERR="$(cat "$d/err")"
}

assert_summary_attempts() {
    local expected="$1"
    test_case "Council summary reports $expected dispatched fallback attempt(s) in quorum"
    if (COUNCIL_ROSTER_JSON="$COUNCIL_SEAT_RECORDS_JSON" COUNCIL_MAX_COST=1 \
        COUNCIL_RESOLVED_MEMBERS=3 council_write_summary_json partial) &&
        jq -e --argjson expected "$expected" \
            '.quorum.chair_fallback_attempts == $expected' "$COUNCIL_RUN_DIR/summary.json" >/dev/null; then
        test_pass
    else
        test_fail "unexpected quorum: $(jq -c .quorum "$COUNCIL_RUN_DIR/summary.json" 2>/dev/null || true)"
    fi
}

unset OCTOPUS_COUNCIL_CHAIR_FALLBACK_MAX
council_reset_defaults
test_case "by default a rejected chair gets one fallback attempt, not five"
run_fallback
if [[ "$CALLS" == 1 && "$COUNCIL_CHAIR_FALLBACK_ATTEMPTS" == 1 && "$ERR" == *"chair fallback stopped after 1 dispatched attempt"* ]]; then
    test_pass
else
    test_fail "calls=$CALLS attempts=$COUNCIL_CHAIR_FALLBACK_ATTEMPTS err=$ERR"
fi
assert_summary_attempts 1

test_case "OCTOPUS_COUNCIL_CHAIR_FALLBACK_MAX raises, removes or rejects the cap"
OCTOPUS_COUNCIL_CHAIR_FALLBACK_MAX=3 run_fallback; three="$CALLS"
OCTOPUS_COUNCIL_CHAIR_FALLBACK_MAX=0 run_fallback; zero="$CALLS"
OCTOPUS_COUNCIL_CHAIR_FALLBACK_MAX=9 run_fallback; all="$CALLS"
OCTOPUS_COUNCIL_CHAIR_FALLBACK_MAX=lots run_fallback; bad="$CALLS"
if [[ "$three" == 3 && "$zero" == 0 && "$all" == 5 && "$bad" == 1 ]]; then
    test_pass
else
    test_fail "max3=$three max0=$zero max9=$all invalid=$bad"
fi
OCTOPUS_COUNCIL_CHAIR_FALLBACK_MAX=0 run_fallback
assert_summary_attempts 0

test_case "with new attempts disabled, an accepted advice response is still reused"
d="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/chair-reuse.XXXXXX")"; mkdir -p "$d/responses"
printf 'review\n' > "$d/responses/03-code-reviewer.md"
COUNCIL_RUN_DIR="$d"
COUNCIL_SEAT_RECORDS_JSON='[{"persona":"code-reviewer","status":"responded"}]'
COUNCIL_CHAIR_RESPONSE_RECEIVED="false" COUNCIL_CHAIR_FALLBACK_USED="false"
COUNCIL_CHAIR_FALLBACK_PERSONA="" COUNCIL_CHAIR_FALLBACK_ATTEMPTS=0
council_contribution_record_json() { printf '{"validation_result":"valid-grounded","grounding":{}}\n'; }
council_response_is_substantive() { return 0; }
council_pick_provider() { printf 'claude'; }
council_provider_is_available() { return 0; }
council_dispatch_member_detached() { printf 'dispatched\n' >> "$COUNCIL_RUN_DIR/dispatched"; return 1; }
rc=0; OCTOPUS_COUNCIL_CHAIR_FALLBACK_MAX=0 council_run_chair_fallback sha256:test 2>/dev/null || rc=$?
reused="$COUNCIL_CHAIR_FALLBACK_PERSONA"
unset -f council_contribution_record_json council_response_is_substantive council_pick_provider \
    council_provider_is_available council_dispatch_member_detached
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/council.sh"
if [[ "$rc" == 0 && "$reused" == code-reviewer && ! -e "$d/dispatched" ]]; then
    test_pass
else
    test_fail "rc=$rc persona=$reused dispatched=$(cat "$d/dispatched" 2>/dev/null)"
fi

test_case "council_reset_defaults clears the attempt count"
COUNCIL_CHAIR_FALLBACK_ATTEMPTS=4
council_reset_defaults >/dev/null 2>&1 || true
if [[ "$COUNCIL_CHAIR_FALLBACK_ATTEMPTS" == 0 ]]; then test_pass; else test_fail "attempts=$COUNCIL_CHAIR_FALLBACK_ATTEMPTS"; fi

test_summary
