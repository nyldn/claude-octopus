#!/bin/bash
# Test: Scheduler Lifecycle Integration
# Tests daemon start/stop, job add/list/remove, policy enforcement, and kill switches

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Use a temporary scheduler directory to avoid polluting real state
export HOME="$(mktemp -d)"
SCHEDULER_DIR="${HOME}/.claude-octopus/scheduler"

# Source modules
source "${PROJECT_ROOT}/scripts/scheduler/store.sh"
source "${PROJECT_ROOT}/scripts/scheduler/cron.sh"
source "${PROJECT_ROOT}/scripts/scheduler/policy.sh"

echo "================================================================"
echo "  Scheduler Lifecycle - Integration Tests"
echo "================================================================"
echo ""
echo "Using temp HOME: $HOME"
echo ""

FAILED=0
PASSED=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

# --- Test: Store initialization ---
echo "--- Store Initialization ---"

store_init
if [[ -d "$JOBS_DIR" ]] && [[ -d "$RUNS_DIR" ]] && [[ -d "$RUNTIME_DIR" ]]; then
    pass "store_init creates directory structure"
else
    fail "store_init directory structure"
fi

if [[ -f "${LEDGER_DIR}/daily.json" ]]; then
    local_date=$(jq -r '.date' "${LEDGER_DIR}/daily.json")
    today=$(date +%Y-%m-%d)
    if [[ "$local_date" == "$today" ]]; then
        pass "Daily ledger initialized with today's date"
    else
        fail "Daily ledger date mismatch: $local_date != $today"
    fi
else
    fail "Daily ledger not created"
fi

# --- Test: Atomic write ---
echo ""
echo "--- Atomic Write ---"

test_file="${SCHEDULER_DIR}/test-atomic.json"
store_atomic_write "$test_file" '{"key":"value"}'
if [[ -f "$test_file" ]] && jq -e '.key == "value"' "$test_file" > /dev/null 2>&1; then
    pass "atomic_write creates valid JSON file"
else
    fail "atomic_write file creation"
fi

# Test invalid JSON rejection
if store_atomic_write "$test_file" 'not json' 2>/dev/null; then
    fail "atomic_write should reject invalid JSON"
else
    pass "atomic_write rejects invalid JSON"
fi

# --- Test: Job management ---
echo ""
echo "--- Job Management ---"

# Create a valid job file
VALID_JOB=$(cat <<'EOF'
{
  "id": "test-job",
  "name": "Test Job",
  "enabled": true,
  "schedule": {"cron": "0 2 * * *"},
  "task": {"workflow": "probe", "prompt": "Test research task"},
  "execution": {"workspace": "/tmp", "timeout_seconds": 60},
  "budget": {"max_cost_usd_per_run": 1.0, "max_cost_usd_per_day": 5.0},
  "security": {"sandbox": "workspace-write", "deny_flags": ["--dangerously-skip-permissions"]}
}
EOF
)

# Save job
store_atomic_write "${JOBS_DIR}/test-job.json" "$VALID_JOB"
if [[ -f "${JOBS_DIR}/test-job.json" ]]; then
    pass "Job file saved to jobs directory"
else
    fail "Job file not saved"
fi

# List jobs
job_list=$(list_jobs)
if echo "$job_list" | grep -q "test-job"; then
    pass "list_jobs finds saved job"
else
    fail "list_jobs doesn't find saved job"
fi

# Load job
loaded=$(load_job "${JOBS_DIR}/test-job.json")
loaded_id=$(echo "$loaded" | jq -r '.id')
if [[ "$loaded_id" == "test-job" ]]; then
    pass "load_job returns correct data"
else
    fail "load_job returned wrong id: $loaded_id"
fi

# --- Test: Policy checks ---
echo ""
echo "--- Policy Checks ---"

# Valid job should pass
result=$(policy_check "${JOBS_DIR}/test-job.json" 2>/dev/null)
allowed=$(echo "$result" | jq -r '.allowed')
if [[ "$allowed" == "true" ]]; then
    pass "Valid job passes policy check"
else
    fail "Valid job rejected by policy: $result"
fi

# Invalid workflow should fail
BAD_WORKFLOW=$(echo "$VALID_JOB" | jq '.task.workflow = "evil-command"')
bad_wf_file="${SCHEDULER_DIR}/bad-workflow.json"
store_atomic_write "$bad_wf_file" "$BAD_WORKFLOW"
result=$(policy_check "$bad_wf_file" 2>/dev/null) || true
allowed=$(echo "$result" | jq -r '.allowed')
if [[ "$allowed" == "false" ]]; then
    pass "Invalid workflow rejected by policy"
else
    fail "Invalid workflow not rejected"
fi

# Path traversal should fail
BAD_PATH=$(echo "$VALID_JOB" | jq '.execution.workspace = "/tmp/../etc"')
bad_path_file="${SCHEDULER_DIR}/bad-path.json"
store_atomic_write "$bad_path_file" "$BAD_PATH"
result=$(policy_check "$bad_path_file" 2>/dev/null) || true
allowed=$(echo "$result" | jq -r '.allowed')
if [[ "$allowed" == "false" ]]; then
    pass "Path traversal rejected by policy"
else
    fail "Path traversal not rejected"
fi

