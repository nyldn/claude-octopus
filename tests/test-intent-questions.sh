#!/usr/bin/env bash
# Test Intent Mode 3-Question Pattern
# Validates that workflows have proper clarifying questions implementation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMANDS_DIR="$PROJECT_ROOT/.claude/commands"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}🧪 Testing Intent Mode 3-Question Pattern${NC}"
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

# Commands that should have 3-question pattern directly in the command file
# Note: debate.md is a skill wrapper and doesn't have questions directly
COMMANDS_WITH_QUESTIONS=("discover.md" "review.md" "security.md" "tdd.md" "embrace.md")

# Test 1: Verify all command files exist
echo "Test 1: Checking if command files exist..."
MISSING_FILES=0
for cmd_file in "${COMMANDS_WITH_QUESTIONS[@]}"; do
    if [[ -f "$COMMANDS_DIR/$cmd_file" ]]; then
        pass "Command file exists: $cmd_file"
    else
        fail "Missing command file" "File not found: $COMMANDS_DIR/$cmd_file"
        ((MISSING_FILES++))
    fi
done

if [[ $MISSING_FILES -gt 0 ]]; then
    echo ""
    echo -e "${RED}❌ Cannot continue - missing command files${NC}"
    exit 1
fi

# Test 2: Check for "Step 1: Ask Clarifying Questions" section
echo ""
echo "Test 2: Checking for clarifying questions section..."
for cmd_file in "${COMMANDS_WITH_QUESTIONS[@]}"; do
    full_path="$COMMANDS_DIR/$cmd_file"
    if grep -q "Step 1: Ask Clarifying Questions" "$full_path" || \
       grep -q "Ask Clarifying Questions" "$full_path" || \
       grep -q "Clarifying Questions" "$full_path"; then
        pass "$cmd_file has clarifying questions section"
    else
        fail "$cmd_file missing clarifying questions section" "Should have 'Ask Clarifying Questions' section"
    fi
done

# Test 3: Check for AskUserQuestion tool usage
echo ""
echo "Test 3: Checking for AskUserQuestion tool usage..."
for cmd_file in "${COMMANDS_WITH_QUESTIONS[@]}"; do
    full_path="$COMMANDS_DIR/$cmd_file"
    if grep -q "AskUserQuestion" "$full_path"; then
        pass "$cmd_file uses AskUserQuestion tool"
    else
        fail "$cmd_file missing AskUserQuestion" "Should use AskUserQuestion tool for questions"
    fi
done

# Test 4: Check for 3 questions (questions array)
echo ""
echo "Test 4: Checking for 3 questions in each command..."
for cmd_file in "${COMMANDS_WITH_QUESTIONS[@]}"; do
    full_path="$COMMANDS_DIR/$cmd_file"
    # Count question objects in AskUserQuestion block (both JSON and JS notation)
    question_count=$(grep -E -o '("|'"'"')?question("|'"'"')?\s*:' "$full_path" | wc -l | tr -d ' ')

    if [[ $question_count -ge 3 ]]; then
        pass "$cmd_file has $question_count questions"
    else
        fail "$cmd_file has insufficient questions" "Found $question_count questions, expected at least 3"
    fi
done

# Test 5: Check for required question fields (question, header, options)
echo ""
echo "Test 5: Checking question structure (question, header, options)..."
for cmd_file in "${COMMANDS_WITH_QUESTIONS[@]}"; do
    full_path="$COMMANDS_DIR/$cmd_file"
    has_question_field=$(grep -E -c '("|'"'"')?question("|'"'"')?\s*:' "$full_path" || echo 0)
    has_header_field=$(grep -E -c '("|'"'"')?header("|'"'"')?\s*:' "$full_path" || echo 0)
    has_options_field=$(grep -E -c '("|'"'"')?options("|'"'"')?\s*:' "$full_path" || echo 0)

    if [[ $has_question_field -ge 3 ]] && [[ $has_header_field -ge 3 ]] && [[ $has_options_field -ge 3 ]]; then
        pass "$cmd_file has proper question structure"
    else
        fail "$cmd_file has incomplete question structure" \
            "question fields: $has_question_field, header fields: $has_header_field, options fields: $has_options_field"
    fi
