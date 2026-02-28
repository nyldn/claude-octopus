#!/usr/bin/env bash
# Test v8.24.0 Perplexity Provider Integration (Issue #22)
# Validates Perplexity Sonar as a web-grounded research provider

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE_SH="$PROJECT_ROOT/scripts/orchestrate.sh"
MCP_DETECT="$PROJECT_ROOT/scripts/mcp-provider-detection.sh"
STATE_MANAGER="$PROJECT_ROOT/scripts/state-manager.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}Testing v8.24.0 Perplexity Provider Integration (Issue #22)${NC}"
echo ""

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "${GREEN}  PASS${NC}: $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "${RED}  FAIL${NC}: $1"
    [[ -n "${2:-}" ]] && echo -e "   ${YELLOW}$2${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 1: orchestrate.sh - Agent Registration
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 1: Agent Registration"
echo "────────────────────────────────────────"

# Test 1.1: perplexity in AVAILABLE_AGENTS
if grep -q "perplexity" "$ORCHESTRATE_SH" && grep "AVAILABLE_AGENTS=" "$ORCHESTRATE_SH" | grep -q "perplexity"; then
    pass "perplexity in AVAILABLE_AGENTS"
else
    fail "perplexity NOT in AVAILABLE_AGENTS"
fi

# Test 1.2: perplexity-fast in AVAILABLE_AGENTS
if grep "AVAILABLE_AGENTS=" "$ORCHESTRATE_SH" | grep -q "perplexity-fast"; then
    pass "perplexity-fast in AVAILABLE_AGENTS"
else
    fail "perplexity-fast NOT in AVAILABLE_AGENTS"
fi

# Test 1.3: get_agent_command has perplexity case
if grep -A3 "perplexity|perplexity-fast" "$ORCHESTRATE_SH" | grep -q "perplexity_execute"; then
    pass "get_agent_command() handles perplexity"
else
    fail "get_agent_command() missing perplexity case"
fi

# Test 1.4: get_agent_model has perplexity defaults
if grep -q 'perplexity).*echo "sonar-pro"' "$ORCHESTRATE_SH"; then
    pass "get_agent_model() default: sonar-pro"
else
    fail "get_agent_model() missing sonar-pro default"
fi

if grep -q 'perplexity-fast).*echo "sonar"' "$ORCHESTRATE_SH"; then
    pass "get_agent_model() default: sonar (fast)"
else
    fail "get_agent_model() missing sonar default"
fi

# Test 1.5: perplexity provider in get_agent_model case
if grep -q 'perplexity|perplexity-fast)' "$ORCHESTRATE_SH" && grep -A1 'perplexity|perplexity-fast)' "$ORCHESTRATE_SH" | grep -q 'provider="perplexity"'; then
    pass "get_agent_model() maps perplexity to provider"
else
    fail "get_agent_model() provider mapping missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 2: orchestrate.sh - perplexity_execute Function
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 2: perplexity_execute Function"
echo "────────────────────────────────────────"

# Test 2.1: Function exists
if grep -q "^perplexity_execute()" "$ORCHESTRATE_SH"; then
    pass "perplexity_execute() function exists"
else
    fail "perplexity_execute() function NOT found"
fi

# Test 2.2: PERPLEXITY_API_KEY check
if grep -q 'PERPLEXITY_API_KEY' "$ORCHESTRATE_SH"; then
    pass "PERPLEXITY_API_KEY referenced"
else
    fail "PERPLEXITY_API_KEY not referenced"
fi

# Test 2.3: Uses Perplexity API endpoint
if grep -q "api.perplexity.ai" "$ORCHESTRATE_SH"; then
    pass "Uses api.perplexity.ai endpoint"
else
    fail "api.perplexity.ai endpoint missing"
fi

# Test 2.4: JSON payload with model
if grep -A20 "^perplexity_execute()" "$ORCHESTRATE_SH" | grep -q '"model"'; then
    pass "perplexity_execute sends model in payload"
else
    fail "perplexity_execute missing model in payload"
