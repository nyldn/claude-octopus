#!/usr/bin/env bash
# Tests for skill-coverage-audit: codepath tracing, test mapping, auto-generation (CONSOLIDATED-10)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "skill-coverage-audit: codepath tracing, test mapping, auto-generation (CONSOLIDATED-10)"

SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-coverage-audit.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

assert_contains() {
  local output="$1" pattern="$2" label="$3"
  echo "$output" | grep -qE "$pattern" && pass "$label" || fail "$label" "missing: $pattern"
}

assert_not_contains() {
  local output="$1" pattern="$2" label="$3"
  echo "$output" | grep -qE "$pattern" && fail "$label" "should not contain: $pattern" || pass "$label"
}

SKILL_CONTENT=$(<"$SKILL_FILE")

# ── File exists ──────────────────────────────────────────────────────────────

if [[ -f "$SKILL_FILE" ]]; then
  pass "skill-coverage-audit.md exists"
else
  fail "skill-coverage-audit.md exists" "file not found at $SKILL_FILE"
fi

# ── YAML frontmatter structure ───────────────────────────────────────────────

FIRST_LINE=$(head -n 1 "$SKILL_FILE")
if [[ "$FIRST_LINE" == "---" ]]; then
  pass "frontmatter: opening delimiter present"
else
  fail "frontmatter: opening delimiter present" "first line is not ---"
fi

CLOSING_DELIM=$(tail -n +2 "$SKILL_FILE" | grep -c '^---$' || true)
if [[ "$CLOSING_DELIM" -ge 1 ]]; then
  pass "frontmatter: closing delimiter present"
else
  fail "frontmatter: closing delimiter present" "no closing --- found"
fi

# Extract frontmatter (between first and second ---)
FRONTMATTER=$(awk '/^---$/{if(++count==2) exit} count==1' "$SKILL_FILE")

# ── Required frontmatter fields ──────────────────────────────────────────────

assert_contains "$FRONTMATTER" "^name: skill-coverage-audit" "frontmatter: name field is skill-coverage-audit"

assert_contains "$FRONTMATTER" "coverage-audit" "frontmatter: aliases include coverage-audit"

assert_contains "$FRONTMATTER" "test-coverage" "frontmatter: aliases include test-coverage"

assert_contains "$FRONTMATTER" "description:" "frontmatter: description field present"

assert_contains "$FRONTMATTER" "trigger:" "frontmatter: trigger field present"

# ── Trigger phrases ──────────────────────────────────────────────────────────

assert_contains "$FRONTMATTER" "coverage" "frontmatter: trigger mentions coverage"

assert_contains "$FRONTMATTER" "untested" "frontmatter: trigger mentions untested"

assert_contains "$FRONTMATTER" "generate tests" "frontmatter: trigger mentions generate tests"

# ── Section: Codepath Tracing ────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "Codepath Tracing" "section: codepath tracing present"

assert_contains "$SKILL_CONTENT" "Conditionals" "codepath tracing: covers conditionals"

assert_contains "$SKILL_CONTENT" "Error paths" "codepath tracing: covers error paths"

assert_contains "$SKILL_CONTENT" "Function calls" "codepath tracing: covers function calls"

assert_contains "$SKILL_CONTENT" "Guard clauses" "codepath tracing: covers guard clauses"

assert_contains "$SKILL_CONTENT" "Loop boundaries" "codepath tracing: covers loop boundaries"

assert_contains "$SKILL_CONTENT" "Codepath Inventory" "codepath tracing: has inventory template"

# ── Section: Quality Scoring ─────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "Quality Scoring" "section: quality scoring present"

assert_contains "$SKILL_CONTENT" "Behavior.*edge cases" "quality scoring: has full coverage tier"

assert_contains "$SKILL_CONTENT" "Happy path" "quality scoring: has happy path tier"

assert_contains "$SKILL_CONTENT" "Smoke test" "quality scoring: has smoke test tier"

assert_contains "$SKILL_CONTENT" "No test found" "quality scoring: has no-test tier"

assert_contains "$SKILL_CONTENT" "Coverage Map" "quality scoring: has coverage map template"

# ── Section: ASCII Coverage Diagram ──────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "Coverage Diagram" "section: ASCII coverage diagram present"

assert_contains "$SKILL_CONTENT" "COVERAGE:.*paths tested" "diagram: has coverage summary line"

assert_contains "$SKILL_CONTENT" "Code paths:" "diagram: has code paths breakdown"

assert_contains "$SKILL_CONTENT" "GAPS:.*paths need tests" "diagram: has gaps summary"

assert_contains "$SKILL_CONTENT" "BY TYPE:" "diagram: has type breakdown"

assert_contains "$SKILL_CONTENT" "BY RISK:" "diagram: has risk breakdown"

# ── Section: Auto-Generate Tests ─────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "Auto-Generate" "section: auto-generate tests present"

assert_contains "$SKILL_CONTENT" "Detect.*Test Conventions" "auto-generate: convention detection step"

assert_contains "$SKILL_CONTENT" "Framework:" "auto-generate: detects test framework"

assert_contains "$SKILL_CONTENT" "Generate Tests.*Uncovered" "auto-generate: generates for uncovered paths"

assert_contains "$SKILL_CONTENT" "BEFORE:.*paths tested" "auto-generate: before/after count present"

assert_contains "$SKILL_CONTENT" "AFTER:.*paths tested" "auto-generate: after count present"

assert_contains "$SKILL_CONTENT" "New tests generated:" "auto-generate: reports new test count"

# ── Caps and limits ──────────────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "30 code paths max" "caps: 30 code path limit documented"

assert_contains "$SKILL_CONTENT" "20 tests generated max" "caps: 20 test generation limit documented"

assert_contains "$SKILL_CONTENT" "2-minute per-test exploration cap" "caps: 2-min per-test exploration cap documented"

# ── No attribution to external sources ───────────────────────────────────────

assert_not_contains "$SKILL_CONTENT" "gstack" "no attribution: does not reference gstack"

assert_not_contains "$SKILL_CONTENT" "github\.com/[a-z].*source" "no attribution: no source repo references"

# ── Description length check (must be <= 120 chars per superpowers hardening) ─

DESC_LINE=$(grep '^description:' "$SKILL_FILE" | head -1)
DESC_VALUE=${DESC_LINE#description: }
DESC_VALUE=${DESC_VALUE#\"}
DESC_VALUE=${DESC_VALUE%\"}
DESC_LEN=${#DESC_VALUE}
if [[ "$DESC_LEN" -le 120 ]]; then
  pass "description length <= 120 chars (actual: $DESC_LEN)"
else
  fail "description length <= 120 chars" "actual: $DESC_LEN"
fi

# ── No banned words in description ───────────────────────────────────────────

assert_not_contains "$DESC_VALUE" "independent|compound|team of teams|claude instances" "description: no banned words"
test_summary
