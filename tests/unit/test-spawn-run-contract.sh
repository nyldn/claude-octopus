#!/usr/bin/env bash
# Contract tests for supervised and Agent Teams background execution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "v10 background run contract"

export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
export OCTOPUS_WORKSPACE="$WORKSPACE_DIR"
export OCTOPUS_RUN_ID="spawn-contract-test"
export RESULTS_DIR="$WORKSPACE_DIR/results"
mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR/agent-teams"

source "$PROJECT_ROOT/scripts/lib/run-contract.sh"
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"
source "$PROJECT_ROOT/scripts/lib/validation.sh"
source "$PROJECT_ROOT/scripts/lib/model-cache-path.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
source "$PROJECT_ROOT/scripts/lib/agents.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
source "$PROJECT_ROOT/scripts/lib/utils.sh"
eval "$(declare -f get_agent_command | sed '1s/get_agent_command/octo_real_get_agent_command/')"
eval "$(declare -f validate_agent_command | sed '1s/validate_agent_command/octo_real_validate_agent_command/')"
octo_provider_identity_from_agent_type() { printf '%s\n' "${1%%-*}"; }
get_agent_model() { printf '%s\n' fixture-model; }

ledger="$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/seats.jsonl"
valid_output="$RESULTS_DIR/valid.md"
placeholder_output="$RESULTS_DIR/placeholder.md"
printf '%s\n' 'Substantive background result.' > "$valid_output"
printf '%s\n' 'Provider available' > "$placeholder_output"

transitions_for() {
    jq -r --arg seat "$1" 'select(.seat_id == $seat) | .transition' "$ledger" | paste -sd, -
}

assert_terminal() {
    local name="$1" seat="$2" transition="$3" contribution="$4" reason="$5"
    test_case "$name"
    if jq -e --arg seat "$seat" --arg transition "$transition" \
        --arg contribution "$contribution" --arg reason "$reason" '
        select(.seat_id == $seat) |
        select(.transition == $transition and .contribution == $contribution and .reason == $reason)
    ' "$ledger" >/dev/null; then
        test_pass
    else
        test_fail "missing exact terminal record for $seat"
    fi
}

test_case "background helper begins one truthful running lifecycle"
if octo_spawn_contract_plan "task-success" codex-standard gpt-5.6-luna low probe reviewer && \
   [[ "$(transitions_for spawn-task-success)" == "planned" ]] && \
   octo_spawn_contract_resolve spawn-task-success codex-standard gpt-5.6-luna low && \
   [[ "$(transitions_for spawn-task-success)" == "planned,starting" ]] && \
   octo_spawn_contract_authenticated spawn-task-success && \
   [[ "$(transitions_for spawn-task-success)" == "planned,starting,authenticated" ]] && \
   octo_spawn_contract_running spawn-task-success && \
   [[ "$(transitions_for spawn-task-success)" == "planned,starting,authenticated,running" ]]; then
    test_pass
else
    test_fail "background lifecycle did not reach running in order"
fi

test_case "successful background output becomes contribution eligible"
if octo_spawn_contract_finish "spawn-task-success" success "$valid_output" "" "" 0 21 && \
   [[ "$(transitions_for spawn-task-success)" == "planned,starting,authenticated,running,output_received,validated,contributed" ]] && \
   run_contract_contribution_eligible spawn-task-success; then
    test_pass
else
    test_fail "success did not pass through output validation"
fi

octo_spawn_contract_begin "task-degraded" codex-standard gpt-5.6-luna low probe reviewer
octo_spawn_contract_finish "spawn-task-degraded" degraded "$valid_output" "" "recoverable stdin closure" 0 18
assert_terminal "degraded output is eligible only with warning" \
    spawn-task-degraded degraded eligible-with-warning "recoverable stdin closure"

octo_spawn_contract_begin "task-timeout" codex-standard gpt-5.6-luna low probe reviewer
octo_spawn_contract_finish "spawn-task-timeout" timeout "$valid_output" "" "Timed out before completion" 124 50
assert_terminal "timeout partial output is never contribution eligible" \
    spawn-task-timeout timeout none "Timed out before completion"

octo_spawn_contract_begin "task-cancelled" codex-standard gpt-5.6-luna low probe reviewer
cancel_result="$RESULTS_DIR/codex-task-cancelled.md"
printf '%s\n' '# Agent: codex' '' 'partial provider result' > "$cancel_result"
OCTOPUS_ACTIVE_PROBE_TASK_GROUP="contract-cancel"
OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID=""
OCTOPUS_ACTIVE_PROBE_TMUX="false"
OCTOPUS_ACTIVE_PROBE_PIDS=()
OCTOPUS_ACTIVE_PROBE_AGENTS=(codex)
OCTOPUS_ACTIVE_PROBE_TASK_IDS=(task-cancelled)
PID_FILE="$WORKSPACE_DIR/cancel-pids"
: > "$PID_FILE"
octopus_probe_cancel_active TERM
assert_terminal "cancelled partial output is never contribution eligible" \
    spawn-task-cancelled cancelled none "Cancelled by SIGTERM"

