#!/bin/bash
# Test suite for v8.40.0 — Claude Code v2.1.70-71 feature detection sync
# Validates new SUPPORTS_* flags, detection blocks, and wired integrations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "for v8.40.0 — Claude Code v2.1.70-71 feature detection sync"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCH="$PLUGIN_DIR/scripts/orchestrate.sh"
ALL_SRC=$(mktemp)
cat "$ORCH" "$PLUGIN_DIR/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
# atomic_json_update temporarily replaces and restores the caller's EXIT trap.
# On Bash 4+, a restored trap also runs when a background subshell exits. Keep
# this test's cleanup owned by the top-level shell so concurrent writers cannot
# delete fixtures that the parent still needs.
cleanup_feature_sync_test() {
  [[ "${BASH_SUBSHELL:-0}" -eq 0 ]] || return 0
  rm -f "$ALL_SRC"
  cleanup_test_environment
}
trap cleanup_feature_sync_test EXIT
HOOK="$PLUGIN_DIR/hooks/subagent-result-capture.sh"

PASS=0
FAIL=0
TOTAL=0

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

suite() {
  echo ""
  echo "━━━ $1 ━━━"
}

# ─────────────────────────────────────────────────────────────────────
# Suite 1: New flag declarations (6 flags)
# ─────────────────────────────────────────────────────────────────────
suite "1. v8.40.0 Flag Declarations"

# v2.1.70/v2.1.71 flags pruned in v9.5 (banner-only, no runtime behavior)
# Suite 1 now validates that pruned flags are gone
suite "1. v8.40.0 Flag Pruning (v9.5)"

for flag in SUPPORTS_VSCODE_PLAN_VIEW SUPPORTS_IMAGE_CACHE_COMPACTION \
            SUPPORTS_RENAME_WHILE_PROCESSING SUPPORTS_NATIVE_LOOP \
            SUPPORTS_RUNTIME_DEBUG SUPPORTS_FAST_BRIDGE_RECONNECT; do
  if grep -q "^${flag}=false" "$ALL_SRC"; then
    fail "$flag should have been pruned but still declared"
  else
    pass "$flag correctly pruned"
  fi
done

# ─────────────────────────────────────────────────────────────────────
# Suite 2: v2.1.70/v2.1.71 detection blocks removed
# ─────────────────────────────────────────────────────────────────────
suite "2. Version Detection Blocks Pruned"

if grep -q 'version_compare.*"2\.1\.70"' "$ALL_SRC"; then
  fail "v2.1.70 detection block should have been removed"
else
  pass "v2.1.70 detection block correctly removed"
fi

if grep -q 'version_compare.*"2\.1\.71"' "$ALL_SRC"; then
  fail "v2.1.71 detection block should have been removed"
else
  pass "v2.1.71 detection block correctly removed"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 3: Pruned flag logging removed
# ─────────────────────────────────────────────────────────────────────
suite "3. Flag Logging Pruned"

if grep -q 'VSCode Plan:.*SUPPORTS_VSCODE_PLAN_VIEW' "$ALL_SRC"; then
  fail "Pruned VSCode Plan flag still in logging"
else
  pass "VSCode Plan logging correctly removed"
fi

if grep -q 'Native Loop:.*SUPPORTS_NATIVE_LOOP' "$ALL_SRC"; then
  fail "Pruned Native Loop flag still in logging"
else
  pass "Native Loop logging correctly removed"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 4: Wired flag — SUPPORTS_EFFORT_CALLOUT
# ─────────────────────────────────────────────────────────────────────
suite "4. Effort Callout Wiring"

if grep -q 'SUPPORTS_EFFORT_CALLOUT.*true' "$ALL_SRC" | head -1 && \
   grep -q 'log "USER".*Effort' "$ALL_SRC"; then
  pass "SUPPORTS_EFFORT_CALLOUT wired to user-visible effort display"
else
  fail "SUPPORTS_EFFORT_CALLOUT not wired"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 5: Wired flag — SUPPORTS_HOOK_AGENT_FIELDS
# ─────────────────────────────────────────────────────────────────────
suite "5. Hook Agent Fields Wiring"

if grep -q 'agent_type' "$HOOK"; then
  pass "subagent-result-capture.sh captures agent_type"
