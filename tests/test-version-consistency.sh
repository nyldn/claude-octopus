#!/usr/bin/env bash
# Test Version Consistency for v8.1.0
# Validates that version is consistent across all files and tests new features

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

# Expected version comes from plugin.json (single source of truth)
EXPECTED_VERSION=$(grep '"version"' "$PLUGIN_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [[ -z "$EXPECTED_VERSION" ]]; then
    echo -e "${RED}❌ Could not determine expected version from plugin.json${NC}"
    exit 1
fi

echo -e "${BLUE}🧪 Testing Version Consistency (v${EXPECTED_VERSION})${NC}"
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

# Test 5: Check marketplace.json description mentions current features
echo ""
echo "Test 5: Checking marketplace.json description..."
if [[ -f "$MARKETPLACE_JSON" ]]; then
    description=$(grep -A 5 '"description"' "$MARKETPLACE_JSON" || echo "")

    # Check for key features (multi-AI, workflows, automation)
    mentions_multi_ai=false
    mentions_workflows=false
    mentions_automation=false

    echo "$description" | grep -qi "multi.*ai\|multiple.*ai\|parallel.*ai" && mentions_multi_ai=true
    echo "$description" | grep -qi "workflow\|double.*diamond" && mentions_workflows=true
    echo "$description" | grep -qi "automat\|orchestrat" && mentions_automation=true

    feature_count=0
    $mentions_multi_ai && ((feature_count++))
    $mentions_workflows && ((feature_count++))
    $mentions_automation && ((feature_count++))

    if [[ $feature_count -ge 1 ]]; then
        pass "marketplace.json description mentions core features"
    else
        fail "marketplace.json description outdated" "Should mention multi-AI, workflows, or automation"
    fi
else
    fail "marketplace.json not found" "Expected: $MARKETPLACE_JSON"
fi

# Test 6: Verify command count in plugin.json
echo ""
echo "Test 6: Checking command count in plugin.json..."
if [[ -f "$PLUGIN_JSON" ]]; then
    COMMAND_COUNT=$(grep -o '"\./\.claude/commands/[^"]*\.md"' "$PLUGIN_JSON" | wc -l | tr -d ' ')
    MIN_EXPECTED_COMMANDS=32

    if [[ $COMMAND_COUNT -ge $MIN_EXPECTED_COMMANDS ]]; then
        pass "plugin.json has $COMMAND_COUNT commands (minimum expected: $MIN_EXPECTED_COMMANDS)"
    else
        fail "Command count too low" "Found: $COMMAND_COUNT, Minimum expected: $MIN_EXPECTED_COMMANDS"
    fi
fi

# Test 7: Verify skill count in plugin.json
echo ""
echo "Test 7: Checking skill count in plugin.json..."
if [[ -f "$PLUGIN_JSON" ]]; then
    SKILL_COUNT=$(grep -o '"\./\.claude/skills/[^"]*\.md"' "$PLUGIN_JSON" | wc -l | tr -d ' ')
    EXPECTED_SKILLS=43

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

# Test 10: Verify core command files exist
echo ""
echo "Test 10: Verifying core command files exist..."
CORE_COMMANDS=(
    ".claude/commands/extract.md"
    ".claude/commands/plan.md"
    ".claude/commands/embrace.md"
    ".claude/commands/multi.md"
    ".claude/commands/debate.md"
)

missing_files=0
for file in "${CORE_COMMANDS[@]}"; do
    full_path="$PROJECT_ROOT/$file"
    if [[ -f "$full_path" ]]; then
        pass "Core command exists: $file"
    else
        fail "Missing core command" "Expected: $file"
        ((missing_files++))
    fi
done

# Test 11: Verify v7.19.x features - GitHub release automation
echo ""
echo "Test 11: Checking GitHub release automation (v7.19.3)..."
VALIDATE_RELEASE="$PROJECT_ROOT/scripts/validate-release.sh"
if [[ -f "$VALIDATE_RELEASE" ]]; then
    # Check for auto-create release functionality
    if grep -q "gh release create" "$VALIDATE_RELEASE"; then
        pass "GitHub release auto-creation implemented"
    else
        fail "GitHub release auto-creation missing" "v7.19.3: validate-release.sh should auto-create releases"
    fi

    # Check for --no-verify flag to prevent infinite loop
    if grep -q "\-\-no-verify" "$VALIDATE_RELEASE"; then
        pass "Pre-push hook infinite loop prevention implemented"
    else
        fail "Missing --no-verify flag" "v7.19.3: Should prevent infinite loop in pre-push hook"
    fi
else
    fail "validate-release.sh not found" "Expected: $VALIDATE_RELEASE"
fi

# Test 12: Verify v7.19.2 feature - Gemini agent execution fix
echo ""
echo "Test 12: Checking Gemini agent execution fix (v7.19.2)..."
ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"
if [[ -f "$ORCHESTRATE" ]]; then
    # Check for env prefix in Gemini command
    if grep -q "env NODE_NO_WARNINGS=1 gemini" "$ORCHESTRATE"; then
        pass "Gemini agent execution fix implemented (env prefix)"
    else
        fail "Gemini agent execution fix missing" "v7.19.2: Should use 'env NODE_NO_WARNINGS=1 gemini'"
    fi
else
    fail "orchestrate.sh not found" "Expected: $ORCHESTRATE"
fi

# Test 13: Verify v7.19.0 features - Performance fixes
echo ""
echo "Test 13: Checking performance fixes (v7.19.0)..."
if [[ -f "$ORCHESTRATE" ]]; then
    # Check for result file pipeline improvements
    if grep -q "tee.*processed.*raw" "$ORCHESTRATE"; then
        pass "Result file pipeline fix implemented"
    else
        info "Result file pipeline may use different implementation"
    fi

    # Check for timeout handling
    if grep -q "TIMEOUT.*PARTIAL" "$ORCHESTRATE" || grep -q "124.*timeout" "$ORCHESTRATE"; then
        pass "Timeout partial output preservation implemented"
    else
        info "Timeout handling may use different approach"
    fi
fi

# Test 14: Verify extract command (v7.18.0+ feature)
echo ""
echo "Test 14: Checking /octo:extract command..."
EXTRACT_CMD="$PROJECT_ROOT/.claude/commands/extract.md"
if [[ -f "$EXTRACT_CMD" ]]; then
    if grep -q "gemini" "$EXTRACT_CMD" && grep -q "codex" "$EXTRACT_CMD"; then
        pass "Extract command uses multi-AI extraction"
    else
        info "Extract command exists but may not use multi-AI"
    fi
else
    fail "extract.md command missing" "v7.18.0: /octo:extract should exist"
fi

# Test 15: Check git tag existence (optional - won't fail if missing)
echo ""
echo "Test 15: Checking for git tag v${EXPECTED_VERSION} (optional)..."
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
