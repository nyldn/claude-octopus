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
mkdir -p "$SOURCE_ROOT/vendor" "$SOURCE_ROOT/subdir"
(
    cd "$SOURCE_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'vendor/\n' > .gitignore
    printf 'tracked\n' > tracked.txt
    printf 'inside\n' > inside.txt
    printf 'subdirectory tracked\n' > subdir/context.txt
    ln -s inside.txt safe-link
    printf 'vendored\n' > vendor/big.bin
    git add tracked.txt inside.txt subdir/context.txt safe-link .gitignore
    git commit -q -m init
    printf 'modified\n' > tracked.txt
    printf 'subdirectory modified\n' > subdir/context.txt
    printf 'staged\n' > staged.txt
    git add staged.txt
    printf 'staged and modified\n' > staged.txt
    printf 'untracked but not ignored\n' > untracked.txt
    printf 'must not be copied\n' > .git/source-only-sentinel
)

test_case "gitignored files are excluded from the disposable workspace"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT")"
if [[ -f "$workspace/tracked.txt" && -f "$workspace/untracked.txt" && ! -e "$workspace/vendor" ]]; then
    test_pass
else
    test_fail "expected tracked.txt and untracked.txt present, vendor/ absent in $workspace"
fi
rm -rf "$(dirname "$workspace")"

test_case "the disposable workspace retains local Git review context"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT")"
source_head="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
if [[ "$(git -C "$workspace" rev-parse HEAD 2>/dev/null)" == "$source_head" ]] &&
   [[ ! -e "$workspace/.git/source-only-sentinel" ]] &&
   ! git -C "$workspace" diff --quiet -- tracked.txt &&
   ! git -C "$workspace" diff --cached --quiet -- staged.txt &&
   ! git -C "$workspace" diff --quiet -- staged.txt &&
   git -C "$workspace" status --short 2>/dev/null | grep -q '^?? untracked.txt$'; then
    git -C "$workspace" config octopus.workspace-only true
    if [[ -z "$(git -C "$SOURCE_ROOT" config --get octopus.workspace-only 2>/dev/null)" ]]; then
        test_pass
    else
        test_fail "workspace Git config mutated the source repository"
    fi
else
    test_fail "expected isolated HEAD, index, worktree changes, and untracked files inside $workspace"
fi
rm -rf "$(dirname "$workspace")"

test_case "a launch from a repository subdirectory keeps coherent Git context"
source_status="$(git -C "$SOURCE_ROOT/subdir" status --short)"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT/subdir")"
workspace_top="$(git -C "$workspace" rev-parse --show-toplevel 2>/dev/null)"
workspace_status="$(git -C "$workspace" status --short 2>/dev/null)"
if [[ -f "$workspace/context.txt" ]] &&
   [[ "$(git -C "$workspace" rev-parse HEAD 2>/dev/null)" == "$(git -C "$SOURCE_ROOT" rev-parse HEAD)" ]] &&
   [[ "$workspace_status" == "$source_status" ]]; then
    test_pass
else
    test_fail "expected the copied repository root and returned subdirectory to match source Git status"
fi
rm -rf "$(dirname "$workspace_top")"

test_case "an internal tracked symlink remains usable"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT")"
if [[ -L "$workspace/safe-link" && "$(cat "$workspace/safe-link")" == "inside" ]]; then
    test_pass
else
    test_fail "expected safe-link to remain a working in-repository symlink"
fi
rm -rf "$(dirname "$workspace")"

test_case "an absolute tracked symlink cannot point back into the source"
ABSOLUTE_LINK_ROOT="$TEST_TMP_DIR/absolute-link-source"
mkdir -p "$ABSOLUTE_LINK_ROOT"
(
    cd "$ABSOLUTE_LINK_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'inside\n' > inside.txt
    ln -s "$ABSOLUTE_LINK_ROOT/inside.txt" absolute-link
    git add inside.txt absolute-link
    git commit -q -m "init with absolute symlink"
)
if _octopus_prepare_consultative_workspace "$ABSOLUTE_LINK_ROOT" >/dev/null 2>&1; then
    test_fail "expected an absolute symlink into the source to fail closed"
else
    test_pass
fi

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
NESTED_CHILD_ROOT="$TEST_TMP_DIR/nested-child"
mkdir -p "$NESTED_ROOT" "$NESTED_CHILD_ROOT/vendor"
(
    cd "$NESTED_CHILD_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'vendor/\n' > .gitignore
    printf 'nested tracked\n' > nested.txt
    git add nested.txt .gitignore
    git commit -q -m "nested init"
)
(
    cd "$NESTED_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'parent tracked\n' > parent.txt
    git add parent.txt
    git commit -q -m init
    git -c protocol.file.allow=always submodule add -q "$NESTED_CHILD_ROOT" nested-repo
    git commit -q -am "add nested repository"
    mkdir -p nested-repo/vendor
    printf 'nested vendored\n' > nested-repo/vendor/big.bin
)
workspace="$(_octopus_prepare_consultative_workspace "$NESTED_ROOT")"
if [[ -f "$workspace/parent.txt" && -f "$workspace/nested-repo/nested.txt" && ! -e "$workspace/nested-repo/vendor" ]] &&
   [[ "$(git -C "$workspace/nested-repo" log -1 --format=%s 2>/dev/null)" == "nested init" ]]; then
    test_pass
