#!/usr/bin/env bash
# Inert regression fixtures for #1163. A virtual clock bounds every wait so a
# regression fails locally instead of leaving CI blocked on a retry worker.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RETRY_SOURCE_ROOT="${1:-$PROJECT_ROOT}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Tangle retry supervision (#1163)"

cat > "$TEST_TMP_DIR/zombie.py" <<'PYWORKER'
import os
import signal
import sys
import time

child = os.fork()
if child == 0:
    os._exit(0)
# Observe completion without reaping, deterministically retaining the zombie.
os.waitid(os.P_PID, child, os.WEXITED | os.WNOWAIT)

def finish(*_):
    os.waitpid(child, 0)
    sys.exit(0)

signal.signal(signal.SIGTERM, finish)
with open(sys.argv[1], "w") as stream:
    stream.write(str(child))
while True:
    time.sleep(0.1)
PYWORKER

retry_fixture() {
    set -euo pipefail
    local scenario="$1" fixture_dir="$TEST_TMP_DIR/$1"
    mkdir -p "$fixture_dir/results" "$fixture_dir/workspace/.octo/agents"
    {
        PLUGIN_DIR="$RETRY_SOURCE_ROOT"
        log() { printf '%s %s\n' "$1" "$2" >> "$fixture_dir/log"; }
        source "$RETRY_SOURCE_ROOT/scripts/lib/agent-utils.sh"
        source "$RETRY_SOURCE_ROOT/scripts/lib/workflows.sh"
        RESULTS_DIR="$fixture_dir/results"
        WORKSPACE_DIR="$fixture_dir/workspace"
        PID_FILE="$WORKSPACE_DIR/pids"
        : > "$PID_FILE"
        printf '0' > "$fixture_dir/ticks"
        SUPPORTS_CONTINUATION=false
        MAX_QUALITY_RETRIES=1
        CYAN="" YELLOW="" NC=""
        FAILED_SUBTASKS='codex:first retry'
        [[ "$scenario" != deadline ]] || FAILED_SUBTASKS+=$'\ncodex:second retry'
        OCTOPUS_TANGLE_DEADLINE=0
        [[ "$scenario" != deadline ]] || OCTOPUS_TANGLE_DEADLINE=1
        OCTOPUS_TANGLE_MISSING_MARKER_GRACE=0
        is_provider_locked() { return 1; }
        search_similar_errors() { printf '0\n'; }
        should_use_agent_teams() { return 1; }
        date() {
            if [[ "${1:-}" == +%s ]]; then
                printf '%s\n' "$((100 + $(<"$fixture_dir/ticks")))"
            else
                command date "$@"
            fi
        }
        sleep() {
            local ticks
            ticks=$(( $(<"$fixture_dir/ticks") + 1 ))
            printf '%s' "$ticks" > "$fixture_dir/ticks"
            if (( ticks > 6 )); then
                log ERROR 'fixture wait exceeded six polls'
                exit 85
            fi
            command sleep 0.02
        }
        spawn_agent_capture_pid() {
            local task_id="$3" worker_pid result="$RESULTS_DIR/$1-$3.md"
            printf '%s:%s:%s\n' "$task_id" "$4" "$5" >> "$fixture_dir/dispatch"
            printf '# Agent: codex\n# Task ID: %s\n# Role: implementer\n\n## Output\npartial output retained\n' "$task_id" > "$result"
            if [[ "$scenario" == deadline && "$task_id" == *-0 ]]; then
                printf '\n## Status: SUCCESS\n' >> "$result"
                printf '0\n' > "$WORKSPACE_DIR/.octo/agents/$task_id.done"
                printf '2147480000\n'
                return
            fi
            if [[ "$scenario" == zombie ]]; then
                python3 "$TEST_TMP_DIR/zombie.py" "$fixture_dir/zombie.pid" >/dev/null 2>&1 &
                local zombie_parent=$!
                printf '%s\n' "$zombie_parent" >> "$fixture_dir/owned-pids"
                local tries=0
                while [[ ! -s "$fixture_dir/zombie.pid" && "$tries" -lt 200 ]]; do
                    command sleep 0.01
                    tries=$((tries + 1))
                done
                [[ -s "$fixture_dir/zombie.pid" ]] || return 1
                worker_pid=$(<"$fixture_dir/zombie.pid")
                kill -0 "$worker_pid" || return 1
                [[ "$(ps -o stat= -p "$worker_pid")" == *Z* ]] || return 1
                # No marker, but a completed artifact must be preserved/reconciled.
                printf '\n## Status: SUCCESS\n' >> "$result"
            else
                bash -c '
                    trap "" TERM
                    (
                        trap "" TERM
                        while [[ ! -e "$2" ]]; do sleep 0.05; done
                        : > "$3"
                    ) &
                    printf "%s\n" "$!" > "$1"
                    wait
                ' _ "$fixture_dir/child.pid" "$fixture_dir/release" "$fixture_dir/late-write" >/dev/null 2>&1 &
                worker_pid=$!
                printf '%s\n' "$worker_pid" >> "$fixture_dir/owned-pids"
                local tries=0
                while [[ ! -s "$fixture_dir/child.pid" && "$tries" -lt 200 ]]; do
                    command sleep 0.01
                    tries=$((tries + 1))
                done
                [[ -s "$fixture_dir/child.pid" ]] || return 1
                cat "$fixture_dir/child.pid" >> "$fixture_dir/owned-pids"
                octopus_pid_register "$worker_pid" "$1" "$task_id" >/dev/null
                if [[ "$scenario" == spawn-failure ]]; then return 1; fi
                if [[ "$scenario" == signal ]]; then kill -TERM "$$"; fi
            fi
            printf '%s\n' "$worker_pid"
        }
        trap ':' INT
        trap ':' TERM
        local before_int before_term
        before_int=$(trap -p INT)
        before_term=$(trap -p TERM)
        local retry_rc=0
        retry_failed_subtasks retry-fixture 1 || retry_rc=$?
        if [[ "$scenario" == spawn-failure ]]; then
            [[ "$retry_rc" != 0 && -n "$FAILED_SUBTASKS" ]] || exit 89
        else
            [[ "$retry_rc" == 0 && -z "$FAILED_SUBTASKS" ]] || exit 86
        fi
        [[ "$(trap -p INT)" == "$before_int" && "$(trap -p TERM)" == "$before_term" ]] || exit 87
        [[ -z "${OCTOPUS_ACTIVE_TANGLE_TASK_GROUP:-}" ]] || exit 88
        return "$retry_rc"
    } > "$fixture_dir/output" 2>&1
}

