#!/bin/bash
# tests/helpers/live-test-harness.sh
# Live testing harness for Claude Code plugin features
#
# This harness runs actual Claude Code sessions to test plugin behavior.
# Use for features that can't be tested with mocks (skill loading, natural language triggers, etc.)
#
# USAGE:
#   source tests/helpers/live-test-harness.sh
#   
#   # Run a test
#   live_test "My Test Name" "octo design a PRD for X" \
#     --timeout 120 \
#     --expect "Phase 1" \
#     --reject "Skill.*loaded.*Skill.*loaded.*Skill.*loaded" \
#     --max-skill-loads 2

set -euo pipefail

#==============================================================================
# Configuration
#==============================================================================

LIVE_TEST_DIR="${LIVE_TEST_DIR:-/tmp/claude-octopus-live-tests}"
LIVE_TEST_TIMEOUT="${LIVE_TEST_TIMEOUT:-120}"
LIVE_TEST_LOG_DIR="${LIVE_TEST_LOG_DIR:-$LIVE_TEST_DIR/logs}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
LIVE_TESTS_RUN=0
LIVE_TESTS_PASSED=0
LIVE_TESTS_FAILED=0

# Results
declare -a LIVE_TEST_RESULTS=()

#==============================================================================
# Setup
#==============================================================================

live_test_setup() {
    mkdir -p "$LIVE_TEST_DIR"
    mkdir -p "$LIVE_TEST_LOG_DIR"
    
    # Check if Claude is available
    if ! command -v "$CLAUDE_BIN" &> /dev/null; then
        echo -e "${RED}ERROR: Claude CLI not found at '$CLAUDE_BIN'${NC}"
        echo "Install Claude Code or set CLAUDE_BIN environment variable"
        return 1
    fi
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Claude Octopus Live Test Harness${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Log directory: $LIVE_TEST_LOG_DIR"
    echo -e "Timeout: ${LIVE_TEST_TIMEOUT}s"
    echo ""
}

#==============================================================================
# Core Test Function
#==============================================================================

# Run a live test against Claude Code
# 
# Arguments:
#   $1 - Test name
#   $2 - Prompt to send to Claude
#   
# Options:
#   --timeout N          - Timeout in seconds (default: 120)
#   --expect PATTERN     - Regex pattern that MUST appear in output (can repeat)
#   --reject PATTERN     - Regex pattern that must NOT appear (can repeat)
#   --max-skill-loads N  - Maximum allowed Skill() loads (default: unlimited)
#   --workdir DIR        - Working directory for Claude (default: current)
#   --env KEY=VALUE      - Environment variable to set (can repeat)
#
# Returns:
#   0 on success, 1 on failure
#
live_test() {
    local test_name="$1"
    local prompt="$2"
    shift 2
    
    # Parse options
    local timeout="$LIVE_TEST_TIMEOUT"
    local workdir="${PWD}"
    local -a expect_patterns=()
    local -a reject_patterns=()
    local max_skill_loads=""
    local -a env_vars=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --expect)
                expect_patterns+=("$2")
                shift 2
                ;;
            --reject)
                reject_patterns+=("$2")
                shift 2
                ;;
            --max-skill-loads)
                max_skill_loads="$2"
                shift 2
                ;;
            --workdir)
                workdir="$2"
                shift 2
                ;;
            --env)
                env_vars+=("$2")
                shift 2
                ;;
            *)
                echo -e "${YELLOW}Warning: Unknown option: $1${NC}"
                shift
                ;;
        esac
    done
    
    LIVE_TESTS_RUN=$((LIVE_TESTS_RUN + 1))
    
    local test_id=$(date +%s%N | md5sum | head -c 8)
    local log_file="$LIVE_TEST_LOG_DIR/${test_id}-${test_name// /-}.log"
    
    echo -e "${BLUE}▶ Running: ${NC}${test_name}"
    echo -e "  ${CYAN}Prompt:${NC} ${prompt:0:60}..."
    
    # Build environment
    local env_prefix=""
    for ev in "${env_vars[@]+"${env_vars[@]}"}"; do
        env_prefix="$ev $env_prefix"
    done
    
    # Run Claude with timeout
    local exit_code=0
    local start_time=$(date +%s)
    
    cd "$workdir"
    
    # Use script to capture output with pseudo-terminal
    if command -v script &> /dev/null; then
        # macOS/BSD script
        if [[ "$(uname)" == "Darwin" ]]; then
            timeout "$timeout" script -q "$log_file" \
                $CLAUDE_BIN --dangerously-skip-permissions -p "$prompt" 2>&1 || exit_code=$?
        else
            # Linux script
            timeout "$timeout" script -q -c \
                "$CLAUDE_BIN --dangerously-skip-permissions -p \"$prompt\"" "$log_file" 2>&1 || exit_code=$?
        fi
    else
        # Fallback without script
        echo "$prompt" | timeout "$timeout" \
            $CLAUDE_BIN --dangerously-skip-permissions 2>&1 | tee "$log_file" || exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Read output
    local output=""
    if [[ -f "$log_file" ]]; then
        output=$(cat "$log_file" 2>/dev/null || echo "")
    fi
    
    # Check for timeout
    if [[ $exit_code -eq 124 ]]; then
        echo -e "  ${RED}✗ FAILED: Timed out after ${timeout}s${NC}"
        echo -e "  ${YELLOW}Log: $log_file${NC}"
        LIVE_TESTS_FAILED=$((LIVE_TESTS_FAILED + 1))
        LIVE_TEST_RESULTS+=("FAIL:$test_name:Timeout after ${timeout}s")
        return 1
    fi
    
    # Check expect patterns
    for pattern in "${expect_patterns[@]+"${expect_patterns[@]}"}"; do
        if ! echo "$output" | grep -qE "$pattern"; then
            echo -e "  ${RED}✗ FAILED: Expected pattern not found: $pattern${NC}"
            echo -e "  ${YELLOW}Log: $log_file${NC}"
            LIVE_TESTS_FAILED=$((LIVE_TESTS_FAILED + 1))
            LIVE_TEST_RESULTS+=("FAIL:$test_name:Missing pattern: $pattern")
            return 1
        fi
    done
    
    # Check reject patterns
    for pattern in "${reject_patterns[@]+"${reject_patterns[@]}"}"; do
        if echo "$output" | grep -qE "$pattern"; then
            echo -e "  ${RED}✗ FAILED: Rejected pattern found: $pattern${NC}"
            echo -e "  ${YELLOW}Log: $log_file${NC}"
            LIVE_TESTS_FAILED=$((LIVE_TESTS_FAILED + 1))
            LIVE_TEST_RESULTS+=("FAIL:$test_name:Found rejected pattern: $pattern")
            return 1
        fi
    done
    
    # Check skill load count
    if [[ -n "$max_skill_loads" ]]; then
        local skill_count=$(echo "$output" | grep -c "Skill(" || echo "0")
        if [[ $skill_count -gt $max_skill_loads ]]; then
            echo -e "  ${RED}✗ FAILED: Too many skill loads: $skill_count (max: $max_skill_loads)${NC}"
            echo -e "  ${YELLOW}Log: $log_file${NC}"
            LIVE_TESTS_FAILED=$((LIVE_TESTS_FAILED + 1))
            LIVE_TEST_RESULTS+=("FAIL:$test_name:Skill loaded $skill_count times (max: $max_skill_loads)")
            return 1
        fi
    fi
    
    echo -e "  ${GREEN}✓ PASSED${NC} (${duration}s)"
    LIVE_TESTS_PASSED=$((LIVE_TESTS_PASSED + 1))
    LIVE_TEST_RESULTS+=("PASS:$test_name:${duration}s")
    return 0
}

