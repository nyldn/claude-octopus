#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Orchestrator review regressions"
ORCHESTRATOR="$PROJECT_ROOT/scripts/orchestrate.sh"
log() { :; }

source "$PROJECT_ROOT/scripts/lib/pid-ledger.sh"
eval "$(sed -n '/^kill_agents() {/,/^}/p' "$ORCHESTRATOR")"
PID_FILE="$TEST_TMP_DIR/pids"
cancelled="$TEST_TMP_DIR/cancelled"
review_kill_process_tree_frozen() { printf '%s:%s\n' "$1" "${2:-}" >> "$cancelled"; }

test_case "unverifiable legacy registrations never reach the signal helper"
printf '%s:codex:legacy\n' "$$" > "$PID_FILE"
kill_agents legacy
if [[ ! -e "$cancelled" && ! -s "$PID_FILE" ]]; then test_pass; else test_fail "legacy entry was signalled or retained"; fi

test_case "valid registration is retired without removing another task"
token="$(octopus_pid_register "$$" codex first)"
octopus_pid_register "$$" codex second >/dev/null
kill_agents first
if [[ "$(cat "$cancelled")" == "$$:$token" ]] && grep -q ':second:' "$PID_FILE" && ! grep -q ':first:' "$PID_FILE"; then
    test_pass
else
    test_fail "exact registration retirement failed"
fi

test_case "identity mismatch is rejected before any signal helper call"
rm -f "$cancelled"
printf '%s:codex:stale:not-the-recorded-start-identity\n' "$$" >> "$PID_FILE"
kill_agents stale
if [[ ! -e "$cancelled" ]] && grep -q ':second:' "$PID_FILE" && ! grep -q ':stale:' "$PID_FILE"; then
    test_pass
else
    test_fail "identity mismatch reached signalling or removed a different entry"
fi

test_case "concurrent registration, pruning and retirement retain every active task"
obsolete_token="$(octopus_pid_register "$$" codex obsolete-task)"
retire_token="$(octopus_pid_register "$$" codex retire-target)"
jobs_to_wait=()
for number in 1 2 3 4 5 6 7 8; do
    octopus_pid_register "$$" codex "parallel-$number" >/dev/null &
    jobs_to_wait+=("$!")
done
octopus_pid_prune obsolete- &
jobs_to_wait+=("$!")
octopus_pid_retire "$$" retire-target "$retire_token" &
jobs_to_wait+=("$!")
for job in "${jobs_to_wait[@]}"; do wait "$job"; done
if [[ "$(grep -c ':parallel-' "$PID_FILE")" == 8 ]] && ! grep -q ':obsolete-' "$PID_FILE" \
   && ! grep -q ':retire-target:' "$PID_FILE"; then
    test_pass
else
    test_fail "concurrent updates lost entries or retained a pruned task"
fi

test_case "provider-qualified agent names round-trip without shifting ledger fields"
qualified_token="$(octopus_pid_register "$$" 'codex:gpt-test%3A' qualified)"
qualified_row="$(awk -F: '$3 == "qualified" {print}' "$PID_FILE")"
IFS=: read -r qualified_pid qualified_agent qualified_task recorded_token <<< "$qualified_row"
if [[ "$(octopus_pid_agent_name "$qualified_agent")" == 'codex:gpt-test%3A' && "$recorded_token" == "$qualified_token" ]]; then
    test_pass
else
    test_fail "qualified agent corrupted the ledger columns"
fi
octopus_pid_retire "$$" qualified "$qualified_token"

eval "$(sed -n '/^do_release() {/,/^}/p' "$ORCHESTRATOR")"
SCRIPT_DIR="$TEST_TMP_DIR/release scripts"
mkdir -p "$SCRIPT_DIR"
cat > "$SCRIPT_DIR/release.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RELEASE_CAPTURE"
exit 17
SH
export RELEASE_CAPTURE="$TEST_TMP_DIR/release-args"
DRY_RUN=false
test_case "release requires explicit version and summary without invoking backend"
release_rc=0
do_release >/dev/null 2>&1 || release_rc=$?
if [[ "$release_rc" == 2 && ! -e "$RELEASE_CAPTURE" ]]; then test_pass; else test_fail "argument validation did not stop release"; fi

test_case "release delegates exact arguments and preserves failure status"
release_rc=0
do_release 11.2.1 'Keep the summary intact' || release_rc=$?
if [[ "$release_rc" == 17 && "$(cat "$RELEASE_CAPTURE")" == $'11.2.1\nKeep the summary intact' ]]; then
    test_pass
else
    test_fail "release wrapper lost arguments or exit status"
fi

