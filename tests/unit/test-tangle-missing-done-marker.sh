#!/usr/bin/env bash
# Regression checks for tangle wait loop recovery when a wrapper exits without a .done marker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle missing done marker recovery"

# These tests exercise tangle dispatch/validation behavior, not contextual review.
export OCTOPUS_TANGLE_CODE_REVIEW=false
export OCTOPUS_TANGLE_RUN_WORKTREE=false

WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
rm -rf "$TEST_TMP_DIR"
mkdir -p "$TEST_TMP_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

source "$WORKFLOWS"

CYAN=""
MAGENTA=""
GREEN=""
YELLOW=""
RED=""
NC=""
TMUX_MODE=false
OCTOPUS_TANGLE_MISSING_MARKER_GRACE=0
DRY_RUN=false
SUPPORTS_PARALLEL_FILE_SAFETY=false
RESULTS_DIR="$TEST_TMP_DIR/results"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
PID_FILE="$WORKSPACE_DIR/pids"
LOG_CAPTURE_FILE="$TEST_TMP_DIR/tangle.log"
DATE_COUNTER_FILE="$TEST_TMP_DIR/date-counter"
SLEEP_COUNTER_FILE="$TEST_TMP_DIR/sleep-counter"
ACTIVE_ROOT_PID_FILE="$TEST_TMP_DIR/active-root.pid"
ACTIVE_ROOT_RELEASE_FILE="$TEST_TMP_DIR/active-root.release"
ACTIVE_ROOT_COMPLETED_FILE="$TEST_TMP_DIR/active-root.completed"
FIXTURE_MODE="dead"
DATE_MODE="constant"
mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR/.octo/agents"

log() {
    printf '%s %s\n' "${1:-}" "${2:-}" >> "$LOG_CAPTURE_FILE"
}
octopus_phase_banner() { :; }
design_review_ceremony() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
validate_tangle_results() { :; }
run_agent_sync() {
    printf '%s\n' "1. [CODING] failed marker task. Files: scripts/lib/workflows.sh"
}
spawn_agent_capture_pid() {
    local task_id="$3"
    cat > "$RESULTS_DIR/codex-${task_id}.md" <<EOF
# Agent: codex
# Task ID: $task_id
# Role: implementer
# Prompt: failed marker task
# Started: test

## Output
EOF
    if [[ "$FIXTURE_MODE" == "active-root" ]]; then
        bash -c '
            while [[ ! -e "$1" ]]; do :; done
            printf "0\n" > "$2"
            : > "$3"
        ' _ "$ACTIVE_ROOT_RELEASE_FILE" "$WORKSPACE_DIR/.octo/agents/${task_id}.done" \
            "$ACTIVE_ROOT_COMPLETED_FILE" \
            >/dev/null 2>&1 &
        local active_root_pid="$!"
        printf '%s\n' "$active_root_pid" > "$ACTIVE_ROOT_PID_FILE"
        printf '%s:%s:%s\n' "$active_root_pid" "codex" "$task_id" >> "$PID_FILE"
        printf '%s\n' "$active_root_pid"
        return 0
    fi
    # Use a numeric PID outside the platform range. A real reaped PID can be
    # recycled immediately by the test's own ps/date helpers, making a dead
    # worker look live and turning cleanup into a signal against the fixture.
    printf '%s\n' "2147480000"
}
sleep() {
    local count
    mkdir -p "$(dirname "$SLEEP_COUNTER_FILE")"
    [[ -f "$SLEEP_COUNTER_FILE" ]] || printf '0' > "$SLEEP_COUNTER_FILE"
    count=$(<"$SLEEP_COUNTER_FILE")
    count=$((count + 1))
    printf '%s' "$count" > "$SLEEP_COUNTER_FILE"
    if [[ "$FIXTURE_MODE" == "active-root" && $count -eq 1 ]]; then
        : > "$ACTIVE_ROOT_RELEASE_FILE"
        command sleep 0.1
    fi
    if [[ $count -gt 5 ]]; then
        # Do not let a regression hang CI forever. Force a completion marker so
        # tangle_develop can return; the assertions below fail via the counter.
        rm -f "$WORKSPACE_DIR/.octo/agents" 2>/dev/null || true
        mkdir -p "$WORKSPACE_DIR/.octo/agents"
        printf '0' > "$WORKSPACE_DIR/.octo/agents/tangle-100-0.done"
        if [[ -s "$ACTIVE_ROOT_PID_FILE" ]]; then
            kill -KILL "$(cat "$ACTIVE_ROOT_PID_FILE")" 2>/dev/null || true
        fi
    fi
}
date() {
    if [[ "${1:-}" == "+%s" ]]; then
        local count
        mkdir -p "$(dirname "$DATE_COUNTER_FILE")"
        [[ -f "$DATE_COUNTER_FILE" ]] || printf '0' > "$DATE_COUNTER_FILE"
        count=$(<"$DATE_COUNTER_FILE")
        count=$((count + 1))
        printf '%s' "$count" > "$DATE_COUNTER_FILE"
        if [[ "$DATE_MODE" == "advancing" ]]; then
            printf '%s\n' "$((100 + count))"
        else
            printf '%s\n' "100"
        fi
        return 0
    fi
    command date "$@"
}