octo_spawn_contract_begin "task-unusable" codex-standard gpt-5.6-luna low probe reviewer
test_case "placeholder success is terminalized as failed"
if ! octo_spawn_contract_finish "spawn-task-unusable" success "$placeholder_output" "" "" 0 4 && \
   [[ "$(run_contract_latest_transition spawn-task-unusable)" == failed ]]; then
    test_pass
else
    test_fail "placeholder output was accepted or left running"
fi
assert_terminal "placeholder failure records an exact reason" \
    spawn-task-unusable failed none "Provider returned unusable output"

octo_spawn_contract_begin "task-wrapper-only" codex-standard gpt-5.6-luna low probe reviewer
wrapper_output="$RESULTS_DIR/wrapper-only.md"
printf '%s\n' '# Agent: codex' '' '## Status: SUCCESS' > "$wrapper_output"
test_case "wrapper headers cannot validate unusable provider output"
if ! octo_spawn_contract_finish "spawn-task-wrapper-only" success "$wrapper_output" "" "" 0 4 "" "$placeholder_output" &&
   [[ "$(run_contract_latest_transition spawn-task-wrapper-only)" == failed ]]; then
    test_pass
else
    test_fail "rendered headers made placeholder provider output eligible"
fi

# A native teammate is dispatch evidence only. The real hook must capture and
# validate the result before it becomes synthesis eligible.
native_result="$RESULTS_DIR/claude-native-task.md"
native_instruction="$WORKSPACE_DIR/agent-teams/native-task.json"
octo_spawn_contract_begin "native-task" claude-sonnet claude-sonnet-4-6 medium probe researcher
octo_spawn_contract_begin "wrong-native-task" claude-sonnet claude-sonnet-4-6 medium probe researcher
jq -n \
    --arg result_file "$native_result" \
    '{result_file:$result_file, run_id:"wrong-run", seat_id:"spawn-wrong-native-task",
      dispatch_method:"agent_teams", agent_id:"different-agent"}' \
    > "$WORKSPACE_DIR/agent-teams/000-collision.json"
jq -n \
    --arg result_file "$native_result" \
    --arg run_id "$OCTOPUS_RUN_ID" \
    --arg seat_id "spawn-native-task" \
    '{result_file:$result_file, run_id:$run_id, seat_id:$seat_id,
      dispatch_method:"agent_teams", agent_id:"native-agent"}' > "$native_instruction"
printf '%s\n' '# Agent: claude-sonnet' '' > "$native_result"

test_case "Agent Teams hook captures then contributes substantive output"
if printf '%s' '{"agent_id":"native-agent","agent_type":"claude-sonnet","last_assistant_message":"Native teammate completed the requested analysis."}' | \
     "$PROJECT_ROOT/hooks/subagent-result-capture.sh" && \
   [[ "$(transitions_for spawn-native-task)" == "planned,starting,authenticated,running,output_received,validated,contributed" ]] && \
   [[ "$(run_contract_latest_transition spawn-wrong-native-task)" == running ]] && \
   grep -Fq 'Native teammate completed the requested analysis.' "$native_result"; then
    test_pass
else
    test_fail "hook did not turn native output into a contributed artifact"
fi

race_result="$RESULTS_DIR/claude-race-task.md"
octo_spawn_contract_begin "race-task" claude-sonnet claude-sonnet-4-6 medium probe researcher
jq -n --arg result_file "$race_result" --arg run_id "$OCTOPUS_RUN_ID" '
  {result_file:$result_file, run_id:$run_id, seat_id:"spawn-race-task",
   dispatch_method:"agent_teams", agent_id:"race-agent"}' \
  > "$WORKSPACE_DIR/agent-teams/race-task.json"
printf '%s\n' '# Agent: claude-sonnet' '' > "$race_result"
race_input='{"agent_id":"race-agent","agent_type":"claude-sonnet","last_assistant_message":"One atomic native result."}'
printf '%s' "$race_input" | "$PROJECT_ROOT/hooks/subagent-result-capture.sh" &
race_pid_one=$!
printf '%s' "$race_input" | "$PROJECT_ROOT/hooks/subagent-result-capture.sh" &
race_pid_two=$!
wait "$race_pid_one"
wait "$race_pid_two"
test_case "concurrent native hooks capture and terminalize exactly once"
if [[ "$(grep -Fc 'One atomic native result.' "$race_result")" -eq 1 ]] && \
   [[ "$(transitions_for spawn-race-task)" == "planned,starting,authenticated,running,output_received,validated,contributed" ]]; then
    test_pass
else
    test_fail "native result or contract transition was duplicated"
fi

empty_result="$RESULTS_DIR/claude-empty-task.md"
empty_instruction="$WORKSPACE_DIR/agent-teams/empty-task.json"
octo_spawn_contract_begin "empty-task" claude-sonnet claude-sonnet-4-6 medium probe researcher
jq -n \
    --arg result_file "$empty_result" \
    --arg run_id "$OCTOPUS_RUN_ID" \
    --arg seat_id "spawn-empty-task" \
    '{result_file:$result_file, run_id:$run_id, seat_id:$seat_id,
      dispatch_method:"agent_teams", agent_id:"empty-agent"}' > "$empty_instruction"
printf '%s\n' '# Agent: claude-sonnet' '' > "$empty_result"

