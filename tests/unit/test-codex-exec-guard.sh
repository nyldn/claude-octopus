#!/usr/bin/env bash
# Tests for Codex exec guard hook.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Codex exec guard"

HOOK="$PROJECT_ROOT/hooks/codex-exec-guard.sh"

run_hook() {
    local command="$1"
    printf '{"tool_input":{"command":%s}}\n' "$(printf '%s' "$command" | jq -Rs .)" | bash "$HOOK"
}

test_case "blocks obsolete approval-mode quiet dispatch"
output="$(run_hook 'codex --approval-mode full-auto -q "hello"')"
if [[ "$output" == *'"permissionDecision":"deny"'* ]] \
   && [[ "$output" == *'codex exec --skip-git-repo-check'* ]] \
   && [[ "$output" != *'codex exec --full-auto'* ]]; then
    test_pass
else
    test_fail "expected block with current codex exec guidance, got: ${output:-<empty>}"
fi

test_case "allows current codex exec dispatch"
output="$(run_hook 'codex exec --skip-git-repo-check "hello"')"
if [[ -z "$output" ]]; then
    test_pass
else
    test_fail "expected allow for codex exec, got: ${output:-<empty>}"
fi

test_summary
