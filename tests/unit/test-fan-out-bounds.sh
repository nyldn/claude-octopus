#!/usr/bin/env bash
# Unit coverage for bounded parallel execution and structured seat outcomes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Bounded fan-out outcomes"

source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT/scripts/lib/parallel.sh"

export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
export OCTOPUS_PARALLEL_REPORT_FILE="$TEST_TMP_DIR/parallel-report.json"
export TMPDIR="$TEST_TMP_DIR/parallel-tmp"
mkdir -p "$WORKSPACE_DIR/state" "$TMPDIR"

AVAILABLE_AGENTS="codex agy openrouter qwen perplexity copilot ollama"
MAX_PARALLEL=2
SUPPORTS_DISABLE_CRON_ENV=false
TASKS_FILE="$TEST_TMP_DIR/tasks.json"

ACTIVE_FILE="$TEST_TMP_DIR/active"
MAX_ACTIVE_FILE="$TEST_TMP_DIR/max-active"
COUNTER_LOCK="$TEST_TMP_DIR/counter.lock"
PID_FILE="$TEST_TMP_DIR/pids"
CIRCUIT_CALLS_FILE="$TEST_TMP_DIR/circuit-calls"
QUOTA_CALLS_FILE="$TEST_TMP_DIR/quota-calls"
CIRCUIT_PROVIDER=openrouter
QUOTA_PROVIDER=qwen
AGGREGATE_RC=0

log() { :; }
render_agent_summary() { :; }
aggregate_results() { return "$AGGREGATE_RC"; }

is_provider_available() {
    printf '%s\n' "$1" >> "$CIRCUIT_CALLS_FILE"
    [[ "$1" != "$CIRCUIT_PROVIDER" ]]
}

octo_quota_is_dead() {
    printf '%s\n' "$1" >> "$QUOTA_CALLS_FILE"
    [[ "$1" == "$QUOTA_PROVIDER" ]]
}

update_active_count() {
    local delta="$1" active max_active
    while ! mkdir "$COUNTER_LOCK" 2>/dev/null; do sleep 0.01; done
    active=$(<"$ACTIVE_FILE")
    active=$((active + delta))
    printf '%s\n' "$active" > "$ACTIVE_FILE"
    max_active=$(<"$MAX_ACTIVE_FILE")
    if (( active > max_active )); then
        printf '%s\n' "$active" > "$MAX_ACTIVE_FILE"
    fi
    rmdir "$COUNTER_LOCK"
}

spawn_agent_capture_pid() {
    local agent="$1" task_id="$3" delay=0.08 exit_code=0 handoff wrapper_pid child_pid
    [[ "$agent" == "perplexity" ]] && return 23
    [[ "$agent" == "codex" ]] && delay=0.30
    [[ "$agent" == "copilot" ]] && exit_code=7

    update_active_count 1
    (
        (
            sleep "$delay"
            update_active_count -1
            mkdir -p "$WORKSPACE_DIR/.octo/agents"
            printf '%s\n' "$exit_code" > "$WORKSPACE_DIR/.octo/agents/${task_id}.done.tmp"
            mv "$WORKSPACE_DIR/.octo/agents/${task_id}.done.tmp" \
                "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
            exit "$exit_code"
        ) &
        printf '%s\n' "$!" > "$TEST_TMP_DIR/handoff-${task_id}"
    ) &
    wrapper_pid=$!
    wait "$wrapper_pid"
    child_pid=$(<"$TEST_TMP_DIR/handoff-${task_id}")
    rm -f "$TEST_TMP_DIR/handoff-${task_id}"
    printf '%s\t%s\n' "$task_id" "$child_pid" >> "$PID_FILE"
    printf '%s\n' "$child_pid"
}

reset_run_state() {
    printf '0\n' > "$ACTIVE_FILE"
    printf '0\n' > "$MAX_ACTIVE_FILE"
    : > "$PID_FILE"
    : > "$CIRCUIT_CALLS_FILE"
    : > "$QUOTA_CALLS_FILE"
    rm -rf "$WORKSPACE_DIR/.octo"
    rm -f "$OCTOPUS_PARALLEL_REPORT_FILE"
}