test_case "Agent Teams hook terminalizes empty completion as failed"
if printf '%s' '{"agent_id":"empty-agent","agent_type":"claude-sonnet","last_assistant_message":""}' | \
     "$PROJECT_ROOT/hooks/subagent-result-capture.sh" && \
   [[ "$(run_contract_latest_transition spawn-empty-task)" == failed ]]; then
    test_pass
else
    test_fail "empty native completion remained running"
fi

fallback_result="$RESULTS_DIR/claude-fallback-task.md"
fallback_instruction="$WORKSPACE_DIR/agent-teams/fallback-task.json"
octo_spawn_contract_begin "fallback-task" claude-sonnet claude-sonnet-4-6 medium probe researcher
jq -n --arg result_file "$fallback_result" --arg run_id "$OCTOPUS_RUN_ID" '
  {result_file:$result_file, run_id:$run_id, seat_id:"spawn-fallback-task",
   dispatch_method:"agent_teams", agent_id:""}' > "$fallback_instruction"
printf '%s\n' '# Agent: claude-sonnet' '' > "$fallback_result"
test_case "native hook claims an initially uncorrelated instruction and backfills agent id"
if printf '%s' '{"agent_id":"claimed-agent","agent_type":"claude-sonnet","last_assistant_message":"Claimed native result."}' | \
     "$PROJECT_ROOT/hooks/subagent-result-capture.sh" && \
   [[ "$(run_contract_latest_transition spawn-fallback-task)" == contributed ]] && \
   [[ "$(jq -r '.agent_id' "$fallback_instruction")" == claimed-agent ]]; then
    test_pass
else
    test_fail "uncorrelated native instruction was not claimed truthfully"
fi

# Drive the real supervised spawn path with a hermetic provider. These stubs
# isolate unrelated routing/telemetry dependencies while retaining spawn's
# process, output, classification, timeout, and contract code.
fake_provider="$TEST_TMP_DIR/fake-background-provider.sh"
printf '%s\n' '#!/usr/bin/env bash' \
    'cat >/dev/null' \
    'case "${FAKE_SCENARIO:-success}" in' \
    '  success) printf "%s\n" "Substantive external provider result." ;;' \
    '  agy-contract) printf "%s\n" "${OCTOPUS_AGY_MODEL:-missing}" > "$AGY_MODEL_CAPTURE"; printf "%s\n" "Substantive AGY result." ;;' \
    '  exit) printf "%s\n" "provider rejected request" >&2; exit 42 ;;' \
    '  timeout) printf "%s\n" "partial output before timeout"; exit 124 ;;' \
    'esac' > "$fake_provider"
chmod +x "$fake_provider"

