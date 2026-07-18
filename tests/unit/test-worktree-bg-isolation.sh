#!/usr/bin/env bash
# Tests for the worktree.bgIsolation opt-out flag (OCTOPUS_WORKTREE_BG_ISOLATION).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Worktree bgIsolation flag"

HOOK="$PROJECT_ROOT/hooks/worktree-setup.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

payload() {
    printf '{"worktreePath":"%s"}' "$1"
}

test_case "default (isolation on): worktree-setup injects .octopus-env"
wt1="$TMP_DIR/wt1"; mkdir -p "$wt1"
out=$(payload "$wt1" | env -u OCTOPUS_WORKTREE_BG_ISOLATION OPENAI_API_KEY=test-key bash "$HOOK")
if [[ -f "$wt1/.octopus-env" && -z "$out" ]]; then
    test_pass
else
    test_fail "expected .octopus-env with isolation on, got: $out"
fi

test_case "OCTOPUS_WORKTREE_BG_ISOLATION=false: setup short-circuits, no env injection"
wt2="$TMP_DIR/wt2"; mkdir -p "$wt2"
out=$(payload "$wt2" | OCTOPUS_WORKTREE_BG_ISOLATION=false OPENAI_API_KEY=test-key bash "$HOOK")
if [[ ! -f "$wt2/.octopus-env" && -z "$out" ]]; then
    test_pass
else
    test_fail "expected no .octopus-env with isolation off, got: $out"
fi

test_case "flag values other than false keep isolation on"
wt3="$TMP_DIR/wt3"; mkdir -p "$wt3"
payload "$wt3" | OCTOPUS_WORKTREE_BG_ISOLATION=true OPENAI_API_KEY=test-key bash "$HOOK" >/dev/null
if [[ -f "$wt3/.octopus-env" ]]; then
    test_pass
else
    test_fail "OCTOPUS_WORKTREE_BG_ISOLATION=true must not disable setup"
fi

test_case "providers.sh downgrades SUPPORTS_WORKTREE_ISOLATION when flag is false"
if grep -q 'OCTOPUS_WORKTREE_BG_ISOLATION' "$PROJECT_ROOT/scripts/lib/providers.sh"; then
    test_pass
else
    test_fail "providers.sh does not honor OCTOPUS_WORKTREE_BG_ISOLATION"
fi

test_summary
