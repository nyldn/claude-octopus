#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="/tmp/octopus-tests-$$"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/testing.sh"
test_suite "tangle terminal outcome reporting"
mkdir -p "$TEST_TMP_DIR"

RED=""
GREEN=""
YELLOW=""
NC=""
_BOX_TOP=""
_BOX_BOT=""
MAX_QUALITY_RETRIES=0
QUALITY_THRESHOLD=75
LOOP_UNTIL_APPROVED=false
CI_MODE=true
OCTOPUS_ANTISYCOPHANCY=false
OCTOPUS_FILE_VALIDATION=false

log() { :; }
record_task_metric() { :; }
write_structured_decision() { :; }
retry_failed_subtasks() { :; }
evaluate_quality_branch() { printf '%s\n' "proceed"; }
get_gate_threshold() { printf '%s\n' "75"; }

make_result() {
    local name="$1" status="$2" output="${3:-work completed}"
    local path="$TEST_TMP_DIR/$name.md"
    cat > "$path" <<EOF
# Agent: test
# Task ID: $name
## Output
$output
## Status: $status
EOF
    printf '%s\n' "$path"
}

success=$(make_result success 'SUCCESS')
stalled=$(make_result stalled 'STALLED - PARTIAL RESULTS (exit code: 76)')
timeout=$(make_result timeout 'TIMEOUT - PARTIAL RESULTS (exit code: 124)')
persistence=$(make_result persistence 'FAILED (Execution contract persistence failed)')
failed=$(make_result failed 'FAILED (provider error)')
blocked=$(make_result blocked 'SUCCESS' 'Cannot complete: sandbox is blocking filesystem access.')

for spec in \
    "$success:success" \
    "$stalled:stalled" \
    "$timeout:timeout" \
    "$persistence:persistence_failed" \
    "$failed:failed" \
    "$blocked:blocked"; do
    file="${spec%:*}"
    expected="${spec##*:}"
    test_case "classifies $(basename "$file") as $expected"
    if [[ "$(tangle_result_terminal_outcome "$file")" == "$expected" ]]; then
        test_pass
    else
        test_fail "unexpected terminal outcome"
    fi
done

test_case "summarizes mixed terminal outcomes"
summary=$(tangle_result_paths_outcome_summary "$success
$stalled
$timeout
$persistence
$failed
$blocked")
if [[ "$summary" == "1 succeeded, 1 stalled, 1 timed out, 1 persistence failed, 1 blocked, 1 failed" ]]; then
    test_pass
else
    test_fail "unexpected summary: $summary"
fi

test_case "accepts result: retry candidate prefixes"
summary=$(tangle_result_paths_outcome_summary "result:$timeout
result:$persistence")
if [[ "$summary" == "1 timed out, 1 persistence failed" ]]; then
    test_pass
else
    test_fail "unexpected retry summary: $summary"
fi

test_case "counts missing dispatched results as unknown"
summary=$(tangle_result_paths_outcome_summary "$success" $'success\nmissing')
if [[ "$summary" == "1 succeeded, 1 unknown" ]]; then
    test_pass
else
    test_fail "missing dispatched result was not reported as unknown: $summary"
fi

test_case "reachable validation report includes missing dispatched result"
validation_results="$TEST_TMP_DIR/reachable-validation"
mkdir -p "$validation_results"
cp "$success" "$validation_results/test-tangle-outcomes-0.md"
RESULTS_DIR="$validation_results"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
mkdir -p "$WORKSPACE_DIR"
if validate_tangle_results "outcomes" "Report terminal outcomes" "" "" "" $'success\nmissing' >/dev/null 2>&1 &&
   grep -q -- '- Terminal Outcomes: 1 succeeded, 1 unknown' "$RESULTS_DIR/tangle-validation-outcomes.md"; then
    test_pass
else
    test_fail "reachable validation path did not report the missing dispatched result"
fi

test_case "watcher reports finished rather than complete"
if grep -q 'subtasks finished' "$PROJECT_ROOT/scripts/lib/workflows.sh" \
   && ! grep -q 'subtasks complete' "$PROJECT_ROOT/scripts/lib/workflows.sh"; then
    test_pass
else
    test_fail "watcher still labels terminal tasks as complete"
fi

test_case "retry branch reports candidate terminal outcomes"
if grep -q 'Retrying failed subtasks:' "$PROJECT_ROOT/scripts/lib/testing.sh" \
   && grep -q 'candidate terminal outcomes:' "$PROJECT_ROOT/scripts/lib/testing.sh"; then
    test_pass
else
    test_fail "retry branch is missing terminal outcome reporting"
fi

test_summary
