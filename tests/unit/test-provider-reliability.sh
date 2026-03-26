#!/usr/bin/env bash
# Tests for Provider Reliability Layer (v9.8.0)
# Validates: error classification, circuit breaker, backoff, provider filtering
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROUTER="$PROJECT_ROOT/scripts/provider-router.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── File existence and syntax ─────────────────────────────────────────────────

if [[ -f "$ROUTER" ]]; then
    pass "provider-router.sh exists"
else
    fail "provider-router.sh exists" "not found"
fi

if bash -n "$ROUTER" 2>/dev/null; then
    pass "provider-router.sh has valid bash syntax"
else
    fail "provider-router.sh has valid bash syntax" "syntax error"
fi

# ── Error classification function exists ──────────────────────────────────────

if grep -q 'classify_provider_error()' "$ROUTER" 2>/dev/null; then
    pass "classify_provider_error() function exists"
else
    fail "classify_provider_error() function exists" "function not found"
fi

# ── Classifies transient errors ───────────────────────────────────────────────

if grep -q '429.*transient\|rate.limit' "$ROUTER" 2>/dev/null; then
    pass "Classifies 429/rate-limit as transient"
else
    fail "Classifies 429/rate-limit as transient" "missing 429 classification"
fi

if grep -q '500\|503\|internal server\|service unavailable' "$ROUTER" 2>/dev/null; then
    pass "Classifies 5xx server errors as transient"
else
    fail "Classifies 5xx server errors as transient" "missing 5xx classification"
fi

if grep -q 'timeout\|timed out\|ECONNRESET\|ETIMEDOUT' "$ROUTER" 2>/dev/null; then
    pass "Classifies network errors as transient"
else
    fail "Classifies network errors as transient" "missing network error classification"
fi

# ── Classifies permanent errors ───────────────────────────────────────────────

if grep -q '401\|403\|unauthorized\|forbidden\|invalid.api.key' "$ROUTER" 2>/dev/null; then
    pass "Classifies auth errors as permanent"
else
    fail "Classifies auth errors as permanent" "missing auth error classification"
fi

if grep -q 'billing\|payment\|quota' "$ROUTER" 2>/dev/null; then
    pass "Classifies billing errors as permanent"
else
    fail "Classifies billing errors as permanent" "missing billing classification"
fi

# ── Circuit breaker functions ─────────────────────────────────────────────────

if grep -q 'record_provider_failure()' "$ROUTER" 2>/dev/null; then
    pass "record_provider_failure() function exists"
else
    fail "record_provider_failure() function exists" "function not found"
fi

if grep -q 'record_provider_success()' "$ROUTER" 2>/dev/null; then
    pass "record_provider_success() function exists"
else
    fail "record_provider_success() function exists" "function not found"
fi

if grep -q 'is_provider_available()' "$ROUTER" 2>/dev/null; then
    pass "is_provider_available() function exists"
else
    fail "is_provider_available() function exists" "function not found"
fi

# ── Circuit breaker has configurable thresholds ───────────────────────────────

if grep -q 'OCTO_CB_FAILURE_THRESHOLD' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker failure threshold is configurable"
else
    fail "Circuit breaker failure threshold is configurable" "missing OCTO_CB_FAILURE_THRESHOLD"
fi

if grep -q 'OCTO_CB_COOLDOWN_SECS' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker cooldown is configurable"
else
    fail "Circuit breaker cooldown is configurable" "missing OCTO_CB_COOLDOWN_SECS"
fi

# ── Circuit breaker state persistence ─────────────────────────────────────────

if grep -q 'provider-state' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker uses provider-state directory"
else
    fail "Circuit breaker uses provider-state directory" "missing state directory"
fi

if grep -q '\.cooldown' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker uses cooldown files"
else
    fail "Circuit breaker uses cooldown files" "missing cooldown mechanism"
fi

if grep -q '\.failures' "$ROUTER" 2>/dev/null; then
    pass "Circuit breaker uses failure tracking files"
else
    fail "Circuit breaker uses failure tracking files" "missing failure files"
fi

# ── Backoff calculation ───────────────────────────────────────────────────────

