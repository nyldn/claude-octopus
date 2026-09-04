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

test_case "symlink-sensitive selection equals the derived path-behavior set"
selected_symlink="$TEST_TMP_DIR/selected-symlink"
expected_symlink="$TEST_TMP_DIR/expected-symlink"
list_suites --unit --symlink-sensitive | LC_ALL=C sort > "$selected_symlink"
grep -Eil 'symlink|pwd -P|realpath|logical.{0,40}physical|physical.{0,40}logical' \
    "$PROJECT_ROOT"/tests/unit/test-*.sh \
    | sed "s#^$PROJECT_ROOT/tests/##" \
    | LC_ALL=C sort > "$expected_symlink"
if [[ -s "$selected_symlink" ]] && cmp -s "$selected_symlink" "$expected_symlink"; then
    test_pass
else
    test_fail "symlink-sensitive suite selection is empty or differs from its derivation rule"
fi

test_summary
