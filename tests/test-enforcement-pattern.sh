#!/usr/bin/env bash
# Test Enforcement Pattern Implementation
# Validates that all orchestrate.sh-based skills follow the standardized structure:
# - Frontmatter with execution_mode: enforced
# - Imperative directives (FORBIDDEN, MUST)
# - Numbered execution steps (Step 1-4)
# - orchestrate.sh invocation
# - Visual indicator banners
# - Attribution footer
# - Prohibition section (What NOT to do)
#
# IMPORTANT: These tests verify DOCUMENTATION structure only, not runtime enforcement.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Skills that must use enforcement pattern
ENFORCE_SKILLS=(
    "$PROJECT_ROOT/.claude/skills/skill-deep-research.md"
    "$PROJECT_ROOT/.claude/skills/flow-discover.md"
    "$PROJECT_ROOT/.claude/skills/flow-define.md"
    "$PROJECT_ROOT/.claude/skills/flow-develop.md"
    "$PROJECT_ROOT/.claude/skills/flow-deliver.md"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}Testing Enforcement Pattern Implementation${NC}"
echo ""

# Helper functions
pass() {
    TEST_COUNT=$((TEST_COUNT + 1))
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    TEST_COUNT=$((TEST_COUNT + 1))
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}FAIL${NC}: $1"
    echo -e "   ${YELLOW}$2${NC}"
}

info() {
    echo -e "${BLUE}i${NC}  $1"
}

# Test 1: Check CLAUDE.md has enforcement best practices
echo "Test 1: Checking CLAUDE.md for enforcement best practices..."
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
if grep -q "Enforcement Best Practices" "$CLAUDE_MD" && \
   grep -q "Validation Gate Pattern" "$CLAUDE_MD"; then
    pass "CLAUDE.md documents Validation Gate Pattern"
else
    fail "CLAUDE.md missing enforcement documentation" \
         "Should have 'Enforcement Best Practices' section with 'Validation Gate Pattern'"
fi

# Test 2: Check each skill file exists
echo ""
echo "Test 2: Checking all enforcement-pattern skills exist..."
all_exist=true
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if [[ ! -f "$skill_file" ]]; then
        all_exist=false
        fail "Skill file missing: $(basename "$skill_file")" "Expected: $skill_file"
    fi
done
if $all_exist; then
    pass "All 5 enforcement-pattern skills exist"
fi

# Test 3: Check frontmatter has execution_mode: enforced
echo ""
echo "Test 3: Checking frontmatter has 'execution_mode: enforced'..."
skills_with_mode=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "execution_mode: enforced" "$skill_file"; then
        ((skills_with_mode++)) || true
    else
        fail "$(basename "$skill_file") missing 'execution_mode: enforced'" \
             "Should be in frontmatter YAML"
    fi
done
if [[ $skills_with_mode -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have 'execution_mode: enforced'"
fi

# Test 4: Check for imperative language (FORBIDDEN, MUST)
echo ""
echo "Test 4: Checking for imperative language..."
skills_with_imperatives=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    has_forbidden=$(grep -c "FORBIDDEN" "$skill_file" || echo 0)
    has_must=$(grep -c "MUST" "$skill_file" || echo 0)

    if [[ $has_forbidden -ge 1 && $has_must -ge 1 ]]; then
        ((skills_with_imperatives++)) || true
    else
        fail "$(basename "$skill_file") weak imperative language" \
             "Should use 'FORBIDDEN' and 'MUST' directives"
    fi
done
if [[ $skills_with_imperatives -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills use imperative language (FORBIDDEN, MUST)"
fi

# Test 5: Check for numbered execution steps (## Step 1, ## Step 2)
echo ""
echo "Test 5: Checking for numbered execution steps..."
skills_with_steps=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "## Step 1:" "$skill_file" && \
       grep -q "## Step 2:" "$skill_file"; then
        ((skills_with_steps++)) || true
    else
        fail "$(basename "$skill_file") missing numbered steps" \
             "Should have '## Step 1:', '## Step 2:', etc."
    fi
done
if [[ $skills_with_steps -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have numbered execution steps"
fi

# Test 6: Check for orchestrate.sh reference
echo ""
echo "Test 6: Checking for orchestrate.sh invocation..."
skills_with_orchestrate=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "orchestrate.sh" "$skill_file"; then
        ((skills_with_orchestrate++)) || true
    else
        fail "$(basename "$skill_file") missing orchestrate.sh reference" \
             "Should invoke orchestrate.sh via Bash"
    fi
done
if [[ $skills_with_orchestrate -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills reference orchestrate.sh"
fi

# Test 7: Check for visual indicators (octopus banner)
echo ""
echo "Test 7: Checking for visual indicator banners..."
skills_with_indicators=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "CLAUDE OCTOPUS ACTIVATED" "$skill_file"; then
        ((skills_with_indicators++)) || true
    else
        fail "$(basename "$skill_file") missing visual indicators" \
             "Should have 'CLAUDE OCTOPUS ACTIVATED' banner"
    fi
done
if [[ $skills_with_indicators -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have visual indicator banners"
fi

# Test 8: Check for attribution footer
echo ""
echo "Test 8: Checking for multi-AI attribution footer..."
skills_with_attribution=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "Multi-AI" "$skill_file" && \
       grep -q "Providers:" "$skill_file"; then
        ((skills_with_attribution++)) || true
    else
        fail "$(basename "$skill_file") missing attribution footer" \
             "Should include 'Multi-AI' text and 'Providers:' line"
    fi
done
if [[ $skills_with_attribution -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills include multi-AI attribution"
fi

# Test 9: Check for prohibition section (What NOT to do)
echo ""
echo "Test 9: Checking for prohibition section..."
skills_with_prohibitions=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "What NOT to do" "$skill_file"; then
        ((skills_with_prohibitions++)) || true
    else
        fail "$(basename "$skill_file") missing prohibition section" \
             "Should have '## What NOT to do' section"
    fi
done
if [[ $skills_with_prohibitions -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have prohibition section"
fi

# Test 10: Check for no suggestive language in enforcement directives
echo ""
echo "Test 10: Checking for removal of suggestive language..."
skills_clean=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    # Check the imperative section (between STOP/READ and first Step) for weak language
    if grep -qi "you should execute\|recommended to execute\|consider calling" "$skill_file"; then
        fail "$(basename "$skill_file") has suggestive language" \
             "Should use imperative directives, not suggestions"
    else
        ((skills_clean++)) || true
    fi
done
if [[ $skills_clean -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills use imperative language without suggestions"
fi

# Summary
echo ""
echo "---"
echo -e "${BLUE}Test Summary${NC}"
echo "---"
echo -e "Total tests:  ${BLUE}$TEST_COUNT${NC}"
echo -e "Passed:       ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed:       ${RED}$FAIL_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All enforcement pattern documentation tests passed!${NC}"
    echo ""
    info "All 5 orchestrate.sh skills have consistent enforcement pattern documentation"
    exit 0
else
    echo -e "${RED}Some enforcement documentation tests failed${NC}"
    exit 1
fi
