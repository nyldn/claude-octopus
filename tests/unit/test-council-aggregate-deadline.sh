#!/usr/bin/env bash
# Aggregate wall-clock deadline + per-run provenance stamp (sail-cruisey #2918/#2859).
#
# The council seat loop is serial: N seats each allowed the per-seat cap can sum
# past a parent tool-call/orchestrator timeout and be SIGTERM-reaped mid-run with no
# summary.json. These tests pin the runner's self-bounding behaviour: it stops
# dispatching further seats when the aggregate cap is reached and finalizes a
# REPORTED partial, clamps each seat's cap to the remaining budget, and stamps every
# run with its session id + artifact digest so a client can reject a foreign run
# served from a shared/collided councils pool.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

# A stray OCTOPUS_COUNCIL_DEFAULT_PROVIDERS policy in the caller's env makes
# council_run bail during arg validation; the deadline behaviour is independent of
# it, so neutralise it for a deterministic run.
unset OCTOPUS_COUNCIL_DEFAULT_PROVIDERS \
    OCTOPUS_COUNCIL_DEADLINE_SECS \
    OCTOPUS_COUNCIL_DEADLINE_SEAT_FLOOR_SECS \
    OCTOPUS_COUNCIL_REAP_GRACE_SECS 2>/dev/null || true

test_suite "Council aggregate deadline"

# ---- deadline resolution ---------------------------------------------------

test_deadline_secs_default() {
    test_case "council_run_deadline_secs defaults to 1500 and honours explicit / disabled"
    local d0 d1 d2
    d0="$(council_run_deadline_secs)"
    d1="$(OCTOPUS_COUNCIL_DEADLINE_SECS=0 council_run_deadline_secs)"
    d2="$(OCTOPUS_COUNCIL_DEADLINE_SECS=600 council_run_deadline_secs)"
    if [[ "$d0" == "1500" && "$d1" == "0" && "$d2" == "600" ]]; then
        test_pass
    else
        test_fail "expected 1500/0/600, got $d0/$d1/$d2"
    fi
}

test_deadline_secs_rejects_junk() {
    test_case "council_run_deadline_secs ignores non-numeric / negative overrides"
    local a b
    a="$(OCTOPUS_COUNCIL_DEADLINE_SECS=abc council_run_deadline_secs)"
    b="$(OCTOPUS_COUNCIL_DEADLINE_SECS=-5 council_run_deadline_secs)"
    if [[ "$a" == "1500" && "$b" == "1500" ]]; then
        test_pass
    else
        test_fail "expected fallback 1500 for junk, got $a/$b"
    fi
}

# ---- remaining / exceeded --------------------------------------------------

test_deadline_remaining_sentinel_when_inactive() {
    test_case "council_deadline_remaining is unbounded when disabled or unanchored"
    local unanchored disabled
    ( unset COUNCIL_RUN_START_EPOCH; OCTOPUS_COUNCIL_DEADLINE_SECS=1500 council_deadline_remaining ) >/dev/null
    unanchored="$( unset COUNCIL_RUN_START_EPOCH; OCTOPUS_COUNCIL_DEADLINE_SECS=1500 council_deadline_remaining )"
    disabled="$( COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 10 )) OCTOPUS_COUNCIL_DEADLINE_SECS=0 council_deadline_remaining )"
    if [[ "$unanchored" == "2147483647" && "$disabled" == "2147483647" ]]; then
        test_pass
    else
        test_fail "expected sentinel for unanchored/disabled, got $unanchored/$disabled"
    fi
}

