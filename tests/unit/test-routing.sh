#!/bin/bash
# tests/unit/test-routing.sh
# Tests provider routing logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$SCRIPT_DIR/../helpers/mock-helpers.sh"

test_suite "Provider Routing"

test_provider_detection() {
    test_case "Detects available providers"

    # Mock both providers available
    mock_provider_available "codex" "true"
    mock_provider_available "gemini" "true"

    # Test that orchestrate can detect providers (dry-run)
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" probe -n "test" 2>&1)
    local exit_code=$?

    # Should succeed when providers available
    assert_success "$exit_code" "Should succeed with providers available"
    test_pass
}

test_single_provider_fallback() {
    test_case "Falls back to single provider when one unavailable"

    # Mock only codex available
    mock_provider_available "codex" "true"
    mock_command "gemini" "exit 127"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" probe -n "test" 2>&1)
    local exit_code=$?

    # Should still work with single provider
    if [[ $exit_code -eq 0 ]] || ! echo "$output" | grep -qi "fatal\|error.*no providers"; then
        test_pass
    else
        test_fail "Should work with single provider: $output"
    fi
}

test_command_execution() {
    test_case "Commands execute with valid syntax"

    # Test each command in dry-run mode
    local commands=("probe" "grasp" "tangle" "ink" "embrace" "grapple" "squeeze")

    for cmd in "${commands[@]}"; do
        local result=$("$PROJECT_ROOT/scripts/orchestrate.sh" "$cmd" -n "test" 2>&1)
        local code=$?

        if [[ $code -ne 0 ]]; then
            test_fail "Command $cmd failed in dry-run: $result"
            return 1
        fi
    done

    test_pass
}

test_help_accessibility() {
    test_case "Help is accessible for all commands"

    local commands=("probe" "grasp" "tangle" "ink" "embrace" "grapple" "squeeze")

    for cmd in "${commands[@]}"; do
        local help_output=$("$PROJECT_ROOT/scripts/orchestrate.sh" "$cmd" --help 2>&1 || true)

        if ! echo "$help_output" | grep -qi "usage\|help\|$cmd"; then
            test_fail "No help for command: $cmd"
            return 1
        fi
    done

    test_pass
}

test_invalid_command_handling() {
    test_case "Invalid commands show appropriate error"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" invalid-nonexistent-command 2>&1 || true)

    if echo "$output" | grep -qi "error\|invalid\|unknown\|usage"; then
        test_pass
    else
        test_fail "Should show error for invalid command"
    fi
}

# Run all tests
test_provider_detection
test_single_provider_fallback
test_command_execution
test_help_accessibility
test_invalid_command_handling

test_summary
