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
    test_case "$implementation aggregates a scope larger than the per-argument OS limit"
    large_tasks=$(jq -nc --arg file "$current" \
        '[range(0; 3500) | {id:("t" + tostring),output_file:$file}]')
    rm -f "$RESULTS_DIR"/aggregate-*.md
    aggregate_results '' '' "$large_tasks" > "$TEST_TMP_DIR/large-scope.log" 2>&1 && rc=0 || rc=$?
    content="$(cat "$RESULTS_DIR"/aggregate-*.md)"
    if [[ "$rc" == 0 && "$content" == *CURRENT_IMPLEMENTATION* && "$content" != *UNRELATED_EARLIER* ]]; then
        test_pass
    else
        test_fail "large task scope lost current results, exit=$rc"
    fi
    test_case "$implementation reports invalid task scope instead of silently dropping results"
    if (
        log() { printf '%s: %s\n' "$1" "$2" >&2; }
        aggregate_results '' '' '['
    ) > "$TEST_TMP_DIR/invalid-scope.log" 2>&1; then rc=0; else rc=$?; fi
    if [[ "$rc" -gt 1 ]] && grep -q 'Cannot read aggregation task scope' "$TEST_TMP_DIR/invalid-scope.log"; then
        test_pass
    else
        test_fail "invalid scope was silently accepted, exit=$rc"
    fi
    for scope_results in present empty; do
        for invalid_scope in '[' 'null []' '{} []' '{}' '[{}]'; do
            test_case "$implementation rejects $invalid_scope before selecting $scope_results results"
            if (
                RESULTS_DIR="$TEST_TMP_DIR/scope-validation-$implementation-$scope_results"
                mkdir -p "$RESULTS_DIR"
                rank_results_by_signals() { :; }
                if [[ "$scope_results" == present ]]; then
                    cp "$current" "$RESULTS_DIR/current.md"
                fi
                log() { printf '%s: %s\n' "$1" "$2" >&2; }
                aggregate_results '' '' "$invalid_scope"
            ) > "$TEST_TMP_DIR/scope-validation.log" 2>&1; then rc=0; else rc=$?; fi
            if [[ "$rc" -gt 1 ]] &&
               grep -q 'Cannot read aggregation task scope' "$TEST_TMP_DIR/scope-validation.log" &&
               [[ -z "$(find "$TEST_TMP_DIR/scope-validation-$implementation-$scope_results" -name 'aggregate-*.md' -print)" ]]; then
                test_pass
            else
                test_fail "invalid scope reached aggregation with $scope_results results, exit=$rc"
            fi
        done
    done
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
    AVAILABLE_AGENTS='codex codex-standard claude claude-opus-fast agy'
    for pair in 'codex standard-build codex-standard build' 'claude opus-build claude-opus-fast build'; do
        read -r first_agent first_id second_agent second_id <<< "$pair"
        export OCTOPUS_RUN_ID="collision-terminal-$first_agent"
        saved="$RESULTS_DIR/agy-$second_id.md"
        printf 'earlier completed answer\n' > "$saved"
        write_agent_status agy ok 1 10 '' 0 "$saved" researcher "spawn-$second_id"
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
        jq -e --arg file "$saved" --arg seat "spawn-$second_id" \
            '.agents | any(.seat_id == $seat and .agent == "agy" and .status == "ok" and .output_file == $file)' \
            "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null || exit 1
        agent_status_output_files | grep -Fx -- "$saved" >/dev/null || exit 1
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
python3 "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/helpers/output-claim.py" acquire \
    "$orphan_claim" "$orphan_lock" spawn-orphan "$orphan_output" "$OCTOPUS_RUN_ID" "$WORKSPACE_DIR"
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

