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
mkdir -p "$SOURCE_ROOT/vendor" "$SOURCE_ROOT/subdir" "$SOURCE_ROOT/ordinary-dir"
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
    printf 'subdirectory untracked\n' > subdir/untracked.txt
    printf 'ordinary untracked directory\n' > ordinary-dir/content.txt
)

test_case "Git sources copy exact eligible working-tree bytes without Git metadata"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT")"
if [[ "$(cat "$workspace/tracked.txt" 2>/dev/null)" == "modified working tree" ]] &&
   [[ "$(cat "$workspace/staged.txt" 2>/dev/null)" == "staged and modified working tree" ]] &&
   [[ "$(cat "$workspace/untracked.txt" 2>/dev/null)" == "untracked but not ignored" ]] &&
   [[ "$(cat "$workspace/ordinary-dir/content.txt" 2>/dev/null)" == "ordinary untracked directory" ]] &&
   [[ ! -e "$workspace/vendor" && ! -e "$workspace/.git" ]]; then
    test_pass
else
    test_fail "expected exact tracked/untracked-not-ignored bytes, no vendor tree, and no .git"
fi
rm -rf "$(dirname "$workspace")"

test_case "broken nested Git discovery fails closed before nested metadata or ignored bytes are archived"
BROKEN_NESTED_ROOT="$TEST_TMP_DIR/broken-nested-source"
BROKEN_NESTED_CHILD="$TEST_TMP_DIR/broken-nested-child"
BROKEN_NESTED_TMPDIR="$TEST_TMP_DIR/broken-nested-tmp"
mkdir -p "$BROKEN_NESTED_ROOT" "$BROKEN_NESTED_CHILD/vendor" "$BROKEN_NESTED_TMPDIR"
(
    cd "$BROKEN_NESTED_CHILD"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'vendor/\n' > .gitignore
    printf 'nested tracked\n' > nested.txt
    printf 'nested ignored\n' > vendor/ignored.bin
    git add .gitignore nested.txt
    git commit -q -m init
)
(
    cd "$BROKEN_NESTED_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'parent tracked\n' > parent.txt
    git add parent.txt
    git commit -q -m init
    git -c protocol.file.allow=always submodule add -q "$BROKEN_NESTED_CHILD" nested-repo
    git commit -q -am "add nested repository"
    printf 'gitdir: /missing/octopus-nested-gitdir\n' > nested-repo/.git
)
workspace=""
if workspace="$(TMPDIR="$BROKEN_NESTED_TMPDIR" _octopus_prepare_consultative_workspace "$BROKEN_NESTED_ROOT" 2>/dev/null)"; then
    broken_nested_rc=0
else
    broken_nested_rc=$?
fi
broken_nested_leak=false
if [[ -n "$workspace" ]] &&
   { [[ -e "$workspace/nested-repo/.git" ]] || [[ -e "$workspace/nested-repo/vendor/ignored.bin" ]]; }; then
    broken_nested_leak=true
fi
broken_nested_residue="$(find "$BROKEN_NESTED_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
if [[ "$broken_nested_rc" -ne 0 && "$broken_nested_leak" == "false" && -z "$broken_nested_residue" ]]; then
    test_pass
else
    test_fail "expected broken nested discovery to fail before archive: rc=$broken_nested_rc leak=$broken_nested_leak residue=${broken_nested_residue:-none}"
fi
rm -rf "$BROKEN_NESTED_TMPDIR"

test_case "a registered gitlink with missing nested metadata fails closed"
MISSING_NESTED_TMPDIR="$TEST_TMP_DIR/missing-nested-tmp"
rm -f "$BROKEN_NESTED_ROOT/nested-repo/.git"
mkdir -p "$MISSING_NESTED_TMPDIR"
workspace=""
if workspace="$(TMPDIR="$MISSING_NESTED_TMPDIR" _octopus_prepare_consultative_workspace "$BROKEN_NESTED_ROOT" 2>/dev/null)"; then
    missing_nested_rc=0