else
  fail "subagent-result-capture.sh missing agent_type capture"
fi

if grep -q 'Agent-Type' "$HOOK"; then
  pass "agent_type written to result file"
else
  fail "agent_type not written to result file"
fi

test_case "SubagentStop completion upserts the matching progress task exactly once"
HOOK_WORKSPACE="$TEST_TMP_DIR/hook-workspace"
HOOK_RESULTS="$HOOK_WORKSPACE/results"
HOOK_TEAMS="$HOOK_WORKSPACE/agent-teams"
mkdir -p "$HOOK_RESULTS" "$HOOK_TEAMS"
HOOK_RESULT_FILE="$HOOK_RESULTS/claude-task-1.md"
cat > "$HOOK_TEAMS/task-1.json" <<EOF
{"dispatch_method":"agent_teams","result_file":"$HOOK_RESULT_FILE"}
EOF
cat > "$HOOK_WORKSPACE/progress.json" <<EOF
{"phase":"develop","total_agents":2,"completed_agents":1,"total_time_ms":0,"agents":[{"name":"claude","task_id":"task-1","phase":"develop","status":"running","started_at":"2026-08-11T00:00:00Z","elapsed_ms":0,"cost":0,"output_file":"$HOOK_RESULTS/../results/claude-task-1.md"},{"name":"legacy","task_id":"legacy-terminal","phase":"develop","status":"completed","started_at":"","elapsed_ms":null,"cost":null,"output_file":""}]}
EOF
HOOK_INPUT='{"last_assistant_message":"Implemented the requested change.","agent_id":"agent-1","agent_type":"claude"}'
printf '%s' "$HOOK_INPUT" | OCTOPUS_WORKSPACE="$HOOK_WORKSPACE" "$HOOK"
printf '%s' "$HOOK_INPUT" | OCTOPUS_WORKSPACE="$HOOK_WORKSPACE" "$HOOK"
if jq -e '
  .total_agents == 2 and
  .completed_agents == 2 and
  .successful_agents == 2 and
  (.total_time_ms | numbers) and
  (.total_cost | numbers) and
  (.agents | length) == 2 and
  .agents[0].task_id == "task-1" and
  .agents[0].status == "completed" and
  ([.agents[] | select(.status == "running")] | length) == 0
' "$HOOK_WORKSPACE/progress.json" >/dev/null; then
  test_pass
else
  test_fail "hook failed canonical-path matching, numeric coercion, or idempotent counting"
fi

test_case "SubagentStop releases the shared lock for later shell progress updates"
if [[ ! -e "$HOOK_WORKSPACE/progress.json.lock" ]] && (
  source "$PLUGIN_DIR/scripts/lib/validation.sh"
  source "$PLUGIN_DIR/scripts/lib/agents.sh"
  log() { :; }
  PROGRESS_TRACKING_ENABLED=true
  PROGRESS_FILE="$HOOK_WORKSPACE/progress.json"
  update_agent_status "claude" "completed" 123 0 600 \
    "task-1" "develop" "$HOOK_RESULT_FILE"
); then
  test_pass
else
  test_fail "hook left a lock path that blocks later shell progress updates"
fi

test_case "concurrent SubagentStop and shell writers do not lose progress completions"
CONCURRENT_WORKSPACE="$TEST_TMP_DIR/concurrent-hook-workspace"
CONCURRENT_RESULTS="$CONCURRENT_WORKSPACE/results"
CONCURRENT_TEAMS="$CONCURRENT_WORKSPACE/agent-teams"
mkdir -p "$CONCURRENT_RESULTS" "$CONCURRENT_TEAMS"
CONCURRENT_AGENTS="$TEST_TMP_DIR/concurrent-agents.jsonl"
: > "$CONCURRENT_AGENTS"
for i in $(seq 1 24); do
  concurrent_result="$CONCURRENT_RESULTS/claude-task-${i}.md"
  jq -cn --arg id "agent-${i}" --arg result "$concurrent_result" \
    '{agent_id:$id,dispatch_method:"agent_teams",result_file:$result}' \
    > "$CONCURRENT_TEAMS/task-${i}.json"
  jq -cn --arg task "task-${i}" --arg result "$concurrent_result" \
    '{name:"claude",task_id:$task,phase:"develop",status:"running",started_at:"2026-08-11T00:00:00Z",elapsed_ms:0,cost:0,output_file:$result}' \
    >> "$CONCURRENT_AGENTS"
