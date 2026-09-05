#!/usr/bin/env bash
# Tests for prompt-size preflight behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Dispatch oversize preflight"

log() { :; }
octo_notice_warn() { printf '%s\n' "$*" > "$TEST_TMP_DIR/oversize-notice"; }
record_oversize_event() { printf '%s\n' "$*" > "$TEST_TMP_DIR/oversize-event.args"; }
write_agent_status() { :; }
validate_agent_type() { return 0; }

source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

# These cases isolate compression mechanics from the separately tested output
# and system/tool context reserves.
OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=0
OCTOPUS_CONTEXT_OVERHEAD_TOKENS=0

long_prompt="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

test_case "truncate strategy includes its marker inside the exact resolved boundary"
OCTOPUS_CONTEXT_BUDGET=40
OCTOPUS_OVERSIZE_STRATEGY=truncate
output="$(enforce_context_budget "$long_prompt" "reviewer" "codex" "review")"
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
notice="$(cat "$TEST_TMP_DIR/oversize-notice")"
if [[ "${#output}" -eq 64 ]] &&
   [[ "$output" == *"truncated to fit context budget"* ]] &&
   [[ "$event_args" == "codex ${#long_prompt} 64 truncated reviewer review 16" ]] &&
   [[ "$notice" == "Context budget: truncated codex role=reviewer phase=review from ${#long_prompt} to 64 chars (budget=16 tokens/64 chars)" ]]; then
    test_pass
else
    test_fail "boundary/accounting mismatch: output_chars=${#output} event='$event_args'"
fi

test_case "fail strategy returns context-budget status"
set +e
OCTOPUS_CONTEXT_BUDGET=40
OCTOPUS_OVERSIZE_STRATEGY=fail
enforce_context_budget "$long_prompt" "reviewer" "codex" "review" >"$TEST_TMP_DIR/oversize-fail.out"
rc=$?
set -e
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
if [[ $rc -eq 78 ]] &&
   [[ "$event_args" == "codex ${#long_prompt} ${#long_prompt} failed reviewer review 16" ]]; then
    test_pass
else
    test_fail "expected attributed exit 78, got rc=$rc event='$event_args'"
fi

test_case "summarize strategy dispatches through summarizer"
run_agent_sync() {
    echo "condensed prompt"
}
OCTOPUS_CONTEXT_BUDGET=40
OCTOPUS_OVERSIZE_STRATEGY=summarize
output="$(enforce_context_budget "$long_prompt" "reviewer" "codex" "review")"
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
notice="$(cat "$TEST_TMP_DIR/oversize-notice")"
if [[ "$output" == "condensed prompt" ]] &&
   [[ "$event_args" == "codex ${#long_prompt} 16 summarized reviewer review 16" ]] &&
   [[ "$notice" == "Context budget: summarized codex role=reviewer phase=review from ${#long_prompt} to 16 chars (budget=16 tokens/64 chars)" ]]; then
    test_pass
else
    test_fail "expected attributed summarized prompt, got output='$output' event='$event_args'"
fi

test_case "leading-zero context budget is normalized as decimal before arithmetic"
decimal_prompt="$(printf '%04000d' 0)"
OCTOPUS_CONTEXT_BUDGET=0900
OCTOPUS_OVERSIZE_STRATEGY=truncate
set +e
output="$(enforce_context_budget "$decimal_prompt" "reviewer" "codex" "review" \
    2>"$TEST_TMP_DIR/decimal-budget.err")"
decimal_rc=$?
set -e
event_args="$(cat "$TEST_TMP_DIR/oversize-event.args")"
if [[ "$decimal_rc" -eq 0 ]] && [[ "${#output}" -eq 1440 ]] &&
   [[ "$event_args" == "codex 4000 1440 truncated reviewer review 360" ]]; then
    test_pass
else
    test_fail "0900 was not normalized safely: rc=$decimal_rc output_chars=${#output} event='$event_args' error='$(cat "$TEST_TMP_DIR/decimal-budget.err")'"
fi

test_case "invalid and overflowing context budgets fail before compression"
invalid_budget_ok=true
invalid_budget_failures=""
for invalid_budget in 0 -1 18446744073709551616 9223372036854775807; do
    rm -f "$TEST_TMP_DIR/oversize-event.args" "$TEST_TMP_DIR/oversize-notice"
    set +e
    OCTOPUS_CONTEXT_BUDGET="$invalid_budget" OCTOPUS_OVERSIZE_STRATEGY=truncate \
        enforce_context_budget "$long_prompt" "reviewer" "codex" "review" \
        >"$TEST_TMP_DIR/invalid-budget.out" 2>"$TEST_TMP_DIR/invalid-budget.err"
    rc=$?
    set -e
    invalid_output="$(cat "$TEST_TMP_DIR/invalid-budget.out")"
    if [[ "$rc" -ne 2 ]] || [[ -s "$TEST_TMP_DIR/invalid-budget.out" ]] ||
       [[ -e "$TEST_TMP_DIR/oversize-event.args" ]] || [[ -e "$TEST_TMP_DIR/oversize-notice" ]]; then
        invalid_budget_ok=false
        invalid_budget_failures="${invalid_budget_failures}${invalid_budget}:rc=${rc}:chars=${#invalid_output};"
    fi
done
if [[ "$invalid_budget_ok" == true ]]; then
    test_pass
else
    test_fail "invalid budgets reached prompt processing: $invalid_budget_failures"
fi

test_summary