# Publish the claim of an exited owner that dispatched the last seat, after
# reclaiming in turn from exited owners of each earlier seat.
_stale_claim() {
    local claim="$RESULTS_DIR/$1" output="$2" seat stale_lock
    shift 2
    for seat in "$@"; do
        stale_lock="$RESULTS_DIR/.parallel-owner.stale-$seat"
        : > "$stale_lock"
        python3 "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}/scripts/helpers/output-claim.py" acquire \
            "$claim" "$stale_lock" "$seat" "$output" "$OCTOPUS_RUN_ID" "$WORKSPACE_DIR" >/dev/null || true
    done
}

test_case "a reclaim cancels the exited owner's seat when another task ID shares its output"
export OCTOPUS_RUN_ID=alias-reclaim
alias_output="$RESULTS_DIR/codex-standard-build.md"
rm -f "$TEST_TMP_DIR/alias-spawn" "$alias_output"
write_agent_status codex running 1 0 '' 0 "$alias_output" researcher spawn-standard-build
_stale_claim .codex-standard-build.claim "$alias_output" spawn-standard-build
spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/alias-spawn"; return 1; }
printf '{"tasks":[{"id":"build","agent":"codex-standard","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
AVAILABLE_AGENTS='codex codex-standard'
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-alias.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 && -e "$TEST_TMP_DIR/alias-spawn" && ! -e "$RESULTS_DIR/.codex-standard-build.claim" ]] &&
   jq -e '.results[0].reason == "failed-spawn"' "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null &&
   jq -e --arg file "$alias_output" '.agents | any(.seat_id == "spawn-standard-build" and
       .status == "cancelled" and .output_file == $file)' \
       "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else
    test_fail "the exited owner's seat for a shared output stayed running, exit=$rc"
fi

test_case "a reclaim cancels stale seats inherited by an owner that was killed before reconciling"
export OCTOPUS_RUN_ID=inherited-reclaim
inherited_output="$RESULTS_DIR/codex-carry.md"
rm -f "$TEST_TMP_DIR/carry-spawn"
write_agent_status codex running 1 0 '' 0 "$inherited_output" researcher spawn-original
_stale_claim .codex-carry.claim "$inherited_output" spawn-original spawn-killed-reclaimer
spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/carry-spawn"; return 1; }
printf '{"tasks":[{"id":"carry","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
AVAILABLE_AGENTS=codex
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-carry.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 && -e "$TEST_TMP_DIR/carry-spawn" ]] &&
   jq -e '.agents | any(.seat_id == "spawn-original" and .status == "cancelled")' \
       "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else
    test_fail "an inherited stale seat stayed running after reclaim, exit=$rc"
fi

test_case "TERM between reclaim and seat reconciliation still cancels the stale seat"
export OCTOPUS_RUN_ID=interrupted-reclaim
termed_output="$RESULTS_DIR/codex-termed.md"
write_agent_status codex running 1 0 '' 0 "$termed_output" researcher spawn-old-termed
_stale_claim .codex-termed.claim "$termed_output" spawn-old-termed
printf '{"tasks":[{"id":"termed","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
(
    trap - EXIT
    log() {
        [[ "${2:-}" != Reclaimed* ]] || kill -TERM "$(sh -c 'printf "%s" "$PPID"')"
    }
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-termed.log" 2>&1
) && rc=0 || rc=$?
if [[ "$rc" == 143 && ! -e "$RESULTS_DIR/.codex-termed.claim" ]] &&
   jq -e '.agents | any(.seat_id == "spawn-old-termed" and .status == "cancelled")' \
       "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else
    test_fail "an interrupted reclaim left the stale seat running or kept its claim, exit=$rc"
fi

