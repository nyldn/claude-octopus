#!/usr/bin/env bash
# Regression coverage for #841: cancelling a probe must leave no live process
# tree or stale runtime metadata, and ordinary orchestration must not write
# state into the user's project by default.
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
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

test_suite "Probe cancellation cleanup (#841)"

provider_pid=""
provider_child_pid=""
synthesis_pid=""

cleanup_probe_processes() {
    for pid in "$provider_child_pid" "$provider_pid" "$synthesis_pid"; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
}
after_all cleanup_probe_processes

test_case "probe cancellation helper is available"
if declare -F octopus_probe_cancel_active >/dev/null 2>&1; then
    test_pass
else
    test_fail "octopus_probe_cancel_active is missing"
fi

test_case "TERM reaps provider descendants and synthesis monitor"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
RESULTS_DIR="$WORKSPACE_DIR/results"
PID_FILE="$WORKSPACE_DIR/pids"
OCTO_EVENT_LOG="$RESULTS_DIR/events.jsonl"
mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR/.octo/agents"

child_pid_file="$TEST_TMP_DIR/provider-child.pid"
bash -c '
    trap "" TERM
    sleep 300 &
    printf "%s\n" "$!" > "$1"
    wait
' _ "$child_pid_file" &
provider_pid=$!

attempt=0
while [[ ! -s "$child_pid_file" && "$attempt" -lt 100 ]]; do
    sleep 0.02
    attempt=$((attempt + 1))
done
provider_child_pid="$(cat "$child_pid_file" 2>/dev/null || true)"

sleep 300 &
synthesis_pid=$!

task_group="841001"
task_id="probe-${task_group}-0"
result_file="$RESULTS_DIR/codex-${task_id}.md"
cat > "$result_file" <<EOF
# Agent: codex
# Task ID: $task_id

