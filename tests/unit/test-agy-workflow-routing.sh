#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "agy is the Google seat across workflows (Gemini CLI sunset 2026-06-18)"

test_role_map_research_design_copywriting_is_agy() {
    test_case "get_agent_for_task routes research/design/copywriting to agy"
    local out
    out="$(bash -c 'source "'"$PROJECT_ROOT"'/scripts/lib/agents.sh" 2>/dev/null
        for r in research design copywriting; do get_agent_for_task "$r"; done')"
    if [[ "$(echo "$out" | grep -c '^agy$')" == "3" ]]; then test_pass
    else test_fail "expected 3x agy, got: $(echo "$out" | tr '\n' ' ')"; fi
}

test_fallback_chain_prefers_agy() {
    test_case "get_fallback_agent falls back to agy (not gemini) when codex is down"
    local out
    out="$(bash -c 'source "'"$PROJECT_ROOT"'/scripts/lib/model-resolver.sh" 2>/dev/null
        is_agent_available(){ [[ "$1" == agy ]]; }
        get_fallback_agent codex')"
    [[ "$out" == "agy" ]] && test_pass || test_fail "expected agy, got: $out"
}

test_no_functional_gemini_dispatch() {
    test_case "no functional gemini dispatch remains in the workflow libs"
    local hits
    hits=$(grep -nE 'run_agent_sync "gemini"|echo "gemini"|agent="gemini"' \
        "$PROJECT_ROOT/scripts/lib/workflows.sh" \
        "$PROJECT_ROOT/scripts/lib/agents.sh" \
        "$PROJECT_ROOT/scripts/lib/quality.sh" \
        "$PROJECT_ROOT/scripts/lib/model-resolver.sh" 2>/dev/null || true)
    if [[ -z "$hits" ]]; then test_pass
    else test_fail "stale gemini dispatch: $hits"; fi
}

test_tangle_decompose_default_is_agy() {
    test_case "tangle decompose default agent is agy"
    if grep -q 'tangle_decompose_agent="agy"' "$PROJECT_ROOT/scripts/lib/workflows.sh" && \
       grep -q 'octopus_agent_override "tangle" "decompose" "agy"' "$PROJECT_ROOT/scripts/lib/workflows.sh"; then
        test_pass
    else test_fail "tangle decompose still defaults to gemini"; fi
}

test_role_map_research_design_copywriting_is_agy
test_fallback_chain_prefers_agy
test_no_functional_gemini_dispatch
test_tangle_decompose_default_is_agy

test_summary
