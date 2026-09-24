#!/usr/bin/env bash
# Regression checks for /octo:embrace hardcoded phase fail-fast behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

# This suite intentionally exercises non-zero workflow exits. Keep errexit off
# after loading the shared framework so Bash 5/Linux does not abort before
# assertions run.
set +e

test_suite "embrace phase fail-fast"

# shellcheck source=/dev/null
source "$WORKFLOWS"

TEST_TMP_DIR="/tmp/octopus-tests-$$"
HOME="$TEST_TMP_DIR/home"
RESULTS_DIR="$TEST_TMP_DIR/results"
LOGS_DIR="$TEST_TMP_DIR/logs"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
PLUGIN_DIR="$PROJECT_ROOT"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM
mkdir -p "$HOME" "$RESULTS_DIR" "$LOGS_DIR" "$WORKSPACE_DIR"

CYAN=""
GREEN=""
MAGENTA=""
NC=""
_BOX_TOP=""
_BOX_BOT=""
AUTONOMY_MODE="semi-autonomous"
LOOP_UNTIL_APPROVED=false
RESUME_SESSION=false
DRY_RUN=false
OCTOPUS_YAML_RUNTIME=disabled
OCTOPUS_EMBRACE_DEBATE_GATES=none
SUPPORTS_DISABLE_CRON_ENV=false

CASE_NAME=""
PHASE_CALLS=""
CHECKPOINTS=""
EMBRACE_STATUS=0

log() { :; }
cleanup_old_results() { :; }
show_cost_estimate() { :; }
cleanup_expired_checkpoints() { :; }
reset_provider_lockouts() { :; }
search_observations() { :; }
init_session() { :; }
display_workflow_cost_estimate() { return 0; }
preflight_check() { return 0; }
display_phase_metrics() { :; }
update_context() { :; }
handle_autonomy_checkpoint() { :; }
complete_session() { :; }
write_structured_decision() { :; }
earn_skill() { :; }
sleep() { :; }
run_agent_sync() {
    if [[ "$CASE_NAME" == "gate_agents_fail" && "${5:-}" == "embrace-gate" ]]; then
        return 2
    fi
    printf '%s\n' "gate response from ${1:-agent}"
}
save_session_checkpoint() {
    CHECKPOINTS+="${1}:${2}:${3:-}"$'\n'
}

probe_discover() {
    PHASE_CALLS+="probe "
    [[ "$CASE_NAME" == "missing_probe_output" ]] && return 0
    printf '%s\n' "# probe synthesis" > "$RESULTS_DIR/probe-synthesis-test.md"
}

grasp_define() {
    PHASE_CALLS+="grasp "
    printf '%s\n' "# grasp consensus" > "$RESULTS_DIR/grasp-consensus-test.md"
}

tangle_develop() {
    PHASE_CALLS+="tangle "
    if [[ "$CASE_NAME" == "tangle_fails" ]]; then
        return 7
    fi
    printf '%s\n' "### Quality Gate: PASSED" > "$RESULTS_DIR/tangle-validation-test.md"
}

ink_deliver() {
    PHASE_CALLS+="ink "
    [[ "$CASE_NAME" == "missing_ink_output" ]] && return 0
    printf '%s\n' "# delivery" > "$RESULTS_DIR/delivery-test.md"
}

run_embrace_case() {
    set +e
    CASE_NAME="$1"
    OCTOPUS_EMBRACE_DEBATE_GATES="${2:-none}"
    PHASE_CALLS=""
    CHECKPOINTS=""
    EMBRACE_STATUS=0
    EMBRACE_DEBATE_GATE_OUTPUT=""
    rm -rf "$RESULTS_DIR" "$LOGS_DIR" "$WORKSPACE_DIR"
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR" "$WORKSPACE_DIR" "$HOME"

    embrace_full_workflow "Implement the requested feature" >/dev/null 2>&1
    EMBRACE_STATUS=$?

    return 0
}

run_embrace_case "all_ok" "none" || true

