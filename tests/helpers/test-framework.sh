#!/bin/bash
# tests/helpers/test-framework.sh
# Comprehensive test framework for Claude Octopus
# Provides assertions, mocks, fixtures, hooks, and reporting

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test state
TEST_SUITE_NAME=""
TEST_CASE_NAME=""
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TEST_START_TIME=0
TEST_SUITE_START_TIME=0

# Arrays for tracking
FAILED_TESTS=()
SKIPPED_TESTS=()

# Temporary directories
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
MOCK_BIN_DIR="$TEST_TMP_DIR/mock-bin"

# Hooks
BEFORE_EACH_HOOK=""
AFTER_EACH_HOOK=""
BEFORE_ALL_HOOK=""
AFTER_ALL_HOOK=""

#==============================================================================
# Test Suite Management
#==============================================================================

test_suite() {
    local name="$1"
    TEST_SUITE_NAME="$name"
    TEST_SUITE_START_TIME=$(date +%s)

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test Suite: $name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Setup test environment
    mkdir -p "$TEST_TMP_DIR"
    mkdir -p "$MOCK_BIN_DIR"

    # Run before_all hook if defined
    if [[ -n "$BEFORE_ALL_HOOK" ]]; then
        eval "$BEFORE_ALL_HOOK"
    fi
}

test_case() {
    local name="$1"
    TEST_CASE_NAME="$name"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TEST_START_TIME=$(date +%s)

    echo -e "\n${BLUE}▶ $name${NC}"

    # Run before_each hook if defined
    if [[ -n "$BEFORE_EACH_HOOK" ]]; then
        eval "$BEFORE_EACH_HOOK"
    fi
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    local duration=$(($(date +%s) - TEST_START_TIME))
    echo -e "${GREEN}  ✓ PASS${NC} (${duration}s)"

    # Run after_each hook if defined
    if [[ -n "$AFTER_EACH_HOOK" ]]; then
        eval "$AFTER_EACH_HOOK"
    fi
}

test_fail() {
    local message="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$TEST_CASE_NAME: $message")
    local duration=$(($(date +%s) - TEST_START_TIME))
    echo -e "${RED}  ✗ FAIL${NC} (${duration}s)"
    echo -e "${RED}    $message${NC}"

    # Run after_each hook if defined
    if [[ -n "$AFTER_EACH_HOOK" ]]; then
        eval "$AFTER_EACH_HOOK"
    fi
}

test_skip() {
    local reason="$1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    SKIPPED_TESTS+=("$TEST_CASE_NAME: $reason")
    echo -e "${YELLOW}  ⊘ SKIP${NC} - $reason"
}

skip_if() {
    local condition="$1"
    local reason="$2"

    if eval "$condition"; then
        test_skip "$reason"
        return 0
    fi
    return 1
}

#==============================================================================
# Hooks
#==============================================================================

before_each() {
    BEFORE_EACH_HOOK="$1"
}

after_each() {
    AFTER_EACH_HOOK="$1"
}

before_all() {
    BEFORE_ALL_HOOK="$1"
}

after_all() {
    AFTER_ALL_HOOK="$1"
}

#==============================================================================
# Basic Assertions
#==============================================================================

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values not equal}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        test_fail "$message\n      Expected: $expected\n      Actual:   $actual"
        return 1
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"

    if [[ "$not_expected" != "$actual" ]]; then
        return 0
    else
        test_fail "$message\n      Both values: $actual"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String not found}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        test_fail "$message\n      Looking for: $needle\n      In: ${haystack:0:100}..."
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not be found}"

    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        test_fail "$message\n      Found unwanted: $needle"
        return 1
    fi
}

assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-Pattern not matched}"

    if [[ "$string" =~ $pattern ]]; then
        return 0
    else
        test_fail "$message\n      Pattern: $pattern\n      String: ${string:0:100}..."
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Condition is false}"

    if eval "$condition"; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local message="${2:-Condition is true}"

    if ! eval "$condition"; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

#==============================================================================
# File Assertions
#==============================================================================

assert_file_exists() {
    local file="$1"
    local message="${2:-File does not exist: $file}"

    if [[ -f "$file" ]]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local message="${2:-File should not exist: $file}"

    if [[ ! -f "$file" ]]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-Pattern not found in file: $file}"

    if [[ ! -f "$file" ]]; then
        test_fail "File does not exist: $file"
        return 1
    fi

    if grep -q "$pattern" "$file"; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory does not exist: $dir}"

    if [[ -d "$dir" ]]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