else
    missing_nested_rc=$?
fi
missing_nested_residue="$(find "$MISSING_NESTED_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
if [[ "$missing_nested_rc" -ne 0 && -z "$missing_nested_residue" ]]; then
    test_pass
else
    test_fail "expected a registered gitlink without usable metadata to fail closed: rc=$missing_nested_rc residue=${missing_nested_residue:-none}"
fi
rm -rf "$MISSING_NESTED_TMPDIR"

test_case "Git discovery errors fail closed without a whole-tree copy"
DISCOVERY_GIT_BIN="$TEST_TMP_DIR/discovery-git-bin"
DISCOVERY_CP_MARKER="$TEST_TMP_DIR/discovery-whole-tree-copy"
DISCOVERY_COUNT="$TEST_TMP_DIR/discovery-count"
REAL_GIT="$(command -v git)"
REAL_CP="$(command -v cp)"
mkdir -p "$DISCOVERY_GIT_BIN"
cat > "$DISCOVERY_GIT_BIN/git" <<'EOF'
#!/usr/bin/env bash
is_discovery=false
for arg in "$@"; do
    [[ "$arg" == "--is-inside-work-tree" ]] && is_discovery=true
done
if [[ "$is_discovery" == "true" && ! -e "$DISCOVERY_COUNT" ]]; then
    printf 'failed once\n' > "$DISCOVERY_COUNT"
    exit 128
fi
exec "$REAL_GIT" "$@"
EOF
cat > "$DISCOVERY_GIT_BIN/cp" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == "$SOURCE_ROOT/." ]]; then
        printf 'whole-tree copy attempted\n' > "$DISCOVERY_CP_MARKER"
        exit 91
    fi
done
exec "$REAL_CP" "$@"
EOF
chmod +x "$DISCOVERY_GIT_BIN/git" "$DISCOVERY_GIT_BIN/cp"
if workspace="$(
    export PATH="$DISCOVERY_GIT_BIN:$PATH"
    export DISCOVERY_COUNT DISCOVERY_CP_MARKER REAL_GIT REAL_CP SOURCE_ROOT
    _octopus_prepare_consultative_workspace "$SOURCE_ROOT"
)"; then
    discovery_rc=0
else
    discovery_rc=$?
fi
if [[ "$discovery_rc" -ne 0 && ! -e "$DISCOVERY_CP_MARKER" ]]; then
    test_pass
else
    test_fail "expected discovery failure to prevent copying .git and ignored payloads"
fi

test_case "ambient Git config is ignored and advisory execution cannot mutate source Git state"
AMBIENT_EXCLUDES="$TEST_TMP_DIR/ambient-excludes"
AMBIENT_CONFIG="$TEST_TMP_DIR/ambient-gitconfig"
AMBIENT_MARKER="$TEST_TMP_DIR/ambient-git-env-leaked"
AMBIENT_DISPATCH_MARKER="$TEST_TMP_DIR/ambient-dispatch-ran"
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
    printf 'dispatched\n' > "$AMBIENT_DISPATCH_MARKER"
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
if [[ "$prepare_isolated" == "true" && -f "$AMBIENT_DISPATCH_MARKER" && ! -e "$AMBIENT_MARKER" ]] &&
   [[ "$source_index_after" == "$source_index_before" && "$source_head_after" == "$source_head_before" ]] &&
   ! git -C "$SOURCE_ROOT" show-ref --verify --quiet refs/heads/advisory-write; then
    test_pass
else
    test_fail "expected Git config isolation and unchanged source index, HEAD, and refs"
fi

test_case "a repository subdirectory launch copies only eligible content in that subtree"
workspace="$(_octopus_prepare_consultative_workspace "$SOURCE_ROOT/subdir")"
workspace_root="$(dirname "$workspace")"
if [[ "$workspace" == */workspace/subdir ]] &&
   [[ "$(cat "$workspace/context.txt" 2>/dev/null)" == "subdirectory modified" ]] &&
   [[ "$(cat "$workspace/untracked.txt" 2>/dev/null)" == "subdirectory untracked" ]] &&
   [[ ! -e "$workspace_root/tracked.txt" && ! -e "$workspace_root/staged.txt" ]] &&
   [[ ! -e "$workspace_root/untracked.txt" && ! -e "$workspace_root/inside.txt" ]] &&
   [[ ! -e "$workspace_root/.git" ]]; then
    test_pass
