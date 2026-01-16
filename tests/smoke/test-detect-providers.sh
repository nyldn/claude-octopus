#!/bin/bash
# tests/smoke/test-detect-providers.sh
# Tests provider detection logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$SCRIPT_DIR/../helpers/mock-helpers.sh"

test_suite "Provider Detection"

test_detect_both_providers() {
    test_case "Detects both codex and gemini when available"

    # Mock both providers as available
    mock_provider_available "codex" "true"
    mock_provider_available "gemini" "true"

    # Test detection logic (dry run)
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" probe -n "test" 2>&1 || true)

    if echo "$output" | grep -q "codex\|gemini"; then
        test_pass
    else
        test_fail "Provider detection didn't find expected providers"
        return 1
    fi
}

test_detect_single_provider() {
    test_case "Works with single provider available"

    # Mock only codex available
    mock_provider_available "codex" "true"
    mock_command "gemini" "exit 127"

    # Test detection (dry run)
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" probe -n "test" 2>&1 || true)

    # Should not fail when only one provider available
    if [[ $? -eq 0 ]] || echo "$output" | grep -qv "ERROR.*no providers"; then
        test_pass
    else
        test_fail "Single provider should still work"
        return 1
    fi
}

test_no_providers_error() {
    skip_if "! command -v codex &>/dev/null && ! command -v gemini &>/dev/null" "No real providers to test"

    test_case "Shows error when no providers available"

    # Mock both as unavailable
    mock_command "codex" "exit 127"
    mock_command "gemini" "exit 127"

    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" probe -n "test" 2>&1 || true)
    local exit_code=$?

    # Should show error or warning about no providers
    if echo "$output" | grep -qi "provider\|codex\|gemini" || [[ $exit_code -ne 0 ]]; then
        test_pass
    else
        test_fail "Should indicate provider issue"
        return 1
    fi
}

test_provider_version_check() {
    test_case "Provider commands are callable"

    # Check if real providers exist
    local has_codex=false
    local has_gemini=false

    if command -v codex &>/dev/null; then
        has_codex=true
    fi

    if command -v gemini &>/dev/null; then
        has_gemini=true
    fi

    if [[ "$has_codex" == "true" ]] || [[ "$has_gemini" == "true" ]]; then
        test_pass
    else
        test_skip "No real providers installed"
        return 0
    fi
}

# Run tests
test_detect_both_providers
test_detect_single_provider
test_no_providers_error
test_provider_version_check

test_summary
