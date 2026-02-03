#!/usr/bin/env bash
# Test v7.22.0 lifecycle command skills exist and are properly structured
# Validates: skill-status, skill-issues, skill-rollback, skill-resume, skill-ship

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}🧪 Testing v7.22.0 Lifecycle Commands${NC}"
echo ""

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

LIFECYCLE_SKILLS=(
    "skill-status.md"
    "skill-issues.md"
    "skill-rollback.md"
    "skill-resume.md"
    "skill-ship.md"
)

echo "Test 1: Checking lifecycle skill files exist..."
for skill in "${LIFECYCLE_SKILLS[@]}"; do
    if [[ -f "$SKILLS_DIR/$skill" ]]; then
        pass "$skill exists"
    else
        fail "$skill not found" "Expected: $SKILLS_DIR/$skill"
    fi
done

echo ""
echo "Test 2: Checking skill files have proper frontmatter..."
for skill in "${LIFECYCLE_SKILLS[@]}"; do
    if [[ -f "$SKILLS_DIR/$skill" ]]; then
        if head -1 "$SKILLS_DIR/$skill" | grep -q "^---$"; then
            pass "$skill has frontmatter delimiter"
        else
            fail "$skill missing frontmatter" "Should start with ---"
        fi
    fi
done

echo ""
echo "Test 3: Checking skills reference octo-state.sh..."
for skill in "${LIFECYCLE_SKILLS[@]}"; do
    if [[ -f "$SKILLS_DIR/$skill" ]]; then
        if grep -q "octo-state.sh" "$SKILLS_DIR/$skill"; then
            pass "$skill references octo-state.sh"
        else
            info "$skill does not reference octo-state.sh (may be intentional)"
        fi
    fi
done

echo ""
echo "Test 4: Checking skills are registered in plugin.json..."
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"
for skill in "${LIFECYCLE_SKILLS[@]}"; do
    skill_path="./.claude/skills/$skill"
    if grep -q "\"$skill_path\"" "$PLUGIN_JSON"; then
        pass "$skill registered in plugin.json"
    else
        fail "$skill not registered" "Should be in plugin.json skills array"
    fi
done

echo ""
echo "Test 5: Checking skill-status.md content..."
STATUS_SKILL="$SKILLS_DIR/skill-status.md"
if [[ -f "$STATUS_SKILL" ]]; then
    if grep -qi "status\|dashboard\|progress" "$STATUS_SKILL"; then
        pass "skill-status.md mentions status/dashboard/progress"
    else
        fail "skill-status.md missing key content" "Should mention status, dashboard, or progress"
    fi
fi

echo ""
echo "Test 6: Checking skill-issues.md content..."
ISSUES_SKILL="$SKILLS_DIR/skill-issues.md"
if [[ -f "$ISSUES_SKILL" ]]; then
    if grep -qi "issue\|track\|CRUD\|add\|resolve" "$ISSUES_SKILL"; then
        pass "skill-issues.md mentions issue tracking"
    else
        fail "skill-issues.md missing key content" "Should mention issue tracking operations"
    fi
fi

echo ""
echo "Test 7: Checking skill-rollback.md content..."
ROLLBACK_SKILL="$SKILLS_DIR/skill-rollback.md"
if [[ -f "$ROLLBACK_SKILL" ]]; then
    if grep -qi "rollback\|checkpoint\|restore\|git.*tag" "$ROLLBACK_SKILL"; then
        pass "skill-rollback.md mentions rollback/checkpoint"
    else
        fail "skill-rollback.md missing key content" "Should mention rollback or checkpoint"
    fi
fi

echo ""
echo "Test 8: Checking skill-resume.md content..."
RESUME_SKILL="$SKILLS_DIR/skill-resume.md"
if [[ -f "$RESUME_SKILL" ]]; then
    if grep -qi "resume\|restore\|session\|context" "$RESUME_SKILL"; then
        pass "skill-resume.md mentions resume/session"
    else
        fail "skill-resume.md missing key content" "Should mention resume or session restoration"
    fi
fi

echo ""
echo "Test 9: Checking skill-ship.md content..."
SHIP_SKILL="$SKILLS_DIR/skill-ship.md"
if [[ -f "$SHIP_SKILL" ]]; then
    if grep -qi "ship\|deliver\|multi-ai\|validation" "$SHIP_SKILL"; then
        pass "skill-ship.md mentions ship/deliver"
    else
        fail "skill-ship.md missing key content" "Should mention ship or delivery validation"
    fi
fi

echo ""
echo "Test 10: Checking templates directory..."
TEMPLATES_DIR="$PROJECT_ROOT/templates"
EXPECTED_TEMPLATES=(
    "PROJECT.md.template"
    "ROADMAP.md.template"
    "STATE.md.template"
    "config.json.template"
    "ISSUES.md.template"
    "LESSONS.md.template"
)

for template in "${EXPECTED_TEMPLATES[@]}"; do
    if [[ -f "$TEMPLATES_DIR/$template" ]]; then
        pass "$template exists"
    else
        fail "$template not found" "Expected: $TEMPLATES_DIR/$template"
    fi
done

echo ""
echo "Test 11: Checking CHANGELOG.md mentions v7.22.0..."
CHANGELOG="$PROJECT_ROOT/CHANGELOG.md"
if [[ -f "$CHANGELOG" ]]; then
    if grep -q "7.22.0" "$CHANGELOG"; then
        pass "CHANGELOG.md mentions v7.22.0"
    else
        fail "CHANGELOG.md missing v7.22.0" "Should document v7.22.0 release"
    fi
fi

echo ""
echo "Test 12: Checking COMMAND-REFERENCE.md updated..."
CMD_REF="$PROJECT_ROOT/docs/COMMAND-REFERENCE.md"
if [[ -f "$CMD_REF" ]]; then
    lifecycle_commands=("status" "issues" "rollback" "resume" "ship")
    for cmd in "${lifecycle_commands[@]}"; do
        if grep -qi "/octo:$cmd" "$CMD_REF"; then
            pass "COMMAND-REFERENCE.md documents /octo:$cmd"
        else
            fail "COMMAND-REFERENCE.md missing /octo:$cmd" "Should document the command"
        fi
    done
fi

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
    info "v7.22.0 lifecycle commands are properly configured"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
