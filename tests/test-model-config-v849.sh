#!/usr/bin/env bash
# Test suite for v8.49.0 model-config improvements
# Tests: cache key collision, cache invalidation, input validation,
#        resolution trace, atomic operations, provider whitelist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATE="${SCRIPT_DIR}/../scripts/orchestrate.sh"

PASSED=0
FAILED=0
TOTAL=0

pass() { ((PASSED++)); ((TOTAL++)); echo -e "\033[0;32m✓\033[0m $1"; }
fail() { ((FAILED++)); ((TOTAL++)); echo -e "\033[0;31m✗\033[0m $1"; }

echo "Testing Model Config v8.49.0 Improvements"
echo "==========================================="
echo ""

# ─── Test Group 1: Cache Key Collision Prevention ───────────────────────────

echo "Test Group 1: Cache Key Collision Prevention"
echo "---------------------------------------------"

# The old code used tr '[:punct:]' '_' which made codex+spark collide with codex-spark
# New code uses field-delimited keys: MC_<provider>_A_<type>_P_<phase>_R_<role>

# Verify the new cache key format is in the code
if grep -q 'MC_\${safe_p}_A_\${safe_a}_P_\${safe_ph}_R_\${safe_r}' "$ORCHESTRATE"; then
    pass "Cache key uses field-delimited format (MC_..._A_..._P_..._R_...)"
else
    fail "Cache key format not updated to field-delimited pattern"
fi

# Verify the old collision-prone pattern is removed
if grep -q "CACHE_\${provider}_\${agent_type}" "$ORCHESTRATE"; then
    fail "Old CACHE_ key pattern still present (collision-prone)"
else
    pass "Old CACHE_ collision-prone pattern removed"
fi

# Verify per-field sanitization variables exist
if grep -q 'safe_p="\${provider//\[^a-zA-Z0-9\]/_}"' "$ORCHESTRATE"; then
    pass "Per-field sanitization for cache keys present"
else
    fail "Missing per-field sanitization for cache keys"
fi

echo ""

# ─── Test Group 2: Cache Invalidation ──────────────────────────────────────

echo "Test Group 2: Cache Invalidation"
echo "---------------------------------"

# Verify config mtime check invalidates stale cache
if grep -q 'config_file.*-nt.*persistent_cache' "$ORCHESTRATE"; then
    pass "Config mtime check invalidates stale persistent cache"
else
    fail "Missing config mtime check for cache invalidation"
fi

# Verify set_provider_model clears cache
if grep -A 5 'Set default model' "$ORCHESTRATE" | grep -q 'rm -f.*persistent_cache\|rm -f.*octo-model-cache'; then
    pass "set_provider_model() clears model cache after change"
else
    fail "set_provider_model() does not clear cache after change"
fi

# Verify reset_provider_model clears cache (cache clearing is after the if/elif/fi block)
if grep -A 15 'Cleared all model overrides' "$ORCHESTRATE" | grep -q 'rm -f.*persistent_cache\|rm -f.*octo-model-cache'; then
    pass "reset_provider_model() clears model cache after reset"
else
    fail "reset_provider_model() does not clear cache after reset"
fi

# Verify migrate_provider_config clears cache
if grep -A 5 'Migration to v3.0 complete' "$ORCHESTRATE" | grep -q 'rm -f.*octo-model-cache'; then
    pass "migrate_provider_config() clears cache after migration"
else
    fail "migrate_provider_config() does not clear cache after migration"
fi

echo ""

# ─── Test Group 3: Input Validation Hardening ──────────────────────────────

echo "Test Group 3: Input Validation Hardening"
echo "-----------------------------------------"

# Verify jq --arg is used instead of string interpolation in set_provider_model
if grep -A 3 "atomic_json_update.*config_file" "$ORCHESTRATE" | grep -q '\-\-arg.*p.*provider.*\-\-arg.*m.*model'; then
    pass "set_provider_model() uses jq --arg for injection safety"
else
    fail "set_provider_model() not using jq --arg"
fi

# Verify provider whitelist exists
if grep -q 'codex|gemini|claude|perplexity|openrouter' "$ORCHESTRATE"; then
    pass "Provider whitelist validation present"
else
    fail "Provider whitelist validation missing"
fi

# Verify --force escape hatch for custom providers
if grep -q '\-\-force' "$ORCHESTRATE" && grep -q 'custom provider\|local prox' "$ORCHESTRATE"; then
    pass "--force flag available for custom/local providers"
else
    fail "--force escape hatch for custom providers missing"
fi

# Verify better error message for invalid model names
if grep -q 'shell metacharacters\|spaces.*quotes' "$ORCHESTRATE"; then
    pass "Enhanced error message explains invalid model name characters"
else
    fail "Error message for invalid model names not enhanced"
fi

