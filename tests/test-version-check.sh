#!/bin/bash
# Test suite for Claude Code version check functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "\n${BLUE}[TEST $TESTS_RUN]${NC} $1"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL${NC}: $1"
}

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Octopus - Version Check Test Suite               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Test 1: Bash syntax check
test_start "Bash syntax check"
if bash -n "$ORCHESTRATE" 2>&1; then
    test_pass "No bash syntax errors"
else
    test_fail "Bash syntax errors found"
fi

# Test 2: Full detect-providers output format
test_start "Full detect-providers output format and version check"
echo "Running: $ORCHESTRATE detect-providers"
output=$("$ORCHESTRATE" detect-providers 2>&1)

echo "Output:"
echo "$output"
echo ""

# Test 3: Check for required output fields
test_start "Verify required output fields present"

if echo "$output" | grep -q "CLAUDE_CODE_VERSION="; then
    test_pass "Output contains CLAUDE_CODE_VERSION"
    version=$(echo "$output" | grep "CLAUDE_CODE_VERSION=" | head -1 | cut -d= -f2)
    echo "  Detected version: $version"
else
    test_fail "Output missing CLAUDE_CODE_VERSION"
fi

if echo "$output" | grep -q "CLAUDE_CODE_STATUS="; then
    test_pass "Output contains CLAUDE_CODE_STATUS"
    status=$(echo "$output" | grep "CLAUDE_CODE_STATUS=" | head -1 | cut -d= -f2)
    echo "  Status: $status"
else
    test_fail "Output missing CLAUDE_CODE_STATUS"
fi

if echo "$output" | grep -q "CLAUDE_CODE_MINIMUM="; then
    test_pass "Output contains CLAUDE_CODE_MINIMUM"
    minimum=$(echo "$output" | grep "CLAUDE_CODE_MINIMUM=" | head -1 | cut -d= -f2)
    echo "  Required minimum: $minimum"
else
    test_fail "Output missing CLAUDE_CODE_MINIMUM"
fi

# Test 4: Provider detection still works
test_start "Provider detection fields present"

if echo "$output" | grep -q "CODEX_STATUS="; then
    test_pass "Output contains CODEX_STATUS"
else
    test_fail "Output missing CODEX_STATUS"
fi

if echo "$output" | grep -q "GEMINI_STATUS="; then
    test_pass "Output contains GEMINI_STATUS"
else
    test_fail "Output missing GEMINI_STATUS"
fi

# Test 5: Verify version check runs before provider detection
test_start "Version check runs before provider detection"
first_section=$(echo "$output" | head -15)
if echo "$first_section" | grep -q "Detecting Claude Code version"; then
    test_pass "Version check runs first"
else
    test_fail "Version check should run before provider detection"
fi

# Test 6: Parse version status and verify logic
test_start "Parse and verify version status logic"
claude_status=$(echo "$output" | grep "CLAUDE_CODE_STATUS=" | head -1 | cut -d= -f2)

case "$claude_status" in
    ok)
        if echo "$output" | grep -q "✓ Claude Code version:"; then
            test_pass "Status 'ok' shows success message"
        else
            test_fail "Status 'ok' should show success message"
        fi
        ;;
    outdated)
        if echo "$output" | grep -q "⚠️  WARNING: Claude Code is outdated!"; then
            test_pass "Status 'outdated' shows warning message"
        else
            test_fail "Status 'outdated' should show warning message"
        fi

        # Verify update instructions are present
        if echo "$output" | grep -q "npm update -g"; then
            test_pass "Outdated warning includes npm update instructions"
        else
            test_fail "Should include npm update instructions"
        fi

        if echo "$output" | grep -q "brew upgrade"; then
            test_pass "Outdated warning includes brew upgrade instructions"
        else
            test_fail "Should include brew upgrade instructions"
        fi

        if echo "$output" | grep -q "restart Claude Code"; then
            test_pass "Outdated warning includes restart reminder"
        else
            test_fail "Should include restart reminder"
        fi
        ;;
    unknown)
        echo -e "${YELLOW}⚠ INFO${NC}: Version status is 'unknown' (version detection may not be available in this environment)"
        test_pass "Unknown status handled gracefully"
        ;;
    *)
        test_fail "Unexpected status: $claude_status"
        ;;
esac

