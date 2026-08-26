#!/usr/bin/env bash
# Contract tests for the v10 schema-versioned seat lifecycle.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "v10 run contract"

export WORKSPACE_DIR="$TEST_TMP_DIR/run-contract-workspace"
export OCTOPUS_RUN_ID="run-contract-test"
mkdir -p "$WORKSPACE_DIR"

# This source is intentionally the RED boundary for the first implementation
# slice. The suite must fail until the contract library exists.
if [[ ! -f "$PROJECT_ROOT/scripts/lib/run-contract.sh" ]]; then
    test_case "run-contract library exists"
    test_fail "missing scripts/lib/run-contract.sh"
    test_summary
fi
source "$PROJECT_ROOT/scripts/lib/run-contract.sh"

test_case "test harness fallback never writes contract state under HOME"
fallback_path="$(unset WORKSPACE_DIR; octo_run_contract_ledger_path)"
if [[ "$fallback_path" == "$TEST_TMP_DIR/"* ]]; then
    test_pass
else
    test_fail "expected TEST_TMP_DIR fallback, got $fallback_path"
fi

ledger="$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/seats.jsonl"
snapshot="$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/seats.json"
valid_output="$TEST_TMP_DIR/valid-output.md"
empty_output="$TEST_TMP_DIR/empty-output.md"
placeholder_output="$TEST_TMP_DIR/placeholder-output.md"
printf '%s\n' 'Substantive provider result.' > "$valid_output"
: > "$empty_output"
printf '%s\n' 'Provider available' > "$placeholder_output"

record_pass() {
    test_case "$1"
    test_pass
}

fail_case() {
    local name="$1" message="$2"
    test_case "$name"
    test_fail "$message"
}

expect_transition_ok() {
    local name="$1"
    shift
    if run_contract_transition "$@"; then
        record_pass "$name"
    else
        fail_case "$name" "transition unexpectedly failed: $*"
    fi
}

expect_transition_rejected_without_mutation() {
    local name="$1"
    shift
    local before after
    before="$(cksum "$ledger" 2>/dev/null || printf '%s' absent)"
    if run_contract_transition "$@" >/dev/null 2>&1; then
        fail_case "$name" "transition unexpectedly succeeded: $*"
        return
    fi
    after="$(cksum "$ledger" 2>/dev/null || printf '%s' absent)"
    if [[ "$before" == "$after" ]]; then
        record_pass "$name"
    else
        fail_case "$name" "rejected transition mutated the ledger"
    fi
}

seed_to_state() {
    local seat="$1" target="$2"
    run_contract_transition "$seat" planned >/dev/null
    if [[ "$target" == planned ]]; then return 0; fi
    run_contract_transition "$seat" starting >/dev/null
    if [[ "$target" == starting ]]; then return 0; fi
    run_contract_transition "$seat" authenticated >/dev/null
    if [[ "$target" == authenticated ]]; then return 0; fi
    run_contract_transition "$seat" running >/dev/null
    if [[ "$target" == running ]]; then return 0; fi
    run_contract_transition "$seat" output_received output_file="$valid_output" >/dev/null
    if [[ "$target" == output_received ]]; then return 0; fi
    run_contract_transition "$seat" validated contribution=eligible >/dev/null
}

expect_transition_ok "planned accepts requested identity" \
    seat-1 planned \
    requested_provider=codex requested_model=gpt-5.6-luna requested_effort=low \
    phase=probe role=reviewer isolation=read-only attempt_id=attempt-1
expect_transition_ok "starting accepts resolved identity" \
    seat-1 starting \
    resolved_provider=codex resolved_model=gpt-5.6-luna resolved_effort=low
expect_transition_ok "authenticated follows starting" seat-1 authenticated
expect_transition_ok "running follows authenticated" seat-1 running
expect_transition_ok "output_received requires usable artifact" \
    seat-1 output_received output_file="$valid_output" stderr_file="$TEST_TMP_DIR/stderr.log"
expect_transition_ok "validated marks eligible contribution" \
    seat-1 validated contribution=eligible
expect_transition_ok "contributed terminates the happy path" \
    seat-1 contributed contribution=eligible status=ok

