#!/usr/bin/env bash
# Test: Sonnet 5 Agent in Multi-Agent Workflows (historical v8.2.0 suite)
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

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "Sonnet 5 Agent in Multi-Agent Workflows"

PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$PLUGIN_DIR"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"
# v9.12: Search orchestrate.sh + lib/*.sh for functions that may have been decomposed
ALL_SRC=$(mktemp)
cat "$ORCHESTRATE_SH" "$(dirname "$ORCHESTRATE_SH")/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT
SKILL_DEBATE="$(resolve_claude_skill_path "skill-debate")"


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
    if [[ -n "$detail" ]]; then
        echo -e "  ${YELLOW}$detail${NC}"
    fi
}

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  🐙 Sonnet 5 in Multi-Agent Workflows                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 1: grapple_debate() - 3-way debate (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 1: grapple_debate() - 3-way Debate${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract grapple_debate function (large function, includes config-driven slots)
GRAPPLE_FN=$(grep -A 820 '^grapple_debate()' "$ALL_SRC" | head -820)

# 1.1: grapple_debate references claude-sonnet agent
if echo "$GRAPPLE_FN" | grep -q 'agent_c="claude-sonnet"'; then
    assert_pass "1.1 grapple_debate references claude-sonnet agent"
else
    assert_fail "1.1 grapple_debate references claude-sonnet agent"
fi

# 1.2: grapple_debate defaults the second debate slot to Antigravity
if echo "$GRAPPLE_FN" | grep -q 'agent_b="agy"'; then
    assert_pass "1.2 grapple_debate defaults slot B to agy"
else
    assert_fail "1.2 grapple_debate defaults slot B to agy"
fi

# 1.3: grapple_debate dispatches the third proposal through the resolved Sonnet slot
if echo "$GRAPPLE_FN" | grep -q 'sonnet_proposal=$(run_agent_sync "$agent_c"'; then
    assert_pass "1.3 grapple_debate generates resolved Sonnet-slot proposal"
else
    assert_fail "1.3 grapple_debate generates resolved Sonnet-slot proposal"
fi

# 1.4: grapple_debate has 3-way critique (Codex critiques AGY + Sonnet)
if echo "$GRAPPLE_FN" | grep -q 'codex_critique=$(run_agent_sync "$agent_a"'; then
    assert_pass "1.4 grapple_debate has codex_critique"
else
    assert_fail "1.4 grapple_debate has codex_critique"
fi

# 1.5: grapple_debate has Antigravity critique
if echo "$GRAPPLE_FN" | grep -q 'agy_critique=$(run_agent_sync "$agent_b"'; then
    assert_pass "1.5 grapple_debate has agy_critique"
else
    assert_fail "1.5 grapple_debate has agy_critique"
fi

# 1.6: grapple_debate has sonnet critique
if echo "$GRAPPLE_FN" | grep -q 'sonnet_critique=$(run_agent_sync "$agent_c"'; then
    assert_pass "1.6 grapple_debate has sonnet_critique"
else
    assert_fail "1.6 grapple_debate has sonnet_critique"
fi

# 1.7: Dry-run banner uses resolved labels instead of hardcoded participants
if echo "$GRAPPLE_FN" | grep -q 'Round 1: Generate competing proposals.*label_a.*label_b.*label_c'; then
    assert_pass "1.7 grapple_debate dry-run uses resolved labels"
else
    assert_fail "1.7 grapple_debate dry-run uses resolved labels"
fi

# 1.8: Summary shows 3 participants
if echo "$GRAPPLE_FN" | grep -q 'label_a.*vs.*label_b.*vs.*label_c'; then
    assert_pass "1.8 grapple_debate summary shows 3 resolved participants"
else
    assert_fail "1.8 grapple_debate summary shows 3 resolved participants"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 2: probe_discover() - 5 perspectives (5 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 2: probe_discover() - 5 Perspectives${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract probe_discover function
PROBE_FN=$(grep -A 200 '^probe_discover()' "$ALL_SRC" | head -200)

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
if echo "$PROBE_FN" | grep -q '5.*parallel research agents'; then
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
GRASP_FN=$(grep -A 100 '^grasp_define()' "$ALL_SRC" | head -100)

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
INK_FN=$(grep -A 150 '^ink_deliver()' "$ALL_SRC" | head -150)

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

# 5.1: skill-debate.md mentions Sonnet 5
if grep -q 'Sonnet 5' "$SKILL_DEBATE"; then
    assert_pass "5.1 skill-debate.md mentions Sonnet 5"
else
    assert_fail "5.1 skill-debate.md mentions Sonnet 5"
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
echo -e "${BLUE}Test Summary - Sonnet 5 in Multi-Agent Workflows${NC}"
test_summary
