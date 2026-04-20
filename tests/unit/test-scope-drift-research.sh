#!/usr/bin/env bash
# Tests for Scope Drift Detection (CONSOLIDATED-05) and Research Report Template (CONSOLIDATED-08)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Scope Drift Detection (CONSOLIDATED-05) and Research Report Template (CONSOLIDATED-08)"


DELIVER="$PROJECT_ROOT/.claude/skills/flow-deliver.md"
RESEARCH="$PROJECT_ROOT/.claude/commands/research.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── Scope Drift Detection (removed from flow-deliver.md in v9.7+) ─────────────
# Scope drift detection was consolidated into the verification gate step.
# Tests below validate the remaining deliver verification gate.

if grep -qi 'Verify Execution\|Validation Gate' "$DELIVER" 2>/dev/null; then
    pass "Deliver has verification gate (scope drift consolidated)"
else
    fail "Deliver has verification gate" "missing verification step"
fi

# ── Research Report Template ──────────────────────────────────────────────────

if grep -qi 'Report Format' "$RESEARCH" 2>/dev/null; then
    pass "Research has Report Format section"
else
    fail "Research has Report Format section" "missing"
fi

if grep -qi 'Executive Summary' "$RESEARCH" 2>/dev/null; then
    pass "Template includes Executive Summary"
else
    fail "Template includes Executive Summary" "missing"
fi

if grep -qi 'Key Themes' "$RESEARCH" 2>/dev/null; then
    pass "Template includes Key Themes"
else
    fail "Template includes Key Themes" "missing"
fi

if grep -qi 'Key Takeaways' "$RESEARCH" 2>/dev/null; then
    pass "Template includes Key Takeaways"
else
    fail "Template includes Key Takeaways" "missing"
fi

if grep -qi 'Sources.*Attribution' "$RESEARCH" 2>/dev/null; then
    pass "Template includes Sources & Attribution"
else
    fail "Template includes Sources & Attribution" "missing"
fi

if grep -qi 'Methodology' "$RESEARCH" 2>/dev/null; then
    pass "Template includes Methodology"
else
    fail "Template includes Methodology" "missing"
fi

if grep -qi 'Inference\|unsourced' "$RESEARCH" 2>/dev/null; then
    pass "Requires source attribution (marks inferences)"
else
    fail "Requires source attribution" "missing inference tagging"
fi

if grep -qi 'gaps\|limitations' "$RESEARCH" 2>/dev/null; then
    pass "Acknowledges gaps and limitations"
else
    fail "Acknowledges gaps and limitations" "missing"
fi

# ── No attribution ────────────────────────────────────────────────────────────

if grep -qi 'gstack\|ecc\|gsd-2\|strategic-audit' "$DELIVER" 2>/dev/null; then
    fail "Deliver has no attribution" "found reference"
else
    pass "Deliver has no attribution"
fi

if grep -qi 'ecc\|strategic-audit\|autoresearch' "$RESEARCH" 2>/dev/null; then
    fail "Research has no attribution" "found reference"
else
    pass "Research has no attribution"
fi
test_summary