run_parallel() {
    local tasks_json="$1"
    printf '%s\n' "$tasks_json" > "$TASKS_FILE"
    if parallel_execute "$TASKS_FILE"; then
        PARALLEL_RC=0
    else
        PARALLEL_RC=$?
    fi
}

reset_run_state
run_parallel '{"tasks":[
  {"id":"slow","agent":"codex","prompt":"slow"},
  {"id":"fast","agent":"agy","prompt":"fast"},
  {"id":"unknown","agent":"missing","prompt":"unknown"},
  {"id":"circuit","agent":"openrouter","prompt":"circuit"},
  {"id":"quota","agent":"qwen","prompt":"quota"},
  {"id":"spawn","agent":"perplexity","prompt":"spawn"},
  {"id":"child","agent":"copilot","prompt":"child"},
  {"id":"last","agent":"ollama","prompt":"last"},
  {"agent":"agy","prompt":"missing id"},
  {"id":"missing-agent","prompt":"missing agent"},
  {"id":"missing-prompt","agent":"agy"},
  {"id":"../escape","agent":"agy","prompt":"unsafe id"},
  "not-an-object"
]}'

test_case "mixed execution emits one ordered record per configured seat"
expected_ids='["slow","fast","unknown","circuit","quota","spawn","child","last",null,"missing-agent","missing-prompt","../escape",null]'
if [[ -f "$OCTOPUS_PARALLEL_REPORT_FILE" ]] &&
   jq -e --argjson ids "$expected_ids" '
       .schema_version == 1 and
       ([.results[].id] == $ids) and
       (.results | length == 13)
   ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null; then
    test_pass
else
    test_fail "parallel report is missing seats or does not preserve configured order"
fi

test_case "skipped and failed seats include explicit terminal reasons"
if [[ -f "$OCTOPUS_PARALLEL_REPORT_FILE" ]] && jq -e '
    (.results[] | select(.id == "unknown")) == {sequence:2,id:"unknown",agent:"missing",status:"skipped",reason:"unknown-agent",exit_code:null} and
    (.results[] | select(.id == "circuit")) == {sequence:3,id:"circuit",agent:"openrouter",status:"skipped",reason:"circuit-open",exit_code:null} and
    (.results[] | select(.id == "quota")) == {sequence:4,id:"quota",agent:"qwen",status:"skipped",reason:"quota-dead",exit_code:null} and
    (.results[] | select(.id == "spawn")) == {sequence:5,id:"spawn",agent:"perplexity",status:"failed",reason:"failed-spawn",exit_code:23} and
    (.results[] | select(.id == "child")) == {sequence:6,id:"child",agent:"copilot",status:"failed",reason:"child-exit",exit_code:7} and
    .results[8] == {sequence:8,id:null,agent:"agy",status:"skipped",reason:"missing-id",exit_code:null} and
    .results[9] == {sequence:9,id:"missing-agent",agent:null,status:"skipped",reason:"missing-agent",exit_code:null} and
    .results[10] == {sequence:10,id:"missing-prompt",agent:"agy",status:"skipped",reason:"missing-prompt",exit_code:null} and
    .results[11] == {sequence:11,id:"../escape",agent:"agy",status:"skipped",reason:"invalid-id",exit_code:null} and
    .results[12] == {sequence:12,id:null,agent:null,status:"skipped",reason:"malformed-task",exit_code:null}
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null; then
    test_pass
else
    test_fail "terminal reasons were absent or ambiguous"
fi

test_case "active children reach but never exceed MAX_PARALLEL"
max_active=$(<"$MAX_ACTIVE_FILE")
if (( max_active == MAX_PARALLEL )); then
    test_pass
else
    test_fail "expected peak concurrency $MAX_PARALLEL, observed $max_active"
fi

