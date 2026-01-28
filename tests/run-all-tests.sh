#!/usr/bin/env bash
# Run all test suites for Claude Octopus plugin
# This is the main test entry point

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}║          🐙 Claude Octopus Test Suite                   ║${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Track overall results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# Function to run a test suite
run_test_suite() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Running: ${test_name}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    ((TOTAL_SUITES++))

    if bash "$test_file"; then
        ((PASSED_SUITES++))
        echo ""
        echo -e "${GREEN}✅ Suite passed: ${test_name}${NC}"
    else
        ((FAILED_SUITES++))
        echo ""
        echo -e "${RED}❌ Suite failed: ${test_name}${NC}"
    fi
}

# Make all test scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

# Run all test suites in order
echo -e "${BLUE}Found test suites:${NC}"
for test_file in "$SCRIPT_DIR"/test-*.sh; do
    if [[ -f "$test_file" ]]; then
        echo "  - $(basename "$test_file")"
    fi
done

# Run tests in priority order
run_test_suite "$SCRIPT_DIR/validate-plugin-name.sh"
run_test_suite "$SCRIPT_DIR/test-command-registration.sh"
run_test_suite "$SCRIPT_DIR/test-multi-command.sh"
run_test_suite "$SCRIPT_DIR/test-intent-questions.sh"
run_test_suite "$SCRIPT_DIR/test-plan-command.sh"
run_test_suite "$SCRIPT_DIR/test-intent-contract-skill.sh"
run_test_suite "$SCRIPT_DIR/test-enforcement-pattern.sh"
run_test_suite "$SCRIPT_DIR/test-version-consistency.sh"

# Final summary
echo ""
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}║                    Final Summary                         ║${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Total test suites: ${BLUE}$TOTAL_SUITES${NC}"
echo -e "Passed:            ${GREEN}$PASSED_SUITES${NC}"
echo -e "Failed:            ${RED}$FAILED_SUITES${NC}"
echo ""

if [[ $FAILED_SUITES -eq 0 ]]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}║              ✅ ALL TESTS PASSED! ✅                     ║${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                          ║${NC}"
    echo -e "${RED}║              ❌ SOME TESTS FAILED ❌                     ║${NC}"
    echo -e "${RED}║                                                          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
fi
