#!/usr/bin/env bash
# Test v9.8.0 GitHub Copilot Provider Integration (Issue #198)
# Validates GitHub Copilot as a first-class provider in Claude Octopus

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE_SH="$PROJECT_ROOT/scripts/orchestrate.sh"
# v9.4.0: Support grepping across orchestrate.sh + lib/ for extracted functions
_ORCH_ALL_TMP=$(mktemp)
cat "$ORCHESTRATE_SH" "$PROJECT_ROOT/scripts/lib/"*.sh 2>/dev/null > "$_ORCH_ALL_TMP"
trap 'rm -f "$_ORCH_ALL_TMP"' EXIT
MCP_DETECT="$PROJECT_ROOT/scripts/mcp-provider-detection.sh"
STATE_MANAGER="$PROJECT_ROOT/scripts/state-manager.sh"
UTILS_SH="$PROJECT_ROOT/scripts/lib/utils.sh"
MODELS_SH="$PROJECT_ROOT/scripts/lib/models.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}Testing v9.8.0 GitHub Copilot Provider Integration (Issue #198)${NC}"
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
    [[ -n "${2:-}" ]] && echo -e "   ${YELLOW}$2${NC}" || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 1: Agent Registration
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 1: Agent Registration"
echo "────────────────────────────────────────"

# Test 1.1: copilot in AVAILABLE_AGENTS
if grep "AVAILABLE_AGENTS=" "$ORCHESTRATE_SH" | grep -q "copilot"; then
    pass "copilot in AVAILABLE_AGENTS"
else
    fail "copilot NOT in AVAILABLE_AGENTS"
fi

# Test 1.2: copilot-code in AVAILABLE_AGENTS
if grep "AVAILABLE_AGENTS=" "$ORCHESTRATE_SH" | grep -q "copilot-code"; then
    pass "copilot-code in AVAILABLE_AGENTS"
else
    fail "copilot-code NOT in AVAILABLE_AGENTS"
fi

# Test 1.3: copilot-research in AVAILABLE_AGENTS
if grep "AVAILABLE_AGENTS=" "$ORCHESTRATE_SH" | grep -q "copilot-research"; then
    pass "copilot-research in AVAILABLE_AGENTS"
else
    fail "copilot-research NOT in AVAILABLE_AGENTS"
fi

# Test 1.4: copilot-fast in AVAILABLE_AGENTS
if grep "AVAILABLE_AGENTS=" "$ORCHESTRATE_SH" | grep -q "copilot-fast"; then
    pass "copilot-fast in AVAILABLE_AGENTS"
else
    fail "copilot-fast NOT in AVAILABLE_AGENTS"
fi

# Test 1.5: get_agent_command handles copilot (may be in orchestrate.sh or lib/dispatch.sh)
if grep -A3 "copilot|copilot-code|copilot-research|copilot-fast" "$_ORCH_ALL_TMP" | grep -q "copilot_execute"; then
    pass "get_agent_command() handles copilot"
else
    fail "get_agent_command() missing copilot case"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 2: copilot_execute Function
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 2: copilot_execute Function"
echo "────────────────────────────────────────"

# Test 2.1: Function exists (may be in orchestrate.sh or lib/copilot.sh)
if grep -q "^copilot_execute()" "$_ORCH_ALL_TMP"; then
    pass "copilot_execute() function exists"
else
    fail "copilot_execute() function NOT found"
fi

# Test 2.2: Token exchange endpoint
if grep -q "api.github.com/copilot_internal/v2/token" "$_ORCH_ALL_TMP"; then
    pass "Uses GitHub Copilot token exchange endpoint"
else
    fail "Missing GitHub token exchange endpoint"
fi

# Test 2.3: Chat completions endpoint
if grep -q "api.githubcopilot.com/chat/completions" "$_ORCH_ALL_TMP"; then
    pass "Uses api.githubcopilot.com/chat/completions"
else
    fail "Missing GitHub Copilot chat completions endpoint"
fi

# Test 2.4: Role-based model selection
if grep -q "_copilot_role_model_preferences()" "$_ORCH_ALL_TMP"; then
    pass "Role-based model selection function exists"