else
    test_fail "expected only current tracked and nonignored subdirectory bytes at the matching metadata-free copied path"
fi
rm -rf "$(dirname "$workspace_root")"

test_case "a selected metacharacter subtree uses a literal pathspec"
METACHAR_ROOT="$TEST_TMP_DIR/metachar-source"
METACHAR_SCOPE='scope[one]:*?'
mkdir -p "$METACHAR_ROOT/$METACHAR_SCOPE"
(
    cd "$METACHAR_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'metachar tracked\n' > "$METACHAR_SCOPE/tracked.txt"
    printf 'unrelated tracked\n' > unrelated.txt
    git add -- "$METACHAR_SCOPE/tracked.txt" unrelated.txt
    git commit -q -m init
    printf 'metachar untracked\n' > "$METACHAR_SCOPE/untracked.txt"
)
workspace="$(_octopus_prepare_consultative_workspace "$METACHAR_ROOT/$METACHAR_SCOPE")"
workspace_root="$(dirname "$workspace")"
if [[ "${workspace##*/workspace/}" == "$METACHAR_SCOPE" ]] &&
   [[ "$(cat "$workspace/tracked.txt" 2>/dev/null)" == "metachar tracked" ]] &&
   [[ "$(cat "$workspace/untracked.txt" 2>/dev/null)" == "metachar untracked" ]] &&
   [[ ! -e "$workspace_root/unrelated.txt" ]]; then
    test_pass
else
    test_fail "expected literal scoped copy for a directory containing Git pathspec metacharacters"
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

SCOPED_LINK_ROOT="$TEST_TMP_DIR/scoped-link-source"
SCOPED_LINK_TMPDIR="$TEST_TMP_DIR/scoped-link-tmp"
mkdir -p "$SCOPED_LINK_ROOT/selected/deeper" "$SCOPED_LINK_TMPDIR"
(
    cd "$SCOPED_LINK_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'selected target\n' > selected/inside.txt
    printf 'repository sibling\n' > outside.txt
    ln -s ../inside.txt selected/deeper/safe-link
    git add selected/inside.txt selected/deeper/safe-link outside.txt
    git commit -q -m init
)

test_case "a relative symlink confined to the selected subtree remains usable"
workspace="$(_octopus_prepare_consultative_workspace "$SCOPED_LINK_ROOT/selected")"
workspace_root="$(dirname "$workspace")"
if [[ -L "$workspace/deeper/safe-link" ]] &&
   [[ "$(cat "$workspace/deeper/safe-link" 2>/dev/null)" == "selected target" ]] &&
   [[ ! -e "$workspace_root/outside.txt" ]]; then
    test_pass
else
    test_fail "expected an in-scope relative symlink without repository siblings"
fi
rm -rf "$(dirname "$workspace_root")"

test_case "a relative symlink cannot escape the selected subtree into a repository sibling"
ln -s ../outside.txt "$SCOPED_LINK_ROOT/selected/outside-link"
git -C "$SCOPED_LINK_ROOT" add selected/outside-link
workspace=""
if workspace="$(TMPDIR="$SCOPED_LINK_TMPDIR" _octopus_prepare_consultative_workspace "$SCOPED_LINK_ROOT/selected" 2>/dev/null)"; then
    scoped_link_rc=0
else
    scoped_link_rc=$?
fi
scoped_link_residue="$(find "$SCOPED_LINK_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
if [[ "$scoped_link_rc" -ne 0 && -z "$scoped_link_residue" ]]; then
    test_pass
