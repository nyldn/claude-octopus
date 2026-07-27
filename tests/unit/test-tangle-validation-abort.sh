#!/usr/bin/env bash
# Regression test: failed tangle validation must stop before contextual review.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle validation hard abort"

# This direct-library regression test exercises the validation gate itself,
# independent of the orchestrator's clean-baseline policy.
OCTOPUS_TANGLE_REQUIRE_CLEAN_BASELINE=false
source "$WORKFLOWS"

CYAN=""
GREEN=""
MAGENTA=""
NC=""
TMUX_MODE=false
DRY_RUN=false
SUPPORTS_PARALLEL_FILE_SAFETY=false
TEST_TMP_DIR="/tmp/octopus-tests-$$"
RESULTS_DIR="$TEST_TMP_DIR/tangle-validation-abort"
LOGS_DIR="$RESULTS_DIR/logs"
WORKSPACE_DIR="$RESULTS_DIR/workspace"
rm -rf "$TEST_TMP_DIR"
mkdir -p "$WORKSPACE_DIR/.octo/agents"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

REVIEW_CALLS=0
VALIDATION_CALLS=0

log() { :; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
design_review_ceremony() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
record_agents_batch_complete() { :; }

run_agent_sync() {
    printf '%s\n' '1. [CODING] Verify the existing fix. Files: apps/web/tests/setup.js'
}

spawn_agent_capture_pid() {
    local task_id="$3"
    printf '0\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
    printf '12345\n'
}

validate_tangle_results() {
    VALIDATION_CALLS=$((VALIDATION_CALLS + 1))
    return 1
}

tangle_contextual_review_gate() {
    REVIEW_CALLS=$((REVIEW_CALLS + 1))
    return 0
}

status=0
tangle_develop "Verify the existing React.act fix without unrelated edits." >/dev/null 2>&1 || status=$?

test_case "failed validation returns non-zero"
if [[ "$status" -ne 0 ]]; then
    test_pass
else
    test_fail "expected tangle_develop to return non-zero after validation failure"
fi

test_case "validation runs exactly once"
if [[ "$VALIDATION_CALLS" -eq 1 ]]; then
    test_pass
else
    test_fail "expected one validation call, got $VALIDATION_CALLS"
fi

test_case "contextual review is not called after validation abort"
if [[ "$REVIEW_CALLS" -eq 0 ]]; then
    test_pass
else
    test_fail "contextual review ran $REVIEW_CALLS time(s) after validation abort"
fi

test_summary
