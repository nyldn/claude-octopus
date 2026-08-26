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

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "v8.2.0 Agent Persona Enhanced Fields & Skills Preloading"

PLUGIN_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"
# v9.12: Search orchestrate.sh + lib/*.sh for functions that may have been decomposed
ALL_SRC=$(mktemp)
cat "$ORCHESTRATE_SH" "$(dirname "$ORCHESTRATE_SH")/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT
CONFIG_YAML="${PLUGIN_DIR}/agents/config.yaml"
PACKAGE_JSON="${PLUGIN_DIR}/package.json"
PLUGIN_JSON="${PLUGIN_DIR}/.claude-plugin/plugin.json"
MARKETPLACE_JSON="${PLUGIN_DIR}/.claude-plugin/marketplace.json"
CHANGELOG_MD="$(dirname "$(dirname "$SCRIPT_DIR")")/CHANGELOG.md"
README_MD="${PLUGIN_DIR}/README.md"


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
if grep -A 10 '  ai-engineer:' "$CONFIG_YAML" | grep 'permissionMode: plan' >/dev/null; then
    assert_pass "1.1 ai-engineer has permissionMode: plan (probe agent)"
else
    assert_fail "1.1 ai-engineer has permissionMode: plan (probe agent)"
fi

# 1.2: permissionMode exists for tangle agent (tdd-orchestrator)
if grep -A 10 '  tdd-orchestrator:' "$CONFIG_YAML" | grep 'permissionMode: acceptEdits' >/dev/null; then
    assert_pass "1.2 tdd-orchestrator has permissionMode: acceptEdits (tangle agent)"
else
    assert_fail "1.2 tdd-orchestrator has permissionMode: acceptEdits (tangle agent)"
fi

# 1.3: permissionMode exists for ink agent (code-reviewer)
if grep -A 15 '  code-reviewer:' "$CONFIG_YAML" | grep 'permissionMode: default' >/dev/null; then
    assert_pass "1.3 code-reviewer has permissionMode: default (ink agent)"
else
    assert_fail "1.3 code-reviewer has permissionMode: default (ink agent)"
fi

# 1.4: memory: project exists for code-reviewer
if grep -A 10 '  code-reviewer:' "$CONFIG_YAML" | grep 'memory: project' >/dev/null; then
    assert_pass "1.4 code-reviewer has memory: project"
else
    assert_fail "1.4 code-reviewer has memory: project"
fi

# 1.5: memory: project exists for security-auditor
if grep -A 10 '  security-auditor:' "$CONFIG_YAML" | grep 'memory: project' >/dev/null; then
    assert_pass "1.5 security-auditor has memory: project"
else
    assert_fail "1.5 security-auditor has memory: project"
fi

# 1.6: skills field exists for code-reviewer -> skill-code-review
if grep -A 10 '  code-reviewer:' "$CONFIG_YAML" | grep 'skills:.*skill-code-review' >/dev/null; then
    assert_pass "1.6 code-reviewer has skills: [skill-code-review]"
else
    assert_fail "1.6 code-reviewer has skills: [skill-code-review]"
fi

# 1.7: skills field exists for tdd-orchestrator -> skill-tdd
if grep -A 10 '  tdd-orchestrator:' "$CONFIG_YAML" | grep 'skills:.*skill-tdd' >/dev/null; then
    assert_pass "1.7 tdd-orchestrator has skills: [skill-tdd]"
else
    assert_fail "1.7 tdd-orchestrator has skills: [skill-tdd]"
fi

# 1.8: All agents have permissionMode field (count indented lines only, not comments)
agent_count=$(grep -c '^    permissionMode:' "$CONFIG_YAML" || echo "0")
# Count agents by counting entries with a 'file:' field (unique to agent definitions)
expected_agents=$(grep -c '^    file:' "$CONFIG_YAML" || echo "0")
if [[ "$agent_count" -eq "$expected_agents" ]]; then
    assert_pass "1.8 All $expected_agents agents have permissionMode field (count: $agent_count)"
