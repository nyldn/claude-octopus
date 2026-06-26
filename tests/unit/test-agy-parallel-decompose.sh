#!/usr/bin/env bash
set -euo pipefail

# Regression tests for the agy migration of parallel.sh map_reduce/fan_out.
#
# The v9.45.0 agy migration (#524, Gemini CLI sunset 2026-06-18) left Gemini-CLI
# dispatch in the parallel primitives: map_reduce() decomposed tasks with the
# bare `gemini` binary and both fan_out()/map_reduce() defaulted their second
# dispatch seat to `gemini`. When the (sunset) Gemini CLI is absent these paths
# break or skip agy. These tests pin the fix:
#   1. _parallel_google_seat() prefers agy, keeps gemini when still installed,
#      and falls back to claude-sonnet.
#   2. map_reduce() decomposition routes through run_agent_sync (agy), not the
#      bare gemini CLI.
#   3. fan_out()/map_reduce() default pairs prefer agy over gemini.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "agy is the Google seat in parallel.sh map_reduce/fan_out (Gemini CLI sunset 2026-06-18)"

PARALLEL_LIB="$PROJECT_ROOT/scripts/lib/parallel.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Static assertions
# ─────────────────────────────────────────────────────────────────────────────

test_no_bare_gemini_decompose() {
    test_case "map_reduce no longer decomposes with the bare gemini CLI"
    if grep -Eq 'gemini +"\$decompose_prompt"' "$PARALLEL_LIB"; then
        test_fail "stale 'gemini \$decompose_prompt' decomposition still present"
    else
        test_pass
    fi
}

test_decompose_routes_run_agent_sync() {
    test_case "map_reduce decomposition routes through run_agent_sync + _parallel_google_seat"
    if grep -q '_parallel_google_seat' "$PARALLEL_LIB" \
       && grep -q 'run_agent_sync "\$decompose_agent"' "$PARALLEL_LIB"; then
        test_pass
    else
        test_fail "decomposition does not route through run_agent_sync/_parallel_google_seat"
    fi
}

