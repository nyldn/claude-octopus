#!/usr/bin/env bash
# Regression tests for #980: advisory copies honor Git ignore rules without
# exposing source repository control-plane metadata or writable source state.
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
    printf 'modified working tree\n' > tracked.txt
    printf 'subdirectory modified\n' > subdir/context.txt
    printf 'staged\n' > staged.txt
    git add staged.txt
    printf 'staged and modified working tree\n' > staged.txt
    printf 'untracked but not ignored\n' > untracked.txt
)

test_case "Git sources copy exact eligible working-tree bytes without Git metadata"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT")"
if [[ "$(cat "$workspace/tracked.txt" 2>/dev/null)" == "modified working tree" ]] &&
   [[ "$(cat "$workspace/staged.txt" 2>/dev/null)" == "staged and modified working tree" ]] &&
   [[ "$(cat "$workspace/untracked.txt" 2>/dev/null)" == "untracked but not ignored" ]] &&
   [[ ! -e "$workspace/vendor" && ! -e "$workspace/.git" ]]; then
    test_pass
else
    test_fail "expected exact tracked/untracked-not-ignored bytes, no vendor tree, and no .git"
fi
rm -rf "$(dirname "$workspace")"

test_case "ambient Git config is ignored and advisory execution cannot mutate source Git state"
AMBIENT_EXCLUDES="$TEST_TMP_DIR/ambient-excludes"
AMBIENT_CONFIG="$TEST_TMP_DIR/ambient-gitconfig"
AMBIENT_MARKER="$TEST_TMP_DIR/ambient-git-env-leaked"
printf 'untracked.txt\n' > "$AMBIENT_EXCLUDES"
printf '[core]\n\texcludesFile = %s\n' "$AMBIENT_EXCLUDES" > "$AMBIENT_CONFIG"
source_index="$(git -C "$SOURCE_ROOT" rev-parse --git-path index)"
case "$source_index" in /*) ;; *) source_index="$SOURCE_ROOT/$source_index" ;; esac
source_index_before="$(cksum "$source_index")"
source_head_before="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
if workspace=$(
    export GIT_CONFIG="$AMBIENT_CONFIG"
    export GIT_CONFIG_GLOBAL="$AMBIENT_CONFIG"
    export GIT_CONFIG_SYSTEM="$AMBIENT_CONFIG"
    export GIT_CONFIG_NOSYSTEM=1
    _octopus_prepare_consultative_workspace "$SOURCE_ROOT"
) && [[ -f "$workspace/untracked.txt" && ! -e "$workspace/.git" ]]; then
    prepare_isolated=true
else
    prepare_isolated=false
fi
[[ -z "${workspace:-}" ]] || rm -rf "$(dirname "$workspace")"

run_agent_sync() {
    local name
    while IFS= read -r name; do
        case "$name" in
            GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|GIT_COMMON_DIR|GIT_NAMESPACE|GIT_CEILING_DIRECTORIES|GIT_PREFIX|GIT_SUPER_PREFIX|GIT_CONFIG|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_CONFIG_NOSYSTEM|GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*|GIT_QUARANTINE_PATH|GIT_DEFAULT_HASH)
                printf '%s\n' "$name" > "$AMBIENT_MARKER"
                ;;
        esac
    done < <(compgen -v)
    git update-ref refs/heads/advisory-write HEAD >/dev/null 2>&1 || true
    printf 'review only\n'
}
ambient_git_dir="$(git -C "$SOURCE_ROOT" rev-parse --absolute-git-dir)"
old_pwd="$PWD"
cd "$SOURCE_ROOT"
GIT_DIR="$ambient_git_dir" \
GIT_WORK_TREE="$SOURCE_ROOT" \
GIT_INDEX_FILE="$source_index" \
GIT_CONFIG="$AMBIENT_CONFIG" \
GIT_CONFIG_GLOBAL="$AMBIENT_CONFIG" \
GIT_CONFIG_SYSTEM="$AMBIENT_CONFIG" \
GIT_CONFIG_NOSYSTEM=1 \
GIT_CONFIG_COUNT=1 \
GIT_CONFIG_KEY_0=core.hooksPath \
GIT_CONFIG_VALUE_0="$TEST_TMP_DIR/hooks" \
run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1 || true
cd "$old_pwd"
unset -f run_agent_sync
source_index_after="$(cksum "$source_index")"
source_head_after="$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
if [[ "$prepare_isolated" == "true" && ! -e "$AMBIENT_MARKER" ]] &&
   [[ "$source_index_after" == "$source_index_before" && "$source_head_after" == "$source_head_before" ]] &&
   ! git -C "$SOURCE_ROOT" show-ref --verify --quiet refs/heads/advisory-write; then
    test_pass
else
    test_fail "expected Git config isolation and unchanged source index, HEAD, and refs"
fi

test_case "a launch from a repository subdirectory returns its copied subdirectory"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT/subdir")"
workspace_root="$(dirname "$workspace")"
if [[ "$workspace" == */workspace/subdir ]] &&
   [[ "$(cat "$workspace/context.txt" 2>/dev/null)" == "subdirectory modified" ]] &&
   [[ ! -e "$workspace_root/.git" ]]; then
    test_pass