## Output
\`\`\`
partial output before cancellation
EOF
touch "$WORKSPACE_DIR/.octo/agents/${provider_pid}.heartbeat"
printf '%s:%s:%s\n' "$provider_pid" "codex" "$task_id" > "$PID_FILE"

OCTOPUS_ACTIVE_PROBE_TASK_GROUP="$task_group"
OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID="$synthesis_pid"
OCTOPUS_ACTIVE_PROBE_TMUX="false"
OCTOPUS_ACTIVE_PROBE_PIDS=("$provider_pid")
OCTOPUS_ACTIVE_PROBE_AGENTS=("codex")

if declare -F octopus_probe_cancel_active >/dev/null 2>&1; then
    octopus_probe_cancel_active TERM
else
    review_terminate_process_tree "$provider_pid" 0
    kill -TERM "$synthesis_pid" 2>/dev/null || true
fi

wait "$provider_pid" 2>/dev/null || true
wait "$synthesis_pid" 2>/dev/null || true

if ! kill -0 "$provider_pid" 2>/dev/null \
   && ! kill -0 "$provider_child_pid" 2>/dev/null \
   && ! kill -0 "$synthesis_pid" 2>/dev/null; then
    test_pass
else
    test_fail "provider tree or synthesis monitor survived cancellation"
fi

test_case "cancellation reconciles PID and heartbeat records"
if ! grep -q "$task_id" "$PID_FILE" 2>/dev/null \
   && [[ ! -e "$WORKSPACE_DIR/.octo/agents/${provider_pid}.heartbeat" ]]; then
    test_pass
else
    test_fail "stale PID or heartbeat metadata remains"
fi

test_case "partial result is explicitly marked cancelled"
if grep -q '^## Status: CANCELLED - PARTIAL RESULTS' "$result_file"; then
    test_pass
else
    test_fail "cancelled result lacks an explicit terminal marker"
fi

test_case "spawned task receives an agent.cancelled terminal event"
if jq -e --arg task "$task_id" \
    'select(.event == "agent.cancelled" and .attributes.task_id == $task and .attributes.status == "cancelled")' \
    "$OCTO_EVENT_LOG" >/dev/null 2>&1; then
    test_pass
else
    test_fail "agent.cancelled event missing for $task_id"
fi

test_case "probe signal handler maps TERM to exit 143"
if env "HOME=$TEST_TMP_DIR/signal-home" bash -c '
    source "'"$PROJECT_ROOT"'/scripts/lib/workflows.sh"
    OCTOPUS_ACTIVE_PROBE_TASK_GROUP="signal-term"
    WORKSPACE_DIR="'"$TEST_TMP_DIR"'/signal-workspace"
    RESULTS_DIR="$WORKSPACE_DIR/results"
    PID_FILE="$WORKSPACE_DIR/pids"
    octopus_probe_handle_signal TERM
' >/dev/null 2>&1; then
    signal_rc=0
else
    signal_rc=$?
fi
if [[ "$signal_rc" -eq 143 ]]; then test_pass; else test_fail "TERM returned $signal_rc instead of 143"; fi

test_case "probe signal handler maps INT to exit 130"
if env "HOME=$TEST_TMP_DIR/signal-home" bash -c '
    source "'"$PROJECT_ROOT"'/scripts/lib/workflows.sh"
    OCTOPUS_ACTIVE_PROBE_TASK_GROUP="signal-int"
    WORKSPACE_DIR="'"$TEST_TMP_DIR"'/signal-workspace"
    RESULTS_DIR="$WORKSPACE_DIR/results"
    PID_FILE="$WORKSPACE_DIR/pids"
    octopus_probe_handle_signal INT
' >/dev/null 2>&1; then
    signal_rc=0
else
    signal_rc=$?
fi
if [[ "$signal_rc" -eq 130 ]]; then test_pass; else test_fail "INT returned $signal_rc instead of 130"; fi

test_case "dry-run orchestration keeps default state outside the project"
fixture_home="$TEST_TMP_DIR/home"
fixture_project="$TEST_TMP_DIR/project"
mkdir -p "$fixture_home/.claude-octopus" "$fixture_project"
printf '{"feature_ledger_sentinel":true}\n' > "$fixture_home/.claude-octopus/state.json"
(
    unset OCTOPUS_WORKFLOW_STATE_DIR OCTOPUS_STATE_PROJECT_ROOT
    cd "$fixture_project"
    env \
        "HOME=$fixture_home" \
        "OCTOPUS_NON_INTERACTIVE=1" \
        "OCTOPUS_HOST=standalone" \
        "$PROJECT_ROOT/scripts/orchestrate.sh" --dry-run probe "state placement check" \
        >/dev/null 2>&1
)
global_state_file="$(find "$fixture_home/.claude-octopus/projects" -name state.json -type f -print -quit 2>/dev/null || true)"
if [[ ! -e "$fixture_project/.claude-octopus/state.json" ]] \
   && [[ -n "$global_state_file" && -f "$global_state_file" ]] \
   && jq -e '.project_id and .metrics.provider_usage' "$global_state_file" >/dev/null 2>&1 \
   && jq -e '.feature_ledger_sentinel == true and (keys | length == 1)' \
        "$fixture_home/.claude-octopus/state.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "orchestrate wrote state into the project or failed to create global state"
fi

test_case "standalone state manager also defaults outside the project"
direct_home="$TEST_TMP_DIR/direct-home"
direct_project="$TEST_TMP_DIR/direct-project"
mkdir -p "$direct_home" "$direct_project"
(
    cd "$direct_project"
    env "HOME=$direct_home" "$PROJECT_ROOT/scripts/state-manager.sh" init_state \
        >/dev/null 2>&1
)
direct_state_file="$(find "$direct_home/.claude-octopus/projects" -name state.json -type f -print -quit 2>/dev/null || true)"
if [[ ! -e "$direct_project/.claude-octopus/state.json" \
   && -n "$direct_state_file" && -f "$direct_state_file" ]]; then
    test_pass
else
    test_fail "standalone state manager dirtied the project or lost state"
fi

test_case "portable CLI resolves the namespaced workflow state path"
cli_state_file=$(
    cd "$direct_project"
    env "HOME=$direct_home" "$PROJECT_ROOT/bin/octopus" state-path
)
if [[ "$cli_state_file" == "$direct_state_file" ]]; then
    test_pass
else
    test_fail "octopus state-path returned $cli_state_file instead of $direct_state_file"
fi

test_case "project-local workflow state requires explicit opt-in"
opt_in_project="$TEST_TMP_DIR/opt-in-project"
mkdir -p "$opt_in_project"
(
    cd "$opt_in_project"
    env \
        "HOME=$direct_home" \
        "OCTOPUS_WORKFLOW_STATE_DIR=$opt_in_project/.claude-octopus" \
        "$PROJECT_ROOT/scripts/state-manager.sh" init_state >/dev/null 2>&1
)
if [[ -f "$opt_in_project/.claude-octopus/state.json" ]]; then
    test_pass
else
    test_fail "explicit project-local state directory was not honored"
fi

test_summary