test_case "dry-run release never invokes backend"
rm -f "$RELEASE_CAPTURE"
DRY_RUN=true
do_release 11.2.1 'Preview only' >/dev/null
if [[ ! -e "$RELEASE_CAPTURE" ]]; then test_pass; else test_fail "dry-run invoked release"; fi

source "$PROJECT_ROOT/scripts/lib/interactive.sh"
for ci_env in CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL CLAUDE_CODE_DISABLE_BACKGROUND_TASKS; do
    test_case "unattended detection survives initialization for $ci_env"
    if (
        unset CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL CLAUDE_CODE_DISABLE_BACKGROUND_TASKS
        export "$ci_env=true"
        CI_MODE=false
        AUTONOMY_MODE=interactive
        # Include top-level assignments so a later reset cannot go unnoticed.
        ci_mode_assignments="$(sed -n '/^CI_MODE=/p' "$ORCHESTRATOR")"
        [[ -n "$ci_mode_assignments" ]] || exit 1
        eval "$ci_mode_assignments"
        init_ci_mode
        [[ "$CI_MODE" == true && "$AUTONOMY_MODE" == autonomous ]]
    ); then test_pass; else test_fail "unattended state was lost"; fi
done
test_case "explicit --ci mode survives without CI environment variables"
if (
    unset CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL CLAUDE_CODE_DISABLE_BACKGROUND_TASKS
    CI_MODE=true
    AUTONOMY_MODE=interactive
    init_ci_mode
    [[ "$CI_MODE" == true && "$AUTONOMY_MODE" == autonomous ]]
); then test_pass; else test_fail "explicit CI mode was lost"; fi

RECOVERY_BLOCK="$(awk '/^    synthesize-probe\)/ {active=1; next} active && /^[[:space:]]*;;$/ {exit} active {print}' "$ORCHESTRATOR")"
export RECOVERY_BLOCK
export RESULTS_DIR="$TEST_TMP_DIR/probe results" LOGS_DIR="$TEST_TMP_DIR/logs"
mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
printf '%s\n' 'A collected result' > "$RESULTS_DIR/codex-probe-12345-0.md"
run_recovery() {
    bash -eo pipefail -c '
        source "$1/scripts/lib/probe-results.sh"
        shift
        log() { :; }
        probe_result_file_is_usable() { [[ -s "$1" ]]; }
        synthesize_probe_results() { printf "synthesized=%s\n" "$1"; }
        eval "$RECOVERY_BLOCK"
    ' _ "$PROJECT_ROOT"
}
test_case "recovery reaches existing results without a marker under errexit"
recovery_rc=0
recovery_output="$(run_recovery 2>&1)" || recovery_rc=$?
if [[ "$recovery_rc" == 0 && "$recovery_output" == *'synthesized=12345'* ]]; then
    test_pass
else
    test_fail "recovery failed ($recovery_rc): $recovery_output"
fi
test_case "empty recovery emits actionable guidance"
rm "$RESULTS_DIR/codex-probe-12345-0.md"
recovery_rc=0
recovery_output="$(run_recovery 2>&1)" || recovery_rc=$?
if [[ "$recovery_rc" == 1 && "$recovery_output" == *'No pending probe results detected'* ]]; then
    test_pass
else
    test_fail "empty recovery exited without guidance ($recovery_rc): $recovery_output"
fi

test_case "worker ownership check consumes a complete job listing under pipefail"
ownership_check="$(sed -n '/if jobs -pr |/s/^[[:space:]]*if \(.*\); then$/\1/p' "$PROJECT_ROOT/scripts/lib/spawn.sh")"
if (
    set -o pipefail
    [[ -n "$ownership_check" ]] || exit 1
    pid="$$"
    jobs() { awk -v target="$pid" 'BEGIN {print target; for (i=0;i<100000;i++) print 0}'; }
    eval "$ownership_check"
); then test_pass; else test_fail "job listing closed early or ownership predicate disappeared"; fi

