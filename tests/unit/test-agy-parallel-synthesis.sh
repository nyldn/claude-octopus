#!/usr/bin/env bash
set -euo pipefail

# Regression tests for the agy migration in the parallel fan-out aggregator.
#
# The v9.45.0 agy migration (#524) updated the Double-Diamond phase synthesizers
# in workflows.sh but missed scripts/lib/parallel.sh, which hard-coded synthesis
# to the literal `gemini` CLI and degraded to plain concatenation whenever the
# (now sunset, 2026-06-18) Gemini CLI was absent. These tests pin the fix:
#   1. parallel.sh routes synthesis through the agy-capable run_agent_sync
#      abstraction and SELECTS agy (not concatenation) when agy is available.
#   2. embrace.sh get_dispatch_strategy seats agy in the probe/discover fan-out.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "agy is the synthesizer/Google seat in the parallel aggregator (Gemini CLI sunset 2026-06-18)"

PARALLEL_LIB="$PROJECT_ROOT/scripts/lib/parallel.sh"
EMBRACE_LIB="$PROJECT_ROOT/scripts/lib/embrace.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Static assertions
# ─────────────────────────────────────────────────────────────────────────────

test_no_bare_gemini_synthesis_in_parallel() {
    test_case "parallel.sh no longer pipes synthesis to the bare gemini CLI"
    if grep -Eq 'run_with_timeout +"\$TIMEOUT" +gemini' "$PARALLEL_LIB"; then
        test_fail "stale 'run_with_timeout \$TIMEOUT gemini' synthesis still present in parallel.sh"
    else
        test_pass
    fi
}

test_parallel_routes_through_run_agent_sync() {
    test_case "parallel.sh aggregate_results synthesizes via run_agent_sync + agy picker"
    if grep -q '_aggregate_pick_synth_agent' "$PARALLEL_LIB" \
       && grep -q 'run_agent_sync "\$synth_agent"' "$PARALLEL_LIB"; then
        test_pass
    else
        test_fail "parallel.sh does not route synthesis through run_agent_sync/_aggregate_pick_synth_agent"
    fi
}

test_picker_prefers_agy() {
    test_case "_aggregate_pick_synth_agent prefers agy over the claude-sonnet fallback"
    # agy listed before claude-sonnet in the picker body
    local body
    body=$(awk '/^_aggregate_pick_synth_agent\(\)/{f=1} f{print} /^}/{if(f)exit}' "$PARALLEL_LIB")
    if [[ "$body" == *'echo "agy"'* && "$body" == *'echo "claude-sonnet"'* ]] \
       && [[ "$(echo "$body" | grep -n 'echo "agy"' | head -1 | cut -d: -f1)" \
             -lt "$(echo "$body" | grep -n 'echo "claude-sonnet"' | head -1 | cut -d: -f1)" ]]; then
        test_pass
    else
        test_fail "picker does not prefer agy ahead of claude-sonnet"
    fi
}

