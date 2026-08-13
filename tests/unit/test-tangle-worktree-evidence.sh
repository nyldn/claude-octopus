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

test_case "Supabase migration consistency helper is available"
if declare -F tangle_check_supabase_migration_history >/dev/null 2>&1; then
    test_pass
else
    test_fail "tangle_check_supabase_migration_history is missing"
    tangle_check_supabase_migration_history() { return 127; }
fi

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

test_case "runtime-only .claude-octopus changes do not satisfy implementation evidence"
if (
    cd "$REPO_DIR"
    PROJECT_ROOT="$REPO_DIR"
    export PROJECT_ROOT
    rm -f "$RESULTS_DIR"/codex-tangle-evidence-*.md "$RESULTS_DIR"/tangle-validation-evidence-*.md
    snapshot_tangle_worktree_paths > "$RESULTS_DIR/before-runtime-only.txt"
    mkdir -p .claude-octopus
    printf 'runtime\n' > .claude-octopus/state.json
    write_success_result "$RESULTS_DIR/codex-tangle-evidence-runtime-only.md" \
        "Implemented src/app/page.tsx conceptually; runtime metadata changed."
    if RESULTS_DIR="$RESULTS_DIR" validate_tangle_results "evidence-runtime-only" "Implement the app change in src/app/page.tsx" "$RESULTS_DIR/before-runtime-only.txt" >/dev/null 2>&1; then
        exit 1
    fi
    grep -q "Missing Worktree Changes" "$RESULTS_DIR/tangle-validation-evidence-runtime-only.md"
); then
    test_pass
else
    test_fail "runtime-only .claude-octopus change satisfied implementation worktree evidence"
fi

test_case "blocker output with SUCCESS status fails validation"
if (
    cd "$REPO_DIR"
    rm -f "$RESULTS_DIR"/codex-tangle-evidence-*.md "$RESULTS_DIR"/tangle-validation-evidence-*.md
    snapshot_tangle_worktree_paths > "$RESULTS_DIR/before-blocker.txt"
    write_success_result "$RESULTS_DIR/codex-tangle-evidence-blocker.md" \
        "## Blocker Report
Cannot complete the assigned subtask because all shell commands are blocked by Landlock sandbox and no write tools are available."
    if RESULTS_DIR="$RESULTS_DIR" validate_tangle_results "evidence-blocker" "Implement the app change in src/app/page.tsx" "$RESULTS_DIR/before-blocker.txt" >/dev/null 2>&1; then
        exit 1
    fi
    grep -q "Quality Gate: FAILED" "$RESULTS_DIR/tangle-validation-evidence-blocker.md" && \
    grep -q "Failed: 1/1 result files" "$RESULTS_DIR/tangle-validation-evidence-blocker.md"
); then
    test_pass
else
    test_fail "blocker output marked SUCCESS passed validation"
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

test_case "applied Supabase migration missing from disk fails validation"
if (
    cd "$REPO_DIR"
    PROJECT_ROOT="$REPO_DIR"
    export PROJECT_ROOT
    rm -f "$RESULTS_DIR"/codex-tangle-evidence-*.md "$RESULTS_DIR"/tangle-validation-evidence-*.md
    mkdir -p supabase/migrations "$TEST_TMP_DIR/supabase-bin"
    snapshot_tangle_worktree_paths > "$RESULTS_DIR/before-migration-mismatch.txt"
    printf '%s\n' '-- replacement migration' > supabase/migrations/20260813130000_replacement.sql
    cat > "$TEST_TMP_DIR/supabase-bin/supabase" <<'MOCK_SUPABASE'
#!/usr/bin/env bash
if [[ "$*" == "migration list --local" ]]; then
    case "${SUPABASE_LIST_FIXTURE:-mismatch}" in
        aligned)
            printf '%s\n' \
                '        LOCAL      │     REMOTE     │     TIME (UTC)' \
                '  20260813130000   │ 20260813130000 │ 2026-08-13 13:00:00'
            ;;
        empty) : ;;
        *)
            printf '%s\n' \
                '        LOCAL      │     REMOTE     │     TIME (UTC)' \
                '                   │ 20260813120500 │ 2026-08-13 12:05:00' \
                '  20260813130000   │                │ 2026-08-13 13:00:00'
            ;;
    esac