# Leave the claim a real executor published when SIGKILL ends it right after
# its worker recorded a running seat, as an abandoned owner leaves it.
_killed_owner() {
    local run="$1" directory="$2" results="$3" agent="$4" task="$5"
    {
        (
            trap - EXIT
            cd "$directory"
            export OCTOPUS_RUN_ID="$run"
            RESULTS_DIR="$results" AVAILABLE_AGENTS="$agent"
            spawn_agent_capture_pid() {
                write_agent_status "$1" running 1 0 '' 0 "$RESULTS_DIR/$1-$3.md" researcher "spawn-$3"
                kill -KILL "$(sh -c 'printf "%s\n" "$PPID"')"
            }
            jq -n --arg id "$task" --arg agent "$agent" '{tasks:[{id:$id,agent:$agent,prompt:"inert"}]}' \
                > "$TEST_TMP_DIR/killed-owner.json"
            parallel_execute "$TEST_TMP_DIR/killed-owner.json"
        )
    } >/dev/null 2>&1 || true
}

test_case "a reclaim cancels the exited owner's seat under the result path spelling it recorded"
export OCTOPUS_RUN_ID=spelling-reclaim
mkdir -p "$TEST_TMP_DIR/spelling-results"
rm -f "$TEST_TMP_DIR/spelling-spawn"
_killed_owner spelling-reclaim "$TEST_TMP_DIR" spelling-results codex standard-build
spawn_agent_capture_pid() { printf '%s\n' "$3" >> "$TEST_TMP_DIR/spelling-spawn"; return 1; }
AVAILABLE_AGENTS='codex codex-standard'
printf '{"tasks":[{"id":"build","agent":"codex-standard","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
(trap - EXIT; RESULTS_DIR="$TEST_TMP_DIR/spelling-results"; parallel_execute "$TEST_TMP_DIR/tasks.json") \
    > "$TEST_TMP_DIR/parallel-spelling.log" 2>&1 || true
printf '{"tasks":[{"id":"standard-build","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
(trap - EXIT; cd "$TEST_TMP_DIR" && RESULTS_DIR=spelling-results && parallel_execute "$TEST_TMP_DIR/tasks.json") \
    > "$TEST_TMP_DIR/parallel-spelling-retry.log" 2>&1 || true
if [[ "$(cat "$TEST_TMP_DIR/spelling-spawn" 2>/dev/null)" == $'build\nstandard-build' ]] &&
   jq -e '.agents | any(.seat_id == "spawn-standard-build" and .status == "cancelled" and
       .output_file == "spelling-results/codex-standard-build.md")' \
       "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else
    test_fail "a different spelling of the results directory left the exited owner's seat running"
fi

test_case "a reclaim leaves another run's live seat on the same result path alone"
crossrun_output="$RESULTS_DIR/codex-crossrun.md"
rm -f "$TEST_TMP_DIR/crossrun-spawn"
_killed_owner crossrun-exited "$TEST_TMP_DIR" "$RESULTS_DIR" codex crossrun
export OCTOPUS_RUN_ID=crossrun-live
run_contract_transition spawn-crossrun planned requested_provider=codex
run_contract_transition spawn-crossrun starting resolved_provider=codex resolved_model=fixture
run_contract_transition spawn-crossrun authenticated
run_contract_transition spawn-crossrun running "output_file=$crossrun_output"
write_agent_status codex running 1 0 '' 0 "$crossrun_output" researcher spawn-crossrun
spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/crossrun-spawn"; return 1; }
AVAILABLE_AGENTS=codex
printf '{"tasks":[{"id":"crossrun","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-crossrun.log" 2>&1 && rc=0 || rc=$?
if [[ "$rc" == 1 && ! -e "$TEST_TMP_DIR/crossrun-spawn" ]] &&
   [[ "$(run_contract_latest_transition spawn-crossrun)" == running ]] &&
   jq -e '.results[0].reason == "output-path-owned"' "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null &&
   jq -e '.agents | any(.seat_id == "spawn-crossrun" and .status == "running")' \
       "$WORKSPACE_DIR/runs/crossrun-live/agents.json" >/dev/null &&
   jq -e '.agents | any(.seat_id == "spawn-crossrun" and .status == "cancelled")' \
       "$WORKSPACE_DIR/runs/crossrun-exited/agents.json" >/dev/null; then
    test_pass
else
    test_fail "reclaiming another run's claim finalized the current run's live seat, exit=$rc"