test_default_pairs_use_google_seat() {
    test_case "fan_out and map_reduce default pairs use _parallel_google_seat (not hard-coded gemini)"
    local hits
    hits=$(grep -c 'agents=("codex" "\$(_parallel_google_seat)")' "$PARALLEL_LIB")
    if [[ "$hits" -ge 2 ]] && ! grep -q 'agents=("codex" "gemini")' "$PARALLEL_LIB"; then
        test_pass
    else
        test_fail "expected 2 google-seat default pairs and no hard-coded codex/gemini pair (found $hits)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Unit: _parallel_google_seat preference order (hermetic PATH)
# ─────────────────────────────────────────────────────────────────────────────

_seat_with_clis() {
    # $@ = CLI names to install as fakes on a hermetic PATH; echoes the seat
    local workdir hbin b p cli
    workdir=$(mktemp -d "${TEST_TMP_DIR}/wd.XXXXXX"); hbin="$workdir/hbin"; mkdir -p "$hbin"
    for b in cat basename; do p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$hbin/$b"; done
    for cli in "$@"; do printf '#!/bin/sh\necho ok\n' > "$hbin/$cli"; chmod +x "$hbin/$cli"; done
    PROJECT_ROOT="$PROJECT_ROOT" HBIN="$hbin" bash -c '
        set -euo pipefail
        export PATH="$HBIN"
        source "$PROJECT_ROOT/scripts/lib/parallel.sh"
        _parallel_google_seat
    '
    rm -rf "$workdir"
}

test_seat_prefers_agy() {
    test_case "_parallel_google_seat returns agy when agy is available"
    local out; out="$(_seat_with_clis agy gemini)"
    [[ "$out" == "agy" ]] && test_pass || test_fail "expected agy, got: $out"
}

test_seat_keeps_gemini_when_no_agy() {
    test_case "_parallel_google_seat keeps gemini when agy absent but gemini still installed"
    local out; out="$(_seat_with_clis gemini)"
    [[ "$out" == "gemini" ]] && test_pass || test_fail "expected gemini, got: $out"
}

test_seat_claude_fallback() {
    test_case "_parallel_google_seat falls back to claude-sonnet when neither agy nor gemini present"
    local out; out="$(_seat_with_clis)"
    [[ "$out" == "claude-sonnet" ]] && test_pass || test_fail "expected claude-sonnet, got: $out"
}

# ─────────────────────────────────────────────────────────────────────────────
# Functional: drive map_reduce / fan_out in a hermetic env with a fake agy.
# run_agent_sync and spawn_agent_capture_pid are stubbed to record which agent
# each path selected; the bare gemini CLI is deliberately absent from PATH.
# ─────────────────────────────────────────────────────────────────────────────

test_mapreduce_decomposes_via_agy() {
    test_case "map_reduce decomposes via run_agent_sync(agy) and seats agy in the subtask rotation"
    local workdir hbin b p out
    workdir=$(mktemp -d "${TEST_TMP_DIR}/wd.XXXXXX"); hbin="$workdir/hbin"; mkdir -p "$hbin" "$workdir/results"
    for b in date cat basename rm mkdir sed sleep; do p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$hbin/$b"; done
    printf '#!/bin/sh\necho ok\n' > "$hbin/agy"; chmod +x "$hbin/agy"   # agy present, gemini absent

    out="$(PROJECT_ROOT="$PROJECT_ROOT" WORKDIR="$workdir" HBIN="$hbin" bash -c '
        set -euo pipefail
        export PATH="$HBIN"
        RESULTS_DIR="$WORKDIR/results"; DRY_RUN=false; TIMEOUT=30; CYAN=""; NC=""
        # Source FIRST, then override parallel.sh-defined functions (aggregate_results)
        # plus the cross-lib helpers (log/run_agent_sync/spawn_agent_capture_pid).
        source "$PROJECT_ROOT/scripts/lib/parallel.sh"
        log() { :; }
        aggregate_results() { :; }
        run_agent_sync() { echo "DECOMPOSE_AGENT=$1" >> "$WORKDIR/ras.log"; printf "1. alpha subtask\n2. beta subtask\n"; }
        spawn_agent_capture_pid() { echo "$1" >> "$WORKDIR/spawn.log"; echo 2147480000; }
        map_reduce "build a thing" >/dev/null 2>&1
        echo "=== RAS ==="; cat "$WORKDIR/ras.log" 2>/dev/null || true
        echo "=== SPAWN ==="; cat "$WORKDIR/spawn.log" 2>/dev/null || true
    ')"
    rm -rf "$workdir"

    # Scope the rotation assertion to the SPAWN section only — otherwise the
    # DECOMPOSE_AGENT=agy line in the RAS section would satisfy *"agy"* even if a
    # regression dropped agy from the spawned subtask pair (CodeRabbit, #539).
    local spawn_section="${out##*=== SPAWN ===}"
    if [[ "$out" == *"DECOMPOSE_AGENT=agy"* ]] \
       && [[ "$out" != *"DECOMPOSE_AGENT=gemini"* ]] \
       && [[ "$spawn_section" == *"codex"* ]] && [[ "$spawn_section" == *"agy"* ]] \
       && [[ "$spawn_section" != *"gemini"* ]]; then
        test_pass
    else
        test_fail "expected decomposition via agy + agy in subtask rotation, got:\n$out"
    fi
}

test_fanout_default_pair_prefers_agy() {
    test_case "fan_out default pair is (codex, agy) when no wizard config and agy is available"
    local workdir hbin b p out
    workdir=$(mktemp -d "${TEST_TMP_DIR}/wd.XXXXXX"); hbin="$workdir/hbin"; mkdir -p "$hbin" "$workdir/results"
    for b in date cat basename rm mkdir tr sleep; do p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$hbin/$b"; done
    printf '#!/bin/sh\necho ok\n' > "$hbin/agy"; chmod +x "$hbin/agy"   # agy present, gemini absent

    out="$(PROJECT_ROOT="$PROJECT_ROOT" WORKDIR="$workdir" HBIN="$hbin" bash -c '
        set -euo pipefail
        export PATH="$HBIN"
        RESULTS_DIR="$WORKDIR/results"; DRY_RUN=false; CYAN=""; NC=""
        # Source FIRST, then override _fan_out_agents_from_config (defined in
        # parallel.sh) to force the default-pair path, plus cross-lib stubs.
        source "$PROJECT_ROOT/scripts/lib/parallel.sh"
        log() { :; }
        _fan_out_agents_from_config() { :; }   # force the default-pair path
        spawn_agent_capture_pid() { echo "$1" >> "$WORKDIR/spawn.log"; echo 2147480000; }
        fan_out "do work" >/dev/null 2>&1
        cat "$WORKDIR/spawn.log" 2>/dev/null | tr "\n" " "
    ')"
    rm -rf "$workdir"

    if [[ "$out" == *"codex"* ]] && [[ "$out" == *"agy"* ]] && [[ "$out" != *"gemini"* ]]; then
        test_pass
    else
        test_fail "expected fan_out to spawn (codex, agy), got: $out"
    fi
}

test_no_bare_gemini_decompose
test_decompose_routes_run_agent_sync
test_default_pairs_use_google_seat
test_seat_prefers_agy
test_seat_keeps_gemini_when_no_agy
test_seat_claude_fallback
test_mapreduce_decomposes_via_agy
test_fanout_default_pair_prefers_agy

test_summary
