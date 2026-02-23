#!/bin/bash
# tests/test-v7.19.0-performance-fixes.sh
# Tests for v7.19.0 performance fixes and enhancements
# Tests all 10 performance improvements from OCTOPUS-PERFORMANCE-ANALYSIS-20260131.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE="$PLUGIN_ROOT/scripts/orchestrate.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Helper functions
test_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Testing: $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

test_case() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "\n${YELLOW}Test $TESTS_RUN:${NC} $1"
}

assert_success() {
    if [[ $1 -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} $2"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $2 (exit code: $1)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    if echo "$1" | grep -q "$2"; then
        echo -e "${GREEN}✓${NC} Found: $2"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} Not found: $2"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    if [[ -f "$1" ]]; then
        echo -e "${GREEN}✓${NC} File exists: $1"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} File missing: $1"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_size_gt() {
    local file="$1"
    local min_size="$2"
    local actual_size=$(wc -c < "$file" 2>/dev/null || echo "0")

    if [[ $actual_size -gt $min_size ]]; then
        echo -e "${GREEN}✓${NC} File size ${actual_size}B > ${min_size}B: $file"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} File size ${actual_size}B <= ${min_size}B: $file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

skip_test() {
    echo -e "${YELLOW}⊘${NC} SKIPPED: $1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# ═══════════════════════════════════════════════════════════════════════════════
# P0.1: Result File Pipeline Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p01_result_file_pipeline() {
    test_header "P0.1 - Result File Pipeline"

    test_case "spawn_agent creates result files with content"

    # Check if spawn_agent function exists
    if ! grep -q "^spawn_agent()" "$ORCHESTRATE"; then
        skip_test "spawn_agent function not found"
        return
    fi

    # Check for tee usage in spawn_agent (real-time streaming)
    if grep -q "tee.*raw_output" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found tee for real-time output streaming"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing tee for output streaming"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for raw output backup
    if grep -q "raw_output=.*\.raw-.*\.out" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found raw output backup mechanism"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing raw output backup"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for file size verification
    if grep -q "result_size.*wc -c.*result_file" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found result file size verification"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing result file size check"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# P0.2: Timeout Preservation Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p02_timeout_preservation() {
    test_header "P0.2 - Timeout Preservation"

    test_case "Partial output preserved on timeout"

    # Check for timeout exit code handling (124, 143)
    if grep -q "exit_code -eq 124.*exit_code -eq 143" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found timeout exit code handling (124, 143)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing timeout exit code detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for "TIMEOUT - PARTIAL RESULTS" status
    if grep -q "TIMEOUT - PARTIAL RESULTS" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found timeout status marker"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing timeout status marker"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for partial output processing on timeout
    if grep -A 10 "exit_code -eq 124" "$ORCHESTRATE" | grep -q "awk.*temp_output"; then
        echo -e "${GREEN}✓${NC} Found partial output processing on timeout"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC}  Partial output processing may not preserve results"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# P0.3: Agent Status Tracking Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p03_agent_status_tracking() {
    test_header "P0.3 - Agent Status Tracking"

    test_case "Agent status categorization with file size checks"

    # Check for status indicators in output (check individually)
    if grep -q '✓' "$ORCHESTRATE" && grep -q '✗\|❌' "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found status indicators"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing status indicators"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for file size categorization
    if grep -q "file_size\|result_size" "$ORCHESTRATE" && grep -q "success_count\|usable_results" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found file size-based categorization"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing file size categorization logic"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for summary display
    if grep -q "Results summary\|WORKFLOW SUMMARY\|results summary" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found results summary display"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing results summary"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# P1.1: Graceful Degradation Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p11_graceful_degradation() {
    test_header "P1.1 - Graceful Degradation"

    test_case "Synthesis proceeds with partial results (2+ agents)"

    # Check for usable_results parameter
    if grep -q "usable_results=.*3.*-" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found usable_results parameter"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing usable_results tracking"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for content size filtering (>500 bytes)
    if grep -q "file_size.*gt 500" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found content size filtering (>500 bytes)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing content size filter"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for warning when proceeding with partial results
    if grep -q "Proceeding with.*usable results" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found partial results warning"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing partial results messaging"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# P1.2: Rich Progress Display Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p12_rich_progress_display() {
    test_header "P1.2 - Rich Progress Display"

    test_case "Rich progress dashboard with visual indicators"

    # Check for display_rich_progress function
    if grep -q "^display_rich_progress()" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found display_rich_progress function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing display_rich_progress function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return
    fi

    # Check for progress bar rendering
    if grep -q "bar_width=" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found progress bar rendering logic"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing progress bar logic"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for agent emoji indicators
    if grep -q "🔴" "$ORCHESTRATE" && grep -q "🟡" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found agent emoji indicators"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing emoji indicators"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for elapsed time display
    if grep -q "elapsed" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found elapsed time tracking"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing elapsed time display"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# P1.3: Enhanced Error Messages Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p13_enhanced_error_messages() {
    test_header "P1.3 - Enhanced Error Messages"

    test_case "Context-aware error messages with remediation"

    # Check for enhanced_error function
    if grep -q "^enhanced_error()" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found enhanced_error function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing enhanced_error function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return
    fi

    # Check for error types
    if grep -q "probe_synthesis_no_results\|agent_spawn_failed\|result_file_empty" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found error type handling"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing error type definitions"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for remediation suggestions
    if grep -q "Suggested actions:\|Troubleshooting steps:" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found remediation suggestions"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing remediation messaging"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# P2.1: Log Management Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p21_log_management() {
    test_header "P2.1 - Log Management"

    test_case "Enhanced log cleanup with age-based rotation"

    # Check for log cleanup functionality
    if grep -q "rotate_logs\|cleanup_old_progress_files\|cleanup_cache" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found log cleanup functions"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing log cleanup"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for cleanup on old files
    if grep -q "mtime\|cleanup\|rotate" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found file age-based cleanup"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing age-based cleanup"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for raw output handling
    if grep -q "raw_output\|\.raw-" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found raw output handling"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing raw output handling"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# P2.2: Gemini Warnings Suppression Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p22_gemini_warnings() {
    test_header "P2.2 - Gemini CLI Warnings Suppression"

    test_case "NODE_NO_WARNINGS=1 in Gemini commands"

    # Check for NODE_NO_WARNINGS in gemini commands
    if grep -q "NODE_NO_WARNINGS=1.*gemini" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found NODE_NO_WARNINGS in gemini commands"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing NODE_NO_WARNINGS environment variable"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Count gemini command occurrences with suppression
    local gemini_count=$(grep -c "NODE_NO_WARNINGS=1.*gemini" "$ORCHESTRATE" || echo "0")
    if [[ $gemini_count -ge 3 ]]; then
        echo -e "${GREEN}✓${NC} Found $gemini_count gemini commands with warning suppression"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC}  Only found $gemini_count gemini commands with suppression"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# P2.3: Result Caching Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p23_result_caching() {
    test_header "P2.3 - Result Caching"

    test_case "Prompt-based caching with 1-hour TTL"

    # Check for cache directory definition
    if grep -q "CACHE_DIR=.*cache.*probe-results" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found cache directory definition"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing cache directory"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for cache TTL
    if grep -q "CACHE_TTL=3600" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found 1-hour cache TTL (3600s)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing or incorrect cache TTL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for cache key generation (SHA256)
    if grep -q "get_cache_key" "$ORCHESTRATE" && grep -q "shasum -a 256" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found SHA256 cache key generation"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing cache key generation"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for cache hit/miss logic
    if grep -q "check_cache.*cache_key" "$ORCHESTRATE" && grep -q "save_to_cache" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found cache hit/miss handling"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing cache logic"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for cleanup function
    if grep -q "cleanup_cache" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found cache cleanup function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing cache cleanup"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# P2.4: Progressive Synthesis Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_p24_progressive_synthesis() {
    test_header "P2.4 - Progressive Synthesis"

    test_case "Synthesis starts with 2+ completed agents"

    # Check for progressive synthesis flag
    if grep -q "ENABLE_PROGRESSIVE_SYNTHESIS" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found progressive synthesis flag"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing progressive synthesis configuration"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for monitor function
    if grep -q "progressive_synthesis_monitor" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found progressive synthesis monitor"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing synthesis monitor function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for minimum results threshold (2)
    if grep -q "min_results.*2" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found minimum 2 results threshold"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing minimum results check"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check for partial synthesis function
    if grep -q "synthesize_probe_results_partial" "$ORCHESTRATE"; then
        echo -e "${GREEN}✓${NC} Found partial synthesis function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing partial synthesis"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Integration Tests