fi

# Test 2.5: Citations extraction
if grep -q "citations" "$ORCHESTRATE_SH"; then
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
if grep -q '"perplexity_execute"' "$ORCHESTRATE_SH"; then
    pass "perplexity_execute in command whitelist"
else
    fail "perplexity_execute NOT in command whitelist"
fi

# Test 3.2: Trust markers include perplexity
if grep -q 'codex\*|gemini\*|perplexity\*' "$ORCHESTRATE_SH"; then
    pass "Trust markers include perplexity*"
else
    fail "Trust markers missing perplexity"
fi

# Test 3.3: is_api_based_provider handles perplexity
if grep -q 'perplexity)' "$ORCHESTRATE_SH" && grep -B1 -A3 'perplexity)' "$ORCHESTRATE_SH" | grep -q 'PERPLEXITY_API_KEY'; then
    pass "is_api_based_provider() handles perplexity"
else
    fail "is_api_based_provider() missing perplexity"
fi

# Test 3.4: Model pricing for sonar models
if grep -q 'sonar-pro)' "$ORCHESTRATE_SH" && grep -q 'sonar)' "$ORCHESTRATE_SH"; then
    pass "Model pricing for sonar-pro and sonar"
else
    fail "Model pricing missing for sonar models"
fi

# Test 3.5: Environment isolation
if grep -q 'perplexity\*)' "$ORCHESTRATE_SH" && grep -A1 'perplexity\*)' "$ORCHESTRATE_SH" | grep -q 'PERPLEXITY_API_KEY'; then
    pass "build_provider_env() isolates Perplexity"
else
    fail "build_provider_env() missing perplexity isolation"
fi

# Test 3.6: OCTOPUS_PERPLEXITY_MODEL env var support
if grep -q 'OCTOPUS_PERPLEXITY_MODEL' "$ORCHESTRATE_SH"; then
    pass "OCTOPUS_PERPLEXITY_MODEL env var supported"
else
    fail "OCTOPUS_PERPLEXITY_MODEL env var missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 4: orchestrate.sh - Probe Discover Integration
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 4: Probe Discover Integration"
echo "────────────────────────────────────────"

# Test 4.1: Perplexity agent added to probe_discover
if grep -q 'probe_agents+=("perplexity")' "$ORCHESTRATE_SH"; then
    pass "Perplexity added to probe_agents in probe_discover()"
else
    fail "Perplexity NOT added to probe_agents"
fi

# Test 4.2: Web research perspective
if grep -q "Web Research" "$ORCHESTRATE_SH"; then
    pass "Web Research pane title present"
else
    fail "Web Research pane title missing"
fi

# Test 4.3: Conditional on PERPLEXITY_API_KEY
if grep -B5 'probe_agents+=("perplexity")' "$ORCHESTRATE_SH" | grep -q 'PERPLEXITY_API_KEY'; then
    pass "Perplexity agent conditional on API key"
else
    fail "Perplexity agent not gated on API key"
fi

# Test 4.4: Web-grounded research prompt
if grep -q "live web" "$ORCHESTRATE_SH" && grep -q "source URLs" "$ORCHESTRATE_SH"; then
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
echo -e "${BLUE}Test Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total tests:  ${BLUE}${TEST_COUNT}${NC}"
echo -e "Passed:       ${GREEN}${PASS_COUNT}${NC}"
echo -e "Failed:       ${RED}${FAIL_COUNT}${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All v8.24.0 Perplexity integration tests passed!${NC}"
    echo ""
    echo -e "${BLUE}Summary:${NC}"
    echo "  Perplexity Sonar added as 5th AI provider (🟣)"
    echo "  Models: sonar-pro (deep research), sonar (fast search)"
    echo "  Integrations: orchestrate.sh, mcp-provider-detection.sh, state-manager.sh"
    echo "  Security: trust markers, env isolation, command whitelist"
    echo "  Discover phase: auto-adds web search agent when PERPLEXITY_API_KEY set"
    echo ""
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
