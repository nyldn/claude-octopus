#!/usr/bin/env bash
# Every deterministic test file must be reachable by CI. Share category
# discovery with the public issue matrix and retain the legacy-root baseline.
# Nested category directories are not discovered by the runner.
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Test suite reachability (#752)"

TESTS_DIR="$PROJECT_ROOT/tests"
RUNNER="$PROJECT_ROOT/tests/run-all-tests.sh"
MAKEFILE="$PROJECT_ROOT/Makefile"

WORKFLOW="$PROJECT_ROOT/.github/workflows/test.yml"

source "$SCRIPT_DIR/../helpers/ci-coverage.sh"

# Reject workflow references to missing Make targets before category discovery.
makefile_has_target() {
    grep -qE "^${1}:" "$MAKEFILE"
}

# Mirror discover_tests(): find <dir> -maxdepth 1 -name 'test-*.sh'
reachable_files() {
    local cat
    while IFS= read -r cat; do
        [[ -n "$cat" ]] || continue
        find "$TESTS_DIR/$cat" -maxdepth 1 -name 'test-*.sh' -type f 2>/dev/null
    done < <(ci_test_categories "$PROJECT_ROOT")
}

# Two directories are excluded by directory, not filename, so a genuine suite
# added to either would still be reported:
#   helpers/ — test-framework.sh matches the glob but is sourced, not run.
#   live/    — deliberately not run in CI; those suites dispatch real providers
#              and cost money. Their exclusion is a decision, not this gap.
all_files() {
    find "$TESTS_DIR" -name 'test-*.sh' -type f 2>/dev/null \
        | grep -v "^$TESTS_DIR/helpers/" \
        | grep -v "^$TESTS_DIR/live/"
}

test_case "the Makefile names at least one runnable category"
cats="$(ci_test_categories "$PROJECT_ROOT")"
if [[ -n "$cats" ]]; then
    test_pass
else
    test_fail "could not derive any category from the Makefile — this suite cannot judge reachability"
fi

test_case "discover_tests still uses maxdepth 1 (the assumption this suite mirrors)"
if grep -q 'maxdepth 1' "$RUNNER"; then
    test_pass
else
    test_fail "run-all-tests.sh changed its discovery depth; update reachable_files() to match"
fi

# Known debt, recorded rather than ignored. #741 tracks relocating these 34
# files; triaging them is a separate job because some are likely stale (e.g.
# test-model-config-v849.sh names a long-past version). Baselining means this
# suite fails on any NEW unreachable file from today, without blocking on that
# triage — and without landing red, which would make it worthless.
#
# Shrinking the baseline as #741 progresses is the intended direction. The
# no-growth assertion below is what stops the debt increasing meanwhile.
BASELINE="$SCRIPT_DIR/fixtures/unreachable-baseline.txt"

test_case "the unreachable baseline file exists"
if [[ -f "$BASELINE" ]]; then
    test_pass
else
    test_fail "missing $BASELINE — regenerate it, or this suite cannot distinguish known debt from a new gap"
fi

# The assertion that matters: no test file may become unreachable that was not
# already recorded.
test_case "no NEW test file is unreachable by a category CI runs"
unreachable="$(comm -23 <(all_files | sed "s|^$PROJECT_ROOT/||" | sort) <(reachable_files | sed "s|^$PROJECT_ROOT/||" | sort) || true)"
newly="$(comm -23 <(printf '%s\n' "$unreachable" | grep -c . >/dev/null 2>&1 && printf '%s\n' "$unreachable" | sort || true) <(sort "$BASELINE" 2>/dev/null || true) || true)"
count="$(printf '%s' "$newly" | grep -c . || true)"
if [[ "${count:-0}" -eq 0 ]]; then
    test_pass
else
    sample="$(printf '%s\n' "$newly" | head -5 | tr '\n' ' ')"
    test_fail "${count} test file(s) added that no CI gate runs: ${sample}— put them under tests/{smoke,unit,integration}/ or add a Makefile target and CI step"
fi

# Ratchet: the recorded debt must never grow, even if every entry is baselined.
test_case "the unreachable baseline has not grown"
now="$(printf '%s' "$unreachable" | grep -c . || true)"
was="$(grep -c . "$BASELINE" 2>/dev/null || echo 0)"
if [[ "${now:-0}" -le "${was:-0}" ]]; then
    test_pass
else
    test_fail "unreachable count rose from ${was} to ${now} — see #741"
fi

# Guards the derivation itself: if someone points the Makefile at a category the
# runner does not implement, reachability would silently compute as empty.
# A category counts as implemented if the runner has either a bare `<cat>)` arm
# or a `--<cat>) CATEGORIES` flag arm; the flag form is what the real categories
# use. This previously also absorbed the compat aliases (`--e2e` resolving to
# integration, `--performance` to live), which have since been removed because
# each made a category reachable under a second name.
test_case "every category the Makefile invokes resolves to a real runner category"
bad=""
while IFS= read -r cat; do
    [[ -n "$cat" ]] || continue
    grep -qE "^[[:space:]]*${cat}\)" "$RUNNER" && continue
    grep -qE -- "^[[:space:]]*--${cat}\)" "$RUNNER" && continue
    bad="$bad $cat"
done < <(ci_test_categories "$PROJECT_ROOT")
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "Makefile invokes categories the runner does not implement:$bad"
fi

test_case "every 'make test-*' the workflow invokes exists as a Makefile target"
missing_targets=""
while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    makefile_has_target "$target" || missing_targets="$missing_targets $target"
done < <(ci_make_targets "$PROJECT_ROOT")
if [[ -z "$missing_targets" ]]; then
    test_pass
else
    test_fail "workflow calls make target(s) that do not exist:${missing_targets} — CI will die with 'No rule to make target'. Remove the step or restore the target."
fi

# Paired with the above: a target that exists but resolves to no runner
# category is equally broken, just later in the pipeline.
test_case "the workflow invokes at least one make target (guards a silent empty set)"
n_targets="$(ci_make_targets "$PROJECT_ROOT" | grep -c . || true)"
if [[ "${n_targets:-0}" -ge 3 ]]; then
    test_pass
else
    test_fail "found only ${n_targets} 'make test-*' invocations in the workflow — the grep or the workflow changed, so the assertion above would be vacuous"
fi

test_case "at least one test is actually discovered (guards a silent empty set)"
n="$(reachable_files | grep -c . || true)"
if [[ "${n:-0}" -gt 50 ]]; then
    test_pass
else
    test_fail "only ${n} test files discovered — discovery is probably broken, which would make the assertion above vacuous"
fi

test_summary