LOGS_DIR="$WORKSPACE_DIR/logs"
PID_FILE="$WORKSPACE_DIR/pids"
TIMEOUT=5
DRY_RUN=false
OCTOPUS_PERSISTENCE_AVAILABLE=true
OCTOPUS_BACKEND=api
CLAUDE_TASK_ID=""
SUPPORTS_FORK_CONTEXT=false
SUPPORTS_WORKTREE_HOOKS=false
SUPPORTS_FAST_BASH=false
SUPPORTS_AGENT_TYPE_ROUTING=false
SUPPORTS_NATIVE_AUTO_MEMORY=false
SUPPORTS_FAST_OPUS=false
SUPPORTS_OPUS_5=true
SUPPORTS_OPUS_4_8=true
SUPPORTS_OPUS_4_7=true
SUPPORTS_SDK_MODEL_CAPS=true
SUPPORTS_EFFORT_COMMAND=true
SUPPORTS_EFFORT_CLI_FLAG=true
SUPPORTS_XHIGH_EFFORT=false
SUPPORTS_SUBAGENT_MODEL_FIX=true
SUPPORTS_FULL_MODEL_IDS=false
SUPPORTS_BG_PARTIAL_RESULTS=false
SUPPORTS_OPUS_MEDIUM_EFFORT=false
SUPPORTS_EFFORT_CALLOUT=false
SUPPORTS_EFFORT_REDESIGN=false
SUPPORTS_STABLE_AUTH=true
SUPPORTS_AGENT_MEMORY_GC=false
SUPPORTS_HOOK_LAST_MESSAGE=false
SUPPORTS_CONTINUATION=false
SUPPORTS_AGENT_MODEL_OVERRIDE=false
PROVIDER_ENV_ARRAY=()
AVAILABLE_AGENTS="fake-api kimi kimi-research"
PLUGIN_DIR="$PROJECT_ROOT"
_BARE_OPT=""
export OCTOPUS_OPUS_MODEL=claude-opus-5
log() { :; }
octo_provider_identity_from_agent_type() { printf '%s\n' "${1%%-*}"; }
classify_task() { printf '%s\n' standard; }
get_role_for_context() { printf '%s\n' reviewer; }
match_routing_rule() { :; }
load_agent_checkpoint() { :; }
apply_persona() { printf 'PERSONA[%s]\n%s\n' "$1" "$2"; }
load_earned_skills() { :; }
build_provider_context() { :; }
enforce_context_budget() {
    if [[ "${FAKE_COMPRESS_PROMPT:-false}" == true ]]; then
        if [[ "${FAKE_PROMPT_MARKER:-false}" == true ]]; then
            printf 'D\n# Started: x\n%s\n' "$4"
        else
            printf 'DISPATCHED role=%s phase=%s\n' "$2" "$4"
        fi
    else
        printf '%s\n' "$1"
    fi
}
octo_prompt_byte_length() { LC_ALL=C printf '%s' "$1" | wc -c | tr -d '[:space:]'; }
octo_dispatch_command_model() {
    printf '%s\n' "$1" | awk -v fallback="$2" '
        { for (i = 1; i <= NF; i++) if ($i == "--model" && i < NF) { print $(i + 1); found=1; exit } }
        END { if (!found) print fallback }
    '
}
is_provider_available() { return 0; }
get_agent_command() {
    case "${FAKE_SCENARIO:-}" in
        claude-contract|exact-fable-contract)
            octo_real_get_agent_command "$@"
            return
            ;;
        agy-contract)
            printf '%s\n' "$fake_provider"
            return
            ;;
    esac
    local command_model="routed-model"
    if [[ "${1:-}" == *:* ]]; then
        command_model="${1#*:}"
    fi
    printf '%s\n' "${4:-missing}" > "$TEST_TMP_DIR/background-prompt-bytes"
    printf '%s\n' "$fake_provider --model $command_model"
}
validate_agent_command() {
    if [[ "$1" == "$fake_provider "* || "$1" == "$fake_provider" ]]; then
        return 0
    fi
    octo_real_validate_agent_command "$1"
}
get_agent_model() {
    [[ "${FAKE_SCENARIO:-}" == model-fail ]] && return 1
    if [[ "${1:-}" == *:* ]]; then
        printf '%s\n' "${1#*:}"
        return 0
    fi
    printf '%s\n' fixture-model
}
record_agent_call() { :; }
estimate_agent_call_cost() { printf '%s\n' 0.001; }
update_metrics() { :; }
bridge_register_task() { :; }
record_agent_start() { :; }
should_use_agent_teams() { return 1; }
update_agent_status() { :; }
write_agent_status() { :; }
check_provider_health() {
    printf '%s\n' "$1" >> "$TEST_TMP_DIR/background-health-calls"
    [[ "$1" != kimi ]] || printf '%s\n' "${2:-missing}" > "$TEST_TMP_DIR/background-kimi-health-model"
    if [[ "${FAKE_SCENARIO:-}" == kimi-dangling-default ]]; then
        if ! KIMI_CODE_HOME="$PROJECT_ROOT/tests/fixtures/kimi-dangling-default" \
            OCTOPUS_KIMI_MODEL="${2:-}" \
            kimi_configured_credential_method >/dev/null 2>&1; then
            printf '%s\n' 'fixture dangling Kimi default'
            return 1
        fi
    fi
    [[ "${FAKE_SCENARIO:-}" != health-fail ]]
}
build_provider_env() { PROVIDER_ENV_ARRAY=(); }
start_quota_watcher() { :; }
stop_quota_watcher() { :; }
append_provider_history() { :; }
record_outcome() { :; }
record_success() { :; }
record_failure() { :; }
record_run_pattern() { :; }
record_task_metric() { :; }
run_drift_check() { :; }
record_error() { :; }
save_agent_checkpoint() { :; }
record_result_hash() { :; }
start_heartbeat_monitor() { :; }
cleanup_heartbeat() { :; }
_octopus_agent_lifecycle_event() { :; }
octo_append_runtime_identity() { :; }
octo_spawn_contract_finish() {
    if [[ "${FAKE_CONTRACT_PERSISTENCE_FAIL:-false}" == true ]]; then
        return 74
    fi
    octo_run_contract_finish_background "$@"
}
octopus_capture_provider_output() {
    local prompt="$1" _timeout="$2" input="$3" output="$4" errors="$5"
    shift 5
    if [[ -n "${CAPTURED_PROVIDER_PROMPT_FILE:-}" ]]; then
        printf '%s' "$prompt" > "$CAPTURED_PROVIDER_PROMPT_FILE"
    fi
    printf '%s' "$prompt" > "$input"
    "$@" < "$input" > "$output" 2> "$errors"
}

run_external_fixture() {
    local scenario="$1" task="$2" agent_type="${3:-fake-api}"
    local role="${4:-reviewer}" phase="${5:-probe}" pid
    export FAKE_SCENARIO="$scenario"
    pid="$(spawn_agent "$agent_type" "External $scenario fixture" "$task" "$role" "$phase")" || return $?
    wait "$pid" 2>/dev/null || true
}

test_case "Tangle boundary refusal completes through the shared failure path"
saved_boundary_impl="$(declare -f octopus_tangle_apply_execution_boundary)"
saved_lifecycle_impl="$(declare -f _octopus_agent_lifecycle_event)"
saved_cleanup_impl="$(declare -f cleanup_heartbeat)"
lifecycle_file="$TEST_TMP_DIR/tangle-boundary-lifecycle"
cleanup_file="$TEST_TMP_DIR/tangle-boundary-cleanup"
octopus_tangle_apply_execution_boundary() { return 1; }
_octopus_agent_lifecycle_event() {
    printf '%s:%s:%s\n' "$1" "$8" "$9" >> "$lifecycle_file"
}
cleanup_heartbeat() {
    printf 'cleaned\n' > "$cleanup_file"
}
OCTOPUS_TANGLE_EXECUTION_BOUNDARY=true
OCTOPUS_TANGLE_WORKTREE="$TEST_TMP_DIR/tangle-boundary-worktree"
OCTOPUS_TANGLE_RESULTS_DIR="$RESULTS_DIR"
mkdir -p "$OCTOPUS_TANGLE_WORKTREE"
boundary_pid_file="$TEST_TMP_DIR/tangle-boundary.pid"
if spawn_agent fake-api "Boundary refusal fixture" boundary-refusal implementer tangle > "$boundary_pid_file"; then
    boundary_spawn_rc=0
