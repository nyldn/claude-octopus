#!/usr/bin/env bash
# Regression: all path consumers share strict cross-platform canonicalization.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATH_RUNTIME="$ROOT_DIR/scripts/lib/path-runtime.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/octo-path-runtime.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/repo/src" "$TEST_ROOT/repo2" "$TEST_ROOT/outside"
printf '%s\n' ok > "$TEST_ROOT/repo/src/context.md"
printf '%s\n' outside > "$TEST_ROOT/repo2/context.md"
git -C "$TEST_ROOT/repo" init -q

source "$PATH_RUNTIME"

repo_posix="$(cd "$TEST_ROOT/repo" && pwd -P)"
context_posix="$repo_posix/src/context.md"

if pathrt_is_windows; then
    repo_native="$(cygpath -m "$repo_posix")"
    context_native="$(cygpath -w "$context_posix")"
    [[ "$(pathrt_canon_existing "$repo_posix")" == "$(pathrt_canon_existing "$repo_native")" ]] || {
        echo "FAIL: Windows native and MSYS roots did not canonicalize equally" >&2
        exit 1
    }
    pathrt_within_existing "$repo_posix" "$context_native" || {
        echo "FAIL: Windows native context was rejected under MSYS root" >&2
        exit 1
    }
    git_root="$(pathrt_for_git "$repo_posix")"
    [[ "$git_root" =~ ^[A-Za-z]:/ ]] || {
        echo "FAIL: Git execution path was not converted to drive form" >&2
        exit 1
    }
    MSYS2_ARG_CONV_EXCL='*' git -C "$git_root" rev-parse --show-toplevel >/dev/null || {
        echo "FAIL: native Windows Git rejected shared execution path" >&2
        exit 1
    }
else
    [[ "$(pathrt_canon_existing "$repo_posix")" == "$repo_posix" ]] || {
        echo "FAIL: POSIX canonical path changed unexpectedly" >&2
        exit 1
    }
fi

pathrt_within_existing "$repo_posix" "$context_posix" || {
    echo "FAIL: existing child was rejected" >&2
    exit 1
}
if pathrt_within_existing "$repo_posix" "$TEST_ROOT/repo2/context.md"; then
    echo "FAIL: prefix sibling was accepted without a separator boundary" >&2
    exit 1
fi
if pathrt_within_existing "$repo_posix" "$repo_posix/../repo2/context.md"; then
    echo "FAIL: traversal outside the root was accepted" >&2
    exit 1
fi

pathrt_within_target "$repo_posix" "$repo_posix/src/new.md" || {
    echo "FAIL: target with existing parent was rejected" >&2
    exit 1
}
set +e
pathrt_within_target "$repo_posix" "$repo_posix/missing/new.md"
missing_rc=$?
pathrt_canon_existing 'C:relative-path'
drive_relative_rc=$?
pathrt_canon_existing '\\server\share\file.md'
unc_rc=$?
set -e
[[ "$missing_rc" -eq 2 && "$drive_relative_rc" -eq 2 && "$unc_rc" -eq 2 ]] || {
    echo "FAIL: invalid paths did not fail closed with status 2" >&2
    exit 1
}

ln -s "$TEST_ROOT/outside" "$TEST_ROOT/repo/escape-link" 2>/dev/null || true
if [[ -L "$TEST_ROOT/repo/escape-link" ]] \
    && pathrt_within_existing "$repo_posix" "$TEST_ROOT/repo/escape-link"; then
    echo "FAIL: symlink escape was accepted" >&2
    exit 1
fi

grep -Fq 'pathrt_within_existing "$review_root" "$context_file"' "$ROOT_DIR/scripts/lib/review.sh" || {
    echo "FAIL: review context guard does not use shared containment" >&2
    exit 1
}
grep -Fq 'pathrt_for_git' "$ROOT_DIR/scripts/lib/workflows.sh" || {
    echo "FAIL: workflows do not use shared Git path conversion" >&2
    exit 1
}
grep -Fq 'pathrt_for_git' "$ROOT_DIR/scripts/lib/testing.sh" || {
    echo "FAIL: testing does not use shared Git path conversion" >&2
    exit 1
}

echo "PASS: shared path runtime canonicalizes, contains, and fails closed"
