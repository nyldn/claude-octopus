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
    grep -qE -- "^[[:space:]]*--${cat}\)" "$RUNNER" && continue
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

test_case "the unit matrix keeps full coverage in two bounded macOS shards"
unit_timeout_setting="$(awk '
    /^  unit:/ { in_unit = 1; next }
    in_unit && /^  [[:alnum:]_-]+:/ { exit }
    in_unit && /^    timeout-minutes:[[:space:]]/ {
        sub(/^    timeout-minutes:[[:space:]]*/, "")
        print
        exit
    }
' "$WORKFLOW")"
macos_entry_count="$(awk '
    /^  unit:/ { in_unit = 1; next }
    in_unit && /^  [[:alnum:]_-]+:/ { exit }
    in_unit && /^[[:space:]]+- os:[[:space:]]+macos-latest[[:space:]]*$/ { count++ }
    END { print count + 0 }
' "$WORKFLOW")"
macos_timeout_count="$(awk '
    /^  unit:/ { in_unit = 1; next }
    in_unit && /^  [[:alnum:]_-]+:/ { exit }
    in_unit && /^[[:space:]]+- os:[[:space:]]+macos-latest[[:space:]]*$/ { in_macos = 1; next }
    in_macos && /^[[:space:]]+- os:/ { in_macos = 0 }
    in_macos && /^[[:space:]]+timeout_minutes:[[:space:]]+45[[:space:]]*$/ { count++ }
    END { print count + 0 }
' "$WORKFLOW")"
macos_shard_indexes="$(awk '
    /^  unit:/ { in_unit = 1; next }
    in_unit && /^  [[:alnum:]_-]+:/ { exit }
    in_unit && /^[[:space:]]+- os:[[:space:]]+macos-latest[[:space:]]*$/ { in_macos = 1; next }
    in_macos && /^[[:space:]]+- os:/ { in_macos = 0 }
    in_macos && /^[[:space:]]+shard_index:[[:space:]]/ { print $2 }
' "$WORKFLOW" | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//')"
macos_shard_count_rows="$(awk '
    /^  unit:/ { in_unit = 1; next }
    in_unit && /^  [[:alnum:]_-]+:/ { exit }
    in_unit && /^[[:space:]]+- os:[[:space:]]+macos-latest[[:space:]]*$/ { in_macos = 1; next }
    in_macos && /^[[:space:]]+- os:/ { in_macos = 0 }
    in_macos && /^[[:space:]]+shard_count:[[:space:]]+2[[:space:]]*$/ { count++ }
    END { print count + 0 }
' "$WORKFLOW")"
ubuntu_timeout_minutes="$(awk '
    /^  unit:/ { in_unit = 1; next }
    in_unit && /^  [[:alnum:]_-]+:/ { exit }
    in_unit && /^[[:space:]]+- os:[[:space:]]+ubuntu-latest[[:space:]]*$/ { in_ubuntu = 1; next }
    in_ubuntu && /^[[:space:]]+- os:/ { exit }
    in_ubuntu && /^[[:space:]]+timeout_minutes:[[:space:]]/ { print $2; exit }
' "$WORKFLOW")"
if [[ "$unit_timeout_setting" == '${{ matrix.timeout_minutes }}' ]] \
   && [[ "$macos_entry_count" == "2" ]] \
   && [[ "$macos_timeout_count" == "2" ]] \
   && [[ "$macos_shard_indexes" == "0,1" ]] \
   && [[ "$macos_shard_count_rows" == "2" ]] \
   && [[ "$ubuntu_timeout_minutes" == "25" ]] \
   && grep -Fq -- '--shard-index=${{ matrix.shard_index }} --shard-count=${{ matrix.shard_count }}' "$WORKFLOW"; then
    test_pass
else
    test_fail "unit matrix must be one full Ubuntu run plus deterministic macOS shards 0 and 1 of 2 with 45-minute bounds"
fi

test_case "required Unit Tests aggregates the symlink lane"
symlink_job="$(awk '
    /^  symlinked-path:/ { in_job = 1 }
    in_job && /^  [[:alnum:]_-]+:/ && $0 !~ /^  symlinked-path:/ { exit }
    in_job { print }
' "$WORKFLOW")"
if grep -Fq 'needs: [classify-changes, unit, symlinked-path]' "$WORKFLOW" &&
   grep -Fq 'needs.symlinked-path.result' "$WORKFLOW" &&
   [[ "$symlink_job" == *'GITHUB_EVENT_NAME: ${{ github.event_name }}'* ]] &&
   [[ "$symlink_job" == *'if [[ "$GITHUB_EVENT_NAME" == "pull_request" ]]; then'* ]] &&
   [[ "$symlink_job" == *'make test-symlink-sensitive'* ]] &&
   [[ "$symlink_job" == *'else'* ]] &&
   [[ "$symlink_job" == *'make test-unit'* ]] &&
   [[ "$symlink_job" == *'logical and physical paths match'* ]]; then
    test_pass
else
    test_fail "the required Unit Tests check must include targeted PR symlink coverage and the full non-PR symlink gate"
fi

test_case "manual workflows run the heavy integration lane"
integration_job="$(awk '
    /^  integration-heavy:/ { in_job = 1 }
    in_job && /^  [[:alnum:]_-]+:/ && $0 !~ /^  integration-heavy:/ { exit }
    in_job { print }
' "$WORKFLOW")"
if grep -Fq "github.event_name == 'workflow_dispatch'" <<< "$integration_job"; then
    test_pass
else
    test_fail "workflow_dispatch selects heavy tests but skips integration-heavy"
fi

test_case "at least one test is actually discovered (guards a silent empty set)"
n="$(reachable_files | grep -c . || true)"
if [[ "${n:-0}" -gt 50 ]]; then
    test_pass
else
    test_fail "only ${n} test files discovered — discovery is probably broken, which would make the assertion above vacuous"
fi

test_summary
