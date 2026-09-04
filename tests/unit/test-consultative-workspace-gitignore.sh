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

test_case "broken nested Git discovery fails closed before nested metadata or ignored bytes are copied"
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
    test_fail "expected broken nested discovery to fail before copy: rc=$broken_nested_rc leak=$broken_nested_leak residue=${broken_nested_residue:-none}"
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

test_case "Git trace and output sinks are cleared for advisory dispatch"
TRACE_EVENT_SINK="$TEST_TMP_DIR/git-trace2-event.json"
TRACE_TEXT_SINK="$TEST_TMP_DIR/git-trace.log"
TRACE_REDIRECT_SINK="$TEST_TMP_DIR/git-redirect.log"
TRACE_ENV_MARKER="$TEST_TMP_DIR/git-trace-env-leaked"
TRACE_GIT_MARKER="$TEST_TMP_DIR/git-command-ran"
run_agent_sync() {
    local name
    while IFS= read -r name; do
        case "$name" in
            GIT_TRACE*|GIT_REDIRECT_STDIN|GIT_REDIRECT_STDOUT|GIT_REDIRECT_STDERR)
                printf '%s\n' "$name" > "$TRACE_ENV_MARKER"
                ;;
        esac
    done < <(compgen -v)
    git --version > "$TRACE_GIT_MARKER"
    printf 'review only\n'
}
trace_old_pwd="$PWD"
cd "$SOURCE_ROOT"
(
    export GIT_TRACE="$TRACE_TEXT_SINK"
    export GIT_TRACE2_EVENT="$TRACE_EVENT_SINK"
    export GIT_REDIRECT_STDERR="$TRACE_REDIRECT_SINK"
    run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1
)
trace_dispatch_rc=$?
cd "$trace_old_pwd"
unset -f run_agent_sync
if [[ "$trace_dispatch_rc" -eq 0 && -s "$TRACE_GIT_MARKER" ]] &&
   [[ ! -e "$TRACE_ENV_MARKER" && ! -e "$TRACE_EVENT_SINK" && ! -e "$TRACE_TEXT_SINK" && ! -e "$TRACE_REDIRECT_SINK" ]]; then
    test_pass
else
    test_fail "expected Git command execution without inherited trace/output sinks: rc=$trace_dispatch_rc leaked=$(cat "$TRACE_ENV_MARKER" 2>/dev/null || printf none)"
fi

test_case "an exported readonly GIT_DIR cannot redirect advisory Git writes"
READONLY_GIT_DIR_MARKER="$TEST_TMP_DIR/readonly-git-dir-dispatched"
READONLY_GIT_DIR_REF="refs/heads/readonly-advisory-write"
ambient_git_dir="$(git -C "$SOURCE_ROOT" rev-parse --absolute-git-dir)"
git -C "$SOURCE_ROOT" update-ref -d "$READONLY_GIT_DIR_REF" >/dev/null 2>&1 || true
if (
    export READONLY_GIT_DIR_MARKER READONLY_GIT_DIR_REF
    /bin/bash -c '
        source "$1/scripts/lib/agent-sync.sh"
        log() { :; }
        run_agent_sync() {
            printf "dispatched\n" > "$READONLY_GIT_DIR_MARKER"
            git update-ref "$READONLY_GIT_DIR_REF" HEAD >/dev/null 2>&1 || true
            printf "review only\n"
        }
        export GIT_DIR="$3"
        readonly GIT_DIR
        cd "$2" || exit 98
        run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1
    ' _ "$PROJECT_ROOT" "$SOURCE_ROOT" "$ambient_git_dir"
); then
    readonly_git_dir_rc=0
else
    readonly_git_dir_rc=$?
fi
if [[ "$readonly_git_dir_rc" -ne 0 && ! -e "$READONLY_GIT_DIR_MARKER" ]] &&
   ! git -C "$SOURCE_ROOT" show-ref --verify --quiet "$READONLY_GIT_DIR_REF"; then
    test_pass
else
    test_fail "expected readonly repository selectors to fail closed before dispatch: rc=$readonly_git_dir_rc dispatched=$(test -e "$READONLY_GIT_DIR_MARKER" && printf yes || printf no)"
fi
git -C "$SOURCE_ROOT" update-ref -d "$READONLY_GIT_DIR_REF" >/dev/null 2>&1 || true

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

test_case "a non-Git copy rejects a symlink that escapes the copied root"
PLAIN_ESCAPE_ROOT="$TEST_TMP_DIR/plain-escape-source"
PLAIN_ESCAPE_OUTSIDE="$TEST_TMP_DIR/plain-escape-outside"
mkdir -p "$PLAIN_ESCAPE_ROOT" "$PLAIN_ESCAPE_OUTSIDE"
printf 'outside secret\n' > "$PLAIN_ESCAPE_OUTSIDE/secret.txt"
ln -s "../plain-escape-outside/secret.txt" "$PLAIN_ESCAPE_ROOT/external-link"
workspace=""
if workspace="$(_octopus_prepare_consultative_workspace "$PLAIN_ESCAPE_ROOT" 2>/dev/null)"; then
    plain_escape_rc=0
else
    plain_escape_rc=$?
fi
if [[ "$plain_escape_rc" -ne 0 && -z "$workspace" ]]; then
    test_pass
else
    test_fail "expected an external symlink in a non-Git source to fail closed: rc=$plain_escape_rc workspace=${workspace:-none}"
fi
[[ -z "$workspace" ]] || command rm -rf "$(dirname "$workspace")"

test_case "a non-Git copy preserves a relative symlink confined to the copied root"
PLAIN_LINK_ROOT="$TEST_TMP_DIR/plain-link-source"
mkdir -p "$PLAIN_LINK_ROOT/files" "$PLAIN_LINK_ROOT/links"
printf 'inside\n' > "$PLAIN_LINK_ROOT/files/inside.txt"
ln -s "../files/inside.txt" "$PLAIN_LINK_ROOT/links/internal-link"
workspace="$(_octopus_prepare_consultative_workspace "$PLAIN_LINK_ROOT")"
if [[ -L "$workspace/links/internal-link" ]] &&
   [[ "$(cat "$workspace/links/internal-link" 2>/dev/null)" == "inside" ]]; then
    test_pass
else
    test_fail "expected a confined non-Git symlink to remain usable in the copy"
fi
command rm -rf "$(dirname "$workspace")"

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

test_case "an empty parent copy list skips leaf copies and still copies nested work trees"
NESTED_ONLY_ROOT="$TEST_TMP_DIR/nested-only-source"
NESTED_ONLY_CP_BIN="$TEST_TMP_DIR/nested-only-cp-bin"
NESTED_ONLY_CP_MARKER="$TEST_TMP_DIR/nested-only-parent-cp-ran"
REAL_CP="$(command -v cp)"
mkdir -p "$NESTED_ONLY_ROOT" "$NESTED_ONLY_CP_BIN"
git -C "$NESTED_ONLY_ROOT" init -q
git -C "$NESTED_ONLY_ROOT" config user.email "test@example.com"
git -C "$NESTED_ONLY_ROOT" config user.name "test"
git clone -q "$NESTED_CHILD_ROOT" "$NESTED_ONLY_ROOT/nested-repo"
nested_only_oid="$(git -C "$NESTED_ONLY_ROOT/nested-repo" rev-parse HEAD)"
git -C "$NESTED_ONLY_ROOT" update-index --add --cacheinfo 160000 "$nested_only_oid" nested-repo
git -C "$NESTED_ONLY_ROOT" commit -q -m "nested-only parent"
printf 'nested-only working tree\n' > "$NESTED_ONLY_ROOT/nested-repo/nested.txt"
NESTED_ONLY_ROOT="$(cd "$NESTED_ONLY_ROOT" && pwd -P)"
cat > "$NESTED_ONLY_CP_BIN/cp" <<'EOF'
#!/usr/bin/env bash
original_args=("$@")
if [[ "$PWD" == "$NESTED_ONLY_ROOT" && "${1:-}" == "-pP" ]]; then
    printf 'parent leaf copy ran\n' > "$NESTED_ONLY_CP_MARKER"
    exit 97
