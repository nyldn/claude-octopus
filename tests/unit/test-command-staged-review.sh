#!/usr/bin/env bash
# Tests for /octo:staged-review command file integrity
# Validates: file exists, frontmatter, no broken refs, compliance block, skill reference, registration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "/octo:staged-review command file integrity"

CMD_FILE="$PROJECT_ROOT/.claude/commands/staged-review.md"
SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-staged-review.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"
COMMANDS_DIR="$PROJECT_ROOT/.claude/commands"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── 1. File exists ──────────────────────────────────────────────────
if [[ -f "$CMD_FILE" ]]; then
    pass "staged-review.md exists"
else
    fail "staged-review.md exists" "file not found at $CMD_FILE"
fi

# ── 2. YAML frontmatter uses 'command:' field ───────────────────────
if head -1 "$CMD_FILE" | grep -q "^---$"; then
    if grep -c "^command: staged-review" "$CMD_FILE" >/dev/null 2>&1; then
        pass "frontmatter has command: staged-review"
    else
        fail "frontmatter has command: staged-review" "missing or incorrect command field"
    fi
else
    fail "frontmatter has command: staged-review" "no YAML frontmatter found"
fi

# ── 3. No broken /octo:verify reference ─────────────────────────────
if grep -c '/octo:verify' "$CMD_FILE" >/dev/null 2>&1; then
    fail "no broken /octo:verify reference" "/octo:verify does not exist — should be /octo:deliver"
else
    pass "no broken /octo:verify reference"
fi

# ── 4. No broken /octo:ship reference ───────────────────────────────
if grep -c '/octo:ship' "$CMD_FILE" >/dev/null 2>&1; then
    fail "no broken /octo:ship reference" "/octo:ship does not exist — should be /octo:review"
else
    pass "no broken /octo:ship reference"
fi

# ── 5. Has mandatory compliance block ────────────────────────────────
if grep -c "MANDATORY COMPLIANCE" "$CMD_FILE" >/dev/null 2>&1; then
    pass "has mandatory compliance block"
else
    fail "has mandatory compliance block" "missing MANDATORY COMPLIANCE section"
fi

# ── 6. References the staged-review skill ────────────────────────────
if grep -c "skill-staged-review" "$CMD_FILE" >/dev/null 2>&1; then
    pass "references skill-staged-review"
else
    fail "references skill-staged-review" "no reference to skill-staged-review found"
fi

# ── 7. Skill file exists ────────────────────────────────────────────
if [[ -f "$SKILL_FILE" ]]; then
    pass "skill-staged-review.md exists"
else
    fail "skill-staged-review.md exists" "referenced skill file not found"
fi

# ── 8. Related commands reference only existing commands ─────────────
# Extract all /octo: references and verify each exists
broken_refs=0
while IFS= read -r ref; do
    cmd_name=$(echo "$ref" | sed 's|/octo:||')
    if [[ ! -f "$COMMANDS_DIR/${cmd_name}.md" ]]; then
        fail "related command exists: /octo:$cmd_name" "referenced command file not found"
        broken_refs=$((broken_refs + 1))
    fi
done < <(grep -oE '/octo:[a-zA-Z0-9_-]+' "$CMD_FILE" 2>/dev/null | sort -u || true)
if [[ $broken_refs -eq 0 ]]; then
    pass "all /octo: references point to existing commands"
fi

# ── 9. Registered in plugin.json ─────────────────────────────────────
if grep -c "staged-review.md" "$PLUGIN_JSON" >/dev/null 2>&1; then
    pass "registered in plugin.json"
else
    fail "registered in plugin.json" "staged-review.md not found in plugin.json"
fi
test_summary
