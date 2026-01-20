#!/bin/bash
# tests/run-all.sh
# Master test runner for Claude Octopus
# Orchestrates all test categories and generates reports

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
CATEGORY="${1:-all}"
VERBOSE="${VERBOSE:-false}"
JUNIT_OUTPUT="${JUNIT_OUTPUT:-test-results.xml}"
PARALLEL="${PARALLEL:-false}"

# Counters
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0

# Arrays for tracking
declare -a FAILED_SUITE_NAMES=()
declare -a ALL_RESULTS=()

#==============================================================================
# Helper Functions
#==============================================================================

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo -e "\n${BLUE}▶ $1${NC}"
}

run_test_suite() {
    local test_file="$1"
    local suite_name=$(basename "$test_file" .sh)

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    print_section "Running: $suite_name"

    if [[ "$VERBOSE" == "true" ]]; then
        bash "$test_file"
        local exit_code=$?
    else
        bash "$test_file" > "/tmp/test_${suite_name}_$$.log" 2>&1
        local exit_code=$?
    fi

    if [[ $exit_code -eq 0 ]]; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo -e "${GREEN}  ✓ PASSED${NC}"
        ALL_RESULTS+=("PASS:$suite_name")
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        FAILED_SUITE_NAMES+=("$suite_name")
        echo -e "${RED}  ✗ FAILED${NC}"
        ALL_RESULTS+=("FAIL:$suite_name")

        if [[ "$VERBOSE" == "false" ]]; then
            echo -e "${YELLOW}  Log: /tmp/test_${suite_name}_$$.log${NC}"
        fi
    fi

    return $exit_code
}

run_category() {
    local category="$1"
    local test_dir="$SCRIPT_DIR/$category"

    if [[ ! -d "$test_dir" ]]; then
        echo -e "${YELLOW}No tests found for category: $category${NC}"
        return 0
    fi

    print_header "Running $category tests"

    local test_files=("$test_dir"/test-*.sh)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No test files found in $category${NC}"
        return 0
    fi

    local failed=0
    for test_file in "${test_files[@]}"; do
        if [[ -f "$test_file" ]]; then
            run_test_suite "$test_file" || failed=1
        fi
    done

    return $failed
}

#==============================================================================
# Test Execution
#==============================================================================

run_benchmark() {
    local mode="${1:-demo}"

    if [[ "$mode" == "real" ]]; then
        print_header "Running REAL Execution Benchmark"
        echo -e "${RED}⚠️  WARNING: This will make real API calls and incur costs!${NC}"
        echo -e "${YELLOW}This compares actual execution with live agents${NC}\n"

        local benchmark_script="$SCRIPT_DIR/benchmark/real-execution-benchmark.sh"

        if [[ ! -f "$benchmark_script" ]]; then
            echo -e "${RED}ERROR: Real benchmark script not found${NC}"
            echo "Expected: $benchmark_script"
            return 1
        fi

        bash "$benchmark_script"
    else
        print_header "Running Plugin Value Demonstration"
        echo -e "${YELLOW}This will demonstrate Claude Code baseline vs Claude Code + Octopus Plugin${NC}"
        echo -e "${YELLOW}Based on architectural analysis and validated test results${NC}"
        echo -e "${CYAN}For real execution benchmark with API costs, use: benchmark-real${NC}\n"

        local benchmark_script="$SCRIPT_DIR/benchmark/demo-plugin-value.sh"

        if [[ ! -f "$benchmark_script" ]]; then
            echo -e "${RED}ERROR: Benchmark script not found${NC}"
            echo "Expected: $benchmark_script"
            return 1
        fi

        bash "$benchmark_script"
    fi

    return $?
}

run_tests() {
    local start_time=$(date +%s)

    case "$CATEGORY" in
        smoke)
            run_category "smoke"
            ;;
        unit)
            run_category "unit"
            ;;
        integration)
            run_category "integration"
            ;;
        e2e)
            run_category "e2e"
            ;;
        live)
            run_category "live"
            ;;
        performance)
            run_category "performance"
            ;;
        regression)
            run_category "regression"
            ;;
        benchmark)
            run_benchmark "demo"
            return $?
            ;;
        benchmark-real)
            run_benchmark "real"
            return $?
            ;;
        all)
            print_header "Claude Octopus Test Suite"
            echo -e "Running all test categories\n"

            run_category "smoke"
            run_category "unit"
            run_category "integration"
            run_category "e2e"
            ;;
        --category=*)
            local cat="${CATEGORY#*=}"
            run_category "$cat"
            ;;
        *)
            echo -e "${RED}Unknown category: $CATEGORY${NC}"
            echo "Usage: $0 [smoke|unit|integration|e2e|performance|regression|benchmark|all]"
            exit 1
            ;;
    esac

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    print_summary "$duration"
}

