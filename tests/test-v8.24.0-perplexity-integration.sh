#!/usr/bin/env bash
# Test v8.24.0 Perplexity Provider Integration (Issue #22)
# Validates Perplexity Sonar as a web-grounded research provider

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "v8.24.0 Perplexity Provider Integration (Issue #22)"

ORCHESTRATE_SH="$PROJECT_ROOT/scripts/orchestrate.sh"
# v9.4.0: Support grepping across orchestrate.sh + lib/ for extracted functions
_ORCH_ALL_TMP=$(mktemp)
cat "$ORCHESTRATE_SH" "$PROJECT_ROOT/scripts/lib/"*.sh 2>/dev/null > "$_ORCH_ALL_TMP"
trap 'rm -f "$_ORCH_ALL_TMP"' EXIT
MCP_DETECT="$PROJECT_ROOT/scripts/mcp-provider-detection.sh"
STATE_MANAGER="$PROJECT_ROOT/scripts/state-manager.sh"


TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}Testing v8.24.0 Perplexity Provider Integration (Issue #22)${NC}"
echo ""

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 1: orchestrate.sh - Agent Registration
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 1: Agent Registration"
echo "────────────────────────────────────────"

# Test 1.1: perplexity in AVAILABLE_AGENTS
if grep -q "perplexity" "$_ORCH_ALL_TMP" && grep "AVAILABLE_AGENTS=" "$_ORCH_ALL_TMP" | grep -q "perplexity"; then
    pass "perplexity in AVAILABLE_AGENTS"
else
    fail "perplexity NOT in AVAILABLE_AGENTS"
fi

# Test 1.2: perplexity-fast in AVAILABLE_AGENTS
if grep "AVAILABLE_AGENTS=" "$_ORCH_ALL_TMP" | grep -q "perplexity-fast"; then
    pass "perplexity-fast in AVAILABLE_AGENTS"
else
    fail "perplexity-fast NOT in AVAILABLE_AGENTS"
fi

# Test 1.3: get_agent_command has perplexity case
if grep -A3 "perplexity|perplexity-fast" "$_ORCH_ALL_TMP" | grep -q "perplexity_execute"; then
    pass "get_agent_command() handles perplexity"
else
    fail "get_agent_command() missing perplexity case"
fi

# Test 1.4: perplexity defaults to sonar-pro (via model catalog or resolve fallback)
# Refactored: models resolved via resolve_octopus_model + model catalog, not get_agent_model case
if grep -q 'sonar-pro' "$_ORCH_ALL_TMP" && grep -q 'perplexity.*sonar-pro\|sonar-pro.*perplexity' "$_ORCH_ALL_TMP"; then
    pass "perplexity default: sonar-pro (in model catalog/resolution)"
else
    fail "perplexity missing sonar-pro default"
fi

if grep -q 'sonar' "$_ORCH_ALL_TMP" && grep -q 'candidates=.*sonar' "$_ORCH_ALL_TMP"; then
    pass "perplexity sonar model registered in catalog"
else
    fail "perplexity missing sonar model"
fi

# Test 1.5: perplexity provider handled in get_agent_command
# Refactored: provider mapping now via get_agent_command case + perplexity_execute
if grep -q 'perplexity|perplexity-fast)' "$_ORCH_ALL_TMP" && grep -A 3 'perplexity|perplexity-fast)' "$_ORCH_ALL_TMP" | grep -q 'perplexity_execute\|provider.*perplexity'; then
    pass "get_agent_command() handles perplexity provider"
else
    fail "get_agent_command() perplexity handling missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 2: orchestrate.sh - perplexity_execute Function
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 2: perplexity_execute Function"
echo "────────────────────────────────────────"

# Test 2.1: Function exists
if grep -q "^perplexity_execute()" "$_ORCH_ALL_TMP"; then
    pass "perplexity_execute() function exists"
else
    fail "perplexity_execute() function NOT found"
fi

# Test 2.2: PERPLEXITY_API_KEY check
if grep -q 'PERPLEXITY_API_KEY' "$_ORCH_ALL_TMP"; then
    pass "PERPLEXITY_API_KEY referenced"
else
    fail "PERPLEXITY_API_KEY not referenced"
fi

# Test 2.3: Uses Perplexity API endpoint
if grep -q "api.perplexity.ai" "$_ORCH_ALL_TMP"; then
    pass "Uses api.perplexity.ai endpoint"
else
    fail "api.perplexity.ai endpoint missing"
fi

# Test 2.4: JSON payload with model
if grep -A35 "^perplexity_execute()" "$_ORCH_ALL_TMP" | grep -q '"model"'; then
    pass "perplexity_execute sends model in payload"
else
    fail "perplexity_execute missing model in payload"
fi

# Test 2.5: Citations extraction
if grep -q "citations" "$_ORCH_ALL_TMP"; then
    pass "Citation extraction present"
else
    fail "Citation extraction missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 3: orchestrate.sh - Security & Cost Integration
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 3: Security & Cost Integration"
echo "────────────────────────────────────────"

# Test 3.1: Command whitelist
if grep -q '"perplexity_execute"' "$_ORCH_ALL_TMP"; then
    pass "perplexity_execute in command whitelist"
else
    fail "perplexity_execute NOT in command whitelist"
fi

# Test 3.2: Trust markers include perplexity
if grep -q 'codex\*|gemini\*|perplexity\*' "$_ORCH_ALL_TMP"; then
    pass "Trust markers include perplexity*"
else
    fail "Trust markers missing perplexity"
fi

# Test 3.3: is_api_based_provider handles perplexity
if grep -q 'perplexity)' "$_ORCH_ALL_TMP" && grep -B1 -A3 'perplexity)' "$_ORCH_ALL_TMP" | grep -q 'PERPLEXITY_API_KEY'; then
    pass "is_api_based_provider() handles perplexity"
else
    fail "is_api_based_provider() missing perplexity"
fi

# Test 3.4: Model pricing for sonar models
if grep -q 'sonar-pro)' "$_ORCH_ALL_TMP" && grep -q 'sonar)' "$_ORCH_ALL_TMP"; then
    pass "Model pricing for sonar-pro and sonar"
else
    fail "Model pricing missing for sonar models"
fi

# Test 3.5: Perplexity env — shell function provider, resolves key (#300)
if grep -q 'perplexity\*)' "$_ORCH_ALL_TMP" && grep -A3 'perplexity\*)' "$_ORCH_ALL_TMP" | grep -q 'PERPLEXITY_API_KEY'; then
    pass "build_provider_env() resolves Perplexity API key"
else
    fail "build_provider_env() missing perplexity key resolution"
fi

# Test 3.6: OCTOPUS_<PROVIDER>_MODEL env var support (dynamic pattern covers all providers)
if grep -q 'OCTOPUS_.*_MODEL' "$_ORCH_ALL_TMP" && grep -q 'tr.*lower.*upper.*_MODEL' "$_ORCH_ALL_TMP"; then
    pass "OCTOPUS_<PROVIDER>_MODEL dynamic env var pattern (covers perplexity)"
else
    fail "OCTOPUS_<PROVIDER>_MODEL env var pattern missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 4: orchestrate.sh - Probe Discover Integration
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 4: Probe Discover Integration"
echo "────────────────────────────────────────"

# Test 4.1: Perplexity agent added to probe_discover
if grep -q 'probe_agents+=("perplexity")' "$_ORCH_ALL_TMP"; then
    pass "Perplexity added to probe_agents in probe_discover()"
else
    fail "Perplexity NOT added to probe_agents"
fi

# Test 4.2: Web research perspective
if grep -q "Web Research" "$_ORCH_ALL_TMP"; then
    pass "Web Research pane title present"
else
    fail "Web Research pane title missing"
fi

# Test 4.3: Conditional on PERPLEXITY_API_KEY
if grep -B5 'probe_agents+=("perplexity")' "$_ORCH_ALL_TMP" | grep -q 'PERPLEXITY_API_KEY'; then
    pass "Perplexity agent conditional on API key"
else
    fail "Perplexity agent not gated on API key"
fi

# Test 4.4: Web-grounded research prompt
if grep -q "live web" "$_ORCH_ALL_TMP" && grep -q "source URLs" "$_ORCH_ALL_TMP"; then
    pass "Web-grounded research prompt includes live web and source URLs"
else
    fail "Web research prompt missing key terms"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 5: mcp-provider-detection.sh
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 5: MCP Provider Detection"
echo "────────────────────────────────────────"

# Test 5.1: detect_provider_mcp handles perplexity
if grep -q 'perplexity)' "$MCP_DETECT"; then
    pass "detect_provider_mcp() handles perplexity"
else
    fail "detect_provider_mcp() missing perplexity"
fi

# Test 5.2: detect_provider_cli handles perplexity
if grep -A5 'detect_provider_cli' "$MCP_DETECT" | grep -q 'perplexity'; then
    pass "detect_provider_cli() handles perplexity"
else
    # More lenient check
    if grep 'perplexity' "$MCP_DETECT" | grep -q 'PERPLEXITY_API_KEY'; then
        pass "detect_provider_cli() handles perplexity (via API key)"
    else
        fail "detect_provider_cli() missing perplexity"
    fi
fi

# Test 5.3: detect_all_providers includes perplexity
if grep -q 'perplexity_status' "$MCP_DETECT"; then
    pass "detect_all_providers() tracks perplexity_status"
else
    fail "detect_all_providers() missing perplexity_status"
fi

# Test 5.4: JSON output includes perplexity
if grep -q '"perplexity"' "$MCP_DETECT" && grep -q '"🟣"' "$MCP_DETECT"; then
    pass "JSON output includes perplexity with 🟣 emoji"
else
    fail "JSON output missing perplexity entry"
fi

# Test 5.5: Banner includes perplexity
if grep -q 'perplexity_display' "$MCP_DETECT"; then
    pass "get_provider_banner() includes perplexity"
else
    fail "get_provider_banner() missing perplexity"
fi

# Test 5.6: Usage text lists perplexity
if grep -q 'perplexity' "$MCP_DETECT" | head -1 && grep 'Providers:' "$MCP_DETECT" | grep -q 'perplexity'; then
    pass "Usage text lists perplexity provider"
else
    fail "Usage text missing perplexity"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 6: state-manager.sh
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 6: State Manager"
echo "────────────────────────────────────────"

# Test 6.1: provider_usage includes perplexity
if grep -q '"perplexity": 0' "$STATE_MANAGER"; then
    pass "provider_usage includes perplexity: 0"
else
    fail "provider_usage missing perplexity"
fi

# Test 6.2: Status display includes perplexity
if grep -q 'Perplexity:' "$STATE_MANAGER"; then
    pass "Status display shows Perplexity usage"
else
    fail "Status display missing Perplexity"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 7: Documentation & Skills
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 7: Documentation & Skills"
echo "────────────────────────────────────────"

# Test 7.1: CLAUDE.md includes perplexity indicator
if grep -q '🟣.*Perplexity' "$PROJECT_ROOT/CLAUDE.md"; then
    pass "CLAUDE.md has 🟣 Perplexity indicator"
else
    fail "CLAUDE.md missing Perplexity indicator"
fi

# Test 7.2: CLAUDE.md has perplexity cost info
if grep -q 'Perplexity.*Sonar' "$PROJECT_ROOT/CLAUDE.md"; then
    pass "CLAUDE.md has Perplexity cost info"
else
    fail "CLAUDE.md missing Perplexity cost info"
fi

# Test 7.3: flow-discover.md includes perplexity
if grep -q '🟣.*Perplexity' "$PROJECT_ROOT/.claude/skills/flow-discover.md"; then
    pass "flow-discover.md has 🟣 Perplexity indicator"
else
    fail "flow-discover.md missing Perplexity indicator"
fi

# Test 7.4: embrace.md includes perplexity
if grep -q '🟣.*Perplexity' "$PROJECT_ROOT/.claude/commands/embrace.md"; then
    pass "embrace.md has 🟣 Perplexity indicator"
else
    fail "embrace.md missing Perplexity indicator"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 8: Functional Verification
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 8: Functional Verification"
echo "────────────────────────────────────────"

# Test 8.1: orchestrate.sh help still works
if "$ORCHESTRATE_SH" help >/dev/null 2>&1; then
    pass "orchestrate.sh help command works"
else
    fail "orchestrate.sh help command failed"
fi

# Test 8.2: mcp-provider-detection.sh runs without errors
if "$MCP_DETECT" detect-all cli 2>/dev/null | grep -q "perplexity"; then
    pass "mcp-provider-detection.sh outputs perplexity in JSON"
else
    fail "mcp-provider-detection.sh missing perplexity in output"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Final Summary
# ═══════════════════════════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_summary
