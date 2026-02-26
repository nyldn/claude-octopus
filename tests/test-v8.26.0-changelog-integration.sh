#!/usr/bin/env bash
# Test v8.26.0 Changelog Integration
# Validates feature flags, version blocks, worktree hooks, settings, doctor agents,
# memory delegation, agent isolation, and log lines

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE_SH="$PROJECT_ROOT/scripts/orchestrate.sh"
HOOKS_JSON="$PROJECT_ROOT/.claude-plugin/hooks.json"
SETTINGS_JSON="$PROJECT_ROOT/.claude-plugin/settings.json"
SKILL_DOCTOR="$PROJECT_ROOT/.claude/skills/skill-doctor.md"
CONFIG_YAML="$PROJECT_ROOT/agents/config.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}Testing v8.26.0 Changelog Integration${NC}"
echo ""

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "${GREEN}  PASS${NC}: $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "${RED}  FAIL${NC}: $1"
    if [[ -n "${2:-}" ]]; then echo -e "   ${YELLOW}$2${NC}"; fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 1: Feature Flags (9 tests)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 1: Feature Flags"
echo "────────────────────────────────────────"

for flag in SUPPORTS_REMOTE_CONTROL SUPPORTS_NPM_PLUGIN_REGISTRIES SUPPORTS_FAST_BASH \
            SUPPORTS_AGGRESSIVE_DISK_PERSIST SUPPORTS_ACCOUNT_ENV_VARS SUPPORTS_MANAGED_SETTINGS_PLATFORM \
            SUPPORTS_NATIVE_AUTO_MEMORY SUPPORTS_AGENT_MEMORY_GC SUPPORTS_SMART_BASH_PREFIXES; do
    if grep -q "^${flag}=false" "$ORCHESTRATE_SH"; then
        pass "$flag declared with default false"
    else
        fail "$flag declaration NOT found" "Expected: ${flag}=false"
    fi
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 2: Version Detection Blocks (4 tests)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 2: Version Detection Blocks"
echo "────────────────────────────────────────"

# Test 2.1: v2.1.51 block exists
if grep -q 'version_compare.*"2\.1\.51".*">="' "$ORCHESTRATE_SH"; then
    pass "v2.1.51+ version detection block exists"
else
    fail "v2.1.51+ version detection block NOT found"
fi

# Test 2.2: v2.1.59 block exists
if grep -q 'version_compare.*"2\.1\.59".*">="' "$ORCHESTRATE_SH"; then
    pass "v2.1.59+ version detection block exists"
else
    fail "v2.1.59+ version detection block NOT found"
fi

# Test 2.3: v2.1.51 block sets SUPPORTS_REMOTE_CONTROL
if grep -A 10 'version_compare.*"2\.1\.51"' "$ORCHESTRATE_SH" | grep -q 'SUPPORTS_REMOTE_CONTROL=true'; then
    pass "v2.1.51+ block sets SUPPORTS_REMOTE_CONTROL=true"
else
    fail "v2.1.51+ block does NOT set SUPPORTS_REMOTE_CONTROL=true"
fi

# Test 2.4: v2.1.59 block sets SUPPORTS_NATIVE_AUTO_MEMORY
if grep -A 10 'version_compare.*"2\.1\.59"' "$ORCHESTRATE_SH" | grep -q 'SUPPORTS_NATIVE_AUTO_MEMORY=true'; then
    pass "v2.1.59+ block sets SUPPORTS_NATIVE_AUTO_MEMORY=true"
else
    fail "v2.1.59+ block does NOT set SUPPORTS_NATIVE_AUTO_MEMORY=true"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 3: Worktree Hooks (6 tests)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 3: Worktree Hooks"
echo "────────────────────────────────────────"

# Test 3.1: worktree-setup.sh exists
if [[ -f "$PROJECT_ROOT/hooks/worktree-setup.sh" ]]; then
    pass "worktree-setup.sh exists"
else
    fail "worktree-setup.sh NOT found"
fi

# Test 3.2: worktree-setup.sh is executable
if [[ -x "$PROJECT_ROOT/hooks/worktree-setup.sh" ]]; then
    pass "worktree-setup.sh is executable"
else
    fail "worktree-setup.sh is NOT executable"
fi

# Test 3.3: worktree-teardown.sh exists
if [[ -f "$PROJECT_ROOT/hooks/worktree-teardown.sh" ]]; then
    pass "worktree-teardown.sh exists"
else
    fail "worktree-teardown.sh NOT found"
fi

# Test 3.4: worktree-teardown.sh is executable
if [[ -x "$PROJECT_ROOT/hooks/worktree-teardown.sh" ]]; then
    pass "worktree-teardown.sh is executable"
else
    fail "worktree-teardown.sh is NOT executable"
fi

# Test 3.5: hooks.json contains WorktreeCreate
if grep -q '"WorktreeCreate"' "$HOOKS_JSON"; then
    pass "hooks.json contains WorktreeCreate event"
else
    fail "hooks.json does NOT contain WorktreeCreate event"