test_deadline_exceeded_logic() {
    test_case "council_deadline_exceeded true past the cap, false when within / disabled / unanchored"
    local past within disabled unanchored
    past="no"; within="no"; disabled="no"; unanchored="no"
    COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 2000 )) OCTOPUS_COUNCIL_DEADLINE_SECS=1500 council_deadline_exceeded && past="yes"
    COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 10 ))   OCTOPUS_COUNCIL_DEADLINE_SECS=1500 council_deadline_exceeded && within="yes"
    COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 2000 )) OCTOPUS_COUNCIL_DEADLINE_SECS=0    council_deadline_exceeded && disabled="yes"
    ( unset COUNCIL_RUN_START_EPOCH; OCTOPUS_COUNCIL_DEADLINE_SECS=1500 council_deadline_exceeded ) && unanchored="yes"
    if [[ "$past" == "yes" && "$within" == "no" && "$disabled" == "no" && "$unanchored" == "no" ]]; then
        test_pass
    else
        test_fail "past=$past within=$within disabled=$disabled unanchored=$unanchored (want yes/no/no/no)"
    fi
}

# ---- per-seat clamp --------------------------------------------------------

test_seat_timeout_clamped_to_budget() {
    test_case "council_seat_timeout clamps to remaining budget minus reaper grace, floored"
    local clamped floored unbounded
    # Neutralise any provider/global timeout overrides so the built-in 120s default
    # is the pre-clamp value. Reaper grace is 15s (default), floor 30s.
    (
        unset OCTOPUS_COUNCIL_TIMEOUT_CLAUDE COUNCIL_SEAT_TIMEOUT OCTOPUS_COUNCIL_AGENT_TIMEOUT COUNCIL_SEAT_TIMEOUT_CEILING OCTOPUS_COUNCIL_REAP_GRACE_SECS OCTOPUS_COUNCIL_DEADLINE_SEAT_FLOOR_SECS 2>/dev/null || true
        OCTOPUS_COUNCIL_DEADLINE_SECS=1500
        # ~100s remain -> budget 100-15=85, between floor and the 120 default -> ~85.
        COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 1400 )); printf '%s\n' "$(council_seat_timeout claude)" > "$TEST_TMP_DIR/clamped"
        # ~40s remain -> budget 40-15=25, below the 30s floor -> floored to 30.
        COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 1460 )); printf '%s\n' "$(council_seat_timeout claude)" > "$TEST_TMP_DIR/floored"
        # Unanchored -> no clamp -> the 120 default.
        unset COUNCIL_RUN_START_EPOCH; printf '%s\n' "$(council_seat_timeout claude)" > "$TEST_TMP_DIR/unbounded"
    )
    clamped="$(cat "$TEST_TMP_DIR/clamped")"
    floored="$(cat "$TEST_TMP_DIR/floored")"
    unbounded="$(cat "$TEST_TMP_DIR/unbounded")"
    # clamp reserves the 15s grace: seat budget + grace must stay under what remained.
    if (( clamped >= 75 && clamped <= 90 )) && [[ "$floored" == "30" ]] && [[ "$unbounded" == "120" ]]; then
        test_pass
    else
        test_fail "clamped=$clamped (want ~85) floored=$floored (want 30) unbounded=$unbounded (want 120)"
    fi
}

# ---- provenance stamp (end-to-end fixture) ---------------------------------

test_summary_carries_provenance() {
    test_case "summary.json + run-status.json carry session_id, artifact_digest, deadline"
    local tmp rd
    tmp="$(mktemp -d "$TEST_TMP_DIR/prov.XXXXXX")"
    # Pin a known session id so the assertion is deterministic on a headless
    # runner (no Claude Code session is present in CI, where the runtime would
    # otherwise resolve none and stamp session_id:null — the honest value).
    OCTOPUS_HOST=claude CLAUDE_CODE_SESSION_ID="test-council-session-xyz" OCTOPUS_COUNCIL_FIXTURE=full-success \
        council_run --goal review --depth standard --output-dir "$tmp" "Review the auth refactor plan" >/dev/null 2>&1 || true
    rd="$(find "$tmp" -maxdepth 1 -type d -name '2*' | head -1)"
    if [[ -z "$rd" || ! -f "$rd/summary.json" ]]; then
        test_fail "no summary.json written"
        return 1
    fi
    if jq -e '.session_id == "test-council-session-xyz"
              and .artifact_digest != null
              and .deadline.cap_secs == 1500
              and .deadline.hit == false' "$rd/summary.json" >/dev/null \
       && jq -e '.session_id == "test-council-session-xyz"' "$rd/run-status.json" >/dev/null; then
        test_pass
    else
        test_fail "summary/run-status missing provenance: $(jq -c '{session_id,artifact_digest,deadline}' "$rd/summary.json")"
    fi
}

