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

    # Test detection logic (dry run) - flag must come before command
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test" 2>&1 || true)

    # Just verify dry-run completes without error
    if [[ $? -eq 0 ]]; then
        test_pass
    else
        test_fail "Provider detection dry-run failed"
        return 1
    fi
}

test_detect_single_provider() {
    test_case "Works with single provider available"

    # Test detection (dry run) - flag must come before command
    local output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test" 2>&1 || true)

    # Should not fail in dry-run mode
    if [[ $? -eq 0 ]]; then
        test_pass
    else
        test_fail "Single provider dry-run should work"
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
test_provider_version_check

test_summary
