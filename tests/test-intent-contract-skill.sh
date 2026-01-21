#!/usr/bin/env bash
# Test Intent Contract Skill Implementation
# Validates the skill-intent-contract.md skill structure and functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-intent-contract.md"
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

echo -e "${BLUE}🧪 Testing Intent Contract Skill${NC}"
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

# Test 1: Check if skill file exists
echo "Test 1: Checking if skill-intent-contract.md exists..."
if [[ -f "$SKILL_FILE" ]]; then
    pass "skill-intent-contract.md file exists"
else
    fail "skill-intent-contract.md not found" "Expected: $SKILL_FILE"
    echo ""
    echo -e "${RED}❌ Cannot continue - skill file missing${NC}"
    exit 1
fi

# Test 2: Check frontmatter has correct skill name
echo ""
echo "Test 2: Checking skill name in frontmatter..."
if grep -q '^name: skill-intent-contract$' "$SKILL_FILE" || \
   grep -q '^name:skill-intent-contract$' "$SKILL_FILE"; then
    pass "Skill name is 'skill-intent-contract'"
else
    fail "Incorrect or missing skill name" "Should be 'name: skill-intent-contract' in frontmatter"
fi

# Test 3: Check registration in plugin.json
echo ""
echo "Test 3: Checking if skill is registered in plugin.json..."
if grep -q '"\./\.claude/skills/skill-intent-contract\.md"' "$PLUGIN_JSON"; then
    pass "skill-intent-contract.md is registered in plugin.json"
else
    fail "skill not registered" "Should be listed in plugin.json skills array"
fi

# Test 4: Check for Intent Contract Structure section
echo ""
echo "Test 4: Checking for Intent Contract Structure section..."
if grep -q "Intent Contract Structure" "$SKILL_FILE" || \
   grep -qi "contract structure\|contract template" "$SKILL_FILE"; then
    pass "Has Intent Contract Structure section"
else
    fail "Missing Contract Structure section" "Should document the intent contract structure"
fi

# Test 5: Check for required contract components
echo ""
echo "Test 5: Checking for required contract components..."
has_job_statement=false
has_success_criteria=false
has_boundaries=false
has_context=false
has_validation=false

grep -qi "job statement\|what to build" "$SKILL_FILE" && has_job_statement=true
grep -qi "success criteria\|done when" "$SKILL_FILE" && has_success_criteria=true
grep -qi "boundaries\|scope\|out of scope" "$SKILL_FILE" && has_boundaries=true
grep -qi "context.*constraint\|constraint.*context" "$SKILL_FILE" && has_context=true
grep -qi "validation checklist\|validation.*check" "$SKILL_FILE" && has_validation=true

passed_components=0
$has_job_statement && ((passed_components++))
$has_success_criteria && ((passed_components++))
$has_boundaries && ((passed_components++))
$has_context && ((passed_components++))
$has_validation && ((passed_components++))

if [[ $passed_components -ge 4 ]]; then
    pass "Has $passed_components/5 key contract components"
else
    fail "Missing key contract components" \
        "Should have: Job Statement, Success Criteria, Boundaries, Context & Constraints, Validation Checklist"
fi

# Test 6: Check for Step 1 - Capture Intent
echo ""
echo "Test 6: Checking for Step 1: Capture Intent..."
if grep -q "Step 1: Capture Intent" "$SKILL_FILE" || \
   grep -q "Capture Intent" "$SKILL_FILE"; then
    pass "Has Step 1: Capture Intent section"
else
    fail "Missing Step 1 section" "Should have 'Capture Intent' step"
fi

# Test 7: Check for Step 2 - Write Intent Contract File
echo ""
echo "Test 7: Checking for Step 2: Write Intent Contract File..."
if grep -q "Step 2: Write Intent Contract" "$SKILL_FILE" || \
   grep -q "Write Intent Contract File" "$SKILL_FILE"; then
    pass "Has Step 2: Write Intent Contract File section"
else
    fail "Missing Step 2 section" "Should have 'Write Intent Contract File' step"
fi

