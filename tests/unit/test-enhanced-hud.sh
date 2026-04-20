#!/usr/bin/env bash
# test-enhanced-hud.sh - Static analysis tests for enhanced octopus-hud.mjs
# Tests async HUD with rate limits, agent trees, configurable columns, and v9.6.0 features
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "-enhanced-hud.sh - Static analysis tests for enhanced octopus-hud.mjs"

HUD_MJS="$PLUGIN_ROOT/hooks/octopus-hud.mjs"

PASS=0 FAIL=0

assert_pass() { ((PASS++)); echo "  ✓ $1"; }
assert_fail() { ((FAIL++)); echo "  ✗ $1"; }

echo "============================================================"
echo "Enhanced HUD Tests"
echo "============================================================"
echo ""

# ── Group 1: Core Rate Limit Functions (8 tests) ────────────────────────────
echo "Group 1: Core Rate Limit Functions"
echo "------------------------------------------------------------"

grep -q 'function getCredentials' "$HUD_MJS" && \
    assert_pass "1.1 getCredentials function exists" || \
    assert_fail "1.1 getCredentials function exists"

grep -q 'function fetchUsage' "$HUD_MJS" && \
    assert_pass "1.2 fetchUsage function exists" || \
    assert_fail "1.2 fetchUsage function exists"

grep -q 'async function getUsage' "$HUD_MJS" && \
    assert_pass "1.3 getUsage async orchestrator exists" || \
    assert_fail "1.3 getUsage async orchestrator exists"

grep -q 'function readUsageCache' "$HUD_MJS" && \
    assert_pass "1.4 readUsageCache function exists" || \
    assert_fail "1.4 readUsageCache function exists"

grep -q 'function writeUsageCache' "$HUD_MJS" && \
    assert_pass "1.5 writeUsageCache function exists" || \
    assert_fail "1.5 writeUsageCache function exists"

grep -q 'function refreshAccessToken' "$HUD_MJS" && \
    assert_pass "1.6 refreshAccessToken function exists" || \
    assert_fail "1.6 refreshAccessToken function exists"

grep -q 'OAUTH_CLIENT_ID' "$HUD_MJS" && \
    assert_pass "1.7 OAUTH_CLIENT_ID constant defined" || \
    assert_fail "1.7 OAUTH_CLIENT_ID constant defined"

grep -q 'CACHE_TTL_MS' "$HUD_MJS" && \
    assert_pass "1.8 CACHE_TTL_MS constant defined" || \
    assert_fail "1.8 CACHE_TTL_MS constant defined"

echo ""

# ── Group 2: Rate Limit Display (5 tests) ───────────────────────────────────
echo "Group 2: Rate Limit Display"
echo "------------------------------------------------------------"

grep -q 'function colorForPercent' "$HUD_MJS" && \
    assert_pass "2.1 colorForPercent function exists" || \
    assert_fail "2.1 colorForPercent function exists"

grep -q 'function formatResetTime' "$HUD_MJS" && \
    assert_pass "2.2 formatResetTime function exists" || \
    assert_fail "2.2 formatResetTime function exists"

grep -q '5h Usage' "$HUD_MJS" && \
    assert_pass "2.3 5h Usage column defined" || \
    assert_fail "2.3 5h Usage column defined"

grep -q '7d Usage' "$HUD_MJS" && \
    assert_pass "2.4 7d Usage column defined" || \
    assert_fail "2.4 7d Usage column defined"

# Tailwind 24-bit colors (Emerald-600, Amber-600, Red-600)
grep -q '38;2;5;150;105' "$HUD_MJS" && \
    assert_pass "2.5 Tailwind Emerald-600 color present" || \
    assert_fail "2.5 Tailwind Emerald-600 color present"

echo ""

# ── Group 3: Enhanced Features (6 tests) ────────────────────────────────────
echo "Group 3: Enhanced Features"
echo "------------------------------------------------------------"

grep -q 'function cacheHitRate' "$HUD_MJS" && \
    assert_pass "3.1 cacheHitRate function exists" || \
    assert_fail "3.1 cacheHitRate function exists"

# Gradient bar uses ▰▱ characters
grep -q '▰' "$HUD_MJS" && grep -q '▱' "$HUD_MJS" && \
    assert_pass "3.2 Gradient bar characters (▰▱) present" || \
    assert_fail "3.2 Gradient bar characters (▰▱) present"

grep -q 'function formatDuration' "$HUD_MJS" && \
    assert_pass "3.3 formatDuration function exists" || \
    assert_fail "3.3 formatDuration function exists"

grep -q 'function formatTokens' "$HUD_MJS" && \
    assert_pass "3.4 formatTokens function exists" || \
    assert_fail "3.4 formatTokens function exists"

grep -q 'function fetchLatestVersion' "$HUD_MJS" && \
    assert_pass "3.5 fetchLatestVersion function exists" || \
    assert_fail "3.5 fetchLatestVersion function exists"

grep -q 'async function parseTranscript' "$HUD_MJS" && \
    assert_pass "3.6 parseTranscript async function exists" || \
    assert_fail "3.6 parseTranscript async function exists"

