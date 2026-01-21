#!/usr/bin/env bash
# Test Version Consistency for v7.11.0
# Validates that version 7.11.0 is consistent across all files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$PROJECT_ROOT/.claude-plugin/marketplace.json"
PACKAGE_JSON="$PROJECT_ROOT/package.json"
README="$PROJECT_ROOT/README.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Expected version
EXPECTED_VERSION="7.11.0"

echo -e "${BLUE}🧪 Testing Version Consistency (v${EXPECTED_VERSION})${NC}"
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

# Test 1: Check plugin.json version
echo "Test 1: Checking plugin.json version..."
if [[ -f "$PLUGIN_JSON" ]]; then
    PLUGIN_VERSION=$(grep '"version"' "$PLUGIN_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ "$PLUGIN_VERSION" == "$EXPECTED_VERSION" ]]; then
        pass "plugin.json has version $EXPECTED_VERSION"
    else
        fail "plugin.json version mismatch" "Found: $PLUGIN_VERSION, Expected: $EXPECTED_VERSION"
    fi
else
    fail "plugin.json not found" "Expected: $PLUGIN_JSON"
fi

# Test 2: Check marketplace.json version
echo ""
echo "Test 2: Checking marketplace.json version..."
if [[ -f "$MARKETPLACE_JSON" ]]; then
    # Get plugin version (not metadata version - that's for the marketplace itself)
    MARKETPLACE_VERSION=$(grep '"version"' "$MARKETPLACE_JSON" | tail -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ "$MARKETPLACE_VERSION" == "$EXPECTED_VERSION" ]]; then
        pass "marketplace.json has plugin version $EXPECTED_VERSION"
    else
        fail "marketplace.json plugin version mismatch" "Found: $MARKETPLACE_VERSION, Expected: $EXPECTED_VERSION"
    fi
else
    fail "marketplace.json not found" "Expected: $MARKETPLACE_JSON"
fi

