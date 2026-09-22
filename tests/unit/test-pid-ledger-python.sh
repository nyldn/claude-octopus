#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "PID ledger Python capability selection"

source "$PROJECT_ROOT/scripts/lib/pid-ledger.sh"
default_python_candidates=("${_OCTO_PID_PYTHON_CANDIDATES[@]}")

make_probe() {
    local path="$1" result="$2" counter="$3"
    cat > "$path" <<EOF
#!/usr/bin/env bash
printf 'probe\n' >> "$counter"
[[ "\${2:-}" == capability ]] || exit 64
exit $result
EOF
    chmod +x "$path"
}

bad_python="$TEST_TMP_DIR/python-bad"
good_python="$TEST_TMP_DIR/python-good"
bad_count="$TEST_TMP_DIR/bad-count"
good_count="$TEST_TMP_DIR/good-count"
make_probe "$bad_python" 1 "$bad_count"
make_probe "$good_python" 0 "$good_count"

test_case "automatic selection skips an incapable PATH candidate and caches the capable interpreter"
unset OCTOPUS_PYTHON
_OCTO_PID_LEDGER_PYTHON=""
_OCTO_PID_PYTHON_CANDIDATES=("$bad_python" "$good_python")
first_result="$TEST_TMP_DIR/first-result"
second_result="$TEST_TMP_DIR/second-result"
selection_ok=true
octopus_pid_python_resolve >"$first_result" 2>/dev/null || selection_ok=false
octopus_pid_python_resolve >"$second_result" 2>/dev/null || selection_ok=false
if [[ "$selection_ok" == true ]] &&
   [[ "$(cat "$first_result")" == "$good_python" ]] &&
   [[ "$(cat "$second_result")" == "$good_python" ]] &&
   [[ "$(wc -l < "$bad_count" | tr -d ' ')" == 1 ]] &&
   [[ "$(wc -l < "$good_count" | tr -d ' ')" == 1 ]]; then
    test_pass
else
    test_fail "capable interpreter was not selected and cached"
fi

test_case "automatic candidates prefer the shell PATH before fixed system paths"
if [[ "${default_python_candidates[0]}" == "python3" ]] &&
   [[ "${default_python_candidates[1]}" == "/usr/bin/python3" ]]; then
    test_pass
else
    test_fail "unexpected automatic candidate order: ${default_python_candidates[*]}"
fi

test_case "an ambient private cache value cannot bypass capability validation"
ambient_result="$({
    _OCTO_PID_LEDGER_PYTHON="$bad_python" bash -c '
        source "$1"
        _OCTO_PID_PYTHON_CANDIDATES=("$2")
        octopus_pid_python_resolve
    ' _ "$PROJECT_ROOT/scripts/lib/pid-ledger.sh" "$good_python"
} 2>/dev/null || true)"
if [[ "$ambient_result" == "$good_python" ]]; then
    test_pass
else
    test_fail "ambient cache value was trusted without probing: $ambient_result"
fi

test_case "an explicit incapable OCTOPUS_PYTHON override replaces an inherited cache and fails closed"
: > "$bad_count"
: > "$good_count"
OCTOPUS_PYTHON="$bad_python"
override_error="$TEST_TMP_DIR/override-error"
override_status=0
octopus_pid_python_resolve >/dev/null 2>"$override_error" || override_status=$?
if [[ "$override_status" -ne 0 ]] &&
   grep -q "OCTOPUS_PYTHON" "$override_error" &&
   [[ "$(wc -l < "$bad_count" | tr -d ' ')" == 1 ]] &&
   [[ ! -s "$good_count" ]]; then
    test_pass
else
    test_fail "invalid explicit override fell back or lacked actionable guidance"
fi
unset OCTOPUS_PYTHON

test_case "the bundled PID ledger exposes a platform capability probe"
_OCTO_PID_LEDGER_PYTHON=""
_OCTO_PID_PYTHON_CANDIDATES=(python3 /usr/bin/python3 python3.13 python3.12 python3.11 python3.10 python3.9)
selected_python="$(octopus_pid_python_resolve)"
if "$selected_python" "$PROJECT_ROOT/scripts/helpers/pid-ledger.py" capability >/dev/null; then
    test_pass