#==============================================================================
# Exit Code Assertions
#==============================================================================

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Exit code mismatch}"

    if [[ "$expected" -eq "$actual" ]]; then
        return 0
    else
        test_fail "$message\n      Expected: $expected\n      Actual:   $actual"
        return 1
    fi
}

assert_success() {
    local exit_code="$1"
    local message="${2:-Command failed}"

    assert_exit_code 0 "$exit_code" "$message"
}

assert_failure() {
    local exit_code="$1"
    local message="${2:-Command should have failed}"

    if [[ "$exit_code" -ne 0 ]]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

#==============================================================================
# JSON Assertions
#==============================================================================

assert_json_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-JSON values not equal}"

    # Normalize JSON (remove whitespace differences)
    local norm_expected=$(echo "$expected" | tr -d '[:space:]')
    local norm_actual=$(echo "$actual" | tr -d '[:space:]')

    if [[ "$norm_expected" == "$norm_actual" ]]; then
        return 0
    else
        test_fail "$message\n      Expected: $expected\n      Actual:   $actual"
        return 1
    fi
}

assert_json_contains() {
    local json="$1"
    local key="$2"
    local expected_value="$3"
    local message="${4:-JSON key not found or value mismatch}"

    # Simple grep-based check (for basic cases)
    # In production, use jq for proper JSON parsing
    if echo "$json" | grep -q "\"$key\".*:.*\"$expected_value\""; then
        return 0
    else
        test_fail "$message\n      Key: $key\n      Expected value: $expected_value"
        return 1
    fi
}

#==============================================================================
# Performance Assertions
#==============================================================================

assert_within_time() {
    local max_seconds="$1"
    local command="$2"
    local message="${3:-Command took too long}"

    local start_time=$(date +%s)
    eval "$command" >/dev/null 2>&1
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ "$duration" -le "$max_seconds" ]]; then
        return 0
    else
        test_fail "$message\n      Max time: ${max_seconds}s\n      Actual:   ${duration}s"
        return 1
    fi
}

#==============================================================================
# Mock Infrastructure
#==============================================================================

mock_command() {
    local command_name="$1"
    local mock_script="$2"

    # Create mock executable
    local mock_path="$MOCK_BIN_DIR/$command_name"
    cat > "$mock_path" <<EOF
#!/bin/bash
# Mock for $command_name
# Log invocation
echo "\$(date +%s) \$@" >> "$TEST_TMP_DIR/mock_${command_name}_calls.log"

# Increment call count
count=0
if [[ -f "$TEST_TMP_DIR/mock_${command_name}_count" ]]; then
    count=\$(cat "$TEST_TMP_DIR/mock_${command_name}_count")
fi
count=\$((count + 1))
echo "\$count" > "$TEST_TMP_DIR/mock_${command_name}_count"

# Execute mock script
$mock_script
EOF
    chmod +x "$mock_path"

    # Prepend mock directory to PATH
    export PATH="$MOCK_BIN_DIR:$PATH"

    # Initialize call count
    echo "0" > "$TEST_TMP_DIR/mock_${command_name}_count"
}

unmock_command() {
    local command_name="$1"

    # Remove mock
    rm -f "$MOCK_BIN_DIR/$command_name"

    # Clean up tracking files
    rm -f "$TEST_TMP_DIR/mock_${command_name}_calls.log"
    rm -f "$TEST_TMP_DIR/mock_${command_name}_count"
}

assert_mock_called() {
    local command_name="$1"
    local expected_times="${2:-1}"
    local message="${3:-Mock not called expected number of times}"

    local count_file="$TEST_TMP_DIR/mock_${command_name}_count"
    if [[ ! -f "$count_file" ]]; then
        test_fail "Mock $command_name was never set up"
        return 1
    fi

    local actual_count=$(cat "$count_file")
    if [[ "$actual_count" -eq "$expected_times" ]]; then
        return 0
    else
        test_fail "$message\n      Expected: $expected_times calls\n      Actual:   $actual_count calls"
        return 1
    fi
}