test_case "spawn and health hooks are exercised for the configured seats"
spawned_ids=$(cut -f1 "$PID_FILE" | jq -Rsc 'split("\n") | map(select(length > 0))')
if [[ "$spawned_ids" == '["slow","fast","child","last"]' ]] &&
   grep -qx 'openrouter' "$CIRCUIT_CALLS_FILE" &&
   grep -qx 'qwen' "$QUOTA_CALLS_FILE"; then
    test_pass
else
    test_fail "report records were not backed by the expected spawn and health checks"
fi

test_case "parallel execution reaps every spawned child"
alive=""
while IFS=$'\t' read -r task_id child_pid; do
    [[ -z "$child_pid" ]] && continue
    if kill -0 "$child_pid" 2>/dev/null; then
        alive+=" $task_id:$child_pid"
    fi
done < "$PID_FILE"
if [[ -z "$alive" ]]; then
    test_pass
else
    test_fail "spawned children remain observable after return:$alive"
fi

test_case "parallel execution consumes production completion markers"
remaining_markers=$(find "$WORKSPACE_DIR/.octo/agents" -type f -name '*.done' 2>/dev/null | wc -l | tr -d '[:space:]')
if [[ "$remaining_markers" -eq 0 ]]; then
    test_pass
else
    test_fail "$remaining_markers completion markers were left stale"
fi

test_case "completed seats use the same exact terminal record schema"
if jq -e '
    .results[0] == {sequence:0,id:"slow",agent:"codex",status:"completed",reason:"completed",exit_code:0} and
    .results[1] == {sequence:1,id:"fast",agent:"agy",status:"completed",reason:"completed",exit_code:0} and
    .results[7] == {sequence:7,id:"last",agent:"ollama",status:"completed",reason:"completed",exit_code:0}
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null; then
    test_pass
else
    test_fail "completed seat records do not match the terminal schema"
fi

test_case "mixed terminal outcomes produce degraded aggregate status"
if [[ "$PARALLEL_RC" -eq 0 ]] && jq -e '
    .status == "degraded" and
    .counts == {total:13,completed:3,skipped:8,failed:2} and
    .aggregation_exit_code == 0
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null; then
    test_pass
else
    test_fail "mixed run did not report degraded with the expected counts"
fi

reset_run_state
MAX_PARALLEL=1
run_parallel '{"tasks":[
  {"id":"one","agent":"codex","prompt":"one"},
  {"id":"two","agent":"agy","prompt":"two"},
  {"id":"three","agent":"ollama","prompt":"three"}
]}'

test_case "all successful seats produce complete aggregate status"
if [[ "$PARALLEL_RC" -eq 0 ]] && jq -e '
    .status == "complete" and
    .counts == {total:3,completed:3,skipped:0,failed:0}
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null; then
    test_pass
else
    test_fail "successful run did not report complete"
fi

test_case "MAX_PARALLEL=1 serializes the queue"
if [[ "$(<"$MAX_ACTIVE_FILE")" -eq 1 ]]; then
    test_pass
else
    test_fail "serial queue exceeded one active child"
fi

reset_run_state
MAX_PARALLEL=2
run_parallel '{"tasks":[
  {"id":"unknown-only","agent":"missing","prompt":"unknown"},
  {"id":"spawn-only","agent":"perplexity","prompt":"spawn"}
]}'

test_case "a run with no completed seat produces failed aggregate status"
if [[ "$PARALLEL_RC" -ne 0 ]] && jq -e '
    .status == "failed" and
    .counts == {total:2,completed:0,skipped:1,failed:1}
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null; then
    test_pass
else
    test_fail "run with no completed seat did not fail explicitly"
fi

reset_run_state
run_parallel '{"tasks":[
  {"id":"circuit-only","agent":"openrouter","prompt":"circuit"},
  {"id":"quota-only","agent":"qwen","prompt":"quota"}
]}'

