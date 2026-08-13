#!/usr/bin/env bash
# Regression coverage for #900: cancelling Tangle must terminate every provider
# descendant, reconcile its runtime ledger, and prevent post-cancel writes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

log() { :; }
octo_provider_identity_from_agent_type() { printf '%s\n' "${1%%-*}"; }
get_agent_model() { printf '%s\n' "fixture-model"; }

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/events.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/review.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

test_suite "Tangle cancellation cleanup (#900)"

worker_pid=""
worker_child_pid=""

cleanup_tangle_processes() {
    local pid
    for pid in "$worker_child_pid" "$worker_pid"; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
}
after_all cleanup_tangle_processes

process_is_running() {
    local pid="$1" stat
    kill -0 "$pid" 2>/dev/null || return 1
    stat=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]') || return 1
    [[ -n "$stat" && "$stat" != Z* ]]
}

test_case "tangle cancellation helper is available"
if declare -F octopus_tangle_cancel_active >/dev/null 2>&1; then
    test_pass
else
    test_fail "octopus_tangle_cancel_active is missing"
    octopus_tangle_cancel_active() { :; }
fi

test_case "TERM reaps ledger-only worker tree and prevents late writes"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
RESULTS_DIR="$WORKSPACE_DIR/results"
PID_FILE="$WORKSPACE_DIR/pids"
mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR/.octo/agents"

child_pid_file="$TEST_TMP_DIR/worker-child.pid"
late_write="$TEST_TMP_DIR/late-write"
bash -c '
    trap "" TERM
    (
        sleep 1
        : > "$2"
    ) &
    printf "%s\n" "$!" > "$1"
    wait
' _ "$child_pid_file" "$late_write" &
worker_pid=$!

attempt=0
while [[ ! -s "$child_pid_file" && "$attempt" -lt 100 ]]; do
    sleep 0.02
    attempt=$((attempt + 1))
done
worker_child_pid="$(cat "$child_pid_file" 2>/dev/null || true)"

task_group="900001"
task_id="tangle-${task_group}-0"
result_file="$RESULTS_DIR/codex-${task_id}.md"
printf '# Agent: codex\n# Task ID: %s\n\n## Output\npartial output\n' "$task_id" > "$result_file"
printf '%s:%s:%s\n' "$worker_pid" "codex" "$task_id" > "$PID_FILE"

# Exercise the signal handoff window: the worker reached the authoritative PID
# ledger before spawn_agent_capture_pid returned it to the in-memory array.
OCTOPUS_ACTIVE_TANGLE_TASK_GROUP="$task_group"
OCTOPUS_ACTIVE_TANGLE_TMUX="false"
OCTOPUS_ACTIVE_TANGLE_PIDS=()
OCTOPUS_ACTIVE_TANGLE_AGENTS=()
OCTOPUS_ACTIVE_TANGLE_TASK_IDS=()

octopus_tangle_cancel_active TERM
wait "$worker_pid" 2>/dev/null || true
sleep 1.1

if ! process_is_running "$worker_pid" \
   && ! process_is_running "$worker_child_pid" \
   && [[ ! -e "$late_write" ]]; then
    test_pass
else
    test_fail "worker tree survived cancellation or wrote after cancellation"
fi

test_case "cancellation records terminal state and prunes runtime metadata"
done_file="$WORKSPACE_DIR/.octo/agents/${task_id}.done"
if [[ "$(cat "$done_file" 2>/dev/null || true)" == "cancelled" ]] \
   && grep -q '^## Status: CANCELLED - PARTIAL RESULTS' "$result_file" \
   && ! grep -q "$task_id" "$PID_FILE" 2>/dev/null \
   && [[ -z "${OCTOPUS_ACTIVE_TANGLE_TASK_GROUP:-}" ]]; then
    test_pass
else
    test_fail "cancelled Tangle task lacks terminal marker, result status, ledger cleanup, or state reset"
fi

test_case "cancellation reaps provider spawned before PID ledger handoff"
preledger_write="$TEST_TMP_DIR/preledger-late-write"
bash -c '
    trap "" TERM
    (
        sleep 1
        : > "$1"
    ) &
    wait
' _ "$preledger_write" &
preledger_pid=$!
OCTOPUS_ACTIVE_TANGLE_TASK_GROUP="900002"
OCTOPUS_ACTIVE_TANGLE_TMUX="false"
OCTOPUS_ACTIVE_TANGLE_PIDS=("")
OCTOPUS_ACTIVE_TANGLE_AGENTS=("codex")
OCTOPUS_ACTIVE_TANGLE_TASK_IDS=("tangle-900002-0")
: > "$PID_FILE"