else
    boundary_spawn_rc=$?
fi
boundary_pid="$(tail -n 1 "$boundary_pid_file" 2>/dev/null || true)"
if [[ "$boundary_spawn_rc" -eq 0 && "$boundary_pid" =~ ^[0-9]+$ ]]; then
    if wait "$boundary_pid"; then
        boundary_worker_rc=0
    else
        boundary_worker_rc=$?
    fi
else
    boundary_worker_rc=1
fi
eval "$saved_boundary_impl"
eval "$saved_lifecycle_impl"
eval "$saved_cleanup_impl"
unset OCTOPUS_TANGLE_EXECUTION_BOUNDARY OCTOPUS_TANGLE_WORKTREE OCTOPUS_TANGLE_RESULTS_DIR
boundary_done="$WORKSPACE_DIR/.octo/agents/boundary-refusal.done"
boundary_result="$RESULTS_DIR/fake-api-boundary-refusal.md"
if [[ "$boundary_spawn_rc" -eq 0 && "$boundary_worker_rc" -eq 125 ]] && \
   [[ "$(cat "$boundary_done" 2>/dev/null || true)" == 125 ]] && \
   grep -Fq "$(printf '\140\140\140\n\n## Status: FAILED (exit code: 125)')" "$boundary_result" && \
   grep -Fq '## Status: FAILED (exit code: 125)' "$boundary_result" && \
   grep -Fxq 'completed:125:failed' "$lifecycle_file" && \
   [[ "$(cat "$cleanup_file" 2>/dev/null || true)" == cleaned ]] && \
   [[ "$(run_contract_latest_transition spawn-boundary-refusal)" == failed ]]; then
    test_pass
else
    test_fail "boundary refusal was not finalized: spawn=$boundary_spawn_rc worker=$boundary_worker_rc done=$(cat "$boundary_done" 2>/dev/null || printf missing) transition=$(run_contract_latest_transition spawn-boundary-refusal 2>/dev/null || printf missing)"
fi

test_case "Agent Teams prompt persistence failure terminalizes the seat"
original_should_use_agent_teams="$(declare -f should_use_agent_teams)"
original_write_agent_result_prompt="$(declare -f write_agent_result_prompt)"
original_check_provider_health="$(declare -f check_provider_health)"
original_record_agent_start="$(declare -f record_agent_start)"
should_use_agent_teams() { return 0; }
write_agent_result_prompt() { return 1; }
check_provider_health() { return 0; }
record_agent_start() { printf '%s\n' call-native-prompt-fail; }
record_agent_failure() {
    printf '%s|%s|%s\n' "${4:-failed}" "$1" "${3:-}" >> "$TEST_TMP_DIR/native-usage-terminal"
}
saved_timeout="$TIMEOUT"
TIMEOUT=0
set +e
spawn_agent claude-sonnet "Native prompt persistence fixture" native-prompt-fail reviewer review \
    >"$TEST_TMP_DIR/native-prompt-fail.out" 2>"$TEST_TMP_DIR/native-prompt-fail.err"
native_prompt_rc=$?
set -e
TIMEOUT="$saved_timeout"
eval "$original_should_use_agent_teams"
eval "$original_write_agent_result_prompt"
eval "$original_check_provider_health"
eval "$original_record_agent_start"
unset -f record_agent_failure
native_prompt_transition="$(run_contract_latest_transition spawn-native-prompt-fail)"
native_prompt_reason="$(jq -r --arg seat spawn-native-prompt-fail \
    'select(.seat_id == $seat and .transition == "failed") | .reason' "$ledger" | tail -n 1)"
if [[ "$native_prompt_rc" -eq 74 ]] &&
   [[ "$native_prompt_transition" == failed ]] &&
   [[ "$native_prompt_reason" == "Failed to persist Agent Teams dispatched prompt" ]] &&
   [[ "$(wc -l < "$TEST_TMP_DIR/native-usage-terminal" | tr -d ' ')" == 1 ]] &&
   grep -Fxq 'failed|call-native-prompt-fail|Failed to persist Agent Teams dispatched prompt' \
       "$TEST_TMP_DIR/native-usage-terminal"; then
    test_pass
else
    test_fail "Agent Teams prompt-write failure remained nonterminal (rc=$native_prompt_rc transition=${native_prompt_transition:-missing} reason=${native_prompt_reason:-missing})"
fi