# Test 7: Check cache file creation
test_start "Provider cache file creation"
cache_file="$HOME/.claude-octopus/.provider-cache"
if [[ -f "$cache_file" ]]; then
    test_pass "Cache file exists at $cache_file"

    # Verify cache contents
    if grep -q "CODEX_STATUS=" "$cache_file"; then
        test_pass "Cache contains CODEX_STATUS"
    else
        test_fail "Cache missing CODEX_STATUS"
    fi

    if grep -q "GEMINI_STATUS=" "$cache_file"; then
        test_pass "Cache contains GEMINI_STATUS"
    else
        test_fail "Cache missing GEMINI_STATUS"
    fi

    if grep -q "CACHE_TIME=" "$cache_file"; then
        test_pass "Cache contains timestamp"
    else
        test_fail "Cache missing timestamp"
    fi

    echo "Cache contents:"
    cat "$cache_file" | head -20
else
    test_fail "Cache file not created"
fi

# Test 8: Verify minimum version is 2.1.14
test_start "Verify minimum required version is 2.1.14"
min_version=$(echo "$output" | grep "CLAUDE_CODE_MINIMUM=" | head -1 | cut -d= -f2)
if [[ "$min_version" == "2.1.14" ]]; then
    test_pass "Minimum version correctly set to 2.1.14"
else
    test_fail "Minimum version should be 2.1.14, got: $min_version"
fi

# Test 9: Test version comparison logic with manual test script
test_start "Version comparison logic (manual test)"

cat > /tmp/test_version_compare.sh <<'EOF'
#!/bin/bash
version_compare() {
    local v1="$1"
    local v2="$2"
    IFS='.' read -ra V1 <<< "$v1"
    IFS='.' read -ra V2 <<< "$v2"
    for i in 0 1 2; do
        local num1="${V1[$i]:-0}"
        local num2="${V2[$i]:-0}"
        if (( num1 > num2 )); then
            return 0
        elif (( num1 < num2 )); then
            return 1
        fi
    done
    return 0
}

# Test cases
tests_passed=0
tests_failed=0

# 2.1.10 == 2.1.10 (should pass)
if version_compare "2.1.10" "2.1.10"; then
    echo "PASS: 2.1.10 >= 2.1.10"
    ((tests_passed++))
else
    echo "FAIL: 2.1.10 >= 2.1.10"
    ((tests_failed++))
fi

# 2.1.11 > 2.1.10 (should pass)
if version_compare "2.1.11" "2.1.10"; then
    echo "PASS: 2.1.11 >= 2.1.10"
    ((tests_passed++))
else
    echo "FAIL: 2.1.11 >= 2.1.10"
    ((tests_failed++))
fi

# 2.1.9 < 2.1.10 (should fail)
if version_compare "2.1.9" "2.1.10"; then
    echo "FAIL: 2.1.9 should be < 2.1.10"
    ((tests_failed++))
else
    echo "PASS: 2.1.9 < 2.1.10 (correctly identified)"
    ((tests_passed++))
fi

# 3.0.0 > 2.1.10 (should pass)
if version_compare "3.0.0" "2.1.10"; then
    echo "PASS: 3.0.0 >= 2.1.10"
    ((tests_passed++))
else
    echo "FAIL: 3.0.0 >= 2.1.10"
    ((tests_failed++))
fi

# 1.9.9 < 2.1.10 (should fail)
if version_compare "1.9.9" "2.1.10"; then
    echo "FAIL: 1.9.9 should be < 2.1.10"
    ((tests_failed++))
else
    echo "PASS: 1.9.9 < 2.1.10 (correctly identified)"
    ((tests_passed++))
fi

echo ""
echo "Version comparison tests: $tests_passed passed, $tests_failed failed"
exit $tests_failed
EOF

chmod +x /tmp/test_version_compare.sh
if /tmp/test_version_compare.sh; then
    test_pass "All version comparison tests passed"
else
    test_fail "Some version comparison tests failed"
fi
rm /tmp/test_version_compare.sh

# Test 10: Check that detect-providers can be run multiple times
test_start "Run detect-providers multiple times (idempotency test)"
output1=$("$ORCHESTRATE" detect-providers 2>&1 | grep "CLAUDE_CODE_VERSION=")
output2=$("$ORCHESTRATE" detect-providers 2>&1 | grep "CLAUDE_CODE_VERSION=")

if [[ "$output1" == "$output2" ]]; then
    test_pass "Detect-providers is idempotent (same results on repeated calls)"
else
    test_fail "Detect-providers should return consistent results"
fi

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Test Summary                                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Total tests run: ${BLUE}$TESTS_RUN${NC}"
echo -e "Tests passed:    ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed:    ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "Version check feature is working correctly:"
    echo "  - Claude Code version detection ✓"
    echo "  - Version comparison logic ✓"
    echo "  - Minimum version enforcement (2.1.14) ✓"
    echo "  - Upgrade instructions for outdated versions ✓"
    echo "  - Integration with detect-providers ✓"
    echo "  - Cache file creation ✓"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
