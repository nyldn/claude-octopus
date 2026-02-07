#!/usr/bin/env bash
# Test: v8.2.0 Agent Persona Enhanced Fields & Skills Preloading
# Validates all new features introduced in v8.2.0:
#   - memory, skills, permissionMode fields in agents/config.yaml
#   - Helper functions: get_agent_memory, get_agent_skills, get_agent_permission_mode,
#     load_agent_skill_content, build_skill_context
#   - Skills injection in spawn_agent()
#   - Version consistency across all manifests
#
# NOTE: orchestrate.sh has a main execution block that runs on source,
# so we use grep-based static analysis rather than sourcing the whole file.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"
CONFIG_YAML="${PLUGIN_DIR}/agents/config.yaml"
PACKAGE_JSON="${PLUGIN_DIR}/package.json"
PLUGIN_JSON="${PLUGIN_DIR}/.claude-plugin/plugin.json"
MARKETPLACE_JSON="${PLUGIN_DIR}/.claude-plugin/marketplace.json"
CHANGELOG_MD="$(dirname "$SCRIPT_DIR")/CHANGELOG.md"
README_MD="${PLUGIN_DIR}/README.md"

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
echo -e "${BLUE}║  🐙 v8.2.0 Agent Persona Enhanced Fields & Skills         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 1: Config.yaml Field Declarations (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 1: Config.yaml Field Declarations${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1.1: permissionMode exists for probe agent (ai-engineer)
if grep -A 10 '  ai-engineer:' "$CONFIG_YAML" | grep -q 'permissionMode: plan'; then
    assert_pass "1.1 ai-engineer has permissionMode: plan (probe agent)"
else
    assert_fail "1.1 ai-engineer has permissionMode: plan (probe agent)"
fi

# 1.2: permissionMode exists for tangle agent (tdd-orchestrator)
if grep -A 10 '  tdd-orchestrator:' "$CONFIG_YAML" | grep -q 'permissionMode: acceptEdits'; then
    assert_pass "1.2 tdd-orchestrator has permissionMode: acceptEdits (tangle agent)"
else
    assert_fail "1.2 tdd-orchestrator has permissionMode: acceptEdits (tangle agent)"
fi

# 1.3: permissionMode exists for ink agent (code-reviewer)
if grep -A 10 '  code-reviewer:' "$CONFIG_YAML" | grep -q 'permissionMode: default'; then
    assert_pass "1.3 code-reviewer has permissionMode: default (ink agent)"
else
    assert_fail "1.3 code-reviewer has permissionMode: default (ink agent)"
fi

# 1.4: memory: project exists for code-reviewer
if grep -A 10 '  code-reviewer:' "$CONFIG_YAML" | grep -q 'memory: project'; then
    assert_pass "1.4 code-reviewer has memory: project"
else
    assert_fail "1.4 code-reviewer has memory: project"
fi

# 1.5: memory: project exists for security-auditor
if grep -A 10 '  security-auditor:' "$CONFIG_YAML" | grep -q 'memory: project'; then
    assert_pass "1.5 security-auditor has memory: project"
else
    assert_fail "1.5 security-auditor has memory: project"
fi

# 1.6: skills field exists for code-reviewer -> skill-code-review
if grep -A 10 '  code-reviewer:' "$CONFIG_YAML" | grep -q 'skills:.*skill-code-review'; then
    assert_pass "1.6 code-reviewer has skills: [skill-code-review]"
else
    assert_fail "1.6 code-reviewer has skills: [skill-code-review]"
fi

# 1.7: skills field exists for tdd-orchestrator -> skill-tdd
if grep -A 10 '  tdd-orchestrator:' "$CONFIG_YAML" | grep -q 'skills:.*skill-tdd'; then
    assert_pass "1.7 tdd-orchestrator has skills: [skill-tdd]"
else
    assert_fail "1.7 tdd-orchestrator has skills: [skill-tdd]"
fi

