#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Parallel aggregation task scope"
source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/error-tracking.sh"
source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/agent-spec.sh"
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace" OCTOPUS_RUN_ID=aggregation-scope
RESULTS_DIR="$WORKSPACE_DIR/results"
mkdir -p "$RESULTS_DIR"
current="$RESULTS_DIR/codex-t1.md"
old="$RESULTS_DIR/codex-old-t1.md"
printf '## Output\nCURRENT_IMPLEMENTATION\n## Status: SUCCESS\n' > "$current"
printf '## Output\nUNRELATED_EARLIER_IMPLEMENTATION\n## Status: SUCCESS\n' > "$old"
write_agent_status codex ok 10 10 '' 1 "$old"
write_agent_status codex ok 10 10 '' 1 "$current" researcher spawn-t1
tasks="$(jq -nc --arg file "$current" '[{id:"t1",output_file:$file}]')"
log() { :; }
guard_output() { :; }
rank_results_by_signals() { printf '%s\n%s\n' "$old" "$current"; }
score_result_file() { echo 80; }
DRY_RUN=false TIMEOUT=1 GREEN='' NC=''
for implementation in parallel heuristics; do
    source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/parallel.sh"
    [[ "$implementation" == parallel ]] || source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/heuristics.sh"
    _aggregate_pick_synth_agent() { :; }
    test_case "$implementation aggregation includes only exact current result paths"
    rm -f "$RESULTS_DIR"/aggregate-*.md
    aggregate_results '' '' "$tasks" > /dev/null
    content="$(cat "$RESULTS_DIR"/aggregate-*.md)"
    if [[ "$content" == *CURRENT_IMPLEMENTATION* && "$content" != *UNRELATED_EARLIER* ]]; then
        test_pass
    else
        test_fail "earlier same-provider task entered aggregation: $content"
    fi
    test_case "$implementation empty task scope cannot fall back to earlier outputs"
    rm -f "$RESULTS_DIR"/aggregate-*.md
    aggregate_results '' '' '[]' > /dev/null
    content="$(cat "$RESULTS_DIR"/aggregate-*.md)"
    if [[ "$content" == *'Total Results: 0'* && "$content" != *IMPLEMENTATION* ]]; then
        test_pass
    else
        test_fail "empty current task list included stale results: $content"
    fi
done

test_case "parallel executor passes attempted task identities even when spawning fails"
source "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/parallel.sh"
AVAILABLE_AGENTS=codex SUPPORTS_DISABLE_CRON_ENV=false MAX_PARALLEL=1
spawn_agent_capture_pid() { return 1; }
aggregate_results() { printf '%s' "${3:-null}" > "$TEST_TMP_DIR/aggregation-tasks.json"; }
printf '{"tasks":[{"id":"t1","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 ]] && jq -e --arg file "$current" \
    '. == [{id:"t1",output_file:$file}]' "$TEST_TMP_DIR/aggregation-tasks.json" > /dev/null; then
    test_pass
else
    test_fail "executor lost attempted task scope, exit=$rc"
fi
test_case "a failed repeated spawn cannot retain an earlier output at the same path"
if [[ ! -e "$current" ]]; then
    test_pass
else
    test_fail "failed spawn retained a previous answer at its current task path"
fi
test_case "legacy Opus fast alias uses the normalized dispatch result path"
AVAILABLE_AGENTS=claude-opus-fast
printf '{"tasks":[{"id":"t2","agent":"claude-opus-fast","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-alias.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 ]] && jq -e --arg file "$RESULTS_DIR/claude-opus-t2.md" \
    '.[0].output_file == $file' "$TEST_TMP_DIR/aggregation-tasks.json" > /dev/null; then
    test_pass
else
    test_fail "aggregation expected a different path than the normalized dispatcher"
fi
test_case "dry-run preserves previous outputs"
AVAILABLE_AGENTS=codex DRY_RUN=true
spawn_agent() { :; }
printf 'preserve previous answer\n' > "$current"
printf '{"tasks":[{"id":"t1","agent":"codex","prompt":"preview"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-preview.log" 2>&1
if [[ "$(cat "$current")" == 'preserve previous answer' ]]; then
    test_pass
