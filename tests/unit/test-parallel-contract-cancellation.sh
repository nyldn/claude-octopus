#!/usr/bin/env bash
# Cleanup must agree with durable execution state without cancelling native seats.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Parallel contract cancellation"
source "$PROJECT_ROOT/scripts/lib/error-tracking.sh"
source "$PROJECT_ROOT/scripts/lib/run-contract.sh"
source "$PROJECT_ROOT/scripts/lib/parallel.sh"
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
RESULTS_DIR="$WORKSPACE_DIR/results"
mkdir -p "$RESULTS_DIR"
AVAILABLE_AGENTS=codex MAX_PARALLEL=1 SUPPORTS_DISABLE_CRON_ENV=false DRY_RUN=false
# jq 1.5 supports slurpfile, but rejects rawfile. Retain real filter execution.
jq() {
    local arg
    for arg in "$@"; do
        [[ "$arg" != --rawfile ]] || return 2
    done
    command jq "$@"
}
log() { :; }
aggregate_results() { :; }
render_agent_summary() { :; }
is_provider_available() { return 0; }
octo_quota_is_dead() { return 1; }

# Exercise real contract persistence; only provider dispatch is inert.
spawn_agent_capture_pid() {
    local seat="spawn-$3" output="$RESULTS_DIR/$1-$3.md"
    run_contract_transition "$seat" planned requested_provider=codex
    run_contract_transition "$seat" starting resolved_provider=codex resolved_model=fixture
    run_contract_transition "$seat" authenticated
    run_contract_transition "$seat" running "output_file=$output"
    case "$OCTOPUS_RUN_ID" in
        terminal) run_contract_transition "$seat" failed reason=original-failure ;;
        native)
            write_agent_status "$1" running 1 0 "Dispatched via Agent Teams" 0 "$output" researcher "$seat"
            return 1 ;;
    esac
    write_agent_status "$1" running 1 0 '' 0 "$output" researcher "$seat"
    if [[ "$OCTOPUS_RUN_ID" == signal ]]; then
        # Signal during PID handoff, after the durable running record exists.
        kill -TERM "$BASHPID"
    fi
    (exit 74) &
    printf '%s\n' "$!"
}
printf '{"tasks":[{"id":"stopped","agent":"codex","prompt":"inert"}]}' > "$TEST_TMP_DIR/tasks.json"

for scenario in worker signal terminal native; do
    test_case "$scenario cleanup preserves durable execution truth"
    export OCTOPUS_RUN_ID="$scenario"
    if (trap - EXIT; parallel_execute "$TEST_TMP_DIR/tasks.json") > "$TEST_TMP_DIR/$scenario.log" 2>&1; then rc=0; else rc=$?; fi
    transition="$(run_contract_latest_transition spawn-stopped)"
    status="$(jq -r '.agents[0].status' "$WORKSPACE_DIR/runs/$scenario/agents.json")"
    case "$scenario" in
        worker) expected=cancelled; expected_status=cancelled; expected_rc=1 ;;
        signal) expected=cancelled; expected_status=cancelled; expected_rc=143 ;;
        terminal) expected=failed; expected_status=cancelled; expected_rc=1 ;;
        native) expected=running; expected_status=running; expected_rc=1 ;;
    esac
    if [[ "$transition" == "$expected" && "$status" == "$expected_status" && "$rc" == "$expected_rc" ]]; then
        test_pass
    else
        test_fail "durable=$transition summary=$status exit=$rc; expected $expected/$expected_status/$expected_rc"
    fi
done
test_summary