fi
exec "$REAL_CP" "${original_args[@]}"
EOF
chmod +x "$NESTED_ONLY_CP_BIN/cp"
nested_only_rc=0
if workspace="$(
    export PATH="$NESTED_ONLY_CP_BIN:$PATH"
    export REAL_CP NESTED_ONLY_ROOT NESTED_ONLY_CP_MARKER
    _octopus_prepare_consultative_workspace "$NESTED_ONLY_ROOT"
)"; then
    nested_only_rc=0
else
    nested_only_rc=$?
fi
if [[ "$nested_only_rc" -eq 0 && ! -e "$NESTED_ONLY_CP_MARKER" ]] &&
   [[ "$(cat "$workspace/nested-repo/nested.txt" 2>/dev/null)" == "nested-only working tree" ]] &&
   [[ ! -e "$workspace/nested-repo/.git" ]]; then
    test_pass
else
    test_fail "expected nested copy without invoking the parent leaf copier: rc=$nested_only_rc"
fi
[[ -z "${workspace:-}" ]] || rm -rf "$(dirname "$workspace")"

test_case "nested repositories are excluded from the parent leaf copier"
NESTED_ROOT="$(cd "$NESTED_ROOT" && pwd -P)"
REAL_CP="$(command -v cp)"
CP_GUARD_BIN="$TEST_TMP_DIR/cp-guard-bin"
CP_GUARD_MARKER="$TEST_TMP_DIR/cp-saw-nested-root"
CP_GUARD_EXECUTED="$TEST_TMP_DIR/cp-guard-executed"
mkdir -p "$CP_GUARD_BIN"
cat > "$CP_GUARD_BIN/cp" <<'EOF'
#!/usr/bin/env bash
original_args=("$@")
if [[ "$PWD" == "$NESTED_ROOT" && "${1:-}" == "-pP" ]]; then
    printf 'guard executed\n' > "$CP_GUARD_EXECUTED"
    if [[ "${2:-}" == "./nested-repo" || "${2:-}" == ./nested-repo/* ]]; then
        printf 'nested repository reached parent copier\n' > "$CP_GUARD_MARKER"
        exit 97
    fi
fi
exec "$REAL_CP" "${original_args[@]}"
EOF
chmod +x "$CP_GUARD_BIN/cp"
workspace="$(
    export PATH="$CP_GUARD_BIN:$PATH" REAL_CP CP_GUARD_MARKER CP_GUARD_EXECUTED NESTED_ROOT
    _octopus_prepare_consultative_workspace "$NESTED_ROOT"
)"
if [[ -f "$CP_GUARD_EXECUTED" && ! -e "$CP_GUARD_MARKER" ]] &&
   [[ -f "$workspace/nested-repo/nested.txt" && ! -e "$workspace/nested-repo/vendor" ]]; then
    test_pass
else
    test_fail "expected the parent leaf copier to omit nested-repo before recursively copying it"
fi
rm -rf "$(dirname "$workspace")"

test_case "an ancestor swap after validation cannot redirect the copied leaf"
TOCTOU_ROOT="$TEST_TMP_DIR/toctou-source"
TOCTOU_OUTSIDE="$TEST_TMP_DIR/toctou-outside"
TOCTOU_BIN="$TEST_TMP_DIR/toctou-bin"
TOCTOU_CP_MARKER="$TEST_TMP_DIR/toctou-cp-ran"
REAL_CP="$(command -v cp)"
mkdir -p "$TOCTOU_ROOT/safe" "$TOCTOU_OUTSIDE" "$TOCTOU_BIN"
(
    cd "$TOCTOU_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'safe bytes\n' > safe/payload.txt
    git add safe/payload.txt
    git commit -q -m init
)
printf 'outside secret\n' > "$TOCTOU_OUTSIDE/payload.txt"
TOCTOU_ROOT="$(cd "$TOCTOU_ROOT" && pwd -P)"
cat > "$TOCTOU_BIN/cp" <<'EOF'
#!/usr/bin/env bash
original_args=("$@")
if [[ "$PWD" == "$TOCTOU_ROOT/safe" && "${1:-}" == "-pP" && ! -e "$TOCTOU_CP_MARKER" ]]; then
    mv "$TOCTOU_ROOT/safe" "$TOCTOU_ROOT/safe-before-race"
    ln -s "$TOCTOU_OUTSIDE" "$TOCTOU_ROOT/safe"
    printf 'leaf copy ran\n' > "$TOCTOU_CP_MARKER"
fi
exec "$REAL_CP" "${original_args[@]}"
EOF
chmod +x "$TOCTOU_BIN/cp"
workspace=""
if workspace="$(
    export PATH="$TOCTOU_BIN:$PATH"
    export REAL_CP TOCTOU_ROOT TOCTOU_OUTSIDE TOCTOU_CP_MARKER
    _octopus_prepare_consultative_workspace "$TOCTOU_ROOT"
)"; then
    toctou_rc=0
else
    toctou_rc=$?
fi
if [[ "$toctou_rc" -eq 0 && -f "$TOCTOU_CP_MARKER" ]] &&
   [[ "$(cat "$workspace/safe/payload.txt" 2>/dev/null)" == "safe bytes" ]]; then
    test_pass
else
    test_fail "expected the entered source directory to remain authoritative after an ancestor swap: rc=$toctou_rc cp_ran=$(test -e "$TOCTOU_CP_MARKER" && printf yes || printf no) copied=$(cat "$workspace/safe/payload.txt" 2>/dev/null || printf missing)"
fi
[[ -z "$workspace" ]] || command rm -rf "$(dirname "$workspace")"

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
   grep -Eq '^argc=2 first=-d second=.*/octopus-copy-lists\.[0-9]+\.[0-9]+\.XXXXXX$' "$COPY_LIST_MKTEMP_CALLS"; then
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

test_case "Git copy list directory is removed after leaf-copy failure"
COPY_LIST_FAILURE_TMPDIR="$TEST_TMP_DIR/copy-list-failure-tmp"
COPY_LIST_FAILURE_WORKSPACE="$TEST_TMP_DIR/copy-list-failure-workspace"
COPY_LIST_FAILURE_BIN="$TEST_TMP_DIR/copy-list-failure-bin"
mkdir -p "$COPY_LIST_FAILURE_TMPDIR" "$COPY_LIST_FAILURE_WORKSPACE" "$COPY_LIST_FAILURE_BIN"
cat > "$COPY_LIST_FAILURE_BIN/cp" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-pP" ]] || exec "$REAL_CP" "$@"
exit 97
EOF
chmod +x "$COPY_LIST_FAILURE_BIN/cp"
copy_list_failure_rc=0
if (
    export TMPDIR="$COPY_LIST_FAILURE_TMPDIR"
    export PATH="$COPY_LIST_FAILURE_BIN:$PATH"
    export REAL_CP
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
    test_fail "expected leaf-copy failure to remove its list directory: rc=$copy_list_failure_rc residue=$copy_list_failure_residue"
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

test_case "copy-list allocation owns real mktemp output before INT and TERM"
COPY_LIST_ALLOCATION_BIN="$TEST_TMP_DIR/copy-list-allocation-bin"
COPY_LIST_ALLOCATION_MARKER="$TEST_TMP_DIR/copy-list-allocation-created"
COPY_LIST_ALLOCATION_INT_MARKER="$TEST_TMP_DIR/copy-list-allocation-caller-int"
COPY_LIST_ALLOCATION_TERM_MARKER="$TEST_TMP_DIR/copy-list-allocation-caller-term"
REAL_MKTEMP="$(command -v mktemp)"
mkdir -p "$COPY_LIST_ALLOCATION_BIN"
cat > "$COPY_LIST_ALLOCATION_BIN/mktemp" <<'EOF'
#!/usr/bin/env bash
allocated="$($REAL_MKTEMP "$@")" || exit 91
printf '%s\n' "$allocated" > "$COPY_LIST_ALLOCATION_MARKER" || exit 92
kill -s "$SIGNAL_NAME" "$PPID" || exit 93
printf '%s\n' "$allocated"
EOF
chmod +x "$COPY_LIST_ALLOCATION_BIN/mktemp"
copy_list_allocation_failed=false
copy_list_allocation_failures=""
for copy_list_allocation_signal in INT TERM; do
    case "$copy_list_allocation_signal" in
        INT) copy_list_allocation_expected_rc=130 ;;
        TERM) copy_list_allocation_expected_rc=143 ;;
    esac
    COPY_LIST_ALLOCATION_TMPDIR="$TEST_TMP_DIR/copy-list-allocation-${copy_list_allocation_signal}"
    COPY_LIST_ALLOCATION_WORKSPACE="$TEST_TMP_DIR/copy-list-allocation-workspace-${copy_list_allocation_signal}"
    rm -f "$COPY_LIST_ALLOCATION_MARKER" "$COPY_LIST_ALLOCATION_INT_MARKER" "$COPY_LIST_ALLOCATION_TERM_MARKER"
    mkdir -p "$COPY_LIST_ALLOCATION_TMPDIR" "$COPY_LIST_ALLOCATION_WORKSPACE"
    if (
        export TMPDIR="$COPY_LIST_ALLOCATION_TMPDIR"
        export PATH="$COPY_LIST_ALLOCATION_BIN:$PATH"
        export REAL_MKTEMP COPY_LIST_ALLOCATION_MARKER
        export SIGNAL_NAME="$copy_list_allocation_signal"
        export COPY_LIST_ALLOCATION_INT_MARKER COPY_LIST_ALLOCATION_TERM_MARKER
        export OCTOPUS_ALLOCATION_CALLER_ENV="preserved"
        trap 'printf "caller INT trap ran\n" > "$COPY_LIST_ALLOCATION_INT_MARKER"' INT
        trap 'printf "caller TERM trap ran\n" > "$COPY_LIST_ALLOCATION_TERM_MARKER"' TERM
        caller_int_before="$(trap -p INT)"
        caller_term_before="$(trap -p TERM)"
        caller_pwd_before="$(pwd -P)"
        set +e
        _octopus_copy_git_tracked_tree "$SOURCE_ROOT" "$COPY_LIST_ALLOCATION_WORKSPACE"
        allocation_rc=$?
        set -e
        allocation_residue="$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print)"
        [[ "$allocation_rc" -eq "$copy_list_allocation_expected_rc" ]] &&
            [[ -f "$COPY_LIST_ALLOCATION_MARKER" ]] &&
            [[ -z "$allocation_residue" ]] &&
            [[ ! -e "$COPY_LIST_ALLOCATION_INT_MARKER" && ! -e "$COPY_LIST_ALLOCATION_TERM_MARKER" ]] &&
            [[ "$(trap -p INT)" == "$caller_int_before" ]] &&
            [[ "$(trap -p TERM)" == "$caller_term_before" ]] &&
            [[ "$(pwd -P)" == "$caller_pwd_before" ]] &&
            [[ "$OCTOPUS_ALLOCATION_CALLER_ENV" == "preserved" ]]
    ); then
        copy_list_allocation_case_rc=0
    else
        copy_list_allocation_case_rc=$?
    fi
    copy_list_allocation_residue="$(find "$COPY_LIST_ALLOCATION_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
    if [[ "$copy_list_allocation_case_rc" -ne 0 || -n "$copy_list_allocation_residue" ]]; then
        copy_list_allocation_failed=true
        copy_list_allocation_failures="${copy_list_allocation_failures}${copy_list_allocation_signal} case_rc=${copy_list_allocation_case_rc} residue=${copy_list_allocation_residue:-none}; "
    fi
    command rm -rf "$COPY_LIST_ALLOCATION_TMPDIR" "$COPY_LIST_ALLOCATION_WORKSPACE"
done
command rm -rf "$COPY_LIST_ALLOCATION_BIN" "$COPY_LIST_ALLOCATION_MARKER" "$COPY_LIST_ALLOCATION_INT_MARKER" "$COPY_LIST_ALLOCATION_TERM_MARKER"
if [[ "$copy_list_allocation_failed" == "false" ]]; then
    test_pass
else
    test_fail "expected allocation-time signals to preserve status and caller state without list residue: $copy_list_allocation_failures"
fi

test_case "copy-list cleanup failure preserves TERM status and fails normal success"
COPY_LIST_RM_FAILURE_TMPDIR="$TEST_TMP_DIR/copy-list-rm-failure-tmp"
COPY_LIST_RM_FAILURE_WORKSPACE="$TEST_TMP_DIR/copy-list-rm-failure-workspace"
COPY_LIST_RM_FAILURE_BIN="$TEST_TMP_DIR/copy-list-rm-failure-bin"
COPY_LIST_RM_FAILURE_PID_FILE="$TEST_TMP_DIR/copy-list-rm-failure.pid"
REAL_RM="$(command -v rm)"
mkdir -p "$COPY_LIST_RM_FAILURE_TMPDIR" "$COPY_LIST_RM_FAILURE_WORKSPACE" "$COPY_LIST_RM_FAILURE_BIN"
cat > "$COPY_LIST_RM_FAILURE_BIN/rm" <<'EOF'
#!/usr/bin/env bash
case "${2:-}" in
    */octopus-copy-lists.*.*.??????) exit 95 ;;
