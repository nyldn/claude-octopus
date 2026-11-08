#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "review profile batch parsing"
# Run the parser from review_run in isolation, without provider or credential access.
parser="$(sed -n '/^    local profile_values=()/,/^    artifact_id="/p' "$ROOT/scripts/lib/review.sh")"
[[ -n "$parser" && "$parser" == *'artifact_id="'* ]] || {
    printf '%s\n' 'Review profile parser extraction failed' >&2
    exit 1
}
# The extracted parser reads profile_json and assigns the output variables.
# shellcheck disable=SC2034,SC2154
parse() {
    local profile_json="$1"
    source "$TMP/parser.sh" || return 1
    printf '%s\0' "$target" "$focus" "$provenance" "$autonomy" "$publish" "$debate" "$history" "$context_file" "$context_text" "$context_label" "$artifact_id"
}
TMP="$TEST_TMP_DIR/review-profile"
mkdir -p "$TMP"
printf '%s\n' "$parser" > "$TMP/parser.sh"
test_case "missing and null values preserve all defaults and empty positions"
parse '{"target":null,"contextFile":null,"context_text":null}' > "$TMP/actual"
printf '%s\0' staged correctness,security,architecture,tdd unknown supervised ask auto auto '' '' 'Review context / task contract' '' > "$TMP/expected"
if cmp -s "$TMP/actual" "$TMP/expected"; then test_pass; else test_fail "default field mismatch"; fi
test_case "empty fields, embedded tabs/newlines, model-qualified values and trailing newline semantics"
parse '{"target":"codex:vendor/model","focus":[],"provenance":"","autonomy":"supervised","publish":"never","debate":"off","history":"fresh","context_file":"","contextText":"a\tb\nc\n\n","contextLabel":"x\ny","artifact_id":"test"}' > "$TMP/actual"
printf '%s\0' codex:vendor/model '' '' supervised never off fresh '' $'a\tb\nc' $'x\ny' test > "$TMP/expected"
if cmp -s "$TMP/actual" "$TMP/expected"; then test_pass; else test_fail "string fields changed"; fi
test_case "invalid JSON fails closed"
if parse '{' >/dev/null 2>&1; then test_fail "invalid profile accepted"; else test_pass; fi
test_summary