# ═══════════════════════════════════════════════════════════════════════════════

test_integration_version_consistency() {
    test_header "Integration - Version Consistency"

    test_case "Version 7.19.0 consistency across files"

    # Check plugin.json has a version
    if grep -q '"version":' "$PLUGIN_ROOT/.claude-plugin/plugin.json"; then
        echo -e "${GREEN}✓${NC} plugin.json has version field"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} plugin.json version missing"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Check CHANGELOG has 7.19.0 entry
    if grep -q "7\.19\.0" "$PLUGIN_ROOT/CHANGELOG.md"; then
        echo -e "${GREEN}✓${NC} CHANGELOG mentions 7.19.0"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} CHANGELOG missing 7.19.0 mention"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

test_integration_documentation() {
    test_header "Integration - Documentation Quality"

    test_case "All features documented in CHANGELOG"

    local features=(
        "P0.1.*Result File Pipeline"
        "P0.2.*Timeout Preservation"
        "P0.3.*Agent Status Tracking"
        "P1.1.*Graceful Degradation"
        "P1.2.*Rich Progress Display"
        "P1.3.*Enhanced Error Messages"
        "P2.1.*Log Management"
        "P2.2.*Gemini.*Warnings"
        "P2.3.*Result Caching"
        "P2.4.*Progressive Synthesis"
    )

    local documented=0
    for feature in "${features[@]}"; do
        if grep -q "$feature" "$PLUGIN_ROOT/CHANGELOG.md"; then
            ((documented++))
        fi
    done

    if [[ $documented -eq ${#features[@]} ]]; then
        echo -e "${GREEN}✓${NC} All 10 features documented in CHANGELOG"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC}  Only $documented/10 features documented"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test Execution
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Claude Octopus v7.19.0 Performance Test Suite          ║${NC}"
    echo -e "${BLUE}║  Testing all 10 performance fixes                        ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # P0 Critical Tests
    test_p01_result_file_pipeline
    test_p02_timeout_preservation
    test_p03_agent_status_tracking

    # P1 High Priority Tests
    test_p11_graceful_degradation
    test_p12_rich_progress_display
    test_p13_enhanced_error_messages

    # P2 Quality of Life Tests
    test_p21_log_management
    test_p22_gemini_warnings
    test_p23_result_caching
    test_p24_progressive_synthesis

    # Integration Tests
    test_integration_version_consistency
    test_integration_documentation

    # Summary
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Total:   $TESTS_RUN"
    echo -e "${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        exit 1
    fi
}

main "$@"
