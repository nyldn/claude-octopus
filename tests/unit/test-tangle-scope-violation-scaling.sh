#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_SRC="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle write-scope pre-gate scaling"

mkdir -p "$TEST_TMP_DIR"
PATHS_FILE="$TEST_TMP_DIR/store-paths.txt"
PATH_COUNT=10000
TIME_LIMIT_SECONDS=30
awk -v count="$PATH_COUNT" 'BEGIN {
    for (i = 0; i < count; i++) printf ".pnpm-store/v10/files/%02x/%040d-index.json\n", i % 256, i
}' > "$PATHS_FILE"

test_case "the pre-gate collects ${PATH_COUNT} out-of-scope paths within ${TIME_LIMIT_SECONDS}s and keeps every one"
if (
    source "$PROJECT_ROOT_SRC/scripts/lib/testing.sh"
    source "$PROJECT_ROOT_SRC/scripts/lib/workflows.sh"
    unset OCTOPUS_TANGLE_WRITE_SCOPE_MODE
    log() { :; }
    validate_tangle_results() { : > "$TEST_TMP_DIR/base-validation-called"; }
    tangle_changed_paths_outside_write_scopes() { cat "$PATHS_FILE"; }
    RESULTS_DIR="$TEST_TMP_DIR/results"
    expected=$(cat "$PATHS_FILE")
    rc=0
    start=$SECONDS
    tangle_validate_results_with_scope_contract scaling 'Edit app' "$TEST_TMP_DIR/before.txt" \
        '1. [CODING] Edit app — Files: src/app.ts — Task: edit the declared file.' 2>/dev/null || rc=$?
    elapsed=$((SECONDS - start))
    printf '%s\n' "$elapsed" > "$TEST_TMP_DIR/elapsed"
    [[ "$rc" -ne 0 && ! -e "$TEST_TMP_DIR/base-validation-called" ]] &&
        [[ "$elapsed" -lt "$TIME_LIMIT_SECONDS" ]] &&
        [[ "$TANGLE_SCOPE_CONTRACT_VIOLATIONS" == "$expected" ]]
); then
    test_pass
else
    test_fail "pre-gate took $(cat "$TEST_TMP_DIR/elapsed" 2>/dev/null || echo '?')s or lost paths"
fi

test_summary