# Verify jq --arg in migrate_provider_config stale model migration
if grep -B2 -A2 'Migrating stale model' "$ORCHESTRATE" | grep -q '\-\-arg val'; then
    pass "migrate_provider_config() uses jq --arg for stale model replacement"
else
    fail "migrate_provider_config() not using jq --arg for migration"
fi

# Verify --argjson for overrides merge
if grep -q '\-\-argjson ovr' "$ORCHESTRATE"; then
    pass "migrate_provider_config() uses --argjson for safe overrides merge"
else
    fail "migrate_provider_config() not using --argjson for overrides"
fi

echo ""

# ─── Test Group 4: Resolution Trace ───────────────────────────────────────

echo "Test Group 4: Resolution Trace (OCTOPUS_TRACE_MODELS)"
echo "------------------------------------------------------"

# Verify trace env var support
if grep -q 'OCTOPUS_TRACE_MODELS' "$ORCHESTRATE"; then
    pass "OCTOPUS_TRACE_MODELS env var supported"
else
    fail "OCTOPUS_TRACE_MODELS env var not found"
fi

# Verify trace header with provider/type/phase/role context
if grep -q '\[model-trace\] Resolving:' "$ORCHESTRATE"; then
    pass "Trace outputs resolution context header"
else
    fail "Trace missing resolution context header"
fi

# Count trace tier outputs (should have tiers 0.5 through 7)
trace_tiers=$(grep -c '\[model-trace\] Tier' "$ORCHESTRATE" 2>/dev/null || echo "0")
if [[ "$trace_tiers" -ge 7 ]]; then
    pass "Trace covers $trace_tiers+ precedence tiers"
else
    fail "Trace only covers $trace_tiers tiers (expected ≥7)"
fi

# Verify final result trace line
if grep -q '\[model-trace\] ► Result:' "$ORCHESTRATE"; then
    pass "Trace outputs final resolved model"
else
    fail "Trace missing final result output"
fi

# Verify trace goes to stderr (not stdout, to avoid polluting model name output)
if grep -q '\[model-trace\].*>&2' "$ORCHESTRATE"; then
    pass "Trace output goes to stderr (won't pollute model name)"
else
    fail "Trace output not directed to stderr"
fi

echo ""

# ─── Test Group 5: Atomic Operations ──────────────────────────────────────

echo "Test Group 5: Atomic JSON Operations"
echo "--------------------------------------"

# Verify atomic_json_update is used in set_provider_model
set_calls=$(grep -c 'atomic_json_update.*config_file' "$ORCHESTRATE" 2>/dev/null || echo "0")
if [[ "$set_calls" -ge 2 ]]; then
    pass "set_provider_model() uses atomic_json_update ($set_calls calls)"
else
    fail "set_provider_model() not using atomic_json_update (found $set_calls)"
fi

# Verify atomic_json_update is used in reset_provider_model
reset_calls=$(grep -A 20 'reset_provider_model()' "$ORCHESTRATE" | grep -c 'atomic_json_update' 2>/dev/null || echo "0")
if [[ "$reset_calls" -ge 2 ]]; then
    pass "reset_provider_model() uses atomic_json_update ($reset_calls calls)"
else
    fail "reset_provider_model() not using atomic_json_update (found $reset_calls)"
fi

# Verify no raw jq > tmp && mv pattern in set/reset functions
# (should all be using atomic_json_update now)
if grep -A 20 'set_provider_model()' "$ORCHESTRATE" | grep -q 'jq.*config_file.*>.*\.tmp.*&&.*mv'; then
    fail "set_provider_model() still has raw jq > tmp && mv pattern"
else
    pass "set_provider_model() no longer uses raw jq > tmp && mv"
fi

# Verify persistent cache write uses PID-safe temp file
if grep -q 'persistent_cache.*\.tmp\.\$\$' "$ORCHESTRATE"; then
    pass "Persistent cache write uses PID-safe temp file (.\$\$)"
else
    fail "Persistent cache write not using PID-safe temp file"
fi

echo ""

# ─── Test Group 6: Persistent Cache Safety ─────────────────────────────────

echo "Test Group 6: Persistent Cache Safety"
echo "---------------------------------------"

# Verify persistent cache uses jq --arg (not string interpolation)
if grep -q "jq --arg key.*--arg val.*persistent_cache" "$ORCHESTRATE"; then
    pass "Persistent cache write uses jq --arg (injection safe)"
else
    fail "Persistent cache write not using jq --arg"
fi

echo ""

# ─── Summary ──────────────────────────────────────────────────────────────

echo "==========================================="
echo "Test Summary"
echo "==========================================="
echo "Total tests: $TOTAL"
echo -e "\033[0;32mPassed: $PASSED\033[0m"
if [[ "$FAILED" -gt 0 ]]; then
    echo -e "\033[0;31mFailed: $FAILED\033[0m"
    exit 1
else
    echo "Failed: 0"
    echo ""
    echo -e "\033[0;32m✓ All v8.49.0 model-config tests passed!\033[0m"
fi