# Test 8: Check for session-intent.md file path
echo ""
echo "Test 8: Checking for session-intent.md file path..."
if grep -q "session-intent\.md" "$SKILL_FILE" || \
   grep -q "\.claude/session-intent" "$SKILL_FILE"; then
    pass "References session-intent.md file path"
else
    fail "Missing session-intent.md reference" "Should specify .claude/session-intent.md as the contract file"
fi

# Test 9: Check for Step 3 - Reference During Execution
echo ""
echo "Test 9: Checking for Step 3: Reference During Execution..."
if grep -q "Step 3: Reference During Execution" "$SKILL_FILE" || \
   grep -qi "reference.*execution\|during execution" "$SKILL_FILE"; then
    pass "Has Step 3: Reference During Execution section"
else
    fail "Missing Step 3 section" "Should have 'Reference During Execution' step"
fi

# Test 10: Check for Step 4 - Validate at End
echo ""
echo "Test 10: Checking for Step 4: Validate at End..."
if grep -q "Step 4: Validate" "$SKILL_FILE" || \
   grep -qi "validate at end\|final validation" "$SKILL_FILE"; then
    pass "Has Step 4: Validate at End section"
else
    fail "Missing Step 4 section" "Should have 'Validate at End' step"
fi

# Test 11: Check for Step 5 - Update Intent Contract Status
echo ""
echo "Test 11: Checking for Step 5: Update Intent Contract Status..."
if grep -q "Step 5: Update" "$SKILL_FILE" || \
   grep -qi "update.*status\|update contract" "$SKILL_FILE"; then
    pass "Has Step 5: Update Intent Contract Status section"
else
    fail "Missing Step 5 section" "Should have 'Update Intent Contract Status' step"
fi

# Test 12: Check for workflow integration documentation
echo ""
echo "Test 12: Checking for workflow integration documentation..."
workflows_mentioned=0
grep -qi "embrace" "$SKILL_FILE" && ((workflows_mentioned++))
grep -qi "discover\|probe" "$SKILL_FILE" && ((workflows_mentioned++))
grep -qi "plan\|/plan" "$SKILL_FILE" && ((workflows_mentioned++))

if [[ $workflows_mentioned -ge 2 ]]; then
    pass "Documents integration with $workflows_mentioned workflow(s)"
else
    fail "Missing workflow integration docs" "Should document integration with Embrace, Discover, and Plan"
fi

# Test 13: Check for example intent contract
echo ""
echo "Test 13: Checking for example intent contract..."
if grep -qi "example.*contract\|sample.*contract\|contract.*example" "$SKILL_FILE"; then
    pass "Provides example intent contract"
else
    fail "Missing example contract" "Should include an example intent contract"
fi

# Test 14: Check for validation report format
echo ""
echo "Test 14: Checking for validation report format..."
if grep -qi "validation report\|report.*format\|validation.*format" "$SKILL_FILE"; then
    pass "Specifies validation report format"
else
    fail "Missing validation report format" "Should specify how to format validation reports"
fi

# Test 15: Check for contract template structure
echo ""
echo "Test 15: Checking for contract template with markdown structure..."
if grep -q "##" "$SKILL_FILE" || grep -q "###" "$SKILL_FILE"; then
    pass "Uses markdown structure for contract template"
else
    fail "Missing markdown template structure" "Contract template should use markdown headers"
fi

# Test 16: Check for AskUserQuestion mention or usage
echo ""
echo "Test 16: Checking for question-asking guidance..."
if grep -qi "AskUserQuestion\|ask.*question\|clarifying question" "$SKILL_FILE"; then
    pass "References asking clarifying questions"
else
    fail "Missing question guidance" "Should mention AskUserQuestion or clarifying questions"
fi

# Test 17: Check for checkboxes in validation
echo ""
echo "Test 17: Checking for checkbox/checklist format..."
if grep -q "\[ \]\|\[x\]\|\- \[ \]" "$SKILL_FILE"; then
    pass "Uses checkbox format for validation checklist"
else
    fail "Missing checkbox format" "Validation checklist should use markdown checkboxes"
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
    info "Intent contract skill is properly implemented"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