export RETRY_SOURCE_ROOT TEST_TMP_DIR
export -f retry_fixture
run_fixture() { bash -c 'retry_fixture "$1"' _ "$1"; }

cleanup_fixture() {
    local fixture_dir="$1" pid
    [[ -f "$fixture_dir/owned-pids" ]] || return 0
    while read -r pid; do
        kill -TERM "$pid" 2>/dev/null || true
    done < "$fixture_dir/owned-pids"
    command sleep 0.1
    while read -r pid; do
        tangle_process_is_active_non_zombie "$pid" && kill -KILL "$pid" 2>/dev/null || true
    done < "$fixture_dir/owned-pids"
    rm -f "$fixture_dir/owned-pids"
}
source "$PROJECT_ROOT/scripts/lib/workflows.sh"
cleanup_retry_fixtures() {
    local scenario
    for scenario in deadline zombie spawn-failure signal; do
        cleanup_fixture "$TEST_TMP_DIR/$scenario"
    done
    cleanup_test_environment
}
trap cleanup_retry_fixtures EXIT


test_case "retry deadline kills the registered worker tree and preserves a successful sibling"
fixture_rc=0
run_fixture deadline || fixture_rc=$?
fixture_dir="$TEST_TMP_DIR/deadline"
: > "$fixture_dir/release"
command sleep 0.15
all_dead=true
[[ -f "$fixture_dir/owned-pids" ]] || : > "$fixture_dir/owned-pids"
while read -r pid; do
    if tangle_process_is_active_non_zombie "$pid"; then all_dead=false; fi
