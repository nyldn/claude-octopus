#!/usr/bin/env bash
set -euo pipefail

# Regression tests for the RUNTIME-effective synthesis path.
#
# orchestrate.sh sources scripts/lib/parallel.sh and then scripts/lib/heuristics.sh,
# and BOTH define aggregate_results(). Because heuristics.sh is sourced last, its
# copy wins at runtime — so the parallel.sh agy fix (#538) was shadowed and the
# probe/parallel synthesis still routed to the bare gemini CLI. These tests pin
# the heuristics.sh copy (aggregate_results + synthesize_probe_results) to the
# agy-capable run_agent_sync path and prove the runtime-effective routing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "agy is the runtime synthesizer in heuristics.sh (parallel.sh aggregate_results is shadowed)"

HEUR_LIB="$PROJECT_ROOT/scripts/lib/heuristics.sh"
PARALLEL_LIB="$PROJECT_ROOT/scripts/lib/parallel.sh"
ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Static assertions
# ─────────────────────────────────────────────────────────────────────────────

test_heuristics_is_sourced_after_parallel() {
    test_case "orchestrate.sh sources heuristics.sh after parallel.sh (heuristics aggregate_results wins)"
    local p_line h_line
    p_line=$(grep -n 'source .*lib/parallel\.sh' "$ORCH" | head -1 | cut -d: -f1)
    h_line=$(grep -n 'source .*lib/heuristics\.sh' "$ORCH" | head -1 | cut -d: -f1)
    if [[ -n "$p_line" && -n "$h_line" && "$h_line" -gt "$p_line" ]]; then
        test_pass
    else
        test_fail "expected heuristics.sh sourced after parallel.sh (parallel=$p_line heuristics=$h_line)"
    fi
}

test_heuristics_no_bare_gemini_synthesis() {
    test_case "heuristics.sh aggregate_results/synthesize_probe_results no longer dispatch the bare gemini CLI"
    if grep -Eq 'run_with_timeout +"\$TIMEOUT" +gemini|run_agent_sync +"gemini"' "$HEUR_LIB"; then
        test_fail "stale gemini synthesis dispatch still present in heuristics.sh"
    else
        test_pass
    fi
}

test_both_aggregate_results_route_agy() {
    test_case "both aggregate_results copies route synthesis through run_agent_sync (shadow is harmless)"
    # Whichever copy wins at runtime, neither may pipe synthesis to a bare gemini.
    if grep -q 'run_agent_sync "\$synth_agent"' "$HEUR_LIB" \
       && grep -q 'run_agent_sync "\$synth_agent"' "$PARALLEL_LIB"; then
        test_pass
    else
        test_fail "one of the aggregate_results copies does not route through run_agent_sync"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Functional: source BOTH libs in runtime order, then drive aggregate_results.
# The active definition is heuristics.sh's; _aggregate_pick_synth_agent comes
# from parallel.sh (sourced first), exactly as at runtime.
# ─────────────────────────────────────────────────────────────────────────────

_run_runtime_aggregate() {
    # $1 = "agy" (fake agy present) or "none"
    local mode="$1" workdir hbin
    workdir=$(mktemp -d "${TEST_TMP_DIR}/wd.XXXXXX")
    hbin="$workdir/hbin"; mkdir -p "$hbin" "$workdir/results"
    [[ "$mode" == "agy" ]] && { printf '#!/bin/sh\necho agy\n' > "$hbin/agy"; chmod +x "$hbin/agy"; }
    printf 'Result A\n' > "$workdir/results/codex-probe-1.md"
    printf 'Result B\n' > "$workdir/results/agy-probe-2.md"

    # Prepend the fake CLI dir; keep the real PATH so coreutils resolve. agy is
    # checked first by the picker, so the choice is deterministic regardless of
    # whether the host has gemini.
    PROJECT_ROOT="$PROJECT_ROOT" WORKDIR="$workdir" HBIN="$hbin" MODE="$mode" bash -c '
        set -uo pipefail
        export PATH="$HBIN:$PATH"
        RESULTS_DIR="$WORKDIR/results"; DRY_RUN=false; TIMEOUT=30; GREEN=""; NC=""
        source "$PROJECT_ROOT/scripts/lib/parallel.sh"
        source "$PROJECT_ROOT/scripts/lib/heuristics.sh"   # runtime order: this wins
        # Stub deps after sourcing so our versions win (functions resolve at call time)
        log() { :; }
        guard_output() { :; }
        probe_result_file_is_usable() { return 0; }
        rank_results_by_signals() { printf "%s\n%s\n" "$RESULTS_DIR/codex-probe-1.md" "$RESULTS_DIR/agy-probe-2.md"; }
        score_result_file() { echo 80; }
        run_agent_sync() { echo "SYNTH_AGENT=$1" >> "$WORKDIR/agent.log"; echo "SYNTH BODY via $1"; }
        aggregate_results >/dev/null 2>&1
        echo "=== AGG ==="; cat "$RESULTS_DIR"/aggregate-*.md 2>/dev/null || true
        echo "=== LOG ==="; cat "$WORKDIR/agent.log" 2>/dev/null || true
    '
    rm -rf "$workdir"
}

test_runtime_aggregate_synthesizes_via_agy() {
    test_case "runtime aggregate_results (heuristics.sh) synthesizes via agy, not concatenation"
    local out; out="$(_run_runtime_aggregate agy)"
    if [[ "$out" == *"Synthesized Results"* ]] \
       && [[ "$out" == *"Synthesizer: agy"* ]] \
       && [[ "$out" == *"SYNTH_AGENT=agy"* ]] \
       && [[ "$out" != *"Aggregated Results"* ]]; then
        test_pass
    else
        test_fail "expected runtime synthesis via agy, got:\n$out"
    fi
}

test_heuristics_is_sourced_after_parallel
test_heuristics_no_bare_gemini_synthesis
test_both_aggregate_results_route_agy
test_runtime_aggregate_synthesizes_via_agy

test_summary
