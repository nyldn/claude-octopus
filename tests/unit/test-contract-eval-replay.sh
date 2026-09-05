#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "audit contract replay and fleet scoring"

test_case "every sanitized audit regression reaches its owning local contract"
replay="$("$PROJECT_ROOT/scripts/helpers/replay-contract-evals.sh")"
if jq -e '.total == 9 and .passed == 9 and .failed == 0 and all(.results[]; .matched)' <<< "$replay" >/dev/null; then
    test_pass
else
    test_fail "contract replay failed: $replay"
fi

test_case "fleet scoring rewards validated recall and preserves minority misses"
score_input="$TEST_TMP_DIR/score-input.json"
printf '%s\n' '{
  "schema_version": 1,
  "ground_truth_finding_ids": ["A", "B"],
  "runs": [
    {"strategy":"owner-verifier","latency_ms":1000,"tokens":100,"cost_usd":0.1,
     "findings":[
       {"id":"A","validated":true,"reviewers":["owner"],"included":true},
       {"id":"B","validated":true,"reviewers":["verifier"],"included":false}]},
    {"strategy":"large-council","latency_ms":3000,"tokens":500,"cost_usd":0.8,
     "findings":[
       {"id":"A","validated":true,"reviewers":["seat-1","seat-2"],"included":true},
       {"id":"C","validated":false,"reviewers":["seat-3"],"included":true}]}
  ]
}' > "$score_input"
score="$(python3 "$PROJECT_ROOT/scripts/helpers/score-review-fleet.py" "$score_input")"
if jq -e '
    (.strategies[] | select(.strategy=="owner-verifier") |
      .ground_truth_findings==2 and .unique_validated_findings==2 and
      .surfaced_validated_findings==1 and
      .unresolved_minority_findings==1 and .validated_finding_recall==0.5 and
      .total_tokens==100 and .total_cost_usd==0.1) and
    (.strategies[] | select(.strategy=="large-council") |
      .unique_validated_findings==1 and .surfaced_validated_findings==1 and
      .unresolved_minority_findings==0 and .validated_finding_recall==0.5 and
      .total_tokens==500 and .total_cost_usd==0.8)
  ' <<< "$score" >/dev/null; then
    test_pass
else
    test_fail "evidence-weighted fleet score mismatch: $score"
fi

test_case "invalid scorer input fails closed"
if printf '{"schema_version":1,"ground_truth_finding_ids":[],"runs":[]}' |
   python3 "$PROJECT_ROOT/scripts/helpers/score-review-fleet.py" >/dev/null 2>&1; then
    test_fail "invalid scorer schema was accepted"
else
    test_pass
fi

test_case "fleet scoring treats unavailable numeric metrics as zero"
score_input="$TEST_TMP_DIR/score-null-metrics.json"
printf '%s\n' '{
  "schema_version": 1,
  "ground_truth_finding_ids": ["A"],
  "runs": [
    {"strategy":"partial","latency_ms":null,"tokens":"n/a","cost_usd":null,"findings":[]}
  ]
}' > "$score_input"
if score="$(python3 "$PROJECT_ROOT/scripts/helpers/score-review-fleet.py" "$score_input")" &&
   jq -e '.strategies[0].median_latency_ms == 0 and .strategies[0].total_tokens == 0 and .strategies[0].total_cost_usd == 0' <<< "$score" >/dev/null; then
    test_pass
else
    test_fail "unavailable numeric metrics crashed or changed zero defaults"
fi

test_case "fleet scoring rejects malformed findings without a traceback"
score_input="$TEST_TMP_DIR/score-malformed-findings.json"
printf '%s\n' '{
  "schema_version": 1,
  "ground_truth_finding_ids": ["A"],
  "runs": [
    {"strategy":"partial","findings":{"id":"A","validated":true}}
  ]
}' > "$score_input"
score_error="$TEST_TMP_DIR/score-malformed-findings.err"
if python3 "$PROJECT_ROOT/scripts/helpers/score-review-fleet.py" "$score_input" > /dev/null 2> "$score_error"; then
    test_fail "malformed findings object was accepted"
elif grep -Fq 'Traceback' "$score_error"; then
    test_fail "malformed findings emitted a traceback: $(cat "$score_error")"
else
    test_pass
fi

test_case "fleet scoring rejects malformed reviewers without a traceback"
score_input="$TEST_TMP_DIR/score-malformed-reviewers.json"
printf '%s\n' '{
  "schema_version": 1,
  "ground_truth_finding_ids": ["A"],
  "runs": [
    {"strategy":"partial","findings":[{"id":"A","validated":true,"reviewers":null}]}
  ]
}' > "$score_input"
score_error="$TEST_TMP_DIR/score-malformed-reviewers.err"
if python3 "$PROJECT_ROOT/scripts/helpers/score-review-fleet.py" "$score_input" > /dev/null 2> "$score_error"; then
    test_fail "malformed reviewers value was accepted"
elif grep -Fq 'Traceback' "$score_error"; then
    test_fail "malformed reviewers emitted a traceback: $(cat "$score_error")"
else
    test_pass
fi

test_summary
