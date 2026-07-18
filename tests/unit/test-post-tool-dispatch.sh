#!/usr/bin/env bash
# Tests for the PostToolUse dispatcher hook (hooks/post-tool-dispatch.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "PostToolUse dispatcher"

HOOK="$PROJECT_ROOT/hooks/post-tool-dispatch.sh"

SESSION="test-ptd-$$"
DEBOUNCE_FILE="/tmp/octopus-compress-debounce-${SESSION}.count"
trap 'rm -f "$DEBOUNCE_FILE"; cleanup_test_environment' EXIT

# Build a >3000-char, >40-line, non-timestamped payload so output-compressor.sh
# classifies it as "verbose" and produces a compressed summary.
build_verbose_payload() {
    local i
    for i in $(seq 1 80); do
        echo "line ${i}: some verbose tool output that is not a timestamped log entry"
    done
}

test_case "emits hookSpecificOutput (not legacy root decision) when a sub-hook adds context"
rm -f "$DEBOUNCE_FILE"

PAYLOAD="$(build_verbose_payload)"
output=""
# output-compressor.sh only analyzes every 3rd call (debounce); drive it there.
for _ in 1 2 3; do
    output="$(CLAUDE_SESSION_ID="$SESSION" printf '%s' "$PAYLOAD" | CLAUDE_SESSION_ID="$SESSION" bash "$HOOK")"
done
rm -f "$DEBOUNCE_FILE"

if [[ "$output" == *'"hookSpecificOutput":{"hookEventName":"PostToolUse"'* ]] \
   && [[ "$output" == *'"additionalContext"'* ]] \
   && [[ "$output" != '{"decision"'* ]]; then
    test_pass
else
    test_fail "expected nested hookSpecificOutput.additionalContext, got: ${output:-<empty>}"
fi

test_case "output is valid JSON per the current hook schema"
if command -v jq &>/dev/null; then
    if [[ -n "$output" ]] && echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
       && ! echo "$output" | jq -e '.decision' >/dev/null 2>&1; then
        test_pass
    else
        test_fail "output did not parse as the expected schema: ${output:-<empty>}"
    fi
else
    test_skip "jq not available"
fi

test_case "emits nothing (pass-through) when no sub-hook has context to add"
output="$(printf 'ok' | bash "$HOOK")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected silence for small/uninteresting output, got: ${output:-<empty>}"
fi

test_summary
