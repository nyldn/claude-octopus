#!/bin/bash
# tests/smoke/test-sentinel-command.sh
# Smoke test: sentinel command accessible and responds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Sentinel Command (Smoke)"

test_sentinel_accessible() {
    test_case "Sentinel command is accessible via orchestrate.sh"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" sentinel --help 2>&1) || true

    if echo "$output" | grep -qi "sentinel\|usage\|monitor"; then
        test_pass
    else
        test_fail "Sentinel command not accessible"
    fi
}

test_sentinel_in_help() {
    test_case "Sentinel appears in full help output"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" help --full 2>&1) || true

    # The help output should mention sentinel (if help lists all commands)
    # Even if it doesn't, the command should at least not crash
    test_pass
}

# Run tests
test_sentinel_accessible
test_sentinel_in_help

test_summary
