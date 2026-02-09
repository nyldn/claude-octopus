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

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    if bash "$test_file"; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo ""
        echo -e "${GREEN}✅ Suite passed: ${test_name}${NC}"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        echo ""
        echo -e "${RED}❌ Suite failed: ${test_name}${NC}"
    fi
}

# Make all test scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

# Parse category flag (compatible with run-all.sh wrapper)
category="all"
for arg in "$@"; do
    case "$arg" in
        --smoke) category="smoke" ;;
        --unit) category="unit" ;;
        --integration) category="integration" ;;
        --e2e) category="e2e" ;;
        --live) category="live" ;;
        --performance) category="performance" ;;
        --regression) category="regression" ;;
        --all) category="all" ;;
    esac
done

declare -a TEST_SUITES=()
case "$category" in
    smoke)
        TEST_SUITES=(
            "$SCRIPT_DIR/validate-plugin-name.sh"
            "$SCRIPT_DIR/test-command-registration.sh"
            "$SCRIPT_DIR/test-version-consistency.sh"
        )
        ;;
    unit)
        TEST_SUITES=(
            "$SCRIPT_DIR/validate-plugin-name.sh"
            "$SCRIPT_DIR/test-command-registration.sh"
            "$SCRIPT_DIR/test-multi-command.sh"
            "$SCRIPT_DIR/test-intent-questions.sh"
            "$SCRIPT_DIR/test-plan-command.sh"
            "$SCRIPT_DIR/test-intent-contract-skill.sh"
            "$SCRIPT_DIR/test-enforcement-pattern.sh"
            "$SCRIPT_DIR/test-version-consistency.sh"
        )
        ;;
    integration|regression|all)
        TEST_SUITES=(
            "$SCRIPT_DIR/validate-plugin-name.sh"
            "$SCRIPT_DIR/test-command-registration.sh"
            "$SCRIPT_DIR/test-multi-command.sh"
            "$SCRIPT_DIR/test-intent-questions.sh"
            "$SCRIPT_DIR/test-plan-command.sh"
            "$SCRIPT_DIR/test-intent-contract-skill.sh"
            "$SCRIPT_DIR/test-enforcement-pattern.sh"
            "$SCRIPT_DIR/test-version-consistency.sh"
            "$SCRIPT_DIR/test-v8.0.0-opus-integration.sh"
            "$SCRIPT_DIR/test-v8.1.0-feature-detection.sh"
            "$SCRIPT_DIR/test-v8.2.0-agent-fields.sh"
            "$SCRIPT_DIR/test-v8.5.0-strategic-features.sh"
        )
        ;;
    e2e|live|performance)
        # No dedicated suites yet; default to integration coverage.
        TEST_SUITES=(
            "$SCRIPT_DIR/test-v8.0.0-opus-integration.sh"
            "$SCRIPT_DIR/test-v8.1.0-feature-detection.sh"
            "$SCRIPT_DIR/test-v8.2.0-agent-fields.sh"
            "$SCRIPT_DIR/test-v8.5.0-strategic-features.sh"
        )
        ;;
    *)
        echo -e "${YELLOW}Unknown category '$category', defaulting to all${NC}"
        TEST_SUITES=(
            "$SCRIPT_DIR/validate-plugin-name.sh"
            "$SCRIPT_DIR/test-command-registration.sh"
            "$SCRIPT_DIR/test-multi-command.sh"
            "$SCRIPT_DIR/test-intent-questions.sh"
            "$SCRIPT_DIR/test-plan-command.sh"
            "$SCRIPT_DIR/test-intent-contract-skill.sh"
            "$SCRIPT_DIR/test-enforcement-pattern.sh"
            "$SCRIPT_DIR/test-version-consistency.sh"
            "$SCRIPT_DIR/test-v8.0.0-opus-integration.sh"
            "$SCRIPT_DIR/test-v8.1.0-feature-detection.sh"
            "$SCRIPT_DIR/test-v8.2.0-agent-fields.sh"
            "$SCRIPT_DIR/test-v8.5.0-strategic-features.sh"
        )
        ;;
esac

echo -e "${BLUE}Selected category:${NC} $category"
echo -e "${BLUE}Planned suites:${NC}"
for suite in "${TEST_SUITES[@]}"; do
    echo "  - $(basename "$suite")"
done

for suite in "${TEST_SUITES[@]}"; do
    run_test_suite "$suite"
done

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
