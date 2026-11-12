#!/usr/bin/env bash
# Regression checks for /octo:develop explicit file coverage validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTING="$PROJECT_ROOT/scripts/lib/testing.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle explicit file coverage"

test_case "testing.sh has valid bash syntax"
if bash -n "$TESTING" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in testing.sh"
fi

# shellcheck source=/dev/null
source "$TESTING"

RED=""
GREEN=""
YELLOW=""
NC=""
_BOX_TOP=""
_BOX_BOT=""
DIM=""
MAX_QUALITY_RETRIES=0
QUALITY_THRESHOLD=75
LOOP_UNTIL_APPROVED=false
CI_MODE=true
OCTOPUS_ANTISYCOPHANCY=false
OCTOPUS_FILE_VALIDATION=false
FAILED_SUBTASKS=""

log() { :; }
record_task_metric() { :; }
write_structured_decision() { :; }
retry_failed_subtasks() { :; }
evaluate_quality_branch() { echo "proceed"; }
get_gate_threshold() { echo "75"; }

TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
RESULTS_DIR="$TEST_TMP_DIR/tangle-file-coverage"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

write_success_result() {
    local file="$1"
    local output="$2"
    cat > "$file" <<EOF
# Agent: codex
# Task ID: tangle-coverage-0
# Role: implementer
# Phase: tangle
# Prompt: Generic implementation slice

## Output
${output}

## Status: SUCCESS
EOF
}

original_prompt="Update src/lib/templates/NA10_HANDLE_SILENCE.ts and src/lib/templates/NA20_REQUEST_MISSING_INFO.ts."

write_success_result "$RESULTS_DIR/codex-tangle-coverage-0.md" \
    "Updated src/lib/templates/NA10_HANDLE_SILENCE.ts and validated tests."

test_case "missing explicit file coverage fails validation"
if validate_tangle_results "coverage" "$original_prompt" >/dev/null 2>&1; then
    test_fail "validation passed even though NA20 was never covered by any tangle output"
else
    report="$(cat "$RESULTS_DIR/tangle-validation-coverage.md")"
    if [[ "$report" == *"Quality Gate: FAILED"* ]] && \
       [[ "$report" == *"Missing Explicit File Coverage"* ]] && \
       [[ "$report" == *"src/lib/templates/NA20_REQUEST_MISSING_INFO.ts"* ]]; then
        test_pass
    else
        test_fail "validation failed without reporting the missing explicit file coverage"
    fi
fi

