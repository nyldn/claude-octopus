#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "ink retrospective runs only on a failed tangle gate"

source "$WORKFLOWS"

TEST_ROOT="$(mktemp -d)"
HOME="$TEST_ROOT/home"
RESULTS_DIR="$TEST_ROOT/results"
LOGS_DIR="$TEST_ROOT/logs"
WORKSPACE_DIR="$TEST_ROOT/workspace"
RETROSPECTIVE_LOG="$TEST_ROOT/retrospective-calls"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$HOME" "$RESULTS_DIR" "$LOGS_DIR" "$WORKSPACE_DIR"

CYAN=""
GREEN=""
MAGENTA=""
NC=""
DRY_RUN=false
SUPPORTS_BATCH_COMMAND=false
OCTOPUS_REVIEW_4X10=false

log() { :; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
score_cross_model_review() { echo "10:10:10:10"; }
format_review_scorecard() { :; }
write_structured_decision() { :; }
octopus_complete() { :; }
octo_provider_allowed() { return 1; }
run_agent_sync() { return 1; }
retrospective_ceremony() { printf '%s\n' "$2" >> "$RETROSPECTIVE_LOG"; }

retrospective_calls() {
    if [[ -f "$RETROSPECTIVE_LOG" ]]; then
        wc -l < "$RETROSPECTIVE_LOG" | tr -d '[:space:]'
    else
        echo 0
    fi
}

deliver_with_tangle_gate() {
    local gate_line="$1"
    local tangle_file="$RESULTS_DIR/tangle-validation-test.md"

    rm -rf "$RESULTS_DIR" "$RETROSPECTIVE_LOG"
    mkdir -p "$RESULTS_DIR"
    {
        echo "# Tangle"
        [[ -z "$gate_line" ]] || echo "$gate_line"
        echo "Implementation notes for the requested feature."
    } > "$tangle_file"

    ink_deliver "Implement the requested feature" "$tangle_file" >/dev/null 2>&1
}

test_case "tangle results without a quality gate line skip the failure retrospective"
if deliver_with_tangle_gate ""; then
    calls="$(retrospective_calls)"
    if [[ "$calls" == "0" ]]; then
        test_pass
    else
        test_fail "retrospective_ceremony ran $calls time(s) without a failed quality gate"
    fi
else
    test_fail "ink_deliver returned non-zero for tangle results without a quality gate line"
fi

test_case "tangle results with a passed quality gate skip the failure retrospective"
if deliver_with_tangle_gate "### Quality Gate: PASSED"; then
    calls="$(retrospective_calls)"
    if [[ "$calls" == "0" ]]; then
        test_pass
    else
        test_fail "retrospective_ceremony ran $calls time(s) after a passed quality gate"
    fi
else
    test_fail "ink_deliver returned non-zero for tangle results with a passed quality gate"
fi

test_case "tangle results with a failed quality gate run the failure retrospective once"
if deliver_with_tangle_gate "### Quality Gate: FAILED"; then
    calls="$(retrospective_calls)"
    if [[ "$calls" == "1" ]] && \
       [[ "$(cat "$RETROSPECTIVE_LOG")" == "Quality gate FAILED in tangle phase" ]]; then
        test_pass
    else
        test_fail "expected one failure retrospective, got $calls call(s)"
    fi
else
    test_fail "ink_deliver returned non-zero for tangle results with a failed quality gate"
fi

test_summary
