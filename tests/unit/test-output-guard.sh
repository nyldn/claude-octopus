#!/usr/bin/env bash
# Tests for guard_output() function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "guard_output() function"

SECURE="$PROJECT_ROOT/scripts/lib/secure.sh"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── guard_output function exists ────────────────────────────────────

if grep -q '^guard_output()' "$SECURE" 2>/dev/null; then
    pass "guard_output() defined in secure.sh"
else
    fail "guard_output() defined in secure.sh" "function not found"
fi

# ── guard_output has max_bytes threshold ────────────────────────────

if grep -A5 'guard_output()' "$SECURE" | grep -q 'max_bytes' 2>/dev/null; then
    pass "guard_output has max_bytes threshold"
else
    fail "guard_output has max_bytes threshold" "missing max_bytes"
fi

# ── guard_output uses secure_tempfile ───────────────────────────────

if grep -A15 'guard_output()' "$SECURE" | grep -q 'secure_tempfile' 2>/dev/null; then
    pass "guard_output uses secure_tempfile for overflow"
else
    fail "guard_output uses secure_tempfile for overflow" "missing secure_tempfile call"
fi

# ── guard_output has @file: pointer pattern ─────────────────────────

if grep -A50 'guard_output()' "$SECURE" | grep -q '@file:' 2>/dev/null; then
    pass "guard_output emits @file: pointer for oversize content"
else
    fail "guard_output emits @file: pointer for oversize content" "missing @file: pattern"
fi

# ── guard_output wired into aggregate_results ───────────────────────

if grep -c 'guard_output' <(grep -A200 'aggregate_results()' "$ALL_SRC" | head -200) >/dev/null 2>&1; then
    pass "guard_output wired into aggregate_results()"
else
    fail "guard_output wired into aggregate_results()" "not found in function body"
fi

# ── guard_output wired into synthesize_probe_results ────────────────

if grep -c 'guard_output' <(grep -A150 'synthesize_probe_results()' "$ALL_SRC" | head -200) >/dev/null 2>&1; then
    pass "guard_output wired into synthesize_probe_results()"
else
    fail "guard_output wired into synthesize_probe_results()" "not found in function body"
fi
test_summary
