#!/usr/bin/env bash
# Static tests for tangle contextual review/correction loop wiring.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle contextual review loop"

# Bash 5 inherits EXIT traps into subshells. Several fixtures exercise review
# code that restores its caller's traps, so only the parent test process may
# run the framework cleanup for this shared temporary directory.
CONTEXT_REVIEW_TEST_MAIN_PID="${BASHPID:-$$}"
cleanup_context_review_test_environment() {
    [[ "${BASHPID:-$$}" == "$CONTEXT_REVIEW_TEST_MAIN_PID" ]] || return 0
    cleanup_test_environment
}
trap cleanup_context_review_test_environment EXIT

WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
HELP="$PROJECT_ROOT/scripts/lib/usage-help.sh"

# shellcheck disable=SC1090
source "$WORKFLOWS"
log() { :; }

assert_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    test_case "$label"
    if grep -Fq -- "$pattern" "$file"; then
        test_pass
    else
        test_fail "missing pattern: $pattern"
    fi
}

make_test_dir() {
    local dir="$TEST_TMP_DIR/$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

test_case "review warning does not fabricate an actionable blocker"
warning_only="$TEST_TMP_DIR/review-warning-only.json"
printf '%s\n' '{"findings":[],"warning":"Round 1 was partial"}' > "$warning_only"
if [[ "$(tangle_review_blocking_count "$warning_only")" == "0" ]] &&
   [[ "$(tangle_review_warning_text "$warning_only")" == "Round 1 was partial" ]]; then
    test_pass
else
    test_fail "warning-only review must remain blocking through review_rc without becoming severity=normal"
fi

test_case "review warning preserves the count of real actionable blockers"
warning_with_blocker="$TEST_TMP_DIR/review-warning-with-blocker.json"
printf '%s\n' '{"findings":[{"severity":"normal","title":"real blocker"}],"warning":"Round 1 was partial"}' > "$warning_with_blocker"
if [[ "$(tangle_review_blocking_count "$warning_with_blocker")" == "1" ]]; then
    test_pass
else
    test_fail "warning must not alter the number of severity=normal findings"
fi

test_case "schema-invalid review findings remain fail-closed"
malformed_findings="$TEST_TMP_DIR/review-malformed.json"
missing_findings="$TEST_TMP_DIR/review-missing.json"
null_findings="$TEST_TMP_DIR/review-null.json"
non_object_findings="$TEST_TMP_DIR/review-non-object.json"
printf '%s\n' '{"findings":[' > "$malformed_findings"
printf '%s\n' '{}' > "$missing_findings"
printf '%s\n' '{"findings":null}' > "$null_findings"
printf '%s\n' '{"findings":["not-an-object"]}' > "$non_object_findings"
if [[ "$(tangle_review_blocking_count "$TEST_TMP_DIR/review-absent.json")" == "1" ]] &&
   [[ "$(tangle_review_blocking_count "$malformed_findings")" == "1" ]] &&
   [[ "$(tangle_review_blocking_count "$missing_findings")" == "1" ]] &&
   [[ "$(tangle_review_blocking_count "$null_findings")" == "1" ]] &&
   [[ "$(tangle_review_blocking_count "$non_object_findings")" == "1" ]]; then
    test_pass
else
    test_fail "invalid review schemas must retain one blocking failure"
fi

run_warning_review_gate() {
    local case_name="$1"
    local initial_findings="$2"
    local initial_rc="$3"
    local recovery_findings="$4"
    local recovery_rc="$5"
    local case_dir="$TEST_TMP_DIR/review-gate-$case_name"
    rm -rf "$case_dir"
    mkdir -p "$case_dir"

    bash -c '
        set -u
        project_root="$1"
        case_dir="$2"
        initial_findings="$3"
        initial_rc="$4"
        recovery_findings="$5"
        recovery_rc="$6"
        export RESULTS_DIR="$case_dir/results"
        mkdir -p "$RESULTS_DIR"

        initial_file="$case_dir/initial.json"
        recovery_file="$case_dir/recovery.json"
        review_calls_file="$case_dir/review-calls"
        correction_calls_file="$case_dir/correction-calls"
        validation_file="$case_dir/validation.md"
        printf "%s\n" "$initial_findings" > "$initial_file"
        printf "%s\n" "$recovery_findings" > "$recovery_file"
        printf "0" > "$review_calls_file"
        printf "0" > "$correction_calls_file"
        : > "$validation_file"

        source "$project_root/scripts/lib/testing.sh" 2>/dev/null
        source "$project_root/scripts/lib/workflows.sh" 2>/dev/null
        log() { :; }
        tangle_build_develop_review_context() {
            printf "%s\n" "$case_dir/context-$7.md"
        }
        tangle_run_context_code_review() {
            local calls rc
            calls=$(<"$review_calls_file")
            if [[ "$calls" -eq 0 ]]; then
                TANGLE_REVIEW_FINDINGS_FILE="$initial_file"
                rc="$initial_rc"
            else
                TANGLE_REVIEW_FINDINGS_FILE="$recovery_file"
                rc="$recovery_rc"
            fi
            printf "%s" "$((calls + 1))" > "$review_calls_file"
            return "$rc"
        }
        tangle_apply_review_corrections() {
            local calls
            calls=$(<"$correction_calls_file")
            printf "%s" "$((calls + 1))" > "$correction_calls_file"
            TANGLE_CORRECTION_STATUS="completed"
            TANGLE_CORRECTION_CHANGED=1
            TANGLE_CORRECTION_CONTAMINATION=""
            TANGLE_CORRECTION_FILE="$case_dir/correction.md"
            return 0
        }
        validate_tangle_results() { return 0; }

        rc=0
        OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=bounded \
        OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS=1 \
            tangle_contextual_review_gate \
                test "prompt" "context" "subtasks" \
                "$validation_file" "$case_dir/worktree-before" 0 codex || rc=$?

        printf "rc=%s corrections=%s reviews=%s\n" \
            "$rc" "$(<"$correction_calls_file")" "$(<"$review_calls_file")"
    ' _ "$PROJECT_ROOT" "$case_dir" "$initial_findings" "$initial_rc" \
        "$recovery_findings" "$recovery_rc"
}

test_case "warning-only review is fatal without a correction call"
out=$(run_warning_review_gate \
    warning-only \
    '{"findings":[],"warning":"Round 1 was partial"}' 1 \
    '{"findings":[]}' 0)
if [[ "$out" == "rc=1 corrections=0 reviews=1" ]]; then
    test_pass
else
    test_fail "warning-only review entered correction or lost fatal status: $out"
fi

test_case "warning with a real blocker can recover after one bounded correction"
out=$(run_warning_review_gate \
    warning-with-blocker \
    '{"findings":[{"severity":"normal","title":"real blocker","file":"src/app.sh","line":1}],"warning":"Round 1 was partial"}' 1 \
    '{"findings":[]}' 0)
if [[ "$out" == "rc=0 corrections=1 reviews=2" ]]; then
    test_pass
else
    test_fail "actionable warning did not complete one bounded recovery: $out"
fi

test_case "missing findings array is fatal without a correction call"
out=$(run_warning_review_gate \
    missing-findings \
    '{}' 0 \
    '{"findings":[]}' 0)
if [[ "$out" == "rc=1 corrections=0 reviews=1" ]]; then
    test_pass
else
    test_fail "missing findings array entered correction or passed: $out"
fi

test_case "truncated findings are fatal without a correction call"
out=$(run_warning_review_gate \
    truncated-findings \
    '{"findings":[' 0 \
    '{"findings":[]}' 0)
if [[ "$out" == "rc=1 corrections=0 reviews=1" ]]; then
    test_pass
else
    test_fail "truncated findings entered correction or passed: $out"
fi

assert_contains "$WORKFLOWS" "tangle_build_develop_review_context" "tangle builds review context"
assert_contains "$WORKFLOWS" "tangle_run_context_code_review" "tangle runs contextual code review"
assert_contains "$WORKFLOWS" "tangle_build_review_diff_snapshot" "tangle snapshots complete review input"
assert_contains "$WORKFLOWS" "all-changes" "tangle snapshot includes staged and unstaged changes"
assert_contains "$WORKFLOWS" "regenerating immutable review snapshot once" "dirty no-diff review retries exactly once"
assert_contains "$WORKFLOWS" 'wait "$stdout_tee_pid"' "review output waits for stdout capture before inspection"
assert_contains "$WORKFLOWS" 'wait "$stderr_tee_pid"' "review output waits for stderr capture before inspection"
assert_contains "$WORKFLOWS" 'return "$review_rc"' "review status comes from review_run"
assert_contains "$WORKFLOWS" '"${review_log:-}"' "review log is covered by cleanup trap"
assert_contains "$WORKFLOWS" "artifactId" "context review assigns an invocation-owned artifact identity"
test_case "context review does not use coarse mtime freshness"
if ! grep -Fq -- '-nt "$marker"' "$WORKFLOWS"; then
    test_pass
else
    test_fail "context review findings must be selected by invocation identity, not mtime"
fi
assert_contains "$WORKFLOWS" "contextFile" "review profile passes contextFile"
assert_contains "$WORKFLOWS" ".claude-octopus/results" "review context is stored inside workspace"
assert_contains "$WORKFLOWS" "plan-conformance" "review focus includes plan conformance"
assert_contains "$WORKFLOWS" "tangle_apply_review_corrections" "tangle applies review corrections"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE" "correction loop supports explicit bounded mode"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_CORRECTION_STALL_WINDOW" "correction loop uses stall watchdog"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_DEADLINE:-0" "initial tangle deadline defaults to no absolute timeout"
assert_contains "$WORKFLOWS" "decompose_prompt" "decomposition prompt is present"
assert_contains "$WORKFLOWS" '"$decompose_prompt" 0' "decomposition runs without absolute timeout"
assert_contains "$WORKFLOWS" "_tangle_max_wait" "initial tangle deadline is optional"
assert_contains "$WORKFLOWS" "failed but left partial writes" "partial writes continue to validation/review"
assert_contains "$WORKFLOWS" 'run_agent_sync "$correction_agent" "$correction_prompt" 0' "corrections run without absolute timeout"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_CODE_REVIEW" "code review gate is toggleable"
assert_contains "$WORKFLOWS" "Contextual code review warning" "review warnings are blocking"
assert_contains "$WORKFLOWS" "No changes found to review" "legacy no-diff message is detected"
assert_contains "$WORKFLOWS" 'grep -ci "No changes found to review"' "retry match uses a pipefail-safe count"
assert_contains "$WORKFLOWS" '[[ "$no_changes_count" -gt 0 ]]' "retry match guards the count numerically"
assert_contains "$WORKFLOWS" "with no actionable blockers" "non-zero review without actionable blockers is blocking"
assert_contains "$WORKFLOWS" "Skipping ink/deliver because tangle validation gate returned non-zero" "ink is skipped when validation fails"
assert_contains "$HELP" "Contextual code review" "develop help documents contextual review"
assert_contains "$HELP" "OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE" "develop help documents bounded mode"
assert_contains "$HELP" "OCTOPUS_TANGLE_CORRECTION_STALL_WINDOW" "develop help documents stall window"
assert_contains "$WORKFLOWS" "OCTOPUS_INK_REVIEW_TIMEOUT:-0" "ink review has no wall timeout by default"

test_case "review snapshot captures staged, unstaged, and untracked changes"
workspace=$(make_test_dir workspace-review-snapshot)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base-a\n' > "$workspace/a.txt"
printf 'base-b\n' > "$workspace/b.txt"
git -C "$workspace" add a.txt b.txt
git -C "$workspace" commit -q -m init
printf 'staged-a\n' > "$workspace/a.txt"
git -C "$workspace" add a.txt
printf 'unstaged-b\n' > "$workspace/b.txt"
printf 'untracked-c\n' > "$workspace/c.txt"
snapshot_results=$(make_test_dir snapshot-results)
if snapshot=$(cd "$workspace" && RESULTS_DIR="$snapshot_results" tangle_build_review_diff_snapshot "test" "initial"); then
    snapshot_mode=$(stat -c '%a' "$snapshot" 2>/dev/null || stat -f '%Lp' "$snapshot" 2>/dev/null || true)
else
    snapshot=""
    snapshot_mode=""
fi
if [[ -f "$snapshot" ]] && [[ "$snapshot_mode" == "400" ]] &&
   grep -q 'a.txt' "$snapshot" && grep -q 'b.txt' "$snapshot" && grep -q 'c.txt' "$snapshot"; then
    test_pass
else
    test_fail "review snapshot must be owner-only and cover staged, unstaged, and untracked changes"
fi

test_case "review collection rejects a missing symbolic HEAD in a non-empty repository"
workspace=$(make_test_dir workspace-missing-symbolic-head)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'committed\n' > "$workspace/committed.txt"
git -C "$workspace" add committed.txt
git -C "$workspace" commit -q -m init
printf 'ref: refs/heads/missing\n' > "$workspace/.git/HEAD"
if (
    cd "$workspace" || exit 1
    ! review_collect_all_changes_diff >/dev/null
); then
    test_pass
else
    test_fail "a symbolic HEAD with a missing target must not be treated as an unborn repository"
fi

test_case "untracked collection propagates git ls-files failures"
workspace=$(make_test_dir workspace-ls-files-failure)
git -C "$workspace" init -q
printf 'untracked\n' > "$workspace/untracked.txt"
if (
    cd "$workspace" || exit 1
    git() {
        if [[ "${1:-}" == "-C" && "${3:-}" == "ls-files" ]]; then
            return 2
        fi
        command git "$@"
    }
    ! review_collect_untracked_diff >/dev/null
); then
    test_pass
else
    test_fail "untracked collection swallowed a git ls-files failure"
fi

test_case "repo-local TMPDIR does not contaminate review collection"
workspace=$(make_test_dir workspace-local-tmpdir)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base\n' > "$workspace/tracked.txt"
git -C "$workspace" add tracked.txt
git -C "$workspace" commit -q -m init
printf 'untracked\n' > "$workspace/untracked.txt"
mkdir -p "$workspace/tmp"
if collected=$(cd "$workspace" && TMPDIR="$workspace/tmp" review_collect_all_changes_diff) &&
   grep -q 'untracked.txt' <<< "$collected" &&
   ! grep -q 'octopus-review-untracked' <<< "$collected"; then
    test_pass
else
    test_fail "review collection scratch files leaked into the worktree diff"
fi

test_case "review snapshot rejects an initial partial diff when collection errors"
workspace=$(make_test_dir workspace-partial-initial)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base\n' > "$workspace/tracked.txt"
git -C "$workspace" add tracked.txt
git -C "$workspace" commit -q -m init
printf 'changed\n' > "$workspace/tracked.txt"
partial_results=$(make_test_dir partial-initial-results)
if (
    cd "$workspace" || exit 1
    git() {
        if [[ "${1:-}" == "diff" && "${2:-}" == "HEAD" ]]; then
            printf '%s\n' 'diff --git a/tracked.txt b/tracked.txt' '@@ -1 +1 @@' '-base' '+partial'
            return 2
        fi
        command git "$@"
    }
    ! RESULTS_DIR="$partial_results" tangle_build_review_diff_snapshot test partial-initial >/dev/null 2>&1
) && ! find "$partial_results" -type f -name 'tangle-review-input-*.diff' -print -quit | grep -q .; then
    test_pass
else
    test_fail "initial snapshot collection must reject partial diff output from a failing git command"
fi

test_case "review snapshot rejects partial output from the bounded regeneration"
workspace=$(make_test_dir workspace-partial-retry)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base\n' > "$workspace/tracked.txt"
git -C "$workspace" add tracked.txt
git -C "$workspace" commit -q -m init
printf 'changed\n' > "$workspace/tracked.txt"
retry_results=$(make_test_dir partial-retry-results)
retry_count="$retry_results/collect-count"
printf '0\n' > "$retry_count"
if (
    cd "$workspace" || exit 1
    review_collect_diff() {
        local calls
        calls=$(<"$retry_count")
        calls=$((calls + 1))
        printf '%s\n' "$calls" > "$retry_count"
        if [[ "$calls" -eq 1 ]]; then
            return 0
        fi
        printf '%s\n' 'diff --git a/tracked.txt b/tracked.txt' '@@ -1 +1 @@' '-base' '+partial'
        return 2
    }
    ! RESULTS_DIR="$retry_results" tangle_build_review_diff_snapshot test partial-retry >/dev/null 2>&1
) && [[ "$(<"$retry_count")" -eq 2 ]] &&
   ! find "$retry_results" -type f -name 'tangle-review-input-*.diff' -print -quit | grep -q .; then
    test_pass
else
    test_fail "snapshot regeneration must reject partial diff output when the retry command fails"
fi

test_case "repository-local results do not contaminate review snapshots"
workspace=$(make_test_dir workspace-local-results)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'tracked content\n' > "$workspace/tracked.txt"
git -C "$workspace" add tracked.txt
git -C "$workspace" commit -q -m init
printf 'changed content\n' > "$workspace/tracked.txt"
local_results="$workspace/review-results"
mkdir -p "$local_results"
if first_snapshot=$(cd "$workspace" && RESULTS_DIR="$local_results" tangle_build_review_diff_snapshot "test" "local-results-1"); then
    printf 'unrelated user change\n' > "$workspace/unrelated.txt"
    if second_snapshot=$(cd "$workspace" && RESULTS_DIR="$local_results" tangle_build_review_diff_snapshot "test" "local-results-2") &&
       grep -q 'unrelated.txt' "$second_snapshot" &&
       ! grep -q 'review-results/' "$second_snapshot" &&
       ! grep -q "$(basename "$first_snapshot")" "$second_snapshot"; then
        test_pass
    else
        test_fail "second snapshot must exclude prior RESULTS_DIR artifacts without hiding unrelated changes"
    fi
else
    test_fail "repository-local results must not contaminate snapshot input"
fi

test_case "repository root cannot be used as the review results directory"
workspace=$(make_test_dir workspace-root-results)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base\n' > "$workspace/tracked.txt"
git -C "$workspace" add tracked.txt
git -C "$workspace" commit -q -m init
printf 'changed\n' > "$workspace/tracked.txt"
if ! (cd "$workspace" && RESULTS_DIR="$workspace" tangle_build_review_diff_snapshot test root-results) >/dev/null 2>&1; then
    test_pass
else
    test_fail "using the repository root as RESULTS_DIR would hide unrelated user changes and must fail closed"
fi

test_case "repository-local results exclusion remains repository-wide from a subdirectory"
workspace=$(make_test_dir workspace-local-results-subdirectory)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base\n' > "$workspace/top-level.txt"
mkdir -p "$workspace/subdir" "$workspace/review-results"
git -C "$workspace" add top-level.txt
git -C "$workspace" commit -q -m init
printf 'changed\n' > "$workspace/top-level.txt"
printf 'untracked\n' > "$workspace/top-level-untracked.txt"
if subdir_snapshot=$(cd "$workspace/subdir" && RESULTS_DIR="$workspace/review-results" tangle_build_review_diff_snapshot test subdirectory) &&
   grep -q 'top-level.txt' "$subdir_snapshot" &&
   grep -q 'top-level-untracked.txt' "$subdir_snapshot" &&
   ! grep -q 'review-results/' "$subdir_snapshot"; then
    test_pass
else
    test_fail "RESULTS_DIR exclusion must not scope all-changes collection to the caller subdirectory"
fi

test_case "external results keep untracked collection repository-wide from a subdirectory"
workspace=$(make_test_dir workspace-subdir-external-results)
external_results=$(make_test_dir external-review-results)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base\n' > "$workspace/top-level.txt"
mkdir -p "$workspace/subdir"
git -C "$workspace" add top-level.txt
git -C "$workspace" commit -q -m init
printf 'top-level untracked\n' > "$workspace/top-level-untracked.txt"
if subdir_snapshot=$(cd "$workspace/subdir" && RESULTS_DIR="$external_results" tangle_build_review_diff_snapshot test external-results) &&
   grep -q 'top-level-untracked.txt' "$subdir_snapshot"; then
    test_pass
else
    test_fail "external RESULTS_DIR must not make untracked collection caller-subdirectory scoped"
fi

test_case "unborn repository collection remains repository-wide from a subdirectory"
workspace=$(make_test_dir workspace-unborn-subdirectory)
git -C "$workspace" init -q
mkdir -p "$workspace/subdir"
printf 'top-level unborn\n' > "$workspace/top-level.txt"
if unborn_snapshot=$(cd "$workspace/subdir" && review_collect_unborn_worktree_diff) &&
   grep -q 'top-level.txt' <<< "$unborn_snapshot" &&
   grep -q 'top-level unborn' <<< "$unborn_snapshot"; then
    test_pass
else
    test_fail "unborn collection must resolve root-relative Git paths from the repository root"
fi

test_case "context review rejects a reused artifact identity before dispatch"
workspace=$(make_test_dir workspace-stale-artifact)
stale_results="$workspace/review-results"
mkdir -p "$stale_results"
stale_marker="$TEST_TMP_DIR/octopus-tangle-review-marker.REUSED"
stale_id="${stale_marker##*/}"
printf '%s\n' '{"findings":[]}' > "$stale_results/review-findings-old-${stale_id}.json"
stale_dispatch="$workspace/dispatched"
if (
    export RESULTS_DIR="$stale_results"
    export OCTOPUS_TANGLE_REVIEW_TARGET="$workspace/input.diff"
    printf 'diff --git a/a b/a\n' > "$OCTOPUS_TANGLE_REVIEW_TARGET"
    mktemp() {
        case "${1:-}" in
            *octopus-tangle-review-marker.XXXXXX)
                : > "$stale_marker"
                printf '%s\n' "$stale_marker"
                ;;
            *) command mktemp "$@" ;;
        esac
    }
    review_run() {
        : > "$stale_dispatch"
        return 0
    }
    ! tangle_run_context_code_review test "$workspace/context.md" initial &&
        [[ ! -e "$stale_dispatch" ]] && [[ ! -e "$stale_marker" ]]
); then
    test_pass
