#!/usr/bin/env bash
# Regression checks for /octo:develop worktree-change validation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle worktree change evidence"

TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
RESULTS_DIR="$TEST_TMP_DIR/tangle-worktree-evidence-results"
REPO_DIR="$TEST_TMP_DIR/tangle-worktree-evidence-repo"
rm -rf "$RESULTS_DIR" "$REPO_DIR"
mkdir -p "$RESULTS_DIR" "$REPO_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

GREEN=""
RED=""
YELLOW=""
DIM=""
NC=""
_BOX_TOP=""
_BOX_BOT=""
QUALITY_THRESHOLD=70
MAX_QUALITY_RETRIES=0
LOOP_UNTIL_APPROVED=false
OCTOPUS_ANTISYCOPHANCY=false

log() { :; }
record_task_metric() { :; }
write_structured_decision() { :; }
evaluate_quality_branch() { echo "proceed"; }
run_file_validation() { :; }
run_agent_sync() { echo "GENUINELY_CLEAN_TEST"; }
get_gate_threshold() { echo 70; }

source "$PROJECT_ROOT/scripts/lib/testing.sh"

write_success_result() {
    local path="$1"
    local body="$2"
    cat > "$path" <<EOF
# Agent: codex
# Task ID: tangle-evidence-0
# Phase: tangle

## Output
$body

## Status: SUCCESS
EOF
}

write_failed_result() {
    local path="$1"
    local body="$2"
    cat > "$path" <<EOF
# Agent: codex
# Task ID: tangle-evidence-0
# Phase: tangle

## Output
$body

## Status: FAILED (Empty output)
EOF
}

git -C "$REPO_DIR" init -q
git -C "$REPO_DIR" config user.email test@example.com
git -C "$REPO_DIR" config user.name "Octopus Test"
printf 'base\n' > "$REPO_DIR/README.md"
git -C "$REPO_DIR" add README.md
git -C "$REPO_DIR" commit -q -m init

test_case "snapshot worktree detection falls back to pwd when PROJECT_ROOT is invalid"
if (
    cd "$REPO_DIR"
    touch fallback.txt
    snapshot_output=$(PROJECT_ROOT="$TEST_TMP_DIR/missing-project-root" snapshot_tangle_worktree_paths)
    rm -f fallback.txt
    [[ "$snapshot_output" == *"fallback.txt"* ]]
); then
    test_pass
else
    test_fail "snapshot_tangle_worktree_paths ignored pwd fallback when PROJECT_ROOT was invalid"
fi

test_case "snapshot fallback resolves to git top-level from a subdirectory"
if (
    cd "$REPO_DIR"
    mkdir -p src/app
    touch root-only.txt
    snapshot_output=$(
        cd src/app
        PROJECT_ROOT="$TEST_TMP_DIR/missing-project-root" snapshot_tangle_worktree_paths
    )
    rm -f root-only.txt
    [[ "$snapshot_output" == *"root-only.txt"* ]]
); then
    test_pass
else
    test_fail "snapshot_tangle_worktree_paths did not resolve fallback to the git top-level"
fi

test_case "snapshot honors existing non-git PROJECT_ROOT instead of unrelated pwd repo"
if (
    cd "$REPO_DIR"
    mkdir -p "$TEST_TMP_DIR/not-a-repo"
    touch unrelated-repo-change.txt
    snapshot_output=$(PROJECT_ROOT="$TEST_TMP_DIR/not-a-repo" snapshot_tangle_worktree_paths)
    rm -f unrelated-repo-change.txt
    [[ -z "$snapshot_output" ]]
); then
    test_pass
else
    test_fail "snapshot_tangle_worktree_paths used cwd repo despite explicit non-git PROJECT_ROOT"
fi