fi

test_case "an abnormal controller exit stops live workers before releasing their claims"
export OCTOPUS_RUN_ID=abnormal-exit
rm -f "$TEST_TMP_DIR/exit-worker.pid"
printf '{"tasks":[{"id":"exit-worker","agent":"codex","prompt":"implement"}]}' > "$TEST_TMP_DIR/tasks.json"
(
    trap - EXIT
    log() { [[ "${2:-}" != Progress:* ]] || exit 3; }
    spawn_agent_capture_pid() {
        sleep 30 &
        printf '%s\n' "$!" > "$TEST_TMP_DIR/exit-worker.pid"
        printf '%s\n' "$!"
    }
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/parallel-exit.log" 2>&1
) && rc=0 || rc=$?
exit_worker="$(cat "$TEST_TMP_DIR/exit-worker.pid" 2>/dev/null || true)"
worker_alive=false
[[ -n "$exit_worker" ]] && kill -0 "$exit_worker" 2>/dev/null && worker_alive=true
if [[ "$rc" == 3 && -n "$exit_worker" && "$worker_alive" == false && ! -e "$RESULTS_DIR/.codex-exit-worker.claim" ]]; then
    test_pass
else
    test_fail "abnormal exit released a claim while its worker ran, exit=$rc worker_alive=$worker_alive"
fi
[[ "$worker_alive" == false ]] || kill "$exit_worker" 2>/dev/null || true

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

for path_form in absolute relative dotted; do
test_case "TERM after $path_form claim publication cannot strand an unregistered claim"
if (
    trap - EXIT
    export OCTOPUS_RUN_ID="claim-publication-$path_form"
    if [[ "$path_form" != absolute ]]; then
        cd "$TEST_TMP_DIR"
        RESULTS_DIR=relative-results
        mkdir -p "$RESULTS_DIR"
        if [[ "$path_form" == dotted ]]; then RESULTS_DIR=relative-results/../relative-results; fi
    fi
    rm -f "$TEST_TMP_DIR/interrupted-spawn" "$TEST_TMP_DIR/publication-retry"
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
[[ "$rc" == 143 && ! -e "$TEST_TMP_DIR/interrupted-spawn" && -e "$TEST_TMP_DIR/publication-retry" ]] &&
   [[ ! -e "$RESULTS_DIR/.codex-publish-interrupt.claim" ]]
); then test_pass
else test_fail "interrupted publication blocked retry for $path_form results"; fi
done

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

test_case "a spawn that records running then fails cancels only its own seat and permits retry"
export OCTOPUS_RUN_ID=spawn-admission-failure
write_agent_status codex running 1 0 '' 0 "$RESULTS_DIR/codex-other.md" researcher spawn-other
spawn_agent_capture_pid() {
    write_agent_status "$1" running 1 0 '' 0 "$RESULTS_DIR/$1-$3.md" researcher "spawn-$3"
    printf '%s\n' "$3" >> "$TEST_TMP_DIR/spawn-attempts"
    return 74
}
printf '{"tasks":[{"id":"admission-failed","agent":"codex","prompt":"inert"}]}' > "$TEST_TMP_DIR/tasks.json"
for _ in 1 2; do
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/admission-failure.log" 2>&1 || true
done
if [[ -f "$TEST_TMP_DIR/spawn-attempts" && "$(wc -l < "$TEST_TMP_DIR/spawn-attempts")" -eq 2 ]] &&
   jq -e '.agents | any(.seat_id == "spawn-admission-failed" and .status == "cancelled") and
       any(.seat_id == "spawn-other" and .status == "running")' \
       "$WORKSPACE_DIR/runs/$OCTOPUS_RUN_ID/agents.json" >/dev/null; then
    test_pass
else test_fail "failed admission left its seat running or cancelled an unrelated seat"; fi

test_case "fallback and Python claim publication cannot admit two owners"
if python3 "$PROJECT_ROOT/tests/unit/test-output-claim-races.py"; then test_pass
else test_fail "controlled claim publication interleavings admitted two owners"; fi

