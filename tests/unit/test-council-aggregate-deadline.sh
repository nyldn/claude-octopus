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
    if [[ "$status" == "partial" && "$hit" == "true" && "$skipped" =~ ^[0-9]+$ ]] && (( skipped >= 1 )) \
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

test_fallback_rechecks_deadline() {
    test_case "chair fallback stops after an attempt exhausts the budget"
    local result
    result="$(
        council_reset_defaults
        COUNCIL_RUN_DIR="$TEST_TMP_DIR/fallback-budget"
        mkdir -p "$COUNCIL_RUN_DIR/responses"
        OCTOPUS_COUNCIL_DEADLINE_SECS=60
        COUNCIL_RUN_START_EPOCH="$(date +%s)"
        attempts=0
        council_synthesis_capable_persona() { return 0; }
        council_persona_should_fail() { return 1; }
        council_pick_provider() { printf 'claude'; }
        council_provider_is_available() { return 0; }
        council_roster_entry_json() { printf '{"persona":"%s","provider":"claude"}' "$1"; }
        council_dispatch_member_detached() {
            attempts=$((attempts + 1))
            COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 120 ))
            return 1
        }
        council_run_chair_fallback known-digest || true
        printf '%s:%s' "$attempts" "$COUNCIL_DEADLINE_HIT"
    )"
    if [[ "$result" == "1:true" ]]; then test_pass; else test_fail "attempts:deadline=$result"; fi
}

test_fallback_reuses_completed_response_after_deadline() {
    test_case "chair fallback can reuse accepted advice after the deadline"
    local result
    result="$(
        council_reset_defaults
        COUNCIL_RUN_DIR="$TEST_TMP_DIR/fallback-reuse"
        mkdir -p "$COUNCIL_RUN_DIR/responses"
        printf 'Reviewed scripts/lib/council.sh:1.\nVERDICT: APPROVE\n' > "$COUNCIL_RUN_DIR/responses/00-strategy-analyst.md"
        COUNCIL_SEAT_RECORDS_JSON='[{"persona":"strategy-analyst","status":"responded"}]'
        OCTOPUS_COUNCIL_DEADLINE_SECS=1
        COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 120 ))
        council_synthesis_capable_persona() { return 0; }
        council_persona_should_fail() { return 1; }
        council_response_is_substantive() { return 0; }
        council_dispatch_member_detached() { printf 'unexpected dispatch'; return 1; }
        council_run_chair_fallback known-digest || true
        printf '%s:%s' "$COUNCIL_CHAIR_RESPONSE_RECEIVED" "$COUNCIL_CHAIR_FALLBACK_PERSONA"
    )"
    if [[ "$result" == "true:strategy-analyst" ]]; then test_pass; else test_fail "reuse=$result"; fi
}

