#!/usr/bin/env bash
# Meta-contract for the recurring public issue families exercised by UAT.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MATRIX="$PROJECT_ROOT/tests/fixtures/reported-issue-patterns.tsv"
LIVE_SUITE="$PROJECT_ROOT/tests/live/test-installed-package-issue-patterns.sh"
RUNNER="$PROJECT_ROOT/tests/run-all.sh"
WORKFLOW="$PROJECT_ROOT/.github/workflows/test.yml"
MAKEFILE="$PROJECT_ROOT/Makefile"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "reported issue pattern coverage"

test_case "the public regression matrix defines all six recurring families"
rows="$(awk -F '\t' '$1 !~ /^#/ && NF {n++} END {print n + 0}' "$MATRIX" 2>/dev/null || echo 0)"
if [[ "$rows" -eq 6 ]]; then
    test_pass
else
    test_fail "expected six issue families, found $rows"
fi

test_case "the matrix covers a broad set of public issue reports"
issue_count="$(awk -F '\t' '$1 !~ /^#/ {print $2}' "$MATRIX" | tr ',' '\n' | sed '/^$/d' | sort -un | wc -l | tr -d ' ')"
if [[ "$issue_count" -ge 80 ]]; then
    test_pass
else
    test_fail "expected at least 80 distinct public issues, found $issue_count"
fi

test_case "every deterministic suite named by the matrix exists and is CI-reachable"
missing=""
ci_suites=""
while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    category="$(awk -v target="$target" '
        $0 ~ "^" target ":" {in_target = 1; next}
        in_target && /^[[:alnum:]_.-]+:/ {exit}
        in_target && /run-all\.sh/ {
            command = $0
            sub(/^.*run-all\.sh[[:space:]]+/, "", command)
            split(command, args, /[[:space:]]+/)
            print args[1]
            exit
        }
    ' "$MAKEFILE")"
    [[ -n "$category" ]] || continue
    ci_suites+="$(bash "$RUNNER" "$category" --list | sed -n 's/^[[:space:]]*- /tests\//p')"$'\n'
done < <(
    sed 's/#.*//' "$WORKFLOW" |
        grep -ohE 'make test-[a-z0-9-]+' |
        awk '{print $2}' |
        sort -u
)
while IFS= read -r suite; do
    [[ -n "$suite" ]] || continue
    if [[ ! -f "$PROJECT_ROOT/$suite" ]]; then
        missing+=" $suite(missing)"
    elif ! grep -Fxq "$suite" <<< "$ci_suites"; then
        missing+=" $suite(not-ci-reachable)"
    fi
done < <(awk -F '\t' '$1 !~ /^#/ {print $3}' "$MATRIX" | tr ',' '\n' | sort -u)
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "invalid deterministic suite references:$missing"
fi

test_case "every installed-package check in the matrix is implemented"
missing=""
while IFS= read -r check; do
    [[ -n "$check" ]] || continue
    if ! grep -Fq "run_case \"$check\"" "$LIVE_SUITE" &&
       ! grep -Fq "CURRENT_CASE=\"$check\"" "$LIVE_SUITE"; then
        missing+=" $check"
    fi
done < <(awk -F '\t' '$1 !~ /^#/ {print $4}' "$MATRIX" | tr ',' '\n' | sort -u)
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "matrix checks missing from live suite:$missing"
fi

test_case "matrix content is limited to public issue IDs and repository paths"
if awk -F '\t' '
    $1 ~ /^#/ || !NF {next}
    $1 !~ /^[a-z0-9-]+$/ {bad=1}
    $2 !~ /^[0-9]+(,[0-9]+)*$/ {bad=1}
    $3 !~ /^tests\/(smoke|unit|integration)\/[^[:space:]]+(,tests\/(smoke|unit|integration)\/[^[:space:]]+)*$/ {bad=1}
    $4 !~ /^[a-z0-9-]+(,[a-z0-9-]+)*$/ {bad=1}
    END {exit bad}
' "$MATRIX"; then
    test_pass
else
    test_fail "matrix contains malformed or non-public fields"
fi

test_case "the installed-package runner stays host-agnostic"
if grep -Eiq '(tailscale|ssh[[:space:]]+[[:alnum:]_.-]+|/Users/[[:alnum:]_-]+|/home/[[:alnum:]_-]+)' "$LIVE_SUITE"; then
    test_fail "live UAT contains a machine, network, or user-specific path"
else
    test_pass
fi

test_summary
