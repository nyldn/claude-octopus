#!/usr/bin/env bash
# Regression coverage for issue #943: intermittent AGY SIGSEGV failures must
# receive one bounded retry, and signal stderr must remain inspectable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "synchronous provider signal retry"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
eval "$(declare -f run_with_timeout | sed '1s/^run_with_timeout/octopus_test_real_run_with_timeout/')"

test_case "retry attempts use a conservative remainder of the original timeout"
if declare -F octopus_sync_attempt_timeout >/dev/null 2>&1 && \
   [[ "$(octopus_sync_attempt_timeout 130 100 0)" == "30" ]] && \
   [[ "$(octopus_sync_attempt_timeout 130 100 1)" == "29" ]] && \
   ! octopus_sync_attempt_timeout 130 129 1 >/dev/null 2>&1 && \
   ! octopus_sync_attempt_timeout 130 130 0 >/dev/null 2>&1; then
    test_pass
else
    test_fail "retry timeout helper can extend or revive an exhausted wall-clock budget"
fi

run_sync_fixture() (
    local provider="$1"
    local fail_count="$2"
    local scenario="${3:-${provider}-${fail_count}}"
    local sync_timeout="${4:-30}"
    local fixture_root="$TEST_TMP_DIR/$scenario"
    local fake_provider="$fixture_root/provider.sh"

    mkdir -p "$fixture_root/results"
    export RESULTS_DIR="$fixture_root/results"
    export ATTEMPT_FILE="$fixture_root/attempts"
    export FAIL_COUNT="$fail_count"

    cat > "$fake_provider" <<'EOF'
#!/usr/bin/env bash
attempt=0
[[ -f "$ATTEMPT_FILE" ]] && attempt="$(cat "$ATTEMPT_FILE")"
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$ATTEMPT_FILE"
if [[ "$attempt" -le "$FAIL_COUNT" ]]; then
    if [[ "${OVERLONG_FIRST_ATTEMPT:-false}" == "true" ]] && [[ "$attempt" -eq 1 ]]; then
        if [[ -n "${OVERLONG_COMPLETION_FILE:-}" ]]; then
            python3 -c '
import pathlib
import sys
import time

time.sleep(float(sys.argv[2]))
pathlib.Path(sys.argv[1]).write_text("completed\\n")
' "$OVERLONG_COMPLETION_FILE" "${OVERLONG_SLEEP:-3}"
        else
            sleep "${OVERLONG_SLEEP:-3}"
        fi
    fi
    printf 'synthetic provider crash attempt %s\n' "$attempt" >&2
    exit 139
fi
printf 'recovered provider output\n'
EOF
    chmod 755 "$fake_provider"

    log() { :; }
    classify_task() { printf 'standard\n'; }
    get_role_for_context() { printf 'reviewer\n'; }
    apply_persona() { printf '%s\n' "$2"; }
    load_earned_skills() { :; }
    build_provider_context() { :; }
    enforce_context_budget() { printf '%s\n' "$1"; }
    get_agent_model() { printf 'fixture-model\n'; }
    estimate_agent_call_cost() { printf '0.000000\n'; }
    check_provider_health() { return 0; }
    record_agent_call() { :; }
    get_agent_command() { printf '%s\n' "$fake_provider"; }
    build_provider_env() { PROVIDER_ENV_ARRAY=(); }
    run_with_timeout() {
        printf '%s\n' "$1" >> "$fixture_root/timeouts"
        if [[ "${ENFORCE_TIMEOUT:-false}" == "true" ]]; then
            octopus_test_real_run_with_timeout "$@"
            return $?
        fi
        shift
        "$@"
    }
    stop_quota_watcher() { :; }
    update_agent_status() { :; }
    octo_estimate_tokens_for_file() { printf '0\n'; }
    classify_agent_output() { printf '%s\n' "${CLASSIFICATION_RESULT:-ok:}"; }
    wrap_cli_output() { printf '%s\n' "$2"; }
    write_agent_status() {
        printf '%s|%s|%s|%s\n' "$1" "$2" "$5" "$7" >> "$fixture_root/statuses"
    }

    if [[ "${CALLER_ERREXIT:-on}" == "off" ]]; then
        set +e
    fi

    OCTOPUS_PERSISTENCE_AVAILABLE=true \
        run_agent_sync "$provider" 'review this change' "$sync_timeout" reviewer council
    local sync_rc=$?
    printf '%s\n' "$-" > "$fixture_root/caller-options-after"
    return "$sync_rc"
)