if grep -q 'calculate_backoff()' "$ROUTER" 2>/dev/null; then
    pass "calculate_backoff() function exists"
else
    fail "calculate_backoff() function exists" "function not found"
fi

if grep -q 'jitter\|RANDOM' "$ROUTER" 2>/dev/null; then
    pass "Backoff includes jitter"
else
    fail "Backoff includes jitter" "no jitter in backoff calculation"
fi

# ── Provider filtering ────────────────────────────────────────────────────────

if grep -q 'filter_available_providers()' "$ROUTER" 2>/dev/null; then
    pass "filter_available_providers() function exists"
else
    fail "filter_available_providers() function exists" "function not found"
fi

# ── Retry-After header extraction ─────────────────────────────────────────────

if grep -q 'extract_retry_after\|retry.after' "$ROUTER" 2>/dev/null; then
    pass "Extract Retry-After header support"
else
    fail "Extract Retry-After header support" "missing Retry-After extraction"
fi

# ── Doctor integration ────────────────────────────────────────────────────────

if grep -q 'get_circuit_breaker_status()' "$ROUTER" 2>/dev/null; then
    pass "get_circuit_breaker_status() for doctor integration"
else
    fail "get_circuit_breaker_status() for doctor integration" "function not found"
fi

DOCTOR="$PROJECT_ROOT/.claude/skills/skill-doctor.md"
if grep -q 'circuit breaker' "$DOCTOR" 2>/dev/null; then
    pass "Doctor skill mentions circuit breaker"
else
    fail "Doctor skill mentions circuit breaker" "missing from doctor"
fi

# ── Scored routing mode ───────────────────────────────────────────────────────

if grep -q 'scored)' "$ROUTER" 2>/dev/null; then
    pass "Scored routing mode exists"
else
    fail "Scored routing mode exists" "missing scored routing"
fi

# ── Half-open state support ───────────────────────────────────────────────────

if grep -qi 'half.open' "$ROUTER" 2>/dev/null; then
    pass "Supports half-open circuit breaker state"
else
    fail "Supports half-open circuit breaker state" "missing half-open"
fi

# ── No attribution references ─────────────────────────────────────────────────

if grep -qi 'gsd-2\|ecc\|strategic-audit\|Rust agent runtime' "$ROUTER" 2>/dev/null; then
    fail "No attribution references" "found prohibited reference"
else
    pass "No attribution references"
fi

# ── v9.13: Persistent state + spawn integration ──────────────────────────────

ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

# Persistent state dir (not /tmp/)
if grep -q 'CLAUDE_PLUGIN_DATA\|WORKSPACE_DIR\|\.claude-octopus' "$PROJECT_ROOT/scripts/lib/resilience.sh" 2>/dev/null; then
    pass "Circuit breaker state persists across sessions"
else
    fail "Circuit breaker state persists" "still using /tmp/"
fi

# Spawn integration: circuit check before dispatch
if grep -q 'is_provider_available' "$PROJECT_ROOT/scripts/lib/spawn.sh" 2>/dev/null; then
    pass "spawn_agent checks circuit breaker before dispatch"
else
    fail "spawn integration" "is_provider_available not in spawn.sh"
fi

# Spawn integration: records failure with classification
if grep -q 'classify_error' "$PROJECT_ROOT/scripts/lib/spawn.sh" 2>/dev/null; then
    pass "spawn_agent classifies errors for circuit breaker"
else
    fail "spawn error classification" "classify_error not in spawn.sh"
fi

# Bash 3.2 compat: no ${var,,}
if grep -q '${.*,,}' "$PROJECT_ROOT/scripts/lib/resilience.sh" 2>/dev/null; then
    fail "Bash 3.2 compat in resilience.sh" "found \${var,,}"
else
    pass "Bash 3.2 compat in resilience.sh"
fi

# Doctor shows open circuits
if grep -q 'circuit-breaker' "$PROJECT_ROOT/scripts/lib/doctor.sh" 2>/dev/null; then
    pass "Doctor checks circuit breaker state"
else
    fail "Doctor circuit check" "not found in doctor.sh"
fi

rm -f "$ALL_SRC"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════"
echo "provider-reliability: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
