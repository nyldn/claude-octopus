#!/usr/bin/env bash
# Tests for prompt-size preflight behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Dispatch oversize preflight"

log() { :; }
record_oversize_event() { :; }
write_agent_status() { :; }
validate_agent_type() { return 0; }

source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

long_prompt="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

test_case "truncate strategy bounds oversized prompts"
OCTOPUS_CONTEXT_BUDGET=4
OCTOPUS_OVERSIZE_STRATEGY=truncate
output="$(enforce_context_budget "$long_prompt" "" "codex")"
if [[ "$output" == abcdefghijklmnop* && "$output" == *"truncated to fit context budget"* ]]; then
    test_pass
else
    test_fail "expected truncated prompt, got: $output"
fi

test_case "fail strategy returns context-budget status"
set +e
OCTOPUS_CONTEXT_BUDGET=4
OCTOPUS_OVERSIZE_STRATEGY=fail
enforce_context_budget "$long_prompt" "" "codex" >/tmp/octopus-oversize-fail.out
rc=$?
set -e
if [[ $rc -eq 78 ]]; then
    test_pass
else
    test_fail "expected exit 78 for oversize fail strategy, got: $rc"
fi

test_case "summarize strategy dispatches through summarizer"
run_agent_sync() {
    echo "condensed prompt"
}
OCTOPUS_CONTEXT_BUDGET=4
OCTOPUS_OVERSIZE_STRATEGY=summarize
output="$(enforce_context_budget "$long_prompt" "" "codex")"
if [[ "$output" == "condensed prompt" ]]; then
    test_pass
else
    test_fail "expected summarized prompt, got: $output"
fi

test_summary