test_case "an all-skipped run is failed rather than degraded"
if [[ "$PARALLEL_RC" -ne 0 ]] && jq -e '
    .status == "failed" and
    .counts == {total:2,completed:0,skipped:2,failed:0}
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null; then
    test_pass
else
    test_fail "all-skipped run did not fail explicitly"
fi

reset_run_state
run_parallel '{"tasks":[]}'

test_case "an empty task list is a complete no-op"
if [[ "$PARALLEL_RC" -eq 0 ]] && jq -e '
    .status == "complete" and
    .counts == {total:0,completed:0,skipped:0,failed:0} and
    .results == []
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null; then
    test_pass
else
    test_fail "empty task list did not report a complete no-op"
fi

reset_run_state
MAX_PARALLEL=1
run_parallel '{"tasks":[
  {"id":"duplicate","agent":"agy","prompt":"first"},
  {"id":"duplicate","agent":"ollama","prompt":"second"}
]}'

test_case "duplicate task IDs are rejected before a second spawn"
if [[ "$PARALLEL_RC" -eq 0 ]] && jq -e '
    .status == "degraded" and
    .counts == {total:2,completed:1,skipped:1,failed:0} and
    .results[0].status == "completed" and
    .results[1] == {sequence:1,id:"duplicate",agent:"ollama",status:"skipped",reason:"duplicate-id",exit_code:null}
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null 2>&1 &&
   [[ "$(cut -f1 "$PID_FILE" | grep -c '^duplicate$' || true)" -eq 1 ]]; then
    test_pass
else
    test_fail "duplicate IDs spawned more than once or shared a completion marker"
fi

test_case "parallel temp resources are cleaned before normal return"
if find "$TMPDIR" -maxdepth 1 \( -name 'octo-parallel-outcomes.*' -o -name 'octo-parallel-spawn.*' \) \
    -print | grep -c . >/dev/null 2>&1; then
    test_fail "parallel execution left normal-exit temp resources"
else
    test_pass
fi

test_case "fallback group signalling requires the provider PID to own its process group"
if awk '
    /pgid=.*ps -o pgid=/ { saw_lookup = 1 }
    /\[\[ "\$pgid" == "\$pid" \]\] && kill -STOP -- "-\$pid"/ { saw_guard = 1 }
    /kill -KILL -- "-\$pid"/ { saw_group_kill = 1 }
    END { exit !(saw_lookup && saw_guard && saw_group_kill) }
' "$PROJECT_ROOT/scripts/lib/parallel.sh"; then
    test_pass
else
    test_fail "negative-PID signals are not guarded by a matching process-group lookup"
fi

test_case "TERM cleanup preserves the caller trap and removes parallel temp resources"
interrupt_runner="$TEST_TMP_DIR/parallel-interrupt-runner.sh"
interrupt_tasks="$TEST_TMP_DIR/interrupt-tasks.json"
interrupt_marker="$TEST_TMP_DIR/previous-term-handler"
interrupt_child="$TEST_TMP_DIR/interrupt-child"
interrupt_ready="$TEST_TMP_DIR/interrupt-ready"
cat > "$interrupt_tasks" <<'JSON'
{"tasks":[{"id":"interrupt","agent":"agy","prompt":"wait"}]}
JSON
cat > "$interrupt_runner" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT/scripts/lib/parallel.sh"
log() { :; }
render_agent_summary() { :; }
aggregate_results() { :; }
is_provider_available() { return 0; }
octo_quota_is_dead() { return 1; }
spawn_agent_capture_pid() {
    (
        sleep 30 &
        printf '%s\n' "$!" > "$INTERRUPT_CHILD"
        wait
    ) &
    wrapper_pid=$!
    if [[ "${OCTOPUS_SPAWN_PID_HANDOFF_FD:-}" == "9" ]]; then
        printf 'wrapper:%s\n' "$wrapper_pid" >&9
    fi
    printf ready > "$INTERRUPT_READY"
    while :; do sleep 0.05; done
}
trap 'printf previous > "$INTERRUPT_MARKER"; exit 143' TERM
AVAILABLE_AGENTS=agy
MAX_PARALLEL=1
SUPPORTS_DISABLE_CRON_ENV=false
parallel_execute "$INTERRUPT_TASKS"
RUNNER
chmod +x "$interrupt_runner"
PROJECT_ROOT="$PROJECT_ROOT" INTERRUPT_MARKER="$interrupt_marker" \
INTERRUPT_CHILD="$interrupt_child" INTERRUPT_READY="$interrupt_ready" \
INTERRUPT_TASKS="$interrupt_tasks" \
WORKSPACE_DIR="$WORKSPACE_DIR" OCTOPUS_PARALLEL_REPORT_FILE="$OCTOPUS_PARALLEL_REPORT_FILE" \
TMPDIR="$TMPDIR" "$interrupt_runner" &
interrupt_pid=$!
for _ in $(seq 1 100); do
    [[ -f "$interrupt_ready" && -f "$interrupt_child" ]] && break
    sleep 0.05