octopus_tangle_cancel_active TERM
wait "$preledger_pid" 2>/dev/null || true
sleep 1.1

if ! process_is_running "$preledger_pid" && [[ ! -e "$preledger_write" ]]; then
    test_pass
else
    kill -KILL "$preledger_pid" 2>/dev/null || true
    test_fail "provider survived cancellation before PID ledger handoff"
fi

test_case "frozen cancellation kills a worker group after its leader exits"
group_child_pid_file="$TEST_TMP_DIR/group-child.pid"
group_late_write="$TEST_TMP_DIR/group-late-write"
monitor_was_enabled=false
[[ "$-" == *m* ]] && monitor_was_enabled=true
set -m
bash -c '
    (
        trap "" TERM
        sleep 1
        : > "$2"
    ) &
    printf "%s\n" "$!" > "$1"
' _ "$group_child_pid_file" "$group_late_write" &
group_leader_pid=$!
[[ "$monitor_was_enabled" == "true" ]] || set +m
wait "$group_leader_pid" 2>/dev/null || true
group_child_pid="$(cat "$group_child_pid_file" 2>/dev/null || true)"

review_kill_process_tree_frozen "$group_leader_pid"
sleep 1.1

if [[ -n "$group_child_pid" ]] \
   && ! process_is_running "$group_child_pid" \
   && [[ ! -e "$group_late_write" ]]; then
    test_pass
else
    kill -KILL "$group_child_pid" 2>/dev/null || true
    test_fail "provider group survived after its recorded leader exited"
fi

test_case "tangle signal handler maps TERM to exit 143"
if env "HOME=$TEST_TMP_DIR/signal-home" bash -c '
    source "'"$PROJECT_ROOT"'/scripts/lib/workflows.sh"
    OCTOPUS_ACTIVE_TANGLE_TASK_GROUP="signal-term"
    WORKSPACE_DIR="'"$TEST_TMP_DIR"'/signal-workspace"
    RESULTS_DIR="$WORKSPACE_DIR/results"
    PID_FILE="$WORKSPACE_DIR/pids"
    octopus_tangle_handle_signal TERM
' >/dev/null 2>&1; then
    signal_rc=0
else
    signal_rc=$?
fi
if [[ "$signal_rc" -eq 143 ]]; then test_pass; else test_fail "TERM returned $signal_rc instead of 143"; fi

test_case "orchestrator signal traps cancel work and exit"
orchestrator_source="$PROJECT_ROOT/scripts/orchestrate.sh"
if grep -Fq "trap 'octopus_orchestrator_handle_signal TERM' TERM" "$orchestrator_source" \
   && grep -Fq "trap 'octopus_orchestrator_handle_signal INT' INT" "$orchestrator_source" \
   && grep -Fq "trap 'octopus_orchestrator_handle_exit \"\$?\"' EXIT" "$orchestrator_source" \
   && ! grep -Fq "trap 'rm -rf \"\$OCTOPUS_TMP_DIR\"' EXIT INT TERM" "$orchestrator_source"; then
    test_pass
else
    test_fail "top-level orchestrator still swallows INT/TERM without cancellation and exit"
fi

test_case "unexpected orchestrator exit cancels registered Tangle work"
if declare -F octopus_orchestrator_handle_exit >/dev/null 2>&1; then
    unset -f octopus_orchestrator_handle_exit
fi
eval "$(sed -n '/^octopus_orchestrator_handle_exit() {/,/^}/p' "$orchestrator_source")"
exit_cleanup_log="$TEST_TMP_DIR/exit-cleanup.log"
octopus_orchestrator_cancel_active() { printf 'cancel:%s\n' "$1" >> "$exit_cleanup_log"; }
octopus_cleanup_tmp() { printf 'tmp\n' >> "$exit_cleanup_log"; }
if declare -F octopus_orchestrator_handle_exit >/dev/null 2>&1; then
    if octopus_orchestrator_handle_exit 37; then exit_handler_rc=0; else exit_handler_rc=$?; fi
else
    exit_handler_rc=127
fi
if [[ "$exit_handler_rc" -eq 37 ]] \
   && grep -q '^cancel:TERM$' "$exit_cleanup_log" 2>/dev/null \
   && grep -q '^tmp$' "$exit_cleanup_log" 2>/dev/null; then
    test_pass
else
    test_fail "EXIT handler did not cancel active work, preserve status 37, and clean temp state"
fi

test_summary