# ---- deadline hit -> reported partial, never a silent hang -----------------

test_deadline_hit_finalizes_reported_partial() {
    test_case "an exhausted budget stops dispatch and finalizes a reported partial (no hang)"
    local tmp rd status hit skipped
    tmp="$(mktemp -d "$TEST_TMP_DIR/dlhit.XXXXXX")"
    # cap=1s is already spent by the time the loop runs, so every advice seat is
    # skipped-for-deadline; the run must still write summary.json and report the
    # partial rather than dispatch seats or hang.
    OCTOPUS_COUNCIL_FIXTURE=full-success OCTOPUS_COUNCIL_DEADLINE_SECS=1 \
        council_run --goal review --depth standard --output-dir "$tmp" "Review the auth refactor plan" >/dev/null 2>&1 || true
    rd="$(find "$tmp" -maxdepth 1 -type d -name '2*' | head -1)"
    if [[ -z "$rd" || ! -f "$rd/summary.json" ]]; then
        test_fail "deadline hit produced no summary.json (silent hang)"
        return 1
    fi
    status="$(jq -r '.status' "$rd/summary.json")"
    hit="$(jq -r '.deadline.hit' "$rd/summary.json")"
    skipped="$(jq -r '.deadline.seats_skipped' "$rd/summary.json")"
    # No seat, chair fallback, or later phase may dispatch once the budget is spent:
    # seats_dispatched must be 0 and no seat may reach "responded".
    if [[ "$status" == "partial" && "$hit" == "true" ]] && (( skipped >= 1 )) \
       && jq -e '.deadline.seats_dispatched == 0' "$rd/summary.json" >/dev/null \
       && jq -e '[.seats[] | select(.status == "skipped-deadline")] | length >= 1' "$rd/summary.json" >/dev/null \
       && jq -e '[.seats[] | select(.status == "responded")] | length == 0' "$rd/summary.json" >/dev/null \
       && jq -e '.quorum.met == false' "$rd/summary.json" >/dev/null; then
        test_pass
    else
        test_fail "status=$status hit=$hit skipped=$skipped dispatched=$(jq -r '.deadline.seats_dispatched' "$rd/summary.json") responded=$(jq -r '[.seats[]|select(.status==\"responded\")]|length' "$rd/summary.json") (want partial/true, dispatched 0, no responded seats, met=false)"
    fi
}

test_synthesis_timeout_clamped_to_budget() {
    test_case "council_synthesis_timeout honors its override but clamps to the deadline budget"
    local over clamped
    # No run anchored: the large override passes through unclamped.
    over="$( unset COUNCIL_RUN_START_EPOCH OCTOPUS_COUNCIL_DEADLINE_SECS 2>/dev/null || true
             OCTOPUS_COUNCIL_SYNTHESIS_TIMEOUT=900 council_synthesis_timeout claude )"
    # Anchored with ~100s left: the 900s override is clamped to budget (100-15 grace=85).
    clamped="$( OCTOPUS_COUNCIL_DEADLINE_SECS=1500 COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 1400 )) \
                OCTOPUS_COUNCIL_SYNTHESIS_TIMEOUT=900 council_synthesis_timeout claude )"
    if [[ "$over" == "900" ]] && (( clamped >= 75 && clamped <= 90 )); then
        test_pass
    else
        test_fail "over=$over (want 900) clamped=$clamped (want ~85 = 100-15 grace)"
    fi
}

source "$PROJECT_ROOT/scripts/lib/council.sh"

test_deadline_secs_default
test_deadline_secs_rejects_junk
test_deadline_remaining_sentinel_when_inactive
test_deadline_exceeded_logic
test_seat_timeout_clamped_to_budget
test_synthesis_timeout_clamped_to_budget
test_summary_carries_provenance
test_deadline_hit_finalizes_reported_partial

test_summary