else
    test_fail "a pre-existing findings suffix collision must fail before review dispatch"
fi

test_case "context review rejects a reused symlink artifact before dispatch"
workspace=$(make_test_dir workspace-stale-symlink-artifact)
symlink_results="$workspace/review-results"
mkdir -p "$symlink_results"
symlink_marker="$TEST_TMP_DIR/octopus-tangle-review-marker.SYMLINK"
symlink_id="${symlink_marker##*/}"
symlink_target="$workspace/symlink-target"
printf 'sentinel\n' > "$symlink_target"
ln -s "$symlink_target" "$symlink_results/review-findings-old-${symlink_id}.json"
symlink_dispatch="$workspace/dispatched"
if (
    export RESULTS_DIR="$symlink_results"
    export OCTOPUS_TANGLE_REVIEW_TARGET="$workspace/input.diff"
    printf 'diff --git a/a b/a\n' > "$OCTOPUS_TANGLE_REVIEW_TARGET"
    mktemp() {
        case "${1:-}" in
            *octopus-tangle-review-marker.XXXXXX)
                : > "$symlink_marker"
                printf '%s\n' "$symlink_marker"
                ;;
            *) command mktemp "$@" ;;
        esac
    }
    review_run() {
        : > "$symlink_dispatch"
        return 0
    }
    ! tangle_run_context_code_review test "$workspace/context.md" initial &&
        [[ ! -e "$symlink_dispatch" ]] &&
        [[ "$(cat "$symlink_target")" == sentinel ]] &&
        [[ -L "$symlink_results/review-findings-old-${symlink_id}.json" ]]
); then
    test_pass
