#!/usr/bin/env bash
# Test /octo:plan Command Implementation
# Validates the new plan.md command structure and functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAN_FILE="$PROJECT_ROOT/.claude/commands/plan.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}🧪 Testing /octo:plan Command${NC}"
echo ""

# Helper functions
pass() {
    ((TEST_COUNT++))
    ((PASS_COUNT++))
    echo -e "${GREEN}✅ PASS${NC}: $1"
}

fail() {
    ((TEST_COUNT++))
    ((FAIL_COUNT++))
    echo -e "${RED}❌ FAIL${NC}: $1"
    echo -e "   ${YELLOW}$2${NC}"
}

info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

# Test 1: Check if plan.md exists
echo "Test 1: Checking if plan.md exists..."
if [[ -f "$PLAN_FILE" ]]; then
    pass "plan.md file exists"
else
    fail "plan.md not found" "Expected: $PLAN_FILE"
    echo ""
    echo -e "${RED}❌ Cannot continue - plan.md missing${NC}"
    exit 1
fi

# Test 2: Check frontmatter has correct command name
echo ""
echo "Test 2: Checking command name in frontmatter..."
if grep -q '^command: plan$' "$PLAN_FILE" || grep -q '^command:plan$' "$PLAN_FILE"; then
    pass "Command name is 'plan'"
else
    fail "Incorrect or missing command name" "Should be 'command: plan'"
fi

# Test 3: Check for aliases
echo ""
echo "Test 3: Checking for command aliases..."
if grep -q 'build-plan' "$PLAN_FILE" && grep -q 'intent' "$PLAN_FILE"; then
    pass "Command has expected aliases (build-plan, intent)"
else
    fail "Missing expected aliases" "Should have aliases: build-plan, intent"
fi

# Test 4: Check registration in plugin.json
echo ""
echo "Test 4: Checking if plan.md is registered in plugin.json..."
if grep -q '"\./\.claude/commands/plan\.md"' "$PLUGIN_JSON"; then
    pass "plan.md is registered in plugin.json"
else
    fail "plan.md not registered" "Should be listed in plugin.json commands array"
fi

# Test 5: Check for Step 1 - Capture Comprehensive Intent
echo ""
echo "Test 5: Checking for Step 1: Capture Comprehensive Intent..."
if grep -q "Step 1: Capture Comprehensive Intent" "$PLAN_FILE" || \
   grep -q "Capture Comprehensive Intent" "$PLAN_FILE"; then
    pass "Has Step 1: Capture Comprehensive Intent section"
else
    fail "Missing Step 1 section" "Should have 'Capture Comprehensive Intent' section"
fi

# Test 6: Check for 5 strategic questions
echo ""
echo "Test 6: Checking for 5 strategic questions..."
question_count=$(grep -E -o '("|'"'"')?question("|'"'"')?\s*:' "$PLAN_FILE" | wc -l | tr -d ' ')

if [[ $question_count -ge 5 ]]; then
    pass "Has $question_count questions (expected 5 strategic questions)"
else
    fail "Insufficient strategic questions" "Found $question_count questions, expected at least 5"
fi

# Test 7: Check for specific question topics
echo ""
echo "Test 7: Checking for specific strategic question topics..."
has_goal=false
has_knowledge=false
has_clarity=false
has_success=false
has_constraints=false

grep -i "goal\|objective\|what" "$PLAN_FILE" | grep -q "question" && has_goal=true
grep -i "knowledge\|know\|context" "$PLAN_FILE" | grep -q "question" && has_knowledge=true
grep -i "clarity\|clear\|ambiguous" "$PLAN_FILE" | grep -q "question" && has_clarity=true
grep -i "success\|done\|complete" "$PLAN_FILE" | grep -q "question" && has_success=true
grep -i "constraint\|limitation\|avoid" "$PLAN_FILE" | grep -q "question" && has_constraints=true

if $has_goal && $has_knowledge && $has_clarity && $has_success && $has_constraints; then
    pass "Has questions covering: goal, knowledge, clarity, success, constraints"
elif $has_goal && $has_success && $has_constraints; then
    pass "Has core strategic questions (goal, success, constraints)"
else
    fail "Missing key question topics" "Should cover goal, knowledge, clarity, success, and constraints"
fi

# Test 8: Check for Step 2 - Create Intent Contract
echo ""
echo "Test 8: Checking for Step 2: Create Intent Contract..."
if grep -q "Step 2: Create Intent Contract" "$PLAN_FILE" || \
   grep -q "Create Intent Contract" "$PLAN_FILE"; then
    pass "Has Step 2: Create Intent Contract section"
else
    fail "Missing Step 2 section" "Should have 'Create Intent Contract' section"
