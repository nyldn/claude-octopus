#!/bin/bash
# Test suite for agent-teams-bridge.sh
# Validates: enable gate, nested guard, task dependencies, shutdown protocol,
#            cleanup warning, native team discovery, ledger lifecycle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BRIDGE="$PLUGIN_DIR/scripts/agent-teams-bridge.sh"
DOCTOR="$PLUGIN_DIR/scripts/lib/doctor.sh"
ALL_SRC=$(mktemp)
trap 'rm -f "$ALL_SRC" "$BRIDGE_TEST_DIR" 2>/dev/null; rm -rf "${BRIDGE_TEST_DIR:-/tmp/nonexistent}" 2>/dev/null' EXIT
cat "$PLUGIN_DIR/scripts/orchestrate.sh" "$PLUGIN_DIR/scripts/lib/"*.sh "$BRIDGE" > "$ALL_SRC" 2>/dev/null

PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  ❌ FAIL: $1 — $2"; }
suite() { echo ""; echo "━━━ $1 ━━━"; }

# ── 1. Enable Gate (static analysis) ─────────────────────────────────────────
suite "Enable Gate"

if grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$BRIDGE"; then
  pass "bridge_is_enabled checks CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
else
  fail "bridge_is_enabled checks CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" "env var not referenced"
fi

if grep -q 'SUPPORTS_AGENT_TEAMS_BRIDGE' "$BRIDGE"; then
  pass "bridge_is_enabled checks SUPPORTS_AGENT_TEAMS_BRIDGE"
else
  fail "bridge_is_enabled checks SUPPORTS_AGENT_TEAMS_BRIDGE" "flag not referenced"
fi

# Verify the auto case returns 1 when flag is false
if grep -A3 'auto)' "$BRIDGE" | grep -q 'return 1\||| return 1'; then
  pass "auto case returns 1 when flag is false"
else
  fail "auto case returns 1 when flag is false" "missing return 1"
fi

# ── 2. Nested Team Guard ─────────────────────────────────────────────────────
suite "Nested Team Guard"

if grep -q 'nested team\|nested.*guard\|Cannot create nested' "$BRIDGE"; then
  pass "bridge_init_ledger has nested team guard"
else
  fail "bridge_init_ledger has nested team guard" "no nested guard found"
fi

if grep -A15 'bridge_init_ledger' "$BRIDGE" | grep -q 'running'; then
  pass "Guard checks for running status"
else
  fail "Guard checks for running status" "no running check"
fi

# ── 3. Task Dependencies ─────────────────────────────────────────────────────
suite "Task Dependencies"

if grep -q 'depends_on' "$BRIDGE"; then
  pass "bridge_register_task has depends_on parameter"
else
  fail "bridge_register_task has depends_on parameter" "not found"
fi

if grep -q 'bridge_is_task_unblocked' "$BRIDGE"; then
  pass "bridge_is_task_unblocked function exists"
else
  fail "bridge_is_task_unblocked function exists" "not found"
fi

# Verify depends_on is split into array in jq
if grep 'split.*","' "$BRIDGE" | grep -q 'deps'; then
  pass "depends_on parsed as comma-separated into array"
else
  fail "depends_on parsed as comma-separated into array" "no split found"
fi

# Verify unblocked check looks at completed status
if grep -A15 'bridge_is_task_unblocked' "$BRIDGE" | grep -q '"completed"'; then
  pass "Unblocked check verifies completed status"
else
  fail "Unblocked check verifies completed status" "no completed check"
fi

# ── 4. Shutdown Protocol ─────────────────────────────────────────────────────
suite "Shutdown Protocol"

if grep -q 'bridge_shutdown_teammate' "$BRIDGE"; then
  pass "bridge_shutdown_teammate function exists"
else
  fail "bridge_shutdown_teammate function exists" "not found"
fi

if grep -A8 'bridge_shutdown_teammate' "$BRIDGE" | grep -q 'shutting_down'; then
  pass "Shutdown sets status to shutting_down"
else
  fail "Shutdown sets status to shutting_down" "no status transition"
fi

# ── 5. Cleanup Warning ───────────────────────────────────────────────────────
suite "Cleanup Warning"

if grep -A15 'bridge_cleanup' "$BRIDGE" | grep -q 'still running'; then
  pass "bridge_cleanup warns about running tasks"
else
  fail "bridge_cleanup warns about running tasks" "no warning"
fi

if grep -A15 'bridge_cleanup' "$BRIDGE" | grep -q 'archive'; then
  pass "bridge_cleanup archives ledger"
else
  fail "bridge_cleanup archives ledger" "no archive logic"
fi

# ── 6. Native Team Discovery ─────────────────────────────────────────────────
suite "Native Team Discovery"

if grep -q 'bridge_discover_native_team' "$BRIDGE"; then
  pass "bridge_discover_native_team function exists"
else
  fail "bridge_discover_native_team function exists" "not found"
fi

if grep -A10 'bridge_discover_native_team' "$BRIDGE" | grep -q 'claude/teams'; then
  pass "Discovery reads from ~/.claude/teams/"
