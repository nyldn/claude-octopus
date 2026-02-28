#!/usr/bin/env bash
# Test: v8.30 Agent Continuation/Resume Support
# Validates:
#   - SUPPORTS_CONTINUATION flag declaration and detection
#   - resume_agent() function: writes correct JSON, returns 1 on failures
#   - bridge_store_agent_id() / bridge_get_agent_id() roundtrip
#   - Tangle retry path: resume attempt before cold spawn fallback
#
# NOTE: Uses grep-based static analysis (orchestrate.sh has a main execution block)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"
BRIDGE_SH="${PLUGIN_DIR}/scripts/agent-teams-bridge.sh"
FLOW_DEVELOP_MD="${PLUGIN_DIR}/.claude/skills/flow-develop.md"

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
echo -e "${BLUE}║  v8.30 Agent Continuation/Resume Tests                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# PREREQUISITE: File existence checks
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${BLUE}--- Prerequisites ---${NC}"

if [[ -f "$ORCHESTRATE_SH" ]]; then
    assert_pass "0.1 orchestrate.sh exists"
else
    assert_fail "0.1 orchestrate.sh exists" "File not found: $ORCHESTRATE_SH"
    echo -e "\n${RED}Cannot continue without orchestrate.sh${NC}"
    exit 1
fi

if [[ -f "$BRIDGE_SH" ]]; then
    assert_pass "0.2 agent-teams-bridge.sh exists"
else
    assert_fail "0.2 agent-teams-bridge.sh exists" "File not found: $BRIDGE_SH"
fi

if [[ -f "$FLOW_DEVELOP_MD" ]]; then
    assert_pass "0.3 flow-develop.md exists"
else
    assert_fail "0.3 flow-develop.md exists" "File not found: $FLOW_DEVELOP_MD"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 1. SUPPORTS_CONTINUATION flag
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}--- 1. SUPPORTS_CONTINUATION Flag ---${NC}"

# 1.1: Flag declaration exists
if grep -q 'SUPPORTS_CONTINUATION=false' "$ORCHESTRATE_SH"; then
    assert_pass "1.1 SUPPORTS_CONTINUATION flag declared with default=false"
else
    assert_fail "1.1 SUPPORTS_CONTINUATION flag declared with default=false"
fi

# 1.2: Flag set to true in detect_claude_code_version
if grep -A 5 'v2.1.34' "$ORCHESTRATE_SH" | grep -q 'SUPPORTS_CONTINUATION=true'; then
    assert_pass "1.2 SUPPORTS_CONTINUATION enabled in v2.1.34+ detection block"
else
    assert_fail "1.2 SUPPORTS_CONTINUATION enabled in v2.1.34+ detection block"
fi

# 1.3: Flag appears in log output
if grep -q 'Continuation:' "$ORCHESTRATE_SH"; then
    assert_pass "1.3 SUPPORTS_CONTINUATION included in version detection log output"
else
    assert_fail "1.3 SUPPORTS_CONTINUATION included in version detection log output"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 2. resume_agent() function
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}--- 2. resume_agent() Function ---${NC}"

# 2.1: Function exists
if grep -q '^resume_agent()' "$ORCHESTRATE_SH"; then
    assert_pass "2.1 resume_agent() function defined"
else
    assert_fail "2.1 resume_agent() function defined"
fi

# 2.2: Gates on SUPPORTS_CONTINUATION
if grep -A 30 '^resume_agent()' "$ORCHESTRATE_SH" | grep -q 'SUPPORTS_CONTINUATION.*true'; then
    assert_pass "2.2 resume_agent() gates on SUPPORTS_CONTINUATION"
else
    assert_fail "2.2 resume_agent() gates on SUPPORTS_CONTINUATION"
fi

# 2.3: Returns 1 when SUPPORTS_CONTINUATION is false
if grep -A 30 '^resume_agent()' "$ORCHESTRATE_SH" | grep -q 'return 1'; then
    assert_pass "2.3 resume_agent() returns 1 on failure conditions"
else
    assert_fail "2.3 resume_agent() returns 1 on failure conditions"
fi

# 2.4: Gates on empty agent_id
if grep -A 30 '^resume_agent()' "$ORCHESTRATE_SH" | grep -q 'empty agent_id'; then
    assert_pass "2.4 resume_agent() gates on empty agent_id"
else
    assert_fail "2.4 resume_agent() gates on empty agent_id"
fi

# 2.5: Writes JSON instruction file with dispatch_method: "resume"
if grep -A 60 '^resume_agent()' "$ORCHESTRATE_SH" | grep -q 'dispatch_method.*resume'; then
    assert_pass "2.5 resume_agent() writes JSON with dispatch_method=resume"
