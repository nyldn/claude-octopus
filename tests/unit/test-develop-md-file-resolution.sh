#!/usr/bin/env bash
# Static regression checks for /octo:develop Markdown plan reference handling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "develop Markdown plan resolution"

assert_has() {
    local pattern="$1"
    local label="$2"
    test_case "$label"
    if grep -qE "$pattern" "$WORKFLOWS"; then
        test_pass
    else
        test_fail "pattern not found: $pattern"
    fi
}

assert_lacks() {
    local pattern="$1"
    local label="$2"
    test_case "$label"
    if grep -qE "$pattern" "$WORKFLOWS"; then
        test_fail "unexpected pattern found: $pattern"
    else
        test_pass
    fi
}

test_case "workflows.sh has valid bash syntax"
if bash -n "$WORKFLOWS" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in workflows.sh"
fi

assert_lacks 'grep -oE .*\.\.md.*head -1|grep -oE .*\\.md.*head -1' \
    "plan reference scan avoids grep|head pipeline"

assert_has 'for token in \$prompt; do' \
    "plan reference scan uses a shell token loop"

assert_has 'trimmed_prompt=' \
    "plan reference handling detects file-only prompts"

assert_has 'resolved_prompt="\$\{prompt\}' \
    "plan reference handling preserves surrounding user instructions"

assert_has 'spawn_agent "codex" "\$resolved_prompt"' \
    "direct fallback receives resolved prompt"

test_summary