echo ""

# ── Group 4: Octopus Functions Preserved (5 tests) ──────────────────────────
echo "Group 4: Octopus Functions Preserved"
echo "------------------------------------------------------------"

grep -q 'function readSession' "$HUD_MJS" && \
    assert_pass "4.1 readSession function preserved" || \
    assert_fail "4.1 readSession function preserved"

grep -q 'PHASE_EMOJI' "$HUD_MJS" && \
    assert_pass "4.2 PHASE_EMOJI mapping preserved" || \
    assert_fail "4.2 PHASE_EMOJI mapping preserved"

grep -q 'function providerIndicators' "$HUD_MJS" && \
    assert_pass "4.3 providerIndicators function preserved" || \
    assert_fail "4.3 providerIndicators function preserved"

grep -q 'function qualityGate' "$HUD_MJS" && \
    assert_pass "4.4 qualityGate function preserved" || \
    assert_fail "4.4 qualityGate function preserved"

# Context bridge writes to /tmp/octopus-ctx-
grep -q 'octopus-ctx-' "$HUD_MJS" && \
    assert_pass "4.5 Context bridge write preserved" || \
    assert_fail "4.5 Context bridge write preserved"

echo ""

# ── Group 5: Config System (3 tests) ────────────────────────────────────────
echo "Group 5: Config System"
echo "------------------------------------------------------------"

grep -q 'function readConfig' "$HUD_MJS" && \
    assert_pass "5.1 readConfig function exists" || \
    assert_fail "5.1 readConfig function exists"

grep -q 'function parseJsonc' "$HUD_MJS" && \
    assert_pass "5.2 parseJsonc function exists" || \
    assert_fail "5.2 parseJsonc function exists"

grep -q '.hud-config.jsonc' "$HUD_MJS" && \
    assert_pass "5.3 Config path uses .hud-config.jsonc" || \
    assert_fail "5.3 Config path uses .hud-config.jsonc"

echo ""

# ── Group 6: Layout Support (3 tests) ───────────────────────────────────────
echo "Group 6: Layout Support"
echo "------------------------------------------------------------"

grep -q 'function padAnsi' "$HUD_MJS" && \
    assert_pass "6.1 padAnsi function exists" || \
    assert_fail "6.1 padAnsi function exists"

grep -q 'function stripAnsi' "$HUD_MJS" && \
    assert_pass "6.2 stripAnsi function exists" || \
    assert_fail "6.2 stripAnsi function exists"

grep -q 'horizontal' "$HUD_MJS" && grep -q 'vertical' "$HUD_MJS" && \
    assert_pass "6.3 Horizontal and vertical layout support" || \
    assert_fail "6.3 Horizontal and vertical layout support"

echo ""

# ── Group 7: v9.6.0 Features Preserved (6 tests) ───────────────────────────
echo "Group 7: v9.6.0 Features Preserved"
echo "------------------------------------------------------------"

grep -q 'function readProgress' "$HUD_MJS" && \
    assert_pass "7.1 readProgress function preserved" || \
    assert_fail "7.1 readProgress function preserved"

grep -q '_progressCache' "$HUD_MJS" && \
    assert_pass "7.2 readProgress has cache for performance" || \
    assert_fail "7.2 readProgress has cache for performance"

grep -q 'function activeAgentName' "$HUD_MJS" && \
    assert_pass "7.3 activeAgentName function preserved" || \
    assert_fail "7.3 activeAgentName function preserved"

grep -q 'function readProjectState' "$HUD_MJS" && \
    assert_pass "7.4 readProjectState function preserved" || \
    assert_fail "7.4 readProjectState function preserved"

grep -q 'STATE.md' "$HUD_MJS" && \
    assert_pass "7.5 readProjectState reads .octo/STATE.md" || \
    assert_fail "7.5 readProjectState reads .octo/STATE.md"

grep -qE '1F480|💀' "$HUD_MJS" && \
    assert_pass "7.6 Skull emoji for >=90% context" || \
    assert_fail "7.6 Skull emoji for >=90% context"

echo ""

# ── Group 8: Cost Projection Integration (4 tests) ──────────────────────────
echo "Group 8: Cost Projection Integration"
echo "------------------------------------------------------------"

grep -q 'function costProjection' "$HUD_MJS" && \
    assert_pass "8.1 costProjection function exists" || \
    assert_fail "8.1 costProjection function exists"

grep -q 'completed_phases' "$HUD_MJS" && \
    assert_pass "8.2 costProjection reads completed_phases from session" || \
    assert_fail "8.2 costProjection reads completed_phases from session"

grep -q 'OCTO_BUDGET_CEILING' "$HUD_MJS" && \
    assert_pass "8.3 costProjection checks OCTO_BUDGET_CEILING env var" || \
    assert_fail "8.3 costProjection checks OCTO_BUDGET_CEILING env var"

grep -q 'costProjection(session' "$HUD_MJS" && \
    assert_pass "8.4 costProjection wired into workflow row render" || \
    assert_fail "8.4 costProjection wired into workflow row render"
test_summary
