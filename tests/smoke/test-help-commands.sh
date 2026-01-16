#!/bin/bash
# tests/smoke/test-help-commands.sh
# Tests help and usage commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Help Commands"

test_help_flag() {
    test_case "orchestrate.sh --help shows usage"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" --help 2>&1 || true)

    if echo "$output" | grep -q "Usage:"; then
        test_pass
    else
        test_fail "Help output missing 'Usage:' section"
        return 1
    fi
}

test_help_shows_commands() {
    test_case "Help shows all main commands"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" --help 2>&1 || true)

    local commands=("probe" "grasp" "tangle" "ink" "embrace" "grapple" "squeeze")
    local missing=0

    for cmd in "${commands[@]}"; do
        if ! echo "$output" | grep -q "$cmd"; then
            echo "  Missing command: $cmd"
            missing=1
        fi
    done

    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "Some commands missing from help"
        return 1
    fi
}

test_version_flag() {
    test_case "orchestrate.sh --version shows version"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" --version 2>&1 || true)

    if echo "$output" | grep -qE "v[0-9]+\.[0-9]+"; then
        test_pass
    else
        test_fail "Version output doesn't match expected format"
        return 1
    fi
}

test_invalid_command() {
    test_case "Invalid command shows error"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" invalid-command 2>&1 || true)

    if echo "$output" | grep -qi "error\|unknown\|invalid"; then
        test_pass
    else
        test_fail "No error shown for invalid command"
        return 1
    fi
}

test_no_arguments() {
    test_case "No arguments shows help"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" 2>&1 || true)

    if echo "$output" | grep -q "Usage:"; then
        test_pass
    else
        test_fail "No help shown when run without arguments"
        return 1
    fi
}

# Run tests
test_help_flag
test_help_shows_commands
test_version_flag
test_invalid_command
test_no_arguments

test_summary