test_case "no debate gates by default"
if [[ "$EMBRACE_STATUS" -eq 0 ]] && \
   [[ "$PHASE_CALLS" == "probe grasp tangle ink " ]] && \
   [[ "$CHECKPOINTS" != *"debate-"* ]] && \
   ! ls "$RESULTS_DIR"/embrace-gate-*.md >/dev/null 2>&1; then
    test_pass
else
    test_fail "embrace ran debate gates even though none were requested"
fi

run_embrace_case "all_ok" "both" || true

test_case "requested debate gates run before develop and deliver"
if [[ "$EMBRACE_STATUS" -eq 0 ]] && \
   [[ "$PHASE_CALLS" == "probe grasp tangle ink " ]] && \
   [[ "$CHECKPOINTS" == *"debate-define-develop:completed:"* ]] && \
   [[ "$CHECKPOINTS" == *"debate-develop-deliver:completed:"* ]] && \
   ls "$RESULTS_DIR"/embrace-gate-define-develop-*.md >/dev/null 2>&1 && \
   ls "$RESULTS_DIR"/embrace-gate-develop-deliver-*.md >/dev/null 2>&1; then
    test_pass
else
    test_fail "embrace did not run both requested debate gates"
fi

run_embrace_case "gate_agents_fail" "define" || true

test_case "requested debate gate failure stops before tangle"
if [[ "$EMBRACE_STATUS" -ne 0 ]] && \
   [[ "$PHASE_CALLS" == "probe grasp " ]] && \
   [[ "$CHECKPOINTS" == *"debate-define-develop:failed:"* ]]; then
    test_pass
else
    test_fail "embrace continued after requested debate gate failure"
fi

run_embrace_case "missing_probe_output" || true

test_case "missing probe synthesis stops before grasp"
if [[ "$EMBRACE_STATUS" -ne 0 ]] && \
   [[ "$PHASE_CALLS" == "probe " ]] && \
   [[ "$CHECKPOINTS" == *"probe:failed:"* ]]; then
    test_pass
else
    test_fail "embrace did not stop cleanly when probe produced no synthesis artifact"
fi

run_embrace_case "tangle_fails" || true

test_case "tangle failure stops before ink"
if [[ "$EMBRACE_STATUS" -ne 0 ]] && \
   [[ "$PHASE_CALLS" == "probe grasp tangle " ]] && \
   [[ "$CHECKPOINTS" == *"tangle:failed:"* ]]; then
    test_pass
else
    test_fail "embrace did not stop cleanly when tangle returned non-zero"
fi

run_embrace_case "missing_ink_output" || true

test_case "missing delivery artifact fails after ink"
if [[ "$EMBRACE_STATUS" -ne 0 ]] && \
   [[ "$PHASE_CALLS" == "probe grasp tangle ink " ]] && \
   [[ "$CHECKPOINTS" == *"ink:failed:"* ]]; then
    test_pass
else
    test_fail "embrace did not fail when ink produced no delivery artifact"
fi

test_case "debate gate without a context file reads only the session results directory"
CASE_NAME="context_free_gate"
EMBRACE_DEBATE_GATE_OUTPUT=""
rm -rf "$RESULTS_DIR" "$LOGS_DIR" "$HOME/.claude-octopus"
mkdir -p "$RESULTS_DIR" "$LOGS_DIR" "$HOME/.claude-octopus/results"
printf '%s\n' "# session consensus" > "$RESULTS_DIR/grasp-consensus-session.md"
touch -t 202001010000 "$RESULTS_DIR/grasp-consensus-session.md"
printf '%s\n' "# other session consensus" > "$HOME/.claude-octopus/results/grasp-consensus-other.md"
embrace_debate_gate "define-develop" "Implement the requested feature" >/dev/null 2>&1
gate_status=$?
if [[ "$gate_status" -eq 0 ]] && \
   grep -Fq "**Context Artifact:** $RESULTS_DIR/grasp-consensus-session.md" "$EMBRACE_DEBATE_GATE_OUTPUT" 2>/dev/null; then
    test_pass
else
    test_fail "context-free debate gate did not use the session consensus (status $gate_status)"
fi

test_summary
