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

provider_state_fallback() {
    local state="$1" task="$2"
    env -i "PATH=$PATH" "HOME=$TEST_TMP_DIR/home-provider-state" \
        "WORKSPACE_DIR=$TEST_TMP_DIR/provider-state" "VERBOSE=false" \
        "OCTOPUS_PROVIDERS_CONFIG=$TEST_TMP_DIR/missing-provider-routes.json" \
        bash -c '
            # Model an absent Antigravity CLI without replacing availability or routing.
            command() {
                if [[ "$*" == "-v agy" ]]; then return 1; fi
                builtin command "$@"
            }
            source "$1/scripts/lib/smoke.sh"
            source "$1/scripts/lib/model-resolver.sh"
            PROVIDERS_CONFIG_FILE="$2"
            get_fallback_agent agy "$3"
        ' _ "$PROJECT_ROOT" "$state" "$task"
}

test_loaded_provider_state_fallback() {
    local state="$TEST_TMP_DIR/provider-state.yaml" task out rc
    mkdir -p "$TEST_TMP_DIR/home-provider-state"
    printf 'codex:\n  installed: true\n  auth_method: oauth\nclaude:\n  installed: false\n' > "$state"
    test_case "real fallback loads smoke's default false flags for research/design/copywriting/image (#1174)"
    for task in research design copywriting image; do
        rc=0
        out="$(provider_state_fallback "$state" "$task")" || rc=$?
        if [[ "$rc" -ne 0 || "$out" != "codex-review" ]]; then
            test_fail "expected authenticated Codex fallback for $task, got rc=$rc out=[$out]"
            return
        fi
    done
    test_pass

    test_case "real fallback can load a Claude-only provider configuration (#1174)"
    printf 'codex:\n  installed: false\nclaude:\n  installed: true\n' > "$state"
    rc=0
    out="$(provider_state_fallback "$state" research)" || rc=$?
    if [[ "$rc" -eq 0 && "$out" == "claude-opus" ]]; then test_pass
    else test_fail "expected Claude fallback, got rc=$rc out=[$out]"; fi

    test_case "loaded provider configuration still rejects unauthenticated Codex (#1174)"
    printf 'codex:\n  installed: true\n  auth_method: none\nclaude:\n  installed: false\n' > "$state"
    rc=0
    out="$(provider_state_fallback "$state" research)" || rc=$?
    if [[ "$rc" -ne 0 && -z "$out" ]]; then test_pass
    else test_fail "expected fallback exhaustion, got rc=$rc out=[$out]"; fi
}

test_role_map_research_design_copywriting_is_agy
test_fallback_chain_is_configuration_driven
test_tiered_routing_propagates_exhaustion
test_configured_fallback_chain_routes_native_resolver
test_no_functional_gemini_dispatch
test_tangle_decompose_default_is_agy
test_loaded_provider_state_fallback

test_case "Claude-only discovery runs once when Codex remains unavailable"
discovery_log="$TEST_TMP_DIR/provider-discovery.log"
discovery_rc=0
env -i "PATH=$PATH" "HOME=$TEST_TMP_DIR/home-provider-state" "VERBOSE=false" \
    bash -e -c '
        source "$1/scripts/lib/smoke.sh"
        source "$1/scripts/lib/model-resolver.sh"
        PROVIDERS_CONFIG_FILE="$2/missing-provider-state"
        discovery_log="$2/provider-discovery.log"
        detect_providers() { printf "called\n" >> "$discovery_log"; printf "claude:oauth\n"; }
        detect_tier_claude() { printf "pro\n"; }
        get_cost_tier_for_subscription() { printf "medium\n"; }
        is_agent_available_v2 claude-opus
        is_agent_available_v2 claude-sonnet
        is_agent_available_v2 claude-opus-fast
    ' _ "$PROJECT_ROOT" "$TEST_TMP_DIR" || discovery_rc=$?
discovery_count=0
[[ ! -f "$discovery_log" ]] || discovery_count="$(wc -l < "$discovery_log" | tr -d " ")"
if [[ "$discovery_rc" -eq 0 && "$discovery_count" -eq 1 ]]; then test_pass
else test_fail "expected one successful discovery, got rc=$discovery_rc calls=$discovery_count"; fi

