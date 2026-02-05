#!/usr/bin/env bash
# Test: v8.0.0 Opus 4.6 & Claude Code 2.1.32 Integration
# Validates all new features introduced in v8.0.0:
#   - claude-opus agent type in orchestrate.sh
#   - Feature flags (SUPPORTS_AGENT_TEAMS, SUPPORTS_AUTO_MEMORY)
#   - Metrics tracker pricing for claude-opus-4-6
#   - Agent config with claude-opus entries
#   - Skill description compression (single-line, <120 chars)
#   - Role mapping updates (strategist, synthesizer)
#   - OpenRouter premium routing to claude-opus-4-6
#
# NOTE: orchestrate.sh has a main execution block that runs on source,
# so we use grep-based static analysis and subshell function extraction
# rather than sourcing the whole file.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")/plugin"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"
METRICS_SH="${PLUGIN_DIR}/scripts/metrics-tracker.sh"
AGENTS_YAML="${PLUGIN_DIR}/agents/config.yaml"
SKILLS_DIR="${PLUGIN_DIR}/.claude/skills"
MODEL_CONFIG_MD="${PLUGIN_DIR}/.claude/commands/model-config.md"
PROVIDER_CLAUDE_MD="${PLUGIN_DIR}/config/providers/claude/CLAUDE.md"
CHANGELOG_MD="${PLUGIN_DIR}/CHANGELOG.md"
PACKAGE_JSON="${PLUGIN_DIR}/package.json"
PLUGIN_CLAUDE_MD="${PLUGIN_DIR}/CLAUDE.md"

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

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Expected: ${expected}"
        echo -e "  Got:      ${actual}"
    fi
}

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  🐙 v8.0.0 Opus 4.6 & Claude Code 2.1.32 Integration     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 1: orchestrate.sh - claude-opus agent type (static analysis)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 1: orchestrate.sh - claude-opus agent type${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1.1: get_agent_command has claude-opus case
if grep -q 'claude-opus) echo "claude --print -m opus"' "$ORCHESTRATE_SH"; then
    assert_pass "1.1 get_agent_command has claude-opus → 'claude --print -m opus'"
else
    assert_fail "1.1 get_agent_command has claude-opus → 'claude --print -m opus'"
fi

# 1.2: get_agent_command_array has claude-opus case
if grep -q 'claude-opus).*_cmd_array=(claude --print -m opus)' "$ORCHESTRATE_SH"; then
    assert_pass "1.2 get_agent_command_array has claude-opus entry"
else
    assert_fail "1.2 get_agent_command_array has claude-opus entry"
fi

# 1.3: AVAILABLE_AGENTS includes claude-opus
if grep -q 'AVAILABLE_AGENTS=.*claude-opus' "$ORCHESTRATE_SH"; then
    assert_pass "1.3 AVAILABLE_AGENTS includes claude-opus"
else
    assert_fail "1.3 AVAILABLE_AGENTS includes claude-opus"
fi

# 1.4: get_model_pricing has claude-opus-4.6
if grep -q 'claude-opus-4\.6.*5\.00:25\.00' "$ORCHESTRATE_SH"; then
    assert_pass "1.4 get_model_pricing has claude-opus-4.6 → 5.00:25.00"
else
    assert_fail "1.4 get_model_pricing has claude-opus-4.6 → 5.00:25.00"
fi

# 1.5: get_agent_model default for claude-opus
if grep -q 'claude-opus).*echo "claude-opus-4\.6"' "$ORCHESTRATE_SH"; then
    assert_pass "1.5 get_agent_model defaults claude-opus to claude-opus-4.6"
else
    assert_fail "1.5 get_agent_model defaults claude-opus to claude-opus-4.6"
fi

# 1.6: claude-opus maps to claude provider for config precedence
if grep -q 'claude|claude-sonnet|claude-opus)' "$ORCHESTRATE_SH"; then
    assert_pass "1.6 claude-opus included in claude provider pattern"
else
    assert_fail "1.6 claude-opus included in claude provider pattern"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 2: Feature flags (v2.1.32)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 2: Feature flags for Claude Code v2.1.32${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 2.1: SUPPORTS_AGENT_TEAMS flag exists
if grep -q "^SUPPORTS_AGENT_TEAMS=" "$ORCHESTRATE_SH"; then
    assert_pass "2.1 SUPPORTS_AGENT_TEAMS flag declared"
else
    assert_fail "2.1 SUPPORTS_AGENT_TEAMS flag declared"
fi

# 2.2: SUPPORTS_AUTO_MEMORY flag exists
if grep -q "^SUPPORTS_AUTO_MEMORY=" "$ORCHESTRATE_SH"; then
    assert_pass "2.2 SUPPORTS_AUTO_MEMORY flag declared"
else
    assert_fail "2.2 SUPPORTS_AUTO_MEMORY flag declared"
fi

# 2.3: AGENT_TEAMS_ENABLED reads env var
if grep -q 'AGENT_TEAMS_ENABLED=.*CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$ORCHESTRATE_SH"; then
    assert_pass "2.3 AGENT_TEAMS_ENABLED reads CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var"
else
    assert_fail "2.3 AGENT_TEAMS_ENABLED reads CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var"
fi

# 2.4: Version detection enables flags at v2.1.32+
if grep -q '2\.1\.32' "$ORCHESTRATE_SH"; then
    assert_pass "2.4 Version check for v2.1.32 exists in detect_claude_code_version()"
else
    assert_fail "2.4 Version check for v2.1.32 exists in detect_claude_code_version()"
fi

# 2.5: Agent Teams indicator in provider status display
if grep -q 'Agent Teams' "$ORCHESTRATE_SH"; then
    assert_pass "2.5 Agent Teams indicator in provider status display"
else
    assert_fail "2.5 Agent Teams indicator in provider status display"
fi

# 2.6: Log line includes Agent Teams flag
if grep -q 'Agent Teams: \$SUPPORTS_AGENT_TEAMS' "$ORCHESTRATE_SH"; then
    assert_pass "2.6 Log line includes Agent Teams flag status"
else
    assert_fail "2.6 Log line includes Agent Teams flag status"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 3: Role mapping updates
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 3: Role mapping updates${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 3.1: strategist role maps to claude-opus
if grep -q 'strategist).*echo "claude-opus:claude-opus-4\.6"' "$ORCHESTRATE_SH"; then
    assert_pass "3.1 strategist role maps to claude-opus:claude-opus-4.6"
else
    assert_fail "3.1 strategist role maps to claude-opus:claude-opus-4.6"
fi

# 3.2: synthesizer role upgraded to claude (from gemini-flash)
if grep -q 'synthesizer).*echo "claude:claude-sonnet-4\.5"' "$ORCHESTRATE_SH"; then
    assert_pass "3.2 synthesizer role upgraded to claude:claude-sonnet-4.5"
else
    assert_fail "3.2 synthesizer role upgraded to claude:claude-sonnet-4.5"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 4: OpenRouter premium routing
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 4: OpenRouter premium routing${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 4.1: Complexity 3 coding routes to claude-opus-4-6
if grep -q 'anthropic/claude-opus-4-6' "$ORCHESTRATE_SH"; then
    assert_pass "4.1 OpenRouter complexity 3 routes to anthropic/claude-opus-4-6"
else
    assert_fail "4.1 OpenRouter complexity 3 routes to anthropic/claude-opus-4-6"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 5: metrics-tracker.sh pricing
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 5: metrics-tracker.sh pricing${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 5.1: claude-opus-4-6 pricing exists in metrics tracker
if grep -q 'claude-opus-4-6.*5\.00' "$METRICS_SH"; then
    assert_pass "5.1 claude-opus-4-6 pricing (\$5.00) in metrics-tracker.sh"
else
    assert_fail "5.1 claude-opus-4-6 pricing (\$5.00) in metrics-tracker.sh"
fi

# 5.2: Source metrics tracker (it's safe - no main block) and test function
source "$METRICS_SH"
result=$(get_model_cost "claude-opus-4-6")
assert_equals "5.00" "$result" "5.2 get_model_cost(claude-opus-4-6) returns 5.00 (function test)"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 6: agents/config.yaml updates
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 6: agents/config.yaml updates${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 6.1: claude-opus listed in CLI options header
if grep -q 'claude-opus' "$AGENTS_YAML"; then
    assert_pass "6.1 claude-opus mentioned in agents/config.yaml"
else
    assert_fail "6.1 claude-opus mentioned in agents/config.yaml"
fi

# 6.2: strategy-analyst agent exists
if grep -q 'strategy-analyst:' "$AGENTS_YAML"; then
    assert_pass "6.2 strategy-analyst agent entry exists"
else
    assert_fail "6.2 strategy-analyst agent entry exists"
fi

# 6.3: research-synthesizer agent exists
if grep -q 'research-synthesizer:' "$AGENTS_YAML"; then
    assert_pass "6.3 research-synthesizer agent entry exists"
else
    assert_fail "6.3 research-synthesizer agent entry exists"
fi

# 6.4: strategy-analyst uses claude-opus CLI
if grep -A 3 'strategy-analyst:' "$AGENTS_YAML" | grep -q 'cli: claude-opus'; then
    assert_pass "6.4 strategy-analyst uses cli: claude-opus"
else
    assert_fail "6.4 strategy-analyst uses cli: claude-opus"
fi

# 6.5: research-synthesizer uses claude-opus CLI
if grep -A 3 'research-synthesizer:' "$AGENTS_YAML" | grep -q 'cli: claude-opus'; then
    assert_pass "6.5 research-synthesizer uses cli: claude-opus"
else
    assert_fail "6.5 research-synthesizer uses cli: claude-opus"
fi

# 6.6: strategy-analyst and research-synthesizer use claude-opus-4.6 model
if grep -A 4 'strategy-analyst:' "$AGENTS_YAML" | grep -q 'model: claude-opus-4.6'; then
    assert_pass "6.6 strategy-analyst uses model: claude-opus-4.6"
else
    assert_fail "6.6 strategy-analyst uses model: claude-opus-4.6"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 7: Skill description compression
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 7: Skill description compression${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 7.1: No multi-line descriptions remaining
multiline_count=0
for skill_file in "$SKILLS_DIR"/*.md; do
    if grep -q '^description: |' "$skill_file"; then
        multiline_count=$((multiline_count + 1))
        echo -e "  ${YELLOW}Multi-line description in: $(basename "$skill_file")${NC}"
    fi
done
if [[ $multiline_count -eq 0 ]]; then
    assert_pass "7.1 No multi-line description: | blocks remain (all 43 compressed)"
else
    assert_fail "7.1 No multi-line description: | blocks remain" "Found $multiline_count files with multi-line descriptions"
fi

# 7.2: All skill files have a description field
missing_desc=0
for skill_file in "$SKILLS_DIR"/*.md; do
    if ! grep -q '^description:' "$skill_file"; then
        missing_desc=$((missing_desc + 1))
        echo -e "  ${YELLOW}Missing description in: $(basename "$skill_file")${NC}"
    fi
done
if [[ $missing_desc -eq 0 ]]; then
    assert_pass "7.2 All skill files have a description field"
else
    assert_fail "7.2 All skill files have a description field" "Missing in $missing_desc files"
fi

# 7.3: Descriptions with colons are properly quoted
bad_yaml=0
for skill_file in "$SKILLS_DIR"/*.md; do
    desc_line=$(grep '^description:' "$skill_file" || true)
    # Extract value after "description: "
    value="${desc_line#description: }"
    # If value contains a colon, it needs to be double-quoted
    if echo "$value" | grep -q ':' && ! echo "$value" | grep -q '^"'; then
        bad_yaml=$((bad_yaml + 1))
        echo -e "  ${YELLOW}Unquoted colon in: $(basename "$skill_file")${NC}"
    fi
done
if [[ $bad_yaml -eq 0 ]]; then
    assert_pass "7.3 All descriptions with colons are properly YAML-quoted"
else
    assert_fail "7.3 All descriptions with colons are properly YAML-quoted" "$bad_yaml files have unquoted colons"
fi

# 7.4: No description exceeds 120 characters
long_desc=0
for skill_file in "$SKILLS_DIR"/*.md; do
    desc_line=$(grep '^description:' "$skill_file" || true)
    value="${desc_line#description: }"
    # Strip quotes for length check
    value="${value#\"}"
    value="${value%\"}"
    if [[ ${#value} -gt 120 ]]; then
        long_desc=$((long_desc + 1))
        echo -e "  ${YELLOW}Description too long (${#value} chars): $(basename "$skill_file")${NC}"
    fi
done
if [[ $long_desc -eq 0 ]]; then
    assert_pass "7.4 All descriptions are 120 chars or under"
else
    assert_fail "7.4 All descriptions are 120 chars or under" "$long_desc files exceed 120 chars"
fi

# 7.5: Correct skill file count
skill_count=$(find "$SKILLS_DIR" -name "*.md" -type f | wc -l | tr -d ' ')
assert_equals "43" "$skill_count" "7.5 Skill directory contains exactly 43 files"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 8: Documentation updates
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 8: Documentation updates${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 8.1: package.json version is 8.0.0
pkg_version=$(grep '"version"' "$PACKAGE_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
assert_equals "8.0.0" "$pkg_version" "8.1 package.json version is 8.0.0"

# 8.2: CHANGELOG has 8.0.0 entry
if grep -q '\[8.0.0\]' "$CHANGELOG_MD"; then
    assert_pass "8.2 CHANGELOG.md has [8.0.0] entry"
else
    assert_fail "8.2 CHANGELOG.md has [8.0.0] entry"
fi

# 8.3: model-config.md references claude-opus-4-6
if grep -q 'claude-opus-4-6' "$MODEL_CONFIG_MD"; then
    assert_pass "8.3 model-config.md references claude-opus-4-6"
else
    assert_fail "8.3 model-config.md references claude-opus-4-6"
fi

# 8.4: Provider CLAUDE.md documents Opus 4.6
if grep -q 'Opus 4.6' "$PROVIDER_CLAUDE_MD"; then
    assert_pass "8.4 Provider CLAUDE.md documents Opus 4.6"
else
    assert_fail "8.4 Provider CLAUDE.md documents Opus 4.6"
fi

# 8.5: Plugin CLAUDE.md has Opus 4.6 pricing
if grep -q 'Opus 4.6' "$PLUGIN_CLAUDE_MD"; then
    assert_pass "8.5 Plugin CLAUDE.md mentions Opus 4.6 in cost awareness"
else
    assert_fail "8.5 Plugin CLAUDE.md mentions Opus 4.6 in cost awareness"
fi

# 8.6: Auto Memory guidance section exists
if grep -q 'Auto Memory Integration' "$PLUGIN_CLAUDE_MD"; then
    assert_pass "8.6 Auto Memory Integration section in CLAUDE.md"
else
    assert_fail "8.6 Auto Memory Integration section in CLAUDE.md"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 9: No stale references
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 9: Stale reference check${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 9.1: No non-legacy claude-opus-4-5 in commands (excluding model-config which has intentional legacy entry)
stale_refs=$(grep -rl 'claude-opus-4-5' "$PLUGIN_DIR/.claude/commands/" 2>/dev/null | grep -v model-config || true)
if [[ -z "$stale_refs" ]]; then
    assert_pass "9.1 No stale claude-opus-4-5 refs in commands (excluding model-config legacy)"
else
    assert_fail "9.1 No stale claude-opus-4-5 refs in commands" "Found in: $stale_refs"
fi

# 9.2: orchestrate.sh has no claude-opus-4-5 references
if grep -q 'claude-opus-4-5' "$ORCHESTRATE_SH"; then
    assert_fail "9.2 orchestrate.sh has no claude-opus-4-5 references"
else
    assert_pass "9.2 orchestrate.sh has no claude-opus-4-5 references"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 10: Bash syntax validation
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 10: Bash syntax validation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 10.1: orchestrate.sh passes bash -n
if bash -n "$ORCHESTRATE_SH" 2>/dev/null; then
    assert_pass "10.1 orchestrate.sh passes bash -n syntax check"
else
    assert_fail "10.1 orchestrate.sh passes bash -n syntax check"
fi

# 10.2: metrics-tracker.sh passes bash -n
if bash -n "$METRICS_SH" 2>/dev/null; then
    assert_pass "10.2 metrics-tracker.sh passes bash -n syntax check"
else
    assert_fail "10.2 metrics-tracker.sh passes bash -n syntax check"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 11: Cost banner dynamic model name
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 11: Cost banner dynamic model name${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 11.1: Cost banner has dynamic model name logic
if grep -q 'claude_model_label=' "$ORCHESTRATE_SH"; then
    assert_pass "11.1 Cost banner uses dynamic claude_model_label variable"
else
    assert_fail "11.1 Cost banner uses dynamic claude_model_label variable"
fi

# 11.2: Cost banner checks for claude-opus in WORKFLOW_AGENTS
if grep -q 'WORKFLOW_AGENTS.*claude-opus' "$ORCHESTRATE_SH"; then
    assert_pass "11.2 Cost banner checks WORKFLOW_AGENTS for claude-opus"
else
    assert_fail "11.2 Cost banner checks WORKFLOW_AGENTS for claude-opus"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Test Summary - v8.0.0 Opus 4.6 Integration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total tests:  ${BLUE}$TESTS_RUN${NC}"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All v8.0.0 integration tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ $TESTS_FAILED test(s) failed${NC}"
    exit 1
fi
