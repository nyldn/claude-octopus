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

environment_blocked_output='## Worktree Changes

Implemented source and tests in five authorized files.

## Verification

Incomplete due to an environment blocker:

- `pnpm install --frozen-lockfile --offline`: failed with `EPERM`.
- Focused Vitest runs: blocked because `vitest` is unavailable.'
setup_blocked_output='## Verification

Blocked by environment setup:

- Build/lint/typecheck/test could not start: `turbo` not found.

The implementation is therefore incomplete pending dependency installation, regeneration, and the prescribed gates.'
pending_gates_output='## Verification

- **Blocked:** `pnpm platform:check` needs dependencies that are not installed.'
complete_output='## Worktree Changes

- Blocked users are excluded from search results.
- Incomplete payloads are rejected with a 400 response.

## Integration Evidence

- Blocked-user filtering is wired into the search route.

## Verification

- Blockers: none.
- `pnpm test`: 12 passed.'
emphasized_incomplete_output='## Verification

The implementation is **incomplete** pending dependency installation.'
negated_output='## Verification

Implementation complete. No task is blocked. All tests passed.
No subtask remains incomplete.

- Blocked: none
- **Incomplete:** no
- Blocked: no
- Blocked: N/A'
cleared_then_blocked_output='## Verification

- Blocked: none

Gates: the verification is still blocked until `turbo` is installed.'
explained_blocker_output='## Verification

- Blocked: no network access; dependency installation and tests could not run.'
cleared_and_blocked_line_output='## Verification

Blocked: none. The implementation is incomplete pending dependency installation.'

for spec in \
    "environment-blocked:$environment_blocked_output:blocked" \
    "setup-blocked:$setup_blocked_output:blocked" \
    "pending-gates:$pending_gates_output:blocked" \
    "emphasized-incomplete:$emphasized_incomplete_output:blocked" \
    "cleared-then-blocked:$cleared_then_blocked_output:blocked" \
    "explained-blocker:$explained_blocker_output:blocked" \
    "cleared-and-blocked-line:$cleared_and_blocked_line_output:blocked" \
    "complete-with-blocked-terms:$complete_output:success" \
    "negated-blockers:$negated_output:success"; do
    name="${spec%%:*}"
    expected="${spec##*:}"
    output="${spec#*:}"
    output="${output%:*}"
    file=$(make_result "$name" 'SUCCESS' "$output")
    test_case "classifies a successful launch whose output reports $name as $expected"
    if [[ "$(tangle_result_terminal_outcome "$file")" == "$expected" ]]; then
        test_pass
    else
        test_fail "unexpected terminal outcome: $(tangle_result_terminal_outcome "$file")"
    fi
done

test_case "a subtask that reports itself incomplete fails the quality gate"
self_report_results="$TEST_TMP_DIR/self-report-validation"
mkdir -p "$self_report_results"
make_result self-report 'SUCCESS' "$setup_blocked_output" > /dev/null
cp "$TEST_TMP_DIR/self-report.md" "$self_report_results/test-tangle-selfreport-0.md"
RESULTS_DIR="$self_report_results"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
mkdir -p "$WORKSPACE_DIR"
validate_tangle_results "selfreport" "Implement the plan" "" "" "" "self-report" >/dev/null 2>&1 || true
self_report_validation="$RESULTS_DIR/tangle-validation-selfreport.md"
if grep -q -- '### Quality Gate: FAILED' "$self_report_validation" &&
   grep -q -- '- Success Rate: 0% ' "$self_report_validation" &&
   grep -q -- '- Terminal Outcomes: 1 blocked' "$self_report_validation"; then
    test_pass
else
    test_fail "gate scored a self-reported incomplete subtask as: $(grep -E 'Quality Gate|Success Rate|Terminal Outcomes' "$self_report_validation" 2>/dev/null | tr '\n' ' ')"
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