else
    fail "_copilot_role_model_preferences() missing"
fi

# Test 2.5: Org policy fallback (tries multiple models)
if grep -q "try.*next\|trying next\|model_prefs\|model_prefs" "$_ORCH_ALL_TMP" && \
   grep -A5 "400.*403.*404\|HTTP.*400\|org policy" "$_ORCH_ALL_TMP" | grep -q "continue\|next"; then
    pass "Org policy fallback: tries next model on 400/403/404"
else
    fail "Org policy fallback missing (critical for org users)"
fi

# Test 2.6: Token caching
if grep -q "_copilot_get_token()" "$_ORCH_ALL_TMP" && \
   grep -A5 "_copilot_get_token" "$_ORCH_ALL_TMP" | grep -q "cache"; then
    pass "Token caching via _copilot_get_token()"
else
    fail "_copilot_get_token() or token caching missing"
fi

# Test 2.7: 401 token expiry handling
if grep -A5 "401" "$_ORCH_ALL_TMP" | grep -q "cache\|invalidate\|rm.*copilot\|copilot.*token"; then
    pass "401 handling: invalidates token cache"
else
    fail "401 token expiry handling missing"
fi

# Test 2.8: Rate limit (429) handling
if grep -A3 "429" "$_ORCH_ALL_TMP" | grep -q "Rate\|limit\|quota"; then
    pass "429 rate limit handling present"
else
    fail "429 rate limit handling missing"
fi

# Test 2.9: Role-model mapping includes GPT for code
if grep -A5 "copilot_role_model_preferences\|code.*implementation" "$_ORCH_ALL_TMP" | grep -q "gpt"; then
    pass "GPT preferred for code/implementation role"
else
    fail "GPT not mapped to code role"
fi

# Test 2.10: Role-model mapping includes Claude for research
if grep -A5 "research.*analysis.*plan\|research|copilot-research" "$_ORCH_ALL_TMP" | grep -q "claude"; then
    pass "Claude preferred for research/analysis/plan role"
else
    fail "Claude not mapped to research role"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 3: Security & Cost Integration
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 3: Security & Cost Integration"
echo "────────────────────────────────────────"

# Test 3.1: Command whitelist in utils.sh
if grep -q '"copilot_execute"' "$_ORCH_ALL_TMP"; then
    pass "copilot_execute in command whitelist"
else
    fail "copilot_execute NOT in command whitelist"
fi

# Test 3.2: Trust markers include copilot (may be in lib/ files)
if grep -q 'codex\*|gemini\*|perplexity\*|copilot\*' "$_ORCH_ALL_TMP"; then
    pass "Trust markers include copilot*"
else
    fail "Trust markers missing copilot"
fi

# Test 3.3: is_api_based_provider handles copilot (bundled = false)
# Use variable capture to avoid SIGPIPE with grep -q in pipelines (set -o pipefail)
_iapf_copilot=$(grep -A40 "^is_api_based_provider()" "$_ORCH_ALL_TMP" 2>/dev/null | grep -c "copilot" 2>/dev/null || echo 0)
_iapf_ret1=$(grep -A40 "^is_api_based_provider()" "$_ORCH_ALL_TMP" 2>/dev/null | grep -A5 "copilot)" 2>/dev/null | grep -c "return 1" 2>/dev/null || echo 0)
if [[ "$_iapf_copilot" -gt 0 && "$_iapf_ret1" -gt 0 ]]; then
    pass "is_api_based_provider() returns false for copilot (bundled subscription)"
else
    fail "is_api_based_provider() copilot handling missing or incorrect"
fi

# Test 3.4: Build provider env for copilot (GH_TOKEN isolation)
if grep -A5 "copilot\*)" "$_ORCH_ALL_TMP" | grep -q "GH_TOKEN\|GITHUB_TOKEN"; then
    pass "build_provider_env() isolates GH_TOKEN for Copilot"
else
    fail "build_provider_env() missing copilot isolation"
fi