else
    test_fail "preview removed an existing result"
fi
test_case "failure to remove an old output fails closed before dispatch"
DRY_RUN=false
mkdir "$RESULTS_DIR/codex-blocked.md"
spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/unsafe-spawn"; return 1; }
printf '{"tasks":[{"id":"blocked","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-blocked.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 && ! -e "$TEST_TMP_DIR/unsafe-spawn" ]] && \
    jq -e '. == [{id:"blocked",output_file:""}]' "$TEST_TMP_DIR/aggregation-tasks.json" > /dev/null && \
    jq -e '.agents | any(.reason == "stale-output-removal" and .seat_id == "spawn-blocked" and .output_file == "")' \
        "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else
    test_fail "undeletable prior output remained in dispatch or aggregation"
fi
test_case "distinct tasks cannot delete or overwrite a completed task's result"
if (
    trap - EXIT
    AVAILABLE_AGENTS='codex codex-standard claude claude-opus-fast'
    for pair in 'codex standard-build codex-standard build' 'claude opus-build claude-opus-fast build'; do
        read -r first_agent first_id second_agent second_id <<< "$pair"
        collision_file="$RESULTS_DIR/$first_agent-$first_id.md"
        rm -f "$TEST_TMP_DIR/colliding-spawn"
        spawn_agent_capture_pid() {
            if [[ "$3" == "$first_id" ]]; then
                printf 'completed first task\n' > "$collision_file"
                mkdir -p "$WORKSPACE_DIR/.octo/agents"
                printf '0\n' > "$WORKSPACE_DIR/.octo/agents/$3.done"
                printf '99999999\n'
            else
                touch "$TEST_TMP_DIR/colliding-spawn"
                return 1
            fi
        }
        jq -n --arg a "$first_agent" --arg i "$first_id" \
            --arg b "$second_agent" --arg j "$second_id" \
            '{tasks:[{id:$i,agent:$a,prompt:"first"},{id:$j,agent:$b,prompt:"second"}]}' \
            > "$TEST_TMP_DIR/tasks.json"
        parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-collision.log" 2>&1 && rc=0 || rc=$?
        [[ "$rc" == 0 && ! -e "$TEST_TMP_DIR/colliding-spawn" ]] || exit 1
        [[ "$(cat "$collision_file")" == 'completed first task' ]] || exit 1
        jq -e '.status == "degraded" and .counts.completed == 1 and .counts.failed == 1 and
            .results[1].reason == "output-path-collision"' \
            "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null || exit 1
        summary="$(render_agent_summary '' "$(cat "$TEST_TMP_DIR/aggregation-tasks.json")")"
        [[ "$summary" == *'failed'* ]] || exit 1
        jq -e '.agents | any(.reason == "output-path-collision" and .output_file == "")' \
            "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null || exit 1
        jq -e 'length == 2' "$TEST_TMP_DIR/aggregation-tasks.json" >/dev/null || exit 1
    done
); then
    test_pass
else
    test_fail "colliding task dispatched, removed completed output, or entered aggregation"
fi

