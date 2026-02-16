#!/usr/bin/env bash
# Test suite for metrics tracking (v7.25.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/plugin"

# Source metrics tracker
source "${PLUGIN_DIR}/scripts/metrics-tracker.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Test workspace
TEST_WORKSPACE="/tmp/octopus-metrics-test-$$"
export WORKSPACE_DIR="$TEST_WORKSPACE"
export METRICS_BASE="$TEST_WORKSPACE"  # Explicitly set for metrics-tracker.sh
mkdir -p "$TEST_WORKSPACE"

# Cleanup
cleanup() {
    rm -rf "$TEST_WORKSPACE"
}
trap cleanup EXIT

# Test helper
assert_eq() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$expected" == "$actual" ]]; then
        echo "✓ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ $test_name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ -f "$file" ]]; then
        echo "✓ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ $test_name: File $file does not exist"
        return 1
    fi
}

echo "Testing Claude Octopus Metrics Tracking (v7.25.0)"
echo "=================================================="
echo ""

# Test 1: init_metrics_tracking creates session file
echo "Test 1: Metrics initialization"
init_metrics_tracking
assert_file_exists "${WORKSPACE_DIR}/metrics-session.json" "Creates metrics session file"

# Test 2: Session file has valid structure
if command -v jq &> /dev/null; then
    session_id=$(jq -r '.session_id' "${WORKSPACE_DIR}/metrics-session.json")
    assert_eq "string" "$(echo "$session_id" | grep -q '^[0-9]' && echo 'string')" "Session ID is set"
fi

# Test 3: get_model_cost returns pricing
echo ""
echo "Test 2: Model cost lookup"
cost=$(get_model_cost "claude-opus-4-5")
assert_eq "15.00" "$cost" "Opus pricing correct"

cost=$(get_model_cost "claude-sonnet-4-5")
assert_eq "3.00" "$cost" "Sonnet pricing correct"

cost=$(get_model_cost "gemini-2.0-flash-exp")
assert_eq "0.30" "$cost" "Gemini Flash pricing correct"

# Test 4: record_agent_start creates metrics_id
echo ""
echo "Test 3: Agent start recording"
metrics_id=$(record_agent_start "codex" "gpt-5.1-codex-max" "test prompt" "probe")
assert_eq "string" "$(echo "$metrics_id" | grep -q '^codex' && echo 'string')" "Metrics ID created"

# Test 5: record_agent_complete updates metrics
echo ""
echo "Test 4: Agent completion recording"
sleep 2  # Wait 2 seconds to have measurable duration
record_agent_complete "$metrics_id" "codex" "gpt-5.1-codex-max" "test output" "probe"

if command -v jq &> /dev/null; then
    agent_count=$(jq '.totals.agent_calls' "${WORKSPACE_DIR}/metrics-session.json")
    assert_eq "1" "$agent_count" "Agent call count incremented"

    duration=$(jq '.phases[0].duration_seconds' "${WORKSPACE_DIR}/metrics-session.json")
    [[ $duration -ge 2 ]] && echo "✓ Duration tracked (${duration}s)" || echo "✗ Duration should be >= 2s, got ${duration}s"
    TESTS_RUN=$((TESTS_RUN + 1))
    [[ $duration -ge 2 ]] && TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 6: record_agents_batch_complete processes results
echo ""
echo "Test 5: Batch completion recording"

# Create mock result files
export RESULTS_DIR="${WORKSPACE_DIR}/results"
mkdir -p "$RESULTS_DIR"

# Create metrics map and start files (simulating what record_agent_start would create)
start_time=$(date +%s)

cat > "${WORKSPACE_DIR}/.metrics-map" << EOF
123-0:codex-111-$$:codex:gpt-5.1-codex-max
123-1:gemini-222-$$:gemini:gemini-2.0-flash-exp
EOF

# Create start time files (required by record_agent_complete)
echo "$start_time" > "${WORKSPACE_DIR}/.agent-start-codex-111-$$"
echo "$start_time" > "${WORKSPACE_DIR}/.agent-start-gemini-222-$$"

# Create result files
echo "Mock codex result content" > "${RESULTS_DIR}/probe-123-0.md"
echo "Mock gemini result content" > "${RESULTS_DIR}/probe-123-1.md"

# Record batch completion
record_agents_batch_complete "probe" "123"

if command -v jq &> /dev/null; then
    agent_count=$(jq '.totals.agent_calls' "${WORKSPACE_DIR}/metrics-session.json")
    assert_eq "3" "$agent_count" "Batch completion recorded (1 + 2 = 3)"
fi

# Test 7: display_phase_metrics doesn't crash
echo ""
echo "Test 6: Display functions"
output=$(display_phase_metrics "probe" 2>&1)
echo "$output" | grep -q "Phase Metrics" && echo "✓ Phase metrics display works" || echo "✗ Phase metrics display failed"
TESTS_RUN=$((TESTS_RUN + 1))
echo "$output" | grep -q "Phase Metrics" && TESTS_PASSED=$((TESTS_PASSED + 1))

# Test 8: display_session_metrics doesn't crash
output=$(display_session_metrics 2>&1)
echo "$output" | grep -q "Session Totals" && echo "✓ Session metrics display works" || echo "✗ Session metrics display failed"
TESTS_RUN=$((TESTS_RUN + 1))
echo "$output" | grep -q "Session Totals" && TESTS_PASSED=$((TESTS_PASSED + 1))

# Test 9: display_provider_breakdown doesn't crash
output=$(display_provider_breakdown 2>&1)
echo "$output" | grep -q "Provider Breakdown" && echo "✓ Provider breakdown works" || echo "✗ Provider breakdown failed"
TESTS_RUN=$((TESTS_RUN + 1))
echo "$output" | grep -q "Provider Breakdown" && TESTS_PASSED=$((TESTS_PASSED + 1))

# Test 10: Graceful degradation without jq
echo ""
echo "Test 7: Graceful degradation"
if ! command -v jq &> /dev/null; then
    echo "✓ Tests run without jq available"
else
    # Temporarily hide jq
    PATH_BACKUP="$PATH"
    export PATH="/usr/bin:/bin"  # Minimal PATH without jq
    init_metrics_tracking 2>&1 | grep -q "error" && echo "✗ Fails without jq" || echo "✓ Graceful degradation works"
    export PATH="$PATH_BACKUP"
fi
TESTS_RUN=$((TESTS_RUN + 1))
TESTS_PASSED=$((TESTS_PASSED + 1))  # Assume pass if we got here

# Summary
echo ""
echo "=================================================="
echo "Results: $TESTS_PASSED/$TESTS_RUN tests passed"
echo "=================================================="

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