# Test 3.5: Model pricing for copilot models (bundled = 0.00)
_copilot_pricing=$(grep -A2 "copilot-premium\|copilot-fast\|copilot-code\|copilot-research" "$_ORCH_ALL_TMP" 2>/dev/null | grep -c "0\.00" 2>/dev/null || echo 0)
if grep -q "copilot-premium\|copilot-fast" "$_ORCH_ALL_TMP" 2>/dev/null && [[ "$_copilot_pricing" -gt 0 ]]; then
    pass "Model pricing for copilot models: bundled (0.00)"
else
    fail "Model pricing missing for copilot models"
fi

# Test 3.6: OCTOPUS_COPILOT_ALLOWED_MODELS env var support
if grep -q 'OCTOPUS_COPILOT_ALLOWED_MODELS' "$_ORCH_ALL_TMP"; then
    pass "OCTOPUS_COPILOT_ALLOWED_MODELS model restriction supported"
else
    fail "OCTOPUS_COPILOT_ALLOWED_MODELS restriction missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 4: Provider Detection
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 4: Provider Detection"
echo "────────────────────────────────────────"

# Test 4.1: detect_providers() includes copilot (copilot added ~46 lines in; use -A60)
_dp_copilot=$(grep -A60 "^detect_providers()" "$ORCHESTRATE_SH" 2>/dev/null | grep -c "copilot" 2>/dev/null || echo 0)
if [[ "$_dp_copilot" -gt 0 ]]; then
    pass "detect_providers() includes copilot"
else
    fail "detect_providers() missing copilot"
fi

# Test 4.2: check_provider_health() handles copilot (may be in lib/providers.sh)
if grep -A80 "^check_provider_health()" "$_ORCH_ALL_TMP" | grep -q "copilot"; then
    pass "check_provider_health() includes copilot case"
else
    fail "check_provider_health() missing copilot health check"
fi

# Test 4.3: check_all_providers loop includes copilot
if grep -A10 "^check_all_providers()" "$_ORCH_ALL_TMP" | grep -q "copilot"; then
    pass "check_all_providers() loop includes copilot"
else
    fail "check_all_providers() loop missing copilot"
fi

# Test 4.4: copilot health check verifies gh auth
if grep -A80 "^check_provider_health()" "$_ORCH_ALL_TMP" | grep -A15 "copilot)" | grep -q "gh auth\|gh.*auth\|gh CLI"; then
    pass "copilot health check verifies gh auth"
else
    fail "copilot health check missing gh auth verification"
fi

# Test 4.5: _provider_for_health includes copilot (pre-dispatch health check)
if grep -A10 "_provider_for_health" "$_ORCH_ALL_TMP" | grep -q "copilot"; then
    pass "_provider_for_health includes copilot"
else
    fail "_provider_for_health missing copilot"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 5: Workflow Integration (probe_discover)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 5: Workflow Integration"
echo "────────────────────────────────────────"

# Test 5.1: probe_discover conditionally adds copilot agent (may be in lib/workflows.sh)
if grep -B5 'probe_agents+=.*"copilot' "$_ORCH_ALL_TMP" | grep -q "gh auth\|gh.*copilot\|copilot"; then
    pass "probe_discover() adds copilot agent when available"
else
    fail "probe_discover() missing copilot agent injection"
fi

# Test 5.2: Copilot perspective focuses on implementation
if grep -A2 'probe_agents+=.*"copilot' "$_ORCH_ALL_TMP" | grep -q "implementation\|code pattern\|developer\|Copilot"; then
    pass "Copilot probe perspective is implementation-focused"
else
    # Check the perspective text is nearby
    if grep -B10 'probe_agents+=.*"copilot' "$_ORCH_ALL_TMP" | grep -q "implementation\|code pattern\|developer\|programming assistant"; then
        pass "Copilot probe perspective is implementation-focused"
    else
        fail "Copilot probe perspective not implementation-focused"
    fi
fi

# Test 5.3: Copilot pane title uses 🟢 emoji
if grep -q '🟢.*Implementation\|🟢.*Copilot' "$_ORCH_ALL_TMP"; then
    pass "Copilot pane title uses 🟢 emoji"
else
    fail "Copilot pane title missing 🟢 emoji"
fi

# Test 5.4: Copilot probe is gated on availability check
if grep -B10 'probe_agents+=("copilot' "$_ORCH_ALL_TMP" | grep -q "command -v gh\|gh auth\|GH_TOKEN\|GITHUB_TOKEN"; then
    pass "Copilot probe gated on availability check"