test_case "implementation prompt with no worktree change fails validation"
if (
    cd "$REPO_DIR"
    snapshot_tangle_worktree_paths > "$RESULTS_DIR/before-empty.txt"
    write_success_result "$RESULTS_DIR/codex-tangle-evidence-empty.md" \
        "Implemented src/app/page.tsx conceptually; no files changed."
    if RESULTS_DIR="$RESULTS_DIR" validate_tangle_results "evidence-empty" "Implement the app change in src/app/page.tsx" "$RESULTS_DIR/before-empty.txt" >/dev/null 2>&1; then
        exit 1
    fi
    grep -q "Missing Worktree Changes" "$RESULTS_DIR/tangle-validation-evidence-empty.md"
); then
    test_pass
else
    test_fail "validation passed despite no worktree changes"
fi

test_case "implementation prompt with new worktree path passes validation"
if (
    cd "$REPO_DIR"
    rm -f "$RESULTS_DIR"/codex-tangle-evidence-*.md "$RESULTS_DIR"/tangle-validation-evidence-*.md
    snapshot_tangle_worktree_paths > "$RESULTS_DIR/before-change.txt"
    mkdir -p src/app
    printf 'export default function Page() { return null }\n' > src/app/page.tsx
    write_success_result "$RESULTS_DIR/codex-tangle-evidence-change.md" \
        "Changed src/app/page.tsx and wired the page."
    RESULTS_DIR="$RESULTS_DIR" validate_tangle_results "evidence-change" "Implement the app change in src/app/page.tsx" "$RESULTS_DIR/before-change.txt" >/dev/null 2>&1
    grep -q "src/app/page.tsx" "$RESULTS_DIR/tangle-validation-evidence-change.md"
); then
    test_pass
else
    test_fail "validation failed despite a new worktree path"
fi

test_case "analysis prompt does not require worktree changes"
if (
    cd "$REPO_DIR"
    rm -f "$RESULTS_DIR"/codex-tangle-evidence-*.md "$RESULTS_DIR"/tangle-validation-evidence-*.md
    snapshot_tangle_worktree_paths > "$RESULTS_DIR/before-analysis.txt"
    write_success_result "$RESULTS_DIR/codex-tangle-evidence-analysis.md" \
        "Architecture analysis only."
    RESULTS_DIR="$RESULTS_DIR" validate_tangle_results "evidence-analysis" "Analyze architecture tradeoffs" "$RESULTS_DIR/before-analysis.txt" >/dev/null 2>&1
    grep -q "Not required for this prompt." "$RESULTS_DIR/tangle-validation-evidence-analysis.md"
); then
    test_pass
else
    test_fail "analysis prompt unexpectedly required worktree changes"
fi

test_case "failed quality gate writes validation report before abort"
if (
    cd "$REPO_DIR"
    rm -f "$RESULTS_DIR"/codex-tangle-evidence-*.md "$RESULTS_DIR"/tangle-validation-evidence-*.md
    snapshot_tangle_worktree_paths > "$RESULTS_DIR/before-abort.txt"
    write_failed_result "$RESULTS_DIR/codex-tangle-evidence-abort.md" \
        "Provider produced no usable implementation."
    evaluate_quality_branch() { echo "abort"; }
    if RESULTS_DIR="$RESULTS_DIR" validate_tangle_results "evidence-abort" "Implement the app change in src/app/page.tsx" "$RESULTS_DIR/before-abort.txt" >/dev/null 2>&1; then
        exit 1
    fi
    grep -q "### Quality Gate: FAILED" "$RESULTS_DIR/tangle-validation-evidence-abort.md" && \
    grep -q "Decision Branch: abort" "$RESULTS_DIR/tangle-validation-evidence-abort.md" && \
    grep -q "threshold: 70%" "$RESULTS_DIR/tangle-validation-evidence-abort.md" && \
    grep -q "Failed: 1/1 result files" "$RESULTS_DIR/tangle-validation-evidence-abort.md"
); then
    test_pass
else
    test_fail "abort path did not leave a useful validation report"
fi

test_summary