done
kill -TERM "$interrupt_pid" 2>/dev/null || true
if wait "$interrupt_pid"; then interrupt_rc=0; else interrupt_rc=$?; fi
interrupt_child_dead=false
if [[ -f "$interrupt_child" ]]; then
    child_pid="$(<"$interrupt_child")"
    for _ in $(seq 1 100); do
        kill -0 "$child_pid" 2>/dev/null || break
        sleep 0.05
    done
    if ! kill -0 "$child_pid" 2>/dev/null; then
        interrupt_child_dead=true
    fi
fi
leftovers="$(find "$TMPDIR" -maxdepth 1 \( -name 'octo-parallel-outcomes.*' -o -name 'octo-parallel-spawn.*' -o -name 'octo-parallel-pid.*' \) -print)"
if [[ "$interrupt_rc" -eq 143 && -f "$interrupt_marker" && \
      "$interrupt_child_dead" == "true" && -z "$leftovers" ]]; then
    test_pass
else
    test_fail "TERM cleanup rc=$interrupt_rc prior_handler=$([[ -f "$interrupt_marker" ]] && echo yes || echo no) child_dead=$interrupt_child_dead leftovers=$leftovers"
fi

test_case "TERM before the first tracked PID is set-u safe"
early_runner="$TEST_TMP_DIR/parallel-early-interrupt-runner.sh"
early_marker="$TEST_TMP_DIR/early-previous-term-handler"
early_ready="$TEST_TMP_DIR/early-spawn-entered"
cat > "$early_runner" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT/scripts/lib/parallel.sh"
log() { :; }
render_agent_summary() { :; }
aggregate_results() { :; }
is_provider_available() { return 0; }
octo_quota_is_dead() { return 1; }
spawn_agent_capture_pid() {
    printf ready > "$EARLY_READY"
    while :; do sleep 0.05; done
}
trap 'printf previous > "$EARLY_MARKER"; exit 143' TERM
AVAILABLE_AGENTS=agy
MAX_PARALLEL=1
SUPPORTS_DISABLE_CRON_ENV=false
parallel_execute "$INTERRUPT_TASKS"
RUNNER
chmod +x "$early_runner"
PROJECT_ROOT="$PROJECT_ROOT" EARLY_MARKER="$early_marker" EARLY_READY="$early_ready" \
INTERRUPT_TASKS="$interrupt_tasks" WORKSPACE_DIR="$WORKSPACE_DIR" \
OCTOPUS_PARALLEL_REPORT_FILE="$OCTOPUS_PARALLEL_REPORT_FILE" TMPDIR="$TMPDIR" \
"$early_runner" &
early_pid=$!
for _ in $(seq 1 100); do
    [[ -f "$early_ready" ]] && break
    sleep 0.05
