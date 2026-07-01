#!/usr/bin/env bash
# Regression checks for tangle decomposition reformat routing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle reformat agent routing"

WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
AGENT_UTILS="$PROJECT_ROOT/scripts/lib/agent-utils.sh"
CALL_LOG="$TEST_TMP_DIR/reformat-calls.log"
mkdir -p "$TEST_TMP_DIR"

PLUGIN_DIR="$PROJECT_ROOT"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
RESULTS_DIR="$TEST_TMP_DIR/results"
mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"
log() { :; }

source "$AGENT_UTILS"
source "$WORKFLOWS"

run_agent_sync() {
    local agent="$1"
    local prompt="$2"
    local timeout="$3"
    local role="$4"
    local phase="$5"
    printf '%s|%s|%s|%s\n' "$agent" "$timeout" "$role" "$phase" >> "$CALL_LOG"
    if [[ "$agent" == "gemini" || "$agent" == "agy" ]]; then
        printf '1. [CODING] Reformatted task — Files: scripts/lib/workflows.sh — Task: use configured reformat route\n'
        return 0
    fi
    return 1
}

test_case "reformat uses OCTOPUS_TANGLE_DECOMPOSE_AGENT before legacy defaults"
if (
    rm -f "$CALL_LOG"
    export OCTOPUS_TANGLE_DECOMPOSE_AGENT="gemini"
    export OCTOPUS_TANGLE_DECOMPOSE_FALLBACK_AGENT="codex"
    result=$(tangle_reformat_decomposition "task" "bad decomposition" "overlap" "")
    [[ "$result" == *"Reformatted task"* ]] &&
    [[ "$(sed -n '1p' "$CALL_LOG")" == "gemini|120|researcher|tangle" ]] &&
    [[ "$(wc -l < "$CALL_LOG")" -eq 1 ]]
); then
    test_pass
else
    test_fail "reformat did not use OCTOPUS_TANGLE_DECOMPOSE_AGENT first"
fi

test_case "reformat falls back to OCTOPUS_TANGLE_DECOMPOSE_FALLBACK_AGENT"
if (
    rm -f "$CALL_LOG"
    export OCTOPUS_TANGLE_DECOMPOSE_AGENT="unavailable-agent"
    export OCTOPUS_TANGLE_DECOMPOSE_FALLBACK_AGENT="gemini"
    result=$(tangle_reformat_decomposition "task" "bad decomposition" "overlap" "")
    [[ "$result" == *"Reformatted task"* ]] &&
    [[ "$(sed -n '1p' "$CALL_LOG")" == "unavailable-agent|120|researcher|tangle" ]] &&
    [[ "$(sed -n '2p' "$CALL_LOG")" == "gemini|120|researcher|tangle" ]]
); then
    test_pass
else
    test_fail "reformat did not use OCTOPUS_TANGLE_DECOMPOSE_FALLBACK_AGENT"
fi


test_case "reformat keeps legacy agy/codex compatibility when override helper is absent"
if (
    rm -f "$CALL_LOG"
    unset -f octopus_agent_override
    unset OCTOPUS_TANGLE_DECOMPOSE_AGENT
    unset OCTOPUS_TANGLE_DECOMPOSE_FALLBACK_AGENT
    result=$(tangle_reformat_decomposition "task" "bad decomposition" "overlap" "")
    [[ "$result" == *"Reformatted task"* ]] &&
    [[ "$(sed -n '1p' "$CALL_LOG")" == "agy|120|researcher|tangle" ]] &&
    [[ "$(wc -l < "$CALL_LOG")" -eq 1 ]]
); then
    test_pass
else
    test_fail "reformat did not preserve agy/codex compatibility without octopus_agent_override"
fi

test_case "reformat dispatch no longer hardcodes agy claude-sonnet chain"
reformat_body=$(sed -n '/^tangle_reformat_decomposition()/,/^}/p' "$WORKFLOWS")
if [[ "$(printf '%s\n' "$reformat_body" | grep -c 'run_agent_sync "agy"' || true)" -eq 0 ]] &&
   [[ "$(printf '%s\n' "$reformat_body" | grep -c 'run_agent_sync "claude-sonnet"' || true)" -eq 0 ]]; then
    test_pass
else
    test_fail "reformat still contains hardcoded agy/claude-sonnet dispatch"
fi

test_summary