else
    test_fail "expected selected-subtree symlink escape to fail closed: rc=$scoped_link_rc residue=${scoped_link_residue:-none}"
fi
rm -rf "$SCOPED_LINK_TMPDIR"

test_case "a confined dangling tracked relative symlink is preserved"
DANGLING_ROOT="$TEST_TMP_DIR/dangling-link-source"
mkdir -p "$DANGLING_ROOT/links"
(
    cd "$DANGLING_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    ln -s ../future/missing.txt links/pending
    git add links/pending
    git commit -q -m "init with confined dangling symlink"
)
if workspace="$(_octopus_prepare_consultative_workspace "$DANGLING_ROOT" 2>/dev/null)" &&
   [[ -L "$workspace/links/pending" ]] &&
   [[ "$(readlink "$workspace/links/pending")" == "../future/missing.txt" ]] &&
   [[ ! -e "$workspace/links/pending" ]]; then
    test_pass
else
    test_fail "expected the confined dangling symlink target to remain unchanged"
fi
[[ -z "${workspace:-}" ]] || rm -rf "$(dirname "$workspace")"

test_case "a dangling tracked relative symlink with a lexical escape is rejected"
DANGLING_ESCAPE_ROOT="$TEST_TMP_DIR/dangling-escape-source"
mkdir -p "$DANGLING_ESCAPE_ROOT/links"
(
    cd "$DANGLING_ESCAPE_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    ln -s ../../outside/missing.txt links/escape
    git add links/escape
    git commit -q -m "init with escaping dangling symlink"
)
if _octopus_prepare_consultative_workspace "$DANGLING_ESCAPE_ROOT" >/dev/null 2>&1; then
    test_fail "expected a dangling symlink target outside the workspace to fail closed"
else
    test_pass
fi

test_case "a symlink in an eligible path's ancestor chain fails closed"
ANCESTOR_ROOT="$TEST_TMP_DIR/ancestor-link-source"
ANCESTOR_GIT_BIN="$TEST_TMP_DIR/ancestor-git-bin"
ANCESTOR_REAL_GIT="$(command -v git)"
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
ancestor_path_before="$PATH"
ancestor_real_git_before="${REAL_GIT:-}"
REAL_GIT="caller-real-git-sentinel"
set -o posix
if (
    export PATH="$ANCESTOR_GIT_BIN:$PATH"
    export REAL_GIT="$ANCESTOR_REAL_GIT"
    _octopus_prepare_consultative_workspace "$ANCESTOR_ROOT" >/dev/null 2>&1
); then
    ancestor_rejected=false
else
    ancestor_rejected=true
fi
if [[ "$PATH" == "$ancestor_path_before" && "$REAL_GIT" == "caller-real-git-sentinel" ]]; then
    ancestor_env_isolated=true
else
    ancestor_env_isolated=false
fi
set +o posix
PATH="$ancestor_path_before"
export PATH
REAL_GIT="$ancestor_real_git_before"
if [[ "$ancestor_rejected" == "true" && "$ancestor_env_isolated" == "true" ]]; then
    test_pass
else
    test_fail "expected a symlink-ancestor rejection without PATH or REAL_GIT leakage"
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

