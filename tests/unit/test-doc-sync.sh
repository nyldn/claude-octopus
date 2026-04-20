#!/usr/bin/env bash
# Tests for skill-doc-sync: post-ship documentation synchronization
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "skill-doc-sync: post-ship documentation synchronization"

SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-doc-sync.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── File existence ───────────────────────────────────────────────────────────

if [[ -f "$SKILL_FILE" ]]; then
  pass "skill-doc-sync.md exists"
else
  fail "skill-doc-sync.md exists" "file not found at $SKILL_FILE"
  echo "Cannot continue without skill file."
  exit 1
fi

CONTENT=$(<"$SKILL_FILE")

# ── Frontmatter structure ────────────────────────────────────────────────────

FRONTMATTER=$(awk '/^---$/{if(++count==2) exit} count==1' "$SKILL_FILE")

# name field
if echo "$FRONTMATTER" | grep -q "^name: skill-doc-sync"; then
  pass "frontmatter: has name field (skill-doc-sync)"
else
  fail "frontmatter: has name field" "missing or wrong name"
fi

# aliases field
if echo "$FRONTMATTER" | grep -q "^aliases:"; then
  pass "frontmatter: has aliases field"
else
  fail "frontmatter: has aliases field" "missing aliases"
fi

# Check specific aliases
for alias in "doc-sync" "sync-docs" "document-release"; do
  if echo "$FRONTMATTER" | grep -q "$alias"; then
    pass "frontmatter: alias '$alias' present"
  else
    fail "frontmatter: alias '$alias' present" "missing alias: $alias"
  fi
done

# description field
if echo "$FRONTMATTER" | grep -q "^description:"; then
  pass "frontmatter: has description field"
else
  fail "frontmatter: has description field" "missing description"
fi

# trigger patterns in description (Use when: ...)
for trigger in "sync docs" "update doc" "document changes" "release notes"; do
  if echo "$FRONTMATTER" | grep -qi "$trigger"; then
    pass "frontmatter: trigger pattern '$trigger' present"
  else
    fail "frontmatter: trigger pattern '$trigger' present" "missing trigger: $trigger"
  fi
done

# ── Description constraints ──────────────────────────────────────────────────

DESC_LINE=$(echo "$FRONTMATTER" | grep "^description:" | sed 's/^description: *//')
DESC_LEN=${#DESC_LINE}

if [[ "$DESC_LEN" -le 120 ]]; then
  pass "description length <= 120 chars ($DESC_LEN chars)"
else
  fail "description length <= 120 chars" "got $DESC_LEN chars"
fi

# Banned words check
BANNED_WORDS=("independent" "compound" "team of teams" "claude instances")
for word in "${BANNED_WORDS[@]}"; do
  if echo "$DESC_LINE" | grep -qi "$word"; then
    fail "description: no banned word '$word'" "found banned word in description"
  else
    pass "description: no banned word '$word'"
  fi
done

# ── All 9 steps present ─────────────────────────────────────────────────────

STEP_LABELS=(
  "Step 1.*Discover"
  "Step 2.*Cross-[Rr]eference"
  "Step 3.*Auto-[Uu]pdate"
  "Step 4.*Risky"
  "Step 5.*CHANGELOG"
  "Step 6.*Cross-[Dd]oc"
  "Step 7.*Discoverability"
  "Step 8.*TODO"
  "Step 9.*Commit"
)

for i in "${!STEP_LABELS[@]}"; do
  step_num=$((i + 1))
  pattern="${STEP_LABELS[$i]}"
  if echo "$CONTENT" | grep -qE "$pattern"; then
    pass "step $step_num present (${pattern})"
  else
    fail "step $step_num present" "missing pattern: $pattern"
  fi
done

# ── Key patterns ─────────────────────────────────────────────────────────────

# git diff reference
if echo "$CONTENT" | grep -q "git diff"; then
  pass "references git diff"
else
  fail "references git diff" "no git diff found in content"
fi

# sell test
if echo "$CONTENT" | grep -qi "sell test"; then
  pass "references sell test"
else
  fail "references sell test" "no sell test reference found"
fi

# cross-doc consistency
if echo "$CONTENT" | grep -qi "cross-doc consistency"; then
  pass "references cross-doc consistency"
else
  fail "references cross-doc consistency" "not found"
fi

# discoverability check
if echo "$CONTENT" | grep -qi "discoverability"; then
  pass "references discoverability"
else
  fail "references discoverability" "not found"
fi

# CHANGELOG append-only
if echo "$CONTENT" | grep -qi "append only"; then
  pass "CHANGELOG append-only rule documented"
else
  fail "CHANGELOG append-only rule documented" "not found"
fi

# Never clobber CHANGELOG
if echo "$CONTENT" | grep -Eqi "never.*clobber|never.*delete.*existing.*entries"; then
  pass "never clobber CHANGELOG rule documented"
else
  fail "never clobber CHANGELOG rule documented" "not found"
fi

# ── Caps documented ──────────────────────────────────────────────────────────

# 30 file cap
if echo "$CONTENT" | grep -q "30"; then
  pass "30-file cap documented"
else
  fail "30-file cap documented" "no mention of 30-file limit"
fi

# User confirmation for risky changes
if echo "$CONTENT" | grep -qi "user.*confirm\|ask.*user\|require.*confirmation\|user.*approval"; then
  pass "user confirmation for risky changes documented"
else
  fail "user confirmation for risky changes documented" "not found"
fi

# ── No attribution / no source repo references ──────────────────────────────

if echo "$CONTENT" | grep -qi "gstack"; then
  fail "no gstack reference" "found 'gstack' in content"
else
  pass "no gstack reference"
fi

if echo "$CONTENT" | grep -qi "source repo"; then
  fail "no source repo reference" "found 'source repo' in content"
else
  pass "no source repo reference"
fi

# Check no Attribution section
if echo "$CONTENT" | grep -qi "^## Attribution"; then
  fail "no Attribution section" "found Attribution heading"
else
  pass "no Attribution section"
fi

# ── Integration notes ────────────────────────────────────────────────────────

if echo "$CONTENT" | grep -qi "flow-deliver"; then
  pass "references flow-deliver integration"
else
  fail "references flow-deliver integration" "not found"
fi

# ── flow-deliver actually wires doc-sync ───────────────────────────────────

DELIVER_SKILL="$PROJECT_ROOT/skills/flow-deliver/SKILL.md"
if [[ -f "$DELIVER_SKILL" ]]; then
  if grep -qi 'doc.sync\|doc-sync\|sync docs' "$DELIVER_SKILL" 2>/dev/null; then
    pass "flow-deliver references doc-sync step"
  else
    fail "flow-deliver references doc-sync step" "no doc-sync reference in flow-deliver"
  fi
else
  fail "flow-deliver references doc-sync step" "flow-deliver SKILL.md not found"
fi
test_summary
