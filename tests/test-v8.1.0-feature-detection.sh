#!/usr/bin/env bash
# Test: v8.1.0 Claude Code v2.1.33 Feature Detection & Complexity Routing
# Validates all new features introduced in v8.1.0:
#   - SUPPORTS_PERSISTENT_MEMORY, SUPPORTS_HOOK_EVENTS, SUPPORTS_AGENT_TYPE_ROUTING flags
#   - v2.1.33 version check block in detect_claude_code_version()
#   - Complexity-based Claude agent routing in get_tiered_agent_v2()
#   - Strategist role upgrade for grasp/ink phases
#   - claude-opus in is_agent_available_v2()
#   - Version consistency across package.json, plugin.json, marketplace.json, CHANGELOG, README
#
# NOTE: orchestrate.sh has a main execution block that runs on source,
# so we use grep-based static analysis rather than sourcing the whole file.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "v8.1.0 Claude Code v2.1.33 Feature Detection & Complexity Routing"

PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"
# v9.12: Search orchestrate.sh + lib/*.sh for functions that may have been decomposed
ALL_SRC=$(mktemp)
cat "$ORCHESTRATE_SH" "$(dirname "$ORCHESTRATE_SH")/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT
PACKAGE_JSON="${PLUGIN_DIR}/package.json"
PLUGIN_JSON="${PLUGIN_DIR}/.claude-plugin/plugin.json"
MARKETPLACE_JSON="${PLUGIN_DIR}/.claude-plugin/marketplace.json"
CHANGELOG_MD="$(dirname "$SCRIPT_DIR")/CHANGELOG.md"
README_MD="${PLUGIN_DIR}/README.md"
PLUGIN_CLAUDE_MD="${PLUGIN_DIR}/CLAUDE.md"


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
echo -e "${BLUE}║  🐙 v8.1.0 Feature Detection & Complexity Routing         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 1: v2.1.33 Feature Flag Declarations (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 1: v2.1.33 Feature Flag Declarations${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1.1: SUPPORTS_PERSISTENT_MEMORY declared
if grep -q '^SUPPORTS_PERSISTENT_MEMORY=false' "$ALL_SRC"; then
    assert_pass "1.1 SUPPORTS_PERSISTENT_MEMORY=false declared"
else
    assert_fail "1.1 SUPPORTS_PERSISTENT_MEMORY=false declared"
fi

# 1.2: SUPPORTS_HOOK_EVENTS declared
if grep -q '^SUPPORTS_HOOK_EVENTS=false' "$ALL_SRC"; then
    assert_pass "1.2 SUPPORTS_HOOK_EVENTS=false declared"
else
    assert_fail "1.2 SUPPORTS_HOOK_EVENTS=false declared"
fi

# 1.3: SUPPORTS_AGENT_TYPE_ROUTING declared
if grep -q '^SUPPORTS_AGENT_TYPE_ROUTING=false' "$ALL_SRC"; then
    assert_pass "1.3 SUPPORTS_AGENT_TYPE_ROUTING=false declared"
else
    assert_fail "1.3 SUPPORTS_AGENT_TYPE_ROUTING=false declared"
fi

# 1.4: v2.1.33 version check block exists
if grep -q 'version_compare.*2\.1\.33' "$ALL_SRC"; then
    assert_pass "1.4 v2.1.33 version_compare block exists"
else
    assert_fail "1.4 v2.1.33 version_compare block exists"
fi

# 1.5: SUPPORTS_PERSISTENT_MEMORY set to true in version block
if grep -q 'SUPPORTS_PERSISTENT_MEMORY=true' "$ALL_SRC"; then
    assert_pass "1.5 SUPPORTS_PERSISTENT_MEMORY=true activation in version block"
else
    assert_fail "1.5 SUPPORTS_PERSISTENT_MEMORY=true activation in version block"
fi

# 1.6: SUPPORTS_HOOK_EVENTS set to true in version block
if grep -q 'SUPPORTS_HOOK_EVENTS=true' "$ALL_SRC"; then
    assert_pass "1.6 SUPPORTS_HOOK_EVENTS=true activation in version block"
else
    assert_fail "1.6 SUPPORTS_HOOK_EVENTS=true activation in version block"
fi

# 1.7: SUPPORTS_AGENT_TYPE_ROUTING set to true in version block
if grep -q 'SUPPORTS_AGENT_TYPE_ROUTING=true' "$ALL_SRC"; then
    assert_pass "1.7 SUPPORTS_AGENT_TYPE_ROUTING=true activation in version block"
else
    assert_fail "1.7 SUPPORTS_AGENT_TYPE_ROUTING=true activation in version block"
fi