test_case "AGY exit 139 retries once and records the recovered crash artifact"
agy_output="$(run_sync_fixture agy 1)" && agy_rc=0 || agy_rc=$?
agy_root="$TEST_TMP_DIR/agy-1"
agy_artifact="$(find "$agy_root/results" -maxdepth 1 -name 'sync-failure-*.stderr.log' -print -quit)"
agy_mode="$(stat -c '%a' "$agy_artifact" 2>/dev/null || stat -f '%Lp' "$agy_artifact" 2>/dev/null || true)"
agy_result_artifact="$(awk -F'|' '$1 == "agy" && $2 == "degraded" {print $4}' "$agy_root/statuses" | tail -n 1)"
first_timeout="$(sed -n '1p' "$agy_root/timeouts")"
retry_timeout="$(sed -n '2p' "$agy_root/timeouts")"
if [[ "$agy_rc" -eq 0 ]] && [[ "$(cat "$agy_root/attempts")" == "2" ]] && \
   [[ "$agy_output" == *"recovered provider output"* ]] && \
   [[ "$first_timeout" =~ ^[0-9]+$ ]] && [[ "$retry_timeout" =~ ^[0-9]+$ ]] && \
   [[ "$retry_timeout" -lt "$first_timeout" ]] && \
   [[ -f "$agy_artifact" ]] && grep -q 'synthetic provider crash attempt 1' "$agy_artifact" && \
   [[ "$agy_mode" == "600" ]] && \
   [[ -s "$agy_result_artifact" ]] && grep -q 'recovered provider output' "$agy_result_artifact" && \
   grep -Fq "agy|degraded|Recovered after AGY exit 139|$agy_result_artifact" "$agy_root/statuses"; then
    test_pass
else
    test_fail "AGY retry/artifact contract failed (rc=$agy_rc attempts=$(cat "$agy_root/attempts" 2>/dev/null || echo 0) timeouts=${first_timeout:-missing}/${retry_timeout:-missing} artifact=${agy_artifact:-missing} mode=${agy_mode:-unknown})"
fi

test_case "a second AGY exit 139 fails without a third attempt and retains stderr"
set +e
run_sync_fixture agy 2 >/dev/null 2>&1
terminal_rc=$?
set -e
terminal_root="$TEST_TMP_DIR/agy-2"
terminal_artifact="$(find "$terminal_root/results" -maxdepth 1 -name 'sync-failure-*-attempt-2.stderr.log' -print -quit)"
if [[ "$terminal_rc" -eq 139 ]] && [[ "$(cat "$terminal_root/attempts")" == "2" ]] && \
   [[ -f "$terminal_artifact" ]] && grep -q 'synthetic provider crash attempt 2' "$terminal_artifact" && \
   grep -Fq "agy|failed|Exit code 139|$terminal_artifact" "$terminal_root/statuses"; then
    test_pass
else
    test_fail "terminal AGY crash did not stop after one retry with evidence (rc=$terminal_rc attempts=$(cat "$terminal_root/attempts" 2>/dev/null || echo 0))"
fi

test_case "non-AGY exit 139 is not retried but still preserves signal stderr"
set +e
run_sync_fixture openrouter 1 >/dev/null 2>&1
other_rc=$?
set -e
other_root="$TEST_TMP_DIR/openrouter-1"
other_artifact="$(find "$other_root/results" -maxdepth 1 -name 'sync-failure-*.stderr.log' -print -quit)"
if [[ "$other_rc" -eq 139 ]] && [[ "$(cat "$other_root/attempts")" == "1" ]] && \
   [[ -f "$other_artifact" ]] && grep -q 'synthetic provider crash attempt 1' "$other_artifact"; then
    test_pass
