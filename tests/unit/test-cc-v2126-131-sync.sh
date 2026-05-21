#!/usr/bin/env bash
# Tests for Claude Code v2.1.126-131 compatibility sync.
# Validates feature flags, doctor guidance, release smoke checks, and the
# latest 2.1.131 version comparison regression.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Claude Code v2.1.126-131 compatibility sync"

ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"
PROVIDERS="$PROJECT_ROOT/scripts/lib/providers.sh"
DOCTOR="$PROJECT_ROOT/scripts/lib/doctor.sh"
VALIDATE_RELEASE="$PROJECT_ROOT/scripts/validate-release.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

assert_declared() {
    local flag="$1"
    if grep -q "^${flag}=false" "$ORCH"; then
        pass "$flag declared"
    else
        fail "$flag declared" "missing ${flag}=false in orchestrate.sh"
    fi
}

assert_block_sets() {
    local version="$1"
    local flag="$2"
    local window="${3:-20}"
    if grep -A "$window" "version_compare.*CLAUDE_CODE_VERSION.*\"${version}\"" "$PROVIDERS" | grep -q "${flag}=true"; then
        pass "v${version} block sets $flag"
    else
        fail "v${version} block sets $flag" "missing ${flag}=true near v${version} detection"
    fi
}

assert_doctor_tip() {
    local tip="$1"
    if grep -q "\"${tip}\"" "$DOCTOR"; then
        pass "Doctor tip '$tip' exists"
    else
        fail "Doctor tip '$tip'" "missing from doctor.sh"
    fi
}

echo "=== 1. Latest version comparison ==="
if grep -q 'version_compare "$current_version" "$min_version" ">="' "$ORCH"; then
    pass "check_claude_version uses explicit >= operator"
else
    fail "check_claude_version operator" "2-arg version_compare marks 2.1.131 as outdated"
fi

if bash -lc 'source scripts/lib/providers.sh; version_compare 2.1.131 2.1.14 ">="' >/dev/null 2>&1; then
    pass "version_compare treats 2.1.131 as >= 2.1.14"
else
    fail "2.1.131 comparison" "2.1.131 should satisfy minimum 2.1.14"
fi

echo ""
echo "=== 2. Flag declarations ==="
for flag in \
    SUPPORTS_GATEWAY_MODEL_DISCOVERY \
    SUPPORTS_PROJECT_PURGE \
    SUPPORTS_SKILL_ACTIVATED_OTEL_TRIGGER \
    SUPPORTS_PLUGIN_ZIP_DIR \
    SUPPORTS_MCP_TOOL_COUNTS \
    SUPPORTS_MCP_WORKSPACE_RESERVED \
    SUPPORTS_LOCAL_SETTINGS_SUGGESTIONS \
    SUPPORTS_SUBPROCESS_OTEL_SCRUB \
    SUPPORTS_INIT_PLUGIN_ERRORS \
    SUPPORTS_PARALLEL_SHELL_READONLY_RESILIENCE \
    SUPPORTS_PLUGIN_UPDATE_NPM \
    SUPPORTS_PLUGIN_URL \
    SUPPORTS_FORCE_SYNC_OUTPUT \
    SUPPORTS_PACKAGE_MANAGER_AUTO_UPDATE \
    SUPPORTS_EXPERIMENTAL_MANIFEST_KEYS \
    SUPPORTS_GATEWAY_MODEL_DISCOVERY_OPT_IN \
    SUPPORTS_SKILL_OVERRIDES \
    SUPPORTS_PR_COUNT_MCP_OTEL; do
    assert_declared "$flag"
done

echo ""
echo "=== 3. Detection blocks ==="
for flag in SUPPORTS_GATEWAY_MODEL_DISCOVERY SUPPORTS_PROJECT_PURGE SUPPORTS_SKILL_ACTIVATED_OTEL_TRIGGER; do
    assert_block_sets "2.1.126" "$flag" 12
done

for flag in SUPPORTS_PLUGIN_ZIP_DIR SUPPORTS_MCP_TOOL_COUNTS SUPPORTS_MCP_WORKSPACE_RESERVED \
            SUPPORTS_LOCAL_SETTINGS_SUGGESTIONS SUPPORTS_SUBPROCESS_OTEL_SCRUB \
            SUPPORTS_INIT_PLUGIN_ERRORS SUPPORTS_PARALLEL_SHELL_READONLY_RESILIENCE \
            SUPPORTS_PLUGIN_UPDATE_NPM; do
    assert_block_sets "2.1.128" "$flag" 18
done

for flag in SUPPORTS_PLUGIN_URL SUPPORTS_FORCE_SYNC_OUTPUT SUPPORTS_PACKAGE_MANAGER_AUTO_UPDATE \
            SUPPORTS_EXPERIMENTAL_MANIFEST_KEYS SUPPORTS_GATEWAY_MODEL_DISCOVERY_OPT_IN \
            SUPPORTS_SKILL_OVERRIDES SUPPORTS_PR_COUNT_MCP_OTEL; do
    assert_block_sets "2.1.129" "$flag" 18
done

echo ""
echo "=== 4. Detection logs ==="
for label in "Gateway Models" "Project Purge" "Plugin Zip Dir" "Plugin URL" \
             "Skill Overrides" "Init Plugin Errors"; do
    if grep -q "$label" "$PROVIDERS"; then
        pass "Logged: $label"
    else
        fail "Logged: $label" "missing from providers.sh logging"
    fi
done

echo ""
echo "=== 5. Doctor checks ==="
for tip in gateway-model-discovery project-purge skill-activated-otel plugin-zip-dir \
           plugin-url force-sync-output package-manager-auto-update \
           experimental-manifest-keys skill-overrides mcp-workspace-reserved \
           init-plugin-errors pr-count-mcp-otel; do
    assert_doctor_tip "$tip"
done

if grep -q 'CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY' "$DOCTOR"; then
    pass "Doctor mentions gateway discovery opt-in env"
else
    fail "Gateway discovery opt-in" "missing CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY guidance"
fi

if grep -q 'skillOverrides' "$DOCTOR"; then
    pass "Doctor checks skillOverrides"
else
    fail "skillOverrides doctor check" "missing skillOverrides guidance"
fi

if grep -q 'mcpServers.*workspace' "$DOCTOR"; then
    pass "Doctor checks reserved MCP workspace server"
else
    fail "MCP workspace reserved check" "missing reserved workspace MCP check"
fi

echo ""
echo "=== 6. Release smoke checks ==="
if grep -Fq 'claude --plugin-dir "$PLUGIN_ZIP"' "$VALIDATE_RELEASE"; then
    pass "Release validation covers --plugin-dir zip smoke"
else
    fail "plugin-dir zip release smoke" "missing --plugin-dir zip validation"
fi

if grep -q -- '--plugin-url' "$VALIDATE_RELEASE"; then
    pass "Release validation covers --plugin-url support"
else
    fail "plugin-url release smoke" "missing --plugin-url validation"
fi

if grep -q 'OCTOPUS_RELEASE_RUNTIME_SMOKE' "$VALIDATE_RELEASE"; then
    pass "Runtime release smoke is opt-in"
else
    fail "runtime smoke opt-in" "runtime plugin load smoke should be gated by OCTOPUS_RELEASE_RUNTIME_SMOKE"
fi

test_summary