fi

# Test 9: Check for Step 3 - Analyze and Route
echo ""
echo "Test 9: Checking for Step 3: Analyze and Route..."
if grep -q "Step 3: Analyze and Route" "$PLAN_FILE" || \
   grep -q "Analyze and Route" "$PLAN_FILE"; then
    pass "Has Step 3: Analyze and Route section"
else
    fail "Missing Step 3 section" "Should have 'Analyze and Route' section"
fi

# Test 10: Check for routing logic
echo ""
echo "Test 10: Checking for routing logic and conditions..."
if grep -qi "routing\|route to\|workflow" "$PLAN_FILE" && \
   (grep -qi "discover\|probe" "$PLAN_FILE" || \
    grep -qi "define\|grasp" "$PLAN_FILE" || \
    grep -qi "develop\|tangle" "$PLAN_FILE" || \
    grep -qi "deliver\|ink" "$PLAN_FILE"); then
    pass "Has routing logic for workflows"
else
    fail "Missing routing logic" "Should have routing conditions for different workflows"
fi

# Test 11: Check for Step 4 - Present the Plan
echo ""
echo "Test 11: Checking for Step 4: Present the Plan..."
if grep -q "Step 4: Present the Plan" "$PLAN_FILE" || \
   grep -q "Present the Plan" "$PLAN_FILE"; then
    pass "Has Step 4: Present the Plan section"
else
    fail "Missing Step 4 section" "Should have 'Present the Plan' section"
fi

# Test 12: Check for plan visualization/formatting
echo ""
echo "Test 12: Checking for plan visualization..."
if grep -qi "visualization\|format\|present" "$PLAN_FILE"; then
    pass "Has plan presentation/visualization instructions"
else
    fail "Missing visualization instructions" "Should specify how to present the plan"
fi

# Test 13: Check for validation section
echo ""
echo "Test 13: Checking for validation against intent contract..."
if grep -qi "validate.*intent\|validation.*contract\|Step 7" "$PLAN_FILE"; then
    pass "Has validation against intent contract"
else
    fail "Missing validation section" "Should validate plan against intent contract"
fi

# Test 14: Check for phase weight calculations
echo ""
echo "Test 14: Checking for phase weight calculations..."
if grep -q "25%" "$PLAN_FILE" || grep -qi "weight\|percentage\|allocation" "$PLAN_FILE"; then
    pass "Has phase weight/allocation calculations"
else
    fail "Missing phase weight calculations" "Should calculate weights for each phase (e.g., 25% ± adjustments)"
fi

# Test 15: Check for integration with intent contract
echo ""
echo "Test 15: Checking for intent contract integration..."
if grep -q "session-intent\.md" "$PLAN_FILE" || \
   grep -qi "intent contract" "$PLAN_FILE"; then
    pass "References intent contract system"
else
    fail "Missing intent contract integration" "Should reference session-intent.md or intent contract"
fi

# Test 16: Check for provider availability check
echo ""
echo "Test 16: Checking for provider availability check..."
if grep -qi "codex\|gemini\|provider" "$PLAN_FILE"; then
    pass "References provider availability"
else
    fail "Missing provider availability check" "Should check for Codex/Gemini availability"
fi

# Test 17: Check for AskUserQuestion usage
echo ""
echo "Test 17: Checking for AskUserQuestion tool usage..."
if grep -q "AskUserQuestion" "$PLAN_FILE"; then
    pass "Uses AskUserQuestion tool for strategic questions"
else
    fail "Missing AskUserQuestion usage" "Should use AskUserQuestion for the 5 strategic questions"
fi

# Test 18: Check for proper question structure
echo ""
echo "Test 18: Checking question structure (header, options, multiSelect)..."
has_headers=$(grep -E -c '("|'"'"')?header("|'"'"')?\s*:' "$PLAN_FILE" || echo 0)
has_options=$(grep -E -c '("|'"'"')?options("|'"'"')?\s*:' "$PLAN_FILE" || echo 0)
has_multiselect=$(grep -E -c '("|'"'"')?multiSelect("|'"'"')?\s*:' "$PLAN_FILE" || echo 0)

if [[ $has_headers -ge 5 ]] && [[ $has_options -ge 5 ]] && [[ $has_multiselect -ge 5 ]]; then
    pass "Questions have proper structure (header, options, multiSelect)"
else
    fail "Incomplete question structure" \
        "headers: $has_headers, options: $has_options, multiSelect: $has_multiselect (expected ≥5 each)"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Test Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total tests:  ${BLUE}$TEST_COUNT${NC}"
echo -e "Passed:       ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed:       ${RED}$FAIL_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    info "/octo:plan command is properly implemented"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
