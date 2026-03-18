#!/usr/bin/env bash
# Tests for guard_output() function in lib/utils.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS="$PROJECT_ROOT/scripts/lib/utils.sh"
ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── guard_output function exists in utils.sh ────────────────────────────────

if grep -q '^guard_output()' "$UTILS" 2>/dev/null; then
    pass "guard_output() defined in utils.sh"
else
    fail "guard_output() defined in utils.sh" "function not found"
fi

# ── guard_output has max_bytes threshold ────────────────────────────────────

if grep -A5 'guard_output()' "$UTILS" | grep -q 'max_bytes' 2>/dev/null; then
    pass "guard_output has max_bytes threshold"
else
    fail "guard_output has max_bytes threshold" "missing max_bytes"
fi

# ── guard_output uses secure_tempfile ───────────────────────────────────────

if grep -A15 'guard_output()' "$UTILS" | grep -q 'secure_tempfile' 2>/dev/null; then
    pass "guard_output uses secure_tempfile for overflow"
else
    fail "guard_output uses secure_tempfile for overflow" "missing secure_tempfile call"
fi

# ── guard_output has @file: pointer pattern ─────────────────────────────────

if grep -A15 'guard_output()' "$UTILS" | grep -q '@file:' 2>/dev/null; then
    pass "guard_output emits @file: pointer for oversize content"
else
    fail "guard_output emits @file: pointer for oversize content" "missing @file: pattern"
fi

# ── guard_output wired into aggregate_results ───────────────────────────────

if grep -A200 'aggregate_results()' "$ORCHESTRATE" | head -120 | grep -q 'guard_output' 2>/dev/null; then
    pass "guard_output wired into aggregate_results()"
else
    fail "guard_output wired into aggregate_results()" "not found in function body"
fi

# ── guard_output wired into synthesize_probe_results ────────────────────────

if grep -A150 'synthesize_probe_results()' "$ORCHESTRATE" | head -130 | grep -q 'guard_output' 2>/dev/null; then
    pass "guard_output wired into synthesize_probe_results()"
else
    fail "guard_output wired into synthesize_probe_results()" "not found in function body"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "output-guard: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