else
    fail "Copilot probe not gated on availability"
fi

# Test 5.5: run_agent_sync _provider_for_health includes copilot
if grep -A10 "_provider_for_health" "$_ORCH_ALL_TMP" | grep -q "copilot"; then
    pass "run_agent_sync pre-dispatch health check includes copilot"
else
    fail "run_agent_sync missing copilot health check"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 6: MCP Provider Detection
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 6: MCP Provider Detection"
echo "────────────────────────────────────────"

# Test 6.1: detect_provider_cli handles copilot
if grep -A10 "detect_provider_cli" "$MCP_DETECT" | grep -q "copilot"; then
    pass "detect_provider_cli() handles copilot"
else
    fail "detect_provider_cli() missing copilot"
fi

# Test 6.2: Copilot detection checks gh auth
if grep -A15 "copilot)" "$MCP_DETECT" | grep -q "gh auth\|gh.*auth"; then
    pass "detect_provider_cli() checks gh auth for copilot"
else
    fail "detect_provider_cli() missing gh auth check"
fi

# Test 6.3: detect_all_providers includes copilot
if grep -q "copilot_status" "$MCP_DETECT"; then
    pass "detect_all_providers() tracks copilot_status"
else
    fail "detect_all_providers() missing copilot_status"
fi

# Test 6.4: JSON output includes copilot with 🟢
if grep -q '"copilot"' "$MCP_DETECT" && grep -q '"🟢"' "$MCP_DETECT"; then
    pass "JSON output includes copilot with 🟢 emoji"
else
    fail "JSON output missing copilot entry or 🟢 emoji"
fi

# Test 6.5: Banner includes copilot
if grep -q "copilot_display" "$MCP_DETECT"; then
    pass "get_provider_banner() includes copilot"
else
    fail "get_provider_banner() missing copilot"
fi

# Test 6.6: Usage text lists copilot
if grep -q "copilot" "$MCP_DETECT" | head -1 && grep 'Providers:' "$MCP_DETECT" | grep -q "copilot"; then
    pass "Usage text lists copilot provider"
else
    fail "Usage text missing copilot"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 7: State Manager
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 7: State Manager"
echo "────────────────────────────────────────"

# Test 7.1: provider_usage includes copilot
if grep -q '"copilot": 0' "$STATE_MANAGER"; then
    pass "provider_usage includes copilot: 0"
else
    fail "provider_usage missing copilot"
fi

# Test 7.2: Status display includes copilot
if grep -q 'Copilot:' "$STATE_MANAGER"; then
    pass "Status display shows Copilot usage"
else
    fail "Status display missing Copilot"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 8: Model Catalog (lib/models.sh)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 8: Model Catalog"
echo "────────────────────────────────────────"

# Test 8.1: copilot-premium in model catalog
if grep -q "copilot-premium" "$MODELS_SH"; then
    pass "copilot-premium in model catalog"
else
    fail "copilot-premium missing from model catalog"
fi

# Test 8.2: copilot-fast in model catalog
if grep -q "copilot-fast" "$MODELS_SH"; then
    pass "copilot-fast in model catalog"
else
    fail "copilot-fast missing from model catalog"
fi

# Test 8.3: copilot models in all_models list
if grep -A20 "all_models=(" "$MODELS_SH" | grep -q "copilot"; then
    pass "copilot models in all_models list"
else
    fail "copilot models missing from all_models list"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 9: Documentation
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 9: Documentation"
echo "────────────────────────────────────────"

# Test 9.1: CLAUDE.md has 🟢 Copilot indicator
if grep -q '🟢.*GitHub Copilot\|🟢.*Copilot' "$PROJECT_ROOT/CLAUDE.md"; then
    pass "CLAUDE.md has 🟢 GitHub Copilot indicator"
else
    fail "CLAUDE.md missing 🟢 Copilot indicator"
fi

# Test 9.2: CLAUDE.md has copilot cost info
if grep -q 'Copilot.*subscription\|Copilot.*bundled' "$PROJECT_ROOT/CLAUDE.md"; then
    pass "CLAUDE.md has Copilot cost info"
