#!/usr/bin/env bash
# Tests for native Claude Code worktree ownership.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Native worktree lifecycle"

HOOKS_JSON="$PROJECT_ROOT/hooks/hooks.json"

test_case "plugin does not replace Claude Code native WorktreeCreate"
if ! jq -e '.hooks.WorktreeCreate // empty' "$HOOKS_JSON" >/dev/null; then
    test_pass
else
    test_fail "WorktreeCreate command hooks replace native Git creation and must return a created path"
fi

test_case "plugin does not replace Claude Code native WorktreeRemove"
if ! jq -e '.hooks.WorktreeRemove // empty' "$HOOKS_JSON" >/dev/null; then
    test_pass
else
    test_fail "WorktreeRemove is paired only with custom non-Git worktree creation"
fi

test_case "plugin does not ship dormant worktree credential writers"
if [[ ! -e "$PROJECT_ROOT/hooks/worktree-setup.sh" && ! -e "$PROJECT_ROOT/hooks/worktree-teardown.sh" ]]; then
    test_pass
else
    test_fail "obsolete worktree hook can persist provider credentials in a repository"
fi

test_case "providers.sh downgrades SUPPORTS_WORKTREE_ISOLATION when flag is false"
if grep -q 'OCTOPUS_WORKTREE_BG_ISOLATION' "$PROJECT_ROOT/scripts/lib/providers.sh"; then
    test_pass
else
    test_fail "providers.sh does not honor OCTOPUS_WORKTREE_BG_ISOLATION"
fi

test_summary