done
jq -s '{phase:"develop",total_agents:length,completed_agents:0,total_time_ms:0,agents:.}' \
  "$CONCURRENT_AGENTS" > "$CONCURRENT_WORKSPACE/progress.json"

concurrent_pids=""
for i in $(seq 1 24); do
  (printf '{"last_assistant_message":"Done %s","agent_id":"agent-%s","agent_type":"claude"}' "$i" "$i" |
    OCTO_LOCK_WAIT_SECS=15 OCTO_LOCK_RETRY_MILLIS=100 \
    OCTOPUS_WORKSPACE="$CONCURRENT_WORKSPACE" "$HOOK") &
  concurrent_pids="$concurrent_pids $!"
done
(
  source "$PLUGIN_DIR/scripts/lib/validation.sh"
  source "$PLUGIN_DIR/scripts/lib/agents.sh"
  log() { :; }
  PROGRESS_TRACKING_ENABLED=true
  PROGRESS_FILE="$CONCURRENT_WORKSPACE/progress.json"
  OCTO_LOCK_WAIT_SECS=15 OCTO_LOCK_RETRY_MILLIS=100 \
    update_agent_status "claude" "completed" 456 0 600 \
    "task-1" "develop" "$CONCURRENT_RESULTS/claude-task-1.md"
) &
concurrent_pids="$concurrent_pids $!"
for concurrent_pid in $concurrent_pids; do
  wait "$concurrent_pid" || true
done
if jq -e '
  .total_agents == 24 and
  .completed_agents == 24 and
  .successful_agents == 24 and
  (.agents | length) == 24 and
  ([.agents[] | select(.status == "running")] | length) == 0
' "$CONCURRENT_WORKSPACE/progress.json" >/dev/null; then
  test_pass
else
  test_fail "concurrent hook/shell rewrites lost one or more terminal updates"
fi

test_case "concurrent progress writers preserve parent test fixtures"
if [[ -s "$ALL_SRC" ]]; then
  test_pass
else
  test_fail "a background progress writer ran the parent EXIT cleanup"
fi

test_case "live progress lock is not reclaimed and a duplicate hook reconciles later"
LOCK_WORKSPACE="$TEST_TMP_DIR/live-lock-workspace"
LOCK_RESULTS="$LOCK_WORKSPACE/results"
LOCK_TEAMS="$LOCK_WORKSPACE/agent-teams"
LOCK_RESULT_FILE="$LOCK_RESULTS/claude-lock-task.md"
mkdir -p "$LOCK_RESULTS" "$LOCK_TEAMS" "$LOCK_WORKSPACE/progress.json.lock"
cat > "$LOCK_TEAMS/lock-task.json" <<EOF
{"agent_id":"lock-agent","dispatch_method":"agent_teams","result_file":"$LOCK_RESULT_FILE"}
EOF
cat > "$LOCK_WORKSPACE/progress.json" <<EOF
{"phase":"develop","total_agents":1,"completed_agents":0,"agents":[{"name":"claude","task_id":"lock-task","phase":"develop","status":"running","started_at":"2026-08-11T00:00:00Z","elapsed_ms":0,"cost":0,"output_file":"$LOCK_RESULT_FILE"}]}
EOF
printf '%s\n' "$$" > "$LOCK_WORKSPACE/progress.json.lock/pid"
printf '%s\n' "$(( $(date +%s) - 120 ))" > "$LOCK_WORKSPACE/progress.json.lock/ts"
LOCK_INPUT='{"last_assistant_message":"Finished after lock release.","agent_id":"lock-agent","agent_type":"claude"}'
printf '%s' "$LOCK_INPUT" | OCTO_LOCK_WAIT_SECS=1 OCTO_LOCK_RETRY_MILLIS=100 \
  OCTOPUS_WORKSPACE="$LOCK_WORKSPACE" "$HOOK"
lock_preserved=false
if [[ -d "$LOCK_WORKSPACE/progress.json.lock" ]] &&
   jq -e '.agents[0].status == "running"' "$LOCK_WORKSPACE/progress.json" >/dev/null; then
  lock_preserved=true