test_case "a selected subtree retains nested Git content without copying repository siblings"
NESTED_SUBTREE_ROOT="$TEST_TMP_DIR/nested-subtree-source"
NESTED_SUBTREE_CHILD="$TEST_TMP_DIR/nested-subtree-child"
mkdir -p "$NESTED_SUBTREE_ROOT/selected" "$NESTED_SUBTREE_CHILD/vendor"
(
    cd "$NESTED_SUBTREE_CHILD"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'vendor/\n' > .gitignore
    printf 'nested tracked\n' > nested.txt
    git add nested.txt .gitignore
    git commit -q -m "nested init"
)
(
    cd "$NESTED_SUBTREE_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'selected tracked\n' > selected/context.txt
    printf 'unrelated tracked\n' > unrelated.txt
    git add selected/context.txt unrelated.txt
    git commit -q -m init
    git -c protocol.file.allow=always submodule add -q "$NESTED_SUBTREE_CHILD" selected/nested-repo
    git commit -q -am "add selected nested repository"
    printf 'selected untracked\n' > selected/local.txt
    printf 'unrelated untracked\n' > unrelated-local.txt
    printf 'nested working tree\n' > selected/nested-repo/nested.txt
    mkdir -p selected/nested-repo/vendor
    printf 'nested vendored\n' > selected/nested-repo/vendor/big.bin
)
workspace="$(_octopus_prepare_consultative_workspace "$NESTED_SUBTREE_ROOT/selected")"
workspace_root="$(dirname "$workspace")"
if [[ "$workspace" == */workspace/selected ]] &&
   [[ "$(cat "$workspace/context.txt" 2>/dev/null)" == "selected tracked" ]] &&
   [[ "$(cat "$workspace/local.txt" 2>/dev/null)" == "selected untracked" ]] &&
   [[ "$(cat "$workspace/nested-repo/nested.txt" 2>/dev/null)" == "nested working tree" ]] &&
   [[ ! -e "$workspace/nested-repo/vendor" && ! -e "$workspace/nested-repo/.git" ]] &&
   [[ ! -e "$workspace_root/unrelated.txt" && ! -e "$workspace_root/unrelated-local.txt" ]]; then
    test_pass
else
    test_fail "expected scoped parent bytes and recursively filtered nested content without repository siblings"
fi
rm -rf "$(dirname "$workspace_root")"

test_case "an empty parent copy list skips tar and still copies nested work trees"
NESTED_ONLY_ROOT="$TEST_TMP_DIR/nested-only-source"
NESTED_ONLY_TAR_BIN="$TEST_TMP_DIR/nested-only-tar-bin"
NESTED_ONLY_TAR_MARKER="$TEST_TMP_DIR/nested-only-parent-tar-ran"
REAL_TAR="$(command -v tar)"
mkdir -p "$NESTED_ONLY_ROOT" "$NESTED_ONLY_TAR_BIN"
git -C "$NESTED_ONLY_ROOT" init -q
git -C "$NESTED_ONLY_ROOT" config user.email "test@example.com"
git -C "$NESTED_ONLY_ROOT" config user.name "test"
git clone -q "$NESTED_CHILD_ROOT" "$NESTED_ONLY_ROOT/nested-repo"
nested_only_oid="$(git -C "$NESTED_ONLY_ROOT/nested-repo" rev-parse HEAD)"
git -C "$NESTED_ONLY_ROOT" update-index --add --cacheinfo 160000 "$nested_only_oid" nested-repo
git -C "$NESTED_ONLY_ROOT" commit -q -m "nested-only parent"
printf 'nested-only working tree\n' > "$NESTED_ONLY_ROOT/nested-repo/nested.txt"
NESTED_ONLY_ROOT="$(cd "$NESTED_ONLY_ROOT" && pwd -P)"
cat > "$NESTED_ONLY_TAR_BIN/tar" <<'EOF'
#!/usr/bin/env bash
original_args=("$@")
archive_root=""
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "-C" ]]; then
        archive_root="${2:-}"
        shift
    fi
    shift
done
if [[ "$archive_root" == "$NESTED_ONLY_ROOT" ]]; then
    printf 'parent tar ran\n' > "$NESTED_ONLY_TAR_MARKER"
    exit 97
fi
exec "$REAL_TAR" "${original_args[@]}"
EOF
chmod +x "$NESTED_ONLY_TAR_BIN/tar"
nested_only_rc=0
if workspace="$(
    export PATH="$NESTED_ONLY_TAR_BIN:$PATH"
    export REAL_TAR NESTED_ONLY_ROOT NESTED_ONLY_TAR_MARKER
    _octopus_prepare_consultative_workspace "$NESTED_ONLY_ROOT"
)"; then
    nested_only_rc=0
else
    nested_only_rc=$?
