#!/usr/bin/env bash
# Manifest publication must not depend on how large a session's seat ledger has
# grown. The writer used to hand the whole seat projection to jq as one --argjson
# argv string, which Linux caps at MAX_ARG_STRLEN (128 KiB); past that every
# transition rolled back and no seat could be planned (#1111).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "run contract ledger size"

source "$PROJECT_ROOT/scripts/lib/events.sh"
source "$PROJECT_ROOT/scripts/lib/run-contract.sh"

export WORKSPACE_DIR="$TEST_TMP_DIR/ledger-size-workspace"
export OCTOPUS_RUN_ID="ledger-size"
mkdir -p "$WORKSPACE_DIR"
run_dir="$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID"
manifest="$run_dir/run.json"

# One argv string is capped at 131072 bytes on Linux. Twenty seats whose reason
# is 4 KiB each put the projection well past that: the reason appears in the
# seat record and again in its timeline entry.
arg_strlen_cap=131072
seat_count=20
pad="$(printf 'x%.0s' $(seq 1 4096))"

test_case "seats keep planning after the projection outgrows one argv string"
planned=0
for i in $(seq 1 "$seat_count"); do
    run_contract_transition "seat-$i" planned requested_provider=codex \
        requested_model=fixture-model phase=review role=reviewer "reason=$pad" || break
    planned=$i
done
if [[ "$planned" -eq "$seat_count" ]]; then
    test_pass
else
    test_fail "transition failed at seat-$((planned + 1)) of $seat_count"
fi

test_case "the fixture really exceeds the per-argument cap"
seats_bytes="$(jq -c '.seats' "$manifest" 2>/dev/null | wc -c | tr -d ' ')"
if [[ "${seats_bytes:-0}" -gt "$arg_strlen_cap" ]]; then
    test_pass
else
    test_fail "seat projection is only ${seats_bytes:-0} bytes, so the fixture proves nothing"
fi

test_case "manifest, compat snapshot and latest pointer describe every seat"
if jq -e --argjson n "$seat_count" '
      .schema_version == "10.0" and .run_id == "ledger-size" and
      (.seats | length == $n) and .summary.total_seats == $n and
      .summary.running == $n and .phases.review.total == $n and
      (.seats[] | .transition == "planned" and .reason != "")
    ' "$manifest" >/dev/null 2>&1 &&
   cmp -s "$manifest" "$run_dir/seats.json" &&
   [[ "$(readlink "$WORKSPACE_DIR/runs/latest")" == "$run_dir" ]]; then
    test_pass
else
    test_fail "manifest does not reflect all $seat_count seats"
fi

test_case "no recovery marker or rollback backup survives the oversized appends"
if [[ ! -e "$run_dir/seats.jsonl.recovery" ]] &&
   ! ls "$run_dir"/seats.jsonl.rollback.* >/dev/null 2>&1; then
    test_pass
else
    test_fail "recovery artifacts left behind in $run_dir"
fi

test_case "run events still publish alongside the oversized ledger"
if run_contract_record_event fixture.checkpoint note=after-oversize &&
   jq -e --argjson n "$seat_count" '
      (.events | length == 1) and .events[0].event == "fixture.checkpoint" and
      (.seats | length == $n)
    ' "$manifest" >/dev/null 2>&1; then
    test_pass
else
    test_fail "run_contract_record_event failed or the manifest lost the event"
fi

test_case "a terminal transition on the oversized ledger still lands"
if run_contract_transition seat-1 failed reason=fixture-abandoned cleanup_result=no-process &&
   [[ "$(run_contract_latest_transition seat-1)" == failed ]] &&
   jq -e --argjson n "$seat_count" '
      .summary.failed == 1 and .summary.running == ($n - 1) and
      .phases.review.failed == 1
    ' "$manifest" >/dev/null 2>&1; then
    test_pass
else
    test_fail "terminal transition failed on the oversized ledger"
fi

test_summary