test_case "ledger records complete valid schema"
if [[ "$(wc -l < "$ledger" | tr -d ' ')" == 7 ]] && \
   jq -e -s '
     length == 7 and
     all(.[];
       .schema_version == "10.0" and
       .run_id == "run-contract-test" and
       .seat_id == "seat-1" and
       (.transition | type == "string") and
       (.status | type == "string") and
       (.contribution | type == "string") and
       (.requested | type == "object") and
       (.resolved | type == "object") and
       (.execution | type == "object") and
       (.metrics | type == "object") and
       (.artifacts | type == "object") and
       (.reason | type == "string") and
       (.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))) and
     .[0].requested == {provider:"codex",model:"gpt-5.6-luna",effort:"low"} and
     .[0].execution.phase == "probe" and
     .[0].execution.role == "reviewer" and
     .[0].execution.isolation == "read-only" and
     .[0].attempt_id == "attempt-1" and
     .[1].resolved == {provider:"codex",model:"gpt-5.6-luna",effort:"low"} and
     .[4].artifacts.output == $output and
     .[6].transition == "contributed" and
     .[6].contribution == "eligible"
   ' --arg output "$valid_output" "$ledger" >/dev/null; then
    test_pass
else
    test_fail "ledger did not retain the complete v10 record contract"
fi

test_case "query helpers return persisted truth"
latest="$(run_contract_latest_transition seat-1)"
snapshot_json="$(run_contract_snapshot)"
if [[ "$latest" == contributed ]] && \
   run_contract_output_usable seat-1 && \
   run_contract_contribution_eligible seat-1 && \
   [[ -s "$snapshot" ]] && \
   jq -e '
     .schema_version == "10.0" and
     .run_id == "run-contract-test" and
     (.seats | length == 1) and
     .seats[0].seat_id == "seat-1" and
     .seats[0].transition == "contributed"
   ' <<< "$snapshot_json" >/dev/null && \
   cmp -s <(printf '%s\n' "$snapshot_json") "$snapshot"; then
    test_pass
else
    test_fail "query helpers or atomic snapshot did not expose persisted truth"
fi

expect_transition_rejected_without_mutation \
    "initial contributed transition is rejected" \
    seat-2 contributed contribution=eligible

seed_to_state seat-3 running
expect_transition_rejected_without_mutation \
    "empty output is rejected before output_received" \
    seat-3 output_received output_file="$empty_output"

seed_to_state seat-placeholder running
expect_transition_rejected_without_mutation \
    "placeholder output is rejected before output_received" \
    seat-placeholder output_received output_file="$placeholder_output"

run_contract_transition seat-4 planned >/dev/null
expect_transition_rejected_without_mutation \
    "planned cannot jump directly to running" \
    seat-4 running

# Deterministically hold an older snapshot immediately before publication while
# a newer transition appends and snapshots. The final snapshot must never move
# backward to the older view.
snapshot_gate="$TEST_TMP_DIR/snapshot-publish-entered"
snapshot_release="$TEST_TMP_DIR/snapshot-publish-release"
mv() {
    if [[ "${OCTO_DELAY_SNAPSHOT_PUBLISH:-false}" == true && "${1:-}" == *seats.json.tmp.* ]]; then
        : > "$snapshot_gate"
        while [[ ! -f "$snapshot_release" ]]; do
            sleep 0.01
        done
    fi
    command mv "$@"
}

OCTO_DELAY_SNAPSHOT_PUBLISH=true run_contract_snapshot >/dev/null &
stale_snapshot_pid=$!
for _snapshot_wait in $(seq 1 100); do
    [[ -f "$snapshot_gate" ]] && break
    sleep 0.01
done

run_contract_transition race-seat planned >/dev/null &
new_transition_pid=$!
sleep 0.1
: > "$snapshot_release"
wait "$stale_snapshot_pid"
wait "$new_transition_pid"
unset -f mv

test_case "concurrent snapshot publication cannot regress durable state"
if jq -e '.seats | any(.seat_id == "race-seat" and .transition == "planned")' "$snapshot" >/dev/null; then
    test_pass
else
    test_fail "an older concurrent snapshot overwrote the newer seat state"
fi

terminal_edges='planned skipped
planned failed
starting failed
starting cancelled
authenticated failed
authenticated cancelled
running degraded
running skipped
running failed
running timeout
running cancelled
output_received degraded
output_received failed
output_received cancelled
validated degraded
validated failed
validated cancelled'

edge_index=0
while read -r from terminal; do
    [[ -n "$from" ]] || continue
    edge_index=$((edge_index + 1))
    edge_seat="edge-$edge_index"
    seed_to_state "$edge_seat" "$from"
    args=("$edge_seat" "$terminal" "reason=fixture-$terminal")
    if [[ "$terminal" == degraded ]]; then
        args+=("output_file=$valid_output" "contribution=eligible-with-warning")
    fi
    expect_transition_ok "$from may terminate as $terminal" "${args[@]}"
    expect_transition_rejected_without_mutation \
        "$terminal is absorbing from $from" \
        "$edge_seat" "$terminal" "reason=duplicate"
done <<< "$terminal_edges"

test_summary
