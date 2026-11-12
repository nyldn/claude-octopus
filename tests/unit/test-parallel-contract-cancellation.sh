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

# Bash 3.2 has no BASHPID. Exercise that contract on newer shells too.
unset BASHPID

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
        committed)
            # The worker commits its answer, then dies before its status row.
            printf '## Output\ncommitted answer\n## Status: SUCCESS\n' > "$output"
            octo_run_contract_finish_background "$seat" success "$output" "" "" 0 1 "" ;;
        recovery)
            # The worker is stopped mid-append, leaving a valid recovery marker.
            local ledger
            ledger="$(octo_run_contract_ledger_path)"
            cp "$ledger" "$ledger.rollback.fixture"
            printf 'true\t%s\n' "$ledger.rollback.fixture" > "$(octo_run_contract_recovery_path)"
            printf '{"seat_id":' >> "$ledger" ;;
    esac
    write_agent_status "$1" running 1 0 '' 0 "$output" researcher "$seat"
    if [[ "$OCTOPUS_RUN_ID" == signal ]]; then
        # Signal during PID handoff, after the durable running record exists.
        kill -TERM "$(sh -c 'printf "%s\n" "$PPID"')"
    fi
    (exit 74) &
    printf '%s\n' "$!"
}
printf '{"tasks":[{"id":"stopped","agent":"codex","prompt":"inert"}]}' > "$TEST_TMP_DIR/tasks.json"

for scenario in worker signal terminal native committed recovery; do
    test_case "$scenario cleanup preserves durable execution truth"
    export OCTOPUS_RUN_ID="$scenario"
    if (trap - EXIT; parallel_execute "$TEST_TMP_DIR/tasks.json") > "$TEST_TMP_DIR/$scenario.log" 2>&1; then rc=0; else rc=$?; fi
    # Read after a locked operation recovers any interrupted append.
    run_contract_snapshot >/dev/null 2>&1 || true
    transition="$(run_contract_latest_transition spawn-stopped)" || transition=unreadable
    status="$(jq -r '.agents[0].status' "$WORKSPACE_DIR/runs/$scenario/agents.json")"
    case "$scenario" in
        worker) expected=cancelled; expected_status=cancelled; expected_rc=1 ;;
        signal) expected=cancelled; expected_status=cancelled; expected_rc=143 ;;
        terminal) expected=failed; expected_status=failed; expected_rc=1 ;;
        native) expected=running; expected_status=running; expected_rc=1 ;;
        committed) expected=contributed; expected_status=ok; expected_rc=1 ;;
        recovery) expected=cancelled; expected_status=cancelled; expected_rc=1 ;;
    esac
    # Only a committed contribution remains an output offered to synthesis.
    offered="$(agent_status_output_files '' "$(jq -nc --arg file "$RESULTS_DIR/codex-stopped.md" \
        '[{id:"stopped",output_file:$file}]')")"
    expected_offered=""
    [[ "$scenario" != committed ]] || expected_offered="$RESULTS_DIR/codex-stopped.md"
    if [[ "$transition" == "$expected" && "$status" == "$expected_status" && "$rc" == "$expected_rc" &&
          "$offered" == "$expected_offered" ]]; then
        test_pass
    else
        test_fail "durable=$transition summary=$status exit=$rc offered=${offered:-none}; expected $expected/$expected_status/$expected_rc"
    fi
done
test_summary
