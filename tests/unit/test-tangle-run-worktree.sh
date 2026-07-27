#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle run worktree"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

TEST_ROOT="$TEST_TMP_DIR/tangle-run-worktree"
SOURCE_REPO="$TEST_ROOT/source"
RUNTIME_ROOT="$TEST_ROOT/runtime"
RESULTS_DIR="$TEST_ROOT/results"
WORKSPACE_DIR="$TEST_ROOT/state"
mkdir -p "$SOURCE_REPO" "$RESULTS_DIR" "$WORKSPACE_DIR"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

git -C "$SOURCE_REPO" init -q
git -C "$SOURCE_REPO" config user.email octopus-tests@example.invalid
git -C "$SOURCE_REPO" config user.name "Octopus Tests"
printf 'baseline\n' > "$SOURCE_REPO/baseline.txt"
git -C "$SOURCE_REPO" add baseline.txt
git -C "$SOURCE_REPO" commit -qm "baseline"

ORIGINAL_PROJECT_ROOT="$SOURCE_REPO"
PROJECT_ROOT="$SOURCE_REPO"
OCTOPUS_RUN_WORKTREE_ROOT="$RUNTIME_ROOT"
OCTOPUS_TANGLE_RUN_WORKTREE=true
OCTOPUS_TANGLE_RUN_ID="run-worktree-test"
SEEN_PROJECT_ROOT=""

log() { :; }
_tangle_develop_in_workspace() {
    SEEN_PROJECT_ROOT="$PROJECT_ROOT"
    printf 'agent write\n' > generated.txt
    return "${STUB_TANGLE_RC:-0}"
}

status=0
tangle_develop "test prompt" || status=$?

test_case "tangle implementation runs in isolated worktree"
if [[ "$SEEN_PROJECT_ROOT" == "$RUNTIME_ROOT/run-worktree-test/integration" ]]; then
    test_pass
else
    test_fail "unexpected implementation root: $SEEN_PROJECT_ROOT"
fi

test_case "agent writes are isolated from source checkout"
if [[ -f "$SEEN_PROJECT_ROOT/generated.txt" && ! -e "$SOURCE_REPO/generated.txt" ]]; then
    test_pass
else
    test_fail "generated file was not isolated"
fi

test_case "run branch is based on source HEAD"
source_head=$(git -C "$SOURCE_REPO" rev-parse HEAD)
run_head=$(git -C "$SEEN_PROJECT_ROOT" rev-parse HEAD)
if [[ "$source_head" == "$run_head" ]]; then
    test_pass
else
    test_fail "run branch base differs from source HEAD"
fi

test_case "source project context is restored"
if [[ "$PROJECT_ROOT" == "$ORIGINAL_PROJECT_ROOT" && "$PWD" != "$SEEN_PROJECT_ROOT" ]]; then
    test_pass
else
    test_fail "project context was not restored"
fi

test_case "Git metadata records source and run paths"
metadata="$RESULTS_DIR/.tangle-run-worktree-test-git.json"
if [[ -f "$metadata" ]] \
    && grep -Fq "$SOURCE_REPO" "$metadata" \
    && grep -Fq 'octopus/run/run-worktree-test/integration' "$metadata" \
    && grep -Fq "$SEEN_PROJECT_ROOT" "$metadata"; then
    test_pass
else
    test_fail "run Git metadata is missing or incomplete"
fi


test_case "metadata failure rolls back worktree and branch"
OCTOPUS_TANGLE_RUN_ID="run-worktree-metadata-failure"
ORIGINAL_WRITE_METADATA_DEFINITION=$(declare -f tangle_write_run_git_metadata)
tangle_write_run_git_metadata() { return 1; }
status=0
tangle_develop "metadata failure" || status=$?
if [[ "$status" -ne 0 \
    && ! -e "$RUNTIME_ROOT/run-worktree-metadata-failure/integration" \
    && -z "$(git -C "$SOURCE_REPO" branch --list 'octopus/run/run-worktree-metadata-failure/integration')" ]]; then
    test_pass
else
    test_fail "metadata failure left a worktree or branch behind"
fi
unset -f tangle_write_run_git_metadata
eval "$ORIGINAL_WRITE_METADATA_DEFINITION"

test_case "failed runs remain isolated and preserve worktree"
OCTOPUS_TANGLE_RUN_ID="run-worktree-failure"
STUB_TANGLE_RC=7
status=0
tangle_develop "failing prompt" || status=$?
if [[ "$status" -eq 7 \
    && -d "$RUNTIME_ROOT/run-worktree-failure/integration" \
    && ! -e "$SOURCE_REPO/generated.txt" ]]; then
    test_pass
else
    test_fail "failed run isolation was not preserved"
fi

test_summary