else
    test_fail "non-AGY signal policy regressed (rc=$other_rc attempts=$(cat "$other_root/attempts" 2>/dev/null || echo 0))"
fi

test_case "a recovered crash keeps its artifact when output classification fails"
set +e
CLASSIFICATION_RESULT='failed:Empty output' run_sync_fixture agy 1 classified >/dev/null 2>&1
classified_rc=$?
set -e
classified_root="$TEST_TMP_DIR/classified"
classified_artifact="$(find "$classified_root/results" -maxdepth 1 -name 'sync-failure-*-attempt-1.stderr.log' -print -quit)"
if [[ "$classified_rc" -eq 1 ]] && [[ -f "$classified_artifact" ]] && \
   grep -Fq "agy|failed|Empty output|$classified_artifact" "$classified_root/statuses"; then
    test_pass
else
    test_fail "post-retry classification failure dropped its crash artifact (rc=$classified_rc artifact=${classified_artifact:-missing})"
fi

test_case "recovered crashes preserve an existing degraded classifier reason"
CLASSIFICATION_RESULT='degraded:Partial output' run_sync_fixture agy 1 degraded >/dev/null
degraded_root="$TEST_TMP_DIR/degraded"
degraded_artifact="$(find "$degraded_root/results" -maxdepth 1 -name 'sync-failure-*-attempt-1.stderr.log' -print -quit)"
degraded_result_artifact="$(awk -F'|' '$1 == "agy" && $2 == "degraded" {print $4}' "$degraded_root/statuses" | tail -n 1)"
if [[ -s "$degraded_artifact" ]] && [[ -s "$degraded_result_artifact" ]] && \
   grep -Fq "agy|degraded|Recovered after AGY exit 139; Partial output|$degraded_result_artifact" "$degraded_root/statuses"; then
    test_pass
else
    test_fail "recovery status overwrote the classifier's degraded reason"
fi

test_case "successful sync dispatch preserves a caller with errexit disabled"
CALLER_ERREXIT=off run_sync_fixture agy 0 caller-errexit-off >/dev/null
caller_options="$(cat "$TEST_TMP_DIR/caller-errexit-off/caller-options-after")"
if [[ "$caller_options" != *e* ]]; then
    test_pass
else
    test_fail "run_agent_sync enabled errexit in a caller that had it disabled (options=$caller_options)"
fi

test_case "an overlong attempt is interrupted before an AGY retry can exceed the deadline"
overlong_start=$SECONDS
overlong_completion="$TEST_TMP_DIR/overlong-completed"
set +e
(
    export "ENFORCE_TIMEOUT=true"
    export "OVERLONG_FIRST_ATTEMPT=true"
    export "OVERLONG_SLEEP=30"
    export "OVERLONG_COMPLETION_FILE=$overlong_completion"
    run_sync_fixture agy 1 overlong-deadline 2 >/dev/null 2>&1
)
overlong_rc=$?
set -e
overlong_elapsed=$((SECONDS - overlong_start))
overlong_root="$TEST_TMP_DIR/overlong-deadline"
overlong_attempt_timeout="$(cat "$overlong_root/timeouts" 2>/dev/null || true)"
if [[ "$overlong_rc" -eq 124 ]] && [[ "$(cat "$overlong_root/attempts")" == "1" ]] && \
   [[ "$overlong_attempt_timeout" =~ ^[12]$ ]] && [[ ! -e "$overlong_completion" ]] && \
   [[ "$overlong_elapsed" -lt 15 ]]; then
    test_pass
else
    test_fail "overlong attempt escaped its deadline (rc=$overlong_rc attempts=$(cat "$overlong_root/attempts" 2>/dev/null || echo 0) timeout=${overlong_attempt_timeout:-missing} completed=$([[ -e "$overlong_completion" ]] && echo yes || echo no) elapsed=${overlong_elapsed}s)"
fi

test_summary
