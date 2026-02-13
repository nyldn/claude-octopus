#!/usr/bin/env bash
# Test the /octo:multi command implementation
# Validates command file, registration, and triggers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}🧪 Testing /octo:multi command implementation${NC}"
echo ""

# Helper functions
pass() {
    TEST_COUNT=$((TEST_COUNT + 1))
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "${GREEN}✅ PASS${NC}: $1"
}

fail() {
    TEST_COUNT=$((TEST_COUNT + 1))
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}❌ FAIL${NC}: $1"
    echo -e "   ${YELLOW}$2${NC}"
}

info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

# Test 1: Command file exists
echo "Test 1: Checking if multi.md exists..."
COMMAND_FILE="$PROJECT_ROOT/.claude/commands/multi.md"
if [[ -f "$COMMAND_FILE" ]]; then
    pass "Command file exists at .claude/commands/multi.md"
else
    fail "Command file not found" "Expected: $COMMAND_FILE"
fi

# Test 2: Old parallel-agents.md should NOT exist
echo ""
echo "Test 2: Checking old parallel-agents.md is removed..."
OLD_FILE="$PROJECT_ROOT/.claude/commands/parallel-agents.md"
if [[ ! -f "$OLD_FILE" ]]; then
    pass "Old parallel-agents.md file is removed"
else
    fail "Old file still exists" "File should be removed: $OLD_FILE"
fi

# Test 3: Command frontmatter has correct name
echo ""
echo "Test 3: Validating command frontmatter..."
if [[ -f "$COMMAND_FILE" ]]; then
    COMMAND_NAME=$(grep '^command:' "$COMMAND_FILE" | sed 's/command:[[:space:]]*//')
    if [[ "$COMMAND_NAME" == "multi" ]]; then
        pass "Command name is 'multi' in frontmatter"
    else
        fail "Incorrect command name" "Expected: 'multi', Got: '$COMMAND_NAME'"
    fi
fi

# Test 4: No aliases in frontmatter
echo ""
echo "Test 4: Checking for aliases..."
if [[ -f "$COMMAND_FILE" ]]; then
    if grep -q '^aliases:' "$COMMAND_FILE"; then
        fail "Aliases found in frontmatter" "Command should have no aliases"
    else
        pass "No aliases in frontmatter (as expected)"
    fi
fi

# Test 5: Command registered in plugin.json
echo ""
echo "Test 5: Checking plugin.json registration..."
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"
if grep -q '"\./\.claude/commands/multi\.md"' "$PLUGIN_JSON"; then
    pass "Command registered in plugin.json"
else
    fail "Command not registered" "plugin.json should contain multi.md"
fi

# Test 6: Old parallel-agents.md NOT in plugin.json commands array
echo ""
echo "Test 6: Checking old command removed from plugin.json..."
if grep -q '"\./\.claude/commands/parallel-agents\.md"' "$PLUGIN_JSON"; then
    fail "Old command still registered" "plugin.json commands should not contain parallel-agents.md"
else
    pass "Old command removed from plugin.json"
fi

# Test 7: Skill file has priority triggers
echo ""
echo "Test 7: Validating skill priority triggers..."
SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-parallel-agents.md"
if grep -q 'PRIORITY TRIGGERS' "$SKILL_FILE"; then
    pass "PRIORITY TRIGGERS section exists in skill file"
else
    fail "Missing PRIORITY TRIGGERS" "skill-parallel-agents.md should have priority triggers"
fi

# Test 8: Priority triggers include /octo:multi
echo ""
echo "Test 8: Checking /octo:multi in priority triggers..."
if grep -A 5 'PRIORITY TRIGGERS' "$SKILL_FILE" | grep -q '/octo:multi'; then
    pass "/octo:multi found in priority triggers"
else
    fail "/octo:multi not in triggers" "Priority triggers should include /octo:multi"
fi

# Test 9: Old command aliases removed from triggers
echo ""
echo "Test 9: Checking old aliases removed from triggers..."
if grep -A 5 'PRIORITY TRIGGERS' "$SKILL_FILE" | grep -qE '(parallel-agents|all-providers)'; then
    fail "Old aliases still in triggers" "parallel-agents and all-providers should be removed"
else
    pass "Old command aliases removed from triggers"
fi

# Test 10: Skill has execution steps for multi-provider orchestration
echo ""
echo "Test 10: Checking multi-provider execution steps..."
if grep -q '## Step 2: Execute orchestrate.sh' "$SKILL_FILE"; then
    pass "Skill has orchestrate.sh execution step"
else
    fail "Missing execution step" "Skill should have 'Step 2: Execute orchestrate.sh' section"
fi

# Test 11: Natural language triggers preserved
echo ""
echo "Test 11: Checking natural language triggers..."
if grep -A 5 'PRIORITY TRIGGERS' "$SKILL_FILE" | grep -q 'run this with all providers'; then
    pass "Natural language triggers preserved"
else
    fail "Natural language triggers missing" "Triggers should include 'run this with all providers'"
fi

# Test 12: TRIGGERS.md documentation updated
echo ""
echo "Test 12: Validating TRIGGERS.md documentation..."
TRIGGERS_DOC="$PROJECT_ROOT/docs/TRIGGERS.md"
if grep -q '## Multi Command' "$TRIGGERS_DOC"; then
    pass "TRIGGERS.md has 'Multi Command' section"
else
    fail "Missing documentation section" "TRIGGERS.md should have '## Multi Command' section"
fi

# Test 13: TRIGGERS.md shows only /octo:multi
echo ""
echo "Test 13: Checking TRIGGERS.md command syntax..."
if grep -A 3 'Explicit command:' "$TRIGGERS_DOC" | grep -q '/octo:multi'; then
    pass "TRIGGERS.md shows /octo:multi command"
else
    fail "Documentation missing command" "TRIGGERS.md should document /octo:multi"
fi

# Test 14: No parallel-agents references in TRIGGERS.md
echo ""
echo "Test 14: Checking for old command references in docs..."
if grep -q 'parallel-agents' "$TRIGGERS_DOC"; then
    fail "Old command name in docs" "TRIGGERS.md should not reference parallel-agents"
else
    pass "No references to old command name in docs"
fi

# Test 15: Command file has no references to old command names
echo ""
echo "Test 15: Checking command file content..."
if [[ -f "$COMMAND_FILE" ]]; then
    if grep -qi 'parallel-agents' "$COMMAND_FILE"; then
        fail "Old command name in file" "multi.md should not reference parallel-agents"
    else
        pass "Command file contains no old command references"
    fi
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
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
