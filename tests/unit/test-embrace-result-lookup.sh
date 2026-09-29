#!/usr/bin/env bash
# Embrace looks up phase artifacts in the session RESULTS_DIR. The lookup must
# return the newest match, and must survive a RESULTS_DIR containing a space.
# The previous helper read only its first argument (the alphabetically first,
# which for epoch-stamped names is the oldest) and re-split it unquoted.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "embrace result lookup"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

OLD_EPOCH="1700000000"
NEW_EPOCH="1790000000"

make_results() {
    local dir="$1"
    mkdir -p "$dir"
    touch -t 202601010000 "$dir/probe-synthesis-${OLD_EPOCH}.md"
    touch -t 202609010000 "$dir/probe-synthesis-${NEW_EPOCH}.md"
}

test_case "the newest artifact wins, not the alphabetically first"
plain="$TEST_TMP_DIR/results"
make_results "$plain"
got="$(octo_newest_existing_file "$plain"/probe-synthesis-*.md)"
if [[ "$got" == "$plain/probe-synthesis-${NEW_EPOCH}.md" ]]; then
    test_pass
else
    test_fail "got ${got:-nothing}; expected probe-synthesis-${NEW_EPOCH}.md"
fi

test_case "a RESULTS_DIR containing a space still resolves"
spaced="$TEST_TMP_DIR/results dir"
make_results "$spaced"
got="$(octo_newest_existing_file "$spaced"/probe-synthesis-*.md)"
if [[ "$got" == "$spaced/probe-synthesis-${NEW_EPOCH}.md" ]]; then
    test_pass
else
    test_fail "got ${got:-nothing} for a directory with a space"
fi

test_case "no matching artifact prints nothing and fails"
empty="$TEST_TMP_DIR/empty"
mkdir -p "$empty"
set +e
got="$(octo_newest_existing_file "$empty"/probe-synthesis-*.md)"
rc=$?
set -e
if [[ -z "$got" && "$rc" -ne 0 ]]; then
    test_pass
else
    test_fail "unmatched glob returned '${got}' with rc=$rc"
fi

test_case "the debate gate and the phase lookups share the helper"
workflows_source="$(cat "$PROJECT_ROOT/scripts/lib/workflows.sh")"
if [[ "$workflows_source" == *'context_file=$(octo_newest_existing_file "${RESULTS_DIR}/${artifact_prefix}"*.md)'* ]] && \
   [[ "$workflows_source" != *'ls -t $expected_pattern'* ]] && \
   [[ "$workflows_source" != *'ls -t $pattern'* ]]; then
    test_pass
else
    test_fail "an embrace artifact lookup still expands an unquoted path"
fi

test_summary
