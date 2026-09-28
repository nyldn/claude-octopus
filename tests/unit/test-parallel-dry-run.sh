#!/usr/bin/env bash
# Regression coverage for `orchestrate.sh --dry-run parallel <tasks.json>`.
# spawn_agent's dry-run branch prints a command preview and never a provider
# PID, so routing each task through spawn_agent_capture_pid reported every
# valid task as a failed spawn, then aggregated and reported the failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "parallel dry-run"

# An isolated HOME keeps a developer's workspace out of the run. The workspace
# and report overrides are cleared too, because they take precedence over HOME
# and would send run state to the real workspace.
parallel_home="$TEST_TMP_DIR/parallel-dry-run-home"
parallel_project="$TEST_TMP_DIR/parallel-dry-run-project"
workspace="$parallel_home/.claude-octopus"
mkdir -p "$workspace/.octo/agents"
printf '0\n' > "$workspace/.octo/agents/t1.done"
git init -q "$parallel_project"
cat > "$parallel_project/tasks.json" <<'JSON'
{"tasks":[
  {"id":"t1","agent":"codex","prompt":"first task"},
  "not-an-object",
  {"id":"t2","agent":"missing-agent","prompt":"unknown agent"},
  {"id":"t1","agent":"codex","prompt":"duplicate id"},
  {"id":"t3","agent":"claude-sonnet","prompt":"last task"}
]}
JSON

out="$(cd "$parallel_project" && env -u CLAUDE_PLUGIN_DATA -u CLAUDE_OCTOPUS_WORKSPACE \
    -u OCTOPUS_WORKFLOW_STATE_DIR -u OCTOPUS_STATE_PROJECT_ROOT -u OCTOPUS_PARALLEL_REPORT_FILE \
    "HOME=$parallel_home" \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" -n parallel "$parallel_project/tasks.json" </dev/null 2>&1)" \
    && rc=0 || rc=$?
previews="$(grep -c '\[DRY-RUN\] Would execute:' <<< "$out" || true)"

test_case "dry-run parallel exits cleanly when a task is valid"
if [[ "$rc" -eq 0 ]]; then
    test_pass
else
    test_fail "expected exit 0; got exit=$rc, output: $out"
fi

test_case "dry-run parallel previews each valid task once"
if [[ "$previews" -eq 2 ]]; then
    test_pass
else
    test_fail "expected 2 previews; got $previews, output: $out"
fi

test_case "dry-run parallel reports invalid tasks as a real run does"
if [[ "$out" == *"Skipping malformed task at sequence 1"* \
    && "$out" == *"Skipping task t2: unknown agent 'missing-agent'"* \
    && "$out" == *"Skipping duplicate task id 't1'"* ]]; then
    test_pass
else
    test_fail "expected a skip warning per invalid task; output: $out"
fi

test_case "dry-run parallel summarizes what a real run would dispatch"
if [[ "$out" == *"[DRY-RUN] Would dispatch 2 of 5 tasks (3 skipped, 0 failed)"* ]]; then
    test_pass
else
    test_fail "expected a dry-run dispatch summary; output: $out"
fi

test_case "dry-run parallel reports no failed spawn"
if [[ "$out" != *"produced no provider PID"* && "$out" != *"failed to spawn agent"* ]]; then
    test_pass
else
    test_fail "dry-run reported spawn failures: $out"
fi

test_case "dry-run parallel writes no aggregate or execution report"
aggregates="$(find "$workspace" -name 'aggregate-*.md' | wc -l | tr -d ' ')"
if [[ "$out" != *"Aggregating results"* && "$aggregates" -eq 0 \
    && ! -e "$workspace/state/parallel-report.json" ]]; then
    test_pass
else
    test_fail "dry-run aggregated or reported; aggregates=$aggregates, output: $out"
fi

test_case "dry-run parallel keeps existing completion markers"
if [[ -f "$workspace/.octo/agents/t1.done" ]]; then
    test_pass
else
    test_fail "dry-run removed $workspace/.octo/agents/t1.done"
fi

# A fresh bash process mirrors orchestrate.sh's `set -eo pipefail`; a call
# inside this suite's `&& ... || ...` capture would silently ignore errexit.
# The spawn_agent stub drains stdin, which is the task stream in production.
harness="$TEST_TMP_DIR/parallel-dry-run-harness.sh"
cat > "$harness" <<'HARNESS'
set -eo pipefail
tasks_file="$2"
calls_log="$3"
failing_agent="$4"
DRY_RUN=true
AVAILABLE_AGENTS="codex claude-sonnet"
SUPPORTS_DISABLE_CRON_ENV=false
log() { printf '%s: %s\n' "$1" "$2"; }
source "$1"
aggregate_results() { printf 'aggregate\n' >> "$calls_log"; }
spawn_agent() {
    cat > /dev/null
    printf 'preview:%s:%s\n' "$1" "$3" >> "$calls_log"
    [[ "$1" != "$failing_agent" ]]
}
spawn_agent_capture_pid() { printf 'capture:%s\n' "$1" >> "$calls_log"; return 1; }
trap ': caller' INT
trap ': caller' TERM
trap ': caller' EXIT
traps_before="$(trap -p INT; trap -p TERM; trap -p EXIT)"
parallel_execute "$tasks_file"
[[ "$(trap -p INT; trap -p TERM; trap -p EXIT)" == "$traps_before" ]] && echo "caller traps restored"
echo "parallel_execute returned"
HARNESS

