#!/usr/bin/env bash
# Tests for /octo:prd-score command file integrity
# Validates: file exists, frontmatter with arguments, scoring categories, grade scale, registration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "/octo:prd-score command file integrity"

CMD_FILE="$PROJECT_ROOT/.claude/commands/prd-score.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── 1. File exists ──────────────────────────────────────────────────
if [[ -f "$CMD_FILE" ]]; then
    pass "prd-score.md exists"
else
    fail "prd-score.md exists" "file not found at $CMD_FILE"
fi

# ── 2. YAML frontmatter uses 'command:' field ───────────────────────
if head -1 "$CMD_FILE" | grep -q "^---$"; then
    if grep -c "^command: prd-score" "$CMD_FILE" >/dev/null 2>&1; then
        pass "frontmatter has command: prd-score"
    else
        fail "frontmatter has command: prd-score" "missing or incorrect command field"
    fi
else
    fail "frontmatter has command: prd-score" "no YAML frontmatter found"
fi

# ── 3. Has arguments field in frontmatter ────────────────────────────
if grep -c "^arguments:" "$CMD_FILE" >/dev/null 2>&1; then
    pass "frontmatter has arguments field"
else
    fail "frontmatter has arguments field" "prd-score requires a file argument"
fi

# ── 4. Scoring categories A-D ───────────────────────────────────────
for category in "Category A" "Category B" "Category C" "Category D"; do
    if grep -c "$category" "$CMD_FILE" >/dev/null 2>&1; then
        pass "scoring category: $category"
    else
        fail "scoring category: $category" "missing from command file"
    fi
done

# ── 5. 100-point reference ──────────────────────────────────────────
if grep -c "100-point" "$CMD_FILE" >/dev/null 2>&1; then
    pass "references 100-point framework"
else
    fail "references 100-point framework" "missing 100-point scoring reference"
fi

# ── 6. Grade scale ──────────────────────────────────────────────────
if grep -c "Grade Scale" "$CMD_FILE" >/dev/null 2>&1; then
    pass "contains Grade Scale"
else
    fail "contains Grade Scale" "missing Grade Scale definition"
fi

# ── 7. Category point totals sum to 100 ─────────────────────────────
# Verify via static content - categories mention 25, 25, 30, 20
if grep -c "25 points" "$CMD_FILE" >/dev/null 2>&1 && grep -c "30 points" "$CMD_FILE" >/dev/null 2>&1 && grep -c "20 points" "$CMD_FILE" >/dev/null 2>&1; then
    pass "category point totals present (25+25+30+20=100)"
else
    fail "category point totals present" "expected 25+25+30+20=100 points across categories"
fi

# ── 8. Registered in plugin.json ─────────────────────────────────────
if grep -c "prd-score.md" "$PLUGIN_JSON" >/dev/null 2>&1; then
    pass "registered in plugin.json"
else
    fail "registered in plugin.json" "prd-score.md not found in plugin.json"
fi
test_summary