else
    fail "CLAUDE.md missing Copilot cost info"
fi

# Test 9.3: Provider config file exists
if [[ -f "$PROJECT_ROOT/config/providers/copilot/CLAUDE.md" ]]; then
    pass "config/providers/copilot/CLAUDE.md exists"
else
    fail "config/providers/copilot/CLAUDE.md missing"
fi

# Test 9.4: Provider config has role-based model info
if grep -q "role-based\|Role-Based\|GPT.*code\|Claude.*research" "$PROJECT_ROOT/config/providers/copilot/CLAUDE.md"; then
    pass "Copilot provider config documents role-based model selection"
else
    fail "Copilot provider config missing role-based model docs"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 10: Functional Verification
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 10: Functional Verification"
echo "────────────────────────────────────────"

# Test 10.1: orchestrate.sh syntax check
if bash -n "$ORCHESTRATE_SH" 2>/dev/null; then
    pass "orchestrate.sh syntax check passed"
else
    fail "orchestrate.sh has syntax errors"
fi

# Test 10.2: orchestrate.sh help still works
if "$ORCHESTRATE_SH" help >/dev/null 2>&1; then
    pass "orchestrate.sh help command works"
else
    fail "orchestrate.sh help command failed"
fi

# Test 10.3: mcp-provider-detection.sh runs without errors
if "$MCP_DETECT" detect-all cli 2>/dev/null | grep -q "copilot"; then
    pass "mcp-provider-detection.sh outputs copilot in JSON"
else
    fail "mcp-provider-detection.sh missing copilot in output"
fi

# Test 10.4: utils.sh syntax check
if bash -n "$UTILS_SH" 2>/dev/null; then
    pass "utils.sh syntax check passed"
else
    fail "utils.sh has syntax errors"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 10b: Dispatch Chain Model Resolution (Bug regression: role preservation)
# Verifies that get_agent_model preserves role-encoded agent types through Tier 7
# so that copilot_execute receives "copilot-code" (not "copilot-premium")
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 10b: Dispatch Chain Model Resolution"
echo "────────────────────────────────────────"

# Test 10b.1: copilot-code resolves to copilot-code (preserves role for GPT routing)
_resolved=$(bash -c 'source scripts/lib/utils.sh 2>/dev/null; source scripts/lib/models.sh 2>/dev/null; source scripts/orchestrate.sh 2>/dev/null; get_agent_model copilot-code' 2>/dev/null)
if [[ "$_resolved" == "copilot-code" ]]; then
    pass "get_agent_model(copilot-code) → 'copilot-code' (role preserved for GPT routing)"
else
    fail "get_agent_model(copilot-code) → '$_resolved' (expected 'copilot-code' — role lost!)" "Bug: role-based routing broken in dispatch chain"
fi

# Test 10b.2: copilot-research resolves to copilot-research (preserves role for Claude routing)
_resolved=$(bash -c 'source scripts/lib/utils.sh 2>/dev/null; source scripts/lib/models.sh 2>/dev/null; source scripts/orchestrate.sh 2>/dev/null; get_agent_model copilot-research' 2>/dev/null)
if [[ "$_resolved" == "copilot-research" ]]; then
    pass "get_agent_model(copilot-research) → 'copilot-research' (role preserved for Claude routing)"
else
    fail "get_agent_model(copilot-research) → '$_resolved' (expected 'copilot-research' — role lost!)"
fi

# Test 10b.3: copilot (bare) still resolves to copilot-premium (default)
_resolved=$(bash -c 'source scripts/lib/utils.sh 2>/dev/null; source scripts/lib/models.sh 2>/dev/null; source scripts/orchestrate.sh 2>/dev/null; get_agent_model copilot' 2>/dev/null)
if [[ "$_resolved" == "copilot-premium" ]]; then
    pass "get_agent_model(copilot) → 'copilot-premium' (default model)"
else
    fail "get_agent_model(copilot) → '$_resolved' (expected 'copilot-premium')"
fi