else
    test_fail "a matching symlink must fail before dispatch without changing its target"
fi

test_case "context review preserves another invocation's artifact claim"
workspace=$(make_test_dir workspace-claimed-artifact)
claimed_results="$workspace/review-results"
mkdir -p "$claimed_results"
claimed_marker="$TEST_TMP_DIR/octopus-tangle-review-marker.CLAIMED"
claimed_id="${claimed_marker##*/}"
claimed_dir="$claimed_results/.tangle-review-claim-${claimed_id}"
mkdir "$claimed_dir"
claimed_dispatch="$workspace/dispatched"
if (
    export RESULTS_DIR="$claimed_results"
    export OCTOPUS_TANGLE_REVIEW_TARGET="$workspace/input.diff"
    printf 'diff --git a/a b/a\n' > "$OCTOPUS_TANGLE_REVIEW_TARGET"
    mktemp() {
        case "${1:-}" in
            *octopus-tangle-review-marker.XXXXXX)
                : > "$claimed_marker"
                printf '%s\n' "$claimed_marker"
                ;;
            *) command mktemp "$@" ;;
        esac
    }
    review_run() {
        : > "$claimed_dispatch"
        return 0
    }
    ! tangle_run_context_code_review test "$workspace/context.md" initial &&
        [[ -d "$claimed_dir" ]] && [[ ! -e "$claimed_dispatch" ]]
); then
    test_pass