else
    assert_fail "2.5 resume_agent() writes JSON with dispatch_method=resume"
fi

# 2.6: Emits AGENT_TEAMS_RESUME signal
if grep -A 70 '^resume_agent()' "$ORCHESTRATE_SH" | grep -q 'AGENT_TEAMS_RESUME'; then
    assert_pass "2.6 resume_agent() emits AGENT_TEAMS_RESUME signal"
else
    assert_fail "2.6 resume_agent() emits AGENT_TEAMS_RESUME signal"
fi

# 2.7: Calls bridge_register_task for the resumed task
if grep -A 70 '^resume_agent()' "$ORCHESTRATE_SH" | grep -q 'bridge_register_task'; then
    assert_pass "2.7 resume_agent() registers task in bridge ledger"
else
    assert_fail "2.7 resume_agent() registers task in bridge ledger"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 3. Bridge agent_id functions
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}--- 3. Bridge Agent ID Functions ---${NC}"

# 3.1: bridge_store_agent_id function exists
if grep -q '^bridge_store_agent_id()' "$BRIDGE_SH"; then
    assert_pass "3.1 bridge_store_agent_id() defined in bridge"
else
    assert_fail "3.1 bridge_store_agent_id() defined in bridge"
fi

# 3.2: bridge_get_agent_id function exists
if grep -q '^bridge_get_agent_id()' "$BRIDGE_SH"; then
    assert_pass "3.2 bridge_get_agent_id() defined in bridge"
else
    assert_fail "3.2 bridge_get_agent_id() defined in bridge"
fi

# 3.3: bridge_store_agent_id uses bridge_atomic_ledger_update
if grep -A 15 '^bridge_store_agent_id()' "$BRIDGE_SH" | grep -q 'bridge_atomic_ledger_update'; then
    assert_pass "3.3 bridge_store_agent_id() uses atomic ledger update"
else
    assert_fail "3.3 bridge_store_agent_id() uses atomic ledger update"
fi

# 3.4: bridge_get_agent_id reads from ledger via jq
if grep -A 15 '^bridge_get_agent_id()' "$BRIDGE_SH" | grep -q 'agent_id'; then
    assert_pass "3.4 bridge_get_agent_id() reads agent_id from ledger"
else
    assert_fail "3.4 bridge_get_agent_id() reads agent_id from ledger"
fi

# 3.5: Both functions gate on bridge_is_enabled
store_gated=$(grep -A 5 '^bridge_store_agent_id()' "$BRIDGE_SH" | grep -c 'bridge_is_enabled') || true
get_gated=$(grep -A 5 '^bridge_get_agent_id()' "$BRIDGE_SH" | grep -c 'bridge_is_enabled') || true
if [[ "$store_gated" -gt 0 && "$get_gated" -gt 0 ]]; then
    assert_pass "3.5 Both bridge functions gate on bridge_is_enabled"
else
    assert_fail "3.5 Both bridge functions gate on bridge_is_enabled"
fi

# 3.6: Functional roundtrip test (requires jq, runs in subshell to avoid re-entrance)
if command -v jq &>/dev/null; then
    roundtrip_result=$(
        _test_dir=$(mktemp -d)

        # Define stubs before sourcing
        log() { :; }
        OCTOPUS_AGENT_TEAMS_BRIDGE="enabled"
        SUPPORTS_AGENT_TEAMS_BRIDGE="true"

        source "$BRIDGE_SH"

        # Override paths AFTER sourcing (source resets _BRIDGE_DIR to hardcoded default)
        _BRIDGE_DIR="$_test_dir/bridge"
        _BRIDGE_LEDGER="$_BRIDGE_DIR/task-ledger.json"
        _BRIDGE_LOCKFILE="$_BRIDGE_DIR/.ledger.lock"
        mkdir -p "$_BRIDGE_DIR"
        echo '{"tasks": {}}' > "$_BRIDGE_LEDGER"

        # Store and retrieve
        bridge_store_agent_id "test-task-123" "agent-abc-456"
        retrieved=$(bridge_get_agent_id "test-task-123" 2>/dev/null) || retrieved=""
        unknown=$(bridge_get_agent_id "nonexistent-task" 2>/dev/null) || unknown=""

        echo "retrieved=$retrieved"
        echo "unknown=$unknown"

        rm -rf "$_test_dir"
    )

    retrieved_val=$(echo "$roundtrip_result" | grep '^retrieved=' | cut -d= -f2)
    unknown_val=$(echo "$roundtrip_result" | grep '^unknown=' | cut -d= -f2)

    if [[ "$retrieved_val" == "agent-abc-456" ]]; then
        assert_pass "3.6 bridge_store_agent_id/bridge_get_agent_id roundtrip"
    else
        assert_fail "3.6 bridge_store_agent_id/bridge_get_agent_id roundtrip" "Expected 'agent-abc-456', got '$retrieved_val'"
    fi

    if [[ -z "$unknown_val" ]]; then
        assert_pass "3.7 bridge_get_agent_id returns empty for unknown task"
    else
        assert_fail "3.7 bridge_get_agent_id returns empty for unknown task" "Expected empty, got '$unknown_val'"
    fi
