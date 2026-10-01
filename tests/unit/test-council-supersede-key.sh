#!/usr/bin/env bash
# Additive --supersede-key runner support: a keyed run supersedes prior runs
# carrying the SAME key in the pool and records a `latest-<slug>` pointer, while
# runs with no key or a different key are left untouched. The caller (sail-cruisey
# #2952) supplies the per-gate key; absent a key this is a complete no-op, so
# CP1/CP2 interleaved in one session pool never cross-supersede.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

# A stray default-providers policy in the caller env makes council_run bail during
# arg validation; neutralise it (and any inherited key) for a deterministic run.
unset OCTOPUS_COUNCIL_DEFAULT_PROVIDERS OCTOPUS_COUNCIL_SUPERSEDE_KEY 2>/dev/null || true

test_suite "Council supersede-key"

_run_keyed() {
    # _run_keyed <pool> <key-or-empty>
    local pool="$1" key="$2" args=(--goal review --depth quick --output-dir "$pool")
    [[ -n "$key" ]] && args+=(--supersede-key "$key")
    OCTOPUS_COUNCIL_FIXTURE=full-success council_run "${args[@]}" "task" >/dev/null 2>&1 || true
}

_latest_run() { ls -1dt "$1"/2*/ 2>/dev/null | head -1; }

test_supersede_key_slug_is_fs_safe() {
    test_case "council_supersede_key_slug sanitizes unsafe characters"
    local slug
    slug="$(council_supersede_key_slug '2921:CP2 /weird')"
    if [[ "$slug" =~ ^[A-Za-z0-9._-]+$ ]]; then test_pass; else test_fail "unsafe slug: $slug"; fi
}

test_flag_and_env_resolution() {
    test_case "--supersede-key flag and OCTOPUS_COUNCIL_SUPERSEDE_KEY env both set the key"
    local via_flag via_env
    ( council_parse_args --supersede-key "k1" "task" >/dev/null 2>&1; printf '%s' "$COUNCIL_SUPERSEDE_KEY" ) > "$TEST_TMP_DIR/flag"
    via_flag="$(cat "$TEST_TMP_DIR/flag")"
    ( OCTOPUS_COUNCIL_SUPERSEDE_KEY="k2" council_reset_defaults; printf '%s' "$COUNCIL_SUPERSEDE_KEY" ) > "$TEST_TMP_DIR/env"
    via_env="$(cat "$TEST_TMP_DIR/env")"
    if [[ "$via_flag" == "k1" && "$via_env" == "k2" ]]; then test_pass; else test_fail "flag=$via_flag env=$via_env (want k1/k2)"; fi
}

test_same_key_supersedes_prior() {
    test_case "a keyed run supersedes the prior same-key run and updates the latest pointer"
    local pool r1 r2 slug
    pool="$(mktemp -d "$TEST_TMP_DIR/pool-same.XXXXXX")"
    _run_keyed "$pool" "2921:CP2"; sleep 1
    r1="$(_latest_run "$pool")"; r1="${r1%/}"
    _run_keyed "$pool" "2921:CP2"; sleep 1
    r2="$(_latest_run "$pool")"; r2="${r2%/}"
    slug="$(council_supersede_key_slug "2921:CP2")"
    if [[ "$r1" != "$r2" ]] \
       && [[ "$(jq -r '.superseded' "$r1/run-status.json")" == "true" ]] \
       && [[ "$(jq -r '.superseded_by' "$r1/run-status.json")" == "$(basename "$r2")" ]] \
       && [[ "$(jq -r '.superseded' "$r2/run-status.json")" == "false" ]] \
       && [[ "$(cat "$pool/latest-$slug" 2>/dev/null)" == "$(basename "$r2")" ]]; then
        test_pass
    else
        test_fail "r1 superseded=$(jq -r '.superseded' "$r1/run-status.json") by=$(jq -r '.superseded_by' "$r1/run-status.json"); pointer=$(cat "$pool/latest-$slug" 2>/dev/null)"
    fi
}

test_different_keys_do_not_cross_supersede() {
    test_case "different keys (CP1 vs CP2) in one pool never supersede each other"
    local pool cp2 cp1
    pool="$(mktemp -d "$TEST_TMP_DIR/pool-mixed.XXXXXX")"
    _run_keyed "$pool" "2921:CP2"; sleep 1
    _run_keyed "$pool" "2921:CP1"; sleep 1
    # Find each round by its key.
    cp2=""; cp1=""
    local d k
    for d in "$pool"/2*/; do
        d="${d%/}"; k="$(jq -r '.supersede_key // empty' "$d/run-status.json" 2>/dev/null)"
        [[ "$k" == "2921:CP2" ]] && cp2="$d"
        [[ "$k" == "2921:CP1" ]] && cp1="$d"
    done
    if [[ -n "$cp2" && -n "$cp1" ]] \
       && [[ "$(jq -r '.superseded' "$cp2/run-status.json")" == "false" ]] \
       && [[ "$(jq -r '.superseded' "$cp1/run-status.json")" == "false" ]] \
       && [[ -f "$pool/latest-$(council_supersede_key_slug "2921:CP2")" ]] \
       && [[ -f "$pool/latest-$(council_supersede_key_slug "2921:CP1")" ]]; then
        test_pass
    else
        test_fail "cp2 superseded=$(jq -r '.superseded' "$cp2/run-status.json" 2>/dev/null) cp1 superseded=$(jq -r '.superseded' "$cp1/run-status.json" 2>/dev/null)"
    fi
}

test_unkeyed_run_is_a_noop() {
    test_case "an unkeyed run writes no latest pointer and no superseded flag (behavior unchanged)"
    local pool run
    pool="$(mktemp -d "$TEST_TMP_DIR/pool-none.XXXXXX")"
    _run_keyed "$pool" ""; sleep 1
    _run_keyed "$pool" ""
    run="$(_latest_run "$pool")"; run="${run%/}"
    if ! ls "$pool"/latest-* >/dev/null 2>&1 \
       && [[ "$(jq -r '.superseded' "$run/run-status.json")" == "false" ]] \
       && [[ "$(jq -r '.supersede_key' "$run/run-status.json")" == "null" ]]; then
        test_pass
    else
        test_fail "unkeyed run left a pointer or superseded flag"
    fi
}

test_summary_carries_supersede_key() {
    test_case "summary.json records the supersede_key"
    local pool run
    pool="$(mktemp -d "$TEST_TMP_DIR/pool-sum.XXXXXX")"
    _run_keyed "$pool" "2921:CP2"
    run="$(_latest_run "$pool")"; run="${run%/}"
    if [[ "$(jq -r '.supersede_key' "$run/summary.json")" == "2921:CP2" ]]; then
        test_pass
    else
        test_fail "summary supersede_key=$(jq -r '.supersede_key' "$run/summary.json" 2>/dev/null)"
    fi
}

source "$PROJECT_ROOT/scripts/lib/council.sh"

test_supersede_key_slug_is_fs_safe
test_flag_and_env_resolution
test_same_key_supersedes_prior
test_different_keys_do_not_cross_supersede
test_unkeyed_run_is_a_noop
test_summary_carries_supersede_key

test_summary
