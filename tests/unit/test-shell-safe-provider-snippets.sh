#!/usr/bin/env bash
# Guard against command-substitution provider checks in user-facing docs.
# These snippets get copied into live Bash tool calls, where `$(...)` can trigger
# unnecessary shell confirmation prompts in Codex/Claude hosts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Guard against command-substitution provider checks in user-facing docs."


FAILED=0

check_tree() {
    local label="$1"
    local path="$2"
    local hits

    hits=$(rg -n '=\$\(command -v (codex|gemini|opencode)' "$path" 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
        echo "FAIL: $label contains command-substitution provider checks"
        echo "$hits"
        FAILED=1
    else
        echo "PASS: $label uses shell-safe provider checks"
    fi
}

check_tree "source command docs" "$PROJECT_ROOT/.claude/commands"
check_tree "source skill docs" "$PROJECT_ROOT/.claude/skills"
check_tree "packaged command docs" "$PROJECT_ROOT/commands"
check_tree "packaged skill docs" "$PROJECT_ROOT/skills"
test_summary