for owner in claim legacy-ledger; do
    test_case "a $owner owner keeps its output when another invocation reuses the task"
    export OCTOPUS_RUN_ID="ownership-$owner"
    owned="$RESULTS_DIR/codex-owned.md"
    printf 'active partial output\n' > "$owned"
    rm -f "$TEST_TMP_DIR/unsafe-spawn"
    mkdir -p "$WORKSPACE_DIR/.octo/agents"
    printf '0\n' > "$WORKSPACE_DIR/.octo/agents/owned.done"
    if [[ "$owner" == claim ]]; then
        mkdir "$RESULTS_DIR/.codex-owned.claim"
    else
        write_agent_status codex running 1 0 '' 0 "$owned" researcher spawn-owned
    fi
    printf '{"tasks":[{"id":"owned","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
    AVAILABLE_AGENTS=codex
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-owned.log" 2>&1 && rc=0 || rc=$?
    if [[ "$rc" == 1 && ! -e "$TEST_TMP_DIR/unsafe-spawn" && "$(cat "$owned")" == 'active partial output' ]] &&
       jq -e '.results[0].reason == "output-path-owned"' "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null; then
        test_pass
    else test_fail "another invocation deleted or dispatched into an owned output"; fi
    test_case "a rejected $owner contender preserves the owner's completion marker"
    if [[ -f "$WORKSPACE_DIR/.octo/agents/owned.done" ]] && \
       [[ "$(cat "$WORKSPACE_DIR/.octo/agents/owned.done")" == 0 ]]; then
        test_pass
    else
        test_fail "rejected contender removed a completed owner's marker"
    fi
    [[ "$owner" != claim ]] || rmdir "$RESULTS_DIR/.codex-owned.claim"
done

test_case "a claim stays owned while a process its exited owner started is alive"
export OCTOPUS_RUN_ID=ownership-orphan
orphan_output="$RESULTS_DIR/codex-orphan.md"
orphan_claim="$RESULTS_DIR/.codex-orphan.claim"
orphan_lock="$RESULTS_DIR/.parallel-owner.orphan"
printf 'orphaned partial output\n' > "$orphan_output"
write_agent_status codex running 1 0 '' 0 "$orphan_output" researcher spawn-orphan
mkdir "$orphan_claim"
printf '%s\n' "$orphan_lock" > "$orphan_claim/owner"
(
    exec 7>"$orphan_lock"
    python3 "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/helpers/output-claim.py" hold 7 </dev/null || exit 1
    : > "$TEST_TMP_DIR/orphan-ready"
    exec sleep 60
) &
orphan_holder=$!
for _ in $(seq 1 50); do [[ -e "$TEST_TMP_DIR/orphan-ready" ]] && break; sleep 0.1; done
rm -f "$TEST_TMP_DIR/orphan-spawn"
spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/orphan-spawn"; return 1; }
printf '{"tasks":[{"id":"orphan","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-orphan.log" 2>&1 && rc=0 || rc=$?
if [[ -e "$TEST_TMP_DIR/orphan-ready" && "$rc" == 1 && ! -e "$TEST_TMP_DIR/orphan-spawn" ]] &&
   [[ "$(cat "$orphan_output")" == 'orphaned partial output' ]] &&
   jq -e '.results[0].reason == "output-path-owned"' "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null; then
    test_pass
else
    test_fail "a claim was taken while its owner's descendant still held the owner lock, exit=$rc"
fi

test_case "a claim is reclaimed and its seat cancelled once every owner process has exited"
kill "$orphan_holder" 2>/dev/null || true
wait "$orphan_holder" 2>/dev/null || true
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-reclaim.log" 2>&1 && rc=0 || rc=$?
leftover_locks="$(find "$RESULTS_DIR" -maxdepth 1 -name '.parallel-owner.*' ! -name '.parallel-owner.orphan' | wc -l | tr -d ' ')"
if [[ "$rc" == 1 && -e "$TEST_TMP_DIR/orphan-spawn" && ! -e "$orphan_output" && ! -e "$orphan_claim" ]] &&
   [[ "$leftover_locks" == 0 ]] &&
   jq -e '.results[0].reason == "failed-spawn"' "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null &&
   jq -e '.agents | any(.seat_id == "spawn-orphan" and .status == "cancelled" and
       .output_file == "'"$orphan_output"'")' "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else
    test_fail "stale claim was not reclaimed, its seat stayed running, or claim state leaked, exit=$rc locks=$leftover_locks"
fi

test_case "a descriptor 7 opened by the caller survives the executor"
caller_fd_file="$TEST_TMP_DIR/caller-fd7.log"
if (
    trap - EXIT
    exec 7>"$caller_fd_file"
    printf '{"tasks":[{"id":"caller-fd","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-caller-fd.log" 2>&1 || true
    printf 'caller still owns fd 7\n' >&7
) && [[ "$(cat "$caller_fd_file")" == 'caller still owns fd 7' ]]; then
    test_pass
