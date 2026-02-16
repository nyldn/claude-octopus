#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_FILE="${1:-$SCRIPT_DIR/test-prd-skill.sh}"
MAX_ITERATIONS="${2:-10}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Claude Octopus Fix Loop${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Test: $TEST_FILE"
echo -e "Max iterations: $MAX_ITERATIONS"
echo ""
echo -e "${YELLOW}This will run tests and wait for fixes between iterations.${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop at any time.${NC}"
echo ""

iteration=1
while [[ $iteration -le $MAX_ITERATIONS ]]; do
    echo -e "${BLUE}━━━ Iteration $iteration/$MAX_ITERATIONS ━━━${NC}"
    
    if bash "$TEST_FILE"; then
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}✓ ALL TESTS PASSED on iteration $iteration${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        exit 0
    fi
    
    echo ""
    echo -e "${RED}Tests failed. Waiting for fix...${NC}"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  1. Fix the code in another terminal"
    echo -e "  2. Press ENTER to re-run tests"
    echo -e "  3. Press Ctrl+C to exit"
    echo ""
    
    read -r -p "Press ENTER when ready to re-test: "
    
    iteration=$((iteration + 1))
done

echo -e "${RED}Max iterations ($MAX_ITERATIONS) reached without passing.${NC}"
exit 1
