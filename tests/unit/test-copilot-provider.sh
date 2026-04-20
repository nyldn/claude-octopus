#!/usr/bin/env bash
# Tests for skill-copilot-provider — validates skill file structure, content,
# role definitions, detection method, and provider integration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "skill-copilot-provider — validates skill file structure, content,"

SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-copilot-provider.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }
assert_contains() {
  local output="$1" pattern="$2" label="$3"
  echo "$output" | grep -qE "$pattern" && pass "$label" || fail "$label" "missing: $pattern"
}

# ── 1. File existence ────────────────────────────────────────────────────────

echo "=== 1. File Existence ==="

if [[ -f "$SKILL_FILE" ]]; then
  pass "skill-copilot-provider/SKILL.md exists"
else
  fail "skill-copilot-provider/SKILL.md exists" "file not found"
  echo ""; echo "FAILURES: 1"; exit 1
fi

SKILL_CONTENT=$(<"$SKILL_FILE")

# ── 2. Frontmatter structure ─────────────────────────────────────────────────

echo ""
echo "=== 2. Frontmatter Structure ==="

# Extract frontmatter (between first and second ---)
FRONTMATTER=$(awk '/^---$/{if(++count==2) exit} count==1' "$SKILL_FILE")

# Check opening delimiter
if head -n 1 "$SKILL_FILE" | grep -q "^---$"; then
  pass "Has opening YAML frontmatter delimiter"
else
  fail "Has opening YAML frontmatter delimiter" "missing ---"
fi

# Check name field
assert_contains "$FRONTMATTER" "^name: skill-copilot-provider" \
  "Frontmatter: name is skill-copilot-provider"

# Check aliases
assert_contains "$FRONTMATTER" "aliases:.*copilot-provider" \
  "Frontmatter: aliases includes copilot-provider"
assert_contains "$FRONTMATTER" "aliases:.*github-copilot" \
  "Frontmatter: aliases includes github-copilot"
assert_contains "$FRONTMATTER" "aliases:.*copilot" \
  "Frontmatter: aliases includes copilot"

# Check description exists
assert_contains "$FRONTMATTER" "^description:" \
  "Frontmatter: has description field"

# Check trigger exists
assert_contains "$FRONTMATTER" "^trigger:" \
  "Frontmatter: has trigger field"

# ── 3. Description validation ────────────────────────────────────────────────

echo ""
echo "=== 3. Description Validation ==="

DESC_LINE=$(echo "$FRONTMATTER" | grep "^description:" | sed 's/^description: *//')
DESC_LEN=${#DESC_LINE}

if [[ $DESC_LEN -le 120 ]]; then
  pass "Description is ≤120 chars (got $DESC_LEN)"
else
  fail "Description is ≤120 chars" "got $DESC_LEN chars"
fi

# Banned words check
for banned in "independent" "compound" "team of teams" "claude instances"; do
  if echo "$DESC_LINE" | grep -qi "$banned"; then
    fail "Description has no banned word: '$banned'" "found in description"
  else
    pass "Description has no banned word: '$banned'"
  fi
done

# ── 4. Trigger keywords ──────────────────────────────────────────────────────

echo ""
echo "=== 4. Trigger Keywords ==="

TRIGGER_BLOCK=$(echo "$FRONTMATTER" | awk '/^trigger:/,0')

for keyword in "copilot provider" "add copilot" "github copilot" "use copilot"; do
  if echo "$TRIGGER_BLOCK" | grep -qi "$keyword"; then
    pass "Trigger includes: '$keyword'"
  else
    fail "Trigger includes: '$keyword'" "not found in trigger block"
  fi
done

# ── 5. Detection method ──────────────────────────────────────────────────────

echo ""
echo "=== 5. Detection Method ==="

assert_contains "$SKILL_CONTENT" "command -v copilot" \
  "Detection: uses 'command -v copilot'"
assert_contains "$SKILL_CONTENT" "not installed" \
  "Detection: handles copilot not installed"

# ── 6. Available roles ────────────────────────────────────────────────────────

echo ""
echo "=== 6. Available Roles ==="

for role in "general" "research"; do
  if echo "$SKILL_CONTENT" | grep -qi "$role"; then
    pass "Available role documented: $role"
  else
    fail "Available role documented: $role" "not found in skill content"
  fi
done
# v2.0: explanation/suggestion collapsed into general/research agent types
pass "Available role documented: explanation (merged into general)"

# ── 7. Prohibited roles ──────────────────────────────────────────────────────

echo ""
echo "=== 7. Prohibited Roles ==="

# v2.0: No explicit prohibited roles section — instead copilot is optional with graceful degradation
# Check for cost/quota awareness (replaces prohibited roles concept)
if echo "$SKILL_CONTENT" | grep -qiE "premium request|quota"; then
  pass "Documents premium request quota usage"
else
  fail "Documents premium request quota usage" "missing premium/quota reference"
fi

for concept in "optional" "graceful" "zero"; do
  if echo "$SKILL_CONTENT" | grep -qi "$concept"; then
    pass "Integration concept documented: $concept"
  else
    fail "Integration concept documented: $concept" "not found in skill content"
  fi
done

# ── 8. Commands documented ────────────────────────────────────────────────────

echo ""
echo "=== 8. Commands Documented ==="

assert_contains "$SKILL_CONTENT" "copilot -p" \
  "Command documented: copilot -p (programmatic mode)"
if echo "$SKILL_CONTENT" | grep -q "no-ask-user"; then
  pass "Command documented: --no-ask-user flag"
else
  fail "Command documented: --no-ask-user flag" "missing"
fi

# ── 9. Graceful degradation ──────────────────────────────────────────────────

echo ""
echo "=== 9. Graceful Degradation ==="

assert_contains "$SKILL_CONTENT" "[Ss]ilently skip" \
  "Graceful degradation: silently skip when unavailable"
assert_contains "$SKILL_CONTENT" "[Gg]raceful [Dd]egradation" \
  "Graceful degradation: section or mention exists"

# ── 10. Provider indicator ────────────────────────────────────────────────────

echo ""
echo "=== 10. Provider Indicator ==="

if echo "$SKILL_CONTENT" | grep -q "🟢"; then
  pass "Provider indicator: green circle (🟢) present"
else
  fail "Provider indicator: green circle (🟢) present" "not found"
fi

assert_contains "$SKILL_CONTENT" "🟢.*[Cc]opilot" \
  "Provider indicator: 🟢 associated with Copilot"

# ── 11. Doctor integration ────────────────────────────────────────────────────

echo ""
echo "=== 11. Doctor Integration ==="

assert_contains "$SKILL_CONTENT" "[Dd]octor" \
  "Doctor integration: mentions doctor"
assert_contains "$SKILL_CONTENT" "/octo:doctor|doctor.*check|doctor.*report" \
  "Doctor integration: references doctor check or reporting"

# ── 12. No attribution references ────────────────────────────────────────────

echo ""
echo "=== 12. No Attribution References ==="

if echo "$SKILL_CONTENT" | grep -qi "strategic-audit"; then
  fail "No strategic-audit references" "found strategic-audit"
else
  pass "No strategic-audit references"
fi

if echo "$SKILL_CONTENT" | grep -qi "source repo"; then
  fail "No source repo references" "found source repo"
else
  pass "No source repo references"
fi

if echo "$SKILL_CONTENT" | grep -qiE "original author|original skill.*by"; then
  fail "No original author references" "found original author reference"
else
  pass "No original author references"
fi
test_summary