# 1.8: Log line for new feature flags
if grep -q 'Persistent Memory.*Hook Events.*Agent Type Routing' "$ALL_SRC"; then
    assert_pass "1.8 Log line outputs Persistent Memory, Hook Events, Agent Type Routing"
else
    assert_fail "1.8 Log line outputs Persistent Memory, Hook Events, Agent Type Routing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 2: Complexity-Based Claude Routing (5 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 2: Complexity-Based Claude Routing${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 2.1: Agent type routing gates on SUPPORTS_AGENT_TYPE_ROUTING
if grep -q 'SUPPORTS_AGENT_TYPE_ROUTING.*true' "$ALL_SRC"; then
    assert_pass "2.1 Agent routing gates on SUPPORTS_AGENT_TYPE_ROUTING"
else
    assert_fail "2.1 Agent routing gates on SUPPORTS_AGENT_TYPE_ROUTING"
fi

# 2.2: claude-opus agent type recognized in is_agent_available_v2
if grep -q 'claude-opus)' "$ALL_SRC"; then
    assert_pass "2.2 claude-opus agent type recognized"
else
    assert_fail "2.2 claude-opus agent type recognized"
fi

# 2.3: strategist role exists in agent routing
if grep -q 'strategist).*echo "claude-opus' "$ALL_SRC"; then
    assert_pass "2.3 strategist role maps to claude-opus agent"
else
    assert_fail "2.3 strategist role maps to claude-opus agent"
fi

# 2.4: strategist role maps to premium agent (claude-opus)
if grep -q 'strategist).*echo "claude-opus' "$ALL_SRC"; then
    assert_pass "2.4 strategist role maps to claude-opus for premium phases"
else
    assert_fail "2.4 strategist role maps to claude-opus for premium phases"
fi

# 2.5: is_agent_available_v2 handles claude-opus
if grep -q 'claude|claude-sonnet|claude-opus)' "$ALL_SRC"; then
    assert_pass "2.5 is_agent_available_v2 handles claude-opus agent type"
else
    assert_fail "2.5 is_agent_available_v2 handles claude-opus agent type"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 3: Version Consistency (7 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 3: Version Consistency${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 3.1: package.json version is current
pkg_version=$(grep '"version"' "$PACKAGE_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [[ "$pkg_version" =~ ^(8|9)\. ]]; then
    assert_pass "3.1 package.json version is 8.x/9.x ($pkg_version)"
else
    assert_fail "3.1 package.json version is 8.x/9.x" "Got: $pkg_version"
fi

# 3.2: plugin.json version is current
pj_version=$(grep '"version"' "$PLUGIN_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [[ "$pj_version" =~ ^(8|9)\. ]]; then
    assert_pass "3.2 plugin.json version is 8.x/9.x ($pj_version)"
else
    assert_fail "3.2 plugin.json version is 8.x/9.x" "Got: $pj_version"
fi

# 3.3: marketplace.json version is current
mj_version=$(grep '"version"' "$MARKETPLACE_JSON" | tail -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [[ "$mj_version" =~ ^(8|9)\. ]]; then
    assert_pass "3.3 marketplace.json version is 8.x/9.x ($mj_version)"
else
    assert_fail "3.3 marketplace.json version is 8.x/9.x" "Got: $mj_version"
fi

# 3.4: CHANGELOG exists with version entries (v8.37.0 trimmed pre-8.22.0 history)
if [[ -f "$CHANGELOG_MD" ]] && grep -qE '\[(8|9)\.' "$CHANGELOG_MD"; then
    assert_pass "3.4 CHANGELOG.md has version entries"
else
    assert_fail "3.4 CHANGELOG.md has version entries"
fi

# 3.5: README version badge is current 8.x
if grep -qE 'Version-(8|9)\.' "$README_MD"; then
    assert_pass "3.5 README.md version badge is 8.x/9.x"
else
    assert_fail "3.5 README.md version badge is 8.x/9.x"
fi

# 3.6: README Claude Code badge is v2.1.33+ (accept newer patch/minor)
if grep -Eq 'v2\.1\.(3[3-9]|[4-9][0-9])\+' "$README_MD"; then
    assert_pass "3.6 README.md Claude Code badge is v2.1.33+"
else
    assert_fail "3.6 README.md Claude Code badge is v2.1.33+"
fi

# 3.7: orchestrate.sh passes bash -n syntax check
if bash -n "$ORCHESTRATE_SH" 2>/dev/null; then
    assert_pass "3.7 orchestrate.sh passes bash -n syntax check"
else
    assert_fail "3.7 orchestrate.sh passes bash -n syntax check"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Test Summary - v8.1.0 Feature Detection & Complexity Routing${NC}"
test_summary