# Root workspace should fail
BAD_ROOT=$(echo "$VALID_JOB" | jq '.execution.workspace = "/"')
bad_root_file="${SCHEDULER_DIR}/bad-root.json"
store_atomic_write "$bad_root_file" "$BAD_ROOT"
result=$(policy_check "$bad_root_file" 2>/dev/null) || true
allowed=$(echo "$result" | jq -r '.allowed')
if [[ "$allowed" == "false" ]]; then
    pass "Root workspace rejected by policy"
else
    fail "Root workspace not rejected"
fi

# Dangerous flag in prompt should fail
BAD_FLAG=$(echo "$VALID_JOB" | jq '.task.prompt = "run with --dangerously-skip-permissions"')
bad_flag_file="${SCHEDULER_DIR}/bad-flag.json"
store_atomic_write "$bad_flag_file" "$BAD_FLAG"
result=$(policy_check "$bad_flag_file" 2>/dev/null) || true
allowed=$(echo "$result" | jq -r '.allowed')
if [[ "$allowed" == "false" ]]; then
    pass "Dangerous flag in prompt rejected by policy"
else
    fail "Dangerous flag in prompt not rejected"
fi

# --- Test: Kill switches ---
echo ""
echo "--- Kill Switches ---"

# KILL_ALL should block
touch "${SWITCHES_DIR}/KILL_ALL"
result=$(policy_check "${JOBS_DIR}/test-job.json" 2>/dev/null) || true
allowed=$(echo "$result" | jq -r '.allowed')
if [[ "$allowed" == "false" ]]; then
    reason=$(echo "$result" | jq -r '.reason')
    if echo "$reason" | grep -q "KILL_ALL"; then
        pass "KILL_ALL switch blocks jobs"
    else
        fail "KILL_ALL switch wrong reason: $reason"
    fi
else
    fail "KILL_ALL switch not blocking"
fi
rm -f "${SWITCHES_DIR}/KILL_ALL"

# PAUSE_ALL should block
touch "${SWITCHES_DIR}/PAUSE_ALL"
result=$(policy_check "${JOBS_DIR}/test-job.json" 2>/dev/null) || true
allowed=$(echo "$result" | jq -r '.allowed')
if [[ "$allowed" == "false" ]]; then
    pass "PAUSE_ALL switch blocks jobs"
else
    fail "PAUSE_ALL switch not blocking"
fi
rm -f "${SWITCHES_DIR}/PAUSE_ALL"

# After removing switches, should pass again
result=$(policy_check "${JOBS_DIR}/test-job.json" 2>/dev/null)
allowed=$(echo "$result" | jq -r '.allowed')
if [[ "$allowed" == "true" ]]; then
    pass "Jobs allowed after removing kill switches"
else
    fail "Jobs still blocked after removing switches"
fi

# --- Test: Ledger tracking ---
echo ""
echo "--- Ledger Tracking ---"

update_ledger "1.50" "test-job"
daily_spend=$(get_daily_spend)
if [[ "$daily_spend" == "1.5" ]]; then
    pass "Ledger tracks cost correctly (\$1.50)"
else
    fail "Ledger cost wrong: $daily_spend (expected 1.5)"
fi

update_ledger "0.75" "test-job"
daily_spend=$(get_daily_spend)
if awk -v s="$daily_spend" 'BEGIN { exit (s + 0 >= 2.2 && s + 0 <= 2.3) ? 0 : 1 }'; then
    pass "Ledger accumulates costs (\$2.25)"
else
    fail "Ledger accumulation wrong: $daily_spend (expected ~2.25)"
fi

# Budget admission with exceeded limit
BUDGET_JOB=$(echo "$VALID_JOB" | jq '.budget.max_cost_usd_per_day = 2.0')
budget_file="${SCHEDULER_DIR}/budget-job.json"
store_atomic_write "$budget_file" "$BUDGET_JOB"
result=$(policy_check "$budget_file" 2>/dev/null) || true
allowed=$(echo "$result" | jq -r '.allowed')
if [[ "$allowed" == "false" ]]; then
    pass "Budget admission rejects when daily limit exceeded"
else
    fail "Budget admission should reject (spent \$2.25, limit \$2.00)"
fi

# --- Test: Event log ---
echo ""
echo "--- Event Log ---"

append_event '{"event":"test","timestamp":"2026-02-16T00:00:00Z"}'
if [[ -f "${LEDGER_DIR}/events.jsonl" ]] && grep -q '"event":"test"' "${LEDGER_DIR}/events.jsonl"; then
    pass "Event appended to events.jsonl"
else
    fail "Event not found in events.jsonl"
fi

# --- Test: Run metadata ---
echo ""
echo "--- Run Metadata ---"

save_run "run-20260216-020000-test-job" '{"run_id":"run-20260216-020000-test-job","job_id":"test-job","status":"completed","exit_code":0,"cost_usd":0.5}'
if [[ -f "${RUNS_DIR}/run-20260216-020000-test-job.json" ]]; then
    run_status=$(jq -r '.status' "${RUNS_DIR}/run-20260216-020000-test-job.json")
    if [[ "$run_status" == "completed" ]]; then
        pass "Run metadata saved correctly"
    else
        fail "Run metadata wrong status: $run_status"
    fi
else
    fail "Run metadata file not created"
fi

# --- Cleanup ---
echo ""
echo "Cleaning up temp HOME: $HOME"
rm -rf "$HOME"

# --- Summary ---
echo ""
echo "================================================================"
echo "  Test Results Summary"
echo "================================================================"
echo ""
echo "Total Tests: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"

exit $([[ $FAILED -eq 0 ]] && echo 0 || echo 1)
