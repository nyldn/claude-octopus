#!/usr/bin/env bash
# Run all test suites for Claude Octopus plugin
# This is the main test entry point
#
# Usage:
#   ./run-all-tests.sh [OPTIONS] [--CATEGORY ...]
#
# Categories (combine multiple):
#   --smoke         Tests in smoke/
#   --unit          Tests in unit/
#   --integration   Tests in integration/
#   --root          Root-level test-*.sh and validate-*.sh
#   --live          Tests in live/ (requires real CLIs, opt-in)
#   --all           All categories except live (default)
#   --everything    All categories including live
#
# Options:
#   --fail-fast     Stop on first suite failure
#   --list          List discovered tests without running them

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Track overall results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0
FAIL_FAST=false
LIST_ONLY=false

# Function to run a test suite
run_test_suite() {
    local test_file="$1"
    local test_name
    # Show relative path from tests/ for clarity
    test_name="${test_file#"$SCRIPT_DIR"/}"

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Running: ${test_name}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    if bash "$test_file"; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo ""
        echo -e "${GREEN}  PASS: ${test_name}${NC}"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        echo ""
        echo -e "${RED}  FAIL: ${test_name}${NC}"
        if $FAIL_FAST; then
            echo ""
            echo -e "${YELLOW}--fail-fast: stopping after first failure${NC}"
            print_summary
            exit 1
        fi
    fi
}

# Discover test files in a directory (sorted by name for deterministic order)
discover_tests() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        local files=()
        while IFS= read -r -d '' f; do
            files+=("$f")
        done < <(find "$dir" -maxdepth 1 -name 'test-*.sh' -print0 | sort -z)
        # Also pick up validate-*.sh at root level
        if [[ "$dir" == "$SCRIPT_DIR" ]]; then
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(find "$dir" -maxdepth 1 -name 'validate-*.sh' -print0 | sort -z)
        fi
        printf '%s\n' "${files[@]}"
    fi
}

print_summary() {
    echo ""
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    Final Summary                         ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Total test suites: ${BLUE}$TOTAL_SUITES${NC}"
    echo -e "Passed:            ${GREEN}$PASSED_SUITES${NC}"
    echo -e "Failed:            ${RED}$FAILED_SUITES${NC}"
    if [[ $SKIPPED_SUITES -gt 0 ]]; then
        echo -e "Skipped:           ${YELLOW}$SKIPPED_SUITES${NC}"
    fi
    echo ""

    if [[ $FAILED_SUITES -eq 0 ]]; then
        echo -e "${GREEN}  ALL TESTS PASSED  ${NC}"
    else
        echo -e "${RED}  SOME TESTS FAILED  ${NC}"
    fi
    echo ""
}

# Parse flags
declare -a CATEGORIES=()
for arg in "$@"; do
    case "$arg" in
        --smoke)       CATEGORIES+=("smoke") ;;
        --unit)        CATEGORIES+=("unit") ;;
        --integration) CATEGORIES+=("integration") ;;
        --root)        CATEGORIES+=("root") ;;
        --live)        CATEGORIES+=("live") ;;
        --regression)  CATEGORIES+=("root") ;;  # backward compat
        --e2e)         CATEGORIES+=("integration") ;;  # backward compat
        --performance) CATEGORIES+=("live") ;;  # backward compat
        --all)         CATEGORIES=("smoke" "unit" "integration" "root") ;;
        --everything)  CATEGORIES=("smoke" "unit" "integration" "root" "live") ;;
        --fail-fast)   FAIL_FAST=true ;;
        --list)        LIST_ONLY=true ;;
        *)
            echo -e "${YELLOW}Unknown flag '$arg', ignoring${NC}" ;;
    esac
done

# Default to --all if no categories specified
if [[ ${#CATEGORIES[@]} -eq 0 ]]; then
    CATEGORIES=("smoke" "unit" "integration" "root")
fi

# Deduplicate categories while preserving order
declare -a UNIQUE_CATS=()
for cat in "${CATEGORIES[@]}"; do
    local_dup=false
    for seen in "${UNIQUE_CATS[@]+"${UNIQUE_CATS[@]}"}"; do
        if [[ "$seen" == "$cat" ]]; then
            local_dup=true
            break
        fi
    done
    if ! $local_dup; then
        UNIQUE_CATS+=("$cat")
    fi
done
CATEGORIES=("${UNIQUE_CATS[@]}")

# Build test list from categories via auto-discovery
declare -a TEST_SUITES=()
for cat in "${CATEGORIES[@]}"; do
    case "$cat" in
        smoke)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR/smoke")
            ;;
        unit)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR/unit")
            ;;
        integration)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR/integration")
            ;;
        root)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR")
            ;;
        live)
            while IFS= read -r f; do
                [[ -n "$f" ]] && TEST_SUITES+=("$f")
            done < <(discover_tests "$SCRIPT_DIR/live")
            ;;
    esac
done

if [[ ${#TEST_SUITES[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No test files discovered for categories: ${CATEGORIES[*]}${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Claude Octopus Test Suite                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Categories:${NC} ${CATEGORIES[*]}"
echo -e "${BLUE}Discovered:${NC} ${#TEST_SUITES[@]} test suites"
if $FAIL_FAST; then
    echo -e "${BLUE}Fail-fast:${NC} enabled"
fi
echo ""
echo -e "${BLUE}Suites:${NC}"
for suite in "${TEST_SUITES[@]}"; do
    echo "  - ${suite#"$SCRIPT_DIR"/}"
done

if $LIST_ONLY; then
    echo ""
    echo -e "${BLUE}(--list mode: not executing)${NC}"
    exit 0
fi

# Make discovered test scripts executable
for suite in "${TEST_SUITES[@]}"; do
    chmod +x "$suite"
done

for suite in "${TEST_SUITES[@]}"; do
    run_test_suite "$suite"
done

print_summary

if [[ $FAILED_SUITES -gt 0 ]]; then
    exit 1
fi