run_harness() {
    local name="$1" tasks_json="$2" failing_agent="${3:-}"
    local home="$TEST_TMP_DIR/$name-home" tmp="$TEST_TMP_DIR/$name-tmp"
    local tasks_file="$TEST_TMP_DIR/$name-tasks.json" calls_log="$TEST_TMP_DIR/$name-calls"
    mkdir -p "$home" "$tmp"
    : > "$calls_log"
    printf '%s\n' "$tasks_json" > "$tasks_file"
    harness_out="$(env -u OCTOPUS_PARALLEL_REPORT_FILE -u WORKSPACE_DIR "HOME=$home" "TMPDIR=$tmp" \
        bash "$harness" "$PROJECT_ROOT/scripts/lib/parallel.sh" "$tasks_file" "$calls_log" \
        "$failing_agent" </dev/null 2>&1)" && harness_rc=0 || harness_rc=$?
    harness_calls="$(<"$calls_log")"
    harness_leftovers="$(find "$tmp" -mindepth 1 | wc -l | tr -d ' ')"
    harness_report="$home/.claude-octopus/state/parallel-report.json"
}

test_case "dry-run parallel previews every task without draining the task stream or capturing a PID"
run_harness stream '{"tasks":[
  {"id":"t1","agent":"codex","prompt":"one"},
  {"id":"t2","agent":"claude-sonnet","prompt":"two"},
  {"id":"t3","agent":"codex","prompt":"three"}
]}'
if [[ "$harness_rc" -eq 0 && "$harness_out" == *"parallel_execute returned"* \
    && "$harness_calls" == $'preview:codex:t1\npreview:claude-sonnet:t2\npreview:codex:t3' \
    && "$harness_leftovers" -eq 0 && ! -e "$harness_report" ]]; then
    test_pass
else
    test_fail "expected three previews, no capture, aggregate or leftovers; got exit=$harness_rc, calls: $harness_calls, leftovers=$harness_leftovers, output: $harness_out"
fi

test_case "dry-run parallel restores the caller's traps"
if [[ "$harness_out" == *"caller traps restored"* ]]; then
    test_pass
else
    test_fail "expected the caller's INT, TERM and EXIT traps after the dry run; output: $harness_out"
fi

test_case "dry-run parallel accepts an empty task list, as a real run does"
run_harness empty '{"tasks":[]}'
if [[ "$harness_rc" -eq 0 && "$harness_out" == *"parallel_execute returned"* \
    && "$harness_out" == *"[DRY-RUN] Would dispatch 0 of 0 tasks (0 skipped, 0 failed)"* \
    && -z "$harness_calls" && "$harness_leftovers" -eq 0 && ! -e "$harness_report" ]]; then
    test_pass
else
    test_fail "expected exit 0 with nothing to preview; got exit=$harness_rc, calls: $harness_calls, leftovers=$harness_leftovers, output: $harness_out"
fi

test_case "dry-run parallel warns on a failed preview and still previews the remaining tasks"
run_harness partial '{"tasks":[
  {"id":"t1","agent":"codex","prompt":"one"},
  {"id":"t2","agent":"claude-sonnet","prompt":"two"}
]}' codex
if [[ "$harness_rc" -eq 0 \
    && "$harness_out" == *"WARN: Skipping task t1: failed to spawn agent 'codex'"* \
    && "$harness_out" == *"[DRY-RUN] Would dispatch 1 of 2 tasks (0 skipped, 1 failed)"* \
    && "$harness_calls" == $'preview:codex:t1\npreview:claude-sonnet:t2' ]]; then
    test_pass
else
    test_fail "expected a warning and both previews; got exit=$harness_rc, calls: $harness_calls, output: $harness_out"
fi

test_case "dry-run parallel fails when no task would be dispatched"
run_harness none '{"tasks":[
  {"id":"t1","agent":"missing-agent","prompt":"one"},
  {"id":"t2","agent":"codex","prompt":"two"}
]}' codex
if [[ "$harness_rc" -eq 1 && "$harness_out" != *"parallel_execute returned"* \
    && "$harness_out" == *"[DRY-RUN] Would dispatch 0 of 2 tasks (1 skipped, 1 failed)"* \
    && "$harness_calls" == "preview:codex:t2" \
    && "$harness_leftovers" -eq 0 && ! -e "$harness_report" ]]; then
    test_pass
else
    test_fail "expected exit 1 after one skip and one failed preview; got exit=$harness_rc, calls: $harness_calls, leftovers=$harness_leftovers, output: $harness_out"
fi

test_summary