esac
exec "$REAL_RM" "$@"
EOF
chmod +x "$COPY_LIST_RM_FAILURE_BIN/rm"
if (
    export TMPDIR="$COPY_LIST_RM_FAILURE_TMPDIR"
    export PATH="$COPY_LIST_RM_FAILURE_BIN:$PATH"
    export REAL_RM COPY_LIST_RM_FAILURE_PID_FILE
    /bin/bash -c '
        source "$1/scripts/lib/agent-sync.sh"
        _octopus_validate_copy_source_path() {
            /bin/sh -c '\''printf "%s\n" "$PPID" > "$1"'\'' _ "$COPY_LIST_RM_FAILURE_PID_FILE" || return 1
            IFS= read -r copy_pid < "$COPY_LIST_RM_FAILURE_PID_FILE" || return 1
            kill -TERM "$copy_pid"
            return 1
        }
        _octopus_copy_git_tracked_tree "$2" "$3"
    ' _ "$PROJECT_ROOT" "$SOURCE_ROOT" "$COPY_LIST_RM_FAILURE_WORKSPACE"
) >/dev/null 2>&1; then
    copy_list_rm_signal_rc=0
else
    copy_list_rm_signal_rc=$?
fi
copy_list_rm_signal_residue="$(find "$COPY_LIST_RM_FAILURE_TMPDIR" -mindepth 1 -maxdepth 1 -type d -name 'octopus-copy-lists.*' -print)"
command rm -rf "$COPY_LIST_RM_FAILURE_TMPDIR" "$COPY_LIST_RM_FAILURE_WORKSPACE" "$COPY_LIST_RM_FAILURE_PID_FILE"

