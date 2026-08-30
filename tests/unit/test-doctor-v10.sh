#!/usr/bin/env bash
# Doctor 2.0 structured-output and exit-semantics contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Doctor 2.0 structured diagnostics"

export HOME="$TEST_TMP_DIR/home"
mkdir -p "$HOME"

MAGENTA="" BOLD="" BLUE="" GREEN="" YELLOW="" RED="" DIM="" NC=""
source "$PROJECT_ROOT/scripts/lib/doctor.sh"

# Keep this suite deterministic and limited to the Doctor runner/output layer.
# Full category implementations retain their own focused suites.
doctor_check_providers() {
    case "${DOCTOR_FIXTURE:-fail}" in
        fail)
            doctor_add "fixture-failure" "providers" "fail" $'broken "provider"\nline two\e' 'repair \\ safely'
            ;;
        mixed)
            doctor_add "fixture-pass" "providers" "pass" "ready" ""
            doctor_add "fixture-info" "providers" "info" "optional" ""
            doctor_add "fixture-warning" "providers" "warn" "degraded" "repair"
            ;;
    esac
}

run_doctor_fixture() {
    local name="$1"
    shift
    local root="$TEST_TMP_DIR/$name"
    mkdir -p "$root"
    set +e
    do_doctor "$@" >"$root/stdout" 2>"$root/stderr"
    DOCTOR_FIXTURE_RC=$?
    set -e
    DOCTOR_FIXTURE_STDOUT="$(<"$root/stdout")"
    DOCTOR_FIXTURE_STDERR="$(<"$root/stderr")"
}

test_case "failed JSON diagnostics stay parseable and return nonzero"
DOCTOR_FIXTURE=fail run_doctor_fixture json-fail providers --json
expected_detail='repair \\ safely'
if [[ "$DOCTOR_FIXTURE_RC" -eq 1 ]] &&
   jq -e --arg expected_detail "$expected_detail" '
      .schema_version == "10.0" and
      .summary == {passed:0, warnings:0, failures:1, info:0, total:1, exit_code:1} and
      (.results | length == 1) and
      .results[0].name == "fixture-failure" and
      .results[0].message == "broken \"provider\"\nline two\u001b" and
      .results[0].detail == $expected_detail
   ' <<<"$DOCTOR_FIXTURE_STDOUT" >/dev/null 2>&1 &&
   [[ -z "$DOCTOR_FIXTURE_STDERR" ]]; then
    test_pass
else
    test_fail "rc=$DOCTOR_FIXTURE_RC stdout=$DOCTOR_FIXTURE_STDOUT stderr=$DOCTOR_FIXTURE_STDERR"
fi

test_case "warnings are structured but do not become failures"
DOCTOR_FIXTURE=mixed run_doctor_fixture json-mixed --json providers
if [[ "$DOCTOR_FIXTURE_RC" -eq 0 ]] &&
   jq -e '
      .summary == {passed:1, warnings:1, failures:0, info:1, total:3, exit_code:0} and
      (.results | length == 3) and
      ([.results[].status] == ["pass", "info", "warn"])
   ' <<<"$DOCTOR_FIXTURE_STDOUT" >/dev/null 2>&1; then
    test_pass
else
    test_fail "rc=$DOCTOR_FIXTURE_RC json=$DOCTOR_FIXTURE_STDOUT"
fi

test_case "human diagnostics preserve aggregated failure exit status"
DOCTOR_FIXTURE=fail run_doctor_fixture human-fail providers
if [[ "$DOCTOR_FIXTURE_RC" -eq 1 && "$DOCTOR_FIXTURE_STDOUT" == *"1 failure(s)"* ]]; then
    test_pass
else
    test_fail "rc=$DOCTOR_FIXTURE_RC stdout=$DOCTOR_FIXTURE_STDOUT"
fi

test_case "unknown flags fail with usage instead of being ignored"
run_doctor_fixture bad-flag providers --definitely-unknown
if [[ "$DOCTOR_FIXTURE_RC" -eq 2 && -z "$DOCTOR_FIXTURE_STDOUT" && "$DOCTOR_FIXTURE_STDERR" == *"Usage:"* && "$DOCTOR_FIXTURE_STDERR" == *"--definitely-unknown"* ]]; then
    test_pass
else
    test_fail "rc=$DOCTOR_FIXTURE_RC stdout=$DOCTOR_FIXTURE_STDOUT stderr=$DOCTOR_FIXTURE_STDERR"