else
    test_fail "a failed claim must not remove another invocation's ownership directory"
fi

test_case "context review rejects a reused retry identity before retry dispatch"
workspace=$(make_test_dir workspace-stale-retry-artifact)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base\n' > "$workspace/tracked.txt"
git -C "$workspace" add tracked.txt
git -C "$workspace" commit -q -m init
printf 'changed\n' > "$workspace/tracked.txt"
retry_results="$workspace/review-results"
mkdir -p "$retry_results"
retry_marker="$TEST_TMP_DIR/octopus-tangle-review-marker.RETRY"
retry_id="${retry_marker##*/}"
printf '%s\n' '{"findings":[]}' > "$retry_results/review-findings-old-${retry_id}-retry1.json"
retry_calls="$workspace/review-calls"
printf '0\n' > "$retry_calls"
if (
    cd "$workspace" || exit 1
    export RESULTS_DIR="$retry_results"
    mktemp() {
        case "${1:-}" in
            *octopus-tangle-review-marker.XXXXXX)
                : > "$retry_marker"
                printf '%s\n' "$retry_marker"
                ;;
            *) command mktemp "$@" ;;
        esac
    }
    review_run() {
        local calls
        calls=$(<"$retry_calls")
        printf '%s\n' "$((calls + 1))" > "$retry_calls"
        printf '%s\n' "No changes found to review"
        return 1
    }
    ! tangle_run_context_code_review test "$workspace/context.md" initial &&
        [[ "$(<"$retry_calls")" -eq 1 ]]
); then
    test_pass
else
    test_fail "a pre-existing retry suffix collision must stop before the retry dispatch"
fi

test_case "review capture preserves separate streams and exact review status"
capture_log="$TEST_TMP_DIR/review-capture.log"
capture_stderr="$TEST_TMP_DIR/review-capture.stderr"
review_run() {
    printf 'stdout-only\n'
    printf 'stderr-only\n' >&2
    return 37
}
set +e
capture_stdout=$(_tangle_review_capture '{}' "$capture_log" 2>"$capture_stderr")
capture_rc=$?
set -e
if [[ "$capture_rc" -eq 37 ]] &&
   [[ "$capture_stdout" == "stdout-only" ]] &&
   [[ "$(<"$capture_stderr")" == "stderr-only" ]] &&
   grep -Fq 'stdout-only' "$capture_log" &&
   grep -Fq 'stderr-only' "$capture_log"; then
    test_pass
