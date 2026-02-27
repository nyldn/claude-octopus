#!/bin/bash
# Test suite for v8.27.0 — Superpowers-Inspired Hardening
# Tests context reinforcement, description trap fixes, HARD-GATE tags,
# human_only flags, staged review pipeline, plan mode interceptor, and version bumps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

pass() {
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ✅ PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ❌ FAIL: $1"
}

suite() {
  echo ""
  echo "━━━ $1 ━━━"
}

# ─────────────────────────────────────────────────────────────────────
# Suite 1: Context Reinforcement
# ─────────────────────────────────────────────────────────────────────
suite "1. Context Reinforcement Hook"

# 1.1 Hook file exists
if [[ -f "$PLUGIN_DIR/hooks/context-reinforcement.sh" ]]; then
  pass "context-reinforcement.sh exists"
else
  fail "context-reinforcement.sh missing"
fi

# 1.2 Hook is executable
if [[ -x "$PLUGIN_DIR/hooks/context-reinforcement.sh" ]]; then
  pass "context-reinforcement.sh is executable"
else
  fail "context-reinforcement.sh is not executable"
fi

# 1.3 hooks.json has SessionStart entry for context-reinforcement
if grep -q "context-reinforcement.sh" "$PLUGIN_DIR/.claude-plugin/hooks.json"; then
  pass "hooks.json references context-reinforcement.sh"
else
  fail "hooks.json missing context-reinforcement.sh reference"
fi

# 1.4 Hook outputs valid JSON when given empty stdin
HOOK_OUTPUT=$(echo '{}' | bash "$PLUGIN_DIR/hooks/context-reinforcement.sh" 2>/dev/null || true)
if echo "$HOOK_OUTPUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  pass "context-reinforcement.sh outputs valid JSON"
else
  fail "context-reinforcement.sh does not output valid JSON"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 2: Description Trap Audit
# ─────────────────────────────────────────────────────────────────────
suite "2. Description Trap (Opaque Descriptions)"

# 2.1 skill-debug — no process details in description
DEBUG_DESC=$(grep '^description:' "$PLUGIN_DIR/.claude/skills/skill-debug.md" | head -1)
if echo "$DEBUG_DESC" | grep -qiE "(phase|investigate|analyze|hypothesize|implement)"; then
  fail "skill-debug description leaks process details"
else
  pass "skill-debug description is opaque"
fi

# 2.2 skill-tdd — no process details
TDD_DESC=$(grep '^description:' "$PLUGIN_DIR/.claude/skills/skill-tdd.md" | head -1)
if echo "$TDD_DESC" | grep -qiE "(discipline|write.*first|failing test|red.green)"; then
  fail "skill-tdd description leaks process details"
else
  pass "skill-tdd description is opaque"
fi

# 2.3 skill-factory — no process details
FACTORY_DESC=$(grep '^description:' "$PLUGIN_DIR/.claude/skills/skill-factory.md" | head -1)
if echo "$FACTORY_DESC" | grep -qiE "(dark factory|spec.in|software.out|holdout|satisfaction)"; then
  fail "skill-factory description leaks process details"
else
  pass "skill-factory description is opaque"
fi

# 2.4 skill-deep-research — no process details
RESEARCH_DESC=$(grep '^description:' "$PLUGIN_DIR/.claude/skills/skill-deep-research.md" | head -1)
if echo "$RESEARCH_DESC" | grep -qiE "(multi.ai|parallel|cost transparency|provider)"; then
  fail "skill-deep-research description leaks process details"
else
  pass "skill-deep-research description is opaque"
fi

# 2.5 flow-parallel — no process details
PARALLEL_DESC=$(grep '^description:' "$PLUGIN_DIR/.claude/skills/flow-parallel.md" | head -1)
if echo "$PARALLEL_DESC" | grep -qiE "(team of teams|claude instances|independent|compound)"; then
  fail "flow-parallel description leaks process details"
else
  pass "flow-parallel description is opaque"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 3: HARD-GATE Tags
# ─────────────────────────────────────────────────────────────────────
suite "3. HARD-GATE XML Enforcement Tags"

# 3.1-3.5 Check each skill for HARD-GATE tag
for skill in skill-debug skill-tdd skill-factory skill-verify skill-deep-research; do
  SKILL_FILE="$PLUGIN_DIR/.claude/skills/${skill}.md"
  if grep -q '<HARD-GATE>' "$SKILL_FILE" && grep -q '</HARD-GATE>' "$SKILL_FILE"; then
    pass "${skill} contains HARD-GATE tags"
  else
    fail "${skill} missing HARD-GATE tags"
  fi
done

# ─────────────────────────────────────────────────────────────────────
# Suite 4: Human-Only Flag
# ─────────────────────────────────────────────────────────────────────
suite "4. Human-Only Invocation Flag"

# 4.1-4.5 Check each skill for human_only
for skill in skill-factory skill-deep-research skill-adversarial-security flow-parallel skill-ship; do
  SKILL_FILE="$PLUGIN_DIR/.claude/skills/${skill}.md"
  if grep -q 'invocation: human_only' "$SKILL_FILE"; then
    pass "${skill} has invocation: human_only"
  else
    fail "${skill} missing invocation: human_only"
  fi
