#!/usr/bin/env bash
# Regression coverage for #892: completed providers must not wait on a
# descendant that inherited stdout from the provider process.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
source "$PROJECT_ROOT/scripts/lib/spawn.sh"

test_suite "Provider output capture"

run_with_timeout() {
    shift
    "$@"
}

child_pid_file="$TEST_TMP_DIR/inherited-stdout-child.pid"
input_mode_file="$TEST_TMP_DIR/provider-input.mode"
input_path_file="$TEST_TMP_DIR/provider-input.path"
provider_with_inherited_stdout() {
    printf '%s\n' "$temp_input" > "$input_path_file"
    if stat -f '%Lp' "$temp_input" >/dev/null 2>&1; then
        stat -f '%Lp' "$temp_input" > "$input_mode_file"
    else
        stat -c '%a' "$temp_input" > "$input_mode_file"
    fi
    ( sleep 5 ) &
    printf '%s\n' "$!" > "$child_pid_file"
    printf 'provider completed\n'
}

cleanup_child() {
    local child_pid=""
    child_pid="$(cat "$child_pid_file" 2>/dev/null || true)"
    if [[ "$child_pid" =~ ^[0-9]+$ ]]; then
        kill "$child_pid" 2>/dev/null || true
        wait "$child_pid" 2>/dev/null || true
    fi
}
after_all cleanup_child

test_case "capture returns when the provider exits, not when its descendant closes stdout"
raw_output="$TEST_TMP_DIR/provider.raw"
temp_errors="$TEST_TMP_DIR/provider.err"
temp_input="$TEST_TMP_DIR/provider.in"
start_time="$(date +%s)"
if declare -F octopus_capture_provider_output >/dev/null 2>&1 &&
   octopus_capture_provider_output \
       "research prompt" 30 "$temp_input" "$raw_output" "$temp_errors" \
       provider_with_inherited_stdout; then
    elapsed=$(( $(date +%s) - start_time ))
else
    elapsed=99
fi
if [[ "$elapsed" -lt 3 ]] &&
   grep -q 'provider completed' "$raw_output" 2>/dev/null; then
    test_pass
else
    test_fail "capture waited ${elapsed}s or lost provider output"
fi

test_case "temporary prompt input is removed after capture"
if [[ ! -e "$temp_input" ]]; then
    test_pass
else
    test_fail "provider prompt remained on disk at $temp_input"
fi

test_case "temporary prompt input is private while the provider reads it"
if [[ "$(cat "$input_mode_file" 2>/dev/null || true)" == "600" ]]; then
    test_pass
else
    test_fail "provider prompt input was not created with mode 600"
fi

test_case "temporary prompt input uses an atomic randomized path"
actual_input="$(cat "$input_path_file" 2>/dev/null || true)"
if [[ "$actual_input" == "${temp_input}."* ]] &&
   [[ "$actual_input" != "$temp_input" ]] &&
   [[ ! -e "$actual_input" ]]; then
    test_pass
else
    test_fail "provider input was not an atomically-created randomized file: ${actual_input:-<empty>}"
fi

test_summary
