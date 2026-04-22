#!/usr/bin/env bash
# Unit tests for scripts/lib/cache-hygiene.sh — stale plugin cache detection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$PROJECT_ROOT/scripts/lib/cache-hygiene.sh"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Cache Hygiene (v9.29.0)"

# Each test gets a fake $HOME so we never touch the real cache.
make_fake_home() {
    local h
    h=$(mktemp -d)
    mkdir -p "$h/.claude/plugins/cache/nyldn-plugins/octo"
    echo "$h"
}

seed_versions() {
    local home="$1"; shift
    local v
    for v in "$@"; do
        mkdir -p "$home/.claude/plugins/cache/nyldn-plugins/octo/$v"
        # write ~1KB so size math has something to chew on
        head -c 1024 /dev/urandom > "$home/.claude/plugins/cache/nyldn-plugins/octo/$v/payload"
    done
}

test_lib_sourceable() {
    test_case "cache-hygiene.sh is readable and syntactically valid"
    [[ -r "$LIB" ]] && bash -n "$LIB" && test_pass || test_fail "lib missing or has syntax errors"
}

test_versions_empty() {
    test_case "octo_cache_versions is empty when no cache exists"
    local fh; fh=$(mktemp -d)  # no octo dir
    local out
    out=$(HOME="$fh" bash -c "source '$LIB'; octo_cache_versions" || true)
    rm -rf "$fh"
    [[ -z "$out" ]] && test_pass || test_fail "expected empty, got: $out"
}

test_versions_sorted() {
    test_case "octo_cache_versions returns versions sorted oldest→newest"
    local fh; fh=$(make_fake_home)
    seed_versions "$fh" 9.10.0 9.2.0 9.28.0
    local out
    out=$(HOME="$fh" bash -c "source '$LIB'; octo_cache_versions" | tr '\n' ',' | sed 's/,$//')
    rm -rf "$fh"
    [[ "$out" == "9.2.0,9.10.0,9.28.0" ]] \
        && test_pass \
        || test_fail "expected 9.2.0,9.10.0,9.28.0 got: $out"
}

test_stale_keeps_default_two() {
    test_case "octo_cache_stale keeps the 2 newest by default"
    local fh; fh=$(make_fake_home)
    seed_versions "$fh" 9.25.0 9.26.0 9.27.0 9.28.0
    local out
    out=$(HOME="$fh" bash -c "source '$LIB'; octo_cache_stale" | tr '\n' ',' | sed 's/,$//')
    rm -rf "$fh"
    [[ "$out" == "9.25.0,9.26.0" ]] \
        && test_pass \
        || test_fail "expected 9.25.0,9.26.0 got: $out"
}

test_stale_respects_keep_env() {
    test_case "OCTOPUS_CACHE_KEEP overrides default keep window"
    local fh; fh=$(make_fake_home)
    seed_versions "$fh" 9.25.0 9.26.0 9.27.0 9.28.0
    local out
    out=$(HOME="$fh" OCTOPUS_CACHE_KEEP=1 bash -c "source '$LIB'; octo_cache_stale" | tr '\n' ',' | sed 's/,$//')
    rm -rf "$fh"
    [[ "$out" == "9.25.0,9.26.0,9.27.0" ]] \
        && test_pass \
        || test_fail "expected 9.25.0,9.26.0,9.27.0 got: $out"
}

test_stale_under_threshold() {
    test_case "octo_cache_stale returns nothing when total ≤ keep"
    local fh; fh=$(make_fake_home)
    seed_versions "$fh" 9.27.0 9.28.0
    local out
    out=$(HOME="$fh" bash -c "source '$LIB'; octo_cache_stale" || true)
    rm -rf "$fh"
    [[ -z "$out" ]] && test_pass || test_fail "expected empty, got: $out"
}

test_active_version_extracted() {
    test_case "octo_cache_active_version reads CLAUDE_PLUGIN_ROOT"
    local out
    out=$(CLAUDE_PLUGIN_ROOT=/some/cache/nyldn-plugins/octo/9.28.0 \
          bash -c "source '$LIB'; octo_cache_active_version")
    [[ "$out" == "9.28.0" ]] \
        && test_pass \
        || test_fail "expected 9.28.0 got: $out"
}

test_clean_skips_active() {
    test_case "octo_cache_clean refuses to delete the active version"
    local fh; fh=$(make_fake_home)
    seed_versions "$fh" 9.25.0 9.26.0 9.27.0 9.28.0
    HOME="$fh" CLAUDE_PLUGIN_ROOT="$fh/.claude/plugins/cache/nyldn-plugins/octo/9.25.0" \
        OCTOPUS_CACHE_KEEP=1 \
        bash -c "source '$LIB'; octo_cache_clean" >/dev/null
    local survivors
    survivors=$(HOME="$fh" bash -c "source '$LIB'; octo_cache_versions" | tr '\n' ',' | sed 's/,$//')
    rm -rf "$fh"
    # active 9.25.0 survives despite being in stale list; 9.28.0 also survives (kept)
    [[ "$survivors" == *"9.25.0"* && "$survivors" == *"9.28.0"* ]] \
        && test_pass \
        || test_fail "active version was deleted, survivors: $survivors"
}

test_clean_removes_stale() {
    test_case "octo_cache_clean removes versions outside the keep window"
    local fh; fh=$(make_fake_home)
    seed_versions "$fh" 9.25.0 9.26.0 9.27.0 9.28.0
    HOME="$fh" bash -c "source '$LIB'; octo_cache_clean" >/dev/null
    local survivors
    survivors=$(HOME="$fh" bash -c "source '$LIB'; octo_cache_versions" | tr '\n' ',' | sed 's/,$//')
    rm -rf "$fh"
    [[ "$survivors" == "9.27.0,9.28.0" ]] \
        && test_pass \
        || test_fail "expected 9.27.0,9.28.0 got: $survivors"
}

test_format_bytes() {
    test_case "octo_cache_format_bytes renders human-readable sizes"
    local out
    out=$(bash -c "source '$LIB'; octo_cache_format_bytes 1048576")
    [[ "$out" == "1.0MB" ]] \
        && test_pass \
        || test_fail "expected 1.0MB got: $out"
}

test_lib_sourceable
test_versions_empty
test_versions_sorted
test_stale_keeps_default_two
test_stale_respects_keep_env
test_stale_under_threshold
test_active_version_extracted
test_clean_skips_active
test_clean_removes_stale
test_format_bytes

test_summary