fi
if [[ "$nested_only_rc" -eq 0 && ! -e "$NESTED_ONLY_TAR_MARKER" ]] &&
   [[ "$(cat "$workspace/nested-repo/nested.txt" 2>/dev/null)" == "nested-only working tree" ]] &&
   [[ ! -e "$workspace/nested-repo/.git" ]]; then
    test_pass
else
    test_fail "expected nested copy without invoking tar for an empty parent list: rc=$nested_only_rc"
fi
[[ -z "${workspace:-}" ]] || rm -rf "$(dirname "$workspace")"

test_case "nested repositories are excluded before the parent archive runs"
NESTED_ROOT="$(cd "$NESTED_ROOT" && pwd -P)"
REAL_TAR="$(command -v tar)"
TAR_GUARD_BIN="$TEST_TMP_DIR/tar-guard-bin"
TAR_GUARD_MARKER="$TEST_TMP_DIR/tar-saw-nested-root"
TAR_GUARD_EXECUTED="$TEST_TMP_DIR/tar-guard-executed"
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
    printf 'guard executed\n' > "$TAR_GUARD_EXECUTED"
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
    export PATH="$TAR_GUARD_BIN:$PATH" REAL_TAR TAR_GUARD_MARKER TAR_GUARD_EXECUTED NESTED_ROOT
    _octopus_prepare_consultative_workspace "$NESTED_ROOT"
)"
if [[ -f "$TAR_GUARD_EXECUTED" && ! -e "$TAR_GUARD_MARKER" ]] &&
   [[ -f "$workspace/nested-repo/nested.txt" && ! -e "$workspace/nested-repo/vendor" ]]; then
    test_pass
else
    test_fail "expected the parent archive to omit nested-repo before recursively copying it"
fi
rm -rf "$(dirname "$workspace")"

test_case "Git copy lists use one owned directory and clean it after success"
COPY_LIST_TMPDIR="$TEST_TMP_DIR/copy-list-tmp"
COPY_LIST_WORKSPACE="$TEST_TMP_DIR/copy-list-workspace"
COPY_LIST_MKTEMP_BIN="$TEST_TMP_DIR/copy-list-mktemp-bin"
COPY_LIST_MKTEMP_CALLS="$TEST_TMP_DIR/copy-list-mktemp-calls"
REAL_MKTEMP="$(command -v mktemp)"
mkdir -p "$COPY_LIST_TMPDIR" "$COPY_LIST_WORKSPACE" "$COPY_LIST_MKTEMP_BIN"
cat > "$COPY_LIST_MKTEMP_BIN/mktemp" <<'EOF'
#!/usr/bin/env bash
printf 'argc=%s first=%s second=%s\n' "$#" "${1:-}" "${2:-}" >> "$COPY_LIST_MKTEMP_CALLS"
exec "$REAL_MKTEMP" "$@"
EOF
chmod +x "$COPY_LIST_MKTEMP_BIN/mktemp"
copy_list_rc=0
if (
    export TMPDIR="$COPY_LIST_TMPDIR"
    export PATH="$COPY_LIST_MKTEMP_BIN:$PATH"
    export COPY_LIST_MKTEMP_CALLS REAL_MKTEMP
    _octopus_copy_git_tracked_tree "$SOURCE_ROOT" "$COPY_LIST_WORKSPACE"
); then
    copy_list_rc=0
else
    copy_list_rc=$?
fi
copy_list_call_count="$(wc -l < "$COPY_LIST_MKTEMP_CALLS" | tr -d ' ')"
copy_list_residue="$(find "$COPY_LIST_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
if [[ "$copy_list_rc" -eq 0 && "$copy_list_call_count" == "1" && -z "$copy_list_residue" ]] &&
   grep -Eq '^argc=2 first=-d second=.*/octopus-copy-lists\.XXXXXX$' "$COPY_LIST_MKTEMP_CALLS"; then
    test_pass
else
    test_fail "expected one cleaned mktemp -d list allocation: rc=$copy_list_rc calls=$copy_list_call_count residue=$copy_list_residue"
