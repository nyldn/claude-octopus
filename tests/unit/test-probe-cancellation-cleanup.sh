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

probe_processes_gone() {
    local pid
    for pid in "$@"; do
        kill -0 "$pid" 2>/dev/null && return 1
    done
    return 0
}

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
OCTOPUS_ACTIVE_PROBE_TASK_IDS=("$task_id")

if declare -F octopus_probe_cancel_active >/dev/null 2>&1; then
    octopus_probe_cancel_active TERM
else
    review_terminate_process_tree "$provider_pid" 0
    kill -TERM "$synthesis_pid" 2>/dev/null || true
fi

wait "$provider_pid" 2>/dev/null || true
wait "$synthesis_pid" 2>/dev/null || true

attempt=0
while ! probe_processes_gone "$provider_pid" "$provider_child_pid" "$synthesis_pid" \
      && [[ "$attempt" -lt 100 ]]; do
    sleep 0.05
    attempt=$((attempt + 1))
done
if probe_processes_gone "$provider_pid" "$provider_child_pid" "$synthesis_pid"; then
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

test_case "registered task without PID is still marked and terminated logically"
no_pid_group="841002"
no_pid_task="probe-${no_pid_group}-0"
no_pid_result="$RESULTS_DIR/codex-${no_pid_task}.md"
printf '# Agent: codex\n\npartial before PID assignment\n' > "$no_pid_result"
OCTOPUS_ACTIVE_PROBE_TASK_GROUP="$no_pid_group"
OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID=""
OCTOPUS_ACTIVE_PROBE_TMUX="false"
OCTOPUS_ACTIVE_PROBE_PIDS=()
OCTOPUS_ACTIVE_PROBE_AGENTS=("codex")
OCTOPUS_ACTIVE_PROBE_TASK_IDS=("$no_pid_task")
octopus_probe_cancel_active TERM
if grep -q '^## Status: CANCELLED - PARTIAL RESULTS' "$no_pid_result" \
   && jq -e --arg task "$no_pid_task" \
        'select(.event == "agent.cancelled" and .attributes.task_id == $task)' \
        "$OCTO_EVENT_LOG" >/dev/null 2>&1; then
    test_pass
else
    test_fail "task registered before PID assignment was not reconciled"
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
    unset OCTOPUS_WORKFLOW_STATE_DIR OCTOPUS_STATE_PROJECT_ROOT \
        CLAUDE_PLUGIN_DATA CLAUDE_OCTOPUS_WORKSPACE
    HOME="$direct_home" "$PROJECT_ROOT/scripts/state-manager.sh" init_state \
        >/dev/null 2>&1
)
direct_state_file="$(find "$direct_home/.claude-octopus/projects" -name state.json -type f -print -quit 2>/dev/null || true)"
if [[ ! -e "$direct_project/.claude-octopus/state.json" \
   && -n "$direct_state_file" && -f "$direct_state_file" ]]; then
    test_pass
else
    test_fail "standalone state manager dirtied the project or lost state"
fi

test_case "standalone context manager also defaults outside the project"
context_home="$TEST_TMP_DIR/context-home"
context_project="$TEST_TMP_DIR/context-project"
mkdir -p "$context_home" "$context_project"
(
    cd "$context_project"
    env -u OCTOPUS_WORKFLOW_STATE_DIR -u OCTOPUS_STATE_PROJECT_ROOT \
        -u CLAUDE_PLUGIN_DATA -u CLAUDE_OCTOPUS_WORKSPACE \
        "HOME=$context_home" \
        "$PROJECT_ROOT/scripts/context-manager.sh" init_context_dir >/dev/null 2>&1
)
context_dir="$(find "$context_home/.claude-octopus/projects" -name context -type d -print -quit 2>/dev/null || true)"
if [[ ! -d "$context_project/.claude-octopus/context" && -n "$context_dir" ]]; then
    test_pass
else
    test_fail "standalone context manager dirtied the project or lost context state"
fi