# Test 10b.4: copilot-fast still resolves to copilot-fast (budget model preserved)
_resolved=$(bash -c 'source scripts/lib/utils.sh 2>/dev/null; source scripts/lib/models.sh 2>/dev/null; source scripts/orchestrate.sh 2>/dev/null; get_agent_model copilot-fast' 2>/dev/null)
if [[ "$_resolved" == "copilot-fast" ]]; then
    pass "get_agent_model(copilot-fast) → 'copilot-fast' (budget model preserved)"
else
    fail "get_agent_model(copilot-fast) → '$_resolved' (expected 'copilot-fast')"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 11: Role Extraction Logic (Unit Tests)
# Verifies role string is correctly extracted from agent_type model name
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 11: Role Extraction Logic"
echo "────────────────────────────────────────"

_extract_role() {
    local model="$1"
    local role="${model#copilot-}"
    [[ "$role" == "premium" || "$role" == "copilot" ]] && role=""
    echo "$role"
}

# Test 11.1: "copilot" (bare) → role="" (uses model_preferences path)
_r=$(_extract_role "copilot")
if [[ "$_r" == "" ]]; then
    pass "copilot (bare) → role='' (uses _copilot_model_preferences)"
else
    fail "copilot (bare) → role='$_r' (expected '')"
fi

# Test 11.2: "copilot-premium" → role="" (same as bare copilot)
_r=$(_extract_role "copilot-premium")
if [[ "$_r" == "" ]]; then
    pass "copilot-premium → role='' (uses _copilot_model_preferences)"
else
    fail "copilot-premium → role='$_r' (expected '')"
fi

# Test 11.3: "copilot-code" → role="code"
_r=$(_extract_role "copilot-code")
if [[ "$_r" == "code" ]]; then
    pass "copilot-code → role='code'"
else
    fail "copilot-code → role='$_r' (expected 'code')"
fi

# Test 11.4: "copilot-research" → role="research"
_r=$(_extract_role "copilot-research")
if [[ "$_r" == "research" ]]; then
    pass "copilot-research → role='research'"
else
    fail "copilot-research → role='$_r' (expected 'research')"
fi

# Test 11.5: "copilot-fast" → role="fast"
_r=$(_extract_role "copilot-fast")
if [[ "$_r" == "fast" ]]; then
    pass "copilot-fast → role='fast'"
else
    fail "copilot-fast → role='$_r' (expected 'fast')"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 12: Role-Model Mapping Correctness (Executable Unit Tests)
# Extracts and executes the mapping functions to verify correct first-choice model
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 12: Role-Model Mapping Correctness"
echo "────────────────────────────────────────"

# Source both functions from orchestrate.sh + lib/*.sh into a temp file using awk (handles any size)
_fn_tmp=$(mktemp)
awk '/^_copilot_role_model_preferences\(\)/{found=1} found{print; if(/^\}$/) {found=0}}' "$_ORCH_ALL_TMP" >> "$_fn_tmp"
awk '/^_copilot_model_preferences\(\)/{found=1} found{print; if(/^\}$/) {found=0}}' "$_ORCH_ALL_TMP" >> "$_fn_tmp"
# shellcheck disable=SC1090
source "$_fn_tmp"
rm -f "$_fn_tmp"

# Test 12.1: code role → gpt-4.1 is first preference
_first=$(( _copilot_role_model_preferences "code" ) | awk '{print $1}')
if [[ "$_first" == "gpt-4.1" ]]; then
    pass "code role → gpt-4.1 first (GPT excels at implementation)"
else
    fail "code role → '$_first' first (expected gpt-4.1)"
fi

# Test 12.2: implementation role → gpt-4.1 is first preference (alias for code)
_first=$(( _copilot_role_model_preferences "implementation" ) | awk '{print $1}')
if [[ "$_first" == "gpt-4.1" ]]; then
    pass "implementation role → gpt-4.1 first (same as code)"
else
    fail "implementation role → '$_first' first (expected gpt-4.1)"
fi

# Test 12.3: research role → claude-3.7-sonnet is first preference
_first=$(( _copilot_role_model_preferences "research" ) | awk '{print $1}')
if [[ "$_first" == "claude-3.7-sonnet" ]]; then
    pass "research role → claude-3.7-sonnet first (Claude excels at research)"