fi

test_case "copy and nested list append failures return nonzero and remove list state"
append_failure_failed=false
append_failure_details=""
for append_failure_kind in copy nested; do
    APPEND_FAILURE_TMPDIR="$TEST_TMP_DIR/append-failure-${append_failure_kind}-tmp"
    APPEND_FAILURE_WORKSPACE="$TEST_TMP_DIR/append-failure-${append_failure_kind}-workspace"
    mkdir -p "$APPEND_FAILURE_TMPDIR" "$APPEND_FAILURE_WORKSPACE"
    case "$append_failure_kind" in
        copy) APPEND_FAILURE_SOURCE="$SOURCE_ROOT" ;;
        nested) APPEND_FAILURE_SOURCE="$NESTED_ROOT" ;;
    esac
    if (
        export TMPDIR="$APPEND_FAILURE_TMPDIR"
        export APPEND_FAILURE_KIND="$append_failure_kind"
        printf() {
            if [[ "${1:-}" == '%s\0' ]]; then
                case "$APPEND_FAILURE_KIND" in
                    copy) return 91 ;;
                    nested) [[ "${2:-}" == "nested-repo" ]] && return 92 ;;
                esac
            fi
            builtin printf "$@"
        }
        _octopus_copy_git_tracked_tree "$APPEND_FAILURE_SOURCE" "$APPEND_FAILURE_WORKSPACE"
    ); then
        append_failure_rc=0
    else
        append_failure_rc=$?
    fi
    append_failure_residue="$(find "$APPEND_FAILURE_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
    if [[ "$append_failure_rc" -eq 0 || -n "$append_failure_residue" ]]; then
        append_failure_failed=true
        append_failure_details="${append_failure_details}${append_failure_kind} rc=${append_failure_rc} residue=${append_failure_residue:-none}; "
    fi
    rm -rf "$APPEND_FAILURE_TMPDIR" "$APPEND_FAILURE_WORKSPACE"
done
if [[ "$append_failure_failed" == "false" ]]; then
    test_pass
else
    test_fail "expected append failures to propagate with no list residue: $append_failure_details"
fi

test_case "Git copy list directory is removed after archive failure"
COPY_LIST_FAILURE_TMPDIR="$TEST_TMP_DIR/copy-list-failure-tmp"
COPY_LIST_FAILURE_WORKSPACE="$TEST_TMP_DIR/copy-list-failure-workspace"
COPY_LIST_FAILURE_BIN="$TEST_TMP_DIR/copy-list-failure-bin"
mkdir -p "$COPY_LIST_FAILURE_TMPDIR" "$COPY_LIST_FAILURE_WORKSPACE" "$COPY_LIST_FAILURE_BIN"
cat > "$COPY_LIST_FAILURE_BIN/tar" <<'EOF'
#!/usr/bin/env bash
exit 97
EOF
chmod +x "$COPY_LIST_FAILURE_BIN/tar"
copy_list_failure_rc=0
if (
    export TMPDIR="$COPY_LIST_FAILURE_TMPDIR"
    export PATH="$COPY_LIST_FAILURE_BIN:$PATH"
    _octopus_copy_git_tracked_tree "$SOURCE_ROOT" "$COPY_LIST_FAILURE_WORKSPACE"
); then
    copy_list_failure_rc=0
else
    copy_list_failure_rc=$?
fi
copy_list_failure_residue="$(find "$COPY_LIST_FAILURE_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
if [[ "$copy_list_failure_rc" -ne 0 && -z "$copy_list_failure_residue" ]]; then
    test_pass
else
    test_fail "expected archive failure to remove its list directory: rc=$copy_list_failure_rc residue=$copy_list_failure_residue"
fi