test_later_phases_bound_preparation_and_cancel_children() {
    test_case "critique, revision and synthesis bound preparation and cancel the full tree"
    local phase
    for phase in cross-critique revision-after-critique chair-synthesis; do
        if ! (
            council_reset_defaults
            COUNCIL_RUN_DIR="$TEST_TMP_DIR/preparation-$phase"
            mkdir -p "$COUNCIL_RUN_DIR/responses" "$COUNCIL_RUN_DIR/critiques" "$COUNCIL_RUN_DIR/revisions"
            COUNCIL_ROSTER_JSON='[{"persona":"strategy-analyst","provider":"codex","agent_spec":"codex","seat":"chair"}]'
            COUNCIL_DEPTH=deep
            # Keep the coarse aggregate clock at its start until preparation
            # launches. The real one-second watchdog and process-tree cleanup
            # still run; crossing a wall-clock second before launch belongs to
            # the separate expired-phase test below.
            COUNCIL_RUN_START_EPOCH=1000000
            date() {
                if [[ "${1:-}" == +%s ]]; then
                    if [[ -s "$COUNCIL_RUN_DIR/child.pid" ]]; then
                        printf '%s\n' "$((COUNCIL_RUN_START_EPOCH + 1))"
                    else
                        printf '%s\n' "$COUNCIL_RUN_START_EPOCH"
                    fi
                else
                    command date "$@"
                fi
            }
            OCTOPUS_COUNCIL_DEADLINE_SECS=2
            OCTOPUS_COUNCIL_DEADLINE_SEAT_FLOOR_SECS=1
            OCTOPUS_COUNCIL_REAP_GRACE_SECS=0
            OCTOPUS_COUNCIL_TIMEOUT_CODEX=1
            OCTOPUS_COUNCIL_SYNTHESIS_TIMEOUT=1
            unset OCTOPUS_COUNCIL_DETACH
            council_prompt_for_member() {
                (sleep 3; touch "$COUNCIL_RUN_DIR/child-finished") &
                printf '%s\n' "$!" > "$COUNCIL_RUN_DIR/child.pid"
                sh -c 'echo "$PPID"' > "$COUNCIL_RUN_DIR/preparation.pid"
                sleep 3
                printf 'prepared prompt'
            }
            council_live_response() { printf '# late provider answer\n'; }
            start="$(python3 -c 'import time; print(time.monotonic())')"
            case "$phase" in
                cross-critique) council_run_critique_phase ;;
                revision-after-critique) council_run_revision_phase ;;
                chair-synthesis) council_write_synthesis || true ;;
            esac
            elapsed="$(python3 -c 'import sys,time; print(time.monotonic()-float(sys.argv[1]))' "$start")"
            python3 -c 'import sys; assert float(sys.argv[1]) < 2.5' "$elapsed" || exit 1
            [[ "$COUNCIL_LAST_DISPATCH_TIMEOUT_PROVENANCE" == internal-watchdog && "$COUNCIL_DEADLINE_HIT" == true ]] || exit 1
            sleep 3.2
            [[ ! -e "$COUNCIL_RUN_DIR/child-finished" ]] || exit 1
            [[ -s "$COUNCIL_RUN_DIR/child.pid" && -s "$COUNCIL_RUN_DIR/preparation.pid" ]] || exit 1
            ! kill -0 "$(cat "$COUNCIL_RUN_DIR/child.pid")" 2>/dev/null || exit 1
            ! kill -0 "$(cat "$COUNCIL_RUN_DIR/preparation.pid")" 2>/dev/null || exit 1
            ! grep -rq 'late provider answer' "$COUNCIL_RUN_DIR" || exit 1
            [[ -z "$(find "$COUNCIL_RUN_DIR" -name '*.partial' -o -name '*.done' -o -name '*.done.tmp')" ]] || exit 1
        ); then
            test_fail "$phase exceeded its budget or left a child/late publication"
            return
        fi
    done
    test_pass
}

test_later_phases_skip_before_preparation_when_expired() {
    test_case "expired critique and revision phases skip preparation without watchdog provenance"
    local phase
    for phase in cross-critique revision-after-critique; do
        if ! (
            council_reset_defaults
            COUNCIL_RUN_DIR="$TEST_TMP_DIR/expired-$phase"
            mkdir -p "$COUNCIL_RUN_DIR/responses" "$COUNCIL_RUN_DIR/critiques" "$COUNCIL_RUN_DIR/revisions"
            COUNCIL_ROSTER_JSON='[{"persona":"strategy-analyst","provider":"codex","agent_spec":"codex","seat":"chair"}]'
            COUNCIL_DEPTH=deep
            OCTOPUS_COUNCIL_DEADLINE_SECS=2
            OCTOPUS_COUNCIL_DEADLINE_SEAT_FLOOR_SECS=1
            OCTOPUS_COUNCIL_REAP_GRACE_SECS=0
            COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 1 ))
            council_prompt_for_member() { touch "$COUNCIL_RUN_DIR/preparation-started"; }
            council_live_response() { touch "$COUNCIL_RUN_DIR/provider-started"; }
            case "$phase" in
                cross-critique) council_run_critique_phase ;;
                revision-after-critique) council_run_revision_phase ;;
            esac
            [[ "$COUNCIL_DEADLINE_HIT" == true && -z "$COUNCIL_LAST_DISPATCH_TIMEOUT_PROVENANCE" ]] &&
            [[ ! -e "$COUNCIL_RUN_DIR/preparation-started" && ! -e "$COUNCIL_RUN_DIR/provider-started" ]]
        ); then
            test_fail "$phase dispatched after its aggregate budget was spent"
            return
        fi
    done
    test_pass
}

