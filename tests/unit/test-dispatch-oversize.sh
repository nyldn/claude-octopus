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

test_summary