# Exercise workflow ledger admission with inert signal helpers.
source "$PROJECT_ROOT/scripts/lib/workflows.sh"
review_kill_process_tree_frozen() { printf '%s:%s\n' "$1" "${2:-}" >> "$cancelled"; }
review_kill_descendants_frozen() { :; }
_octopus_probe_terminate_tree() { printf '%s:%s\n' "$1" "${2:-}" >> "$cancelled"; }
WORKSPACE_DIR="$TEST_TMP_DIR/workflow"
RESULTS_DIR="$WORKSPACE_DIR/results"
PID_FILE="$WORKSPACE_DIR/pids"
mkdir -p "$RESULTS_DIR"
waited="$TEST_TMP_DIR/workflow-waited"
wait() { printf '%s\n' "$*" >> "$waited"; return 0; }
for workflow in probe tangle scoped; do
    for registration in legacy mismatch valid memory-mismatch memory-missing; do
        [[ "$workflow" != scoped || "$registration" != memory-* ]] || continue
        test_case "$workflow cancellation admits only verified ledger workers: $registration"
        rm -f "$cancelled" "$waited"
        task="${workflow}-fixture-0"
        [[ "$workflow" != scoped ]] || task="review-r1-fixture-artifact"
        : > "$PID_FILE"
        case "$registration" in
            legacy) printf '%s:codex:%s\n' "$$" "$task" > "$PID_FILE" ;;
            mismatch|memory-mismatch) printf '%s:codex:%s:wrong-identity\n' "$$" "$task" > "$PID_FILE" ;;
            valid) token="$(octopus_pid_register "$$" codex "$task")" ;;
        esac
        case "$workflow" in
            probe)
                OCTOPUS_ACTIVE_PROBE_TASK_GROUP=fixture
                OCTOPUS_ACTIVE_PROBE_PIDS=()
                OCTOPUS_ACTIVE_PROBE_AGENTS=()
                OCTOPUS_ACTIVE_PROBE_TASK_IDS=()
                if [[ "$registration" == memory-* ]]; then
                    OCTOPUS_ACTIVE_PROBE_PIDS=("$$")
                    OCTOPUS_ACTIVE_PROBE_AGENTS=(codex)
                    OCTOPUS_ACTIVE_PROBE_TASK_IDS=("$task")
                fi
                OCTOPUS_ACTIVE_PROBE_SYNTHESIS_PID=""
                OCTOPUS_ACTIVE_PROBE_SYNTHESIS_LAUNCHING=false
                octopus_probe_cancel_active TERM
                ;;
            tangle)
                OCTOPUS_ACTIVE_TANGLE_TASK_GROUP=fixture
                OCTOPUS_ACTIVE_TANGLE_PIDS=()
                OCTOPUS_ACTIVE_TANGLE_AGENTS=()
                OCTOPUS_ACTIVE_TANGLE_TASK_IDS=()
                if [[ "$registration" == memory-* ]]; then
                    OCTOPUS_ACTIVE_TANGLE_PIDS=("$$")
                    OCTOPUS_ACTIVE_TANGLE_AGENTS=(codex)
                    OCTOPUS_ACTIVE_TANGLE_TASK_IDS=("$task")
                fi
                octopus_tangle_cancel_active TERM
                ;;
            scoped) _tangle_review_kill_scoped_ledger_groups artifact ;;
        esac
        if [[ "$registration" == valid && "$(cat "$cancelled" 2>/dev/null)" == "$$:$token" ]] || \
           [[ "$registration" != valid && ! -e "$cancelled" && ! -e "$waited" ]]; then
            test_pass
        else
            test_fail "$workflow admitted an unverified worker or refused a valid identity"
        fi
    done
done

test_case "scoped cancellation failure does not wait on the resumed worker"
rm -f "$waited"
: > "$PID_FILE"
octopus_pid_register "$$" codex review-r1-fixture-failed-cleanup >/dev/null
review_kill_process_tree_frozen() { return 1; }
cleanup_rc=0
_tangle_review_kill_scoped_ledger_groups failed-cleanup || cleanup_rc=$?
if [[ "$cleanup_rc" != 0 && ! -e "$waited" ]]; then
    test_pass
else
    test_fail "scoped cleanup waited or suppressed its failure"
fi

for workflow in probe tangle; do
    test_case "$workflow retains registrations when native cleanup fails"
    rm -f "$waited"
    : > "$PID_FILE"
    task="$workflow-retained-0"
    octopus_pid_register "$$" codex "$task" >/dev/null
    _octopus_probe_terminate_tree() { OCTO_PROCESS_CLEANUP_RESULT=unverified; return 1; }
    if [[ "$workflow" == probe ]]; then
        OCTOPUS_ACTIVE_PROBE_TASK_GROUP=retained
        OCTOPUS_ACTIVE_PROBE_PIDS=()
        OCTOPUS_ACTIVE_PROBE_AGENTS=()
        OCTOPUS_ACTIVE_PROBE_TASK_IDS=()
        octopus_probe_cancel_active TERM || true
    else
        OCTOPUS_ACTIVE_TANGLE_TASK_GROUP=retained
        OCTOPUS_ACTIVE_TANGLE_PIDS=()
        OCTOPUS_ACTIVE_TANGLE_AGENTS=()
        OCTOPUS_ACTIVE_TANGLE_TASK_IDS=()
        octopus_tangle_cancel_active TERM || true
    fi
    if [[ -s "$PID_FILE" && ! -e "$waited" ]]; then
        test_pass
    else
        test_fail "failed cleanup lost the registration or waited on a live worker"
    fi
done

test_summary