mkdir -p "$COPY_LIST_RM_FAILURE_TMPDIR" "$COPY_LIST_RM_FAILURE_WORKSPACE"
if (
    export TMPDIR="$COPY_LIST_RM_FAILURE_TMPDIR"
    export PATH="$COPY_LIST_RM_FAILURE_BIN:$PATH"
    export REAL_RM
    _octopus_copy_git_tracked_tree "$SOURCE_ROOT" "$COPY_LIST_RM_FAILURE_WORKSPACE"
) >/dev/null 2>&1; then
    copy_list_rm_success_rc=0
else
    copy_list_rm_success_rc=$?
fi
copy_list_rm_success_residue="$(find "$COPY_LIST_RM_FAILURE_TMPDIR" -mindepth 1 -maxdepth 1 -type d -name 'octopus-copy-lists.*' -print)"
command rm -rf "$COPY_LIST_RM_FAILURE_TMPDIR" "$COPY_LIST_RM_FAILURE_WORKSPACE" "$COPY_LIST_RM_FAILURE_BIN"
if [[ "$copy_list_rm_signal_rc" -eq 143 && -n "$copy_list_rm_signal_residue" ]] &&
   [[ "$copy_list_rm_success_rc" -ne 0 && -n "$copy_list_rm_success_residue" ]]; then
    test_pass
else
    test_fail "expected TERM=143 and normal-success cleanup failure: signal_rc=$copy_list_rm_signal_rc success_rc=$copy_list_rm_success_rc"
fi

test_case "preparation-phase INT and TERM preserve status, cleanup, and caller state"
prepare_signal_failed=false
prepare_signal_failures=""
for prepare_signal in INT TERM; do
    case "$prepare_signal" in
        INT) prepare_signal_expected_rc=130 ;;
        TERM) prepare_signal_expected_rc=143 ;;
    esac
    PREPARE_SIGNAL_TMPDIR="$TEST_TMP_DIR/prepare-signal-${prepare_signal}"
    PREPARE_SIGNAL_PID_FILE="$TEST_TMP_DIR/prepare-signal-${prepare_signal}.pid"
    PREPARE_SIGNAL_DISPATCH_MARKER="$TEST_TMP_DIR/prepare-signal-${prepare_signal}.dispatched"
    PREPARE_SIGNAL_INT_MARKER="$TEST_TMP_DIR/prepare-signal-${prepare_signal}.caller-int"
    PREPARE_SIGNAL_TERM_MARKER="$TEST_TMP_DIR/prepare-signal-${prepare_signal}.caller-term"
    mkdir -p "$PREPARE_SIGNAL_TMPDIR"
    if (
        export TMPDIR="$PREPARE_SIGNAL_TMPDIR"
        export SIGNAL_NAME="$prepare_signal"
        export PREPARE_SIGNAL_PID_FILE PREPARE_SIGNAL_DISPATCH_MARKER
        export PREPARE_SIGNAL_INT_MARKER PREPARE_SIGNAL_TERM_MARKER
        export OCTOPUS_SECURITY_V870="caller-security"
        export OCTOPUS_AGY_SANDBOX="caller-agy"
        export OCTOPUS_CODEX_SANDBOX="caller-codex"
        export CLAUDE_OCTOPUS_AUTONOMY="caller-autonomy"
        /bin/bash -c '
            source "$1/scripts/lib/agent-sync.sh"
            log() { :; }
            run_agent_sync() { printf "ran\n" > "$PREPARE_SIGNAL_DISPATCH_MARKER"; }
            _octopus_copy_git_tracked_tree() {
                /bin/sh -c '\''printf "%s\n" "$PPID" > "$1"'\'' _ "$PREPARE_SIGNAL_PID_FILE" || return 1
                IFS= read -r consultative_pid < "$PREPARE_SIGNAL_PID_FILE" || return 1
                kill -s "$SIGNAL_NAME" "$consultative_pid"
                return 99
            }
            trap '\''printf "caller INT trap ran\n" > "$PREPARE_SIGNAL_INT_MARKER"'\'' INT
            trap '\''printf "caller TERM trap ran\n" > "$PREPARE_SIGNAL_TERM_MARKER"'\'' TERM
            caller_int_before="$(trap -p INT)"
            caller_term_before="$(trap -p TERM)"
            cd "$2" || exit 98
            caller_pwd_before="$(pwd -P)"
            set +e
            run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1
            prepare_rc=$?
            set -e
            prepare_residue="$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -type d -name "octopus-consultative.*" -print)"
            [[ "$prepare_rc" -eq "$3" ]] &&
                [[ -z "$prepare_residue" ]] &&
                [[ ! -e "$PREPARE_SIGNAL_DISPATCH_MARKER" ]] &&
                [[ ! -e "$PREPARE_SIGNAL_INT_MARKER" && ! -e "$PREPARE_SIGNAL_TERM_MARKER" ]] &&
                [[ "$(trap -p INT)" == "$caller_int_before" ]] &&
                [[ "$(trap -p TERM)" == "$caller_term_before" ]] &&
                [[ "$(pwd -P)" == "$caller_pwd_before" ]] &&
                [[ "$OCTOPUS_SECURITY_V870" == "caller-security" ]] &&
                [[ "$OCTOPUS_AGY_SANDBOX" == "caller-agy" ]] &&
                [[ "$OCTOPUS_CODEX_SANDBOX" == "caller-codex" ]] &&
                [[ "$CLAUDE_OCTOPUS_AUTONOMY" == "caller-autonomy" ]]
        ' _ "$PROJECT_ROOT" "$SOURCE_ROOT" "$prepare_signal_expected_rc"
    ); then
        prepare_signal_case_rc=0
    else
        prepare_signal_case_rc=$?
    fi
    prepare_signal_residue="$(find "$PREPARE_SIGNAL_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
    if [[ "$prepare_signal_case_rc" -ne 0 || -n "$prepare_signal_residue" ]]; then
        prepare_signal_failed=true
        prepare_signal_failures="${prepare_signal_failures}${prepare_signal} case_rc=${prepare_signal_case_rc} residue=${prepare_signal_residue:-none}; "
    fi
    command rm -rf "$PREPARE_SIGNAL_TMPDIR" "$PREPARE_SIGNAL_PID_FILE" "$PREPARE_SIGNAL_DISPATCH_MARKER" "$PREPARE_SIGNAL_INT_MARKER" "$PREPARE_SIGNAL_TERM_MARKER"
done
if [[ "$prepare_signal_failed" == "false" ]]; then
    test_pass
else
    test_fail "expected preparation signals to preserve status and caller state without residue: $prepare_signal_failures"
fi