fi

test_case "unknown categories fail with usage instead of passing zero checks"
run_doctor_fixture bad-category imaginary
if [[ "$DOCTOR_FIXTURE_RC" -eq 2 && -z "$DOCTOR_FIXTURE_STDOUT" && "$DOCTOR_FIXTURE_STDERR" == *"Unknown doctor category: imaginary"* ]]; then
    test_pass
else
    test_fail "rc=$DOCTOR_FIXTURE_RC stdout=$DOCTOR_FIXTURE_STDOUT stderr=$DOCTOR_FIXTURE_STDERR"
fi

test_case "multiple category arguments are rejected as ambiguous"
run_doctor_fixture two-categories providers auth
if [[ "$DOCTOR_FIXTURE_RC" -eq 2 && "$DOCTOR_FIXTURE_STDERR" == *"Only one doctor category"* ]]; then
    test_pass
else
    test_fail "rc=$DOCTOR_FIXTURE_RC stderr=$DOCTOR_FIXTURE_STDERR"
fi

test_case "help is a successful usage path"
run_doctor_fixture help --help
if [[ "$DOCTOR_FIXTURE_RC" -eq 0 && "$DOCTOR_FIXTURE_STDOUT" == *"Usage:"* && -z "$DOCTOR_FIXTURE_STDERR" ]]; then
    test_pass
else
    test_fail "rc=$DOCTOR_FIXTURE_RC stdout=$DOCTOR_FIXTURE_STDOUT stderr=$DOCTOR_FIXTURE_STDERR"
fi

test_case "strict plugin validation is a real failing diagnostic"
DOCTOR_RESULTS_NAME=() DOCTOR_RESULTS_CAT=() DOCTOR_RESULTS_STATUS=() DOCTOR_RESULTS_MSG=() DOCTOR_RESULTS_DETAIL=()
fake_bin="$TEST_TMP_DIR/doctor-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/claude" <<'SH'
#!/usr/bin/env bash
if [[ "${DOCTOR_CLAUDE_MODE:-fail}" == hang ]]; then sleep 30; fi
[[ "${1:-}" == plugin && "${2:-}" == validate ]] || exit 2
printf 'frontmatter schema mismatch\n' >&2
exit 1
SH
chmod +x "$fake_bin/claude"
if declare -f doctor_check_plugin_validation >/dev/null 2>&1; then
    PATH="$fake_bin:$PATH" doctor_check_plugin_validation "$PROJECT_ROOT"
fi
if [[ "${DOCTOR_RESULTS_NAME[0]:-}" == "plugin-validation" && "${DOCTOR_RESULTS_STATUS[0]:-}" == "fail" && "${DOCTOR_RESULTS_DETAIL[0]:-}" == *"frontmatter schema mismatch"* ]]; then
    test_pass
else
    test_fail "result=${DOCTOR_RESULTS_NAME[0]:-missing}/${DOCTOR_RESULTS_STATUS[0]:-missing} detail=${DOCTOR_RESULTS_DETAIL[0]:-}"
fi

test_case "strict plugin validation is bounded when Claude stalls"
DOCTOR_RESULTS_NAME=() DOCTOR_RESULTS_CAT=() DOCTOR_RESULTS_STATUS=() DOCTOR_RESULTS_MSG=() DOCTOR_RESULTS_DETAIL=()
started_at=$(date +%s)
PATH="$fake_bin:$PATH" DOCTOR_CLAUDE_MODE=hang OCTOPUS_PLUGIN_VALIDATE_TIMEOUT=1 \
    doctor_check_plugin_validation "$PROJECT_ROOT"
elapsed=$(( $(date +%s) - started_at ))
if [[ "$elapsed" -lt 5 && "${DOCTOR_RESULTS_STATUS[0]:-}" == fail ]]; then
    test_pass
else
    test_fail "elapsed=${elapsed}s result=${DOCTOR_RESULTS_STATUS[0]:-missing}"
fi

test_case "JSON escaping preserves UTF-8 and control characters"
escaped_unicode="$(doctor_json_escape $'snowman:☃ next:\u0085')"
if jq -ne --arg expected $'snowman:☃ next:\u0085' --arg escaped "$escaped_unicode" \
    '(("\"" + $escaped + "\"") | fromjson) == $expected' >/dev/null 2>&1; then
    test_pass
else
    test_fail "escaped=$escaped_unicode"
fi