fi
rm -rf "$LOCK_WORKSPACE/progress.json.lock"
printf '%s' "$LOCK_INPUT" | OCTO_LOCK_WAIT_SECS=1 OCTO_LOCK_RETRY_MILLIS=100 \
  OCTOPUS_WORKSPACE="$LOCK_WORKSPACE" "$HOOK"
if [[ "$lock_preserved" == "true" ]] &&
   jq -e '.completed_agents == 1 and .agents[0].status == "completed"' \
     "$LOCK_WORKSPACE/progress.json" >/dev/null &&
   grep -q 'timed out acquiring progress lock' "$LOCK_WORKSPACE/logs/hook-errors.log"; then
  test_pass
else
  test_fail "hook reclaimed a live lock or could not reconcile after the lock cleared"
fi

test_case "hard-aged progress lock with a recycled live PID is reclaimed"
AGED_LOCK_WORKSPACE="$TEST_TMP_DIR/aged-live-lock-workspace"
AGED_LOCK_RESULTS="$AGED_LOCK_WORKSPACE/results"
AGED_LOCK_TEAMS="$AGED_LOCK_WORKSPACE/agent-teams"
AGED_LOCK_RESULT_FILE="$AGED_LOCK_RESULTS/claude-aged-lock-task.md"
mkdir -p "$AGED_LOCK_RESULTS" "$AGED_LOCK_TEAMS" "$AGED_LOCK_WORKSPACE/progress.json.lock"
cat > "$AGED_LOCK_TEAMS/aged-lock-task.json" <<EOF
{"agent_id":"aged-lock-agent","dispatch_method":"agent_teams","result_file":"$AGED_LOCK_RESULT_FILE"}
EOF
cat > "$AGED_LOCK_WORKSPACE/progress.json" <<EOF
{"phase":"develop","total_agents":1,"completed_agents":0,"agents":[{"name":"claude","task_id":"aged-lock-task","phase":"develop","status":"running","started_at":"2026-08-11T00:00:00Z","elapsed_ms":0,"cost":0,"output_file":"$AGED_LOCK_RESULT_FILE"}]}
EOF
printf '%s\n' "$$" > "$AGED_LOCK_WORKSPACE/progress.json.lock/pid"
printf '%s\n' "$(( $(date +%s) - 301 ))" > "$AGED_LOCK_WORKSPACE/progress.json.lock/ts"
AGED_LOCK_INPUT='{"last_assistant_message":"Finished after stale lock recovery.","agent_id":"aged-lock-agent","agent_type":"claude"}'
printf '%s' "$AGED_LOCK_INPUT" | OCTO_LOCK_STALE_SECS=30 OCTO_LOCK_WAIT_SECS=1 \
  OCTO_LOCK_RETRY_MILLIS=100 OCTOPUS_WORKSPACE="$AGED_LOCK_WORKSPACE" "$HOOK"
if [[ ! -e "$AGED_LOCK_WORKSPACE/progress.json.lock" ]] &&
   jq -e '.completed_agents == 1 and .agents[0].status == "completed"' \
     "$AGED_LOCK_WORKSPACE/progress.json" >/dev/null; then
  test_pass
else
  test_fail "hook preserved a hard-aged recycled-PID lock"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 6: Wired flag — SUPPORTS_MEMORY_LEAK_FIXES
# ─────────────────────────────────────────────────────────────────────
suite "6. Memory Leak Fixes Wiring"

if grep -q 'leak_safe_boost' "$ALL_SRC" && \
   grep -q 'SUPPORTS_MEMORY_LEAK_FIXES.*true' "$ALL_SRC"; then
  pass "SUPPORTS_MEMORY_LEAK_FIXES wired to timeout boost"
else
  fail "SUPPORTS_MEMORY_LEAK_FIXES not wired to timeout boost"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 7: Total flag count validation
# ─────────────────────────────────────────────────────────────────────
suite "7. Flag Count"

FLAG_COUNT=$(grep -c '^SUPPORTS_.*=false' "$ALL_SRC")
if [[ "$FLAG_COUNT" -ge 80 ]]; then
  pass "Total SUPPORTS_* flags: $FLAG_COUNT (expected >= 80)"
else
  fail "Total SUPPORTS_* flags: $FLAG_COUNT (expected >= 80)"
fi

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
test_summary