else
    assert_fail "3.6 bridge_store_agent_id/bridge_get_agent_id roundtrip" "jq not available"
    assert_fail "3.7 bridge_get_agent_id returns empty for unknown task" "jq not available"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 4. Tangle retry integration
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}--- 4. Tangle Retry Integration ---${NC}"

# 4.1: retry_failed_subtasks references resume_agent
if grep -A 100 'retry_failed_subtasks()' "$ORCHESTRATE_SH" | grep -q 'resume_agent'; then
    assert_pass "4.1 retry_failed_subtasks() attempts resume_agent before cold spawn"
else
    assert_fail "4.1 retry_failed_subtasks() attempts resume_agent before cold spawn"
fi

# 4.2: retry path calls bridge_get_agent_id to find previous agent
if grep -A 100 'retry_failed_subtasks()' "$ORCHESTRATE_SH" | grep -q 'bridge_get_agent_id'; then
    assert_pass "4.2 retry path looks up previous agent_id via bridge"
else
    assert_fail "4.2 retry path looks up previous agent_id via bridge"
fi

# 4.3: Fallback to spawn_agent when resume fails
if grep -A 100 'retry_failed_subtasks()' "$ORCHESTRATE_SH" | grep -q '_did_resume.*true'; then
    assert_pass "4.3 retry path falls back to spawn_agent when resume unavailable"
else
    assert_fail "4.3 retry path falls back to spawn_agent when resume unavailable"
fi

# 4.4: SUPPORTS_CONTINUATION gate in retry path
if grep -A 100 'retry_failed_subtasks()' "$ORCHESTRATE_SH" | grep -q 'SUPPORTS_CONTINUATION.*true'; then
    assert_pass "4.4 retry path gates resume on SUPPORTS_CONTINUATION"
else
    assert_fail "4.4 retry path gates resume on SUPPORTS_CONTINUATION"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 5. Agent Teams dispatch integration
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}--- 5. Agent Teams Dispatch ---${NC}"

# 5.1: Agent Teams instruction JSON includes agent_id field
if grep -A 20 'agent_instruction_file.*teams_dir' "$ORCHESTRATE_SH" | grep -q 'agent_id'; then
    assert_pass "5.1 Agent Teams instruction JSON includes agent_id field"
else
    assert_fail "5.1 Agent Teams instruction JSON includes agent_id field"
fi

# 5.2: Task-agent map file written for continuation support
if grep -q 'task-agent-map' "$ORCHESTRATE_SH"; then
    assert_pass "5.2 Task-agent map file created for agent_id correlation"
else
    assert_fail "5.2 Task-agent map file created for agent_id correlation"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 6. Flow skill integration
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}--- 6. Flow Skill Integration ---${NC}"

# 6.1: flow-develop.md documents AGENT_TEAMS_RESUME handling
if grep -q 'AGENT_TEAMS_RESUME' "$FLOW_DEVELOP_MD"; then
    assert_pass "6.1 flow-develop.md handles AGENT_TEAMS_RESUME signal"
else
    assert_fail "6.1 flow-develop.md handles AGENT_TEAMS_RESUME signal"
fi

# 6.2: Documents resume fallback behavior
if grep -q 'resume.*fail\|fall.*back' "$FLOW_DEVELOP_MD"; then
    assert_pass "6.2 flow-develop.md documents resume fallback behavior"
else
    assert_fail "6.2 flow-develop.md documents resume fallback behavior"
fi

# 6.3: Documents bridge_store_agent_id for persistence
if grep -q 'bridge_store_agent_id' "$FLOW_DEVELOP_MD"; then
    assert_pass "6.3 flow-develop.md documents agent_id storage after resume"
else
    assert_fail "6.3 flow-develop.md documents agent_id storage after resume"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "Tests run: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${NC} | ${RED}Failed: $TESTS_FAILED${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "\n${RED}SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "\n${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi
