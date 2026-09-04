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
# The single extractor for "which make targets does CI actually invoke".
#
# Both consumers below read through this rather than each running their own
# grep: two spellings of the same parse is the duplication class this repo keeps
# getting bitten by, and I introduced an instance of it here — one copy matched
# `test-[a-z0-9]+` and the other `test-[a-z0-9-]+`, so a hyphenated target like
# `test-plugin-name` would parse as `test-plugin` in one and correctly in the
# other. They agree today only because no hyphenated target is invoked yet.
#
# Comment lines are stripped first. A commented-out step is not an invocation,
# and treating one as active would either demand a target nobody calls or let a
# deleted step keep satisfying the count guard below.
workflow_make_targets() {
    sed 's/#.*//' "$WORKFLOW" 2>/dev/null \
        | grep -ohE 'make test-[a-z0-9-]+' \
        | awk '{print $2}' | sort -u
}

makefile_has_target() {
    grep -qE "^${1}:" "$MAKEFILE"
}

# Derived, not hardcoded: read the make targets CI invokes, then resolve each to
# the runner category its Makefile recipe passes. Adding a `test-root` target and
# a CI step for it therefore widens what counts as reachable automatically, and
# this suite stops reporting those files.
#
# The awk stops at the next target definition, so a recipe further down the
# Makefile cannot donate its `run-all.sh` line to a target whose own recipe has
# none.
ci_categories() {
    local target cat
    while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        cat=$(awk -v t="^${target}:" '
            $0 ~ t { f = 1; next }
            f && /^[a-zA-Z0-9_.-]+:/ { exit }
            f && /run-all\.sh/ { print $NF; exit }
        ' "$MAKEFILE")
        [[ -n "$cat" ]] && printf '%s\n' "$cat"
    done < <(workflow_make_targets) | sort -u
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
    grep -qE -- "--${cat}\)[[:space:]]*CATEGORIES" "$RUNNER" && continue
    bad="$bad $cat"
done < <(ci_categories)
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
done < <(workflow_make_targets)
if [[ -z "$missing_targets" ]]; then
    test_pass
else
    test_fail "workflow calls make target(s) that do not exist:${missing_targets} — CI will die with 'No rule to make target'. Remove the step or restore the target."
fi

# Paired with the above: a target that exists but resolves to no runner
# category is equally broken, just later in the pipeline.
test_case "the workflow invokes at least one make target (guards a silent empty set)"
n_targets="$(workflow_make_targets | grep -c . || true)"
if [[ "${n_targets:-0}" -ge 3 ]]; then
    test_pass
else
    test_fail "found only ${n_targets} 'make test-*' invocations in the workflow — the grep or the workflow changed, so the assertion above would be vacuous"
fi

test_case "the unit matrix timeout has headroom for slow macOS runners"
unit_timeout_setting="$(awk '
    /^  unit:/ { in_unit = 1; next }
    in_unit && /^  [[:alnum:]_-]+:/ { exit }
    in_unit && /^    timeout-minutes:[[:space:]]/ {
        sub(/^    timeout-minutes:[[:space:]]*/, "")
        print
        exit
    }
' "$WORKFLOW")"
macos_timeout_minutes="$(awk '
    /^  unit:/ { in_unit = 1; next }
    in_unit && /^  [[:alnum:]_-]+:/ { exit }
    in_unit && /^[[:space:]]+- os:[[:space:]]+macos-latest[[:space:]]*$/ { in_macos = 1; next }
    in_macos && /^[[:space:]]+- os:/ { exit }
    in_macos && /^[[:space:]]+timeout_minutes:[[:space:]]/ { print $2; exit }
' "$WORKFLOW")"
ubuntu_timeout_minutes="$(awk '
    /^  unit:/ { in_unit = 1; next }
    in_unit && /^  [[:alnum:]_-]+:/ { exit }
    in_unit && /^[[:space:]]+- os:[[:space:]]+ubuntu-latest[[:space:]]*$/ { in_ubuntu = 1; next }
    in_ubuntu && /^[[:space:]]+- os:/ { exit }
    in_ubuntu && /^[[:space:]]+timeout_minutes:[[:space:]]/ { print $2; exit }
' "$WORKFLOW")"
if [[ "$unit_timeout_setting" == '${{ matrix.timeout_minutes }}' ]] \
   && [[ "$macos_timeout_minutes" =~ ^[0-9]+$ ]] \
   && [[ "$macos_timeout_minutes" -ge 30 ]] \
   && [[ "$ubuntu_timeout_minutes" == "25" ]]; then
    test_pass
else
    test_fail "unit timeout setting is ${unit_timeout_setting:-missing} with macOS=${macos_timeout_minutes:-missing} and Ubuntu=${ubuntu_timeout_minutes:-missing}; run 33899702427 crossed 25 minutes — keep at least 30 minutes of macOS budget without relaxing Ubuntu's 25-minute bound"
fi

test_case "at least one test is actually discovered (guards a silent empty set)"
n="$(reachable_files | grep -c . || true)"
if [[ "${n:-0}" -gt 50 ]]; then
    test_pass
else
    test_fail "only ${n} test files discovered — discovery is probably broken, which would make the assertion above vacuous"
fi

test_summary