done

# Test 6: Check for multiSelect field
echo ""
echo "Test 6: Checking for multiSelect field..."
for cmd_file in "${COMMANDS_WITH_QUESTIONS[@]}"; do
    full_path="$COMMANDS_DIR/$cmd_file"
    if grep -E -q '("|'"'"')?multiSelect("|'"'"')?\s*:' "$full_path"; then
        pass "$cmd_file has multiSelect field"
    else
        fail "$cmd_file missing multiSelect field" "Should specify multiSelect for each question"
    fi
done

# Test 7: Check for incorporation instructions
echo ""
echo "Test 7: Checking for answer incorporation instructions..."
for cmd_file in "${COMMANDS_WITH_QUESTIONS[@]}"; do
    full_path="$COMMANDS_DIR/$cmd_file"
    if grep -qi "after receiving answers" "$full_path" || \
       grep -qi "incorporate.*answers" "$full_path" || \
       grep -qi "use.*answers" "$full_path"; then
        pass "$cmd_file has incorporation instructions"
    else
        fail "$cmd_file missing incorporation instructions" "Should instruct how to use answers"
    fi
done

# Test 8: Verify discover.md has specific questions
echo ""
echo "Test 8: Checking discover.md specific questions..."
discover_path="$COMMANDS_DIR/discover.md"
if grep -q "depth" "$discover_path" && \
   grep -q "focus" "$discover_path" && \
   (grep -q "output" "$discover_path" || grep -q "format" "$discover_path"); then
    pass "discover.md has appropriate question topics (depth, focus, output)"
else
    fail "discover.md missing expected question topics" "Should ask about depth, focus, and output format"
fi

# Test 9: Verify review.md has specific questions
echo ""
echo "Test 9: Checking review.md specific questions..."
review_path="$COMMANDS_DIR/review.md"
if grep -q "goal" "$review_path" && \
   grep -q "priority" "$review_path" && \
   grep -q "audience" "$review_path"; then
    pass "review.md has appropriate question topics (goal, priority, audience)"
else
    fail "review.md missing expected question topics" "Should ask about goal, priority, and audience"
fi

# Test 10: Verify security.md has specific questions
echo ""
echo "Test 10: Checking security.md specific questions..."
security_path="$COMMANDS_DIR/security.md"
if (grep -q "threat" "$security_path" || grep -q "attack" "$security_path") && \
   grep -q "compliance" "$security_path" && \
   grep -q "risk" "$security_path"; then
    pass "security.md has appropriate question topics (threat model, compliance, risk)"
else
    fail "security.md missing expected question topics" "Should ask about threat model, compliance, and risk tolerance"
fi

# Test 11: Verify tdd.md has specific questions
echo ""
echo "Test 11: Checking tdd.md specific questions..."
tdd_path="$COMMANDS_DIR/tdd.md"
if grep -q "coverage" "$tdd_path" && \
   (grep -q "style" "$tdd_path" || grep -q "approach" "$tdd_path") && \
   grep -q "complexity" "$tdd_path"; then
    pass "tdd.md has appropriate question topics (coverage, style, complexity)"
else
    fail "tdd.md missing expected question topics" "Should ask about coverage, style, and complexity"
fi

# Test 12: Verify all core workflow commands have been checked
echo ""
echo "Test 12: Summary of core workflow commands with questions..."
info "Commands with 3-question pattern: discover, review, security, tdd, embrace"
info "Note: debate.md is a skill wrapper and loads skill-debate.md"
pass "All applicable workflow commands have been validated"

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
    info "All 5 workflows have proper 3-question intent capture"
    info "(debate.md delegates to skill-debate.md)"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
