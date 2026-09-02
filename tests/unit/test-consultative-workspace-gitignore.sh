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
    git branch -M main
    git checkout -q -b feature
    printf 'feature commit\n' > feature.txt
    git add feature.txt
    git commit -q -m feature
    git update-ref refs/remotes/origin/main refs/heads/main
    git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    git tag review-base refs/heads/main
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

test_case "the disposable workspace retains review base refs"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT")"
source_main="$(git -C "$SOURCE_ROOT" rev-parse main)"
source_origin_main="$(git -C "$SOURCE_ROOT" rev-parse origin/main)"
source_tag="$(git -C "$SOURCE_ROOT" rev-parse review-base)"
source_remote_head="$(git -C "$SOURCE_ROOT" symbolic-ref refs/remotes/origin/HEAD)"
source_review_diff="$(git -C "$SOURCE_ROOT" diff --stat main...HEAD)"
if [[ "$(git -C "$workspace" rev-parse main 2>/dev/null)" == "$source_main" ]] &&
   [[ "$(git -C "$workspace" rev-parse origin/main 2>/dev/null)" == "$source_origin_main" ]] &&
   [[ "$(git -C "$workspace" rev-parse review-base 2>/dev/null)" == "$source_tag" ]] &&
   [[ "$(git -C "$workspace" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)" == "$source_remote_head" ]] &&
   [[ "$(git -C "$workspace" diff --stat main...HEAD 2>/dev/null)" == "$source_review_diff" ]]; then
    git -C "$workspace" update-ref refs/heads/main HEAD
    if [[ "$(git -C "$SOURCE_ROOT" rev-parse main)" == "$source_main" ]] &&
       [[ "$(git -C "$workspace" rev-parse main)" == "$(git -C "$workspace" rev-parse HEAD)" ]] &&
       [[ "$(git -C "$workspace" rev-parse main)" != "$source_main" ]]; then
        test_pass
    else
        test_fail "workspace ref writes changed the source repository or failed to remain local"
    fi
else
    test_fail "expected local, remote-tracking, and symbolic review refs inside $workspace"
fi
rm -rf "$(dirname "$workspace")"