assert_mock_called_with() {
    local command_name="$1"
    local expected_args="$2"
    local message="${3:-Mock not called with expected arguments}"

    local log_file="$TEST_TMP_DIR/mock_${command_name}_calls.log"
    if [[ ! -f "$log_file" ]]; then
        test_fail "Mock $command_name has no call log"
        return 1
    fi

    if grep -q "$expected_args" "$log_file"; then
        return 0
    else
        test_fail "$message\n      Expected args: $expected_args\n      Calls:\n$(cat "$log_file")"
        return 1
    fi
}

get_mock_call_args() {
    local command_name="$1"
    local call_number="${2:-1}"

    local log_file="$TEST_TMP_DIR/mock_${command_name}_calls.log"
    if [[ ! -f "$log_file" ]]; then
        echo ""
        return 1
    fi

    sed -n "${call_number}p" "$log_file" | cut -d' ' -f2-
}

#==============================================================================
# Fixture Management
#==============================================================================

load_fixture() {
    local fixture_name="$1"
    local fixtures_dir="${FIXTURES_DIR:-$(dirname "$0")/../fixtures}"
    local fixture_path="$fixtures_dir/$fixture_name"

    if [[ -f "$fixture_path" ]]; then
        cat "$fixture_path"
    else
        echo "ERROR: Fixture not found: $fixture_path" >&2
        return 1
    fi
}

create_temp_file() {
    local content="$1"
    local filename="${2:-temp_$$_$RANDOM.txt}"

    local temp_file="$TEST_TMP_DIR/$filename"
    echo "$content" > "$temp_file"
    echo "$temp_file"
}

#==============================================================================
# Test Report Generation
#==============================================================================

test_summary() {
    local suite_duration=$(($(date +%s) - TEST_SUITE_START_TIME))

    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test Summary: $TEST_SUITE_NAME${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Total:   $TESTS_TOTAL"
    echo -e "${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo -e "Duration: ${suite_duration}s"

    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo -e "\n${RED}Failed Tests:${NC}"
        for failed in "${FAILED_TESTS[@]}"; do
            echo -e "${RED}  • $failed${NC}"
        done
    fi

    if [[ ${#SKIPPED_TESTS[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}Skipped Tests:${NC}"
        for skipped in "${SKIPPED_TESTS[@]}"; do
            echo -e "${YELLOW}  • $skipped${NC}"
        done
    fi

    # Run after_all hook if defined
    if [[ -n "$AFTER_ALL_HOOK" ]]; then
        eval "$AFTER_ALL_HOOK"
    fi

    # Cleanup
    cleanup_test_environment

    # Exit with failure if any tests failed
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

generate_junit_xml() {
    local output_file="${1:-test-results.xml}"
    local suite_duration=$(($(date +%s) - TEST_SUITE_START_TIME))

    cat > "$output_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="$TEST_SUITE_NAME" tests="$TESTS_TOTAL" failures="$TESTS_FAILED" skipped="$TESTS_SKIPPED" time="$suite_duration">
EOF

    # Add test cases (simplified - in production, track each test individually)
    for failed in "${FAILED_TESTS[@]}"; do
        cat >> "$output_file" <<EOF
  <testcase name="$failed" time="0">
    <failure message="Test failed">$failed</failure>
  </testcase>
EOF
    done

    echo "</testsuite>" >> "$output_file"

    echo -e "\n${BLUE}JUnit XML report written to: $output_file${NC}"
}

#==============================================================================
# Cleanup
#==============================================================================

cleanup_test_environment() {
    # Remove temporary directories (includes all mocks)
    if [[ -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_test_environment EXIT

#==============================================================================
# Helper Functions
#==============================================================================

run_test() {
    local test_function="$1"
    test_case "$test_function"

    if $test_function; then
        test_pass
    else
        # test_fail already called within test function
        :
    fi
}

# Export functions for use in test scripts
export -f test_suite test_case test_pass test_fail test_skip skip_if
export -f before_each after_each before_all after_all
export -f assert_equals assert_not_equals assert_contains assert_not_contains
export -f assert_matches assert_true assert_false
export -f assert_file_exists assert_file_not_exists assert_file_contains assert_dir_exists
export -f assert_exit_code assert_success assert_failure
export -f assert_json_equals assert_json_contains
export -f assert_within_time
export -f mock_command unmock_command assert_mock_called assert_mock_called_with get_mock_call_args
export -f load_fixture create_temp_file
export -f test_summary generate_junit_xml cleanup_test_environment run_test