else
    test_fail "the executor replaced or closed the caller's descriptor 7"
fi

test_case "an admitted retry clears its old marker before dispatch"
mkdir -p "$WORKSPACE_DIR/.octo/agents"
printf '0\n' > "$WORKSPACE_DIR/.octo/agents/retry.done"
spawn_agent_capture_pid() {
    [[ ! -e "$WORKSPACE_DIR/.octo/agents/retry.done" ]] && touch "$TEST_TMP_DIR/retry-cleared"
    return 1
}
printf '{"tasks":[{"id":"retry","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-retry.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 && -f "$TEST_TMP_DIR/retry-cleared" ]]; then test_pass
else test_fail "retry dispatched with its previous completion marker"; fi

for checkpoint in before-record after-record; do
    test_case "SIGKILL $checkpoint cannot publish an ownerless output claim"
    if python3 - "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/helpers/output-claim.py" "$TEST_TMP_DIR" "$checkpoint" <<'PY'
import pathlib
import signal
import subprocess
import sys

helper, root, checkpoint = sys.argv[1:]
root = pathlib.Path(root)
claim = root / (".interrupted-" + checkpoint + ".claim")
owner = root / (".parallel-owner." + checkpoint)
owner.touch()
code = """
import importlib.util, os, signal, sys
spec = importlib.util.spec_from_file_location('claim', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = module.record_owner
def interrupted(*args):
    if sys.argv[4] == 'after-record':
        original(*args)
    os.kill(os.getpid(), signal.SIGKILL)
module.record_owner = interrupted
module.acquire(sys.argv[2], sys.argv[3])
"""
killed = subprocess.run([sys.executable, "-c", code, helper, str(claim), str(owner), checkpoint], timeout=5)
assert killed.returncode == -signal.SIGKILL, killed.returncode
assert not claim.exists(), "interrupted preparation published a claim"
retry = subprocess.run([sys.executable, helper, "acquire", str(claim), str(owner)], timeout=5)
assert retry.returncode == 0, retry.returncode
assert (claim / "owner").read_text().strip() == str(owner)
PY
    then test_pass
    else test_fail "interrupted claim preparation blocked a retry"; fi
done

for concurrency in 1 2; do
    test_case "failed worker clears its running seat at concurrency $concurrency"
    export OCTOPUS_RUN_ID="worker-exit-$concurrency"
    MAX_PARALLEL=$concurrency AVAILABLE_AGENTS='codex claude-opus-fast'
    spawn_agent_capture_pid() {
        local slug="$1"
        [[ "$slug" != claude-opus-fast ]] || slug=claude-opus
        write_agent_status "$1" running 1 0 '' 0 "$RESULTS_DIR/$slug-$3.md" researcher "spawn-$3"
        (exit 74) &
        printf '%s\n' "$!"
    }
    printf '{"tasks":[{"id":"exit-a","agent":"codex","prompt":"first"},{"id":"exit-b","agent":"claude-opus-fast","prompt":"second"}]}' > "$TEST_TMP_DIR/tasks.json"
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/worker-exit-$concurrency.log" 2>&1 && rc=0 || rc=$?
    if [[ "$rc" == 1 ]] && jq -e '.agents | length == 2 and all(.status == "cancelled" and .role == "researcher")' \
        "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
        test_pass
    else test_fail "dead worker left a running seat at concurrency $concurrency"; fi

    test_case "failed workers can retry in the same run at concurrency $concurrency"
    rm -f "$TEST_TMP_DIR/worker-retry"
    spawn_agent_capture_pid() { printf '%s\n' "$3" >> "$TEST_TMP_DIR/worker-retry"; return 1; }
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/worker-retry-$concurrency.log" 2>&1 || true
    if [[ -f "$TEST_TMP_DIR/worker-retry" && "$(wc -l < "$TEST_TMP_DIR/worker-retry")" -eq 2 ]]; then
        test_pass
    else test_fail "dead workers blocked same-run retries"; fi
