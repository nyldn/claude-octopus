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
TEST_START_PWD="$PWD"
mkdir -p "$SOURCE_REPO" "$RESULTS_DIR" "$WORKSPACE_DIR"

git -C "$SOURCE_REPO" init -q
git -C "$SOURCE_REPO" config user.email octopus-tests@example.invalid
git -C "$SOURCE_REPO" config user.name "Octopus Tests"
printf 'baseline\n' > "$SOURCE_REPO/baseline.txt"
printf 'ignored-context/\n' > "$SOURCE_REPO/.gitignore"
git -C "$SOURCE_REPO" add baseline.txt .gitignore
git -C "$SOURCE_REPO" commit -qm "baseline"
mkdir -p "$SOURCE_REPO/ignored-context"
printf 'grasp source context\n' > "$SOURCE_REPO/ignored-context/grasp.md"
printf 'plan source context\n' > "$SOURCE_REPO/ignored-context/run-plan.md"
SOURCE_REPO_PHYSICAL=$(cd "$SOURCE_REPO" && pwd -P)

ORIGINAL_PROJECT_ROOT="$SOURCE_REPO"
PROJECT_ROOT="$SOURCE_REPO"
OCTOPUS_RUN_WORKTREE_ROOT="$RUNTIME_ROOT"
unset OCTOPUS_TANGLE_RUN_WORKTREE
OCTOPUS_TANGLE_REQUIRE_CLEAN_BASELINE=true
OCTOPUS_TANGLE_RUN_ID="run-worktree-test"
SEEN_PROJECT_ROOT=""
SEEN_TASK_GROUP=""
SEEN_GRASP_FILE=""
SEEN_GRASP_CONTENT=""
SEEN_PLAN_FILE=""
SEEN_PLAN_CONTENT=""

log() { :; }
_tangle_develop_in_workspace() {
    SEEN_PROJECT_ROOT="$PROJECT_ROOT"
    SEEN_GRASP_FILE="${2:-}"
    SEEN_TASK_GROUP="${3:-}"
    SEEN_PLAN_FILE="${4:-}"
    [[ -n "$SEEN_GRASP_FILE" ]] && SEEN_GRASP_CONTENT=$(<"$SEEN_GRASP_FILE")
    [[ -n "$SEEN_PLAN_FILE" ]] && SEEN_PLAN_CONTENT=$(<"$SEEN_PLAN_FILE")
    printf 'agent write\n' > generated.txt
    return "${STUB_TANGLE_RC:-0}"
}

test_case "run worktree isolation defaults enabled"
if tangle_run_worktree_enabled; then
    test_pass
else
    test_fail "unset OCTOPUS_TANGLE_RUN_WORKTREE disabled isolation"
fi

test_case "explicit false disables run worktree isolation"
OCTOPUS_TANGLE_RUN_WORKTREE=false
if ! tangle_run_worktree_enabled; then
    test_pass
else
    test_fail "explicit false did not disable isolation"
fi
unset OCTOPUS_TANGLE_RUN_WORKTREE

test_case "invalid run ID override is rejected before execution"
OCTOPUS_TANGLE_RUN_ID="../../escape"
SEEN_TASK_GROUP=""
SEEN_PROJECT_ROOT=""
run_id_log="$TEST_ROOT/invalid-run-id.log"
log() { printf '%s %s\n' "$1" "$2" >> "$run_id_log"; }
status=0
tangle_develop "invalid run id" || status=$?
log() { :; }
if [[ "$status" -ne 0 \
    && -z "$SEEN_PROJECT_ROOT" \
    && "$(grep -c 'Invalid OCTOPUS_TANGLE_RUN_ID' "$run_id_log" 2>/dev/null || true)" -eq 1 ]]; then
    test_pass
else
    test_fail "invalid run ID reached delegated execution: ${SEEN_PROJECT_ROOT:-none}"
fi
OCTOPUS_TANGLE_RUN_ID="run-worktree-test"
SEEN_PROJECT_ROOT=""
SEEN_TASK_GROUP=""