else
    test_fail "current interpreter failed the bundled capability probe"
fi

test_case "a PID capability failure exits 74 without launching the provider"
spawn_home="$TEST_TMP_DIR/spawn-home"
spawn_workspace="$TEST_TMP_DIR/spawn-workspace"
spawn_project="$TEST_TMP_DIR/spawn-project"
spawn_output="$TEST_TMP_DIR/spawn-output"
provider_marker="$TEST_TMP_DIR/provider-ran"
mkdir -p "$spawn_home" "$spawn_project"
cat > "$MOCK_BIN_DIR/codex" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
    printf '%s\n' 'codex-cli 9.9.9'
    exit 0
fi
touch "$provider_marker"
printf '%s\n' provider-ran
EOF
chmod +x "$MOCK_BIN_DIR/codex"
spawn_status=0
env -u _OCTO_PID_LEDGER_PYTHON \
    HOME="$spawn_home" \
    CLAUDE_PLUGIN_DATA="$spawn_workspace" \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
    OCTOPUS_PROJECT_DIR="$spawn_project" \
    OCTOPUS_SKIP_PROVIDER_PROBES=true \
    OCTOPUS_PYTHON="$bad_python" \
    OPENAI_API_KEY=test-only \
    PATH="$MOCK_BIN_DIR:$PATH" \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" spawn codex "Reply OK" \
    >"$spawn_output" 2>&1 || spawn_status=$?
spawn_ledger="$(find "$spawn_workspace/runs" -type f -name seats.jsonl -print -quit 2>/dev/null || true)"
spawn_terminal=""
if [[ -n "$spawn_ledger" ]]; then
    spawn_terminal="$(jq -sr '
        map(select(.seat_id | startswith("spawn-"))) | last |
        [.transition, .reason] | join("|")
    ' "$spawn_ledger" 2>/dev/null || true)"
fi
if [[ "$spawn_status" -eq 74 ]] &&
   grep -q "Worker registration failed" "$spawn_output" &&
   [[ "$spawn_terminal" == "failed|Native process cancellation is unavailable" ]] &&
   [[ ! -e "$provider_marker" ]]; then
    test_pass
else
    test_fail "spawn status=$spawn_status terminal=${spawn_terminal:-missing} provider_ran=$([[ -e "$provider_marker" ]] && printf yes || printf no)"
fi

test_case "spawn resolves Python once before worker command substitutions"
real_python="$(command -v python3)"
counting_python="$TEST_TMP_DIR/python-counting"
capability_count="$TEST_TMP_DIR/capability-count"
cleanup_count="$TEST_TMP_DIR/cleanup-count"
cat > "$counting_python" <<EOF
#!/usr/bin/env bash
if [[ "\${2:-}" == capability ]]; then
    printf 'probe\n' >> "$capability_count"
fi
if [[ "\${1:-}" == */process_control.py ]]; then
    printf 'cleanup\n' >> "$cleanup_count"
fi
exec "$real_python" "\$@"
EOF
chmod +x "$counting_python"
spawn_cached_home="$TEST_TMP_DIR/spawn-cached-home"
spawn_cached_workspace="$TEST_TMP_DIR/spawn-cached-workspace"
spawn_cached_project="$TEST_TMP_DIR/spawn-cached-project"
spawn_cached_output="$TEST_TMP_DIR/spawn-cached-output"
mkdir -p "$spawn_cached_home" "$spawn_cached_project"
spawn_cached_status=0
env -u _OCTO_PID_LEDGER_PYTHON \
    HOME="$spawn_cached_home" \
    CLAUDE_PLUGIN_DATA="$spawn_cached_workspace" \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
    OCTOPUS_PROJECT_DIR="$spawn_cached_project" \
    OCTOPUS_SKIP_PROVIDER_PROBES=true \
    OCTOPUS_PYTHON="$counting_python" \
    OPENAI_API_KEY=test-only \
    PATH="$MOCK_BIN_DIR:$PATH" \
    bash "$PROJECT_ROOT/scripts/orchestrate.sh" spawn codex "Reply OK" \
    >"$spawn_cached_output" 2>&1 || spawn_cached_status=$?
