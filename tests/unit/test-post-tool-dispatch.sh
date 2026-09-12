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
    output="$(printf '%s' "$PAYLOAD" | CLAUDE_SESSION_ID="$SESSION" OCTOPUS_COMPRESS_ENABLED=true bash "$HOOK")"
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


test_case "large output is also silent when compression is not opted in"
output="$(build_verbose_payload | CLAUDE_SESSION_ID="$SESSION-default-off" bash "$HOOK")"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected default silence for large output, got: ${output:-<empty>}"
fi

test_case "statusline bridge alone does not activate context injection"
bridge="/tmp/octopus-ctx-${SESSION-default-off}.json"
printf '{"used_pct":60}\n' > "$bridge"
output="$(printf 'ok' | CLAUDE_SESSION_ID="$SESSION-default-off" bash "$HOOK")"
rm -f "$bridge"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "statusline state activated PostToolUse context: ${output:-<empty>}"
fi

test_case "installed dispatcher subscribes to the tools it compresses"
if jq -e '.hooks.PostToolUse[] | select(any(.hooks[]; .command | endswith("/post-tool-dispatch.sh"))) |
    .matcher | split("|") | index("Read") != null and index("WebFetch") != null and index("Grep") != null' \
    "$PROJECT_ROOT/hooks/hooks.json" >/dev/null; then test_pass; else test_fail "manifest omits supported tools"; fi

test_case "dispatcher passes protocol session identity to child hooks"
fixture="$TEST_TMP_DIR/dispatch-root"
mkdir -p "$fixture/hooks" "$fixture/scripts/lib"
cp "$PROJECT_ROOT/scripts/lib/hook-activation.sh" "$fixture/scripts/lib/"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s" "${CLAUDE_SESSION_ID:-missing}" > "$SESSION_CAPTURE"' > "$fixture/hooks/strategy-rotation.sh"
capture="$TEST_TMP_DIR/session-id"
env -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID CLAUDE_PLUGIN_ROOT="$fixture" \
    OCTO_STRATEGY_ROTATION=on SESSION_CAPTURE="$capture" bash "$HOOK" <<< '{"session_id":"protocol-session"}'
if [[ "$(cat "$capture")" == protocol-session ]]; then test_pass; else test_fail "child lost protocol session identity"; fi

test_summary