#==============================================================================
# Summary and Reporting
#==============================================================================

print_summary() {
    local duration="$1"

    echo ""
    print_header "Test Summary"

    echo -e "Total test suites:   $TOTAL_SUITES"
    echo -e "${GREEN}Passed:             $PASSED_SUITES${NC}"
    echo -e "${RED}Failed:             $FAILED_SUITES${NC}"
    echo -e "${YELLOW}Skipped:            $SKIPPED_SUITES${NC}"
    echo -e "Duration:            ${duration}s"

    if [[ ${#FAILED_SUITE_NAMES[@]} -gt 0 ]]; then
        echo -e "\n${RED}Failed test suites:${NC}"
        for suite in "${FAILED_SUITE_NAMES[@]}"; do
            echo -e "${RED}  • $suite${NC}"
        done
    fi

    # Generate JUnit XML if requested
    if [[ -n "$JUNIT_OUTPUT" ]]; then
        generate_junit_report "$duration"
    fi

    # Exit with failure if any tests failed
    if [[ $FAILED_SUITES -gt 0 ]]; then
        exit 1
    fi
}

generate_junit_report() {
    local duration="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S")

    cat > "$JUNIT_OUTPUT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Claude Octopus Tests" tests="$TOTAL_SUITES" failures="$FAILED_SUITES" skipped="$SKIPPED_SUITES" time="$duration" timestamp="$timestamp">
  <testsuite name="All Tests" tests="$TOTAL_SUITES" failures="$FAILED_SUITES" skipped="$SKIPPED_SUITES" time="$duration">
EOF

    for result in "${ALL_RESULTS[@]+"${ALL_RESULTS[@]}"}"; do
        local status="${result%%:*}"
        local name="${result#*:}"

        if [[ "$status" == "PASS" ]]; then
            echo "    <testcase name=\"$name\" time=\"0\" />" >> "$JUNIT_OUTPUT"
        elif [[ "$status" == "FAIL" ]]; then
            cat >> "$JUNIT_OUTPUT" <<EOF
    <testcase name="$name" time="0">
      <failure message="Test suite failed">Suite $name failed. Check logs for details.</failure>
    </testcase>
EOF
        fi
    done

    cat >> "$JUNIT_OUTPUT" <<EOF
  </testsuite>
</testsuites>
EOF

    echo -e "\n${BLUE}JUnit XML report: $JUNIT_OUTPUT${NC}"
}

#==============================================================================
# Usage and Help
#==============================================================================

show_help() {
    cat <<EOF
Claude Octopus Test Runner

Usage:
    $0 [CATEGORY] [OPTIONS]

Categories:
    smoke           Fast pre-commit tests (<30s)
    unit            Unit tests for individual functions (1-2min)
    integration     Workflow integration tests (5-10min)
    e2e             End-to-end tests with real APIs (15-30min)
    performance     Performance and benchmark tests
    regression      Version-specific regression tests
    benchmark       Demo comparison (fast, free, based on tests)
    benchmark-real  Real execution comparison (slow, uses API credits!)
    all             Run all test categories (default)

Options:
    --help          Show this help message
    --verbose       Show detailed test output
    --junit=FILE    Generate JUnit XML report (default: test-results.xml)
    --parallel      Run tests in parallel (experimental)

Environment Variables:
    VERBOSE=true    Enable verbose output
    JUNIT_OUTPUT    Path to JUnit XML file

Examples:
    # Run smoke tests only
    $0 smoke

    # Run all tests with verbose output
    VERBOSE=true $0 all

    # Run integration tests and generate report
    $0 integration --junit=integration-results.xml

    # Quick pre-commit check
    $0 smoke unit
EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --junit=*)
                JUNIT_OUTPUT="${1#*=}"
                shift
                ;;
            --parallel)
                PARALLEL=true
                shift
                ;;
            *)
                if [[ -z "$CATEGORY" || "$CATEGORY" == "all" ]]; then
                    CATEGORY="$1"
                fi
                shift
                ;;
        esac
    done

    # Check prerequisites
    if [[ ! -f "$SCRIPT_DIR/helpers/test-framework.sh" ]]; then
        echo -e "${RED}ERROR: Test framework not found${NC}"
        echo "Expected: $SCRIPT_DIR/helpers/test-framework.sh"
        exit 1
    fi

    # Run tests
    run_tests
}

# Handle command line arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        CATEGORY="all"
    else
        CATEGORY="$1"
        shift
    fi

    main "$@"
fi