#==============================================================================
# Utility Functions
#==============================================================================

# Count pattern occurrences in last test output
live_test_count_pattern() {
    local pattern="$1"
    local log_file=$(ls -t "$LIVE_TEST_LOG_DIR"/*.log 2>/dev/null | head -1)
    
    if [[ -f "$log_file" ]]; then
        grep -c "$pattern" "$log_file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get last test output
live_test_get_output() {
    local log_file=$(ls -t "$LIVE_TEST_LOG_DIR"/*.log 2>/dev/null | head -1)
    
    if [[ -f "$log_file" ]]; then
        cat "$log_file"
    fi
}

# Run test and retry on failure
live_test_with_retry() {
    local max_retries="${1:-3}"
    shift
    
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        if live_test "$@"; then
            return 0
        fi
        
        echo -e "  ${YELLOW}Retrying ($attempt/$max_retries)...${NC}"
        attempt=$((attempt + 1))
        sleep 2
    done
    
    return 1
}

#==============================================================================
# Summary
#==============================================================================

live_test_summary() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Live Test Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Total:   $LIVE_TESTS_RUN"
    echo -e "${GREEN}Passed:  $LIVE_TESTS_PASSED${NC}"
    echo -e "${RED}Failed:  $LIVE_TESTS_FAILED${NC}"
    echo ""
    
    if [[ $LIVE_TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed tests:${NC}"
        for result in "${LIVE_TEST_RESULTS[@]}"; do
            if [[ "$result" == FAIL:* ]]; then
                local name=$(echo "$result" | cut -d: -f2)
                local reason=$(echo "$result" | cut -d: -f3-)
                echo -e "  ${RED}• $name${NC}: $reason"
            fi
        done
        echo ""
        echo -e "Logs: $LIVE_TEST_LOG_DIR"
        return 1
    fi
    
    return 0
}

#==============================================================================
# Cleanup
#==============================================================================

live_test_cleanup() {
    if [[ -d "$LIVE_TEST_DIR" ]]; then
        # Keep logs but clean temp files
        find "$LIVE_TEST_DIR" -name "*.tmp" -delete 2>/dev/null || true
    fi
}

# Auto-setup if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    live_test_setup
fi
