#!/usr/bin/env bash
# Every test file must be reachable by a gate that CI actually runs (#752).
#
# tests/run-all-tests.sh defines five categories and its default includes all of
# them, but nothing invokes the default: Makefile:21 and .github/workflows/test.yml
# call test-smoke, test-unit and test-integration individually, each passing a
# single category flag. So the `root` branch never fires, and 37 test files —
# including test-credential-isolation.sh — have never run in any gate (#741).
#
# Relocating those files fixes today. This fixes tomorrow: a file added anywhere
# the CI categories do not reach fails here instead of silently asserting nothing.
#
# Note the discovery rule being mirrored: discover_tests() uses
# `find <dir> -maxdepth 1`, so a nested subdirectory under unit/ is unreachable
# too, not just tests/ root.
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Test suite reachability (#752)"

TESTS_DIR="$PROJECT_ROOT/tests"
RUNNER="$PROJECT_ROOT/tests/run-all-tests.sh"
MAKEFILE="$PROJECT_ROOT/Makefile"

WORKFLOW="$PROJECT_ROOT/.github/workflows/test.yml"

# Derived, not hardcoded: read the make targets CI invokes, then resolve each to
# the runner category its Makefile recipe passes. Adding a `test-root` target and
# a CI step for it therefore widens what counts as reachable automatically, and
# this suite stops reporting those files.
ci_categories() {
    local target cat
    while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        cat=$(awk -v t="^${target}:" '$0 ~ t {f=1} f && /run-all\.sh/ {print $NF; exit}' "$MAKEFILE")
        [[ -n "$cat" ]] && printf '%s\n' "$cat"
    done < <(grep -ohE 'make test-[a-z0-9]+' "$WORKFLOW" 2>/dev/null | awk '{print $2}' | sort -u) | sort -u
}

# Mirror discover_tests(): find <dir> -maxdepth 1 -name 'test-*.sh'
reachable_files() {
    local cat
    while IFS= read -r cat; do
        [[ -n "$cat" ]] || continue
        find "$TESTS_DIR/$cat" -maxdepth 1 -name 'test-*.sh' -type f 2>/dev/null
    done < <(ci_categories)
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
cats="$(ci_categories)"
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
# Follows compat aliases: run-all-tests.sh:124 maps `--e2e` to the integration
# category, so `e2e` is implemented even though no `e2e)` arm exists.
test_case "every category the Makefile invokes resolves to a real runner category"
bad=""
while IFS= read -r cat; do
    [[ -n "$cat" ]] || continue
    grep -qE "^[[:space:]]*${cat}\)" "$RUNNER" && continue
    grep -qE -- "--${cat}\)[[:space:]]*CATEGORIES" "$RUNNER" && continue
    bad="$bad $cat"
done < <(ci_categories)
if [[ -z "$bad" ]]; then
    test_pass
else
    test_fail "Makefile invokes categories the runner does not implement:$bad"
fi

test_case "at least one test is actually discovered (guards a silent empty set)"
n="$(reachable_files | grep -c . || true)"
if [[ "${n:-0}" -gt 50 ]]; then
    test_pass
else
    test_fail "only ${n} test files discovered — discovery is probably broken, which would make the assertion above vacuous"
fi

test_summary
