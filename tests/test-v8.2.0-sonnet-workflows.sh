#!/usr/bin/env bash
# Test: v8.2.0 Sonnet 4.6 Agent in Multi-Agent Workflows
# Validates that claude-sonnet is wired into:
#   - grapple_debate() as a 3rd participant (with gemini)
#   - probe_discover() as a 5th perspective
#   - grasp_define() for constraints perspective
#   - ink_deliver() for quality review
#
# NOTE: orchestrate.sh has a main execution block that runs on source,
# so we use grep-based static analysis rather than sourcing the whole file.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")/plugin"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"
SKILL_DEBATE="${PLUGIN_DIR}/.claude/skills/skill-debate.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_pass() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $test_name"
}

assert_fail() {
    local test_name="$1"
    local detail="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $test_name"
    [[ -n "$detail" ]] && echo -e "  ${YELLOW}$detail${NC}"
}

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  🐙 v8.2.0 Sonnet 4.6 in Multi-Agent Workflows            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 1: grapple_debate() - 3-way debate (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 1: grapple_debate() - 3-way Debate${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract grapple_debate function (large function, need ~400 lines)
GRAPPLE_FN=$(grep -A 400 '^grapple_debate()' "$ORCHESTRATE_SH" | head -400)

# 1.1: grapple_debate references claude-sonnet agent
if echo "$GRAPPLE_FN" | grep -q '"claude-sonnet"'; then
    assert_pass "1.1 grapple_debate references claude-sonnet agent"
else
    assert_fail "1.1 grapple_debate references claude-sonnet agent"
fi

# 1.2: grapple_debate references gemini agent for proposals
if echo "$GRAPPLE_FN" | grep -q 'gemini_proposal=$(run_agent_sync "gemini"'; then
    assert_pass "1.2 grapple_debate generates gemini proposal"
else
    assert_fail "1.2 grapple_debate generates gemini proposal"
fi

# 1.3: grapple_debate generates sonnet proposal
if echo "$GRAPPLE_FN" | grep -q 'sonnet_proposal=$(run_agent_sync "claude-sonnet"'; then
    assert_pass "1.3 grapple_debate generates sonnet proposal"
else
    assert_fail "1.3 grapple_debate generates sonnet proposal"
fi

# 1.4: grapple_debate has 3-way critique (codex critiques gemini+sonnet)
if echo "$GRAPPLE_FN" | grep -q 'codex_critique=$(run_agent_sync'; then
    assert_pass "1.4 grapple_debate has codex_critique"
else
    assert_fail "1.4 grapple_debate has codex_critique"
fi

# 1.5: grapple_debate has gemini critique
if echo "$GRAPPLE_FN" | grep -q 'gemini_critique=$(run_agent_sync'; then
    assert_pass "1.5 grapple_debate has gemini_critique"
else
    assert_fail "1.5 grapple_debate has gemini_critique"
fi

# 1.6: grapple_debate has sonnet critique
if echo "$GRAPPLE_FN" | grep -q 'sonnet_critique=$(run_agent_sync'; then
    assert_pass "1.6 grapple_debate has sonnet_critique"
else
    assert_fail "1.6 grapple_debate has sonnet_critique"
fi

# 1.7: Banner shows "Sonnet 4.6"
if echo "$GRAPPLE_FN" | grep -q 'Sonnet 4.6'; then
    assert_pass "1.7 grapple_debate banner mentions Sonnet 4.6"
else
    assert_fail "1.7 grapple_debate banner mentions Sonnet 4.6"
fi

# 1.8: Summary shows 3 participants
if echo "$GRAPPLE_FN" | grep -q 'Codex.*vs.*Gemini.*vs.*Sonnet'; then
    assert_pass "1.8 grapple_debate summary shows 3 participants"
else
    assert_fail "1.8 grapple_debate summary shows 3 participants"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 2: probe_discover() - 5 perspectives (5 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 2: probe_discover() - 5 Perspectives${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract probe_discover function
PROBE_FN=$(grep -A 200 '^probe_discover()' "$ORCHESTRATE_SH" | head -200)

# 2.1: probe_discover includes claude-sonnet in agent list
if echo "$PROBE_FN" | grep -q 'claude-sonnet'; then
    assert_pass "2.1 probe_discover includes claude-sonnet in agent list"
else
    assert_fail "2.1 probe_discover includes claude-sonnet in agent list"
fi

# 2.2: probe_discover has 5 perspectives (count quoted strings in perspectives array)
perspective_count=$(echo "$PROBE_FN" | grep -c '"Analyze the problem\|"Research existing\|"Explore edge\|"Investigate technical\|"Synthesize cross' || echo "0")
if [[ "$perspective_count" -eq 5 ]]; then
    assert_pass "2.2 probe_discover has 5 perspectives (count: $perspective_count)"
else
    assert_fail "2.2 probe_discover has 5 perspectives" "Found: $perspective_count, Expected: 5"
fi

# 2.3: probe_discover has Cross-Synthesis pane
if echo "$PROBE_FN" | grep -q 'Cross-Synthesis'; then
    assert_pass "2.3 probe_discover has Cross-Synthesis pane title"
else
    assert_fail "2.3 probe_discover has Cross-Synthesis pane title"
fi

# 2.4: probe_discover dry-run mentions 5 agents
if echo "$PROBE_FN" | grep -q '5 parallel research agents'; then
    assert_pass "2.4 probe_discover dry-run mentions 5 agents"
else
    assert_fail "2.4 probe_discover dry-run mentions 5 agents"
fi

# 2.5: probe_discover cost estimate uses 5 agents
if echo "$PROBE_FN" | grep -q 'display_workflow_cost_estimate.*5'; then
    assert_pass "2.5 probe_discover cost estimate uses 5 agents"
else
    assert_fail "2.5 probe_discover cost estimate uses 5 agents"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 3: grasp_define() - Sonnet for constraints (3 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 3: grasp_define() - Sonnet for Constraints${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract grasp_define function
GRASP_FN=$(grep -A 100 '^grasp_define()' "$ORCHESTRATE_SH" | head -100)

# 3.1: grasp_define calls claude-sonnet for constraints
if echo "$GRASP_FN" | grep -q 'run_agent_sync "claude-sonnet".*constraints'; then
    assert_pass "3.1 grasp_define calls claude-sonnet for constraints perspective"
else
    assert_fail "3.1 grasp_define calls claude-sonnet for constraints perspective"
fi

# 3.2: grasp_define dry-run mentions 4 perspectives
if echo "$GRASP_FN" | grep -q '4 perspectives'; then
    assert_pass "3.2 grasp_define dry-run mentions 4 perspectives"
else
    assert_fail "3.2 grasp_define dry-run mentions 4 perspectives"
fi

# 3.3: grasp_define still uses codex for problem statement
if echo "$GRASP_FN" | grep -q 'run_agent_sync "codex".*core problem'; then
    assert_pass "3.3 grasp_define still uses codex for problem statement"
else
    assert_fail "3.3 grasp_define still uses codex for problem statement"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 4: ink_deliver() - Sonnet quality review (3 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 4: ink_deliver() - Sonnet Quality Review${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract ink_deliver function
INK_FN=$(grep -A 120 '^ink_deliver()' "$ORCHESTRATE_SH" | head -120)

# 4.1: ink_deliver calls claude-sonnet for quality review
if echo "$INK_FN" | grep -q 'run_agent_sync "claude-sonnet"'; then
    assert_pass "4.1 ink_deliver calls claude-sonnet for quality review"
else
    assert_fail "4.1 ink_deliver calls claude-sonnet for quality review"
fi

# 4.2: ink_deliver has sonnet_review variable
if echo "$INK_FN" | grep -q 'sonnet_review'; then
    assert_pass "4.2 ink_deliver has sonnet_review variable"
else
    assert_fail "4.2 ink_deliver has sonnet_review variable"
fi

# 4.3: ink_deliver synthesis prompt includes quality review
if echo "$INK_FN" | grep -q 'Quality Review'; then
    assert_pass "4.3 ink_deliver synthesis prompt includes Quality Review section"
else
    assert_fail "4.3 ink_deliver synthesis prompt includes Quality Review section"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 5: skill-debate.md updates (2 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 5: skill-debate.md Updates${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 5.1: skill-debate.md mentions Sonnet 4.6
if grep -q 'Sonnet 4.6' "$SKILL_DEBATE"; then
    assert_pass "5.1 skill-debate.md mentions Sonnet 4.6"
else
    assert_fail "5.1 skill-debate.md mentions Sonnet 4.6"
fi

# 5.2: skill-debate.md shows 4 participants (Codex, Gemini, Sonnet, Claude)
participant_count=$(grep -c '🔴\|🟡\|🔵\|🐙' "$SKILL_DEBATE" | head -1 || echo "0")
if grep -q 'Moderator and synthesis' "$SKILL_DEBATE"; then
    assert_pass "5.2 skill-debate.md shows Claude as Moderator and synthesis"
else
    assert_fail "5.2 skill-debate.md shows Claude as Moderator and synthesis"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Test Summary - v8.2.0 Sonnet 4.6 in Multi-Agent Workflows${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total tests:  ${BLUE}$TESTS_RUN${NC}"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All Sonnet 4.6 multi-agent workflow tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ $TESTS_FAILED test(s) failed${NC}"
    exit 1
fi
