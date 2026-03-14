#!/usr/bin/env bash
# Tests for /octo:meta-prompt command file integrity
# Validates: file exists, frontmatter, skill reference, core techniques, registration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CMD_FILE="$PROJECT_ROOT/.claude/commands/meta-prompt.md"
SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-meta-prompt.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── 1. File exists ──────────────────────────────────────────────────
if [[ -f "$CMD_FILE" ]]; then
    pass "meta-prompt.md exists"
else
    fail "meta-prompt.md exists" "file not found at $CMD_FILE"
fi

# ── 2. YAML frontmatter uses 'command:' field ───────────────────────
if head -1 "$CMD_FILE" | grep -q "^---$"; then
    if grep -c "^command: meta-prompt" "$CMD_FILE" >/dev/null 2>&1; then
        pass "frontmatter has command: meta-prompt"
    else
        fail "frontmatter has command: meta-prompt" "missing or incorrect command field"
    fi
else
    fail "frontmatter has command: meta-prompt" "no YAML frontmatter found"
fi

# ── 3. Has description in frontmatter ────────────────────────────────
if grep -c "^description:" "$CMD_FILE" >/dev/null 2>&1; then
    pass "frontmatter has description"
else
    fail "frontmatter has description" "missing description field"
fi

# ── 4. References skill-meta-prompt ──────────────────────────────────
if grep -c "skill-meta-prompt" "$CMD_FILE" >/dev/null 2>&1; then
    pass "references skill-meta-prompt"
else
    fail "references skill-meta-prompt" "no reference to skill-meta-prompt found"
fi

# ── 5. Skill file exists ────────────────────────────────────────────
if [[ -f "$SKILL_FILE" ]]; then
    pass "skill-meta-prompt.md exists"
else
    fail "skill-meta-prompt.md exists" "referenced skill file not found"
fi

# ── 6. Contains core techniques ──────────────────────────────────────
if grep -c "Task Decomposition" "$CMD_FILE" >/dev/null 2>&1; then
    pass "core technique: Task Decomposition"
else
    fail "core technique: Task Decomposition" "missing from command file"
fi

if grep -c "Fresh Eyes" "$CMD_FILE" >/dev/null 2>&1; then
    pass "core technique: Fresh Eyes Review"
else
    fail "core technique: Fresh Eyes Review" "missing from command file"
fi

# ── 7. Registered in plugin.json ─────────────────────────────────────
if grep -c "meta-prompt.md" "$PLUGIN_JSON" >/dev/null 2>&1; then
    pass "registered in plugin.json"
else
    fail "registered in plugin.json" "meta-prompt.md not found in plugin.json"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  meta-prompt command tests: $PASS_COUNT/$TEST_COUNT passed"
echo "═══════════════════════════════════════════"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