else
  fail "Discovery reads from ~/.claude/teams/" "wrong path"
fi

if grep -A10 'bridge_discover_native_team' "$BRIDGE" | grep -q 'config.json'; then
  pass "Discovery reads config.json"
else
  fail "Discovery reads config.json" "not reading config"
fi

# ── 7. Doctor Tips ────────────────────────────────────────────────────────────
suite "Doctor Tips"

if grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$DOCTOR"; then
  pass "Doctor checks agent teams env var"
else
  fail "Doctor checks agent teams env var" "not in doctor.sh"
fi

if grep -q 'agent-teams-disabled' "$DOCTOR"; then
  pass "Doctor has agent-teams-disabled tip"
else
  fail "Doctor has agent-teams-disabled tip" "missing tip ID"
fi

# ── 8. Ledger Lifecycle (functional, requires jq) ────────────────────────────
suite "Ledger Lifecycle (functional)"

if ! command -v jq &>/dev/null; then
  echo "  SKIP: jq not available — skipping functional tests"
else
  BRIDGE_TEST_DIR=$(mktemp -d)
  export SUPPORTS_AGENT_TEAMS_BRIDGE=true
  export OCTOPUS_AGENT_TEAMS_BRIDGE=enabled

  # Need a log function stub before sourcing
  log() { :; }
  export -f log

  # Source the bridge (it's source-safe), then override paths
  source "$BRIDGE"
  _BRIDGE_DIR="$BRIDGE_TEST_DIR"
  _BRIDGE_LEDGER="$BRIDGE_TEST_DIR/task-ledger.json"
  _BRIDGE_LOCKFILE="$BRIDGE_TEST_DIR/.ledger.lock"

  # Test init
  bridge_init_ledger "test-workflow" "test-group"
  if [[ -f "$_BRIDGE_LEDGER" ]] && jq -e '.workflow == "test-workflow"' "$_BRIDGE_LEDGER" >/dev/null 2>&1; then
    pass "bridge_init_ledger creates valid JSON"
  else
    fail "bridge_init_ledger creates valid JSON" "file missing or invalid"
  fi

  # Test nested guard
  if bridge_init_ledger "nested" "nested-group" 2>/dev/null; then
    fail "Nested guard prevents double init" "init succeeded when running ledger exists"
  else
    pass "Nested guard prevents double init"
  fi

  # Test register task with dependencies
  bridge_register_task "task-1" "codex" "probe" "researcher" ""
  bridge_register_task "task-2" "gemini" "probe" "researcher" "task-1"

  if jq -e '.tasks["task-2"].depends_on == ["task-1"]' "$_BRIDGE_LEDGER" >/dev/null 2>&1; then
    pass "Task registered with depends_on array"
  else
    fail "Task registered with depends_on array" "$(jq '.tasks["task-2"].depends_on' "$_BRIDGE_LEDGER" 2>/dev/null)"
  fi

  # Test unblocked check — task-1 is running, task-2 depends on it
  if bridge_is_task_unblocked "task-2"; then
    fail "Blocked task reports as blocked" "task-2 should be blocked (task-1 running)"
  else
    pass "Blocked task reports as blocked"
  fi

  # Complete task-1, check task-2 is now unblocked
  bridge_mark_task_complete "task-1" "completed"
  if bridge_is_task_unblocked "task-2"; then
    pass "Unblocked after dependency completes"
  else
    fail "Unblocked after dependency completes" "task-2 still blocked"
  fi

  # Test shutdown
  bridge_shutdown_teammate "task-2"
  task2_status=""
  task2_status=$(jq -r '.tasks["task-2"].status' "$_BRIDGE_LEDGER" 2>/dev/null)
  if [[ "$task2_status" == "shutting_down" ]]; then
    pass "Shutdown sets status correctly"
  else
    fail "Shutdown sets status correctly" "status=$task2_status"
  fi

  # Test workflow status
  wf_status=""
  wf_status=$(bridge_get_workflow_status 2>/dev/null)
  if echo "$wf_status" | jq -e '.total_tasks == 2' >/dev/null 2>&1; then
    pass "Workflow status reports correct task count"
  else
    fail "Workflow status reports correct task count" "$wf_status"
  fi

  # Test agent ID round-trip
  bridge_store_agent_id "task-1" "agent-abc123"
  retrieved=""
  retrieved=$(bridge_get_agent_id "task-1" 2>/dev/null)
  if [[ "$retrieved" == "agent-abc123" ]]; then
    pass "Agent ID store/get round-trip"
  else
    fail "Agent ID store/get round-trip" "got=$retrieved"
  fi

  # Test cleanup
  bridge_cleanup
  if [[ -d "$BRIDGE_TEST_DIR/history" ]]; then
    pass "Cleanup archives to history/"
  else
    fail "Cleanup archives to history/" "no history dir"
  fi

  rm -rf "$BRIDGE_TEST_DIR"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
echo "═══════════════════════════════════════════"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
