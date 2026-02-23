#!/bin/bash
# Test Suite: Claude Code 2.1.14 Feature Integration
# Tests for context: fork, agent fields, session ID, and related features

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
test_start() {
    ((TESTS_RUN++))
    echo -e "\n${BLUE}[TEST $TESTS_RUN]${NC} $1"
}

test_pass() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

test_fail() {
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: $1"
}

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Code 2.1.14 Feature Integration Tests            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Test 1: Version check updated to 2.1.14
# =============================================================================
test_start "Verify minimum version is 2.1.14 in orchestrate.sh"
if grep -q 'min_version="2.1.14"' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
    test_pass "orchestrate.sh has min_version=2.1.14"
else
    test_fail "orchestrate.sh should have min_version=2.1.14"
fi

# =============================================================================
# Test 2: skill-prd.md has context: fork and agent: Plan
# =============================================================================
test_start "skill-prd.md has context: fork"
if grep -q '^context: fork' "$PROJECT_ROOT/.claude/skills/skill-prd.md"; then
    test_pass "skill-prd.md has context: fork"
else
    test_fail "skill-prd.md should have context: fork"
fi

test_start "skill-prd.md has agent: Plan"
if grep -q '^agent: Plan' "$PROJECT_ROOT/.claude/skills/skill-prd.md"; then
    test_pass "skill-prd.md has agent: Plan"
else
    test_fail "skill-prd.md should have agent: Plan"
fi

# =============================================================================
# Test 3: skill-code-review.md has context: fork and agent: Explore
# =============================================================================
test_start "skill-code-review.md has context: fork"
if grep -q '^context: fork' "$PROJECT_ROOT/.claude/skills/skill-code-review.md"; then
    test_pass "skill-code-review.md has context: fork"
else
    test_fail "skill-code-review.md should have context: fork"
fi

test_start "skill-code-review.md has agent: Explore"
if grep -q '^agent: Explore' "$PROJECT_ROOT/.claude/skills/skill-code-review.md"; then
    test_pass "skill-code-review.md has agent: Explore"
else
    test_fail "skill-code-review.md should have agent: Explore"
fi

# =============================================================================
# Test 4: skill-debate.md has context: fork
# =============================================================================
test_start "skill-debate.md has context: fork"
if grep -q '^context: fork' "$PROJECT_ROOT/.claude/skills/skill-debate.md"; then
    test_pass "skill-debate.md has context: fork"
else
    test_fail "skill-debate.md should have context: fork"
fi

# =============================================================================
# Test 5: skill-deep-research.md has context: fork and agent: Explore
# =============================================================================
test_start "skill-deep-research.md has context: fork"
if grep -q '^context: fork' "$PROJECT_ROOT/.claude/skills/skill-deep-research.md"; then
    test_pass "skill-deep-research.md has context: fork"
else
    test_fail "skill-deep-research.md should have context: fork"
fi

test_start "skill-deep-research.md has agent: Explore"
if grep -q '^agent: Explore' "$PROJECT_ROOT/.claude/skills/skill-deep-research.md"; then
    test_pass "skill-deep-research.md has agent: Explore"
else
    test_fail "skill-deep-research.md should have agent: Explore"
fi

# =============================================================================
# Test 6: flow-discover.md has session ID in banner
# =============================================================================
test_start "flow-discover.md has session ID in visual banner"
if grep -q 'Session: \${CLAUDE_SESSION_ID}' "$PROJECT_ROOT/.claude/skills/flow-discover.md"; then
    test_pass "flow-discover.md has session ID in banner"
else
    test_fail "flow-discover.md should have session ID in banner"
fi

# =============================================================================
# Test 7: flow-define.md has session ID in banner
# =============================================================================
test_start "flow-define.md has session ID in visual banner"
if grep -q 'Session: \${CLAUDE_SESSION_ID}' "$PROJECT_ROOT/.claude/skills/flow-define.md"; then
    test_pass "flow-define.md has session ID in banner"
else
    test_fail "flow-define.md should have session ID in banner"
fi

# =============================================================================
# Test 8: flow-develop.md has session ID in banner
# =============================================================================
test_start "flow-develop.md has session ID in visual banner"
if grep -q 'Session: \${CLAUDE_SESSION_ID}' "$PROJECT_ROOT/.claude/skills/flow-develop.md"; then
    test_pass "flow-develop.md has session ID in banner"
else
    test_fail "flow-develop.md should have session ID in banner"
fi

# =============================================================================
# Test 9: flow-deliver.md has session ID in banner
# =============================================================================
test_start "flow-deliver.md has session ID in visual banner"
if grep -q 'Session: \${CLAUDE_SESSION_ID}' "$PROJECT_ROOT/.claude/skills/flow-deliver.md"; then
    test_pass "flow-deliver.md has session ID in banner"
else
    test_fail "flow-deliver.md should have session ID in banner"
fi

# =============================================================================
# Test 10: flow-discover.md has native background tasks section
# =============================================================================
test_start "flow-discover.md has native background tasks section"
if grep -q 'Native Background Tasks' "$PROJECT_ROOT/.claude/skills/flow-discover.md"; then
    test_pass "flow-discover.md has native background tasks documentation"
else
    test_fail "flow-discover.md should have native background tasks documentation"
fi

# =============================================================================
# Test 11: skill-architecture.md has LSP integration guidance
# =============================================================================
test_start "skill-architecture.md has LSP integration guidance"
if grep -q 'LSP Integration' "$PROJECT_ROOT/.claude/skills/skill-architecture.md"; then
    test_pass "skill-architecture.md has LSP integration guidance"
else
    test_fail "skill-architecture.md should have LSP integration guidance"
fi

# =============================================================================
# Test 15: Validate all updated skills still have valid YAML frontmatter
# =============================================================================
test_start "Validate updated skills have valid YAML frontmatter"
valid=true
for skill in skill-prd.md skill-code-review.md skill-debate.md skill-deep-research.md; do
    skill_path="$PROJECT_ROOT/.claude/skills/$skill"
    if [[ -f "$skill_path" ]]; then
        # Check for opening and closing YAML delimiters
        if ! head -n 1 "$skill_path" | grep -q "^---$"; then
            echo "  $skill: Missing opening YAML delimiter"
            valid=false
        fi
        if ! awk '/^---$/{count++; if(count==2) found=1} END{exit !found}' "$skill_path"; then
            echo "  $skill: Missing closing YAML delimiter"
            valid=false
        fi
        # Check for name field
        if ! grep -q "^name:" "$skill_path"; then
            echo "  $skill: Missing name field"
            valid=false
        fi
    else
        echo "  $skill: File not found"
        valid=false
    fi
done

if $valid; then
    test_pass "All updated skills have valid YAML frontmatter"
else
    test_fail "Some updated skills have invalid YAML frontmatter"
fi

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Test Summary                                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Total tests run: ${BLUE}$TESTS_RUN${NC}"
echo -e "Tests passed:    ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed:    ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All Claude Code 2.1.14 feature tests passed!${NC}"
    echo ""
    echo "Verified features:"
    echo "  - Minimum version updated to 2.1.14 ✓"
    echo "  - context: fork added to heavy skills ✓"
    echo "  - agent field added to specialized skills ✓"
    echo "  - Session ID in visual banners ✓"
    echo "  - Native background tasks documentation ✓"
    echo "  - LSP integration guidance ✓"
    echo "  - YAML frontmatter validity ✓"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
