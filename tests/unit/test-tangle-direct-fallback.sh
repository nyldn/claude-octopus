#!/usr/bin/env bash
# Regression checks for /octo:develop fallback when decomposition is unusable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle direct fallback"

# These tests exercise tangle dispatch/validation behavior, not contextual review.
export OCTOPUS_TANGLE_CODE_REVIEW=false

test_case "workflows.sh has valid bash syntax"
if bash -n "$WORKFLOWS" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in workflows.sh"
fi

# shellcheck source=/dev/null
source "$WORKFLOWS"

CYAN=""
GREEN=""
MAGENTA=""
NC=""
TMUX_MODE=false
DRY_RUN=false
SUPPORTS_PARALLEL_FILE_SAFETY=false
RESULTS_DIR="$(mktemp -d)"
LOGS_DIR="$RESULTS_DIR/logs"
WORKSPACE_DIR="$RESULTS_DIR/workspace"
mkdir -p "$WORKSPACE_DIR/.octo/agents"
trap 'rm -rf "$RESULTS_DIR"' EXIT

DIRECT_PROMPT=""
DIRECT_TASK_ID=""
VALIDATION_CALLED=false
TANGLE_STATUS=0

log() { :; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
design_review_ceremony() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
run_agent_sync() {
    printf '%s\n' "This task should be handled directly."
}
spawn_agent() {
    DIRECT_PROMPT="$2"
    DIRECT_TASK_ID="$3"
}
validate_tangle_results() {
    VALIDATION_CALLED=true
}

original_prompt="Update src/lib/templates/NA10_HANDLE_SILENCE.ts and do not modify src/lib/render/renderEmailTemplate.ts."

tangle_develop "$original_prompt" >/dev/null && TANGLE_STATUS=0 || TANGLE_STATUS=$?

test_case "unparseable decomposition fails closed"
if [[ "$TANGLE_STATUS" -ne 0 ]]; then
    test_pass
else
    test_fail "unparseable decomposition returned success instead of failing closed"
fi

test_case "unparseable decomposition does not spawn direct fallback"
if [[ -z "$DIRECT_TASK_ID" && -z "$DIRECT_PROMPT" ]]; then
    test_pass
else
    test_fail "direct fallback was spawned despite fail-closed decomposition"
fi

test_case "fail-closed path returns before tangle validation"
if [[ "$VALIDATION_CALLED" == "false" ]]; then
    test_pass
else
    test_fail "validation ran even though no subtasks were spawned"
fi

test_summary
