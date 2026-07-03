#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "research defaults use Antigravity instead of Gemini API"

test_case "default researcher role maps to agy"
role_mapping="$(bash -c 'source "$1/scripts/lib/agent-utils.sh" 2>/dev/null; get_role_mapping researcher' bash "$PROJECT_ROOT")"
if [[ "$role_mapping" == "agy:Gemini 3.1 Pro (High)" ]]; then
    test_pass
else
    test_fail "expected agy:Gemini 3.1 Pro (High), got: $role_mapping"
fi

test_case "legacy researcher mapping is preserved"
legacy_mapping="$(bash -c 'export OCTOPUS_LEGACY_ROLES=1; source "$1/scripts/lib/agent-utils.sh" 2>/dev/null; get_role_mapping researcher' bash "$PROJECT_ROOT")"
if [[ "$legacy_mapping" == "gemini:gemini-3.1-pro-preview" ]]; then
    test_pass
else
    test_fail "expected legacy gemini mapping, got: $legacy_mapping"
fi

test_case "new model config routes research phase to agy"
config_hits="$(grep -R '"research": "gemini:default"' "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" "$PROJECT_ROOT/scripts/lib/provider-routing.sh" 2>/dev/null || true)"
if [[ -z "$config_hits" ]] && \
   grep -q '"research": "agy"' "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" && \
   grep -q '"research": "agy"' "$PROJECT_ROOT/scripts/lib/provider-routing.sh" && \
   grep -q '"default": "Gemini 3.1 Pro (High)"' "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" && \
   grep -q '"default": "Gemini 3.1 Pro (High)"' "$PROJECT_ROOT/scripts/lib/provider-routing.sh" && \
   grep -q 'research) default_target="agy" ;;' "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh"; then
    test_pass
else
    test_fail "research config defaults are not consistently agy; stale hits: $config_hits"
fi

test_case "research phase resolves to explicit agy Pro label"
resolve_out="$({
    tmp_home=""
    tmp_bin=""
    cleanup_research_defaults_tmp() {
        rm -rf "$tmp_home" "$tmp_bin"
    }
    trap cleanup_research_defaults_tmp EXIT

    tmp_home="$(mktemp -d)"
    tmp_bin="$(mktemp -d)"
    mkdir -p "$tmp_home/.claude-octopus/config"
    cat > "$tmp_home/.claude-octopus/config/providers.json" <<'JSON'
{"providers":{"agy":{"default":"Gemini 3.1 Pro (High)"}},"routing":{"phases":{"research":"agy"}}}
JSON
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" ]]; then
    printf '%s
' 'Gemini 3.1 Pro (High)' 'Gemini 3.5 Flash (High)' 'Gemini 3.5 Flash (Low)'
    exit 0
fi
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"
    HOME="$tmp_home" PATH="$tmp_bin:$PATH" bash -c 'log(){ :; }; source "$1/scripts/lib/model-resolver.sh"; resolve_octopus_model agy agy research researcher' bash "$PROJECT_ROOT"
} 2>/dev/null)"
if [[ "$resolve_out" == "Gemini 3.1 Pro (High)" ]]; then
    test_pass
else
    test_fail "expected Gemini 3.1 Pro (High), got: $resolve_out"
fi

test_case "council research fallback defaults to agy"
council_out="$(bash -c 'source "$1/scripts/lib/council.sh" 2>/dev/null; council_agent_config_value(){ return 0; }; council_persona_default_provider research-synthesizer; council_persona_model research-synthesizer' bash "$PROJECT_ROOT")"
if [[ "$council_out" == $'agy\nGemini 3.1 Pro (High)' ]]; then
    test_pass
else
    test_fail "expected agy/Gemini 3.1 Pro (High), got: $(printf '%s' "$council_out" | tr '\n' '/')"
fi

test_summary