else
    test_fail "capture must keep stdout/stderr separate, log both, and return rc=37"
fi

test_case "review capture waits for explicit start-gate content"
gate_file="$TEST_TMP_DIR/review-start-gate"
gate_log="$TEST_TMP_DIR/review-start-gate.log"
gate_dispatch="$TEST_TMP_DIR/review-start-gate.dispatch"
: > "$gate_file"
review_run() {
    : > "$gate_dispatch"
    return 0
}
_tangle_review_capture '{}' "$gate_log" "$gate_file" &
gate_capture_pid=$!
sleep 0.1
gate_released_early=false
[[ -e "$gate_dispatch" ]] && gate_released_early=true
printf 'ready\n' > "$gate_file"
gate_capture_rc=0
wait "$gate_capture_pid" || gate_capture_rc=$?
if [[ "$gate_released_early" == false ]] && [[ "$gate_capture_rc" -eq 0 ]] && [[ -e "$gate_dispatch" ]]; then
    test_pass
else
    test_fail "an empty mktemp-owned gate must not release review dispatch"
fi

test_case "context review waits for tee before retry inspection"
workspace=$(make_test_dir workspace-synchronized-review)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base content\n' > "$workspace/tracked.txt"
git -C "$workspace" add tracked.txt
git -C "$workspace" commit -q -m init
printf 'changed content\n' > "$workspace/tracked.txt"
sync_results="$workspace/review-results"
mkdir -p "$sync_results"
sync_calls="$workspace/review-calls"
printf '0\n' > "$sync_calls"
if (
    cd "$workspace" || exit 1
    export RESULTS_DIR="$sync_results"
    tee() { sleep 1; command tee "$@"; }
    review_run() {
        local calls artifact_id
        calls=$(<"$sync_calls")
        artifact_id=$(printf '%s' "$1" | jq -r '.artifactId')
        printf '%s\n' "$((calls + 1))" > "$sync_calls"
        if [[ "$calls" -eq 0 ]]; then
            printf '%s\n' "No changes found to review"
            return 1
        fi
        printf '%s\n' '{"findings":[]}' > "$RESULTS_DIR/review-findings-synchronized-${artifact_id}.json"
        printf '%s\n' "review recovered"
        return 0
    }
    if tangle_run_context_code_review test "$workspace/context.md" initial; then
        [[ "$(<"$sync_calls")" -eq 2 ]]
    else
        false
    fi
); then
    test_pass
else
    test_fail "context review must wait for tee so the dirty no-diff retry is not skipped"
fi

test_case "signal before process-group recording kills the gated capture promptly"
early_signal_child="$TEST_TMP_DIR/review-early-signal.sh"
early_signal_log="$TEST_TMP_DIR/review-early-signal.log"
early_signal_gate="$TEST_TMP_DIR/review-early-signal.gate"
early_signal_dispatch="$TEST_TMP_DIR/review-early-signal.dispatch"
cat > "$early_signal_child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail
WORKFLOWS="$1"
REVIEW_LOG="$2"
START_GATE="$3"
DISPATCH="$4"
source "$WORKFLOWS"
log() { :; }
review_run() {
    : > "$DISPATCH"
}
: > "$START_GATE"
_tangle_review_capture '{}' "$REVIEW_LOG" "$START_GATE" &
_review_capture_pid=$!
_review_capture_pgid=""
artifact_id="early-signal"
_review_exit_trap=$(trap -p EXIT || true)
_review_int_trap=$(trap -p INT || true)
_review_term_trap=$(trap -p TERM || true)
trap '_tangle_review_handle_signal TERM "$@"' TERM
kill -TERM "$$"
CHILD
chmod +x "$early_signal_child"
early_signal_started=$(date +%s)
set +e
bash "$early_signal_child" "$WORKFLOWS" "$early_signal_log" "$early_signal_gate" "$early_signal_dispatch"
early_signal_rc=$?
set -e
early_signal_elapsed=$(($(date +%s) - early_signal_started))
if [[ "$early_signal_rc" -eq 143 ]] && [[ "$early_signal_elapsed" -lt 4 ]] && [[ ! -e "$early_signal_dispatch" ]]; then
    test_pass
else
    test_fail "pre-PGID cancellation must kill the known capture PID without waiting for the gate timeout (rc=$early_signal_rc elapsed=$early_signal_elapsed)"
fi

test_case "TERM stops contextual review and preserves signal status"
workspace=$(make_test_dir workspace-review-term)
git -C "$workspace" init -q
git -C "$workspace" config user.email test@example.com
git -C "$workspace" config user.name "Octopus Test"
printf 'base content\n' > "$workspace/tracked.txt"
git -C "$workspace" add tracked.txt
git -C "$workspace" commit -q -m init
printf 'changed content\n' > "$workspace/tracked.txt"
term_results="$workspace/review-results"
mkdir -p "$term_results"
term_output="$TEST_TMP_DIR/review-term-output"
term_review_pid_file="$TEST_TMP_DIR/review-term-pid"
bash -c '
    set -u
    source "$1/scripts/lib/workflows.sh"
    export RESULTS_DIR="$2"
    TERM_REVIEW_PID_FILE="$4"
    log() { :; }
    review_run() {
        sleep 30 &
        review_sleep_pid=$!
        printf "%s\n" "$review_sleep_pid" > "$TERM_REVIEW_PID_FILE"
        wait "$review_sleep_pid"
        printf "%s\n" "review unexpectedly completed"
        return 0
    }
    cd "$3" || exit 1
    tangle_run_context_code_review test "$3/context.md" initial
    printf "%s\n" "pipeline continued"
' _ "$PROJECT_ROOT" "$term_results" "$workspace" "$term_review_pid_file" > "$term_output" 2>&1 &
term_runner_pid=$!
term_ready=false
term_start_ticks=0
while [[ "$term_start_ticks" -lt 50 ]]; do
    if [[ -s "$term_review_pid_file" ]]; then
        term_ready=true
        break
    fi
    kill -0 "$term_runner_pid" 2>/dev/null || break
    sleep 0.1
    term_start_ticks=$((term_start_ticks + 1))
done
if [[ "$term_ready" == true ]]; then
    kill -TERM "$term_runner_pid"
fi
term_deadline=0
while kill -0 "$term_runner_pid" 2>/dev/null && [[ "$term_deadline" -lt 30 ]]; do
    sleep 0.1
    term_deadline=$((term_deadline + 1))
done
term_rc=0
if [[ "$term_ready" != true ]]; then
    kill -TERM "$term_runner_pid" 2>/dev/null || true
    wait "$term_runner_pid" 2>/dev/null || true
    term_rc=998
elif kill -0 "$term_runner_pid" 2>/dev/null; then
    kill -KILL "$term_runner_pid" 2>/dev/null || true
    wait "$term_runner_pid" 2>/dev/null || true
    term_rc=999
else
    wait "$term_runner_pid" || term_rc=$?