test_case "legacy prompt persistence failure terminalizes the seat"
original_write_agent_result_prompt="$(declare -f write_agent_result_prompt)"
write_agent_result_prompt() { return 1; }
export FAKE_SCENARIO=success
set +e
legacy_prompt_pid="$(spawn_agent fake-api "Legacy prompt persistence fixture" legacy-prompt-fail reviewer review)"
legacy_prompt_spawn_rc=$?
set -e
if [[ "$legacy_prompt_spawn_rc" -eq 0 && -n "$legacy_prompt_pid" ]]; then
    wait "$legacy_prompt_pid" 2>/dev/null || true
fi
eval "$original_write_agent_result_prompt"
unset FAKE_SCENARIO
legacy_prompt_transition="$(run_contract_latest_transition spawn-legacy-prompt-fail)"
legacy_prompt_reason="$(jq -r --arg seat spawn-legacy-prompt-fail \
    'select(.seat_id == $seat and .transition == "failed") | .reason' "$ledger" | tail -n 1)"
if [[ "$legacy_prompt_spawn_rc" -eq 0 ]] &&
   [[ "$legacy_prompt_transition" == failed ]] &&
   [[ "$legacy_prompt_reason" == "Failed to persist background dispatched prompt" ]]; then
    test_pass
else
    test_fail "legacy prompt-write failure remained nonterminal (spawn_rc=$legacy_prompt_spawn_rc transition=${legacy_prompt_transition:-missing} reason=${legacy_prompt_reason:-missing})"
fi

claude_stub_dir="$TEST_TMP_DIR/claude-contract-bin"
claude_argv_capture="$TEST_TMP_DIR/spawn-claude-argv"
mkdir -p "$claude_stub_dir"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    ': > "$CLAUDE_ARGV_CAPTURE"' \
    'for arg in "$@"; do printf "%s\\n" "$arg" >> "$CLAUDE_ARGV_CAPTURE"; done' \
    'cat >/dev/null' \
    'printf "%s\\n" "Substantive Claude contract result."' > "$claude_stub_dir/claude"
chmod +x "$claude_stub_dir/claude"
export CLAUDE_ARGV_CAPTURE="$claude_argv_capture"

test_case "real supervised spawn validates and executes the Claude contract"
export FAKE_SCENARIO=claude-contract
old_path="$PATH"
PATH="$claude_stub_dir:$PATH"
set +e
claude_pid="$(spawn_agent claude-opus "Claude command contract fixture" external-claude reviewer discover)"
claude_spawn_rc=$?
set -e
PATH="$old_path"
if [[ "$claude_spawn_rc" -eq 0 && -n "$claude_pid" ]]; then
    wait "$claude_pid" 2>/dev/null || true
fi
if [[ "$claude_spawn_rc" -eq 0 ]] &&
   [[ -f "$claude_argv_capture" ]] &&
   [[ "$(grep -cx -- '--print' "$claude_argv_capture")" -eq 1 ]] &&
   [[ "$(grep -cx -- '--model' "$claude_argv_capture")" -eq 1 ]] &&
   [[ "$(grep -cx -- '--effort' "$claude_argv_capture")" -eq 1 ]] &&
   ! grep -qx -- '--fast' "$claude_argv_capture"; then
    test_pass
else
    test_fail "spawn_agent rejected or mis-executed the generated Claude command"
fi
unset FAKE_SCENARIO

test_case "background exact AGY model remains one environment value"
export AGY_MODEL_CAPTURE="$TEST_TMP_DIR/spawn-agy-model"
if run_external_fixture agy-contract external-agy \
    'agy:Gemini 3.5 Flash (High)' reviewer review &&
   [[ "$(cat "$AGY_MODEL_CAPTURE" 2>/dev/null || true)" == 'Gemini 3.5 Flash (High)' ]]; then
    test_pass
else
    test_fail "background AGY model was split or omitted"
fi
unset FAKE_SCENARIO AGY_MODEL_CAPTURE

source "$PROJECT_ROOT/scripts/lib/kimi.sh"
kimi_config_bin="$TEST_TMP_DIR/kimi-config-bin"
mkdir -p "$kimi_config_bin"
cat > "$kimi_config_bin/kimi" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    __plugin_run_node) shift; exec "${KIMI_TEST_NODE:?}" "$@" ;;
    doctor|provider) exec "${KIMI_TEST_NODE:?}" "${KIMI_TEST_DRIVER:?}" "$@" ;;
    *) exit 1 ;;
esac
EOF
chmod 755 "$kimi_config_bin/kimi"
export KIMI_TEST_NODE="$(command -v node)"
export KIMI_TEST_DRIVER="$PROJECT_ROOT/tests/fixtures/kimi-code-cli-mock.mjs"
PATH="$kimi_config_bin:$PATH"

test_case "real supervised success follows the complete contract"
run_external_fixture success external-success
external_success_model="$(jq -r '.seats[] | select(.seat_id == "spawn-external-success") | .resolved.model' \
    "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/seats.json")"
external_success_transitions="$(transitions_for spawn-external-success)"
external_success_eligible=false
run_contract_contribution_eligible spawn-external-success && external_success_eligible=true
external_success_reason="$(jq -r --arg seat spawn-external-success 'select(.seat_id == $seat) | .reason' "$ledger" | tail -n 1)"
if [[ "$external_success_transitions" == "planned,starting,authenticated,running,output_received,validated,contributed" ]] && \
   [[ "$external_success_eligible" == true ]] &&
   [[ "$external_success_model" == routed-model ]]; then
    test_pass
