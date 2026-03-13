#!/usr/bin/env bash
# Simple test suite for debug mode (v7.25.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE="${PLUGIN_DIR}/scripts/orchestrate.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Test helper
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "✓ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ $test_name"
        echo "  Expected to find: $needle"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if ! echo "$haystack" | grep -qF -- "$needle"; then
        echo "✓ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ $test_name"
        echo "  Should NOT contain: $needle"
        return 1
    fi
}

echo "Testing Claude Octopus Debug Mode (v7.25.0)"
echo "============================================"
echo ""

# Test 1: --debug flag enables debug logging
echo "Test 1: --debug flag enables debug logging"
output=$("$ORCHESTRATE" --debug probe "test debug mode" --dry-run 2>&1 | head -50)
assert_contains "$output" "DEBUG" "Debug output enabled with --debug flag"

# Test 2: OCTOPUS_DEBUG env var enables debug logging
echo ""
echo "Test 2: OCTOPUS_DEBUG environment variable"
output=$(OCTOPUS_DEBUG=true "$ORCHESTRATE" probe "test debug env" --dry-run 2>&1 | head -50)
assert_contains "$output" "DEBUG" "Debug output enabled with OCTOPUS_DEBUG=true"

# Test 3: No debug output without flag
echo ""
echo "Test 3: No debug output without flag"
output=$("$ORCHESTRATE" probe "test no debug" --dry-run 2>&1 | head -50)
assert_not_contains "$output" "DEBUG" "No debug output without --debug"

# Test 4: Debug emits Command: line in spawn_agent (static analysis — runtime depends on cache state)
echo ""
echo "Test 4: Debug shows model resolution details"
if grep -c 'log.*DEBUG.*Command:' "$ORCHESTRATE" >/dev/null 2>&1; then
    echo "✓ Shows agent command in debug output"
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "✗ Shows agent command in debug output"
    echo "  Expected: debug_log line containing 'Command:' in orchestrate.sh"
    TESTS_RUN=$((TESTS_RUN + 1))
fi

# Test 5: Debug emits spawn_agent: line (static analysis — runtime depends on cache state)
echo ""
echo "Test 5: Debug shows spawn_agent details"
if grep -c 'log.*DEBUG.*spawn_agent' "$ORCHESTRATE" >/dev/null 2>&1; then
    echo "✓ Shows spawn_agent debug info"
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "✗ Shows spawn_agent debug info"
    echo "  Expected: debug_log line containing 'spawn_agent' in orchestrate.sh"
    TESTS_RUN=$((TESTS_RUN + 1))
fi

# Test 6: Help shows --debug option
echo ""
echo "Test 6: Help text includes --debug"
output=$("$ORCHESTRATE" --help 2>&1)
assert_contains "$output" "--debug" "Help text mentions --debug flag"

# Summary
echo ""
echo "============================================"
echo "Results: $TESTS_PASSED/$TESTS_RUN tests passed"
echo "============================================"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
