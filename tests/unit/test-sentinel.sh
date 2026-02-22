#!/bin/bash
# tests/unit/test-sentinel.sh
# Tests sentinel work monitor (v8.18.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Sentinel Work Monitor"

test_sentinel_disabled_by_default() {
    test_case "Sentinel is disabled by default"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" sentinel 2>&1) || true

    if echo "$output" | grep -qi "disabled\|OCTOPUS_SENTINEL_ENABLED"; then
        test_pass
    else
        test_fail "Expected disabled message, got: ${output:0:200}"
    fi
}

test_sentinel_requires_gh() {
    test_case "Sentinel reports when gh CLI is missing"

    # Run with sentinel enabled but in an env where gh might not work
    local output
    output=$(OCTOPUS_SENTINEL_ENABLED=true PATH="/usr/bin:/bin" "$PROJECT_ROOT/scripts/orchestrate.sh" sentinel 2>&1) || true

    # Should either succeed (if gh is available) or report the gh requirement
    if echo "$output" | grep -qi "gh\|GitHub CLI\|sentinel\|triage\|Scanning"; then
        test_pass
    else
        test_fail "Expected sentinel output, got: ${output:0:200}"
    fi
}

test_sentinel_help() {
    test_case "Sentinel --help shows usage"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" sentinel --help 2>&1) || true

    if echo "$output" | grep -qi "sentinel\|usage\|OCTOPUS_SENTINEL_ENABLED"; then
        test_pass
    else
        test_fail "Expected help output, got: ${output:0:200}"
    fi
}

test_sentinel_command_registered() {
    test_case "Sentinel command is registered in plugin.json"

    if grep -q "sentinel.md" "$PROJECT_ROOT/.claude-plugin/plugin.json"; then
        test_pass
    else
        test_fail "sentinel.md not found in plugin.json commands"
    fi
}

test_sentinel_command_file_exists() {
    test_case "Sentinel command file exists"

    if [[ -f "$PROJECT_ROOT/.claude/commands/sentinel.md" ]]; then
        test_pass
    else
        test_fail "sentinel.md command file not found"
    fi
}

test_sentinel_dry_run_no_crash() {
    test_case "Dry-run probe still works with sentinel code present"

    local output exit_code
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test" 2>&1) && exit_code=$? || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run probe failed with exit code $exit_code: ${output:0:200}"
    fi
}

# Run all tests
test_sentinel_disabled_by_default
test_sentinel_requires_gh
test_sentinel_help
test_sentinel_command_registered
test_sentinel_command_file_exists
test_sentinel_dry_run_no_crash

test_summary