fi
term_review_alive=false
if [[ -s "$term_review_pid_file" ]] && kill -0 "$(<"$term_review_pid_file")" 2>/dev/null; then
    term_review_alive=true
fi
if [[ "$term_ready" == true ]] && [[ "$term_rc" -eq 143 ]] && [[ "$term_review_alive" == false ]] &&
   ! grep -Fq "pipeline continued" "$term_output" &&
   [[ -z "$(find "$term_results" -maxdepth 1 -type f -name 'review-findings-*.json' -print -quit)" ]]; then
    test_pass
else
    test_fail "TERM must stop review promptly with rc=143 and no accepted findings (ready=$term_ready rc=$term_rc output=$(tr '\n' ' ' < "$term_output"))"
fi

test_case "TERM preserves caller arguments and cannot inherit a saved trap exit status"
trap_marker="$TEST_TMP_DIR/review-caller-argument.marker"
trap_continued="$TEST_TMP_DIR/review-caller-continued.marker"
trap_child="$TEST_TMP_DIR/review-caller-trap.sh"
cat > "$trap_child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail
WORKFLOWS="$1"
MARKER="$2"
CONTINUED="$3"
source "$WORKFLOWS"
log() { :; }
trap 'printf "%s\n" "$1" > "$MARKER"; exit 77' TERM
_review_exit_trap=$(trap -p EXIT || true)
_review_int_trap=$(trap -p INT || true)
_review_term_trap=$(trap -p TERM || true)
_review_capture_pid=""
trap '_tangle_review_handle_signal TERM "$@"' TERM
caller_function() {
    kill -TERM "$$"
}
caller_function CALLER_ARGUMENT
: > "$CONTINUED"
CHILD
chmod +x "$trap_child"
set +e
bash "$trap_child" "$WORKFLOWS" "$trap_marker" "$trap_continued"
trap_rc=$?
set -e
if [[ "$trap_rc" -eq 143 ]] &&
   [[ "$(cat "$trap_marker" 2>/dev/null || true)" == "CALLER_ARGUMENT" ]] &&
   [[ ! -e "$trap_continued" ]]; then
    test_pass
else
    test_fail "saved TERM trap must see caller arguments while outward status remains 143 (rc=$trap_rc)"
fi

test_case "INT preserves caller arguments and cannot inherit a saved trap exit status"
int_trap_marker="$TEST_TMP_DIR/review-int-caller-argument.marker"
int_trap_continued="$TEST_TMP_DIR/review-int-caller-continued.marker"
int_trap_child="$TEST_TMP_DIR/review-int-caller-trap.sh"
cat > "$int_trap_child" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail
WORKFLOWS="$1"
MARKER="$2"
CONTINUED="$3"
source "$WORKFLOWS"
log() { :; }
trap 'printf "%s\n" "$1" > "$MARKER"; exit 77' INT
_review_exit_trap=$(trap -p EXIT || true)
_review_int_trap=$(trap -p INT || true)
_review_term_trap=$(trap -p TERM || true)
_review_capture_pid=""
trap '_tangle_review_handle_signal INT "$@"' INT
caller_function() {
    kill -INT "$$"
}
caller_function CALLER_ARGUMENT
: > "$CONTINUED"
CHILD
chmod +x "$int_trap_child"
set +e
bash "$int_trap_child" "$WORKFLOWS" "$int_trap_marker" "$int_trap_continued"
int_trap_rc=$?
set -e
if [[ "$int_trap_rc" -eq 130 ]] &&
   [[ "$(cat "$int_trap_marker" 2>/dev/null || true)" == "CALLER_ARGUMENT" ]] &&
   [[ ! -e "$int_trap_continued" ]]; then
    test_pass
else
    test_fail "saved INT trap must see caller arguments while outward status remains 130 (rc=$int_trap_rc)"
fi

test_case "review dispatch fails closed when a dedicated process group is not established"
workspace=$(make_test_dir workspace-review-group-refusal)
group_results="$workspace/review-results"
mkdir -p "$group_results"
group_dispatch="$workspace/dispatched"
if (
    export RESULTS_DIR="$group_results"
    export OCTOPUS_TANGLE_REVIEW_TARGET="$workspace/input.diff"
    printf 'diff --git a/a b/a\n' > "$OCTOPUS_TANGLE_REVIEW_TARGET"
    _tangle_review_read_pgid() {
        ps -o pgid= -p "$$" | tr -d '[:space:]'
    }
    review_run() {
        : > "$group_dispatch"
        return 0
    }
    trap ':' EXIT
    trap ':' INT
    trap ':' TERM
    before_exit=$(trap -p EXIT)
    before_int=$(trap -p INT)
    before_term=$(trap -p TERM)
    ! tangle_run_context_code_review test "$workspace/context.md" initial &&
        [[ ! -e "$group_dispatch" ]] &&
        [[ "$(trap -p EXIT)" == "$before_exit" ]] &&
        [[ "$(trap -p INT)" == "$before_int" ]] &&
        [[ "$(trap -p TERM)" == "$before_term" ]]
); then
    test_pass
else
    test_fail "review must abort before provider work when capture group verification fails"
fi

test_case "context review preflight requires the cleanup helpers used by signal and exit traps"
workspace=$(make_test_dir workspace-review-cleanup-preflight)
cleanup_preflight_dispatch="$workspace/dispatched"
if (
    export RESULTS_DIR="$workspace/review-results"
    export OCTOPUS_TANGLE_REVIEW_TARGET="$workspace/input.diff"
    mkdir -p "$RESULTS_DIR"
    printf 'diff --git a/a b/a\n' > "$OCTOPUS_TANGLE_REVIEW_TARGET"
    unset -f review_kill_descendants_frozen
    review_run() {
        : > "$cleanup_preflight_dispatch"
        return 0
    }
    ! tangle_run_context_code_review test "$workspace/context.md" initial &&
        [[ ! -e "$cleanup_preflight_dispatch" ]]
); then
    test_pass
else
    test_fail "context review must fail before dispatch when scoped cleanup helpers are unavailable"
fi

