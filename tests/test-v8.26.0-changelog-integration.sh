#!/usr/bin/env bash
# Test v8.26.0 Changelog Integration
# Validates feature flags, version blocks, worktree hooks, settings, doctor agents,
# memory delegation, agent isolation, and log lines

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "v8.26.0 Changelog Integration"

ORCHESTRATE_SH="$PROJECT_ROOT/scripts/orchestrate.sh"
# v9.12: Search orchestrate.sh + lib/*.sh for functions that may have been decomposed
ALL_SRC=$(mktemp)
cat "$ORCHESTRATE_SH" "$(dirname "$ORCHESTRATE_SH")/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT
HOOKS_JSON="$PROJECT_ROOT/.claude-plugin/hooks.json"
CONFIG_CHANGE_HANDLER="$PROJECT_ROOT/hooks/config-change-handler.sh"
SKILL_DOCTOR="$PROJECT_ROOT/.claude/skills/skill-doctor.md"
CONFIG_YAML="$PROJECT_ROOT/agents/config.yaml"


TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}Testing v8.26.0 Changelog Integration${NC}"
echo ""

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 1: Feature Flags (9 tests)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 1: Feature Flags"
echo "────────────────────────────────────────"

for flag in SUPPORTS_REMOTE_CONTROL SUPPORTS_NPM_PLUGIN_REGISTRIES SUPPORTS_FAST_BASH \
            SUPPORTS_AGGRESSIVE_DISK_PERSIST SUPPORTS_ACCOUNT_ENV_VARS SUPPORTS_MANAGED_SETTINGS_PLATFORM \
            SUPPORTS_NATIVE_AUTO_MEMORY SUPPORTS_AGENT_MEMORY_GC SUPPORTS_SMART_BASH_PREFIXES; do
    if grep -q "^${flag}=false" "$ALL_SRC"; then
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
if grep -q 'version_compare.*"2\.1\.51".*">="' "$ALL_SRC"; then
    pass "v2.1.51+ version detection block exists"
else
    fail "v2.1.51+ version detection block NOT found"
fi

# Test 2.2: v2.1.59 block exists
if grep -q 'version_compare.*"2\.1\.59".*">="' "$ALL_SRC"; then
    pass "v2.1.59+ version detection block exists"
else
    fail "v2.1.59+ version detection block NOT found"
fi

# Test 2.3: v2.1.51 block sets SUPPORTS_REMOTE_CONTROL
if grep -A 10 'version_compare.*"2\.1\.51"' "$ALL_SRC" | grep -q 'SUPPORTS_REMOTE_CONTROL=true'; then
    pass "v2.1.51+ block sets SUPPORTS_REMOTE_CONTROL=true"
else
    fail "v2.1.51+ block does NOT set SUPPORTS_REMOTE_CONTROL=true"
fi

# Test 2.4: v2.1.59 block sets SUPPORTS_NATIVE_AUTO_MEMORY
if grep -A 10 'version_compare.*"2\.1\.59"' "$ALL_SRC" | grep -q 'SUPPORTS_NATIVE_AUTO_MEMORY=true'; then
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
# settings.json was removed in v9.22.2; settings now live as env-var defaults
# in lib/*.sh and are registered for hot-reload in config-change-handler.sh
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 4: Settings"
echo "────────────────────────────────────────"

for field in OCTOPUS_CODEX_SANDBOX OCTOPUS_MEMORY_INJECTION OCTOPUS_PERSONA_PACKS \
             OCTOPUS_WORKTREE_ISOLATION OCTOPUS_MAX_PARALLEL_AGENTS \
             OCTOPUS_QUALITY_GATE_THRESHOLD OCTOPUS_COST_WARNINGS OCTOPUS_TOOL_POLICIES; do
    if grep -q "${field}" "$CONFIG_CHANGE_HANDLER"; then
        pass "config-change-handler registers $field"
    else
        fail "config-change-handler does NOT register $field"
    fi
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 5: Doctor Agents Category (4 tests)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 5: Doctor Agents Category"
echo "────────────────────────────────────────"

# Test 5.1: doctor_check_agents function exists
if grep -q '^doctor_check_agents()' "$ALL_SRC"; then
    pass "doctor_check_agents() function exists"
else
    fail "doctor_check_agents() function NOT found"
fi

# Test 5.2: categories array includes agents
if grep -q 'categories=.*agents' "$ALL_SRC"; then
    pass "categories array includes 'agents'"
else
    fail "categories array does NOT include 'agents'"
fi

# Test 5.3: skill-doctor.md mentions check categories (10+)
if grep -qE '1[0-9] check categories' "$SKILL_DOCTOR"; then
    pass "skill-doctor.md references check categories count"
else
    fail "skill-doctor.md does NOT reference check categories count"
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
if grep -A 5 'build_memory_context' "$ALL_SRC" | head -20 | grep -q 'SUPPORTS_NATIVE_AUTO_MEMORY'; then
    pass "build_memory_context references SUPPORTS_NATIVE_AUTO_MEMORY"
else
    # Search more broadly
    if grep -B 2 -A 2 'native auto-memory' "$ALL_SRC" | grep -q 'build_memory_context\|Delegating.*memory'; then
        pass "build_memory_context delegates to native auto-memory"
    else
        fail "build_memory_context does NOT reference native auto-memory"
    fi
fi

# Test 6.2: _skip_mem guard in spawn_agent
if grep -q '_skip_mem' "$ALL_SRC"; then
    pass "_skip_mem guard variable exists in spawn_agent"
else
    fail "_skip_mem guard variable NOT found"
fi

# Test 6.3: Skip logic checks scope
if grep -q 'agent_mem.*!=.*local.*agent_mem.*!=.*none' "$ALL_SRC" || \
   grep -q 'agent_mem" != "local" && .*agent_mem" != "none"' "$ALL_SRC"; then
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
if grep -q 'Remote Control:.*NPM Registries:.*Fast Bash:.*Disk Persist:' "$ALL_SRC"; then
    pass "New log line for v2.1.51+ flags exists"
else
    fail "New log line for v2.1.51+ flags NOT found"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
test_summary