test_synthesis_watchdog_uses_chair_budget() {
    test_case "the synthesis watchdog uses its chair budget rather than the advice budget"
    if (
        council_reset_defaults
        COUNCIL_RUN_DIR="$TEST_TMP_DIR/synthesis-budget"
        mkdir -p "$COUNCIL_RUN_DIR"
        COUNCIL_ROSTER_JSON='[{"persona":"strategy-analyst","provider":"codex","agent_spec":"codex","seat":"chair"}]'
        COUNCIL_RUN_START_EPOCH="$(date +%s)"
        OCTOPUS_COUNCIL_DEADLINE_SECS=10
        OCTOPUS_COUNCIL_DEADLINE_SEAT_FLOOR_SECS=1
        OCTOPUS_COUNCIL_REAP_GRACE_SECS=0
        OCTOPUS_COUNCIL_TIMEOUT_CODEX=1
        OCTOPUS_COUNCIL_SYNTHESIS_TIMEOUT=3
        unset OCTOPUS_COUNCIL_DETACH
        council_prompt_for_member() { sleep 1.3; printf 'prepared prompt'; }
        council_live_response() { printf '# completed chair answer\n'; }
        council_write_synthesis && grep -q 'completed chair answer' "$COUNCIL_RUN_DIR/synthesis.md"
    ); then test_pass; else test_fail "chair synthesis was stopped at the shorter advice timeout"; fi
}

test_synthesis_expiry_publishes_reported_partial() {
    test_case "aggregate expiry during synthesis reports a partial with deadline provenance"
    if (
        pool="$TEST_TMP_DIR/synthesis-partial"
        OCTOPUS_COUNCIL_DEADLINE_SECS=5
        OCTOPUS_COUNCIL_DEADLINE_SEAT_FLOOR_SECS=1
        OCTOPUS_COUNCIL_REAP_GRACE_SECS=0
        OCTOPUS_COUNCIL_AGENT_TIMEOUT=1
        OCTOPUS_COUNCIL_SYNTHESIS_TIMEOUT=1
        unset OCTOPUS_COUNCIL_DETACH
        council_run_advice_phase() {
            COUNCIL_FIXTURE=""
            COUNCIL_QUORUM_MET=true
            COUNCIL_CHAIR_RESPONSE_RECEIVED=true
            COUNCIL_CHAIR_HOST_NATIVE=false
            COUNCIL_RUN_START_EPOCH=$(( $(date +%s) - 3 ))
        }
        council_prompt_for_member() { sleep 3; printf 'prepared prompt'; }
        council_live_response() { printf '# late provider answer\n'; }
        rc=0
        OCTOPUS_COUNCIL_FIXTURE=full-success \
            OCTOPUS_COUNCIL_PROVIDER_FIXTURE='claude:available,codex:available,agy:available' \
            council_run --goal review --depth quick --benchmark off --output-dir "$pool" 'Review fixture' \
                > "$TEST_TMP_DIR/synthesis-partial.out" 2>&1 || rc=$?
        [[ "$rc" -ne 0 ]] && jq -e '.status == "partial" and .deadline.hit == true' "$COUNCIL_RUN_DIR/summary.json" >/dev/null \
            && jq -e '.state == "finished" and .status == "partial"' "$COUNCIL_RUN_DIR/run-status.json" >/dev/null
    ); then test_pass; else test_fail "synthesis expiry was not reported as an aggregate-deadline partial"; fi
}

test_deadline_secs_default
test_deadline_secs_rejects_junk
test_deadline_remaining_sentinel_when_inactive
test_deadline_exceeded_logic
test_seat_timeout_clamped_to_budget
test_synthesis_timeout_clamped_to_budget
test_summary_carries_provenance
test_deadline_hit_finalizes_reported_partial
test_fallback_rechecks_deadline
test_fallback_reuses_completed_response_after_deadline
test_later_phases_bound_preparation_and_cancel_children
test_later_phases_skip_before_preparation_when_expired
test_synthesis_watchdog_uses_chair_budget
test_synthesis_expiry_publishes_reported_partial

test_summary