test_case "consultative root allocation owns real mktemp output before INT and TERM"
ROOT_ALLOCATION_BIN="$TEST_TMP_DIR/root-allocation-bin"
ROOT_ALLOCATION_MARKER="$TEST_TMP_DIR/root-allocation-created"
ROOT_ALLOCATION_DISPATCH_MARKER="$TEST_TMP_DIR/root-allocation-dispatched"
ROOT_ALLOCATION_INT_MARKER="$TEST_TMP_DIR/root-allocation-caller-int"
ROOT_ALLOCATION_TERM_MARKER="$TEST_TMP_DIR/root-allocation-caller-term"
REAL_MKTEMP="$(command -v mktemp)"
mkdir -p "$ROOT_ALLOCATION_BIN"
cat > "$ROOT_ALLOCATION_BIN/mktemp" <<'EOF'
#!/usr/bin/env bash
allocated="$($REAL_MKTEMP "$@")" || exit 91
printf '%s\n' "$allocated" > "$ROOT_ALLOCATION_MARKER" || exit 92
kill -s "$SIGNAL_NAME" "$PPID" || exit 93
printf '%s\n' "$allocated"
EOF
chmod +x "$ROOT_ALLOCATION_BIN/mktemp"
root_allocation_failed=false
root_allocation_failures=""
for root_allocation_signal in INT TERM; do
    case "$root_allocation_signal" in
        INT) root_allocation_expected_rc=130 ;;
        TERM) root_allocation_expected_rc=143 ;;
    esac
    ROOT_ALLOCATION_TMPDIR="$TEST_TMP_DIR/root-allocation-${root_allocation_signal}"
    rm -f "$ROOT_ALLOCATION_MARKER" "$ROOT_ALLOCATION_DISPATCH_MARKER" "$ROOT_ALLOCATION_INT_MARKER" "$ROOT_ALLOCATION_TERM_MARKER"
    mkdir -p "$ROOT_ALLOCATION_TMPDIR"
    if (
        export TMPDIR="$ROOT_ALLOCATION_TMPDIR"
        export PATH="$ROOT_ALLOCATION_BIN:$PATH"
        export REAL_MKTEMP ROOT_ALLOCATION_MARKER ROOT_ALLOCATION_DISPATCH_MARKER
        export SIGNAL_NAME="$root_allocation_signal"
        export ROOT_ALLOCATION_INT_MARKER ROOT_ALLOCATION_TERM_MARKER
        export OCTOPUS_SECURITY_V870="caller-security"
        export OCTOPUS_AGY_SANDBOX="caller-agy"
        export OCTOPUS_CODEX_SANDBOX="caller-codex"
        export CLAUDE_OCTOPUS_AUTONOMY="caller-autonomy"
        log() { :; }
        run_agent_sync() { printf "ran\n" > "$ROOT_ALLOCATION_DISPATCH_MARKER"; }
        trap 'printf "caller INT trap ran\n" > "$ROOT_ALLOCATION_INT_MARKER"' INT
        trap 'printf "caller TERM trap ran\n" > "$ROOT_ALLOCATION_TERM_MARKER"' TERM
        caller_int_before="$(trap -p INT)"
        caller_term_before="$(trap -p TERM)"
        cd "$SOURCE_ROOT" || exit 98
        source_pwd="$(pwd -P)"
        set +e
        run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1
        allocation_rc=$?
        set -e
        allocation_residue="$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print)"
        [[ "$allocation_rc" -eq "$root_allocation_expected_rc" ]] &&
            [[ -f "$ROOT_ALLOCATION_MARKER" ]] &&
            [[ -z "$allocation_residue" ]] &&
            [[ ! -e "$ROOT_ALLOCATION_DISPATCH_MARKER" ]] &&
            [[ ! -e "$ROOT_ALLOCATION_INT_MARKER" && ! -e "$ROOT_ALLOCATION_TERM_MARKER" ]] &&
            [[ "$(trap -p INT)" == "$caller_int_before" ]] &&
            [[ "$(trap -p TERM)" == "$caller_term_before" ]] &&
            [[ "$(pwd -P)" == "$source_pwd" ]] &&
            [[ "$OCTOPUS_SECURITY_V870" == "caller-security" ]] &&
            [[ "$OCTOPUS_AGY_SANDBOX" == "caller-agy" ]] &&
            [[ "$OCTOPUS_CODEX_SANDBOX" == "caller-codex" ]] &&
            [[ "$CLAUDE_OCTOPUS_AUTONOMY" == "caller-autonomy" ]]
    ); then
        root_allocation_case_rc=0
    else
        root_allocation_case_rc=$?
    fi
    root_allocation_residue="$(find "$ROOT_ALLOCATION_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
    if [[ "$root_allocation_case_rc" -ne 0 || -n "$root_allocation_residue" ]]; then
        root_allocation_failed=true
        root_allocation_failures="${root_allocation_failures}${root_allocation_signal} case_rc=${root_allocation_case_rc} residue=${root_allocation_residue:-none}; "
    fi
    command rm -rf "$ROOT_ALLOCATION_TMPDIR"
done
command rm -rf "$ROOT_ALLOCATION_BIN" "$ROOT_ALLOCATION_MARKER" "$ROOT_ALLOCATION_DISPATCH_MARKER" "$ROOT_ALLOCATION_INT_MARKER" "$ROOT_ALLOCATION_TERM_MARKER"
if [[ "$root_allocation_failed" == "false" ]]; then
    test_pass
else
    test_fail "expected allocation-time signals to preserve status and caller state without root residue or dispatch: $root_allocation_failures"
fi

test_case "failed mktemp calls clean created allocations and prevent dispatch"
MKTEMP_FAILURE_BIN="$TEST_TMP_DIR/mktemp-failure-bin"
MKTEMP_FAILURE_MARKER="$TEST_TMP_DIR/mktemp-failure-created"
MKTEMP_FAILURE_DISPATCH_MARKER="$TEST_TMP_DIR/mktemp-failure-dispatched"
MKTEMP_FAILURE_COPY_TMPDIR="$TEST_TMP_DIR/mktemp-failure-copy-tmp"
MKTEMP_FAILURE_ROOT_TMPDIR="$TEST_TMP_DIR/mktemp-failure-root-tmp"
MKTEMP_FAILURE_WORKSPACE="$TEST_TMP_DIR/mktemp-failure-workspace"
REAL_MKTEMP="$(command -v mktemp)"
mkdir -p "$MKTEMP_FAILURE_BIN" "$MKTEMP_FAILURE_COPY_TMPDIR" "$MKTEMP_FAILURE_ROOT_TMPDIR" "$MKTEMP_FAILURE_WORKSPACE"
cat > "$MKTEMP_FAILURE_BIN/mktemp" <<'EOF'
#!/usr/bin/env bash
allocated="$($REAL_MKTEMP "$@")" || exit 91
printf '%s\n' "$allocated" >> "$MKTEMP_FAILURE_MARKER" || exit 92
exit 97
EOF
chmod +x "$MKTEMP_FAILURE_BIN/mktemp"
if (
    export TMPDIR="$MKTEMP_FAILURE_COPY_TMPDIR"
    export PATH="$MKTEMP_FAILURE_BIN:$PATH"
    export REAL_MKTEMP MKTEMP_FAILURE_MARKER
    _octopus_copy_git_tracked_tree "$SOURCE_ROOT" "$MKTEMP_FAILURE_WORKSPACE"
); then
    mktemp_failure_copy_rc=0
else
    mktemp_failure_copy_rc=$?