done

test_case "TERM after claim publication cannot strand an unregistered claim"
claim_python="$TEST_TMP_DIR/claim-python"
cat > "$claim_python" <<'SHIM'
#!/usr/bin/env python3
import os
import runpy
import signal
import sys
if len(sys.argv) > 2 and sys.argv[2] == "acquire":
    original = os.rename
    def interrupt_after_publish(*args):
        original(*args)
        os.kill(os.getppid(), signal.SIGTERM)
    os.rename = interrupt_after_publish
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
SHIM
chmod +x "$claim_python"
export claim_python
printf '{"tasks":[{"id":"publish-interrupt","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
if (
    trap - EXIT
    trap 'exit 143' TERM
    octopus_pid_python_resolve() { printf '%s\n' "$claim_python"; }
    spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/interrupted-spawn"; return 1; }
    parallel_execute "$TEST_TMP_DIR/tasks.json" >/dev/null 2>&1
); then rc=0; else rc=$?; fi
spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/publication-retry"; return 1; }
AVAILABLE_AGENTS=codex
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/publication-retry.log" 2>&1 || true
if [[ "$rc" == 143 && ! -e "$TEST_TMP_DIR/interrupted-spawn" && -e "$TEST_TMP_DIR/publication-retry" ]] &&
   [[ ! -e "$RESULTS_DIR/.codex-publish-interrupt.claim" ]]; then
    test_pass
else test_fail "interrupted publication blocked retry, rc=$rc"; fi

for damaged_ledger in truncated trailing; do
    test_case "a $damaged_ledger ownership ledger preserves output and blocks dispatch"
    export OCTOPUS_RUN_ID="ownership-damaged-$damaged_ledger"
    ledger="$(octo_run_dir)/agents.jsonl"
    mkdir -p "$(dirname "$ledger")" "$WORKSPACE_DIR/.octo/agents"
    owned="$RESULTS_DIR/codex-damaged.md"
    printf 'active partial output\n' > "$owned"
    printf '0\n' > "$WORKSPACE_DIR/.octo/agents/damaged.done"
    if [[ "$damaged_ledger" == trailing ]]; then
        write_agent_status codex running 1 0 '' 0 "$owned" researcher spawn-damaged
    fi
    printf '{"agent":' >> "$ledger"
    rm -f "$TEST_TMP_DIR/damaged-spawn"
    spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/damaged-spawn"; return 1; }
    printf '{"tasks":[{"id":"damaged","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
    AVAILABLE_AGENTS=codex
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/damaged-$damaged_ledger.log" 2>&1 && rc=0 || rc=$?
    if [[ "$rc" == 1 && ! -e "$TEST_TMP_DIR/damaged-spawn" && "$(cat "$owned")" == 'active partial output' ]] &&
       [[ "$(cat "$WORKSPACE_DIR/.octo/agents/damaged.done")" == 0 ]] &&
       jq -e '.results[0].reason == "output-path-owned"' "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null; then
        test_pass
    else test_fail "damaged ownership ledger permitted dispatch or removed active artifacts"; fi
done

test_case "a valid terminal ownership ledger permits a new dispatch"
export OCTOPUS_RUN_ID=ownership-terminal
write_agent_status codex failed 1 0 '' 0 "$RESULTS_DIR/codex-damaged.md" researcher spawn-damaged
rm -f "$TEST_TMP_DIR/damaged-spawn"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/terminal-ledger.log" 2>&1 || true
if [[ -e "$TEST_TMP_DIR/damaged-spawn" ]]; then
    test_pass
else test_fail "valid terminal ownership was rejected"; fi

test_case "fallback and Python claim publication cannot admit two owners"
if python3 "$PROJECT_ROOT/tests/unit/test-output-claim-races.py"; then test_pass
else test_fail "controlled claim publication interleavings admitted two owners"; fi

test_summary