else
    fail "research role → '$_first' first (expected claude-3.7-sonnet)"
fi

# Test 12.4: analysis role → claude-3.7-sonnet first (alias for research)
_first=$(( _copilot_role_model_preferences "analysis" ) | awk '{print $1}')
if [[ "$_first" == "claude-3.7-sonnet" ]]; then
    pass "analysis role → claude-3.7-sonnet first"
else
    fail "analysis role → '$_first' first (expected claude-3.7-sonnet)"
fi

# Test 12.5: refactor role → gemini-2.0-flash first (Gemini→refactor mapping)
_first=$(( _copilot_role_model_preferences "refactor" ) | awk '{print $1}')
if [[ "$_first" == "gemini-2.0-flash" ]]; then
    pass "refactor role → gemini-2.0-flash first (Gemini handles structured refactoring)"
else
    fail "refactor role → '$_first' first (expected gemini-2.0-flash)"
fi

# Test 12.6: review role → gemini-2.0-flash first
_first=$(( _copilot_role_model_preferences "review" ) | awk '{print $1}')
if [[ "$_first" == "gemini-2.0-flash" ]]; then
    pass "review role → gemini-2.0-flash first"
else
    fail "review role → '$_first' first (expected gemini-2.0-flash)"
fi

# Test 12.7: fast role → o3-mini first (budget preference)
_first=$(( _copilot_role_model_preferences "fast" ) | awk '{print $1}')
if [[ "$_first" == "o3-mini" ]]; then
    pass "fast role → o3-mini first (budget/fast model)"
else
    fail "fast role → '$_first' first (expected o3-mini)"
fi

# Test 12.8: unknown role → gpt-4.1 first (default fallback)
_first=$(( _copilot_role_model_preferences "unknown-xyz" ) | awk '{print $1}')
if [[ "$_first" == "gpt-4.1" ]]; then
    pass "unknown role → gpt-4.1 first (default fallback)"
else
    fail "unknown role → '$_first' first (expected gpt-4.1 default)"
fi

# Test 12.9: copilot-fast model → o3-mini first
_first=$(( _copilot_model_preferences "copilot-fast" ) | awk '{print $1}')
if [[ "$_first" == "o3-mini" ]]; then
    pass "copilot-fast model → o3-mini first (reasoning model for budget)"
else
    fail "copilot-fast model → '$_first' first (expected o3-mini)"
fi

# Test 12.10: copilot-premium model → gpt-4.1 first (default all-rounder)
_first=$(( _copilot_model_preferences "copilot-premium" ) | awk '{print $1}')
if [[ "$_first" == "gpt-4.1" ]]; then
    pass "copilot-premium model → gpt-4.1 first (best all-rounder)"
else
    fail "copilot-premium model → '$_first' first (expected gpt-4.1)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 13: Security Hardening (grep-based)
# Verifies critical security properties of the Copilot implementation
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 13: Security Hardening"
echo "────────────────────────────────────────"

# Test 13.1: umask 177 used when creating cache file (yields 600 perms)
if grep -q "umask 177" "$_ORCH_ALL_TMP"; then
    pass "umask 177 used for cache file creation (600 permissions)"
else
    fail "umask 177 missing — token cache file may have insecure permissions"
fi

# Test 13.2: GitHub OAuth token exchange uses 'Authorization: token' (not Bearer)
# Header appears before the URL in the curl call, so use -B (before context)
if grep -B5 "copilot_internal/v2/token" "$_ORCH_ALL_TMP" | grep -q "Authorization: token"; then
    pass "Token exchange uses 'Authorization: token' (correct GitHub OAuth format)"
else
    fail "Token exchange missing correct 'Authorization: token' header"
fi

# Test 13.3: Copilot API calls use 'Authorization: Bearer' (JWT format)
if grep -A5 "api.githubcopilot.com/chat/completions" "$_ORCH_ALL_TMP" | grep -q "Authorization: Bearer"; then
    pass "Copilot API calls use 'Authorization: Bearer' (correct JWT format)"
else
    fail "Copilot API calls missing 'Authorization: Bearer' header"
fi