reset_fixture() {
    rm -rf "$RESULTS_DIR" "$WORKSPACE_DIR" "$LOG_CAPTURE_FILE"
    mkdir -p "$RESULTS_DIR" "$WORKSPACE_DIR/.octo/agents"
    printf '0' > "$DATE_COUNTER_FILE"
    printf '0' > "$SLEEP_COUNTER_FILE"
    : > "$ACTIVE_ROOT_PID_FILE"
    rm -f "$ACTIVE_ROOT_RELEASE_FILE"
    rm -f "$ACTIVE_ROOT_COMPLETED_FILE"
    : > "$PID_FILE"
    FIXTURE_MODE="dead"
    DATE_MODE="constant"
}

test_case "dead wrapper writes missing-done-marker and failed status before deadline"
reset_fixture
if tangle_develop "missing marker task" >/dev/null 2>&1; then
    result_file=$(find "$RESULTS_DIR" -maxdepth 1 -type f -name 'codex-tangle-*.md' 2>/dev/null | head -1 || true)
    if [[ "$(grep -c 'finished with status: missing-done-marker' "$LOG_CAPTURE_FILE" || true)" -eq 1 ]] && \
       [[ -n "$result_file" ]] && [[ "$(grep -c '^## Status: FAILED (Missing completion marker)' "$result_file" || true)" -eq 1 ]]; then
        test_pass
    else
        test_fail "dead wrapper did not produce missing-done marker log and failed result status"
    fi
else
    test_fail "tangle_develop failed while handling dead wrapper"
fi

test_case "wait loop records terminal task even when marker write fails"
reset_fixture
rm -rf "$WORKSPACE_DIR/.octo/agents"
printf 'not a directory' > "$WORKSPACE_DIR/.octo/agents"
# tangle_develop is expected to return non-zero when the marker path is unwritable.
# Keep the safety-cap assertion aligned with the sleep() mock above, which
# forces a fallback completion marker after count > 5 to avoid CI hangs.
tangle_develop "unwritable marker task" >/dev/null 2>&1 || true
if [[ "$(<"$SLEEP_COUNTER_FILE")" -le 6 ]] && \
   [[ "$(grep -c "Failed to write missing-done marker" "$LOG_CAPTURE_FILE" || true)" -ge 1 ]]; then
    test_pass
else
    test_fail "wait loop did not terminate when marker write failed"
fi

test_case "live descendant-free provider root can finish without being killed"
reset_fixture
FIXTURE_MODE="active-root"
active_output="$TEST_TMP_DIR/active-root.out"
tangle_develop "active root task" > "$active_output" 2>&1 || true
active_root_pid=$(cat "$ACTIVE_ROOT_PID_FILE" 2>/dev/null || true)
[[ -n "$active_root_pid" ]] && wait "$active_root_pid" 2>/dev/null || true
if [[ -f "$ACTIVE_ROOT_COMPLETED_FILE" ]] \
   && ! grep -q 'stalled-worker' "$LOG_CAPTURE_FILE"; then
    test_pass
else
    kill -KILL "$active_root_pid" 2>/dev/null || true
    test_fail "descendant-free provider root was killed or marked stalled before completion"
fi

test_case "redirected progress prints only when the count changes"
progress_count=$(grep -o 'Progress:' "$active_output" 2>/dev/null | wc -l | tr -d ' ')
if [[ "${progress_count:-0}" -eq 2 ]]; then
    test_pass
else
    test_fail "expected exactly 2 redirected progress lines, found $progress_count"
fi

unset -f date
unset -f sleep

test_summary