parent_fixture="$TEST_TMP_DIR/parent-admission-fixture"
printf 'parent-owned fixture\n' > "$parent_fixture"

test_case "real spawn admission rejects a reused durable seat without deleting its artifacts"
if (
    trap - EXIT
    source "$PROJECT_ROOT/scripts/lib/spawn.sh"
    export OCTOPUS_RUN_ID=durable-retry-artifacts
    SUPPORTS_WORKTREE_HOOKS=false SUPPORTS_FORK_CONTEXT=false
    classify_task() { echo implementation; }
    get_role_for_context() { echo implementer; }
    match_routing_rule() { :; }
    # Exercise the actual capture/spawn/contract path. Replanning must fail
    # before any provider command is constructed, on both old and fixed code.
    get_agent_command() { touch "$TEST_TMP_DIR/unexpected-provider"; return 1; }
    octo_spawn_contract_plan durable-retry codex '' '' parallel implementer
    run_contract_transition spawn-durable-retry failed reason=inert-fixture
    saved="$RESULTS_DIR/codex-durable-retry.md"
    marker="$WORKSPACE_DIR/.octo/agents/durable-retry.done"
    mkdir -p "$(dirname "$marker")"
    printf 'saved answer\n' > "$saved"
    printf '74\n' > "$marker"
    write_agent_status codex failed 1 0 fixture 0 "$saved" implementer spawn-durable-retry
    printf '{"tasks":[{"id":"durable-retry","agent":"codex","prompt":"inert"}]}' > "$TEST_TMP_DIR/tasks.json"
    rm -f "$TEST_TMP_DIR/unexpected-provider"
    # First prove the real spawn admission rejects this exact seat.
    spawn_agent_capture_pid codex inert durable-retry implementer parallel >/dev/null 2>&1 && exit 1
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/durable-retry.log" 2>&1 && exit 1
    [[ "$(cat "$saved")" == 'saved answer' && "$(cat "$marker")" == 74 &&
       ! -e "$TEST_TMP_DIR/unexpected-provider" ]] &&
    jq -e '.results[0].reason == "contract-seat-unavailable"' "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null
); then test_pass
else test_fail "rejected durable retry deleted saved artifacts or dispatched a provider"; fi

test_case "concurrent dispatchers of one durable seat retire artifacts only after winning admission"
if (
    trap - EXIT
    source "$PROJECT_ROOT/scripts/lib/spawn.sh"
    export OCTOPUS_RUN_ID=concurrent-admission
    AVAILABLE_AGENTS='codex claude'
    mkdir -p "$RESULTS_DIR"
    for agent in codex claude; do
        printf 'saved %s answer\n' "$agent" > "$RESULTS_DIR/$agent-shared.md"
        printf '{"tasks":[{"id":"shared","agent":"%s","prompt":"inert"}]}' "$agent" > "$TEST_TMP_DIR/$agent-shared.json"
    done
    # Hold the first dispatcher where it retires its saved answer, so the
    # second checks admission before either has planned the shared seat.
    rm() {
        if [[ "${PAUSE_RETIREMENT:-}" == 1 && " $* " == *" $RESULTS_DIR/claude-shared.md "* ]]; then
            : > "$TEST_TMP_DIR/retirement-paused"
            while [[ ! -e "$TEST_TMP_DIR/retirement-resume" ]]; do sleep 0.05; done
        fi
        command rm "$@"
    }
    spawn_agent_capture_pid() {
        octo_spawn_contract_plan "$3" "$1" '' '' parallel implementer || return 74
        : > "$TEST_TMP_DIR/admitted-$1"
        return 74
    }
    (
        trap - EXIT
        PAUSE_RETIREMENT=1
        parallel_execute "$TEST_TMP_DIR/claude-shared.json"
    ) > "$TEST_TMP_DIR/first-admission.log" 2>&1 &
    first=$!
    for _ in $(seq 1 200); do [[ -e "$TEST_TMP_DIR/retirement-paused" ]] && break; sleep 0.05; done
    paused=false
    [[ -e "$TEST_TMP_DIR/retirement-paused" ]] && paused=true
    parallel_execute "$TEST_TMP_DIR/codex-shared.json" > "$TEST_TMP_DIR/second-admission.log" 2>&1 || true
    : > "$TEST_TMP_DIR/retirement-resume"
    wait "$first" || true
    admitted=0 lost=""
    for agent in codex claude; do
        if [[ -e "$TEST_TMP_DIR/admitted-$agent" ]]; then
            admitted=$((admitted + 1))
        elif [[ "$(cat "$RESULTS_DIR/$agent-shared.md" 2>/dev/null)" != "saved $agent answer" ]]; then
            lost="$lost $agent"
        fi
    done
    [[ "$paused" == true && "$admitted" == 1 && -z "$lost" ]] || {
        echo "paused=$paused admitted=$admitted lost=${lost:-none}" >&2
        exit 1
    }
); then test_pass
else test_fail "a concurrent dispatcher deleted its saved answer before its seat was rejected"; fi