# Test 3: Check package.json version
echo ""
echo "Test 3: Checking package.json version..."
if [[ -f "$PACKAGE_JSON" ]]; then
    PACKAGE_VERSION=$(grep '"version"' "$PACKAGE_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ "$PACKAGE_VERSION" == "$EXPECTED_VERSION" ]]; then
        pass "package.json has version $EXPECTED_VERSION"
    else
        fail "package.json version mismatch" "Found: $PACKAGE_VERSION, Expected: $EXPECTED_VERSION"
    fi
else
    fail "package.json not found" "Expected: $PACKAGE_JSON"
fi

# Test 4: Check README.md badge
echo ""
echo "Test 4: Checking README.md version badge..."
if [[ -f "$README" ]]; then
    if grep -q "$EXPECTED_VERSION" "$README"; then
        pass "README.md references version $EXPECTED_VERSION"
    else
        fail "README.md version badge outdated" "Should show version $EXPECTED_VERSION"
    fi
else
    fail "README.md not found" "Expected: $README"
fi

# Test 5: Check marketplace.json description mentions Intent Mode features
echo ""
echo "Test 5: Checking marketplace.json description..."
if [[ -f "$MARKETPLACE_JSON" ]]; then
    description=$(grep -A 5 '"description"' "$MARKETPLACE_JSON" || echo "")

    # Check for key v7.11.0 features
    mentions_intent=false
    mentions_plan=false
    mentions_questions=false

    echo "$description" | grep -qi "intent\|/plan" && mentions_intent=true
    echo "$description" | grep -qi "plan\|routing" && mentions_plan=true
    echo "$description" | grep -qi "question\|clarif" && mentions_questions=true

    feature_count=0
    $mentions_intent && ((feature_count++))
    $mentions_plan && ((feature_count++))
    $mentions_questions && ((feature_count++))

    if [[ $feature_count -ge 1 ]]; then
        pass "marketplace.json description mentions v7.11.0 features"
    else
        fail "marketplace.json description outdated" "Should mention Intent Mode, /plan command, or clarifying questions"
    fi
else
    fail "marketplace.json not found" "Expected: $MARKETPLACE_JSON"
fi

# Test 6: Verify command count in plugin.json
echo ""
echo "Test 6: Checking command count in plugin.json..."
if [[ -f "$PLUGIN_JSON" ]]; then
    COMMAND_COUNT=$(grep -o '"\./\.claude/commands/[^"]*\.md"' "$PLUGIN_JSON" | wc -l | tr -d ' ')
    EXPECTED_COMMANDS=27

    if [[ $COMMAND_COUNT -eq $EXPECTED_COMMANDS ]]; then
        pass "plugin.json has $COMMAND_COUNT commands (expected: $EXPECTED_COMMANDS)"
    else
        fail "Command count mismatch" "Found: $COMMAND_COUNT, Expected: $EXPECTED_COMMANDS"
    fi
fi

# Test 7: Verify skill count in plugin.json
echo ""
echo "Test 7: Checking skill count in plugin.json..."
if [[ -f "$PLUGIN_JSON" ]]; then
    SKILL_COUNT=$(grep -o '"\./\.claude/skills/[^"]*\.md"' "$PLUGIN_JSON" | wc -l | tr -d ' ')
    EXPECTED_SKILLS=33

    if [[ $SKILL_COUNT -eq $EXPECTED_SKILLS ]]; then
        pass "plugin.json has $SKILL_COUNT skills (expected: $EXPECTED_SKILLS)"
    else
        fail "Skill count mismatch" "Found: $SKILL_COUNT, Expected: $EXPECTED_SKILLS"
    fi
fi

# Test 8: Verify new command plan.md is registered
echo ""
echo "Test 8: Checking if new plan.md command is registered..."
if [[ -f "$PLUGIN_JSON" ]]; then
    if grep -q '"\./\.claude/commands/plan\.md"' "$PLUGIN_JSON"; then
        pass "New plan.md command is registered"
    else
        fail "plan.md not registered" "v7.11.0 feature: /octo:plan command should be registered"
    fi
fi

# Test 9: Verify new skill skill-intent-contract.md is registered
echo ""
echo "Test 9: Checking if new intent contract skill is registered..."
if [[ -f "$PLUGIN_JSON" ]]; then
    if grep -q '"\./\.claude/skills/skill-intent-contract\.md"' "$PLUGIN_JSON"; then
        pass "New skill-intent-contract.md skill is registered"
    else
        fail "skill-intent-contract.md not registered" "v7.11.0 feature: intent contract skill should be registered"
    fi
fi

# Test 10: Verify v7.11.0 features exist
echo ""
echo "Test 10: Verifying v7.11.0 feature files exist..."
NEW_FILES=(
    ".claude/commands/plan.md"
    ".claude/skills/skill-intent-contract.md"
)

missing_files=0
for file in "${NEW_FILES[@]}"; do
    full_path="$PROJECT_ROOT/$file"
    if [[ -f "$full_path" ]]; then
        pass "v7.11.0 feature file exists: $file"
    else
        fail "Missing v7.11.0 feature file" "Expected: $file"
        ((missing_files++))
    fi
done

# Test 11: Verify modified files have 3-question pattern
echo ""
echo "Test 11: Checking modified commands have 3-question pattern..."
MODIFIED_COMMANDS=("discover.md" "review.md" "security.md" "tdd.md")
commands_with_questions=0

for cmd in "${MODIFIED_COMMANDS[@]}"; do
    cmd_path="$PROJECT_ROOT/.claude/commands/$cmd"
    if [[ -f "$cmd_path" ]]; then
        if grep -q "AskUserQuestion" "$cmd_path"; then
            ((commands_with_questions++))
        fi
    fi
done

if [[ $commands_with_questions -ge 3 ]]; then
    pass "$commands_with_questions modified commands have 3-question pattern"
else
    fail "Modified commands missing 3-question pattern" \
        "Found $commands_with_questions with questions, expected at least 3"
fi

# Test 12: Check git tag existence (optional - won't fail if missing)
echo ""
echo "Test 12: Checking for git tag v${EXPECTED_VERSION} (optional)..."
cd "$PROJECT_ROOT"
if git rev-parse "v${EXPECTED_VERSION}" >/dev/null 2>&1; then
    pass "Git tag v${EXPECTED_VERSION} exists"
elif git rev-parse "${EXPECTED_VERSION}" >/dev/null 2>&1; then
    pass "Git tag ${EXPECTED_VERSION} exists (without v prefix)"
else
    info "Git tag v${EXPECTED_VERSION} not found (tag not yet created)"
    # Don't fail - tag might not be created yet
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
    info "Version $EXPECTED_VERSION is consistent across all files"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
