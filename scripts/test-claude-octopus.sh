#!/bin/bash
# test-claude-octopus.sh - Comprehensive test suite for Claude Octopus
# Run with: ./scripts/test-claude-octopus.sh

set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/orchestrate.sh"
PASS=0
FAIL=0
SKIP=0

# Test function
test_cmd() {
    local name="$1"
    local cmd="$2"
    local expect_exit="${3:-0}"  # 0 = expect success, 1 = expect failure

    echo -n "  $name... "

    output=$(eval "$cmd" 2>&1)
    exit_code=$?

    if [[ "$expect_exit" == "0" ]]; then
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}PASS${NC}"
            ((PASS++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (exit code: $exit_code)"
            echo "    Output: ${output:0:200}"
            ((FAIL++))
            return 1
        fi
    else
        if [[ $exit_code -ne 0 ]]; then
            echo -e "${GREEN}PASS${NC} (expected failure)"
            ((PASS++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (expected failure, got success)"
            ((FAIL++))
            return 1
        fi
    fi
}

# Test function for output validation
test_output() {
    local name="$1"
    local cmd="$2"
    local expect_pattern="$3"

    echo -n "  $name... "

    output=$(eval "$cmd" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]] && echo "$output" | grep -qE "$expect_pattern"; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "    Expected pattern: $expect_pattern"
        echo "    Output: ${output:0:200}"
        ((FAIL++))
        return 1
    fi
}

echo ""
echo "========================================"
echo "  Claude Octopus Test Suite"
echo "========================================"
echo ""

# ============================================
# 1. SYNTAX & BASIC SETUP
# ============================================
echo -e "${YELLOW}1. Syntax & Setup${NC}"

test_cmd "Script syntax check" "bash -n '$SCRIPT'"
test_cmd "Help (simple)" "'$SCRIPT' help"
test_cmd "Help (full)" "'$SCRIPT' help --full"
test_cmd "Help (auto command)" "'$SCRIPT' help auto"
test_cmd "Help (research command)" "'$SCRIPT' help research"
test_cmd "Init workspace" "'$SCRIPT' init"

echo ""

# ============================================
# 2. DRY-RUN: DOUBLE DIAMOND PHASES
# ============================================
echo -e "${YELLOW}2. Dry-Run: Double Diamond Phases${NC}"

test_cmd "Probe (discover)" "'$SCRIPT' -n probe 'test prompt'"
test_cmd "Grasp (define)" "'$SCRIPT' -n grasp 'test prompt'"
test_cmd "Tangle (develop)" "'$SCRIPT' -n tangle 'test prompt'"
test_cmd "Ink (deliver)" "'$SCRIPT' -n ink 'test prompt'"
test_cmd "Embrace (full workflow)" "'$SCRIPT' -n embrace 'test prompt'"

echo ""

# ============================================
# 3. DRY-RUN: COMMAND ALIASES
# ============================================
echo -e "${YELLOW}3. Dry-Run: Command Aliases${NC}"

test_cmd "research (probe alias)" "'$SCRIPT' -n research 'test'"
test_cmd "define (grasp alias)" "'$SCRIPT' -n define 'test'"
test_cmd "develop (tangle alias)" "'$SCRIPT' -n develop 'test'"
test_cmd "deliver (ink alias)" "'$SCRIPT' -n deliver 'test'"

echo ""

# ============================================
# 4. DRY-RUN: SMART AUTO-ROUTING
# ============================================
echo -e "${YELLOW}4. Dry-Run: Smart Auto-Routing${NC}"

test_output "Routes 'research' to probe" "'$SCRIPT' -n auto 'research best practices'" "PROBE|probe|diamond-discover"
test_output "Routes 'define' to grasp" "'$SCRIPT' -n auto 'define requirements for auth'" "GRASP|grasp|diamond-define"
test_output "Routes 'build' to tangle+ink" "'$SCRIPT' -n auto 'build a new feature'" "TANGLE|tangle|diamond-develop"
test_output "Routes 'review' to ink" "'$SCRIPT' -n auto 'review the code'" "INK|ink|diamond-deliver"
test_output "Routes 'design' to gemini" "'$SCRIPT' -n auto 'design a responsive UI'" "gemini|design"
test_output "Routes 'generate icon' to gemini-image" "'$SCRIPT' -n auto 'generate an app icon'" "gemini-image|image"
test_output "Routes 'fix bug' to codex" "'$SCRIPT' -n auto 'fix the null pointer bug'" "codex|coding"

echo ""

# ============================================
# 5. DRY-RUN: AGENT SPAWNING
# ============================================
echo -e "${YELLOW}5. Dry-Run: Agent Spawning${NC}"

test_cmd "Spawn codex" "'$SCRIPT' -n spawn codex 'test'"
test_cmd "Spawn gemini" "'$SCRIPT' -n spawn gemini 'test'"
test_cmd "Spawn codex-mini" "'$SCRIPT' -n spawn codex-mini 'test'"
test_cmd "Spawn codex-review" "'$SCRIPT' -n spawn codex-review 'test'"
test_cmd "Spawn gemini-fast" "'$SCRIPT' -n spawn gemini-fast 'test'"
test_cmd "Fan-out" "'$SCRIPT' -n fan-out 'test prompt'"
test_cmd "Map-reduce" "'$SCRIPT' -n map-reduce 'test prompt'"

echo ""

# ============================================
# 6. DRY-RUN: FLAGS & OPTIONS
# ============================================
echo -e "${YELLOW}6. Dry-Run: Flags & Options${NC}"

test_cmd "Verbose flag (-v)" "'$SCRIPT' -v -n auto 'test'"
test_cmd "Quick tier (-Q)" "'$SCRIPT' -Q -n auto 'test'"
test_cmd "Premium tier (-P)" "'$SCRIPT' -P -n auto 'test'"
test_cmd "Custom parallel (-p 5)" "'$SCRIPT' -p 5 -n auto 'test'"
test_cmd "Custom timeout (-t 600)" "'$SCRIPT' -t 600 -n auto 'test'"
test_cmd "No personas (--no-personas)" "'$SCRIPT' --no-personas -n auto 'test'"
test_cmd "Custom quality (-q 80)" "'$SCRIPT' -q 80 -n tangle 'test'"

echo ""

# ============================================
# 7. COST TRACKING
# ============================================
echo -e "${YELLOW}7. Cost Tracking${NC}"

test_cmd "Cost report (table)" "'$SCRIPT' cost"
test_cmd "Cost report (JSON)" "'$SCRIPT' cost-json"
test_cmd "Cost report (CSV)" "'$SCRIPT' cost-csv"
# Note: cost-clear and cost-archive modify state, skipping in automated tests

echo ""

# ============================================
# 8. WORKSPACE MANAGEMENT
# ============================================
echo -e "${YELLOW}8. Workspace Management${NC}"

test_cmd "Status" "'$SCRIPT' status"
# Note: kill, clean, aggregate modify state - manual testing recommended

echo ""

# ============================================
# 9. ERROR HANDLING
# ============================================
echo -e "${YELLOW}9. Error Handling${NC}"

test_cmd "Unknown command shows suggestions" "'$SCRIPT' badcommand" 1
test_cmd "Missing prompt for probe" "'$SCRIPT' probe" 1
test_cmd "Missing prompt for tangle" "'$SCRIPT' tangle" 1
# Note: Invalid agent test depends on implementation

echo ""

# ============================================
# 10. RALPH-WIGGUM ITERATION
# ============================================
echo -e "${YELLOW}10. Ralph-Wiggum Iteration${NC}"

test_cmd "Ralph dry-run" "'$SCRIPT' -n ralph 'test iteration'"
test_cmd "Iterate alias dry-run" "'$SCRIPT' -n iterate 'test iteration'"

echo ""

# ============================================
# SUMMARY
# ============================================
echo "========================================"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "========================================"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    exit 1
fi