else
    assert_fail "1.8 All $expected_agents agents have permissionMode field" "Found: $agent_count, Expected: $expected_agents"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 2: Helper Functions in orchestrate.sh (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 2: Helper Functions in orchestrate.sh${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 2.1: get_agent_memory() function exists
if grep -q '^get_agent_memory()' "$ALL_SRC"; then
    assert_pass "2.1 get_agent_memory() function exists"
else
    assert_fail "2.1 get_agent_memory() function exists"
fi

# 2.2: get_agent_skills() function exists
if grep -q '^get_agent_skills()' "$ALL_SRC"; then
    assert_pass "2.2 get_agent_skills() function exists"
else
    assert_fail "2.2 get_agent_skills() function exists"
fi

# 2.3: get_agent_permission_mode() function exists
if grep -q '^get_agent_permission_mode()' "$ALL_SRC"; then
    assert_pass "2.3 get_agent_permission_mode() function exists"
else
    assert_fail "2.3 get_agent_permission_mode() function exists"
fi

# 2.4: load_agent_skill_content() function exists
if grep -q '^load_agent_skill_content()' "$ALL_SRC"; then
    assert_pass "2.4 load_agent_skill_content() function exists"
else
    assert_fail "2.4 load_agent_skill_content() function exists"
fi

# 2.5: build_skill_context() function exists
if grep -q '^build_skill_context()' "$ALL_SRC"; then
    assert_pass "2.5 build_skill_context() function exists"
else
    assert_fail "2.5 build_skill_context() function exists"
fi

# 2.6: Functions use get_agent_config internally
if grep -A 5 'get_agent_memory()' "$ALL_SRC" | grep 'get_agent_config' >/dev/null; then
    assert_pass "2.6 get_agent_memory uses get_agent_config internally"
else
    assert_fail "2.6 get_agent_memory uses get_agent_config internally"
fi

# 2.7: load_agent_skill_content strips YAML frontmatter (awk pattern)
if grep -A 25 'load_agent_skill_content()' "$ALL_SRC" | grep 'in_fm.*past_fm' >/dev/null; then
    assert_pass "2.7 load_agent_skill_content strips YAML frontmatter (awk pattern)"
else
    assert_fail "2.7 load_agent_skill_content strips YAML frontmatter (awk pattern)"
fi

# 2.8: build_skill_context iterates skills list
if grep -A 15 'build_skill_context()' "$ALL_SRC" | grep 'for skill in' >/dev/null; then
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

# Extract the complete spawn_agent body. Contract and observability setup made
# the function longer than the historical fixed-line grep window.
SPAWN_AGENT_BODY="$(awk '
    /^spawn_agent\(\)/ { in_spawn=1 }
    in_spawn && /^[[:alnum:]_]+\(\)/ && $0 !~ /^spawn_agent\(\)/ { exit }
    in_spawn { print }
' "$ALL_SRC")"

# 3.1: spawn_agent references build_skill_context
if grep 'build_skill_context' <<< "$SPAWN_AGENT_BODY" >/dev/null; then
    assert_pass "3.1 spawn_agent references build_skill_context"
else
    assert_fail "3.1 spawn_agent references build_skill_context"
fi

# 3.2: spawn_agent references select_curated_agent for skill lookup
if grep 'select_curated_agent.*prompt.*phase' <<< "$SPAWN_AGENT_BODY" >/dev/null; then
    assert_pass "3.2 spawn_agent references select_curated_agent for skill lookup"
else
    assert_fail "3.2 spawn_agent references select_curated_agent for skill lookup"
fi

# 3.3: Skills injection gated behind SUPPORTS_AGENT_TYPE_ROUTING
if grep 'SUPPORTS_AGENT_TYPE_ROUTING.*true' <<< "$SPAWN_AGENT_BODY" >/dev/null; then
    assert_pass "3.3 Skills injection gated behind SUPPORTS_AGENT_TYPE_ROUTING"
else
    assert_fail "3.3 Skills injection gated behind SUPPORTS_AGENT_TYPE_ROUTING"
fi

# 3.4: Debug log line for skill context injection exists
if grep -q 'Injected skill context for agent' "$ALL_SRC"; then
    assert_pass "3.4 Debug log line for skill context injection exists"
else
    assert_fail "3.4 Debug log line for skill context injection exists"
fi

# 3.5: Debug log line for agent memory/permissionMode exists
if grep -q 'Agent fields: memory=.*permissionMode=' "$ALL_SRC"; then
    assert_pass "3.5 Debug log line for agent memory/permissionMode exists"
else
    assert_fail "3.5 Debug log line for agent memory/permissionMode exists"
fi

# 3.6: Skill content appended after persona+prompt (v8.16 cache optimization)
if grep 'Agent Skill Context' <<< "$SPAWN_AGENT_BODY" >/dev/null; then
    assert_pass "3.6 Skill content appended after persona+prompt (cache-optimized)"
else
    assert_fail "3.6 Skill content appended after persona+prompt (cache-optimized)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST GROUP 4: Version Consistency (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Test Group 4: Version Consistency${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 4.1: package.json version is semantic
pkg_version=$(grep '"version"' "$PACKAGE_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [[ "$pkg_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    assert_pass "4.1 package.json version is semantic ($pkg_version)"
else
    assert_fail "4.1 package.json version is semantic" "Got: $pkg_version"
fi

# 4.2: plugin.json version is semantic
pj_version=$(grep '"version"' "$PLUGIN_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [[ "$pj_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    assert_pass "4.2 plugin.json version is semantic ($pj_version)"
else
    assert_fail "4.2 plugin.json version is semantic" "Got: $pj_version"
fi

# 4.3: marketplace.json version is semantic for the octo plugin entry
mj_version=$(python3 - "$MARKETPLACE_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for plugin in data.get("plugins", []):
    if plugin.get("name") == "octo":
        print(plugin.get("version", ""))
        break
PY
)
if [[ "$mj_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    assert_pass "4.3 marketplace.json version is semantic ($mj_version)"
else
    assert_fail "4.3 marketplace.json version is semantic" "Got: $mj_version"
fi

# 4.4: CHANGELOG contains the plugin source-of-truth version
if [[ -f "$CHANGELOG_MD" ]] && grep -F "[${pj_version}]" "$CHANGELOG_MD" >/dev/null; then
    assert_pass "4.4 CHANGELOG.md contains current version ($pj_version)"
else
    assert_fail "4.4 CHANGELOG.md contains current version" "Expected: [$pj_version]"
fi

# 4.5: all public release versions match plugin.json
readme_version=$(python3 - "$README_MD" <<'PY'
import re, sys
match = re.search(r"Version-(\d+\.\d+\.\d+)-blue", open(sys.argv[1], encoding="utf-8").read())
print(match.group(1) if match else "")
PY
)
if [[ "$pkg_version" == "$pj_version" && "$mj_version" == "$pj_version" && "$readme_version" == "$pj_version" ]]; then
    assert_pass "4.5 release versions agree with plugin.json ($pj_version)"
else
    assert_fail "4.5 release versions agree with plugin.json" \
        "package=$pkg_version marketplace=$mj_version README=$readme_version plugin=$pj_version"
fi

# 4.6: plugin.json description mentions version or key capabilities
if grep -qE '"description".*(Multi-LLM|orchestration)|"version"' "$PLUGIN_JSON"; then
    assert_pass "4.6 plugin.json description has key metadata"
else
    assert_fail "4.6 plugin.json description has key metadata"
fi

# 4.7: CHANGELOG exact-version guard remains explicit
if [[ -f "$CHANGELOG_MD" ]] && grep -F "[${pj_version}]" "$CHANGELOG_MD" >/dev/null; then
    assert_pass "4.7 CHANGELOG has current release entry"
else
    assert_fail "4.7 CHANGELOG has current release entry"
fi

# 4.8: CHANGELOG has recent entries
if grep -qE '\[(8\.3|9\.)' "$CHANGELOG_MD"; then
    assert_pass "4.8 CHANGELOG has recent version entries"
else
    assert_fail "4.8 CHANGELOG has recent version entries"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Test Summary - v8.2.0 Agent Persona Enhanced Fields${NC}"
test_summary