done
kill -TERM "$early_pid" 2>/dev/null || true
if wait "$early_pid"; then early_rc=0; else early_rc=$?; fi
early_leftovers="$(find "$TMPDIR" -maxdepth 1 \( -name 'octo-parallel-outcomes.*' -o -name 'octo-parallel-spawn.*' -o -name 'octo-parallel-pid.*' \) -print)"
if [[ "$early_rc" -eq 143 && -f "$early_marker" && -z "$early_leftovers" ]]; then
    test_pass
else
    test_fail "early TERM cleanup rc=$early_rc prior_handler=$([[ -f "$early_marker" ]] && echo yes || echo no) leftovers=$early_leftovers"
fi

test_case "TERM harvests a capture-window provider PID and kills its process group"
capture_runner="$TEST_TMP_DIR/parallel-capture-interrupt-runner.sh"
capture_marker="$TEST_TMP_DIR/capture-previous-term-handler"
capture_ready="$TEST_TMP_DIR/capture-provider-ready"
capture_provider_file="$TEST_TMP_DIR/capture-provider-pid"
capture_child_file="$TEST_TMP_DIR/capture-provider-child-pid"
capture_path_file="$TEST_TMP_DIR/capture-temp-path"
cat > "$capture_runner" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT/scripts/lib/parallel.sh"
log() { :; }
render_agent_summary() { :; }
aggregate_results() { :; }
is_provider_available() { return 0; }
octo_quota_is_dead() { return 1; }
spawn_agent_capture_pid() {
    capture_file=$(mktemp "${TMPDIR:-/tmp}/octo-spawn-pid.XXXXXX")
    printf '%s\n' "$capture_file" > "$CAPTURE_PATH_FILE"
    set -m
    (
        sleep 30 &
        printf '%s\n' "$!" > "$CAPTURE_CHILD_FILE"
        wait
    ) &
    provider_pid=$!
    set +m
    printf '%s\n' "$provider_pid" > "$CAPTURE_PROVIDER_FILE"
    printf '%s\n' "$provider_pid" > "$capture_file"
    printf 'capture-file:%s\n' "$capture_file" >&9
    printf ready > "$CAPTURE_READY"
    while :; do sleep 0.05; done
}
trap 'printf previous > "$CAPTURE_MARKER"; exit 143' TERM
AVAILABLE_AGENTS=agy
MAX_PARALLEL=1
SUPPORTS_DISABLE_CRON_ENV=false
parallel_execute "$INTERRUPT_TASKS"
RUNNER
chmod +x "$capture_runner"
PROJECT_ROOT="$PROJECT_ROOT" CAPTURE_MARKER="$capture_marker" \
CAPTURE_READY="$capture_ready" CAPTURE_PROVIDER_FILE="$capture_provider_file" \
CAPTURE_CHILD_FILE="$capture_child_file" CAPTURE_PATH_FILE="$capture_path_file" \
INTERRUPT_TASKS="$interrupt_tasks" WORKSPACE_DIR="$WORKSPACE_DIR" \
OCTOPUS_PARALLEL_REPORT_FILE="$OCTOPUS_PARALLEL_REPORT_FILE" TMPDIR="$TMPDIR" \
"$capture_runner" &
capture_runner_pid=$!
for _ in $(seq 1 100); do
    [[ -f "$capture_ready" && -f "$capture_child_file" ]] && break
    sleep 0.05
done
kill -TERM "$capture_runner_pid" 2>/dev/null || true
if wait "$capture_runner_pid"; then capture_rc=0; else capture_rc=$?; fi
capture_provider_pid="$(<"$capture_provider_file")"
capture_child_pid="$(<"$capture_child_file")"
for _ in $(seq 1 100); do
    if ! kill -0 "$capture_provider_pid" 2>/dev/null && \
       ! kill -0 "$capture_child_pid" 2>/dev/null; then
        break
    fi
    sleep 0.05
done
capture_processes_dead=false
if ! kill -0 "$capture_provider_pid" 2>/dev/null && \
   ! kill -0 "$capture_child_pid" 2>/dev/null; then
    capture_processes_dead=true
