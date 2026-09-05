#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
mkdir -p "$TEST_TMP_DIR/home-default" "$TEST_TMP_DIR/home-configured"
test_suite "agy is the Google seat across workflows (Gemini CLI sunset 2026-06-18)"

test_role_map_research_design_copywriting_is_agy() {
    test_case "get_agent_for_task routes research/design/copywriting to agy"
    local out
    out="$(bash -c 'source "'"$PROJECT_ROOT"'/scripts/lib/agents.sh" 2>/dev/null
        for r in research design copywriting; do get_agent_for_task "$r"; done')"
    if [[ "$(echo "$out" | grep -c '^agy$')" == "3" ]]; then test_pass
    else test_fail "expected 3x agy, got: $(echo "$out" | tr '\n' ' ')"; fi
}

test_fallback_chain_is_configuration_driven() {
    test_case "get_fallback_agent fails closed when every candidate is unavailable"
    local out rc=0
    out="$(env \
        "HOME=$TEST_TMP_DIR/home-default" \
        "OCTOPUS_PROVIDERS_CONFIG=$TEST_TMP_DIR/missing-providers.json" \
        bash -c 'source "'"$PROJECT_ROOT"'/scripts/lib/model-resolver.sh" 2>/dev/null
        is_agent_available(){ [[ "$1" == agy ]]; }
        is_agent_available_v2(){ [[ "$1" == agy ]]; }
        get_fallback_agent codex coding')" || rc=$?
    if [[ "$rc" -ne 0 && -z "$out" ]]; then
        test_pass
    else
        test_fail "expected empty output and non-zero status, got rc=$rc out=[$out]"
    fi
}

test_tiered_routing_propagates_exhaustion() {
    test_case "get_tiered_agent propagates fallback exhaustion"
    local out rc=0
    out="$(env \
        "HOME=$TEST_TMP_DIR/home-tiered" \
        "OCTOPUS_PROVIDERS_CONFIG=$TEST_TMP_DIR/missing-tiered-providers.json" \
        bash -c 'source "'"$PROJECT_ROOT"'/scripts/lib/model-resolver.sh" 2>/dev/null
        source "'"$PROJECT_ROOT"'/scripts/lib/agents.sh" 2>/dev/null
        load_user_config(){ USER_RESOURCE_TIER=standard; }
        get_resource_adjusted_tier(){ printf "%s\n" "$1"; }
        is_agent_available_v2(){ return 1; }
        get_tiered_agent coding 2' 2>/dev/null)" || rc=$?
    if [[ "$rc" -ne 0 && -z "$out" ]]; then
        test_pass
    else
        test_fail "expected routing failure to propagate, got rc=$rc out=[$out]"
    fi
}

test_configured_fallback_chain_routes_native_resolver() {
    test_case "get_fallback_agent honors routing.fallbackChains and routing.roles"
    local cfg out
    cfg="$TEST_TMP_DIR/providers-configured.json"
    cat > "$cfg" <<'JSON'
{"routing":{"roles":{"architect":{"provider":"claude","model":"claude-opus-5"}},"fallbackChains":{"default":[{"role":"architect"}]}}}
JSON
    out="$(env \
        "HOME=$TEST_TMP_DIR/home-configured" \
        "OCTOPUS_PROVIDERS_CONFIG=$cfg" \
        bash -c 'source "'"$PROJECT_ROOT"'/scripts/lib/model-resolver.sh" 2>/dev/null
        is_agent_available(){ [[ "$1" == claude ]]; }
        is_agent_available_v2(){ [[ "$1" == claude ]]; }
        get_fallback_agent codex coding')"
    [[ "$out" == "claude:claude-opus-5" ]] && test_pass || test_fail "expected configured qualified claude fallback, got: $out"
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
       grep -q 'octopus_execution_profile_provider "tangle" "decompose" "researcher" "agy"' "$PROJECT_ROOT/scripts/lib/workflows.sh"; then
        test_pass
    else test_fail "tangle decompose still defaults to gemini"; fi
}

test_role_map_research_design_copywriting_is_agy
test_fallback_chain_is_configuration_driven
test_tiered_routing_propagates_exhaustion
test_configured_fallback_chain_routes_native_resolver
test_no_functional_gemini_dispatch
test_tangle_decompose_default_is_agy

test_summary