else
    test_fail "expected nested-repo/vendor absent, parent.txt and nested-repo/nested.txt present in $workspace"
fi
rm -rf "$(dirname "$workspace")"

test_case "nested repositories are excluded before the parent archive runs"
REAL_TAR="$(command -v tar)"
TAR_GUARD_BIN="$TEST_TMP_DIR/tar-guard-bin"
TAR_GUARD_MARKER="$TEST_TMP_DIR/tar-saw-nested-root"
mkdir -p "$TAR_GUARD_BIN"
cat > "$TAR_GUARD_BIN/tar" <<'EOF'
#!/usr/bin/env bash
original_args=("$@")
list_file=""
archive_root=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -C) archive_root="${2:-}"; shift ;;
        -T|--files-from) list_file="${2:-}"; shift ;;
        -T*) list_file="${1#-T}" ;;
        --files-from=*) list_file="${1#--files-from=}" ;;
    esac
    shift
done
if [[ "$archive_root" == "$NESTED_ROOT" && -n "$list_file" && "$list_file" != "-" ]]; then
    while IFS= read -r -d '' entry; do
        if [[ "${entry%/}" == "nested-repo" || "$entry" == nested-repo/* ]]; then
            printf 'nested repository reached parent archive\n' > "$TAR_GUARD_MARKER"
            exit 97
        fi
    done < "$list_file"
fi
exec "$REAL_TAR" "${original_args[@]}"
EOF
chmod +x "$TAR_GUARD_BIN/tar"
workspace="$(
    export PATH="$TAR_GUARD_BIN:$PATH" REAL_TAR TAR_GUARD_MARKER NESTED_ROOT
    _octopus_prepare_consultative_workspace "$NESTED_ROOT"
)"
if [[ ! -e "$TAR_GUARD_MARKER" && -f "$workspace/nested-repo/nested.txt" && ! -e "$workspace/nested-repo/vendor" ]]; then
    test_pass
else
    test_fail "expected the parent archive to omit nested-repo before recursively copying it"
fi
rm -rf "$(dirname "$workspace")"

# A tracked symlink that leaves source_root still grants the advisory process
# access to files outside the disposable workspace, even if tar preserves it
# as a symlink rather than materializing its target.
test_case "a tracked symlink outside the source repository is rejected"
SYMLINK_ROOT="$TEST_TMP_DIR/symlink-source"
OUTSIDE_ROOT="$TEST_TMP_DIR/symlink-outside"
mkdir -p "$SYMLINK_ROOT" "$OUTSIDE_ROOT"
(
    cd "$OUTSIDE_ROOT"
    printf 'outside secret\n' > secret.txt
)
(
    cd "$SYMLINK_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'main tracked\n' > main.txt
    ln -s "../symlink-outside/secret.txt" evil-link
    git add main.txt evil-link
    git commit -q -m "init with symlink"
)
if _octopus_prepare_consultative_workspace "$SYMLINK_ROOT" >/dev/null 2>&1; then
    test_fail "expected an external tracked symlink to make workspace preparation fail closed"
else
    test_pass
fi

test_case "a Git-aware copy failure never attempts a whole-tree copy"
COPY_GUARD_BIN="$TEST_TMP_DIR/copy-guard-bin"
COPY_GUARD_MARKER="$TEST_TMP_DIR/whole-tree-copy-attempted"
REAL_CP="$(command -v cp)"
mkdir -p "$COPY_GUARD_BIN"
cat > "$COPY_GUARD_BIN/tar" <<'EOF'
#!/usr/bin/env bash
exit 97
EOF
cat > "$COPY_GUARD_BIN/cp" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == "$SOURCE_ROOT/." ]]; then
        printf 'whole-tree copy attempted\n' > "$COPY_GUARD_MARKER"
    fi
done
exec "$REAL_CP" "$@"
EOF
chmod +x "$COPY_GUARD_BIN/tar" "$COPY_GUARD_BIN/cp"
if workspace="$(
    export PATH="$COPY_GUARD_BIN:$PATH" REAL_CP COPY_GUARD_MARKER SOURCE_ROOT
    _octopus_prepare_consultative_workspace "$SOURCE_ROOT"
)"; then
    copy_failure_rc=0
else
    copy_failure_rc=$?
fi
if [[ "$copy_failure_rc" -ne 0 && ! -e "$COPY_GUARD_MARKER" ]]; then
    test_pass
else
    test_fail "expected Git copy failure without any whole-tree cp attempt"
fi

test_summary