else
    test_fail "supervised success contract mismatch (transitions=${external_success_transitions:-missing}, eligible=$external_success_eligible, model=${external_success_model:-missing}, reason=${external_success_reason:-none})"
fi

test_case "result prompt is exactly the enhanced and budgeted provider stdin"
export FAKE_COMPRESS_PROMPT=true
export FAKE_PROMPT_MARKER=true
export CAPTURED_PROVIDER_PROMPT_FILE="$TEST_TMP_DIR/dispatched-provider-prompt"
run_external_fixture success exact-prompt fake-api reviewer review
unset FAKE_COMPRESS_PROMPT FAKE_PROMPT_MARKER CAPTURED_PROVIDER_PROMPT_FILE
prompt_result="$RESULTS_DIR/fake-api-exact-prompt.md"
prompt_frame="$(awk '
    /^# Prompt-Format: octopus-length-v1$/ {
        format_line=NR
        getline
        print format_line ":" $3
        exit
    }
' "$prompt_result")"
prompt_line="${prompt_frame%%:*}"
prompt_bytes="${prompt_frame#*:}"
recorded_prompt="$(tail -n "+$((prompt_line + 2))" "$prompt_result" | dd bs=1 count="$prompt_bytes" 2>/dev/null)"
dispatched_prompt="$(cat "$TEST_TMP_DIR/dispatched-provider-prompt")"
expected_original=$'PERSONA[reviewer]\nExternal success fixture'
expected_dispatched=$'D\n# Started: x\nreview'
prompt_equal=false
expected_equal=false
byte_count_equal=false
metadata_equal=false
original_absent=false
[[ "$recorded_prompt" == "$dispatched_prompt" ]] && prompt_equal=true
[[ "$recorded_prompt" == "$expected_dispatched" ]] && expected_equal=true
[[ "$(LC_ALL=C printf '%s' "$recorded_prompt" | wc -c | tr -d '[:space:]')" == "$prompt_bytes" ]] && byte_count_equal=true
grep -Fqx "# Prompt metadata: original_chars=${#expected_original} final_chars=${#recorded_prompt} compression=applied" "$prompt_result" && metadata_equal=true
! grep -Fq 'External success fixture' "$prompt_result" && original_absent=true
if [[ "$prompt_equal" == true && "$expected_equal" == true && "$byte_count_equal" == true &&
      "$metadata_equal" == true && "$original_absent" == true ]]; then
    test_pass
else
    test_fail "prompt frame mismatch (provider=$prompt_equal expected=$expected_equal bytes=$byte_count_equal metadata=$metadata_equal redaction=$original_absent)"
fi

test_case "exact background seat records canonical provider and literal model"
exact_background_model="thinkingmachines/inkling-small"
run_external_fixture success external-exact "command-code:${exact_background_model}" \
    implementation-logic-reviewer review
if jq -e --arg model "$exact_background_model" '
    .seats[] |
    select(.seat_id == "spawn-external-exact") |
    .requested.provider == "commandcode" and
    .requested.model == $model and
    .resolved.provider == "commandcode" and
    .resolved.model == $model and
    .execution.phase == "review" and
    .execution.role == "implementation-logic-reviewer"
' "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/seats.json" >/dev/null; then
    test_pass
else
    test_fail "exact background lifecycle did not split canonical provider from literal model"
fi

test_case "exact background Fable SDK seat executes with no retry and retains lifecycle identity"
sdk_stub_dir="$TEST_TMP_DIR/fable-sdk-bin"
sdk_capture="$TEST_TMP_DIR/spawn-fable-sdk-capture"
sdk_health_capture="$TEST_TMP_DIR/spawn-fable-sdk-health-capture"
mkdir -p "$sdk_stub_dir"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "no_retry=${OCTOPUS_FABLE5_NO_RETRY:-unset}" > "$SDK_CAPTURE"' \
    'printf "%s\n" "$@" >> "$SDK_CAPTURE"' \
    'cat >/dev/null' \
    'printf "%s\n" "Substantive exact Fable background result."' > "$sdk_stub_dir/claude-agent"
chmod 755 "$sdk_stub_dir/claude-agent"
export SDK_CAPTURE="$sdk_capture" CLAUDE_SDK_API_KEY=fixture-key
old_path="$PATH"
PATH="$sdk_stub_dir:$PATH"
eval "$(declare -f check_provider_health | sed '1s/check_provider_health/octo_real_check_provider_health/')"
check_provider_health() {
    printf '%s\n' "$1" >> "$sdk_health_capture"
    octo_real_check_provider_health "$@"
}
exact_fable_ran=false
if run_external_fixture exact-fable-contract external-exact-fable \
    'claude-sdk:claude-fable-5' implementation-logic-reviewer review; then
    exact_fable_ran=true