fi
mktemp_failure_copy_residue="$(find "$MKTEMP_FAILURE_COPY_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
if (
    export TMPDIR="$MKTEMP_FAILURE_ROOT_TMPDIR"
    export PATH="$MKTEMP_FAILURE_BIN:$PATH"
    export REAL_MKTEMP MKTEMP_FAILURE_MARKER MKTEMP_FAILURE_DISPATCH_MARKER
    log() { :; }
    run_agent_sync() { printf 'ran\n' > "$MKTEMP_FAILURE_DISPATCH_MARKER"; }
    cd "$SOURCE_ROOT" || exit 98
    run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1
); then
    mktemp_failure_root_rc=0
else
    mktemp_failure_root_rc=$?
fi
mktemp_failure_root_residue="$(find "$MKTEMP_FAILURE_ROOT_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
mktemp_failure_calls="$(wc -l < "$MKTEMP_FAILURE_MARKER" | tr -d ' ')"
if [[ "$mktemp_failure_copy_rc" -ne 0 && "$mktemp_failure_root_rc" -ne 0 ]] &&
   [[ "$mktemp_failure_calls" == "2" ]] &&
   [[ -z "$mktemp_failure_copy_residue" && -z "$mktemp_failure_root_residue" ]] &&
   [[ ! -e "$MKTEMP_FAILURE_DISPATCH_MARKER" ]]; then
    test_pass
else
    test_fail "expected both post-create mktemp failures to fail closed without residue or dispatch: copy_rc=$mktemp_failure_copy_rc root_rc=$mktemp_failure_root_rc calls=$mktemp_failure_calls"
fi
command rm -rf "$MKTEMP_FAILURE_BIN" "$MKTEMP_FAILURE_MARKER" "$MKTEMP_FAILURE_COPY_TMPDIR" "$MKTEMP_FAILURE_ROOT_TMPDIR" "$MKTEMP_FAILURE_WORKSPACE" "$MKTEMP_FAILURE_DISPATCH_MARKER"

test_case "real Git consultative dispatch removes its full workspace after success and failure"
dispatch_cleanup_failed=false
dispatch_cleanup_failures=""
for dispatch_mode in success failure; do
    DISPATCH_CLEANUP_TMPDIR="$TEST_TMP_DIR/dispatch-cleanup-${dispatch_mode}"
    DISPATCH_CLEANUP_STARTED="$TEST_TMP_DIR/dispatch-cleanup-${dispatch_mode}-started"
    DISPATCH_CLEANUP_INT_MARKER="$TEST_TMP_DIR/dispatch-cleanup-${dispatch_mode}-int"
    DISPATCH_CLEANUP_TERM_MARKER="$TEST_TMP_DIR/dispatch-cleanup-${dispatch_mode}-term"
    DISPATCH_CLEANUP_EXIT_MARKER="$TEST_TMP_DIR/dispatch-cleanup-${dispatch_mode}-exit"
    mkdir -p "$DISPATCH_CLEANUP_TMPDIR"
    DISPATCH_CLEANUP_TMPDIR="$(cd "$DISPATCH_CLEANUP_TMPDIR" && pwd -P)"
    case "$dispatch_mode" in
        success) dispatch_expected_rc=0 ;;
        failure) dispatch_expected_rc=7 ;;
    esac
    if (
        export TMPDIR="$DISPATCH_CLEANUP_TMPDIR"
        export DISPATCH_MODE="$dispatch_mode"
        export DISPATCH_CLEANUP_STARTED
        export DISPATCH_CLEANUP_INT_MARKER DISPATCH_CLEANUP_TERM_MARKER DISPATCH_CLEANUP_EXIT_MARKER
        export OCTOPUS_SECURITY_V870="caller-security"
        export OCTOPUS_AGY_SANDBOX="caller-agy"
        export OCTOPUS_CODEX_SANDBOX="caller-codex"
        export CLAUDE_OCTOPUS_AUTONOMY="caller-autonomy"
        /bin/bash -c '
            source "$1/scripts/lib/agent-sync.sh"
            log() { :; }
            run_agent_sync() {
                case "$PWD" in
                    "$TMPDIR"/octopus-consultative.*.*.??????/workspace) ;;
                    *) return 96 ;;
                esac
                [[ -d "$PWD" ]] || return 96
                printf "%s\n" "$PWD" > "$DISPATCH_CLEANUP_STARTED"
                printf "provider ran\n"
                [[ "$DISPATCH_MODE" == "success" ]] && return 0
                return 7
            }
            trap '\''printf "caller INT trap ran\n" > "$DISPATCH_CLEANUP_INT_MARKER"'\'' INT
            trap '\''printf "caller TERM trap ran\n" > "$DISPATCH_CLEANUP_TERM_MARKER"'\'' TERM
            trap '\''printf "caller EXIT trap ran\n" > "$DISPATCH_CLEANUP_EXIT_MARKER"'\'' EXIT
            caller_int_trap_before="$(trap -p INT)"
            caller_term_trap_before="$(trap -p TERM)"
            caller_exit_trap_before="$(trap -p EXIT)"
            cd "$2" || exit 98
            caller_pwd_before="$(pwd -P)"
            set +e
            run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1
            dispatch_rc=$?
            set -e
            caller_int_trap_after="$(trap -p INT)"
            caller_term_trap_after="$(trap -p TERM)"
            caller_exit_trap_after="$(trap -p EXIT)"
            dispatch_residue="$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print)"
            IFS= read -r dispatch_workspace < "$DISPATCH_CLEANUP_STARTED" || exit 1
            dispatch_temp_root="${dispatch_workspace%/workspace}"
            [[ "$dispatch_workspace" == "$TMPDIR"/octopus-consultative.*.*.??????/workspace ]] &&
                [[ ! -e "$dispatch_temp_root" ]] &&
                [[ "$dispatch_rc" -eq "$3" ]] &&
                [[ -z "$dispatch_residue" ]] &&
                [[ ! -e "$DISPATCH_CLEANUP_INT_MARKER" && ! -e "$DISPATCH_CLEANUP_TERM_MARKER" && ! -e "$DISPATCH_CLEANUP_EXIT_MARKER" ]] &&
                [[ "$caller_int_trap_after" == "$caller_int_trap_before" ]] &&
                [[ "$caller_term_trap_after" == "$caller_term_trap_before" ]] &&
                [[ "$caller_exit_trap_after" == "$caller_exit_trap_before" ]] &&
                [[ "$(pwd -P)" == "$caller_pwd_before" ]] &&
                [[ "$OCTOPUS_SECURITY_V870" == "caller-security" ]] &&
                [[ "$OCTOPUS_AGY_SANDBOX" == "caller-agy" ]] &&
                [[ "$OCTOPUS_CODEX_SANDBOX" == "caller-codex" ]] &&
                [[ "$CLAUDE_OCTOPUS_AUTONOMY" == "caller-autonomy" ]]
        ' _ "$PROJECT_ROOT" "$SOURCE_ROOT" "$dispatch_expected_rc"
    ); then
        dispatch_cleanup_rc=0
    else
        dispatch_cleanup_rc=$?
    fi
    if [[ "$dispatch_cleanup_rc" -ne 0 ]]; then
        dispatch_cleanup_failed=true
        dispatch_cleanup_failures="${dispatch_cleanup_failures}${dispatch_mode} rc=${dispatch_cleanup_rc}; "
    fi
    rm -rf "$DISPATCH_CLEANUP_TMPDIR" "$DISPATCH_CLEANUP_STARTED" "$DISPATCH_CLEANUP_INT_MARKER" "$DISPATCH_CLEANUP_TERM_MARKER" "$DISPATCH_CLEANUP_EXIT_MARKER"