test_case "unexpected exit cleanup reaps the capture group and invokes the caller EXIT trap"
exit_handler_marker="$TEST_TMP_DIR/review-exit-handler.marker"
exit_handler_pid_file="$TEST_TMP_DIR/review-exit-handler.pid"
exit_handler_temp="$TEST_TMP_DIR/review-exit-handler.tmp"
set +e
(
    EXIT_HANDLER_MARKER="$exit_handler_marker"
    EXIT_HANDLER_PID_FILE="$exit_handler_pid_file"
    marker="$exit_handler_temp"
    review_log=""
    review_start_gate=""
    _review_claim_dir=""
    _review_retry_claim_dir=""
    artifact_id="exit-handler"
    : > "$marker"
    trap 'printf "%s\n" "$1" > "$EXIT_HANDLER_MARKER"' EXIT
    _review_exit_trap=$(trap -p EXIT)
    trap - EXIT
    set -m
    sleep 30 &
    _review_capture_pid=$!
    _review_capture_pgid=$_review_capture_pid
    set +m
    printf '%s\n' "$_review_capture_pid" > "$EXIT_HANDLER_PID_FILE"
    _tangle_review_handle_exit 37 CALLER_ARGUMENT
)
exit_handler_rc=$?
set -e
exit_handler_pid=$(cat "$exit_handler_pid_file" 2>/dev/null || true)
exit_handler_alive=false
if [[ "$exit_handler_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$exit_handler_pid" 2>/dev/null; then
    exit_handler_alive=true
    kill -KILL "$exit_handler_pid" 2>/dev/null || true
    wait "$exit_handler_pid" 2>/dev/null || true
fi
if [[ "$exit_handler_rc" -eq 37 ]] &&
   [[ "$exit_handler_alive" == false ]] &&
   [[ ! -e "$exit_handler_temp" ]] &&
   [[ "$(cat "$exit_handler_marker" 2>/dev/null || true)" == "CALLER_ARGUMENT" ]]; then
    test_pass
else
    test_fail "exit cleanup must preserve status, reap its group, clean files, and invoke the saved trap (rc=$exit_handler_rc alive=$exit_handler_alive)"
fi

test_case "early context-review failure preserves the caller RETURN trap"
workspace=$(make_test_dir workspace-review-return-trap)
return_trap_results="$workspace/review-results"
mkdir -p "$return_trap_results"
if (
    export RESULTS_DIR="$return_trap_results"
    export OCTOPUS_TANGLE_REVIEW_TARGET="$workspace/input.diff"
    printf 'diff --git a/a b/a\n' > "$OCTOPUS_TANGLE_REVIEW_TARGET"
    _tangle_review_claim_artifact() { return 1; }
    trap ':' RETURN
    before_return=$(trap -p RETURN)
    set +e
    tangle_run_context_code_review test "$workspace/context.md" initial
    return_review_rc=$?
    set -e
    after_return=$(trap -p RETURN)
    [[ "$return_review_rc" -ne 0 ]] && [[ "$after_return" == "$before_return" ]]
); then
    test_pass
else
    test_fail "an early context-review return must not replace the caller RETURN trap"
fi

test_case "scoped cleanup kills a ledgered detached session after its launcher exits"
if command -v perl >/dev/null 2>&1; then
    workspace=$(make_test_dir workspace-review-detached-ledger)
    detached_pid_file="$workspace/pids"
    detached_child_file="$workspace/detached-child.pid"
    perl -MPOSIX -e '
        my $path = shift;
        my $pid = fork();
        defined $pid or exit 126;
        exit 0 if $pid;
        POSIX::setsid() >= 0 or exit 125;
        $SIG{HUP} = "IGNORE";
        $SIG{TERM} = "IGNORE";
        open my $fh, ">", $path or exit 124;
        print {$fh} "$$\n";
        close $fh;
        open STDIN, "<", "/dev/null";
        open STDOUT, ">", "/dev/null";
        open STDERR, ">", "/dev/null";
        while (1) { sleep 30; }
    ' "$detached_child_file"
    detached_child=""
    for _ in $(seq 1 100); do
        detached_child=$(cat "$detached_child_file" 2>/dev/null || true)
        [[ "$detached_child" =~ ^[1-9][0-9]*$ ]] && break
        sleep 0.01
    done
    artifact_id="detached-fixture"
    printf '%s:codex:review-r1-fixture-%s\n' "$detached_child" "$artifact_id" > "$detached_pid_file"
    PID_FILE="$detached_pid_file"
    _tangle_review_kill_scoped_ledger_groups "$artifact_id"
    sleep 0.1
    if [[ "$detached_child" =~ ^[1-9][0-9]*$ ]] && ! review_process_is_running "$detached_child"; then
        test_pass
    else
        [[ "$detached_child" =~ ^[1-9][0-9]*$ ]] && kill -KILL "$detached_child" 2>/dev/null || true
        test_fail "scoped cancellation did not kill the detached process group"
    fi
else
    test_skip "Perl POSIX::setsid is unavailable"
fi

assert_contains "$WORKFLOWS" '_tangle_review_kill_scoped_ledger_groups "${artifact_id:-}"' "TERM handler invokes scoped detached-group cleanup"

test_case "generated review context stays inside the workspace"
workspace=$(make_test_dir workspace-context)
if context_file=$(PROJECT_ROOT="$workspace" tangle_build_develop_review_context \
        "test" "prompt" "context" "subtasks" "/nonexistent-validation" \
        "/nonexistent-snapshot" "initial") &&
   workspace_physical=$(cd "$workspace" && pwd -P) &&
   context_dir_physical=$(cd "$(dirname "$context_file")" && pwd -P) &&
   [[ -f "$context_file" ]] &&
   [[ "$context_dir_physical" == "$workspace_physical/.claude-octopus/results" ]]; then
    test_pass
else
    test_fail "generated context must exist under the physical workspace root"
fi

test_case "logical workspace symlink returns a physical context path"
workspace=$(make_test_dir workspace-physical)
workspace_link="$TEST_TMP_DIR/workspace-logical-link"
rm -f "$workspace_link"
ln -s "$workspace" "$workspace_link"
if context_file=$(PROJECT_ROOT="$workspace_link" tangle_build_develop_review_context \
        "test" "prompt" "context" "subtasks" "/nonexistent-validation" \
        "/nonexistent-snapshot" "initial") &&
   workspace_physical=$(cd "$workspace" && pwd -P) &&
   [[ "$context_file" == "$workspace_physical/.claude-octopus/results/develop-review-context-test-initial.md" ]] &&
   [[ -f "$context_file" ]]; then
    test_pass
else
    test_fail "returned context path must use the validated physical workspace"
fi

test_case "symlinked review results directory is rejected"
workspace=$(make_test_dir workspace-symlink)
outside=$(make_test_dir outside-symlink)
mkdir -p "$workspace/.claude-octopus"
ln -s "$outside" "$workspace/.claude-octopus/results"
if ! PROJECT_ROOT="$workspace" tangle_build_develop_review_context \
        "test" "prompt" "context" "subtasks" "/nonexistent-validation" \
        "/nonexistent-snapshot" "initial" >/dev/null 2>&1 &&
   [[ -z "$(find "$outside" -mindepth 1 -print -quit)" ]]; then
    test_pass
else
    test_fail "symlinked results directory must fail without writing outside the workspace"
fi

test_case "external results override cannot redirect review context"
workspace=$(make_test_dir workspace-override)
outside=$(make_test_dir outside-override)
if context_file=$(PROJECT_ROOT="$workspace" RESULTS_DIR="$outside" \
        tangle_build_develop_review_context "test" "prompt" "context" "subtasks" \
        "/nonexistent-validation" "/nonexistent-snapshot" "initial") &&
   workspace_physical=$(cd "$workspace" && pwd -P) &&
   context_dir_physical=$(cd "$(dirname "$context_file")" && pwd -P) &&
   [[ -f "$context_file" ]] &&
   [[ "$context_dir_physical" == "$workspace_physical/.claude-octopus/results" ]] &&
   [[ -z "$(find "$outside" -mindepth 1 -print -quit)" ]]; then
    test_pass
else
    test_fail "review context must ignore external RESULTS_DIR paths"
fi

test_case "review context artifacts do not pollute git status"
workspace=$(make_test_dir workspace-git-clean)
git -C "$workspace" init -q
if context_file=$(PROJECT_ROOT="$workspace" tangle_build_develop_review_context \
        "test" "prompt" "context" "subtasks" "/nonexistent-validation" \
        "/nonexistent-snapshot" "initial") &&
   [[ -f "$context_file" ]] &&
   [[ -z "$(git -C "$workspace" status --porcelain)" ]]; then
    test_pass
else
    test_fail "workspace-local review artifacts must remain git-ignored"
fi

test_case "existing repository-managed ignore file is preserved"
workspace=$(make_test_dir workspace-existing-ignore)
git -C "$workspace" init -q
mkdir -p "$workspace/.claude-octopus/results"
printf 'develop-review-context-*.md\n.develop-review-context.*\n' > "$workspace/.claude-octopus/results/.gitignore"
git -C "$workspace" add -f .claude-octopus/results/.gitignore
ignore_before=$(git -C "$workspace" hash-object .claude-octopus/results/.gitignore)
if context_file=$(PROJECT_ROOT="$workspace" tangle_build_develop_review_context \
        "test" "prompt" "context" "subtasks" "/nonexistent-validation" \
        "/nonexistent-snapshot" "initial") &&
   ignore_after=$(git -C "$workspace" hash-object .claude-octopus/results/.gitignore) &&
   [[ "$ignore_before" == "$ignore_after" ]] &&
   git -C "$workspace" diff --quiet -- .claude-octopus/results/.gitignore &&
   [[ -f "$context_file" ]]; then
    test_pass
else
    test_fail "existing repository-managed ignore rules must remain unchanged"
fi

test_case "repository ignore rules must cover scratch artifacts"
workspace=$(make_test_dir workspace-incomplete-ignore)
git -C "$workspace" init -q
mkdir -p "$workspace/.claude-octopus/results"
printf 'develop-review-context-*.md\n' > "$workspace/.claude-octopus/results/.gitignore"
if ! PROJECT_ROOT="$workspace" tangle_build_develop_review_context \
        "test" "prompt" "context" "subtasks" "/nonexistent-validation" \
        "/nonexistent-snapshot" "initial" >/dev/null 2>&1 &&
   [[ -z "$(find "$workspace/.claude-octopus/results" -type f ! -name .gitignore -print -quit)" ]]; then
    test_pass
else
    test_fail "generation must fail cleanly before creating an unignored scratch file"
fi

test_case "pre-existing context-file symlink is rejected"
workspace=$(make_test_dir workspace-file-symlink)
outside="$TEST_TMP_DIR/outside-file-target"
rm -f "$outside"
printf 'sentinel\n' > "$outside"
mkdir -p "$workspace/.claude-octopus/results"
ln -s "$outside" "$workspace/.claude-octopus/results/develop-review-context-test-initial.md"
if ! PROJECT_ROOT="$workspace" tangle_build_develop_review_context \
        "test" "prompt" "context" "subtasks" "/nonexistent-validation" \
        "/nonexistent-snapshot" "initial" >/dev/null 2>&1 &&
   [[ "$(cat "$outside")" == "sentinel" ]]; then
    test_pass
else
    test_fail "context-file symlinks must fail without modifying their targets"
fi

test_case "unsafe context labels are rejected"
workspace=$(make_test_dir workspace-unsafe-label)
if ! PROJECT_ROOT="$workspace" tangle_build_develop_review_context \
        "../escape" "prompt" "context" "subtasks" "/nonexistent-validation" \
        "/nonexistent-snapshot" "initial" >/dev/null 2>&1 &&
   [[ ! -e "$workspace/.claude-octopus" ]]; then
    test_pass
else
    test_fail "unsafe labels must fail before creating review artifacts"
fi

REVIEW="$PROJECT_ROOT/scripts/lib/review.sh"
assert_contains "$REVIEW" "\"warning\":\"No changes found to review\"" "review no-diff writes warning"
assert_contains "$REVIEW" "return 1" "review no-diff returns non-zero"

QUALITY="$PROJECT_ROOT/scripts/lib/quality.sh"
assert_contains "$QUALITY" "OCTOPUS_DESIGN_REVIEW_TIMEOUT:-0" "design review uses no wall timeout by default"
assert_contains "$QUALITY" "_design_timeout_label" "design review reports effective timeout label"

HEARTBEAT="$PROJECT_ROOT/scripts/lib/heartbeat.sh"
assert_contains "$HEARTBEAT" "timeout_secs=0 means no absolute timeout" "timeout zero disables absolute timeout"
SPAWN="$PROJECT_ROOT/scripts/lib/spawn.sh"
assert_contains "$SPAWN" "TIMEOUT=0 remains" "spawn respects TIMEOUT=0"
assert_contains "$SPAWN" 'octopus_effective_agent_timeout "${TIMEOUT:-0}"' "all providers use the supervised workflow timeout"

TESTING="$PROJECT_ROOT/scripts/lib/testing.sh"
assert_contains "$TESTING" "OCTOPUS_TANGLE_VALIDATION_CORRECTION_FILE" "post-correction validation overlay is wired"
assert_contains "$TESTING" "Static Subtask Rate Before Correction Overlay" "post-correction validation reports static subtask rate"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_VALIDATION_CORRECTION_CHANGED" "correction loop passes validation overlay context"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS" "correction loop has convergence guard"
assert_contains "$WORKFLOWS" "tangle_review_blocking_count" "review blocking count helper exists"
assert_contains "$WORKFLOWS" "fail closed" "malformed review findings fail closed"
assert_contains "$WORKFLOWS" "OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED" "unbounded agent calls document external supervision"
assert_contains "$WORKFLOWS" "stat -f '%z'" "correction progress size uses BSD stat fallback"
assert_contains "$WORKFLOWS" "defaulting to 1 round" "bounded correction mode has implicit cap"
assert_contains "$WORKFLOWS" "tangle_process_is_active_non_zombie" "tangle watcher treats zombies as terminal"
assert_contains "$WORKFLOWS" "exited or became zombie without completion marker" "tangle watcher logs zombie missing-marker grace"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_CONVERGENCE_VALIDATION_PROGRESS" "convergence guard does not treat validation rerenders as progress by default"
assert_contains "$WORKFLOWS" "validation signature changed but blocker best did not improve" "convergence guard logs ignored validation-only movement"
assert_contains "$WORKFLOWS" "interrupted-partial" "correction loop stops on interrupted partial writes"
assert_contains "$WORKFLOWS" "rc=" "interrupted correction logs provider exit code"

test_summary
