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

# A tracked symlink satisfies `-d` when it resolves to a directory, and could
# point outside source_root entirely. It must be left as the symlink tar
# already copied, never resolved and recursively re-copied — that would
# materialize content from outside source_root into the workspace.
test_case "a tracked symlink is left alone, not resolved into the workspace"
SYMLINK_ROOT="$TEST_TMP_DIR/symlink-source"
OUTSIDE_ROOT="$TEST_TMP_DIR/symlink-outside"
mkdir -p "$SYMLINK_ROOT" "$OUTSIDE_ROOT"
(
    cd "$OUTSIDE_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'outside secret\n' > secret.txt
    git add secret.txt
    git commit -q -m init
)
(
    cd "$SYMLINK_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'main tracked\n' > main.txt
    ln -s "$OUTSIDE_ROOT" evil-link
    git add main.txt evil-link
    git commit -q -m "init with symlink"
)
workspace="$(_octopus_prepare_consultative_workspace "$SYMLINK_ROOT")"
if [[ -L "$workspace/evil-link" && -f "$workspace/main.txt" ]]; then
    test_pass
else
    test_fail "expected evil-link to remain a symlink (not resolved into a real copied directory) in $workspace"
fi
rm -rf "$(dirname "$workspace")"

# Bash suppresses errexit inside a function invoked as an `if`/`||` condition,
# so a bare `nested_copy || fallback` inside the per-entry loop cannot signal
# a double failure to the caller by relying on errexit — it must track and
# return it explicitly, or _octopus_prepare_consultative_workspace never
# knows to fall back to a full copy.
test_case "a nested copy that fails both ways is reported to the caller, not swallowed"
if (
    nested_copy_that_always_fails() { return 1; }
    cp_fallback_that_always_fails() { return 1; }

    copy_tree_without_tracking() {
        local entry
        while IFS= read -r entry; do
            nested_copy_that_always_fails || cp_fallback_that_always_fails 2>/dev/null
        done <<< "entry"
        return 0
    }

    copy_tree_with_tracking() {
        local entry
        local nested_copy_failed=0
        while IFS= read -r entry; do
            if ! nested_copy_that_always_fails; then
                cp_fallback_that_always_fails 2>/dev/null || nested_copy_failed=1
            fi
        done <<< "entry"
        [[ "$nested_copy_failed" -eq 0 ]]
    }

    if copy_tree_without_tracking; then without_tracking_rc=0; else without_tracking_rc=1; fi
    if copy_tree_with_tracking; then with_tracking_rc=0; else with_tracking_rc=1; fi
    [[ "$without_tracking_rc" -eq 0 && "$with_tracking_rc" -eq 1 ]]
); then
    test_pass
else
    test_fail "expected the untracked shape to mask a double failure and the tracked shape (used by _octopus_copy_git_tracked_tree) to report it"
fi

test_summary
