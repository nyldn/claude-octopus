#!/usr/bin/env bash
# Tests for skill-design-lineage: design document persistence, revision chains, cross-session discovery
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Design Lineage"

SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-design-lineage.md"

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

# ── File exists ──────────────────────────────────────────────────────────────

if [[ -f "$SKILL_FILE" ]]; then
  pass "skill-design-lineage.md exists"
else
  fail "skill-design-lineage.md exists" "file not found at $SKILL_FILE"
  echo "FATAL: skill file not found, cannot continue"
  exit 1
fi

SKILL_CONTENT=$(<"$SKILL_FILE")

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

assert_contains "$FRONTMATTER" "^name: skill-design-lineage" "frontmatter: name field is skill-design-lineage"

assert_contains "$FRONTMATTER" "design-lineage" "frontmatter: aliases include design-lineage"

assert_contains "$FRONTMATTER" "design-docs" "frontmatter: aliases include design-docs"

assert_contains "$FRONTMATTER" "design-history" "frontmatter: aliases include design-history"

assert_contains "$FRONTMATTER" "description:" "frontmatter: description field present"

assert_contains "$FRONTMATTER" "trigger:" "frontmatter: trigger field present"

# ── Trigger phrases ──────────────────────────────────────────────────────────

assert_contains "$FRONTMATTER" "save design" "frontmatter: trigger mentions save design"

assert_contains "$FRONTMATTER" "design document" "frontmatter: trigger mentions design document"

assert_contains "$FRONTMATTER" "design history" "frontmatter: trigger mentions design history"

assert_contains "$FRONTMATTER" "find prior designs" "frontmatter: trigger mentions find prior designs"

# ── Storage location documented ──────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "~/.claude-octopus/designs/" "storage: ~/.claude-octopus/designs/ location documented"

assert_contains "$SKILL_CONTENT" "project.slug" "storage: project-scoped via slug"

# ── Filename format documented ───────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "user.*branch.*design.*datetime" "filename: user-branch-design-datetime format documented"

assert_contains "$SKILL_CONTENT" "YYYYMMDD" "filename: datetime format includes date component"

# ── Design doc template sections ─────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "Problem Statement" "template: Problem Statement section present"

assert_contains "$SKILL_CONTENT" "Constraints" "template: Constraints section present"

assert_contains "$SKILL_CONTENT" "Approaches Considered" "template: Approaches Considered section present"

assert_contains "$SKILL_CONTENT" "Recommendation" "template: Recommendation section present"

assert_contains "$SKILL_CONTENT" "Open Questions" "template: Open Questions section present"

# ── Frontmatter metadata fields in template ──────────────────────────────────

assert_contains "$SKILL_CONTENT" "branch:" "template metadata: branch field documented"

assert_contains "$SKILL_CONTENT" "user:" "template metadata: user field documented"

assert_contains "$SKILL_CONTENT" "created:" "template metadata: created field documented"

assert_contains "$SKILL_CONTENT" "supersedes:" "template metadata: supersedes field documented"

# ── Revision chain (Supersedes) ──────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "[Ss]upersedes" "revision chain: supersedes concept documented"

assert_contains "$SKILL_CONTENT" "revision" "revision chain: revision concept mentioned"

assert_contains "$SKILL_CONTENT" "prior design|prior document|prior version" "revision chain: links to prior design"

# ── Cross-session discovery ──────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "grep -li" "discovery: grep-based keyword search documented"

assert_contains "$SKILL_CONTENT" "head -10" "discovery: search limited to 10 results"

assert_contains "$SKILL_CONTENT" "deliver.*review.*develop" "discovery: downstream commands mentioned"

assert_contains "$SKILL_CONTENT" "flow-discover" "discovery: integration with flow-discover"

assert_contains "$SKILL_CONTENT" "flow-define" "discovery: integration with flow-define"

assert_contains "$SKILL_CONTENT" "flow-develop" "discovery: integration with flow-develop"

# ── Branch tracking ──────────────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "git rev-parse --abbrev-ref HEAD" "branch tracking: git branch detection documented"

assert_contains "$SKILL_CONTENT" "tr '/' '-'" "branch tracking: slash sanitization documented"

# ── Immutability rule ────────────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "read-only after creation" "immutability: read-only after creation documented"

# ── Caps and limits ──────────────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "50 design docs|Max 50" "caps: 50 design doc limit documented"

assert_contains "$SKILL_CONTENT" "10 results" "caps: 10 result search limit documented"

assert_contains "$SKILL_CONTENT" "500 lines" "caps: 500 line template limit documented"

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

# ── No attribution to external sources ───────────────────────────────────────

assert_not_contains "$SKILL_CONTENT" "gstack" "no attribution: does not reference gstack"

assert_not_contains "$SKILL_CONTENT" "office-hours" "no attribution: does not reference office-hours"

assert_not_contains "$SKILL_CONTENT" "github\.com/[a-z].*source" "no attribution: no source repo references"
test_summary