done
if [[ "$dispatch_cleanup_failed" == "false" ]]; then
    test_pass
else
    test_fail "expected real dispatch cleanup and caller-state preservation: $dispatch_cleanup_failures"
fi

test_case "real Git consultative dispatch removes its full workspace after INT and TERM"
dispatch_signal_failed=false
dispatch_signal_failures=""
for dispatch_signal in INT TERM; do
    case "$dispatch_signal" in
        INT) dispatch_signal_expected_rc=130 ;;
        TERM) dispatch_signal_expected_rc=143 ;;
    esac
    DISPATCH_SIGNAL_TMPDIR="$TEST_TMP_DIR/dispatch-signal-${dispatch_signal}"
    DISPATCH_SIGNAL_STARTED="$TEST_TMP_DIR/dispatch-signal-${dispatch_signal}-started"
    DISPATCH_SIGNAL_PID_FILE="$TEST_TMP_DIR/dispatch-signal-${dispatch_signal}-pid"
    DISPATCH_SIGNAL_INT_MARKER="$TEST_TMP_DIR/dispatch-signal-${dispatch_signal}-caller-int"
    DISPATCH_SIGNAL_TERM_MARKER="$TEST_TMP_DIR/dispatch-signal-${dispatch_signal}-caller-term"
    DISPATCH_SIGNAL_EXIT_MARKER="$TEST_TMP_DIR/dispatch-signal-${dispatch_signal}-caller-exit"
    mkdir -p "$DISPATCH_SIGNAL_TMPDIR"
    DISPATCH_SIGNAL_TMPDIR="$(cd "$DISPATCH_SIGNAL_TMPDIR" && pwd -P)"
    if (
        export TMPDIR="$DISPATCH_SIGNAL_TMPDIR"
        export SIGNAL_NAME="$dispatch_signal"
        export DISPATCH_SIGNAL_STARTED DISPATCH_SIGNAL_PID_FILE
        export DISPATCH_SIGNAL_INT_MARKER DISPATCH_SIGNAL_TERM_MARKER DISPATCH_SIGNAL_EXIT_MARKER
        export OCTOPUS_SECURITY_V870="caller-security"
        export OCTOPUS_AGY_SANDBOX="caller-agy"
        export OCTOPUS_CODEX_SANDBOX="caller-codex"
        export CLAUDE_OCTOPUS_AUTONOMY="caller-autonomy"
        /bin/bash -c '
            source "$1/scripts/lib/agent-sync.sh"
            log() { :; }
            run_agent_sync() {
                local command_subshell_pid consultative_pid
                case "$PWD" in
                    "$TMPDIR"/octopus-consultative.*.*.??????/workspace) ;;
                    *) return 96 ;;
                esac
                [[ -d "$PWD" ]] || return 96
                printf "%s\n" "$PWD" > "$DISPATCH_SIGNAL_STARTED"
                /bin/sh -c '\''printf "%s\n" "$PPID" > "$1"'\'' _ "$DISPATCH_SIGNAL_PID_FILE" || return 1
                IFS= read -r command_subshell_pid < "$DISPATCH_SIGNAL_PID_FILE" || return 1
                consultative_pid="$(/bin/ps -o ppid= -p "$command_subshell_pid" | tr -d "[:space:]")" || return 1
                case "$consultative_pid" in
                    ""|*[!0-9]*) return 1 ;;
                esac
                kill -s "$SIGNAL_NAME" "$consultative_pid" || return 1
                return 0
            }
            trap '\''printf "caller INT trap ran\n" > "$DISPATCH_SIGNAL_INT_MARKER"'\'' INT
            trap '\''printf "caller TERM trap ran\n" > "$DISPATCH_SIGNAL_TERM_MARKER"'\'' TERM
            trap '\''printf "caller EXIT trap ran\n" > "$DISPATCH_SIGNAL_EXIT_MARKER"'\'' EXIT
            caller_int_trap_before="$(trap -p INT)"
            caller_term_trap_before="$(trap -p TERM)"
            caller_exit_trap_before="$(trap -p EXIT)"
            cd "$2" || exit 98
            caller_pwd_before="$(pwd -P)"
            set +e
            run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1
            dispatch_rc=$?
            set -e
            caller_int_trap_after="$(trap -p INT)"
            caller_term_trap_after="$(trap -p TERM)"
            caller_exit_trap_after="$(trap -p EXIT)"
            dispatch_residue="$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -print)"
            IFS= read -r dispatch_workspace < "$DISPATCH_SIGNAL_STARTED" || exit 1
            dispatch_temp_root="${dispatch_workspace%/workspace}"
            [[ "$dispatch_workspace" == "$TMPDIR"/octopus-consultative.*.*.??????/workspace ]] &&
                [[ ! -e "$dispatch_temp_root" ]] &&
                [[ "$dispatch_rc" -eq "$3" ]] &&
                [[ -z "$dispatch_residue" ]] &&
                [[ ! -e "$DISPATCH_SIGNAL_INT_MARKER" && ! -e "$DISPATCH_SIGNAL_TERM_MARKER" && ! -e "$DISPATCH_SIGNAL_EXIT_MARKER" ]] &&
                [[ "$caller_int_trap_after" == "$caller_int_trap_before" ]] &&
                [[ "$caller_term_trap_after" == "$caller_term_trap_before" ]] &&
                [[ "$caller_exit_trap_after" == "$caller_exit_trap_before" ]] &&
                [[ "$(pwd -P)" == "$caller_pwd_before" ]] &&
                [[ "$OCTOPUS_SECURITY_V870" == "caller-security" ]] &&
                [[ "$OCTOPUS_AGY_SANDBOX" == "caller-agy" ]] &&
                [[ "$OCTOPUS_CODEX_SANDBOX" == "caller-codex" ]] &&
                [[ "$CLAUDE_OCTOPUS_AUTONOMY" == "caller-autonomy" ]]
        ' _ "$PROJECT_ROOT" "$SOURCE_ROOT" "$dispatch_signal_expected_rc"
    ); then
        dispatch_signal_rc=0
    else
        dispatch_signal_rc=$?
    fi
    dispatch_signal_residue="$(find "$DISPATCH_SIGNAL_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
    if [[ "$dispatch_signal_rc" -ne 0 || -n "$dispatch_signal_residue" ]]; then
        dispatch_signal_failed=true
        dispatch_signal_failures="${dispatch_signal_failures}${dispatch_signal} rc=${dispatch_signal_rc} residue=${dispatch_signal_residue:-none}; "
    fi
    rm -rf "$DISPATCH_SIGNAL_TMPDIR" "$DISPATCH_SIGNAL_STARTED" "$DISPATCH_SIGNAL_PID_FILE" "$DISPATCH_SIGNAL_INT_MARKER" "$DISPATCH_SIGNAL_TERM_MARKER" "$DISPATCH_SIGNAL_EXIT_MARKER"
done
if [[ "$dispatch_signal_failed" == "false" ]]; then
    test_pass
else
    test_fail "expected exact signal status, full cleanup, restored environment, and unchanged caller traps: $dispatch_signal_failures"
fi

