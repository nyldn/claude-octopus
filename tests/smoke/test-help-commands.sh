#!/bin/bash
# tests/smoke/test-help-commands.sh
# Tests help and usage commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Help Commands"

test_help_flag() {
    test_case "orchestrate.sh --help shows usage"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" --help 2>&1 || true)

    if echo "$output" | grep -qi "Quick Start\|Usage\|Examples"; then
        test_pass
    else
        test_fail "Help output missing usage information"
        return 1
    fi
}

test_help_shows_commands() {
    test_case "Help shows main commands"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" --help 2>&1 || true)

    # Check for the commands shown in basic help
    local commands=("auto" "embrace" "setup")
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

    if echo "$output" | grep -qi "Quick Start\|Usage\|Examples"; then
        test_pass
    else
        test_fail "No help shown when run without arguments"
        return 1
    fi
}

# Run tests
test_help_flag
test_help_shows_commands
test_invalid_command
test_no_arguments

test_summary