# 1.8: All 23 agents have permissionMode field (count indented lines only, not comments)
agent_count=$(grep -c '^    permissionMode:' "$CONFIG_YAML" || echo "0")
if [[ "$agent_count" -eq 23 ]]; then
    assert_pass "1.8 All 23 agents have permissionMode field (count: $agent_count)"
else
    assert_fail "1.8 All 23 agents have permissionMode field" "Found: $agent_count, Expected: 23"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 2: Helper Functions in orchestrate.sh (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 2: Helper Functions in orchestrate.sh${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 2.1: get_agent_memory() function exists
if grep -q '^get_agent_memory()' "$ORCHESTRATE_SH"; then
    assert_pass "2.1 get_agent_memory() function exists"
else
    assert_fail "2.1 get_agent_memory() function exists"
fi

# 2.2: get_agent_skills() function exists
if grep -q '^get_agent_skills()' "$ORCHESTRATE_SH"; then
    assert_pass "2.2 get_agent_skills() function exists"
else
    assert_fail "2.2 get_agent_skills() function exists"
fi

# 2.3: get_agent_permission_mode() function exists
if grep -q '^get_agent_permission_mode()' "$ORCHESTRATE_SH"; then
    assert_pass "2.3 get_agent_permission_mode() function exists"
else
    assert_fail "2.3 get_agent_permission_mode() function exists"
fi

# 2.4: load_agent_skill_content() function exists
if grep -q '^load_agent_skill_content()' "$ORCHESTRATE_SH"; then
    assert_pass "2.4 load_agent_skill_content() function exists"
else
    assert_fail "2.4 load_agent_skill_content() function exists"
fi

# 2.5: build_skill_context() function exists
if grep -q '^build_skill_context()' "$ORCHESTRATE_SH"; then
    assert_pass "2.5 build_skill_context() function exists"
else
    assert_fail "2.5 build_skill_context() function exists"
fi

# 2.6: Functions use get_agent_config internally
if grep -A 5 'get_agent_memory()' "$ORCHESTRATE_SH" | grep -q 'get_agent_config'; then
    assert_pass "2.6 get_agent_memory uses get_agent_config internally"
else
    assert_fail "2.6 get_agent_memory uses get_agent_config internally"
fi

# 2.7: load_agent_skill_content strips YAML frontmatter (awk pattern)
if grep -A 10 'load_agent_skill_content()' "$ORCHESTRATE_SH" | grep -q 'in_fm.*past_fm'; then
    assert_pass "2.7 load_agent_skill_content strips YAML frontmatter (awk pattern)"
else
    assert_fail "2.7 load_agent_skill_content strips YAML frontmatter (awk pattern)"
fi

# 2.8: build_skill_context iterates skills list
if grep -A 15 'build_skill_context()' "$ORCHESTRATE_SH" | grep -q 'for skill in'; then
    assert_pass "2.8 build_skill_context iterates skills list"
else
    assert_fail "2.8 build_skill_context iterates skills list"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 3: spawn_agent Skills Injection (6 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 3: spawn_agent Skills Injection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 3.1: spawn_agent references build_skill_context
if grep -A 100 '^spawn_agent()' "$ORCHESTRATE_SH" | grep -q 'build_skill_context'; then
    assert_pass "3.1 spawn_agent references build_skill_context"
else
    assert_fail "3.1 spawn_agent references build_skill_context"
fi

# 3.2: spawn_agent references select_curated_agent for skill lookup
if grep -A 100 '^spawn_agent()' "$ORCHESTRATE_SH" | grep -q 'select_curated_agent.*prompt.*phase'; then
    assert_pass "3.2 spawn_agent references select_curated_agent for skill lookup"
else
    assert_fail "3.2 spawn_agent references select_curated_agent for skill lookup"
fi

# 3.3: Skills injection gated behind SUPPORTS_AGENT_TYPE_ROUTING
if grep -A 100 '^spawn_agent()' "$ORCHESTRATE_SH" | grep -q 'SUPPORTS_AGENT_TYPE_ROUTING.*true'; then
    assert_pass "3.3 Skills injection gated behind SUPPORTS_AGENT_TYPE_ROUTING"
else
    assert_fail "3.3 Skills injection gated behind SUPPORTS_AGENT_TYPE_ROUTING"
fi

# 3.4: Debug log line for skill context injection exists
if grep -q 'Injected skill context for agent' "$ORCHESTRATE_SH"; then
    assert_pass "3.4 Debug log line for skill context injection exists"
else
    assert_fail "3.4 Debug log line for skill context injection exists"
fi

# 3.5: Debug log line for agent memory/permissionMode exists
if grep -q 'Agent fields: memory=.*permissionMode=' "$ORCHESTRATE_SH"; then
    assert_pass "3.5 Debug log line for agent memory/permissionMode exists"
else
    assert_fail "3.5 Debug log line for agent memory/permissionMode exists"
fi

# 3.6: Skill content prepended before persona+prompt (skill_context before enhanced_prompt)
if grep -A 100 '^spawn_agent()' "$ORCHESTRATE_SH" | grep -q 'enhanced_prompt="${skill_context}'; then
    assert_pass "3.6 Skill content prepended before persona+prompt"
else
    assert_fail "3.6 Skill content prepended before persona+prompt"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 4: Version Consistency (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 4: Version Consistency${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 4.1: package.json version is 8.x
pkg_version=$(grep '"version"' "$PACKAGE_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [[ "$pkg_version" =~ ^8\. ]]; then
    assert_pass "4.1 package.json version is 8.x ($pkg_version)"
else
    assert_fail "4.1 package.json version is 8.x" "Got: $pkg_version"
fi

# 4.2: plugin.json version is 8.x
pj_version=$(grep '"version"' "$PLUGIN_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [[ "$pj_version" =~ ^8\. ]]; then
    assert_pass "4.2 plugin.json version is 8.x ($pj_version)"
else
    assert_fail "4.2 plugin.json version is 8.x" "Got: $pj_version"
fi

# 4.3: marketplace.json version is 8.x
mj_version=$(grep '"version"' "$MARKETPLACE_JSON" | tail -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [[ "$mj_version" =~ ^8\. ]]; then
    assert_pass "4.3 marketplace.json version is 8.x ($mj_version)"
else
    assert_fail "4.3 marketplace.json version is 8.x" "Got: $mj_version"
fi

# 4.4: CHANGELOG has [8.2.0] section
if grep -q '\[8\.2\.0\]' "$CHANGELOG_MD"; then
    assert_pass "4.4 CHANGELOG.md has [8.2.0] section"
else
    assert_fail "4.4 CHANGELOG.md has [8.2.0] section"
fi

# 4.5: README badge shows 8.x
if grep -q 'Version-8\.' "$README_MD"; then
    assert_pass "4.5 README.md badge shows 8.x"
else
    assert_fail "4.5 README.md badge shows 8.x"
fi

# 4.6: plugin.json description mentions v8.x
if grep -q 'v8\.' "$PLUGIN_JSON"; then
    assert_pass "4.6 plugin.json description mentions v8.x"
else
    assert_fail "4.6 plugin.json description mentions v8.x"
fi

# 4.7: CHANGELOG mentions "Agent Persona Enhanced Fields"
if grep -qi 'Agent persona enhanced fields' "$CHANGELOG_MD"; then
    assert_pass "4.7 CHANGELOG mentions Agent Persona Enhanced Fields"
else
    assert_fail "4.7 CHANGELOG mentions Agent Persona Enhanced Fields"
fi

# 4.8: CHANGELOG mentions "Skills Preloading"
if grep -qi 'Skills preloading' "$CHANGELOG_MD"; then
    assert_pass "4.8 CHANGELOG mentions Skills Preloading"
else
    assert_fail "4.8 CHANGELOG mentions Skills Preloading"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Test Summary - v8.2.0 Agent Persona Enhanced Fields${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total tests:  ${BLUE}$TESTS_RUN${NC}"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All v8.2.0 agent persona enhanced fields tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ $TESTS_FAILED test(s) failed${NC}"
    exit 1
fi