if [[ "$spawn_cached_status" -eq 0 ]] &&
   [[ "$(wc -l < "$capability_count" | tr -d ' ')" == 1 ]]; then
    test_pass
else
    test_fail "spawn status=$spawn_cached_status capability probes=$(wc -l < "$capability_count" | tr -d ' ')"
fi

test_case "process cleanup uses the capability-selected interpreter instead of PATH python3"
ln -sf "$bad_python" "$MOCK_BIN_DIR/python3"
source "$PROJECT_ROOT/scripts/lib/review.sh"
_OCTO_PID_LEDGER_PYTHON=""
OCTOPUS_PYTHON="$counting_python"
: > "$cleanup_count"
original_path="$PATH"
PATH="$MOCK_BIN_DIR:$PATH"
sleep 300 &
cleanup_pid=$!
cleanup_status=0
octo_terminate_process_tree "$cleanup_pid" 0 "" >/dev/null 2>&1 || cleanup_status=$?
PATH="$original_path"
if [[ "$cleanup_status" -eq 0 ]] &&
   [[ "$(wc -l < "$cleanup_count" | tr -d ' ')" == 1 ]] &&
   ! kill -0 "$cleanup_pid" 2>/dev/null; then
    wait "$cleanup_pid" 2>/dev/null || true
    test_pass
else
    kill -KILL "$cleanup_pid" 2>/dev/null || true
    wait "$cleanup_pid" 2>/dev/null || true
    test_fail "cleanup bypassed the selected interpreter or left the worker alive"
fi
rm -f "$MOCK_BIN_DIR/python3"
unset OCTOPUS_PYTHON

test_case "Doctor reports the resolved PID ledger interpreter"
_OCTO_PID_LEDGER_PYTHON=""
OCTOPUS_PYTHON="$good_python"
source "$PROJECT_ROOT/scripts/lib/doctor.sh"
DOCTOR_RESULTS_NAME=() DOCTOR_RESULTS_CAT=() DOCTOR_RESULTS_STATUS=() DOCTOR_RESULTS_MSG=() DOCTOR_RESULTS_DETAIL=()
doctor_check_process_control
doctor_result="$(for ((i=0; i<${#DOCTOR_RESULTS_NAME[@]}; i++)); do printf '%s=%s|%s\n' "${DOCTOR_RESULTS_NAME[$i]}" "${DOCTOR_RESULTS_STATUS[$i]}" "${DOCTOR_RESULTS_DETAIL[$i]}"; done)"
DOCTOR_RESULTS_NAME=() DOCTOR_RESULTS_CAT=() DOCTOR_RESULTS_STATUS=() DOCTOR_RESULTS_MSG=() DOCTOR_RESULTS_DETAIL=()
_OCTO_PID_LEDGER_PYTHON=""
OCTOPUS_PYTHON="$bad_python"
doctor_check_process_control
doctor_failure="$(for ((i=0; i<${#DOCTOR_RESULTS_NAME[@]}; i++)); do printf '%s=%s|%s\n' "${DOCTOR_RESULTS_NAME[$i]}" "${DOCTOR_RESULTS_STATUS[$i]}" "${DOCTOR_RESULTS_MSG[$i]}"; done)"
if [[ "$doctor_result" == *"pid-ledger-python=pass|$good_python"* ]] &&
   [[ "$doctor_failure" == *"pid-ledger-python=fail|No compatible Python interpreter"* ]]; then
    test_pass
else
    test_fail "Doctor capability results were incomplete: pass=$doctor_result fail=$doctor_failure"
fi
unset OCTOPUS_PYTHON

test_summary