rm -f "$RESULTS_DIR"/*.md
write_success_result "$RESULTS_DIR/codex-tangle-coverage-0.md" \
    "Updated src/lib/templates/NA10_HANDLE_SILENCE.ts and validated tests."

retry_called=0
retry_failed_subtasks() {
    retry_called=1
    captured_failed_subtasks="$FAILED_SUBTASKS"
    write_success_result "$RESULTS_DIR/codex-tangle-coverage-0.md" \
        "Updated src/lib/templates/NA10_HANDLE_SILENCE.ts and src/lib/templates/NA20_REQUEST_MISSING_INFO.ts."
}
MAX_QUALITY_RETRIES=1

test_case "hard-gate coverage failure retries even when success rate is 100 percent"
if validate_tangle_results "coverage" "$original_prompt" >/dev/null 2>&1; then
    if [[ "$retry_called" -eq 1 ]] && \
       [[ "$captured_failed_subtasks" == *"result:$RESULTS_DIR/codex-tangle-coverage-0.md"* ]]; then
        test_pass
    else
        test_fail "hard gate failure passed without queueing the successful implementer result for retry"
    fi
else
    test_fail "hard gate retry did not recover after retry supplied missing explicit file coverage"
fi

test_case "retry supervision failure aborts validation before another pass"
rm -f "$RESULTS_DIR"/*.md
write_success_result "$RESULTS_DIR/codex-tangle-coverage-0.md" \
    "Updated src/lib/templates/NA10_HANDLE_SILENCE.ts."
retry_called=0
validation_sleeps=0
sleep() { validation_sleeps=$((validation_sleeps + 1)); }
retry_failed_subtasks() {
    retry_called=$((retry_called + 1))
    # A late output must not rescue a failed ownership/cancellation check.
    write_success_result "$RESULTS_DIR/codex-tangle-coverage-0.md" \
        "Updated src/lib/templates/NA10_HANDLE_SILENCE.ts and src/lib/templates/NA20_REQUEST_MISSING_INFO.ts."
    return 71
}
retry_rc=0
validate_tangle_results "coverage" "$original_prompt" >/dev/null 2>&1 || retry_rc=$?
if [[ "$retry_rc" -eq 75 && "$retry_called" -eq 1 && "$validation_sleeps" -eq 0 ]]; then
    test_pass
else
    test_fail "validation continued after retry supervision failed"
fi
unset -f sleep
MAX_QUALITY_RETRIES=0
retry_failed_subtasks() { :; }

rm -f "$RESULTS_DIR"/*.md
write_success_result "$RESULTS_DIR/codex-tangle-coverage-0.md" \
    "Updated src/lib/templates/NA10_HANDLE_SILENCE.ts and validated tests."

test_case "hard-gate coverage failure aborts when retry budget is exhausted"
if validate_tangle_results "coverage" "$original_prompt" >/dev/null 2>&1; then
    test_fail "validation passed despite missing coverage and no retry budget"
else
    report="$(cat "$RESULTS_DIR/tangle-validation-coverage.md")"
    if [[ "$report" == *"Decision Branch: abort"* ]] && \
       [[ "$report" == *"Retry Attempts: 0/0"* ]]; then
        test_pass
    else
        test_fail "hard gate failure did not abort clearly after retry budget was exhausted"
    fi
fi

rm -f "$RESULTS_DIR"/*.md
write_success_result "$RESULTS_DIR/codex-tangle-coverage-0.md" \
    "Updated src/lib/templates/NA10_HANDLE_SILENCE.ts and src/lib/templates/NA20_REQUEST_MISSING_INFO.ts."

test_case "covered explicit files keep validation passing"
if validate_tangle_results "coverage" "$original_prompt" >/dev/null 2>&1; then
    test_pass
else
    test_fail "validation failed even though all explicit files were covered"
fi

test_case "explicit file coverage requires exact file tokens"
missing=$(check_explicit_file_coverage \
    "Update src/foo.ts." \
    "Updated src/foo.tsx and src/foo.ts.bak.")
if [[ "$missing" == *"src/foo.ts"* ]]; then
    test_pass
else
    test_fail "partial filename matches were treated as exact coverage"
fi

test_case "read context is not a required output"
if missing=$(check_explicit_file_coverage 'Read ./SPEC.md. Implement src/main.ts.' 'Implemented src/main.ts.') && [[ -z "$missing" ]]; then test_pass; else test_fail "read context became an output obligation"; fi

test_case "standalone add instructions still require their declared output"
if missing=$(check_explicit_file_coverage 'Add src/new.ts' 'done') && [[ "$missing" == src/new.ts ]]; then test_pass; else test_fail "add instruction lost its output obligation"; fi

test_case "standalone write targets on the next line remain required"
if missing=$(check_explicit_file_coverage $'Read\n./SPEC.md\nUpdate\nsrc/main.ts' 'done') && [[ "$missing" == src/main.ts ]]; then test_pass; else test_fail "multiline instruction lost its target or required the read input"; fi

test_case "read context after a write instruction stays outside output coverage"
if missing=$(check_explicit_file_coverage 'Update src/main.ts. Read ./SPEC.md.' 'Implemented src/main.ts.') && [[ -z "$missing" ]]; then test_pass; else test_fail "following read context became a required output"; fi

for instruction in \
    'Implement read support in src/parser.ts' \
    'Update context handling in src/parser.ts' \
    'Fix input parsing in src/parser.ts' \
    'Add review output to src/parser.ts'; do
    test_case "write instruction retains its target: $instruction"
    if missing=$(check_explicit_file_coverage "$instruction" 'done') && [[ "$missing" == src/parser.ts ]]; then
        test_pass
    else
        test_fail "write instruction lost its target: $instruction"
    fi
done

test_case "bulleted read context stays separate from a write containing a context word"
if missing=$(check_explicit_file_coverage $'- Read ./SPEC.md\n- Implement read support in src/parser.ts' 'done') && [[ "$missing" == src/parser.ts ]]; then test_pass; else test_fail "bullet boundaries lost the target or required context"; fi

test_case "numbered and polite instructions preserve the read boundary"
if missing=$(check_explicit_file_coverage $'1. Please update context handling in src/parser.ts\n2. Read ./SPEC.md' 'done') && [[ "$missing" == src/parser.ts ]]; then test_pass; else test_fail "numbered instruction boundaries changed coverage"; fi

for instruction in 'Update src/parser.ts; read ./SPEC.md' 'Update src/parser.ts;read ./SPEC.md'; do
    test_case "semicolon separates read context from a write target: $instruction"
    if missing=$(check_explicit_file_coverage "$instruction" 'done') && [[ "$missing" == src/parser.ts ]]; then test_pass; else test_fail "semicolon boundary changed coverage"; fi
done

for instruction in \
    'Read ./SPEC.md, then update src/main.ts.' \
    'Read ./SPEC.md and then implement read support in src/main.ts.'; do
    test_case "coordinated instruction requires its output: $instruction"
    if missing=$(check_explicit_file_coverage "$instruction" 'done') && [[ "$missing" == src/main.ts ]]; then
        test_pass
    else
        test_fail "coordinated instruction lost its target: $instruction"
    fi
done

for action in Rename Move; do
    test_case "$action requires source and destination references"
    if missing=$(check_explicit_file_coverage "$action src/old.ts to src/new.ts" 'done') &&
       [[ "$missing" == $'src/new.ts\nsrc/old.ts' ]]; then
        test_pass
    else
        test_fail "$action lost its output obligations"
    fi
done

test_case "standalone parser failure cannot pass as empty coverage"
if (python3() { return 73; }; check_explicit_file_coverage 'Update src/main.ts' 'done') >/dev/null 2>&1; then
    test_fail "unavailable instruction parser passed coverage"
else
    test_pass
fi

for instruction in \
    'Read ./SPEC.md and update src/main.ts.' \
    'Read ./SPEC.md, update src/main.ts' \
    'You should update src/main.ts.' \
    'After reading ./SPEC.md, implement src/main.ts' \
    'Implement parser and read support in src/main.ts'; do
    test_case "ordinary write wording retains its output: $instruction"
    if missing=$(check_explicit_file_coverage "$instruction" 'done') && [[ "$missing" == src/main.ts ]]; then
        test_pass
    else
        test_fail "unexpected required outputs: [$missing]"
    fi
done

test_case "unavailable coverage replaces an earlier successful report"
if (
    check_explicit_file_coverage() { return 73; }
    printf '### Quality Gate: PASSED\n' > "$RESULTS_DIR/tangle-validation-coverage.md"
    if validate_tangle_results coverage 'Update src/main.ts' >/dev/null 2>&1; then exit 1; fi
    grep -q 'Quality Gate: FAILED' "$RESULTS_DIR/tangle-validation-coverage.md" &&
        grep -q 'Unable to verify declared output coverage' "$RESULTS_DIR/tangle-validation-coverage.md" &&
        ! grep -q 'Quality Gate: PASSED' "$RESULTS_DIR/tangle-validation-coverage.md"
); then test_pass; else test_fail "coverage failure left an absent or stale report"; fi

for inherited in absent populated; do
    test_case "empty managed scopes use textual coverage with $inherited inherited scopes"
    if (
        source "$PROJECT_ROOT/scripts/lib/workflows.sh"
        tangle_authorized_write_scopes() { :; }
        tangle_authorized_read_scopes() { :; }
        tangle_changed_paths_outside_write_scopes() { :; }
        tangle_append_write_scope_contract_report() { :; }
        validate_tangle_results() {
            local missing
            missing=$(check_explicit_file_coverage "$2" 'done') || return 1
            [[ "$missing" == src/main.ts && "${TANGLE_REQUIRED_OUTPUT_SCOPES+x}" != x ]]
        }
        unset TANGLE_REQUIRED_OUTPUT_SCOPES
        if [[ "$inherited" == populated ]]; then TANGLE_REQUIRED_OUTPUT_SCOPES=ignored; fi
        tangle_validate_results_with_scope_contract coverage 'Update src/main.ts' '' '1. [CODING] Update the implementation' || exit 1
        if [[ "$inherited" == populated ]]; then [[ "$TANGLE_REQUIRED_OUTPUT_SCOPES" == ignored ]]; fi
    ); then test_pass; else test_fail "empty scopes bypassed coverage or changed caller state"; fi
done

test_case "comma-separated read inputs stay outside the output obligations"
if missing=$(check_explicit_file_coverage 'Read ./SPEC.md, ./DESIGN.md, then update src/main.ts.' 'Updated src/main.ts') && [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "read-only list became required output: [$missing]"
fi

test_case "sequenced read context does not become an output obligation"
if missing=$(check_explicit_file_coverage 'First read ./SPEC.md, then update src/main.ts' 'Updated src/main.ts') && [[ -z "$missing" ]]; then test_pass; else test_fail "sequenced read context became required: [$missing]"; fi

for instruction in 'Read ./SPEC.md to update src/main.ts' 'Read ./SPEC.md;update src/main.ts'; do
    test_case "read-purpose or adjacent sequencing retains the write target: $instruction"
    if missing=$(check_explicit_file_coverage "$instruction" 'done') && [[ "$missing" == src/main.ts ]]; then test_pass; else test_fail "write target was omitted: [$missing]"; fi
done

test_case "managed coverage uses files rather than textual echoes"
mkdir -p "$TEST_TMP_DIR/repo/src"
printf 'implementation\n' > "$TEST_TMP_DIR/repo/src/main.ts"
printf 'documentation\n' > "$TEST_TMP_DIR/repo/README.md"
PROJECT_ROOT="$TEST_TMP_DIR/repo"
TANGLE_REQUIRED_OUTPUT_SCOPES=$'src/main.ts\n./README.md'
if missing=$(check_explicit_file_coverage 'Read ../outside/guide.md' 'done') && [[ -z "$missing" ]]; then test_pass; else test_fail "existing outputs needed textual echoes or external context"; fi

test_case "a missing declared output still fails despite a model claiming it exists"
TANGLE_REQUIRED_OUTPUT_SCOPES=$'src/main.ts\ntests/missing.test.ts'
if [[ "$(check_explicit_file_coverage '' 'Created tests/missing.test.ts')" == 'tests/missing.test.ts' ]]; then test_pass; else test_fail "missing required artifact passed"; fi

test_case "symlinks cannot satisfy output coverage"
ln -s "$TEST_TMP_DIR/repo/src/main.ts" "$TEST_TMP_DIR/repo/link.ts"
TANGLE_REQUIRED_OUTPUT_SCOPES=link.ts
if [[ "$(check_explicit_file_coverage '' '')" == 'link.ts' ]]; then test_pass; else test_fail "symbolic output was accepted"; fi
test_case "empty output directories remain incomplete"
mkdir -p "$TEST_TMP_DIR/repo/empty"
TANGLE_REQUIRED_OUTPUT_SCOPES=empty
if [[ "$(check_explicit_file_coverage '' '')" == 'empty' ]]; then test_pass; else test_fail "empty output directory passed"; fi

test_case "tracked deletions can satisfy a declared edit scope"
git -C "$PROJECT_ROOT" init -q
git -C "$PROJECT_ROOT" -c user.name=Test -c user.email=test@example.com add README.md
git -C "$PROJECT_ROOT" -c user.name=Test -c user.email=test@example.com commit -qm baseline
TANGLE_REQUIRED_OUTPUT_BASELINE=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
rm "$PROJECT_ROOT/README.md"
TANGLE_REQUIRED_OUTPUT_SCOPES=README.md
if missing=$(check_explicit_file_coverage '' '') && [[ -z "$missing" ]]; then test_pass; else test_fail "intentional tracked deletion was rejected"; fi
unset TANGLE_REQUIRED_OUTPUT_SCOPES TANGLE_REQUIRED_OUTPUT_BASELINE PROJECT_ROOT

test_case "managed scopes resolve from the Git root when launched in a package"
PROJECT_ROOT="$TEST_TMP_DIR/deletion-repo"
mkdir -p "$PROJECT_ROOT/pkg" "$PROJECT_ROOT/src/obsolete"
git -C "$PROJECT_ROOT" init -q
printf 'old\n' > "$PROJECT_ROOT/src/old.ts"
printf 'obsolete\n' > "$PROJECT_ROOT/src/obsolete/index.ts"
git -C "$PROJECT_ROOT" add src
git -C "$PROJECT_ROOT" -c user.name=Test -c user.email=test@example.com commit -qm baseline
TANGLE_REQUIRED_OUTPUT_BASELINE=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
printf 'new\n' > "$PROJECT_ROOT/pkg/a.txt"
PROJECT_ROOT="$PROJECT_ROOT/pkg"
TANGLE_REQUIRED_OUTPUT_SCOPES=pkg/a.txt
if missing=$(check_explicit_file_coverage '' '') && [[ -z "$missing" ]]; then test_pass; else test_fail "package root was duplicated in the output path"; fi
PROJECT_ROOT="${PROJECT_ROOT%/pkg}"

test_case "staged renames satisfy both removed and created scopes"
git -C "$PROJECT_ROOT" mv src/old.ts src/new.ts
TANGLE_REQUIRED_OUTPUT_SCOPES=$'src/old.ts\nsrc/new.ts'
if missing=$(check_explicit_file_coverage '' '') && [[ -z "$missing" ]]; then test_pass; else test_fail "rename source was not recognized as removed"; fi

test_case "an intentionally emptied tracked directory satisfies its removal scope"
rm "$PROJECT_ROOT/src/obsolete/index.ts"
TANGLE_REQUIRED_OUTPUT_SCOPES=src/obsolete/
if missing=$(check_explicit_file_coverage '' '') && [[ -z "$missing" ]]; then test_pass; else test_fail "tracked directory removal was rejected"; fi

test_case "a fully removed tracked directory satisfies its removal scope"
rmdir "$PROJECT_ROOT/src/obsolete"
if missing=$(check_explicit_file_coverage '' '') && [[ -z "$missing" ]]; then test_pass; else test_fail "absent removed directory was rejected"; fi

test_case "an uncreated directory has no baseline deletion evidence"
TANGLE_REQUIRED_OUTPUT_SCOPES=src/missing/
if [[ "$(check_explicit_file_coverage '' '')" == src/missing/ ]]; then test_pass; else test_fail "a new missing output passed as a deletion"; fi

test_case "coverage retains previously configured trust for a shared checkout"
real_git=$(command -v git)
if GIT_TEST_ASSUME_DIFFERENT_OWNER=1 "$real_git" -C "$PROJECT_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
    test_skip "Git ownership protection is unavailable or this checkout is already trusted"
else
    # Git's native ownership test switch avoids privileged chown in this fixture.
    mkdir -p "$TEST_TMP_DIR/shared-bin" "$TEST_TMP_DIR/shared-profile/git"
    printf '[safe]\n\tdirectory = %s\n' "$PROJECT_ROOT" > "$TEST_TMP_DIR/shared-profile/git/config"
    cat > "$TEST_TMP_DIR/shared-bin/git" <<'SH'
#!/usr/bin/env bash
GIT_TEST_ASSUME_DIFFERENT_OWNER=1 exec "$COVERAGE_REAL_GIT" "$@"
SH
    chmod 755 "$TEST_TMP_DIR/shared-bin/git"
    TANGLE_REQUIRED_OUTPUT_SCOPES=src/new.ts
    if missing=$(XDG_CONFIG_HOME="$TEST_TMP_DIR/shared-profile" PATH="$TEST_TMP_DIR/shared-bin:$PATH" COVERAGE_REAL_GIT="$real_git" check_explicit_file_coverage '' '') && [[ -z "$missing" ]]; then test_pass; else test_fail "isolated coverage discarded authorized checkout trust"; fi
fi

test_case "an unreadable baseline fails the coverage check rather than returning empty success"
TANGLE_REQUIRED_OUTPUT_BASELINE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
if missing=$(check_explicit_file_coverage '' '' 2>/dev/null); then test_fail "unreadable baseline was accepted"; else test_pass; fi
unset TANGLE_REQUIRED_OUTPUT_SCOPES TANGLE_REQUIRED_OUTPUT_BASELINE PROJECT_ROOT

test_summary
