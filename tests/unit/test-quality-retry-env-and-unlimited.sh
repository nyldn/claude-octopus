#!/usr/bin/env bash
# Regression checks for quality retry environment overrides and unlimited retry mode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "quality retry env and unlimited"

prepare_quality_fixture() {
    export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
    export RESULTS_DIR="$TEST_TMP_DIR/results"
    mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR"
}

test_case "quality.sh preserves LOOP_UNTIL_APPROVED and MAX_QUALITY_RETRIES from env"
if (
    prepare_quality_fixture
    export LOOP_UNTIL_APPROVED=true
    export MAX_QUALITY_RETRIES=unlimited
    export CLAUDE_OCTOPUS_MAX_RETRIES=3
    source "$PROJECT_ROOT/scripts/lib/quality.sh"
    [[ "$LOOP_UNTIL_APPROVED" == "true" ]] && [[ "$MAX_QUALITY_RETRIES" == "unlimited" ]]
); then
    test_pass
else
    test_fail "quality.sh overwrote retry env overrides"
fi

test_case "unlimited retry mode keeps retrying regardless of retry count"
if (
    prepare_quality_fixture
    export LOOP_UNTIL_APPROVED=true
    source "$PROJECT_ROOT/scripts/lib/quality.sh"
    for unlimited_alias in unlimited infinite inf forever -1 UNLIMITED; do
        export MAX_QUALITY_RETRIES="$unlimited_alias"
        [[ "$(evaluate_quality_branch 66 0)" == "retry" ]] || exit 1
        [[ "$(evaluate_quality_branch 66 1000)" == "retry" ]] || exit 1
        [[ "$(quality_retry_limit)" == "∞" ]] || exit 1
    done
); then
    test_pass
else
    test_fail "unlimited retry mode did not keep retry branch open"
fi

test_case "finite retry mode still stops at configured limit"
if (
    prepare_quality_fixture
    export LOOP_UNTIL_APPROVED=true
    export MAX_QUALITY_RETRIES=2
    source "$PROJECT_ROOT/scripts/lib/quality.sh"
    [[ "$(evaluate_quality_branch 66 0)" == "retry" ]] &&
    [[ "$(evaluate_quality_branch 66 1)" == "retry" ]] &&
    [[ "$(evaluate_quality_branch 66 2)" == "abort" ]]
); then
    test_pass
else
    test_fail "finite retry limit no longer stops at configured max"
fi

test_case "CLAUDE_OCTOPUS_MAX_RETRIES remains fallback when MAX_QUALITY_RETRIES unset"
if (
    prepare_quality_fixture
    unset MAX_QUALITY_RETRIES || true
    export LOOP_UNTIL_APPROVED=true
    export CLAUDE_OCTOPUS_MAX_RETRIES=5
    source "$PROJECT_ROOT/scripts/lib/quality.sh"
    [[ "$MAX_QUALITY_RETRIES" == "5" ]] &&
    [[ "$(quality_retry_limit)" == "5" ]] &&
    [[ "$(evaluate_quality_branch 66 4)" == "retry" ]] &&
    [[ "$(evaluate_quality_branch 66 5)" == "abort" ]]
); then
    test_pass
else
    test_fail "CLAUDE_OCTOPUS_MAX_RETRIES fallback no longer works"
fi

test_summary
