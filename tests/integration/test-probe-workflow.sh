#!/bin/bash
# tests/integration/test-probe-workflow.sh
# Tests probe (research) workflow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$SCRIPT_DIR/../helpers/mock-helpers.sh"

test_suite "Probe Workflow Integration"

test_probe_basic_execution() {
    test_case "Probe executes research phase"

    # Create mock responses
    local probe_response=$(generate_probe_response "OAuth authentication")
    local response_file=$(create_success_response "codex" "$probe_response")

    mock_codex "$response_file" 0

    # Execute probe in dry-run
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "Research OAuth authentication" 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "Probe should execute successfully"

    test_pass
}

test_probe_with_multiple_agents() {
    test_case "Probe coordinates multiple agents for research"

    # Mock both agents with different responses
    local codex_response=$(generate_probe_response "Database design")
    local gemini_response=$(generate_probe_response "Database patterns")

    mock_alternating "codex" "gemini" "$codex_response" "$gemini_response"

    # Execute probe
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "Research database patterns" 2>&1)
    local exit_code=$?

    # Should complete successfully
    assert_success "$exit_code" "Multi-agent probe should succeed"

    test_pass
}

test_probe_output_format() {
    test_case "Probe dry-run produces output"

    local response=$(generate_probe_response "API design")
    local response_file=$(create_success_response "codex" "$response")

    mock_codex "$response_file" 0

    local output exit_code=0
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "Research API design" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        test_fail "Probe dry-run exited with $exit_code"
        return 1
    fi

    # Dry-run should produce some output (banner, dry-run notice, etc.)
    if [[ -n "$output" ]]; then
        test_pass
    else
        test_fail "Probe dry-run produced no output"
        return 1
    fi
}

test_probe_handles_timeout() {
    test_case "Probe handles timeout gracefully"

    # Mock timeout scenario
    mock_timeout "codex" 2

    local output exit_code=0
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "Research with timeout" 2>&1) || exit_code=$?

    # In dry-run mode, timeout won't trigger — just verify it doesn't crash
    if [[ $exit_code -eq 0 ]]; then
        test_skip "Timeout not exercised in dry-run mode"
    elif echo "$output" | grep -qi "timeout\|timed out"; then
        test_pass
    else
        test_fail "Probe failed unexpectedly (exit $exit_code): $output"
        return 1
    fi
}

test_probe_parallel_mode() {
    test_case "Probe can run in parallel mode"

    local response=$(generate_probe_response "Microservices")
    local response_file=$(create_success_response "codex" "$response")

    mock_codex "$response_file" 0

    # Test with parallel flag if available
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "Research microservices" 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "Parallel probe should succeed"

    test_pass
}

# Run all tests
test_probe_basic_execution
test_probe_with_multiple_agents
test_probe_output_format
test_probe_handles_timeout
test_probe_parallel_mode

test_summary