test_case "parallel admission recovers an interrupted first contract append"
if (
    trap - EXIT
    source "$PROJECT_ROOT/scripts/lib/spawn.sh"
    export OCTOPUS_RUN_ID=recovery-admission
    ledger="$(octo_run_contract_ledger_path)"
    mkdir -p "$(dirname "$ledger")"
    backup="${ledger}.rollback.fixture"
    : > "$backup"
    printf 'false\t%s\n' "$backup" > "${ledger}.recovery"
    printf '{"seat_id":' > "$ledger"
    mkdir -p "$RESULTS_DIR"
    saved="$RESULTS_DIR/codex-fresh.md"
    printf 'stale answer\n' > "$saved"
    rm -f "$TEST_TMP_DIR/recovered-spawn"
    spawn_agent_capture_pid() {
        # The real contract writer must see the same recovered state.
        octo_spawn_contract_plan "$3" "$1" '' '' parallel implementer || return 74
        touch "$TEST_TMP_DIR/recovered-spawn"
        return 74
    }
    AVAILABLE_AGENTS=codex
    printf '{"tasks":[{"id":"fresh","agent":"codex","prompt":"inert"}]}' > "$TEST_TMP_DIR/tasks.json"
    parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/recovery-admission.log" 2>&1 && exit 1
    [[ -e "$TEST_TMP_DIR/recovered-spawn" && ! -e "${ledger}.recovery" && ! -e "$saved" ]] &&
    jq -e '.results[0].reason == "failed-spawn"' "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null &&
    jq -e '.seat_id == "spawn-fresh" and .transition == "planned"' "$ledger" >/dev/null
); then test_pass
else test_fail "recoverable contract append blocked fresh admission"; fi