test_case "Git copy list directory is removed after INT and TERM"
copy_list_signal_failed=false
copy_list_signal_failures=""
for copy_list_signal in INT TERM; do
    case "$copy_list_signal" in
        INT) copy_list_signal_expected_rc=130 ;;
        TERM) copy_list_signal_expected_rc=143 ;;
    esac
    COPY_LIST_SIGNAL_TMPDIR="$TEST_TMP_DIR/copy-list-signal-${copy_list_signal}"
    COPY_LIST_SIGNAL_WORKSPACE="$TEST_TMP_DIR/copy-list-signal-workspace-${copy_list_signal}"
    mkdir -p "$COPY_LIST_SIGNAL_TMPDIR" "$COPY_LIST_SIGNAL_WORKSPACE"
    copy_list_signal_rc=0
    if (
        export TMPDIR="$COPY_LIST_SIGNAL_TMPDIR"
        export SIGNAL_NAME="$copy_list_signal"
        /bin/bash -c '
            source "$1/scripts/lib/agent-sync.sh"
            copy_list_signal_pid_file="$4"
            _octopus_validate_copy_source_path() {
                local copy_list_subshell_pid
                /bin/sh -c '\''printf "%s\n" "$PPID" > "$1"'\'' _ "$copy_list_signal_pid_file" || return 1
                IFS= read -r copy_list_subshell_pid < "$copy_list_signal_pid_file" || return 1
                rm -f "$copy_list_signal_pid_file" || return 1
                case "$copy_list_subshell_pid" in
                    ""|*[!0-9]*) return 1 ;;
                esac
                [[ "$copy_list_subshell_pid" != "$$" ]] || return 1
                kill -s "$SIGNAL_NAME" "$copy_list_subshell_pid"
                return 1
            }
            _octopus_copy_git_tracked_tree "$2" "$3"
        ' _ "$PROJECT_ROOT" "$SOURCE_ROOT" "$COPY_LIST_SIGNAL_WORKSPACE" "$COPY_LIST_SIGNAL_WORKSPACE/subshell.pid"
    ) >/dev/null 2>&1; then
        copy_list_signal_rc=0
    else
        copy_list_signal_rc=$?
    fi
    copy_list_signal_residue="$(find "$COPY_LIST_SIGNAL_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
    if [[ "$copy_list_signal_rc" -ne "$copy_list_signal_expected_rc" || -n "$copy_list_signal_residue" ]]; then
        copy_list_signal_failed=true
        copy_list_signal_failures="${copy_list_signal_failures}${copy_list_signal} rc=${copy_list_signal_rc} expected=${copy_list_signal_expected_rc} residue=${copy_list_signal_residue:-none}; "
    fi
    rm -rf "$COPY_LIST_SIGNAL_TMPDIR" "$COPY_LIST_SIGNAL_WORKSPACE"
done
if [[ "$copy_list_signal_failed" == "false" ]]; then
    test_pass
else
    test_fail "expected INT and TERM status with no list residue: $copy_list_signal_failures"
fi

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
cleanup_tmpdir_set="${TMPDIR+x}"
cleanup_tmpdir_before="${TMPDIR:-}"
set -o posix
(
    export TMPDIR="$CLEANUP_TMPDIR"
    run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1
) || true
if [[ "${TMPDIR+x}" == "$cleanup_tmpdir_set" && "${TMPDIR:-}" == "$cleanup_tmpdir_before" ]]; then
    cleanup_tmpdir_isolated=true
else
    cleanup_tmpdir_isolated=false
fi
set +o posix
if [[ -n "$cleanup_tmpdir_set" ]]; then
    TMPDIR="$cleanup_tmpdir_before"
    export TMPDIR
else
    unset TMPDIR
fi
cd "$cleanup_old_pwd"
unset -f rm run_agent_sync
cleanup_residue="$(find "$CLEANUP_TMPDIR" -maxdepth 1 -type d -name 'octopus-consultative.*' -print)"
if [[ "$cleanup_tmpdir_isolated" == "true" && -f "$CLEANUP_SENTINEL" && -f "$CLEANUP_REPO_SENTINEL" ]] &&
   [[ ! -e "$UNSAFE_CLEANUP_MARKER" && -z "$cleanup_residue" ]]; then
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
