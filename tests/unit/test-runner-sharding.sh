#!/usr/bin/env bash
# Regression checks for deterministic unit sharding and symlink-sensitive selection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNNER="$PROJECT_ROOT/tests/run-all-tests.sh"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "test runner sharding"

TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
mkdir -p "$TEST_TMP_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

list_suites() {
    /bin/bash "$RUNNER" "$@" --list | sed -n 's/^  - //p'
}

full_list="$TEST_TMP_DIR/full"
shard_zero="$TEST_TMP_DIR/shard-zero"
shard_one="$TEST_TMP_DIR/shard-one"
shard_zero_repeat="$TEST_TMP_DIR/shard-zero-repeat"
union_list="$TEST_TMP_DIR/union"

list_suites --unit > "$full_list"
list_suites --unit --shard-index=0 --shard-count=2 > "$shard_zero"
list_suites --unit --shard-index=1 --shard-count=2 > "$shard_one"
list_suites --unit --shard-index=0 --shard-count=2 > "$shard_zero_repeat"
LC_ALL=C sort -u "$shard_zero" "$shard_one" > "$union_list"

test_case "two deterministic shards are a complete disjoint unit partition"
if cmp -s "$shard_zero" "$shard_zero_repeat" &&
   cmp -s "$full_list" "$union_list" &&
   [[ -z "$(comm -12 "$shard_zero" "$shard_one")" ]]; then
    test_pass
else
    test_fail "unit shard membership is unstable, overlapping, or incomplete"
fi

test_case "each unit shard is non-empty"
if [[ -s "$shard_zero" && -s "$shard_one" ]]; then
    test_pass
else
    test_fail "a configured unit shard selected no suites"
fi

test_case "invalid shard bounds fail closed"
if ! /bin/bash "$RUNNER" --unit --list --shard-count=0 >/dev/null 2>&1 &&
   ! /bin/bash "$RUNNER" --unit --list --shard-index=2 --shard-count=2 >/dev/null 2>&1; then
    test_pass
else
    test_fail "invalid shard count or index was accepted"
fi

test_case "an empty shard or symlink-sensitive subset fails closed"
if ! /bin/bash "$RUNNER" --list --suite=unit/test-runner-sharding.sh --suite=unit/test-suite-reachability.sh --shard-index=2 --shard-count=3 >/dev/null 2>&1 &&
   ! /bin/bash "$RUNNER" --list --suite=unit/test-dispatch-oversize.sh --symlink-sensitive >/dev/null 2>&1; then
    test_pass
else
    test_fail "an empty filtered or sharded selection exited successfully"
fi

test_case "symlink-sensitive selection equals the explicit path-behavior set"
selected_symlink="$TEST_TMP_DIR/selected-symlink"
expected_symlink="$TEST_TMP_DIR/expected-symlink"
list_suites --unit --symlink-sensitive | LC_ALL=C sort > "$selected_symlink"
grep -Ev '^[[:space:]]*(#|$)' "$PROJECT_ROOT/tests/symlink-sensitive.txt" |
    LC_ALL=C sort > "$expected_symlink"
if [[ -s "$selected_symlink" ]] && cmp -s "$selected_symlink" "$expected_symlink"; then
    test_pass
else
    test_fail "symlink-sensitive suite selection is empty or differs from its derivation rule"
fi

test_case "a stale symlink-sensitive allowlist entry fails closed"
stale_symlink_list="$TEST_TMP_DIR/stale-symlink-sensitive.txt"
{
    cat "$PROJECT_ROOT/tests/symlink-sensitive.txt"
    printf '%s\n' 'unit/test-no-longer-present.sh'
} > "$stale_symlink_list"
if ! OCTOPUS_SYMLINK_SUITE_FILE="$stale_symlink_list" \
    /bin/bash "$RUNNER" --unit --symlink-sensitive --list >/dev/null 2>&1; then
    test_pass
else
    test_fail "runner accepted a stale symlink-sensitive suite entry"
fi

test_case "duration weights use deterministic least-loaded assignment"
weights="$TEST_TMP_DIR/weights.tsv"
printf '%s\n' \
    $'unit/test-runner-sharding.sh\t100' \
    $'unit/test-suite-reachability.sh\t60' \
    $'unit/test-dispatch-oversize.sh\t40' \
    $'unit/test-context-budget.sh\t1' > "$weights"
weighted_zero="$TEST_TMP_DIR/weighted-zero"
weighted_one="$TEST_TMP_DIR/weighted-one"
weighted_args=(
    --suite=unit/test-runner-sharding.sh
    --suite=unit/test-suite-reachability.sh
    --suite=unit/test-dispatch-oversize.sh
    --suite=unit/test-context-budget.sh
    --shard-count=2
    --shard-weights="$weights"
)
list_suites "${weighted_args[@]}" --shard-index=0 > "$weighted_zero"
list_suites "${weighted_args[@]}" --shard-index=1 > "$weighted_one"
if grep -Fxq unit/test-runner-sharding.sh "$weighted_zero" &&
   grep -Fxq unit/test-suite-reachability.sh "$weighted_one" &&
   grep -Fxq unit/test-dispatch-oversize.sh "$weighted_one" &&
   grep -Fxq unit/test-context-budget.sh "$weighted_zero"; then
    test_pass
else
    test_fail "weighted shards did not use least-loaded deterministic packing"
fi

test_summary