fi
eval "$(declare -f octo_real_check_provider_health | sed '1s/octo_real_check_provider_health/check_provider_health/')"
PATH="$old_path"
unset CLAUDE_SDK_API_KEY SDK_CAPTURE
if [[ "$exact_fable_ran" == true ]] && \
   grep -Fxq 'claude-sdk' "$sdk_health_capture" && \
   grep -Fxq 'no_retry=1' "$sdk_capture" && \
   grep -Fxq 'claude-fable-5' "$sdk_capture" && \
   jq -e '
       .seats[] |
       select(.seat_id == "spawn-external-exact-fable") |
       .requested.provider == "claude-sdk" and
       .requested.model == "claude-fable-5" and
       .resolved.provider == "claude-sdk" and
       .resolved.model == "claude-fable-5" and
       .transition == "contributed"
   ' "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/seats.json" >/dev/null; then
    test_pass
else
    test_fail "background exact Fable execution retried or lost its lifecycle identity"
fi
test_case "real supervised Kimi dispatch runs registered health and adds trust boundaries"
: > "$TEST_TMP_DIR/background-health-calls"
export FAKE_SCENARIO=success
kimi_pid="$(spawn_agent kimi-research "External Kimi fixture" external-kimi reviewer probe)"
wait "$kimi_pid" 2>/dev/null || true
kimi_result="$RESULTS_DIR/kimi-research-external-kimi.md"
if [[ "$(grep -cx 'kimi' "$TEST_TMP_DIR/background-health-calls")" -eq 1 ]] && \
   [[ "$(cat "$TEST_TMP_DIR/background-kimi-health-model")" == fixture-model ]] && \
   grep -q '<!-- trust=untrusted provider=kimi-research -->' "$kimi_result" && \
   grep -q '<!-- BEGIN-UNTRUSTED:provider=kimi-research:' "$kimi_result" && \
   grep -q '<!-- END-UNTRUSTED:provider=kimi-research:' "$kimi_result"; then
    test_pass
else
    test_fail "Kimi async health or trust-boundary contract was not enforced"
fi

test_case "real supervised Kimi health failure prevents provider dispatch"
: > "$TEST_TMP_DIR/background-health-calls"
export FAKE_SCENARIO=health-fail
set +e
spawn_agent kimi "Kimi health failure" external-kimi-health reviewer probe >/dev/null
kimi_health_rc=$?
set -e
if [[ "$kimi_health_rc" -ne 0 ]] && \
   [[ "$(grep -cx 'kimi' "$TEST_TMP_DIR/background-health-calls")" -eq 1 ]] && \
   [[ ! -e "$RESULTS_DIR/kimi-external-kimi-health.md" ]]; then
    test_pass
else
    test_fail "Kimi async health failure did not fail closed before dispatch"
fi
unset FAKE_SCENARIO

test_case "background Kimi health rejects a dangling default before dispatch"
: > "$TEST_TMP_DIR/background-health-calls"
export FAKE_SCENARIO=kimi-dangling-default
set +e
spawn_agent kimi "Kimi dangling default" external-kimi-dangling reviewer probe >/dev/null
kimi_dangling_rc=$?
set -e
if [[ "$kimi_dangling_rc" -ne 0 ]] && \
   [[ "$(grep -cx 'kimi' "$TEST_TMP_DIR/background-health-calls")" -eq 1 ]] && \
   [[ ! -e "$RESULTS_DIR/kimi-external-kimi-dangling.md" ]]; then
    test_pass
else
    test_fail "Kimi dangling default reached background provider dispatch"
fi
unset FAKE_SCENARIO

test_case "background model-resolution failure terminalizes before provider execution"
set +e
run_external_fixture model-fail external-model-fail
model_fail_rc=$?
set -e
if [[ "$model_fail_rc" -ne 0 ]] &&
   [[ "$(transitions_for spawn-external-model-fail)" == "planned,failed" ]] &&
   [[ ! -e "$RESULTS_DIR/fake-api-external-model-fail.md" ]]; then
    test_pass
else
    test_fail "model resolution failure remained non-terminal or produced an artifact"
fi

test_case "real supervised provider exit terminalizes failed"
run_external_fixture exit external-exit
if [[ "$(run_contract_latest_transition spawn-external-exit)" == failed ]] && \
   ! run_contract_contribution_eligible spawn-external-exit; then
    test_pass
else
    test_fail "supervised provider exit did not fail the contract"
fi

test_case "real supervised timeout terminalizes without contribution"
run_external_fixture timeout external-timeout
if [[ "$(run_contract_latest_transition spawn-external-timeout)" == timeout ]] && \
   ! run_contract_contribution_eligible spawn-external-timeout; then
    test_pass
else
    test_fail "supervised timeout did not terminate truthfully"
fi

test_case "real supervised success fails closed when contract persistence fails"
export FAKE_CONTRACT_PERSISTENCE_FAIL=true
run_external_fixture success external-persistence-fail
unset FAKE_CONTRACT_PERSISTENCE_FAIL
persistence_result="$RESULTS_DIR/fake-api-external-persistence-fail.md"
persistence_done="$WORKSPACE_DIR/.octo/agents/external-persistence-fail.done"
if [[ "$(run_contract_latest_transition spawn-external-persistence-fail)" == running ]] && \
   [[ "$(<"$persistence_done")" == 74 ]] && \
   grep -Fq '## Status: FAILED (Execution contract persistence failed)' "$persistence_result" && \
   ! probe_result_file_is_usable "$persistence_result"; then
    test_pass
else
    test_fail "persistence failure retained a success projection or synthesis eligibility"
fi

test_summary
