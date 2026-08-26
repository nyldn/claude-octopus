#!/usr/bin/env bash
# v10 cancellation, terminal reconciliation, and safe retry contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "v10 cancellation and recovery"

log() { :; }
octo_provider_identity_from_agent_type() { printf '%s\n' "${1%%-*}"; }
get_agent_model() { printf 'fixture-model\n'; }

source "$PROJECT_ROOT/scripts/lib/events.sh"
source "$PROJECT_ROOT/scripts/lib/review.sh"
source "$PROJECT_ROOT/scripts/lib/run-contract.sh"
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
RESULTS_DIR="$WORKSPACE_DIR/results"
PID_FILE="$WORKSPACE_DIR/pids"
OCTOPUS_RUN_ID="cancel-recovery"
mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR/.octo/agents"

tree_parent="" tree_child=""
cleanup_tree() {
    [[ "$tree_parent" =~ ^[0-9]+$ ]] && kill -KILL "$tree_parent" 2>/dev/null || true
    [[ "$tree_child" =~ ^[0-9]+$ ]] && kill -KILL "$tree_child" 2>/dev/null || true
}
after_all cleanup_tree

test_case "cancelled process tree terminalizes only with cleanup evidence"
task_group="v10cancel"
task_id="probe-${task_group}-0"
seat_id="$(octo_spawn_contract_seat_id "$task_id")"
result_file="$RESULTS_DIR/codex-${task_id}.md"
printf 'partial output\n' > "$result_file"
octo_spawn_contract_begin "$task_id" codex fixture-model low probe researcher

child_file="$TEST_TMP_DIR/tree-child.pid"
bash -c '
  trap "" TERM
  sleep 300 &
  printf "%s\n" "$!" > "$1"
  wait
' _ "$child_file" &
tree_parent=$!
for _attempt in $(seq 1 100); do [[ -s "$child_file" ]] && break; sleep 0.02; done
tree_child="$(<"$child_file")"
printf '%s:codex:%s\n' "$tree_parent" "$task_id" > "$PID_FILE"
OCTOPUS_ACTIVE_PROBE_TASK_GROUP="$task_group"
OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID=""
OCTOPUS_ACTIVE_PROBE_TMUX=false
OCTOPUS_ACTIVE_PROBE_PIDS=("$tree_parent")
OCTOPUS_ACTIVE_PROBE_AGENTS=(codex)
OCTOPUS_ACTIVE_PROBE_TASK_IDS=("$task_id")
octopus_probe_cancel_active TERM
tree_survived=false
for _attempt in $(seq 1 100); do
    if ! kill -0 "$tree_parent" 2>/dev/null && ! kill -0 "$tree_child" 2>/dev/null; then
        break
    fi
    sleep 0.02
done
if kill -0 "$tree_parent" 2>/dev/null || kill -0 "$tree_child" 2>/dev/null; then
    tree_survived=true
    cleanup_tree
fi
wait "$tree_parent" 2>/dev/null || true

snapshot="$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/seats.json"
if [[ "$tree_survived" == false ]] &&
   ! kill -0 "$tree_parent" 2>/dev/null && ! kill -0 "$tree_child" 2>/dev/null &&
   jq -e --arg seat "$seat_id" '
      .seats[] | select(.seat_id == $seat) |
      .transition == "cancelled" and
      .execution.cleanup_result == "terminated"
   ' "$snapshot" >/dev/null 2>&1; then
    test_pass
else
    test_fail "process tree survived or cancellation lacks cleanup evidence"
fi

test_case "stale running record reconciles after process exit"
stale_seat="stale-seat"
run_contract_transition "$stale_seat" planned requested_provider=codex requested_model=fixture
run_contract_transition "$stale_seat" starting resolved_provider=codex resolved_model=fixture
run_contract_transition "$stale_seat" authenticated
run_contract_transition "$stale_seat" running
if declare -f run_contract_reconcile_stale >/dev/null 2>&1 &&
   run_contract_reconcile_stale "$stale_seat" 999999 &&
   jq -e --arg seat "$stale_seat" '
      .seats[] | select(.seat_id == $seat) |
      .transition == "failed" and .execution.cleanup_result == "already-exited"
   ' "$snapshot" >/dev/null 2>&1; then
    test_pass
else
    test_fail "stale running seat was not terminalized"
fi

test_case "retry creates a distinct attempt only for non-contributed seats"
failed_seat="retry-source"
run_contract_transition "$failed_seat" planned requested_provider=codex requested_model=fixture attempt_id=attempt-1
run_contract_transition "$failed_seat" failed reason=fixture-failure
retry_seat=""
if declare -f run_contract_retry_seat >/dev/null 2>&1; then
    retry_seat="$(run_contract_retry_seat "$failed_seat" attempt-2 2>/dev/null || true)"
fi

contributed_seat="no-retry"
contributed_output="$TEST_TMP_DIR/contributed.md"
printf 'substantive output\n' > "$contributed_output"
run_contract_transition "$contributed_seat" planned requested_provider=codex requested_model=fixture attempt_id=attempt-1
run_contract_transition "$contributed_seat" starting resolved_provider=codex resolved_model=fixture
run_contract_transition "$contributed_seat" authenticated
run_contract_transition "$contributed_seat" running
run_contract_transition "$contributed_seat" output_received output_file="$contributed_output"
run_contract_transition "$contributed_seat" validated contribution=eligible
run_contract_transition "$contributed_seat" contributed contribution=eligible
set +e
run_contract_retry_seat "$contributed_seat" attempt-2 >/dev/null 2>&1
contributed_retry_rc=$?
set -e
if [[ "$retry_seat" != "$failed_seat" && -n "$retry_seat" && "$contributed_retry_rc" -ne 0 ]] &&
   jq -e --arg seat "$retry_seat" '
      .seats[] | select(.seat_id == $seat) |
      .transition == "planned" and .attempt_id == "attempt-2"
   ' "$snapshot" >/dev/null 2>&1; then
    test_pass
else
    test_fail "retry_seat=$retry_seat contributed_retry_rc=$contributed_retry_rc"
fi

test_case "run records preserve source and cleanup attribution"
attributed="attributed-seat"
if run_contract_transition "$attributed" planned \
      requested_provider=codex requested_model=fixture attempt_id=attempt-source \
      source_sha=deadbeef source_dirty=dirty-blocked checkpoint=probe \
      pid=123 pgid=123 cleanup_result=not-started diff_file=/tmp/change.diff 2>/dev/null &&
   jq -e --arg seat "$attributed" '
      .seats[] | select(.seat_id == $seat) |
      .source == {sha:"deadbeef", dirty_decision:"dirty-blocked"} and
      .execution.checkpoint == "probe" and
      .execution.cleanup_result == "not-started" and
      .process == {pid:"123", pgid:"123"} and
      .artifacts.diff == "/tmp/change.diff"
   ' "$snapshot" >/dev/null 2>&1; then
    test_pass
else
    test_fail "source/process/cleanup attribution is incomplete"
fi

test_summary
