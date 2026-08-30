#!/usr/bin/env bash
# tests/unit/test-consultative-workspace-gitignore.sh
# Regression test for #980: the consultative workspace copy must honour
# .gitignore in a git work tree instead of copying gitignored vendor/build
# trees into every advisory seat's disposable workspace.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"

test_suite "Consultative Workspace .gitignore Handling"

SOURCE_ROOT="$TEST_TMP_DIR/gitignore-source"
mkdir -p "$SOURCE_ROOT/vendor"
(
    cd "$SOURCE_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'vendor/\n' > .gitignore
    printf 'tracked\n' > tracked.txt
    printf 'vendored\n' > vendor/big.bin
    git add tracked.txt .gitignore
    git commit -q -m init
    printf 'untracked but not ignored\n' > untracked.txt
)

test_case "gitignored files are excluded from the disposable workspace"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT")"
if [[ -f "$workspace/tracked.txt" && -f "$workspace/untracked.txt" && ! -e "$workspace/vendor" ]]; then
    test_pass
else
    test_fail "expected tracked.txt and untracked.txt present, vendor/ absent in $workspace"
fi
rm -rf "$(dirname "$workspace")"

test_case "non-git source roots still fall back to a full copy"
PLAIN_ROOT="$TEST_TMP_DIR/plain-source"
mkdir -p "$PLAIN_ROOT"
printf 'x\n' > "$PLAIN_ROOT/file.txt"
workspace="$(_octopus_prepare_consultative_workspace "$PLAIN_ROOT")"
if [[ -f "$workspace/file.txt" ]]; then
    test_pass
else
    test_fail "expected full copy fallback to include file.txt in $workspace"
fi
rm -rf "$(dirname "$workspace")"

# A nested git work tree (a submodule, or a plain untracked checkout that
# isn't itself gitignored) is reported by `git ls-files` as a single opaque
# path. Without recursing into it, a naive tar copy of that path would pull
# in whatever the nested tree's own .gitignore excludes, defeating the fix
# one level down.
test_case "a nested git work tree's own .gitignore is honored too"
NESTED_ROOT="$TEST_TMP_DIR/nested-source"
mkdir -p "$NESTED_ROOT/nested-repo/vendor"
(
    cd "$NESTED_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'parent tracked\n' > parent.txt
    git add parent.txt
    git commit -q -m init

    cd nested-repo
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'vendor/\n' > .gitignore
    printf 'nested tracked\n' > nested.txt
    printf 'nested vendored\n' > vendor/big.bin
    git add nested.txt .gitignore
    git commit -q -m "nested init"
)
workspace="$(_octopus_prepare_consultative_workspace "$NESTED_ROOT")"
if [[ -f "$workspace/parent.txt" && -f "$workspace/nested-repo/nested.txt" && ! -e "$workspace/nested-repo/vendor" ]]; then
    test_pass
else
    test_fail "expected nested-repo/vendor absent, parent.txt and nested-repo/nested.txt present in $workspace"
fi
rm -rf "$(dirname "$workspace")"

test_summary
