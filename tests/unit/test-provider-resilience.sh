#!/usr/bin/env bash
# Tests for scripts/lib/resilience.sh — error classification, circuit breaker, retry
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$PROJECT_ROOT/scripts/lib/resilience.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }
assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "expected '$expected', got '$actual'"
  fi
}

# ── File existence and syntax ─────────────────────────────────────────────────

if [[ -f "$LIB" ]]; then
  pass "resilience.sh exists"
else
  fail "resilience.sh exists" "file not found"
  echo ""; echo "FAILURES: 1"; exit 1
fi

if bash -n "$LIB" 2>/dev/null; then
  pass "resilience.sh has valid bash syntax"
else
  fail "resilience.sh has valid bash syntax" "syntax error"
fi

# ── Source the library ────────────────────────────────────────────────────────

# Use a unique state dir so tests don't collide with real sessions
export CLAUDE_SESSION_ID="test-resilience-$$"
source "$LIB"

# Override state dir to a fresh temp location
TEST_STATE_DIR="/tmp/octopus-resilience-test-$$"
rm -rf "$TEST_STATE_DIR"
RESILIENCE_STATE_DIR="$TEST_STATE_DIR"

# ── classify_error: transient codes ──────────────────────────────────────────

assert_eq "$(classify_error 429)" "transient" "classify_error: 429 → transient"
assert_eq "$(classify_error 500)" "transient" "classify_error: 500 → transient"
assert_eq "$(classify_error 502)" "transient" "classify_error: 502 → transient"
assert_eq "$(classify_error 503)" "transient" "classify_error: 503 → transient"
assert_eq "$(classify_error 504)" "transient" "classify_error: 504 → transient"
assert_eq "$(classify_error 408)" "transient" "classify_error: 408 → transient"

# ── classify_error: permanent codes ──────────────────────────────────────────

assert_eq "$(classify_error 401)" "permanent" "classify_error: 401 → permanent"
assert_eq "$(classify_error 403)" "permanent" "classify_error: 403 → permanent"
assert_eq "$(classify_error 400)" "permanent" "classify_error: 400 → permanent"
assert_eq "$(classify_error 404)" "permanent" "classify_error: 404 → permanent"

# ── classify_error: text patterns ────────────────────────────────────────────

assert_eq "$(classify_error 'rate limit exceeded')" "transient" \
  "classify_error: 'rate limit exceeded' → transient"
assert_eq "$(classify_error 'Request timeout')" "transient" \
  "classify_error: 'Request timeout' → transient"
assert_eq "$(classify_error 'connection refused')" "transient" \
  "classify_error: 'connection refused' → transient"
assert_eq "$(classify_error 'Unauthorized access')" "permanent" \
  "classify_error: 'Unauthorized access' → permanent"
assert_eq "$(classify_error 'invalid key provided')" "permanent" \
  "classify_error: 'invalid key provided' → permanent"
assert_eq "$(classify_error 'some random error')" "unknown" \
  "classify_error: unknown text → unknown"

# ── Circuit breaker: starts closed ───────────────────────────────────────────

assert_eq "$(get_circuit_state 'test-provider')" "closed" \
  "circuit breaker starts closed for new provider"

# ── Circuit breaker: transient failures accumulate ───────────────────────────

record_failure "test-provider-a" "transient"
assert_eq "$(get_circuit_state 'test-provider-a')" "closed" \
  "1 transient failure: circuit stays closed"

record_failure "test-provider-a" "transient"
assert_eq "$(get_circuit_state 'test-provider-a')" "closed" \
  "2 transient failures: circuit stays closed"

record_failure "test-provider-a" "transient"
assert_eq "$(get_circuit_state 'test-provider-a')" "open" \
  "3 transient failures: circuit opens"

# ── Circuit breaker: permanent failure opens immediately ─────────────────────

record_failure "test-provider-b" "permanent"
assert_eq "$(get_circuit_state 'test-provider-b')" "open" \
  "1 permanent failure: circuit opens immediately"

# ── record_success resets circuit ────────────────────────────────────────────

record_success "test-provider-a"
assert_eq "$(get_circuit_state 'test-provider-a')" "closed" \
  "record_success resets circuit to closed"
assert_eq "$(get_failure_count 'test-provider-a')" "0" \
  "record_success resets failure count to 0"

# ── backoff_delay: exponential increase ──────────────────────────────────────

delay1=$(backoff_delay 1 1 30)
delay2=$(backoff_delay 2 1 30)
delay3=$(backoff_delay 3 1 30)

# With base=1: attempt 1 → 1+jitter, attempt 2 → 2+jitter, attempt 3 → 4+jitter
# Verify exponential growth (each delay's base is >= previous base)
if [[ $delay1 -ge 1 && $delay2 -ge 2 && $delay3 -ge 4 ]]; then
  pass "backoff_delay increases exponentially"
else
  fail "backoff_delay increases exponentially" "delays: $delay1, $delay2, $delay3"
fi

# Verify max cap
delay_high=$(backoff_delay 10 1 30)
if [[ $delay_high -le 38 ]]; then  # 30 + 25% jitter max
  pass "backoff_delay respects max cap"
else
  fail "backoff_delay respects max cap" "delay at attempt 10: $delay_high (max 30+jitter)"
fi

# ── is_provider_available: false when circuit open ───────────────────────────

record_failure "test-provider-c" "permanent"
if ! is_provider_available "test-provider-c"; then
  pass "is_provider_available returns false when circuit open"
else
  fail "is_provider_available returns false when circuit open" "returned true"
fi

# ── is_provider_available: true when circuit closed ──────────────────────────

if is_provider_available "test-provider-fresh"; then
  pass "is_provider_available returns true for fresh provider"
else
  fail "is_provider_available returns true for fresh provider" "returned false"
fi

# ── No attribution references ────────────────────────────────────────────────

lib_content=$(<"$LIB")
if echo "$lib_content" | grep -qiE 'gsd|temm1e'; then
  fail "no attribution references in resilience.sh" "found banned pattern"
else
  pass "no attribution references in resilience.sh"
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────

rm -rf "$TEST_STATE_DIR"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════"
echo "Results: $PASS_COUNT/$TEST_COUNT passed, $FAIL_COUNT failed"
echo "═══════════════════════════════════════════════════"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