test_case "dirty source is rejected before run worktree creation"
printf 'local-only\n' > "$SOURCE_REPO/untracked.txt"
OCTOPUS_TANGLE_RUN_ID="dirty-source"
status=0
tangle_develop "dirty source" || status=$?
if [[ "$status" -ne 0 \
    && ! -e "$RUNTIME_ROOT/dirty-source/integration" \
    && -z "$(git -C "$SOURCE_REPO" branch --list 'octopus/run/dirty-source/integration')" \
    && -z "$SEEN_PROJECT_ROOT" ]]; then
    test_pass
else
    test_fail "dirty source reached worktree creation or implementation"
fi
rm -f "$SOURCE_REPO/untracked.txt"
OCTOPUS_TANGLE_RUN_ID="run-worktree-test"

test_case "explicit untracked spec is injected without disabling isolation"
printf 'untracked spec context\n' > "$SOURCE_REPO/SPEC.md"
OCTOPUS_TANGLE_RUN_ID="untracked-spec"
SEEN_PROJECT_ROOT=""
SEEN_PLAN_FILE=""
SEEN_PLAN_CONTENT=""
status=0
cd "$SOURCE_REPO"
tangle_develop "Implement SPEC.md" || status=$?
if [[ "$status" -eq 0 \
    && "$SEEN_PROJECT_ROOT" == "$RUNTIME_ROOT/untracked-spec/integration" \
    && "$SEEN_PLAN_FILE" == "$SOURCE_REPO_PHYSICAL/SPEC.md" \
    && "$SEEN_PLAN_CONTENT" == "untracked spec context" \
    && -f "$SOURCE_REPO/SPEC.md" ]]; then
    test_pass
else
    test_fail "untracked spec was not safely injected into isolated execution"
fi
rm -f "$SOURCE_REPO/SPEC.md"
OCTOPUS_TANGLE_RUN_ID="run-worktree-test"

status=0
cd "$SOURCE_REPO/ignored-context"
tangle_develop "Implement plan:run-plan.md" "grasp.md" || status=$?

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

test_case "delegated execution reuses the isolated run ID"
if [[ "$SEEN_TASK_GROUP" == "run-worktree-test" ]]; then
    test_pass
else
    test_fail "delegated task group diverged from isolated run ID: $SEEN_TASK_GROUP"
fi

test_case "ignored caller context remains available in isolated execution"
if [[ "$SEEN_GRASP_FILE" == "$SOURCE_REPO_PHYSICAL/ignored-context/grasp.md" \
    && "$SEEN_GRASP_CONTENT" == "grasp source context" \
    && "$SEEN_PLAN_FILE" == "$SOURCE_REPO_PHYSICAL/ignored-context/run-plan.md" \
    && "$SEEN_PLAN_CONTENT" == "plan source context" ]]; then
    test_pass
else
    test_fail "caller context was not resolved before entering the run worktree"
fi
cd "$TEST_START_PWD"


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


test_case "rollback reports cleanup failures"
ROLLBACK_LOG="$TEST_ROOT/rollback-errors.log"
log() { printf '%s %s\n' "$1" "$2" >> "$ROLLBACK_LOG"; }
status=0
tangle_rollback_run_worktree "$SOURCE_REPO" "$TEST_ROOT/missing-worktree" "octopus/run/missing/integration" || status=$?
if [[ "$status" -ne 0 ]] \
    && grep -Fq 'Failed to remove Tangle run worktree during rollback' "$ROLLBACK_LOG" \
    && grep -Fq 'Failed to delete Tangle run branch during rollback' "$ROLLBACK_LOG"; then
    test_pass
else
    test_fail "rollback cleanup failures were hidden"
fi
log() { :; }

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

test_case "developer docs limit untracked Tangle context to one explicit file"
developer_docs="$SCRIPT_DIR/../../docs/DEVELOPER.md"
if grep -Fq 'may contain one explicit untracked context input' "$developer_docs" \
   && ! grep -Fq 'one or more explicit untracked context inputs' "$developer_docs"; then
    test_pass
else
    test_fail "developer docs overstate the supported untracked context cardinality"
fi

test_summary