for recovery_case in existing missing-backup malformed; do
    test_case "contract admission preserves artifacts for $recovery_case state"
    if (
        trap - EXIT
        source "$PROJECT_ROOT/scripts/lib/spawn.sh"
        export OCTOPUS_RUN_ID="recovery-preserve-$recovery_case"
        ledger="$(octo_run_contract_ledger_path)"
        mkdir -p "$(dirname "$ledger")" "$RESULTS_DIR" "$WORKSPACE_DIR/.octo/agents"
        saved="$RESULTS_DIR/codex-recover.md"
        marker="$WORKSPACE_DIR/.octo/agents/recover.done"
        printf 'saved answer\n' > "$saved"
        printf '74\n' > "$marker"
        case "$recovery_case" in
            existing)
                octo_spawn_contract_plan recover codex '' '' parallel implementer || exit 1
                backup="${ledger}.rollback.fixture"
                cp "$ledger" "$backup"
                printf 'true\t%s\n' "$backup" > "${ledger}.recovery"
                printf '{"seat_id":' >> "$ledger"
                ;;
            missing-backup)
                printf 'true\t%s\n' "${ledger}.rollback.missing" > "${ledger}.recovery"
                ;;
            malformed) printf '{"seat_id":' > "$ledger" ;;
        esac
        rm -f "$TEST_TMP_DIR/unsafe-recovery-spawn"
        spawn_agent_capture_pid() { touch "$TEST_TMP_DIR/unsafe-recovery-spawn"; return 74; }
        AVAILABLE_AGENTS=codex
        printf '{"tasks":[{"id":"recover","agent":"codex","prompt":"inert"}]}' > "$TEST_TMP_DIR/tasks.json"
        parallel_execute "$TEST_TMP_DIR/tasks.json" > "$TEST_TMP_DIR/preserve-$recovery_case.log" 2>&1 && exit 1
        [[ ! -e "$TEST_TMP_DIR/unsafe-recovery-spawn" && "$(cat "$saved")" == 'saved answer' &&
           "$(cat "$marker")" == 74 ]] &&
        jq -e '.results[0].reason == "contract-seat-unavailable"' "$WORKSPACE_DIR/state/parallel-report.json" >/dev/null
    ); then test_pass
    else test_fail "contract admission lost artifacts or dispatched for $recovery_case"; fi
done

test_case "admission subshells preserve the parent test workspace"
if [[ -f "$parent_fixture" ]]; then
    test_pass
else
    test_fail "an admission subshell removed the parent-owned fixture"
    mkdir -p "$TEST_TMP_DIR"
fi

holder_root="$(mktemp -d "$TEST_TMP_DIR/holder.XXXXXX")"
printf '{"tasks":[{"id":"holder","agent":"codex","prompt":"inert"}]}' > "$holder_root/holder-tasks.json"
for nesting in direct subshell; do
    test_case "a seat reservation names the $nesting dispatcher's process"
    rm -f "$holder_root/holder-recorded" "$holder_root/holder-expected"
    bash -c '
        lib_root="$1" tmp="$2" nesting="$3"
        source "$lib_root/scripts/lib/agent-spec.sh"
        source "$lib_root/scripts/lib/error-tracking.sh"
        source "$lib_root/scripts/lib/parallel.sh"
        source "$lib_root/scripts/lib/run-contract.sh"
        log() { :; }
        aggregate_results() { :; }
        run_contract_reserve_seat() { printf "%s\n" "$2" > "$tmp/holder-recorded"; return 1; }
        export OCTOPUS_RUN_ID="holder-$nesting" WORKSPACE_DIR="$tmp/workspace"
        RESULTS_DIR="$tmp/results" AVAILABLE_AGENTS=codex MAX_PARALLEL=1
        SUPPORTS_DISABLE_CRON_ENV=false DRY_RUN=false TIMEOUT=1 GREEN="" NC=""
        if [[ "$nesting" == subshell ]]; then
            ( parallel_execute "$tmp/holder-tasks.json" ) &
            printf "%s\n" "$!" > "$tmp/holder-expected"
            wait "$!"
        else
            parallel_execute "$tmp/holder-tasks.json"
        fi
    ' _ "${AGGREGATION_LIB_ROOT:-$PROJECT_ROOT}" "$holder_root" "$nesting" \
        > "$holder_root/holder-$nesting.log" 2>&1 &
    dispatcher=$!
    [[ "$nesting" == subshell ]] || printf '%s\n' "$dispatcher" > "$holder_root/holder-expected"
    wait "$dispatcher" || true
    if [[ -s "$holder_root/holder-recorded" &&
          "$(cat "$holder_root/holder-recorded")" == "$(cat "$holder_root/holder-expected")" ]]; then
        test_pass
    else
        test_fail "holder $(cat "$holder_root/holder-recorded" 2>/dev/null) is not dispatcher $(cat "$holder_root/holder-expected")"
    fi
done
rm -rf "$holder_root"

test_summary