fi

# Test 3.6: hooks.json contains WorktreeRemove
if grep -q '"WorktreeRemove"' "$HOOKS_JSON"; then
    pass "hooks.json contains WorktreeRemove event"
else
    fail "hooks.json does NOT contain WorktreeRemove event"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 4: Settings (8 tests)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 4: Settings"
echo "────────────────────────────────────────"

for field in OCTOPUS_CODEX_SANDBOX OCTOPUS_MEMORY_INJECTION OCTOPUS_PERSONA_PACKS \
             OCTOPUS_WORKTREE_ISOLATION OCTOPUS_MAX_PARALLEL_AGENTS \
             OCTOPUS_QUALITY_GATE_THRESHOLD OCTOPUS_COST_WARNINGS OCTOPUS_TOOL_POLICIES; do
    if grep -q "\"${field}\"" "$SETTINGS_JSON"; then
        pass "settings.json contains $field"
    else
        fail "settings.json does NOT contain $field"
    fi
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 5: Doctor Agents Category (4 tests)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 5: Doctor Agents Category"
echo "────────────────────────────────────────"

# Test 5.1: doctor_check_agents function exists
if grep -q '^doctor_check_agents()' "$ORCHESTRATE_SH"; then
    pass "doctor_check_agents() function exists"
else
    fail "doctor_check_agents() function NOT found"
fi

# Test 5.2: categories array includes agents
if grep -q 'categories=.*agents)' "$ORCHESTRATE_SH"; then
    pass "categories array includes 'agents'"
else
    fail "categories array does NOT include 'agents'"
fi

# Test 5.3: skill-doctor.md mentions 10 categories
if grep -q '10 check categories' "$SKILL_DOCTOR"; then
    pass "skill-doctor.md references 10 check categories"
else
    fail "skill-doctor.md does NOT reference 10 check categories"
fi

# Test 5.4: skill-doctor.md lists agents filter command
if grep -q 'doctor agents' "$SKILL_DOCTOR"; then
    pass "skill-doctor.md lists 'doctor agents' filter command"
else
    fail "skill-doctor.md does NOT list 'doctor agents' filter"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 6: Memory Delegation (3 tests)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 6: Memory Delegation"
echo "────────────────────────────────────────"

# Test 6.1: SUPPORTS_NATIVE_AUTO_MEMORY check in build_memory_context
if grep -A 5 'build_memory_context' "$ORCHESTRATE_SH" | head -20 | grep -q 'SUPPORTS_NATIVE_AUTO_MEMORY'; then
    pass "build_memory_context references SUPPORTS_NATIVE_AUTO_MEMORY"
else
    # Search more broadly
    if grep -B 2 -A 2 'native auto-memory' "$ORCHESTRATE_SH" | grep -q 'build_memory_context\|Delegating.*memory'; then
        pass "build_memory_context delegates to native auto-memory"
    else
        fail "build_memory_context does NOT reference native auto-memory"
    fi
fi

# Test 6.2: _skip_mem guard in spawn_agent
if grep -q '_skip_mem' "$ORCHESTRATE_SH"; then
    pass "_skip_mem guard variable exists in spawn_agent"
else
    fail "_skip_mem guard variable NOT found"
fi

# Test 6.3: Skip logic checks scope
if grep -q 'agent_mem.*!=.*local.*agent_mem.*!=.*none' "$ORCHESTRATE_SH" || \
   grep -q 'agent_mem" != "local" && .*agent_mem" != "none"' "$ORCHESTRATE_SH"; then
    pass "Memory skip logic checks for local/none scope"
else
    fail "Memory skip logic does NOT check scope properly"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 7: Agent Isolation (2 tests)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 7: Agent Isolation"
echo "────────────────────────────────────────"

# Test 7.1: security-auditor has isolation: worktree
if grep -A 15 'security-auditor:' "$CONFIG_YAML" | grep -q 'isolation: worktree'; then
    pass "security-auditor has isolation: worktree"
else
    fail "security-auditor does NOT have isolation: worktree"
fi

# Test 7.2: deployment-engineer has isolation: worktree
if grep -A 15 'deployment-engineer:' "$CONFIG_YAML" | grep -q 'isolation: worktree'; then
    pass "deployment-engineer has isolation: worktree"
else
    fail "deployment-engineer does NOT have isolation: worktree"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 8: Log Lines (1 test)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 8: Log Lines"
echo "────────────────────────────────────────"

# Test 8.1: New log lines for v8.26 flags
if grep -q 'Remote Control:.*NPM Registries:.*Fast Bash:.*Disk Persist:' "$ORCHESTRATE_SH"; then
    pass "New log line for v2.1.51+ flags exists"
else
    fail "New log line for v2.1.51+ flags NOT found"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

echo "════════════════════════════════════════"
echo -e "Total: $TEST_COUNT | ${GREEN}Pass: $PASS_COUNT${NC} | ${RED}Fail: $FAIL_COUNT${NC}"
echo "════════════════════════════════════════"

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