test_case "portable CLI resolves the namespaced workflow state path"
cli_state_file=$(
    cd "$direct_project"
    unset OCTOPUS_WORKFLOW_STATE_DIR OCTOPUS_STATE_PROJECT_ROOT \
        CLAUDE_PLUGIN_DATA CLAUDE_OCTOPUS_WORKSPACE
    HOME="$direct_home" "$PROJECT_ROOT/bin/octopus" state-path
)
if [[ "$cli_state_file" == "$direct_state_file" ]]; then
    test_pass
else
    test_fail "octopus state-path returned $cli_state_file instead of $direct_state_file"
fi

test_case "workspace resolver expands tilde consistently"
literal_tilde='~'
tilde_state_file=$(
    cd "$direct_project"
    unset OCTOPUS_WORKFLOW_STATE_DIR OCTOPUS_STATE_PROJECT_ROOT CLAUDE_PLUGIN_DATA
    HOME="$direct_home" CLAUDE_OCTOPUS_WORKSPACE="${literal_tilde}/custom-octopus" \
        "$PROJECT_ROOT/bin/octopus" state-path
)
case "$tilde_state_file" in
    "$direct_home/custom-octopus/projects/"*/state.json) test_pass ;;
    *) test_fail "tilde workspace resolved unexpectedly: $tilde_state_file" ;;
esac

test_case "workspace resolver has a deterministic fallback without HOME"
no_home_state_file=$(
    cd "$direct_project"
    env -u HOME -u OCTOPUS_WORKFLOW_STATE_DIR -u OCTOPUS_STATE_PROJECT_ROOT \
        -u CLAUDE_PLUGIN_DATA -u CLAUDE_OCTOPUS_WORKSPACE \
        "$PROJECT_ROOT/bin/octopus" state-path
)
case "$no_home_state_file" in
    "$direct_project/.claude-octopus/projects/"*/state.json) test_pass ;;
    *) test_fail "HOME-less workspace resolved unexpectedly: $no_home_state_file" ;;
esac

test_case "same remote in separate checkouts gets separate state namespaces"
clone_a="$TEST_TMP_DIR/clone-a"
clone_b="$TEST_TMP_DIR/clone-b"
mkdir -p "$clone_a" "$clone_b"
git -C "$clone_a" init -q
git -C "$clone_b" init -q
git -C "$clone_a" remote add origin https://example.invalid/shared/repo.git
git -C "$clone_b" remote add origin https://example.invalid/shared/repo.git
clone_a_state=$(
    cd "$clone_a"
    unset OCTOPUS_WORKFLOW_STATE_DIR OCTOPUS_STATE_PROJECT_ROOT \
        CLAUDE_PLUGIN_DATA CLAUDE_OCTOPUS_WORKSPACE
    HOME="$direct_home" "$PROJECT_ROOT/bin/octopus" state-path
)
clone_b_state=$(
    cd "$clone_b"
    unset OCTOPUS_WORKFLOW_STATE_DIR OCTOPUS_STATE_PROJECT_ROOT \
        CLAUDE_PLUGIN_DATA CLAUDE_OCTOPUS_WORKSPACE
    HOME="$direct_home" "$PROJECT_ROOT/bin/octopus" state-path
)
if [[ "$clone_a_state" != "$clone_b_state" ]]; then
    test_pass
else
    test_fail "separate checkouts with one remote shared $clone_a_state"
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

test_case "probe synthesis failure keeps recovery marker and returns non-zero"
probe_tail="$(sed -n '/# Intelligent synthesis (v7.19.0 P1.1/,/^}/p' "$PROJECT_ROOT/scripts/lib/workflows.sh")"
if grep -q 'local synthesis_status=0' <<< "$probe_tail" \
   && grep -q 'synthesize_probe_results.*synthesis_status' <<< "$(tr '\n' ' ' <<< "$probe_tail")" \
   && grep -q 'if \[\[ "$synthesis_status" -eq 0 \]\]' <<< "$probe_tail" \
   && grep -q 'return "$synthesis_status"' <<< "$probe_tail"; then
    test_pass
else
    test_fail "probe_discover does not preserve synthesis failure through cleanup"
fi

test_summary