test_case "shallow repository history remains coherent in the disposable workspace"
SHALLOW_ORIGIN="$TEST_TMP_DIR/shallow-origin"
SHALLOW_ROOT="$TEST_TMP_DIR/shallow-source"
mkdir -p "$SHALLOW_ORIGIN"
(
    cd "$SHALLOW_ORIGIN"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'one\n' > history.txt
    git add history.txt
    git commit -q -m one
    printf 'two\n' >> history.txt
    git commit -qam two
)
git -c protocol.file.allow=always clone -q --depth 1 "file://$SHALLOW_ORIGIN" "$SHALLOW_ROOT"
source_shallow_log="$(git -C "$SHALLOW_ROOT" log --oneline)"
if workspace="$(_octopus_prepare_consultative_workspace "$SHALLOW_ROOT")" &&
   workspace_shallow_log="$(git -C "$workspace" log --oneline 2>/dev/null)" &&
   [[ "$(git -C "$workspace" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]] &&
   [[ "$workspace_shallow_log" == "$source_shallow_log" ]]; then
    test_pass
else
    test_fail "expected copied shallow history to stop at the same boundary as the source"
fi
[[ -z "${workspace:-}" ]] || rm -rf "$(dirname "$workspace")"

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

test_case "ambient repository selectors cannot redirect advisory Git writes to the source"
AMBIENT_ROOT="$TEST_TMP_DIR/ambient-git-source"
mkdir -p "$AMBIENT_ROOT"
(
    cd "$AMBIENT_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'source\n' > source.txt
    git add source.txt
    git commit -q -m init
)
AMBIENT_GIT_DIR="$(git -C "$AMBIENT_ROOT" rev-parse --absolute-git-dir)"
run_agent_sync() {
    git update-ref refs/heads/advisory-write HEAD
    printf 'review only\n'
}
ambient_old_pwd="$PWD"
cd "$AMBIENT_ROOT"
GIT_DIR="$AMBIENT_GIT_DIR" GIT_WORK_TREE="$AMBIENT_ROOT" run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1 || true
cd "$ambient_old_pwd"
unset -f run_agent_sync
if ! git -C "$AMBIENT_ROOT" show-ref --verify --quiet refs/heads/advisory-write; then
    test_pass
else
    test_fail "ambient GIT_DIR redirected an advisory Git write into the source repository"
fi

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

test_case "empty and fully ignored launch directories remain valid working directories"
mkdir -p "$SOURCE_ROOT/empty-subdir"
if empty_workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT/empty-subdir" 2>/dev/null)" &&
   ignored_workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT/vendor" 2>/dev/null)" &&
   [[ -d "$empty_workspace" && -d "$ignored_workspace" ]] &&
   [[ "$(git -C "$empty_workspace" rev-parse --show-toplevel 2>/dev/null)" == "$(dirname "$empty_workspace")" ]] &&
   [[ "$(git -C "$ignored_workspace" rev-parse --show-toplevel 2>/dev/null)" == "$(dirname "$ignored_workspace")" ]] &&
   [[ ! -e "$ignored_workspace/big.bin" ]]; then
    test_pass
else
    test_fail "expected empty and ignored source subdirectories to map to empty copied working directories"
fi
[[ -z "${empty_workspace:-}" ]] || rm -rf "$(dirname "$(dirname "$empty_workspace")")"
[[ -z "${ignored_workspace:-}" ]] || rm -rf "$(dirname "$(dirname "$ignored_workspace")")"

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

test_case "sparse checkout index flags remain exact in the disposable workspace"
SPARSE_ROOT="$TEST_TMP_DIR/sparse-source"
mkdir -p "$SPARSE_ROOT/keep" "$SPARSE_ROOT/omit"
(
    cd "$SPARSE_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'keep\n' > keep/file.txt
    printf 'omit\n' > omit/file.txt
    git add keep/file.txt omit/file.txt
    git commit -q -m init
    git sparse-checkout init --cone
    git sparse-checkout set keep
)
source_sparse_status="$(git -C "$SPARSE_ROOT" status --short)"
workspace="$(_octopus_prepare_consultative_workspace "$SPARSE_ROOT")"
workspace_sparse_status="$(git -C "$workspace" status --short 2>/dev/null)"
if [[ -z "$source_sparse_status" && "$workspace_sparse_status" == "$source_sparse_status" && ! -e "$workspace/omit/file.txt" ]]; then
    test_pass
else
    test_fail "expected sparse index flags to prevent false copied-workspace deletions: ${workspace_sparse_status:-<clean>}"
fi
rm -rf "$(dirname "$workspace")"

test_case "intent-to-add state remains exact and workspace index writes stay private"
INTENT_ROOT="$TEST_TMP_DIR/intent-source"
mkdir -p "$INTENT_ROOT"
(
    cd "$INTENT_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'base\n' > base.txt
    git add base.txt
    git commit -q -m init
    printf 'intent\n' > intent.txt
    git add -N intent.txt
)
intent_index="$(git -C "$INTENT_ROOT" rev-parse --git-path index)"
case "$intent_index" in /*) ;; *) intent_index="$INTENT_ROOT/$intent_index" ;; esac
intent_index_before="$(cksum "$intent_index")"
source_intent_status="$(git -C "$INTENT_ROOT" status --short)"
workspace="$(_octopus_prepare_consultative_workspace "$INTENT_ROOT")"
workspace_intent_status="$(git -C "$workspace" status --short 2>/dev/null)"
git -C "$workspace" add intent.txt
intent_index_after="$(cksum "$intent_index")"
if [[ "$workspace_intent_status" == "$source_intent_status" && "$intent_index_after" == "$intent_index_before" ]]; then
    test_pass
else
    test_fail "expected exact intent-to-add state and an isolated writable workspace index"
fi
rm -rf "$(dirname "$workspace")"

test_case "linked worktree split index and shared index stay coherent and private"
LINKED_REPO="$TEST_TMP_DIR/linked-repo"
LINKED_ROOT="$TEST_TMP_DIR/linked-worktree"
mkdir -p "$LINKED_REPO"
(
    cd "$LINKED_REPO"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'base\n' > tracked.txt
    git add tracked.txt
    git commit -q -m init
    git branch linked-review
    git worktree add -q "$LINKED_ROOT" linked-review
)
(
    cd "$LINKED_ROOT"
    git update-index --split-index
    printf 'unstaged\n' >> tracked.txt
    printf 'staged then modified\n' > staged.txt
    git add staged.txt
    printf 'worktree tail\n' >> staged.txt
    printf 'untracked\n' > untracked.txt
)
linked_index="$(git -C "$LINKED_ROOT" rev-parse --git-path index)"
linked_shared_index="$(git -C "$LINKED_ROOT" rev-parse --shared-index-path)"
case "$linked_index" in /*) ;; *) linked_index="$LINKED_ROOT/$linked_index" ;; esac
case "$linked_shared_index" in /*) ;; *) linked_shared_index="$LINKED_ROOT/$linked_shared_index" ;; esac
source_linked_status="$(git -C "$LINKED_ROOT" status --short)"
linked_index_before="$(cksum "$linked_index")"
linked_shared_before="$(cksum "$linked_shared_index")"
workspace="$(_octopus_prepare_consultative_workspace "$LINKED_ROOT")"
workspace_shared_index="$(git -C "$workspace" rev-parse --shared-index-path 2>/dev/null)"
case "$workspace_shared_index" in ""|/*) ;; *) workspace_shared_index="$workspace/$workspace_shared_index" ;; esac
workspace_linked_status="$(git -C "$workspace" status --short 2>/dev/null)"
git -C "$workspace" add tracked.txt
linked_index_after="$(cksum "$linked_index")"
linked_shared_after="$(cksum "$linked_shared_index")"
if [[ -f "$LINKED_ROOT/.git" && -d "$workspace/.git" && -n "$workspace_shared_index" && -f "$workspace_shared_index" ]] &&
   [[ "$workspace_linked_status" == "$source_linked_status" ]] &&
   [[ "$linked_index_after" == "$linked_index_before" && "$linked_shared_after" == "$linked_shared_before" ]]; then
    test_pass
else
    test_fail "expected linked-worktree split index state and private workspace index writes: source=[$source_linked_status] workspace=[$workspace_linked_status] shared=${workspace_shared_index:-missing}"
fi
rm -rf "$(dirname "$workspace")"

test_case "cleanup removes only the allocated temp root when TMPDIR is inside another repository"
CLEANUP_CONTAINER="$TEST_TMP_DIR/cleanup-container"
CLEANUP_OUTER_REPO="$CLEANUP_CONTAINER/unrelated-repo"
CLEANUP_TMPDIR="$CLEANUP_OUTER_REPO/tmp"
CLEANUP_SOURCE="$TEST_TMP_DIR/cleanup-plain-source"
CLEANUP_SENTINEL="$CLEANUP_CONTAINER/outside-sentinel"
CLEANUP_REPO_SENTINEL="$CLEANUP_OUTER_REPO/repo-sentinel"
UNSAFE_CLEANUP_MARKER="$TEST_TMP_DIR/unsafe-cleanup-target"
mkdir -p "$CLEANUP_TMPDIR" "$CLEANUP_SOURCE"
git -C "$CLEANUP_OUTER_REPO" init -q
printf 'outside\n' > "$CLEANUP_SENTINEL"
printf 'repo\n' > "$CLEANUP_REPO_SENTINEL"
printf 'plain\n' > "$CLEANUP_SOURCE/file.txt"
CLEANUP_TMPDIR_PHYSICAL="$(cd "$CLEANUP_TMPDIR" && pwd -P)"
rm() {
    if [[ "${1:-}" == "-rf" ]]; then
        case "${2:-}" in
            "$CLEANUP_TMPDIR_PHYSICAL"/octopus-consultative.*) ;;
            *)
                printf '%s\n' "${2:-missing}" > "$UNSAFE_CLEANUP_MARKER"
                return 1
                ;;
        esac
    fi
    command rm "$@"
}
run_agent_sync() {
    printf 'review only\n'
}
cleanup_old_pwd="$PWD"
cd "$CLEANUP_SOURCE"
TMPDIR="$CLEANUP_TMPDIR" run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1 || true
cd "$cleanup_old_pwd"
unset -f rm run_agent_sync
cleanup_residue="$(find "$CLEANUP_TMPDIR" -maxdepth 1 -type d -name 'octopus-consultative.*' -print)"
if [[ -f "$CLEANUP_SENTINEL" && -f "$CLEANUP_REPO_SENTINEL" && ! -e "$UNSAFE_CLEANUP_MARKER" && -z "$cleanup_residue" ]]; then
    test_pass
else
    test_fail "expected exact temp-root cleanup without touching the enclosing repository"
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