fi
MOCK_SUPABASE
    chmod +x "$TEST_TMP_DIR/supabase-bin/supabase"
    write_success_result "$RESULTS_DIR/codex-tangle-evidence-migration.md" \
        "Added supabase/migrations/20260813130000_replacement.sql and verified the schema."
    if PATH="$TEST_TMP_DIR/supabase-bin:$PATH" RESULTS_DIR="$RESULTS_DIR" \
        validate_tangle_results "evidence-migration" \
        "Implement the database migration" \
        "$RESULTS_DIR/before-migration-mismatch.txt" >/dev/null 2>&1; then
        exit 1
    fi
    grep -q "Migration History: FAILED" "$RESULTS_DIR/tangle-validation-evidence-migration.md" && \
    grep -q "20260813120500" "$RESULTS_DIR/tangle-validation-evidence-migration.md"
); then
    test_pass
else
    test_fail "validation accepted migration history that no longer exists on disk"
fi

test_case "aligned Supabase migration history passes the read-only gate"
if (
    cd "$REPO_DIR"
    PROJECT_ROOT="$REPO_DIR"
    export PROJECT_ROOT
    PATH="$TEST_TMP_DIR/supabase-bin:$PATH"
    SUPABASE_LIST_FIXTURE=aligned
    export PATH SUPABASE_LIST_FIXTURE
    tangle_check_supabase_migration_history \
        "supabase/migrations/20260813130000_replacement.sql" >/dev/null
); then
    test_pass
else
    test_fail "matching local migration history was rejected"
fi

test_case "empty Supabase migration output is not accepted as proof"
if (
    cd "$REPO_DIR"
    PROJECT_ROOT="$REPO_DIR"
    export PROJECT_ROOT
    PATH="$TEST_TMP_DIR/supabase-bin:$PATH"
    SUPABASE_LIST_FIXTURE=empty
    export PATH SUPABASE_LIST_FIXTURE
    ! tangle_check_supabase_migration_history \
        "supabase/migrations/20260813130000_replacement.sql" >/dev/null
); then
    test_pass
else
    test_fail "empty migration history was treated as consistent"
fi

test_case "changed migrations are checked regardless of prompt classification"
if (
    cd "$REPO_DIR"
    PROJECT_ROOT="$REPO_DIR"
    export PROJECT_ROOT
    rm -f "$RESULTS_DIR"/codex-tangle-evidence-*.md "$RESULTS_DIR"/tangle-validation-evidence-*.md
    snapshot_tangle_worktree_paths > "$RESULTS_DIR/before-unclassified-migration.txt"
    printf '%s\n' '-- migration from an unclassified prompt' > supabase/migrations/20260813140000_unclassified.sql
    write_success_result "$RESULTS_DIR/codex-tangle-evidence-unclassified-migration.md" \
        "Assessed database integrity and left a migration artifact."
    if PATH="$TEST_TMP_DIR/supabase-bin:$PATH" RESULTS_DIR="$RESULTS_DIR" \
        validate_tangle_results "evidence-unclassified-migration" \
        "Assess database integrity" \
        "$RESULTS_DIR/before-unclassified-migration.txt" >/dev/null 2>&1; then
        exit 1
    fi
    grep -q "Migration History: FAILED" \
        "$RESULTS_DIR/tangle-validation-evidence-unclassified-migration.md"
); then
    test_pass
else
    test_fail "migration history gate depended on prompt classification instead of the diff"
fi

test_case "explicit unverified-migration override records the skipped gate"
if (
    cd "$REPO_DIR"
    PROJECT_ROOT="$REPO_DIR"
    export PROJECT_ROOT
    rm -f "$RESULTS_DIR"/codex-tangle-evidence-*.md "$RESULTS_DIR"/tangle-validation-evidence-*.md
    snapshot_tangle_worktree_paths > "$RESULTS_DIR/before-unverified-override.txt"
    printf '%s\n' '-- explicitly unverified migration' > supabase/migrations/20260813150000_unverified.sql
    write_success_result "$RESULTS_DIR/codex-tangle-evidence-unverified-override.md" \
        "Added supabase/migrations/20260813150000_unverified.sql."
    PATH="$TEST_TMP_DIR/supabase-bin:$PATH" SUPABASE_LIST_FIXTURE=empty \
        OCTOPUS_TANGLE_ALLOW_UNVERIFIED_MIGRATIONS=true RESULTS_DIR="$RESULTS_DIR" \
        validate_tangle_results "evidence-unverified-override" \
        "Implement supabase/migrations/20260813150000_unverified.sql" \
        "$RESULTS_DIR/before-unverified-override.txt" >/dev/null 2>&1
    grep -q "Migration History: SKIPPED BY EXPLICIT OVERRIDE" \
        "$RESULTS_DIR/tangle-validation-evidence-unverified-override.md"
); then
    test_pass
else
    test_fail "explicit unverified migration override did not bypass and record the unavailable history gate"
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