done

# ─────────────────────────────────────────────────────────────────────
# Suite 5: Staged Review Pipeline
# ─────────────────────────────────────────────────────────────────────
suite "5. Staged Review Pipeline"

# 5.1 Skill file exists
if [[ -f "$PLUGIN_DIR/.claude/skills/skill-staged-review.md" ]]; then
  pass "skill-staged-review.md exists"
else
  fail "skill-staged-review.md missing"
fi

# 5.2 Command file exists
if [[ -f "$PLUGIN_DIR/.claude/commands/staged-review.md" ]]; then
  pass "staged-review command exists"
else
  fail "staged-review command missing"
fi

# 5.3 plugin.json references skill
if grep -q "skill-staged-review.md" "$PLUGIN_DIR/.claude-plugin/plugin.json"; then
  pass "plugin.json registers staged-review skill"
else
  fail "plugin.json missing staged-review skill"
fi

# 5.4 Two-stage structure (contains Stage 1 and Stage 2)
if grep -q "Stage 1" "$PLUGIN_DIR/.claude/skills/skill-staged-review.md" && \
   grep -q "Stage 2" "$PLUGIN_DIR/.claude/skills/skill-staged-review.md"; then
  pass "staged-review has two-stage structure"
else
  fail "staged-review missing two-stage structure"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 6: Plan Mode Interceptor
# ─────────────────────────────────────────────────────────────────────
suite "6. Plan Mode Interceptor"

# 6.1 Hook file exists
if [[ -f "$PLUGIN_DIR/hooks/plan-mode-interceptor.sh" ]]; then
  pass "plan-mode-interceptor.sh exists"
else
  fail "plan-mode-interceptor.sh missing"
fi

# 6.2 Hook is executable
if [[ -x "$PLUGIN_DIR/hooks/plan-mode-interceptor.sh" ]]; then
  pass "plan-mode-interceptor.sh is executable"
else
  fail "plan-mode-interceptor.sh is not executable"
fi

# 6.3 hooks.json has EnterPlanMode matcher
if grep -q '"EnterPlanMode"' "$PLUGIN_DIR/.claude-plugin/hooks.json"; then
  pass "hooks.json has EnterPlanMode matcher"
else
  fail "hooks.json missing EnterPlanMode matcher"
fi

# 6.4 Hook outputs valid JSON
PLAN_OUTPUT=$(echo '{}' | bash "$PLUGIN_DIR/hooks/plan-mode-interceptor.sh" 2>/dev/null || true)
if echo "$PLAN_OUTPUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  pass "plan-mode-interceptor.sh outputs valid JSON"
else
  fail "plan-mode-interceptor.sh does not output valid JSON"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 7: Version Bumps
# ─────────────────────────────────────────────────────────────────────
suite "7. Version Consistency"

# 7.1 package.json
if grep -q '"8.27.0"' "$PLUGIN_DIR/package.json"; then
  pass "package.json version is 8.27.0"
else
  fail "package.json version is not 8.27.0"
fi

# 7.2 plugin.json
if grep -q '"8.27.0"' "$PLUGIN_DIR/.claude-plugin/plugin.json"; then
  pass "plugin.json version is 8.27.0"
else
  fail "plugin.json version is not 8.27.0"
fi

# 7.3 marketplace.json
if grep -q '"8.27.0"' "$PLUGIN_DIR/.claude-plugin/marketplace.json"; then
  pass "marketplace.json version is 8.27.0"
else
  fail "marketplace.json version is not 8.27.0"
fi

# 7.4 README.md badge
if grep -q 'Version-8.27.0' "$PLUGIN_DIR/README.md"; then
  pass "README.md badge shows 8.27.0"
else
  fail "README.md badge does not show 8.27.0"
fi

# 7.5 CHANGELOG.md has entry
if grep -q '\[8.27.0\]' "$PLUGIN_DIR/CHANGELOG.md"; then
  pass "CHANGELOG.md has 8.27.0 entry"
else
  fail "CHANGELOG.md missing 8.27.0 entry"
fi

# 7.6 No stale 8.26.0 in version fields (only in changelog history)
STALE_PACKAGE=$(grep '"version"' "$PLUGIN_DIR/package.json" | grep -c '8.26.0' || true)
STALE_PLUGIN=$(grep '"version"' "$PLUGIN_DIR/.claude-plugin/plugin.json" | grep -c '8.26.0' || true)
STALE_MARKET=$(grep '"version"' "$PLUGIN_DIR/.claude-plugin/marketplace.json" | grep -c '8.26.0' || true)
if [[ "$STALE_PACKAGE" -eq 0 && "$STALE_PLUGIN" -eq 0 && "$STALE_MARKET" -eq 0 ]]; then
  pass "No stale 8.26.0 in version fields"
else
  fail "Stale 8.26.0 found in version fields"
fi

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
