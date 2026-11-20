#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_SRC="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle oversized scope-violation list"

mkdir -p "$TEST_TMP_DIR"
LONG_ENTRIES_FILE="$TEST_TMP_DIR/long-entries.txt"
LONG_ENTRY_COUNT=40
awk -v count="$LONG_ENTRY_COUNT" 'BEGIN {
    filler = sprintf("%060000d", 0)
    for (i = 0; i < count; i++) printf ".pnpm-store/v10/files/%02x/%s-index.json\n", i, filler
}' > "$LONG_ENTRIES_FILE"
FIRST_LONG_ENTRY=$(sed -n 1p "$LONG_ENTRIES_FILE")
LAST_LONG_ENTRY=$(sed -n "${LONG_ENTRY_COUNT}p" "$LONG_ENTRIES_FILE")

STORE_PATHS_FILE="$TEST_TMP_DIR/store-paths.txt"
STORE_PATH_COUNT=31884
awk -v count="$STORE_PATH_COUNT" 'BEGIN {
    for (i = 0; i < count; i++) printf ".pnpm-store/v10/files/%02x/%060d-index.json\n", i % 256, i
}' > "$STORE_PATHS_FILE"
FIRST_STORE_PATH=$(sed -n 1p "$STORE_PATHS_FILE")
TWENTIETH_STORE_PATH=$(sed -n 20p "$STORE_PATHS_FILE")
TWENTY_FIRST_STORE_PATH=$(sed -n 21p "$STORE_PATHS_FILE")

test_case "an oversized out-of-scope list fails the write-scope pre-gate and later commands still run"
if (
    source "$PROJECT_ROOT_SRC/scripts/lib/testing.sh"
    source "$PROJECT_ROOT_SRC/scripts/lib/workflows.sh"
    log() { :; }
    validate_tangle_results() { touch "$TEST_TMP_DIR/base-validation-called"; }
    tangle_changed_paths_outside_write_scopes() { cat "$LONG_ENTRIES_FILE"; }
    RESULTS_DIR="$TEST_TMP_DIR/oversized-results"
    [[ "$(wc -c < "$LONG_ENTRIES_FILE")" -gt 2097152 ]] || exit 1
    rc=0
    tangle_validate_results_with_scope_contract oversized 'Edit app' "$TEST_TMP_DIR/before.txt" \
        '1. [CODING] Edit app — Files: src/app.ts — Task: edit the declared file.' || rc=$?
    [[ "$rc" -ne 0 && ! -e "$TEST_TMP_DIR/base-validation-called" ]] || exit 1
    [[ "$TANGLE_SCOPE_CONTRACT_VIOLATIONS" == "$(cat "$LONG_ENTRIES_FILE")" ]] || exit 1
    [[ "$(declare -p TANGLE_SCOPE_CONTRACT_VIOLATIONS)" != "declare -x"* ]] || exit 1
    /bin/date >/dev/null || exit 1
    mktemp "$TEST_TMP_DIR/after-validation.XXXXXX" >/dev/null || exit 1
    report="$RESULTS_DIR/tangle-validation-oversized.md"
    grep -Fxq '**Status:** FAILED' "$report" &&
        grep -Fxq '**Reason:** deterministic write-scope pre-gate' "$report" &&
        grep -Fxq '#### FAILED: Out-of-Scope Worktree Changes' "$report" &&
        grep -Fxq -- "- $FIRST_LONG_ENTRY" "$report" &&
        grep -Fxq -- "- $LAST_LONG_ENTRY" "$report" &&
        [[ "$(grep -c '^- \.pnpm-store/' "$report")" -eq "$LONG_ENTRY_COUNT" ]]
); then
    test_pass
else
    test_fail "an oversized violation list broke later commands or lost the failed write-scope report"
fi

test_case "an oversized list becomes one scope-contract finding with a bounded detail"
if (
    source "$PROJECT_ROOT_SRC/scripts/lib/testing.sh"
    source "$PROJECT_ROOT_SRC/scripts/lib/workflows.sh"
    findings="$TEST_TMP_DIR/oversized-findings.json"
    printf '%s\n' '{"findings":[]}' > "$findings"
    tangle_ensure_scope_contract_finding "$findings" "$(cat "$STORE_PATHS_FILE")" || exit 1
    jq -e --arg first "$FIRST_STORE_PATH" --arg twentieth "$TWENTIETH_STORE_PATH" \
        --arg excluded "$TWENTY_FIRST_STORE_PATH" --arg remainder " ... and $((STORE_PATH_COUNT - 20)) more" '
        [.findings[] | select(.category == "scope-contract")] as $scope
        | ($scope | length) == 1
          and $scope[0].file == $first
          and ($scope[0].detail | contains($first + " "))
          and ($scope[0].detail | contains($twentieth + $remainder))
          and ($scope[0].detail | contains($excluded) | not)
          and ($scope[0].detail | endswith($remainder))
          and ($scope[0].detail | length) < 4096' "$findings" >/dev/null
); then
    test_pass
else
    test_fail "the scope-contract finding was not written or carried an unbounded detail"
fi

test_case "a short list keeps every entry in the finding detail"
if (
    source "$PROJECT_ROOT_SRC/scripts/lib/testing.sh"
    source "$PROJECT_ROOT_SRC/scripts/lib/workflows.sh"
    findings="$TEST_TMP_DIR/short-findings.json"
    printf '%s\n' '{"findings":[]}' > "$findings"
    tangle_ensure_scope_contract_finding "$findings" $'src/outside.ts\nThe parent-owned scope manifest changed before final validation.' || exit 1
    jq -e '.findings[0].detail == "Implementation changed paths outside the authorized Files:/Creates: write scopes; Reads: is context only: src/outside.ts The parent-owned scope manifest changed before final validation."' "$findings" >/dev/null
); then
    test_pass
else
    test_fail "a short violation list was truncated or reformatted"
fi

test_case "a failed progress snapshot is reported apart from missing worktree progress"
if (
    source "$PROJECT_ROOT_SRC/scripts/lib/testing.sh"
    source "$PROJECT_ROOT_SRC/scripts/lib/workflows.sh"
    state="$TEST_TMP_DIR/before-state.txt"
    printf '%s\n' unchanged > "$state"
    snapshot_tangle_worktree_state() { printf '%s\n' unchanged; }
    rc=0
    tangle_should_attempt_contextual_review 1 "$state" || rc=$?
    [[ "$rc" -eq 1 ]] || exit 1
    mktemp() { return 1; }
    rc=0
    tangle_should_attempt_contextual_review 1 "$state" || rc=$?
    [[ "$rc" -eq 2 ]]
); then
    test_pass
else
    test_fail "a helper failure was indistinguishable from an unchanged worktree"
fi

test_summary