# Test 13.4: curl has --max-time timeout (prevents indefinite hangs)
if grep -A15 "api.githubcopilot.com/chat/completions" "$_ORCH_ALL_TMP" | grep -q "\-\-max-time"; then
    pass "curl --max-time present (prevents indefinite hang)"
else
    fail "curl missing --max-time — requests could hang forever"
fi

# Test 13.5: 401 cache invalidation uses '|| true' (rm failure doesn't abort)
if grep -q "rm -f.*copilot-token.*|| true\||| true.*rm.*copilot-token" "$_ORCH_ALL_TMP"; then
    pass "401 cache rm uses '|| true' (failure-safe invalidation)"
else
    fail "401 cache rm missing '|| true' — rm failure could abort function"
fi

# Test 13.6: Cache file path uses ${USER:-...} fallback (safe when USER unset)
if grep -q 'copilot-token-\${USER:-' "$_ORCH_ALL_TMP"; then
    pass "Cache path uses \${USER:-...} fallback (safe in restricted envs)"
else
    fail "Cache path missing USER fallback"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 14: Edge Cases & Resilience
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 14: Edge Cases & Resilience"
echo "────────────────────────────────────────"

# Test 14.1: Cross-platform stat: Linux (-c %Y) fallback present
if grep -A5 "_copilot_get_token\|age_s=" "$_ORCH_ALL_TMP" | grep -q "stat -c %Y"; then
    pass "Cross-platform stat: Linux '-c %Y' present"
else
    fail "Linux stat format (-c %Y) missing from cache age check"
fi

# Test 14.2: Cross-platform stat: macOS (-f %m) fallback present
if grep -A5 "_copilot_get_token\|age_s=" "$_ORCH_ALL_TMP" | grep -q "stat -f %m"; then
    pass "Cross-platform stat: macOS '-f %m' fallback present"
else
    fail "macOS stat format (-f %m) missing from cache age check"
fi

# Test 14.3: stat failure fallback to echo 0 (stale cache → re-fetch)
if grep -A5 "age_s=" "$_ORCH_ALL_TMP" | grep -q "|| echo 0"; then
    pass "stat failure falls back to echo 0 (treats cache as stale — re-fetch)"
else
    fail "stat failure fallback (echo 0) missing — could cause arithmetic error"
fi

# Test 14.4: Exhausted models → error mentions 'org policy'
if grep -A3 "All model preferences exhausted\|models available" "$_ORCH_ALL_TMP" | grep -q "org\|policy\|Org"; then
    pass "Exhausted fallback error message mentions 'org policy'"
else
    fail "Exhausted fallback error missing 'org policy' context for users"
fi

# Test 14.5: 200 response with empty content → loop continues (no early return)
# Verify: after json_extract succeeds, code checks [[ -n "$content" ]] before returning
if grep -A8 'http_code.*==.*"200"' "$_ORCH_ALL_TMP" | grep -q '\[\[ -n.*content'; then
    pass "200 with empty content → tries next model (no premature return)"
else
    fail "Empty 200 response handling may return early with empty output"
fi

# Test 14.6: cache TTL is 5400 seconds (90 minutes — conservative vs ~3h token lifetime)
if grep -q "age_s -lt 5400\|-lt 5400" "$_ORCH_ALL_TMP"; then
    pass "Token cache TTL = 5400s (90 min) — conservative, safely below ~3h token lifetime"
else
    fail "Cache TTL value (5400s/90min) not found"
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
    echo -e "${GREEN}All v9.8.0 GitHub Copilot integration tests passed!${NC}"
    echo ""
    echo -e "${BLUE}Summary:${NC}"
    echo "  GitHub Copilot added as 6th AI provider (🟢)"
    echo "  Agent types: copilot, copilot-code, copilot-research, copilot-fast"
    echo "  Role-based dynamic model selection (GPT→code, Claude→research, Gemini→refactor)"
    echo "  Org policy graceful fallback (tries next model on 400/403/404)"
    echo "  Token caching via _copilot_get_token() (~90 min cache)"
    echo "  Cost: bundled (not pay-per-token)"
    echo "  probe_discover() integration: auto-injects implementation perspective"
    echo "  Security: trust markers, env isolation (GH_TOKEN), command whitelist"
    echo ""
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
