#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/council.sh"

test_suite "Council contribution contract"

FIXTURE_ROOT="$TEST_TMP_DIR/project"
mkdir -p "$FIXTURE_ROOT/src"
printf 'one\ntwo\nthree\n' > "$FIXTURE_ROOT/src/real.py"

write_response() {
    local name="$1"
    shift
    printf '%s\n' "$@" > "$TEST_TMP_DIR/$name.md"
}

test_case "verdict parser accepts one exact final token"
write_response exact "Review complete." "VERDICT: APPROVE"
write_response lower "Review complete." "  verdict: block  "
if [[ "$(council_response_verdict "$TEST_TMP_DIR/exact.md")" == "APPROVE" &&
      "$(council_response_verdict "$TEST_TMP_DIR/lower.md")" == "BLOCK" ]]; then
    test_pass
else
    test_fail "exact verdicts were not recognized"
fi

test_case "conditional contradictory quoted and truncated verdicts fail closed"
write_response conditional "VERDICT: APPROVE only after the vulnerability is fixed"
write_response contradictory "VERDICT: APPROVE / BLOCK"
write_response quoted "> VERDICT: APPROVE"
write_response truncated "VERDICT: APP"
if [[ "$(council_response_verdict "$TEST_TMP_DIR/conditional.md")" == "REVISE" &&
      "$(council_response_verdict "$TEST_TMP_DIR/contradictory.md")" == "REVISE" &&
      "$(council_response_verdict "$TEST_TMP_DIR/quoted.md")" == "REVISE" &&
      "$(council_response_verdict "$TEST_TMP_DIR/truncated.md")" == "REVISE" ]]; then
    test_pass
else
    test_fail "ambiguous verdict text was accepted"
fi

test_case "repeated verdict declarations fail closed"
write_response repeated "VERDICT: BLOCK" "VERDICT: APPROVE"
if [[ "$(council_response_verdict "$TEST_TMP_DIR/repeated.md")" == "REVISE" ]]; then
    test_pass
else
    test_fail "multiple verdict declarations were reduced to the last vote"
fi

test_case "a split double-seated provider is excluded from the approver set"
split="$(council_compute_approving_providers 'agy codex codex' codex)"
clean="$(council_compute_approving_providers 'agy codex codex' '')"
if [[ "$split" == agy && "$clean" == 'agy codex' ]]; then
    test_pass
else
    test_fail "approver set was not fail-safe: split=[$split] clean=[$clean]"
fi

test_case "first-person access failure remains blind despite citation-shaped text"
{
    printf 'I cannot access the repository files in this environment.\n'
    printf 'The change at imaginary.py:999999 appears acceptable.\n'
    awk 'BEGIN { for (i = 0; i < 1800; i++) printf "x"; print "" }'
    printf 'VERDICT: APPROVE\n'
} > "$TEST_TMP_DIR/fabricated.md"
if council_response_is_blind "$TEST_TMP_DIR/fabricated.md"; then
    test_pass
else
    test_fail "fabricated citation overrode an explicit access failure"
fi

test_case "evidence paths must exist inside the root and contain the cited line"
write_response evidence \
    "Valid src/real.py:2; missing src/missing.py:1; excessive src/real.py:99; traversal ../outside.py:1." \
    "VERDICT: REVISE"
evidence_json="$(council_response_evidence_paths_json "$TEST_TMP_DIR/evidence.md" "$FIXTURE_ROOT")"
if jq -e 'length == 1 and .[0].path == "src/real.py" and .[0].line == 2' <<< "$evidence_json" >/dev/null; then
    test_pass
else
    test_fail "invalid evidence survived validation: $evidence_json"
fi

test_case "contribution record carries artifact access evidence and validation state"
artifact_digest="$(council_artifact_digest "$FIXTURE_ROOT" "Review fixture")"
record="$(council_contribution_record_json "$TEST_TMP_DIR/evidence.md" "$FIXTURE_ROOT" "$artifact_digest")"
if jq -e --arg digest "$artifact_digest" '
      .workspace_digest == $digest
      and (.artifact_digest | startswith("sha256:"))
      and .artifact_digest != $digest
      and (all(.evidence_paths[]; .content_digest | startswith("sha256:")))
      and .access_state == "evidence-validated"
      and .validation_result == "valid-grounded"
      and (.evidence_paths | length) == 1
      and .verdict == "REVISE"
    ' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "contribution record is incomplete: $record"
fi

test_case "blind contribution cannot become valid through fabricated evidence"
artifact_digest="$(council_artifact_digest "$FIXTURE_ROOT" "Review fixture")"
record="$(council_contribution_record_json "$TEST_TMP_DIR/fabricated.md" "$FIXTURE_ROOT" "$artifact_digest")"
if jq -e '
      .access_state == "failed"
      and .validation_result == "invalid-access"
      and (.evidence_paths | length) == 0
      and .verdict == "APPROVE"
    ' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "blind contribution was accepted: $record"
fi

test_summary
