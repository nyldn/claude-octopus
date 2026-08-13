#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle clean Git baseline"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

TEST_ROOT="$TEST_TMP_DIR/tangle-clean-baseline"
REPO="$TEST_ROOT/repo"
mkdir -p "$REPO"

git -C "$REPO" init -q
git -C "$REPO" config user.email octopus-tests@example.invalid
git -C "$REPO" config user.name "Octopus Tests"
printf 'baseline\n' > "$REPO/tracked.txt"
printf 'ignored.log\n' > "$REPO/.gitignore"
git -C "$REPO" add tracked.txt .gitignore
git -C "$REPO" commit -qm baseline

PROJECT_ROOT="$REPO"
LOG_CAPTURE="$TEST_ROOT/log.txt"
log() { printf '%s %s\n' "$1" "$2" >> "$LOG_CAPTURE"; }

test_case "clean repository is accepted"
if tangle_require_clean_git_baseline; then
    test_pass
else
    test_fail "clean repository was rejected"
fi

test_case "tracked modifications are rejected"
printf 'changed\n' >> "$REPO/tracked.txt"
if tangle_require_clean_git_baseline >/dev/null 2>&1; then
    test_fail "tracked modification was accepted"
else
    test_pass
fi
git -C "$REPO" checkout -- tracked.txt

test_case "untracked files are rejected"
printf 'new\n' > "$REPO/untracked.txt"
if tangle_require_clean_git_baseline >/dev/null 2>&1; then
    test_fail "untracked file was accepted"
else
    test_pass
fi
rm -f "$REPO/untracked.txt"

test_case "one explicit untracked context file is accepted"
printf 'implementation brief\n' > "$REPO/SPEC.md"
if tangle_require_clean_git_baseline "$REPO/SPEC.md"; then
    test_pass
else
    test_fail "explicit untracked context file was rejected"
fi

test_case "an unrelated untracked file still blocks an allowed context file"
printf 'unrelated\n' > "$REPO/unrelated.txt"
if tangle_require_clean_git_baseline "$REPO/SPEC.md" >/dev/null 2>&1; then
    test_fail "unrelated dirty path was hidden by the context allowlist"
else
    test_pass
fi
rm -f "$REPO/SPEC.md" "$REPO/unrelated.txt"

test_case "a modified tracked context file is never allowlisted"
printf 'changed tracked input\n' >> "$REPO/tracked.txt"
if tangle_require_clean_git_baseline "$REPO/tracked.txt" >/dev/null 2>&1; then
    test_fail "modified tracked context bypassed the clean baseline"
else
    test_pass
fi
git -C "$REPO" checkout -- tracked.txt

test_case "an untracked context symlink is never allowlisted"
printf 'outside context\n' > "$TEST_ROOT/outside.md"
ln -s "$TEST_ROOT/outside.md" "$REPO/SPEC.md"
if tangle_require_clean_git_baseline "$REPO/SPEC.md" >/dev/null 2>&1; then
    test_fail "symlinked context bypassed the clean baseline"
else
    test_pass
fi
rm -f "$REPO/SPEC.md"


test_case "each blocking status entry is reported"
: > "$LOG_CAPTURE"
printf 'one\n' > "$REPO/untracked-one.txt"
printf 'two\n' > "$REPO/untracked-two.txt"
if tangle_require_clean_git_baseline >/dev/null 2>&1; then
    test_fail "dirty repository was accepted"
elif grep -Fq '?? untracked-one.txt' "$LOG_CAPTURE" \
    && grep -Fq '?? untracked-two.txt' "$LOG_CAPTURE"; then
    test_pass
else
    test_fail "not every blocking status entry was reported"
fi
rm -f "$REPO/untracked-one.txt" "$REPO/untracked-two.txt"

test_case "ignored files do not block the baseline"
printf 'ignored\n' > "$REPO/ignored.log"
if tangle_require_clean_git_baseline; then
    test_pass
else
    test_fail "ignored file blocked the baseline"
fi
rm -f "$REPO/ignored.log"

test_case "non-Git directories are rejected"
PROJECT_ROOT="$TEST_ROOT/not-git"
mkdir -p "$PROJECT_ROOT"
if tangle_require_clean_git_baseline >/dev/null 2>&1; then
    test_fail "non-Git directory was accepted"
else
    test_pass
fi

test_case "orchestrate enables the guard by default"
if grep -Fq 'OCTOPUS_TANGLE_REQUIRE_CLEAN_BASELINE="${OCTOPUS_TANGLE_REQUIRE_CLEAN_BASELINE:-true}"' "$PROJECT_ROOT/../../../../scripts/orchestrate.sh" 2>/dev/null; then
    test_pass
elif grep -Fq 'OCTOPUS_TANGLE_REQUIRE_CLEAN_BASELINE="${OCTOPUS_TANGLE_REQUIRE_CLEAN_BASELINE:-true}"' "$SCRIPT_DIR/../../scripts/orchestrate.sh"; then
    test_pass
else
    test_fail "orchestrate default guard configuration not found"
fi

test_summary