fi
capture_temp_path="$(<"$capture_path_file")"
capture_leftovers="$(find "$TMPDIR" -maxdepth 1 \( -name 'octo-parallel-outcomes.*' -o -name 'octo-parallel-spawn.*' -o -name 'octo-parallel-pid.*' \) -print)"
if [[ "$capture_rc" -eq 143 && -f "$capture_marker" && \
      "$capture_processes_dead" == "true" && ! -e "$capture_temp_path" && \
      -z "$capture_leftovers" ]]; then
    test_pass
else
    test_fail "capture TERM rc=$capture_rc prior_handler=$([[ -f "$capture_marker" ]] && echo yes || echo no) processes_dead=$capture_processes_dead capture_temp=$capture_temp_path leftovers=$capture_leftovers"
fi

reset_run_state
AGGREGATE_RC=9
run_parallel '{"tasks":[{"id":"aggregate","agent":"agy","prompt":"aggregate"}]}'

test_case "aggregation failure overrides successful seat status"
if [[ "$PARALLEL_RC" -eq 9 ]] && jq -e '
    .status == "failed" and
    .counts == {total:1,completed:1,skipped:0,failed:0} and
    .aggregation_exit_code == 9
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null; then
    test_pass
else
    test_fail "aggregation failure was not preserved in report and return code"
fi

test_case "set -e does not bypass report writing after aggregation failure"
set_e_runner="$TEST_TMP_DIR/set-e-runner.sh"
{
    printf '%s\n' '#!/usr/bin/env bash' 'set -eo pipefail'
    printf 'source %q\n' "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
    printf 'source %q\n' "$PROJECT_ROOT/scripts/lib/parallel.sh"
    declare -f log render_agent_summary update_active_count spawn_agent_capture_pid is_provider_available octo_quota_is_dead
    printf '%s\n' 'aggregate_results() { return 9; }'
    printf 'AVAILABLE_AGENTS=%q\n' "$AVAILABLE_AGENTS"
    printf '%s\n' 'MAX_PARALLEL=1' 'SUPPORTS_DISABLE_CRON_ENV=false'
    printf 'WORKSPACE_DIR=%q\n' "$WORKSPACE_DIR"
    printf 'TEST_TMP_DIR=%q\n' "$TEST_TMP_DIR"
    printf 'ACTIVE_FILE=%q\n' "$ACTIVE_FILE"
    printf 'MAX_ACTIVE_FILE=%q\n' "$MAX_ACTIVE_FILE"
    printf 'COUNTER_LOCK=%q\n' "$COUNTER_LOCK"
    printf 'PID_FILE=%q\n' "$PID_FILE"
    printf 'CIRCUIT_CALLS_FILE=%q\n' "$CIRCUIT_CALLS_FILE"
    printf 'QUOTA_CALLS_FILE=%q\n' "$QUOTA_CALLS_FILE"
    printf 'CIRCUIT_PROVIDER=%q\n' "$CIRCUIT_PROVIDER"
    printf 'QUOTA_PROVIDER=%q\n' "$QUOTA_PROVIDER"
    printf 'OCTOPUS_PARALLEL_REPORT_FILE=%q\n' "$OCTOPUS_PARALLEL_REPORT_FILE"
    printf 'parallel_execute %q\n' "$TASKS_FILE"
} > "$set_e_runner"
chmod +x "$set_e_runner"

reset_run_state
printf '%s\n' '{"tasks":[{"id":"set-e","agent":"agy","prompt":"set-e"}]}' > "$TASKS_FILE"
if "$set_e_runner"; then
    set_e_rc=0
else
    set_e_rc=$?
fi
if [[ "$set_e_rc" -eq 9 ]] && jq -e '
    .status == "failed" and .aggregation_exit_code == 9 and .counts.completed == 1
  ' "$OCTOPUS_PARALLEL_REPORT_FILE" >/dev/null 2>&1; then
    test_pass
else
    test_fail "set -e returned $set_e_rc before writing the failed aggregation report"
fi

test_summary