test_case "saving provider state marks it loaded and explicit refresh still reloads"
if env -i "PATH=$PATH" "HOME=$TEST_TMP_DIR/home-provider-state" "VERBOSE=false" \
    bash -e -c '
        source "$1/scripts/lib/smoke.sh"
        PROVIDERS_CONFIG_FILE="$2/saved-provider-state"
        log() { :; }
        PROVIDER_CLAUDE_INSTALLED=true
        save_providers_config
        [[ "$PROVIDERS_CONFIG_LOADED" == "true" ]]
        PROVIDER_CLAUDE_INSTALLED=false
        load_providers_config
        [[ "$PROVIDER_CLAUDE_INSTALLED" == "true" ]]
    ' _ "$PROJECT_ROOT" "$TEST_TMP_DIR"; then test_pass
else test_fail "saved state was not marked loaded or explicit refresh was skipped"; fi

test_case "failed provider saves do not mark the configuration loaded"
mkdir -p "$TEST_TMP_DIR/provider-state-directory"
if env -i "PATH=$PATH" "HOME=$TEST_TMP_DIR/home-provider-state" "VERBOSE=false" \
    bash -e -c '
        source "$1/scripts/lib/smoke.sh"
        PROVIDERS_CONFIG_FILE="$2/provider-state-directory"
        if save_providers_config 2>/dev/null; then exit 1; fi
        [[ "$PROVIDERS_CONFIG_LOADED" == "false" ]]
    ' _ "$PROJECT_ROOT" "$TEST_TMP_DIR"; then test_pass
else test_fail "a failed save reported success or marked the configuration loaded"; fi

test_case "a provider file-open failure remains retryable in the same shell"
if env -i "PATH=$PATH" "HOME=$TEST_TMP_DIR/home-provider-state" "VERBOSE=false" \
    bash -e -c '
        source "$1/scripts/lib/smoke.sh"
        source "$1/scripts/lib/model-resolver.sh"
        PROVIDERS_CONFIG_FILE="$2/retry-provider-state"
        printf "claude:\n  installed: true\n" > "$PROVIDERS_CONFIG_FILE"
        # Remove the file after the existence check, before the real loop opens it.
        set -T
        trap '\''if [[ "$BASH_COMMAND" == "local current_provider="* ]]; then
            rm "$PROVIDERS_CONFIG_FILE"
            trap - DEBUG
        fi'\'' DEBUG
        if load_providers_config 2>/dev/null; then exit 1; fi
        set +T
        trap - DEBUG
        [[ "$PROVIDERS_CONFIG_LOADED" == "false" ]]
        printf "claude:\n  installed: true\n" > "$PROVIDERS_CONFIG_FILE"
        is_agent_available_v2 claude-opus
        [[ "$PROVIDERS_CONFIG_LOADED" == "true" ]]
    ' _ "$PROJECT_ROOT" "$TEST_TMP_DIR"; then test_pass
else test_fail "file-open failure was cached or availability did not retry the repaired file"; fi

test_case "failed provider discovery remains retryable in the same shell"
if env -i "PATH=$PATH" "HOME=$TEST_TMP_DIR/home-provider-state" "VERBOSE=false" \
    bash -e -c '
        source "$1/scripts/lib/smoke.sh"
        source "$1/scripts/lib/model-resolver.sh"
        PROVIDERS_CONFIG_FILE="$2/missing-retry-discovery-state"
        detect_providers() { return 7; }
        if load_providers_config; then exit 1; fi
        [[ "$PROVIDERS_CONFIG_LOADED" == "false" ]]
        detect_providers() { printf "claude:oauth\n"; }
        detect_tier_claude() { printf "pro\n"; }
        get_cost_tier_for_subscription() { printf "medium\n"; }
        is_agent_available_v2 claude-opus
        [[ "$PROVIDERS_CONFIG_LOADED" == "true" ]]
    ' _ "$PROJECT_ROOT" "$TEST_TMP_DIR"; then test_pass
else test_fail "discovery failure was cached or availability did not retry discovery"; fi

test_summary
