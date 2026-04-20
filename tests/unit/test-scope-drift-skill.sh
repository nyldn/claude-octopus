#!/usr/bin/env bash
# Tests for Scope Drift Detection Skill
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Scope Drift Detection Skill"


SCOPE_SKILL="$PLUGIN_ROOT/skills/skill-scope-drift/SKILL.md"
DELIVER_SKILL="$PLUGIN_ROOT/skills/flow-deliver/SKILL.md"
REVIEW_SKILL="$PLUGIN_ROOT/skills/skill-code-review/SKILL.md"
REVIEW_CMD="$PLUGIN_ROOT/commands/octo-review.md"

passed=0
failed=0

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

echo "=== Scope Drift Detection Skill Tests ==="
echo ""

# ── Skill file exists ────────────────────────────────────────────────────────
echo "── File existence ──"
[[ -f "$SCOPE_SKILL" ]] && pass "Skill file exists" || fail "Skill file exists" "missing"

# ── Frontmatter ──────────────────────────────────────────────────────────────
echo "── Frontmatter ──"
if head -5 "$SCOPE_SKILL" | grep -q 'name: skill-scope-drift'; then
    pass "Has correct skill name in frontmatter"
else
    fail "Has correct skill name in frontmatter" "missing"
fi

# ── Core features ────────────────────────────────────────────────────────────
echo "── Core features ──"
if grep -qi 'TODOS.md' "$SCOPE_SKILL" 2>/dev/null; then
    pass "Reads TODOS.md as intent source"
else
    fail "Reads TODOS.md as intent source" "not mentioned"
fi

if grep -qi 'PR description\|PR body\|pr view' "$SCOPE_SKILL" 2>/dev/null; then
    pass "Reads PR description as intent source"
else
    fail "Reads PR description as intent source" "not mentioned"
fi

if grep -qi 'commit messages\|git log' "$SCOPE_SKILL" 2>/dev/null; then
    pass "Reads commit messages as intent source"
else
    fail "Reads commit messages as intent source" "not mentioned"
fi

if grep -qi 'scope creep' "$SCOPE_SKILL" 2>/dev/null; then
    pass "Detects scope creep"
else
    fail "Detects scope creep" "not mentioned"
fi

if grep -qi 'missing requirements' "$SCOPE_SKILL" 2>/dev/null; then
    pass "Detects missing requirements"
else
    fail "Detects missing requirements" "not mentioned"
fi

if grep -qi 'informational\|never blocks' "$SCOPE_SKILL" 2>/dev/null; then
    pass "Marked as informational (non-blocking)"
else
    fail "Marked as informational (non-blocking)" "not mentioned"
fi

if grep -qi 'CLEAN\|DRIFT DETECTED\|REQUIREMENTS MISSING' "$SCOPE_SKILL" 2>/dev/null; then
    pass "Outputs structured status values"
else
    fail "Outputs structured status values" "missing status values"
fi

# ── Integration points ───────────────────────────────────────────────────────
echo "── Integration ──"
if grep -qi 'scope drift\|scope-drift\|skill-scope-drift' "$DELIVER_SKILL" 2>/dev/null; then
    pass "Referenced in flow-deliver"
else
    fail "Referenced in flow-deliver" "not integrated"
fi

if grep -qi 'scope drift\|scope-drift\|skill-scope-drift' "$REVIEW_SKILL" 2>/dev/null; then
    pass "Referenced in skill-code-review"
else
    fail "Referenced in skill-code-review" "not integrated"
fi

if grep -qi 'scope drift\|scope-drift' "$REVIEW_CMD" 2>/dev/null; then
    pass "Referenced in octo-review command"
else
    fail "Referenced in octo-review command" "not integrated"
fi
test_summary