done < "$fixture_dir/owned-pids"
if [[ "$fixture_rc" == 0 && "$all_dead" == true ]] \
   && [[ ! -e "$fixture_dir/late-write" ]] \
   && [[ "$(cat "$fixture_dir/workspace/.octo/agents/tangle-retry-fixture-retry1-1.done" 2>/dev/null || true)" == timeout ]] \
   && [[ "$(cat "$fixture_dir/workspace/.octo/agents/tangle-retry-fixture-retry1-0.done" 2>/dev/null || true)" == 0 ]] \
   && grep -q '## Status: SUCCESS' "$fixture_dir/results/codex-tangle-retry-fixture-retry1-0.md" \
   && grep -q 'partial output retained' "$fixture_dir/results/codex-tangle-retry-fixture-retry1-1.md" \
   && grep -q '^## Status: TIMEOUT - PARTIAL RESULTS' "$fixture_dir/results/codex-tangle-retry-fixture-retry1-1.md" \
   && ! grep -q 'tangle-retry-fixture-retry1-1' "$fixture_dir/workspace/pids"; then
    test_pass
else
    test_fail "bounded cleanup failed: rc=$fixture_rc, dead=$all_dead, output=$(cat "$fixture_dir/output")"
fi
cleanup_fixture "$fixture_dir"

test_case "unreaped zombie completes retry wait without a deadline and keeps its successful result"
if [[ "$(uname -s)" != Linux ]]; then
    test_skip 'deterministic unreaped-zombie fixture uses Linux waitid'
else
    fixture_rc=0
    run_fixture zombie || fixture_rc=$?
    fixture_dir="$TEST_TMP_DIR/zombie"
    if [[ "$fixture_rc" == 0 ]] \
       && kill -0 "$(cat "$fixture_dir/zombie.pid")" 2>/dev/null \
       && [[ "$(ps -o stat= -p "$(cat "$fixture_dir/zombie.pid")")" == *Z* ]] \
       && [[ "$(cat "$fixture_dir/workspace/.octo/agents/tangle-retry-fixture-retry1-0.done" 2>/dev/null || true)" == 0 ]] \
       && grep -q 'Reconciled late successful result' "$fixture_dir/log"; then
        test_pass
    else
        test_fail "zombie retry was not completed/reconciled: rc=$fixture_rc, output=$(cat "$fixture_dir/output")"
    fi
    cleanup_fixture "$fixture_dir"
fi

test_case "retry spawn failure cleans the ledger handoff race and keeps failed tasks for reevaluation"
fixture_rc=0
run_fixture spawn-failure || fixture_rc=$?
fixture_dir="$TEST_TMP_DIR/spawn-failure"
all_dead=true
[[ -f "$fixture_dir/owned-pids" ]] || : > "$fixture_dir/owned-pids"
while read -r pid; do
    if tangle_process_is_active_non_zombie "$pid"; then all_dead=false; fi
done < "$fixture_dir/owned-pids"
if [[ "$fixture_rc" == 1 && "$all_dead" == true ]] \
   && ! grep -q 'tangle-retry-fixture-' "$fixture_dir/workspace/pids"; then
    test_pass
else
    test_fail "spawn failure did not clean registered providers: rc=$fixture_rc, dead=$all_dead"
fi
cleanup_fixture "$fixture_dir"

test_case "TERM during retry PID handoff cancels the worker tree and returns 143"
fixture_rc=0
run_fixture signal || fixture_rc=$?
fixture_dir="$TEST_TMP_DIR/signal"
all_dead=true
[[ -f "$fixture_dir/owned-pids" ]] || : > "$fixture_dir/owned-pids"
while read -r pid; do
    if tangle_process_is_active_non_zombie "$pid"; then all_dead=false; fi
done < "$fixture_dir/owned-pids"
if [[ "$fixture_rc" == 143 && "$all_dead" == true ]] \
   && [[ "$(cat "$fixture_dir/workspace/.octo/agents/tangle-retry-fixture-retry1-0.done" 2>/dev/null || true)" == cancelled ]] \
   && ! grep -q 'tangle-retry-fixture-' "$fixture_dir/workspace/pids"; then
    test_pass
else
    test_fail "retry cancellation failed: rc=$fixture_rc, dead=$all_dead, output=$(cat "$fixture_dir/output")"
fi
cleanup_fixture "$fixture_dir"

test_case "CLI retries retain Tangle implementer dispatch for the existing adaptive stall watchdog"
if grep -Fxq 'tangle-retry-fixture-retry1-1:implementer:tangle' "$TEST_TMP_DIR/deadline/dispatch"; then
    test_pass
else
    test_fail "retry dispatch changed the phase/role that selects provider stall supervision"
fi

test_summary
