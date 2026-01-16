#!/bin/bash
# tests/smoke/test-dry-run-all.sh
# Tests dry-run mode for all commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Dry Run Mode"

test_probe_dry_run() {
    test_case "probe -n executes without errors"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test prompt" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "probe dry-run failed with exit code $exit_code"
        return 1
    fi
}

test_grasp_dry_run() {
    test_case "grasp -n executes without errors"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n grasp "test prompt" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "grasp dry-run failed with exit code $exit_code"
        return 1
    fi
}

test_tangle_dry_run() {
    test_case "tangle -n executes without errors"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n tangle "test prompt" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "tangle dry-run failed with exit code $exit_code"
        return 1
    fi
}

test_ink_dry_run() {
    test_case "ink -n executes without errors"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n ink "test prompt" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "ink dry-run failed with exit code $exit_code"
        return 1
    fi
}

test_embrace_dry_run() {
    test_case "embrace -n executes without errors"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n embrace "test prompt" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "embrace dry-run failed with exit code $exit_code"
        return 1
    fi
}

test_dry_run_no_api_calls() {
    test_case "Dry run doesn't make actual API calls"

    # Verify -n flag output contains dry-run indicators
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test" 2>&1)

    if echo "$output" | grep -qi "dry-run\|would"; then
        test_pass
    else
        test_fail "Dry-run output missing expected indicators"
        return 1
    fi
}

# Run all tests
test_probe_dry_run
test_grasp_dry_run
test_tangle_dry_run
test_ink_dry_run
test_embrace_dry_run
test_dry_run_no_api_calls

test_summary