test_embrace_dispatch_seats_agy() {
    test_case "embrace.sh get_dispatch_strategy detects and seats agy"
    if grep -q 'has_agy=true' "$EMBRACE_LIB" \
       && grep -q 'cli_providers+=(agy)' "$EMBRACE_LIB" \
       && grep -q '"2:agy,claude-sonnet:high"' "$EMBRACE_LIB"; then
        test_pass
    else
        test_fail "get_dispatch_strategy does not seat agy (probe/discover would still skip it)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Functional assertion — drive aggregate_results in a hermetic env
#
# A fresh bash sources parallel.sh, stubs the surrounding lib helpers, and points
# PATH at a temp dir holding ONLY coreutils plus (optionally) a fake `agy`. This
# makes the gemini and claude CLIs deterministically absent regardless of the
# host, so the picker's choice is unambiguous. run_agent_sync is stubbed to log
# which agent synthesis used.
# ─────────────────────────────────────────────────────────────────────────────

_run_aggregate_scenario() {
    # $1 = scenario:
    #   "agy"       install a fake agy CLI (agy synthesizes)
    #   "agy-fails" install fake agy + claude CLIs; the run_agent_sync stub fails
    #              for agy so aggregate_results must retry via claude-sonnet
    #   "none"      install neither (forces concatenation)
    local mode="$1"
    local workdir hbin
    workdir=$(mktemp -d "${TEST_TMP_DIR}/wd.XXXXXX")
    hbin="$workdir/hbin"
    mkdir -p "$hbin" "$workdir/results"

    local b p
    for b in date cat basename rm mkdir ln; do
        p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$hbin/$b"
    done
    if [[ "$mode" == "agy" || "$mode" == "agy-fails" ]]; then
        printf '#!/bin/sh\necho agy-output\n' > "$hbin/agy"
        chmod +x "$hbin/agy"
    fi
    # The claude-sonnet retry branch gates on `command -v claude`; provide it so
    # the agy-failure path can fall through to claude-sonnet.
    if [[ "$mode" == "agy-fails" ]]; then
        printf '#!/bin/sh\necho claude-output\n' > "$hbin/claude"
        chmod +x "$hbin/claude"
    fi
    # Agent whose run_agent_sync stub should fail (empty/non-zero), or empty.
    local fail_agent=""
    [[ "$mode" == "agy-fails" ]] && fail_agent="agy"

    printf 'Result A: problem analysis content\n' > "$workdir/results/codex-probe-1.md"
    printf 'Result B: solution research content\n' > "$workdir/results/agy-probe-2.md"

    PROJECT_ROOT="$PROJECT_ROOT" WORKDIR="$workdir" HBIN="$hbin" FAIL_AGENT="$fail_agent" bash -c '
        set -euo pipefail
        export PATH="$HBIN"
        RESULTS_DIR="$WORKDIR/results"
        DRY_RUN=false
        TIMEOUT=30
        GREEN=""; NC=""
        # Stubs for helpers that live in sibling libs (not sourced here)
        log() { :; }
        guard_output() { :; }
        rank_results_by_signals() {
            printf "%s\n%s\n" "$RESULTS_DIR/codex-probe-1.md" "$RESULTS_DIR/agy-probe-2.md"
        }
        score_result_file() { echo 80; }
        run_agent_sync() {
            echo "SYNTH_AGENT=$1" >> "$WORKDIR/agent.log"
            if [ -n "${FAIL_AGENT:-}" ] && [ "$1" = "$FAIL_AGENT" ]; then return 1; fi
            echo "SYNTHESIZED BODY via $1"
        }
        source "$PROJECT_ROOT/scripts/lib/parallel.sh"
        aggregate_results >/dev/null 2>&1
        echo "=== AGGREGATE ==="
        cat "$RESULTS_DIR"/aggregate-*.md 2>/dev/null || true
        echo "=== AGENTLOG ==="
        cat "$WORKDIR/agent.log" 2>/dev/null || true
    '
    rm -rf "$workdir"
}

test_aggregator_selects_agy_when_available() {
    test_case "aggregate_results SYNTHESIZES via agy (not concatenation) when gemini is missing but agy is available"
    local out
    out="$(_run_aggregate_scenario agy)"
    if [[ "$out" == *"Synthesized Results"* ]] \
       && [[ "$out" == *"Synthesizer: agy"* ]] \
       && [[ "$out" == *"SYNTH_AGENT=agy"* ]] \
       && [[ "$out" != *"Aggregated Results"* ]]; then
        test_pass
    else
        test_fail "expected agy-synthesized aggregate, got:\n$out"
    fi
}

test_aggregator_concatenates_when_no_provider() {
    test_case "aggregate_results falls back to concatenation when NO synthesis provider is reachable"
    local out
    out="$(_run_aggregate_scenario none)"
    if [[ "$out" == *"Aggregated Results"* ]] \
       && [[ "$out" != *"Synthesized Results"* ]] \
       && [[ "$out" != *"SYNTH_AGENT="* ]]; then
        test_pass
    else
        test_fail "expected plain concatenation with no provider, got:\n$out"
    fi
}

test_aggregator_retries_claude_sonnet_when_agy_fails() {
    test_case "aggregate_results retries via claude-sonnet (not concatenation) when the agy synthesizer fails"
    local out
    out="$(_run_aggregate_scenario agy-fails)"
    # agy must be attempted first, then claude-sonnet must produce the synthesis
    if [[ "$out" == *"Synthesized Results"* ]] \
       && [[ "$out" == *"Synthesizer: claude-sonnet"* ]] \
       && [[ "$out" == *"SYNTH_AGENT=agy"* ]] \
       && [[ "$out" == *"SYNTH_AGENT=claude-sonnet"* ]] \
       && [[ "$out" != *"Aggregated Results"* ]]; then
        test_pass
    else
        test_fail "expected claude-sonnet retry synthesis after agy failure, got:\n$out"
    fi
}

test_no_bare_gemini_synthesis_in_parallel
test_parallel_routes_through_run_agent_sync
test_picker_prefers_agy
test_embrace_dispatch_seats_agy
test_aggregator_selects_agy_when_available
test_aggregator_concatenates_when_no_provider
test_aggregator_retries_claude_sonnet_when_agy_fails

test_summary
