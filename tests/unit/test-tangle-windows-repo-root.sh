#!/usr/bin/env bash
# Regression: Git for Windows cannot consume /c/... paths when MSYS argument
# conversion is disabled by the host environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_SOURCE="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle Windows repository root normalization"

source "$PROJECT_ROOT_SOURCE/scripts/lib/workflows.sh"
source "$PROJECT_ROOT_SOURCE/scripts/lib/testing.sh"

repo="$TEST_TMP_DIR/tangle-windows-root/repo"
mkdir -p "$repo"
git -C "$repo" init -q
printf 'tracked\n' > "$repo/README.md"
git -C "$repo" add README.md

test_case "resolved repository root remains valid for git -C with MSYS conversion disabled"
if [[ "$(uname -s)" == MINGW* ]] && command -v cygpath >/dev/null 2>&1; then
    if (
        export PROJECT_ROOT="$repo"
        export MSYS2_ARG_CONV_EXCL='*'
        resolved=$(tangle_resolve_repo_root)
        [[ "$resolved" =~ ^[A-Za-z]:/ ]] &&
        [[ "$(git -C "$resolved" ls-files)" == "README.md" ]]
    ); then
        test_pass
    else
        test_fail "tangle_resolve_repo_root returned a Git-incompatible MSYS path"
    fi
else
    if (
        export PROJECT_ROOT="$repo"
        resolved=$(tangle_resolve_repo_root)
        [[ "$(git -C "$resolved" ls-files)" == "README.md" ]]
    ); then
        test_pass
    else
        test_fail "tangle_resolve_repo_root did not preserve a usable repository root"
    fi
fi

printf 'new artifact\n' > "$repo/PROOF.txt"

test_case "worktree snapshot sees untracked files with MSYS conversion disabled"
if [[ "$(uname -s)" == MINGW* ]] && command -v cygpath >/dev/null 2>&1; then
    if (
        export PROJECT_ROOT="$repo"
        export MSYS2_ARG_CONV_EXCL='*'
        snapshot=$(snapshot_tangle_worktree_paths)
        grep -Fxq 'PROOF.txt' <<< "$snapshot"
    ); then
        test_pass
    else
        test_fail "snapshot_tangle_worktree_paths lost the Windows repository root"
    fi
else
    if (
        export PROJECT_ROOT="$repo"
        snapshot=$(snapshot_tangle_worktree_paths)
        grep -Fxq 'PROOF.txt' <<< "$snapshot"
    ); then
        test_pass
    else
        test_fail "snapshot_tangle_worktree_paths did not report the untracked artifact"
    fi
fi

test_summary