else
    test_fail "expected current subdirectory bytes at the matching metadata-free copied path"
fi
rm -rf "$(dirname "$workspace_root")"

test_case "empty and fully ignored launch directories remain valid working directories"
mkdir -p "$SOURCE_ROOT/empty-subdir"
if empty_workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT/empty-subdir" 2>/dev/null)" &&
   ignored_workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT/vendor" 2>/dev/null)" &&
   [[ -d "$empty_workspace" && -d "$ignored_workspace" ]] &&
   [[ "$empty_workspace" == */workspace/empty-subdir ]] &&
   [[ "$ignored_workspace" == */workspace/vendor ]] &&
   [[ ! -e "$ignored_workspace/big.bin" ]] &&
   [[ ! -e "$(dirname "$empty_workspace")/.git" && ! -e "$(dirname "$ignored_workspace")/.git" ]]; then
    test_pass
else
    test_fail "expected empty and ignored source subdirectories to map to empty copied directories"
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

test_case "a symlink in an eligible path's ancestor chain fails closed"
ANCESTOR_ROOT="$TEST_TMP_DIR/ancestor-link-source"
ANCESTOR_GIT_BIN="$TEST_TMP_DIR/ancestor-git-bin"
REAL_GIT="$(command -v git)"
mkdir -p "$ANCESTOR_ROOT/tracked-dir"
(
    cd "$ANCESTOR_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'tracked\n' > tracked-dir/file.txt
    git add tracked-dir/file.txt
    git commit -q -m init
    mv tracked-dir actual-dir
    ln -s actual-dir tracked-dir
)
mkdir -p "$ANCESTOR_GIT_BIN"
cat > "$ANCESTOR_GIT_BIN/git" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == "ls-files" ]]; then
        printf 'tracked-dir/file.txt\0'
        exit 0
    fi
done
exec "$REAL_GIT" "$@"
EOF
chmod +x "$ANCESTOR_GIT_BIN/git"
if PATH="$ANCESTOR_GIT_BIN:$PATH" REAL_GIT="$REAL_GIT" \
   _octopus_prepare_consultative_workspace "$ANCESTOR_ROOT" >/dev/null 2>&1; then
    test_fail "expected a tracked path beneath a symlink ancestor to fail closed"
else
    test_pass
fi

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

test_case "a tracked symlink outside the source repository is rejected"
SYMLINK_ROOT="$TEST_TMP_DIR/symlink-source"
OUTSIDE_ROOT="$TEST_TMP_DIR/symlink-outside"
mkdir -p "$SYMLINK_ROOT" "$OUTSIDE_ROOT"
printf 'outside secret\n' > "$OUTSIDE_ROOT/secret.txt"
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

test_case "non-Git source roots still fall back to a full copy"
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

test_case "nested Git work trees recursively honor their own ignore rules without metadata"
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
    printf 'nested working tree\n' > nested-repo/nested.txt
    mkdir -p nested-repo/vendor
    printf 'nested vendored\n' > nested-repo/vendor/big.bin
)
workspace="$(_octopus_prepare_consultative_workspace "$NESTED_ROOT")"
if [[ "$(cat "$workspace/parent.txt" 2>/dev/null)" == "parent tracked" ]] &&
   [[ "$(cat "$workspace/nested-repo/nested.txt" 2>/dev/null)" == "nested working tree" ]] &&
   [[ ! -e "$workspace/nested-repo/vendor" ]] &&
   [[ ! -e "$workspace/.git" && ! -e "$workspace/nested-repo/.git" ]]; then
    test_pass
else
    test_fail "expected recursively filtered nested bytes without parent or nested .git metadata"
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