test_case "state health reports writable cache, stale runs, and orphan process evidence"
state_root="$TEST_TMP_DIR/v10-state"
mkdir -p "$state_root/runs/stale-run"
cat > "$state_root/runs/stale-run/seats.json" <<'JSON'
{"schema_version":"10.0","run_id":"stale-run","seats":[{"seat_id":"spawn-known-task","transition":"running","timestamp":"2000-01-01T00:00:00Z"}],"events":[]}
JSON
mkdir -p "$state_root/runs/malformed-run"
printf '{not-json\n' > "$state_root/runs/malformed-run/seats.json"
sleep 30 &
orphan_pid=$!
printf '%s:fixture:orphan-task\n' "$orphan_pid" > "$state_root/pids"
DOCTOR_RESULTS_NAME=() DOCTOR_RESULTS_CAT=() DOCTOR_RESULTS_STATUS=() DOCTOR_RESULTS_MSG=() DOCTOR_RESULTS_DETAIL=()
if declare -f doctor_check_v10_state_health >/dev/null 2>&1; then
    WORKSPACE_DIR="$state_root" PID_FILE="$state_root/pids" OCTOPUS_RUNNING_STALE_SECONDS=1 \
        doctor_check_v10_state_health
fi
kill "$orphan_pid" 2>/dev/null || true
wait "$orphan_pid" 2>/dev/null || true
state_results="$(for ((i=0; i<${#DOCTOR_RESULTS_NAME[@]}; i++)); do printf '%s=%s\n' "${DOCTOR_RESULTS_NAME[$i]}" "${DOCTOR_RESULTS_STATUS[$i]}"; done)"
if [[ "$state_results" == *"probe-cache-writable=pass"* && "$state_results" == *"invalid-run-snapshots=warn"* && "$state_results" == *"stale-running-records=warn"* && "$state_results" == *"orphan-processes=warn"* ]]; then
    test_pass
else
    test_fail "results=$state_results"
fi

test_case "orchestrator doctor JSON has no initialization output prefix"
orchestrator_home="$TEST_TMP_DIR/orchestrator-home"
mkdir -p "$orchestrator_home"
set +e
orchestrator_json=$(env HOME="$orchestrator_home" OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" doctor updates --json 2>/dev/null)
orchestrator_rc=$?
set -e
if [[ "$orchestrator_rc" -le 1 ]] && jq -e '
    .schema_version == "10.0" and
    (.summary.exit_code == 0 or .summary.exit_code == 1) and
    (.results | type == "array")
' <<< "$orchestrator_json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "rc=$orchestrator_rc stdout=$orchestrator_json"
fi

test_case "setup verification is local-only and points to current Doctor entry points"
setup_default="$(sed -n '/^## Default path/,/^## Advanced setup/p' "$PROJECT_ROOT/commands/setup.md")"
if [[ "$setup_default" == *'setup-verification:pass (no provider request)'* &&
      "$setup_default" == *'/octo:skill-doctor'* &&
      "$setup_default" == *'octopus doctor'* &&
      "$setup_default" != *'/octo:doctor'* ]]; then
    test_pass
else
    test_fail "setup must use deterministic no-billing verification and current Doctor entry points"
fi

test_case "Doctor providers and auth reuse one shared readiness collection"
doctor_source="$(cat "$PROJECT_ROOT/scripts/lib/doctor.sh")"
if [[ "$doctor_source" == *'_doctor_collect_provider_readiness'* &&
      "$doctor_source" == *'octo_provider_readiness_all'* &&
      "$doctor_source" == *'DOCTOR_PROVIDER_READINESS_KIND'* ]]; then
    test_pass
else
    test_fail "Doctor does not consume the shared provider readiness contract"
fi

test_case "plan provider display reuses preflight output and handles dispatch failure"
plan_command="$(cat "$PROJECT_ROOT/commands/plan.md")"
release_plan="$(cat "$PROJECT_ROOT/docs/plans/2026-08-25-v10-reliability-modernization.md")"
if [[ "$plan_command" == *'PROVIDER_STATUS='* &&
      "$plan_command" == *'Render every provider status from `PROVIDER_STATUS`'* &&
      "$release_plan" == *'CODEX_REVIEW_RC'* &&
      "$release_plan" == *'BLOCKED: Codex dispatch failed'* ]]; then
    test_pass
else
    test_fail "plan must retain one provider-status source and fail closed on Codex dispatch"
fi

test_summary