test_case "TERM cancels a running consultative provider without waiting for completion"
DEFERRED_TERM_TMPDIR="$TEST_TMP_DIR/deferred-term-tmp"
DEFERRED_TERM_STARTED="$TEST_TMP_DIR/deferred-term-started"
DEFERRED_TERM_FINISHED="$TEST_TMP_DIR/deferred-term-finished"
DEFERRED_TERM_CHILD_PID="$TEST_TMP_DIR/deferred-term-child.pid"
mkdir -p "$DEFERRED_TERM_TMPDIR"
TMPDIR="$DEFERRED_TERM_TMPDIR" \
DEFERRED_TERM_STARTED="$DEFERRED_TERM_STARTED" \
DEFERRED_TERM_FINISHED="$DEFERRED_TERM_FINISHED" \
DEFERRED_TERM_CHILD_PID="$DEFERRED_TERM_CHILD_PID" \
    /bin/bash -c '
        source "$1/scripts/lib/agent-sync.sh"
        log() { :; }
        run_agent_sync() {
            printf "started\n" > "$DEFERRED_TERM_STARTED"
            /bin/sleep 5 &
            provider_child=$!
            printf "%s\n" "$provider_child" > "$DEFERRED_TERM_CHILD_PID"
            wait "$provider_child"
            printf "finished\n" > "$DEFERRED_TERM_FINISHED"
            printf "review only\n"
        }
        cd "$2" || exit 98
        run_agent_sync_consultative codex "review only" 120 reviewer ceremony >/dev/null 2>&1
    ' _ "$PROJECT_ROOT" "$SOURCE_ROOT" &
deferred_term_runner=$!
deferred_term_started=false
for _ in $(seq 1 100); do
    if [[ -f "$DEFERRED_TERM_STARTED" && -f "$DEFERRED_TERM_CHILD_PID" ]]; then
        deferred_term_started=true
        break
    fi
    /bin/sleep 0.02
done
if [[ "$deferred_term_started" == "true" ]]; then
    kill -TERM "$deferred_term_runner" 2>/dev/null || true
fi
deferred_term_stopped=false
for _ in $(seq 1 100); do
    if ! kill -0 "$deferred_term_runner" 2>/dev/null; then
        deferred_term_stopped=true
        break
    fi
    /bin/sleep 0.02
done
if [[ "$deferred_term_stopped" != "true" ]]; then
    kill -KILL "$deferred_term_runner" 2>/dev/null || true
fi
set +e
wait "$deferred_term_runner" 2>/dev/null
deferred_term_rc=$?
set -e
deferred_term_child="$(cat "$DEFERRED_TERM_CHILD_PID" 2>/dev/null || true)"
case "$deferred_term_child" in
    ''|*[!0-9]*) ;;
    *)
        if kill -0 "$deferred_term_child" 2>/dev/null; then
            kill -KILL "$deferred_term_child" 2>/dev/null || true
        fi
        ;;
esac
deferred_term_residue="$(find "$DEFERRED_TERM_TMPDIR" -mindepth 1 -maxdepth 1 -print)"
if [[ "$deferred_term_started" == "true" && "$deferred_term_stopped" == "true" ]] &&
   [[ "$deferred_term_rc" -eq 143 && ! -e "$DEFERRED_TERM_FINISHED" && -z "$deferred_term_residue" ]]; then
    test_pass
else
    test_fail "expected TERM to interrupt provider capture promptly: started=$deferred_term_started stopped=$deferred_term_stopped rc=$deferred_term_rc finished=$(test -e "$DEFERRED_TERM_FINISHED" && printf yes || printf no) residue=${deferred_term_residue:-none}"
fi
command rm -rf "$DEFERRED_TERM_TMPDIR" "$DEFERRED_TERM_STARTED" "$DEFERRED_TERM_FINISHED" "$DEFERRED_TERM_CHILD_PID"

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

test_case "an in-scope TMPDIR cannot enter or contain the consultative copy"
IN_SCOPE_TMP_ROOT="$TEST_TMP_DIR/in-scope-tmp-source"
IN_SCOPE_TMPDIR="$IN_SCOPE_TMP_ROOT/local-tmp"
IN_SCOPE_OLD_WORKSPACE="$IN_SCOPE_TMPDIR/octopus-consultative.12345.67890.OLD123"
IN_SCOPE_OLD_LISTS="$IN_SCOPE_TMPDIR/octopus-copy-lists.12345.67890.OLD123"
IN_SCOPE_TRACKED_LOOKALIKE="$IN_SCOPE_TMPDIR/octopus-consultative.13579.24680.TRK123"
mkdir -p "$IN_SCOPE_OLD_WORKSPACE/workspace" "$IN_SCOPE_OLD_LISTS" "$IN_SCOPE_TRACKED_LOOKALIKE"
(
    cd "$IN_SCOPE_TMP_ROOT"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    printf 'tracked\n' > tracked.txt
    printf 'tracked lookalike\n' > "$IN_SCOPE_TRACKED_LOOKALIKE/kept.txt"
    git add tracked.txt "$IN_SCOPE_TRACKED_LOOKALIKE/kept.txt"
    git commit -q -m init
)
printf 'old workspace payload\n' > "$IN_SCOPE_OLD_WORKSPACE/workspace/leak.txt"
printf 'old list payload\n' > "$IN_SCOPE_OLD_LISTS/tracked"
if workspace="$(
    export TMPDIR="$IN_SCOPE_TMPDIR"
    _octopus_prepare_consultative_workspace "$IN_SCOPE_TMP_ROOT"
)"; then
    in_scope_tmp_rc=0
else
    in_scope_tmp_rc=$?
fi
case "$workspace" in
    "$IN_SCOPE_TMP_ROOT"/*) in_scope_destination=false ;;
    *) in_scope_destination=true ;;
esac
if [[ "$in_scope_tmp_rc" -eq 0 && "$in_scope_destination" == "true" ]] &&
   [[ "$(cat "$workspace/tracked.txt" 2>/dev/null)" == "tracked" ]] &&
   [[ "$(cat "$workspace/local-tmp/octopus-consultative.13579.24680.TRK123/kept.txt" 2>/dev/null)" == "tracked lookalike" ]] &&
   [[ ! -e "$workspace/local-tmp/octopus-consultative.12345.67890.OLD123" ]] &&
   [[ ! -e "$workspace/local-tmp/octopus-copy-lists.12345.67890.OLD123" ]] &&
   [[ -f "$IN_SCOPE_OLD_WORKSPACE/workspace/leak.txt" && -f "$IN_SCOPE_OLD_LISTS/tracked" ]]; then
    test_pass
else
    test_fail "expected an out-of-scope destination and no copied Octopus temp state: rc=$in_scope_tmp_rc workspace=${workspace:-none}"
fi
[[ -z "${workspace:-}" ]] || command rm -rf "$(dirname "$workspace")"

test_case "a Git-aware copy failure never attempts a whole-tree copy"
COPY_GUARD_BIN="$TEST_TMP_DIR/copy-guard-bin"
COPY_GUARD_MARKER="$TEST_TMP_DIR/whole-tree-copy-attempted"
REAL_CP="$(command -v cp)"
mkdir -p "$COPY_GUARD_BIN"
cat > "$COPY_GUARD_BIN/cp" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-pP" ]]; then
    exit 97
fi
for arg in "$@"; do
    if [[ "$arg" == "$SOURCE_ROOT/." ]]; then
        printf 'whole-tree copy attempted\n' > "$COPY_GUARD_MARKER"
    fi
done
exec "$REAL_CP" "$@"
EOF
chmod +x "$COPY_GUARD_BIN/cp"
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
