#!/usr/bin/env bash
# Tests for skill-cost-projections: HUD cost projection from per-phase averages
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "skill-cost-projections: HUD cost projection from per-phase averages"

SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-cost-projections.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

assert_contains() {
  local output="$1" pattern="$2" label="$3"
  # Herestring avoids macOS BSD-grep SIGPIPE on `echo | grep -q` under set -o pipefail:
  # grep exits on first match before echo finishes writing → pipeline reports failure
  # → pass branch never runs → false negative. No pipe, no SIGPIPE.
  grep -qE "$pattern" <<< "$output" && pass "$label" || fail "$label" "missing: $pattern"
}

assert_not_contains() {
  local output="$1" pattern="$2" label="$3"
  grep -qE "$pattern" <<< "$output" && fail "$label" "should not contain: $pattern" || pass "$label"
}

# ── File exists ──────────────────────────────────────────────────────────────

if [[ -f "$SKILL_FILE" ]]; then
  pass "skill-cost-projections.md exists"
else
  fail "skill-cost-projections.md exists" "file not found at $SKILL_FILE"
  echo ""; echo "FATAL: skill file not found, cannot continue"; exit 1
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

assert_contains "$FRONTMATTER" "^name: skill-cost-projections" "frontmatter: name field is skill-cost-projections"

assert_contains "$FRONTMATTER" "cost-projections" "frontmatter: aliases include cost-projections"

assert_contains "$FRONTMATTER" "cost-forecast" "frontmatter: aliases include cost-forecast"

assert_contains "$FRONTMATTER" "budget-projection" "frontmatter: aliases include budget-projection"

assert_contains "$FRONTMATTER" "description:" "frontmatter: description field present"

assert_contains "$FRONTMATTER" "trigger:" "frontmatter: trigger field present"

# ── Trigger phrases ──────────────────────────────────────────────────────────

assert_contains "$FRONTMATTER" "cost projection" "frontmatter: trigger mentions cost projection"

assert_contains "$FRONTMATTER" "estimate remaining cost" "frontmatter: trigger mentions estimate remaining cost"

assert_contains "$FRONTMATTER" "budget forecast" "frontmatter: trigger mentions budget forecast"

assert_contains "$FRONTMATTER" "how much will this cost" "frontmatter: trigger mentions how much will this cost"

# ── Section: Collect completed phase costs ───────────────────────────────────

assert_contains "$SKILL_CONTENT" "[Cc]ollect.*[Cc]ompleted.*[Cc]ost" "section: collect completed phase costs present"

assert_contains "$SKILL_CONTENT" "metrics" "collect costs: references metrics directory"

assert_contains "$SKILL_CONTENT" "metrics-tracker" "collect costs: references metrics-tracker.sh"

# ── Section: Compute average cost ────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "[Cc]ompute.*[Aa]verage" "section: compute average cost present"

assert_contains "$SKILL_CONTENT" "avg_cost.*=.*total_cost.*completed_steps" "compute average: shows formula"

# ── Section: Project remaining cost ──────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "[Pp]roject.*[Rr]emaining" "section: project remaining cost present"

assert_contains "$SKILL_CONTENT" "projected_remaining.*=.*avg_cost.*remaining_steps" "project remaining: shows formula"

# ── Section: Display in HUD ──────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "[Dd]isplay.*HUD" "section: display in HUD present"

assert_contains "$SKILL_CONTENT" "Spent:.*Est\. remaining:.*Total:" "display: format includes Spent/Est. remaining/Total"

# ── Section: Budget ceiling warning ──────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "[Bb]udget.*[Cc]eiling" "section: budget ceiling warning present"

assert_contains "$SKILL_CONTENT" "OCTO_BUDGET_CEILING" "budget ceiling: references OCTO_BUDGET_CEILING env var"

assert_contains "$SKILL_CONTENT" "projected to exceed" "budget ceiling: warns on overrun"

# ── Section: Profile suggestion ──────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "[Pp]rofile.*[Ss]uggestion" "section: profile suggestion present"

assert_contains "$SKILL_CONTENT" "OCTO_PROFILE=budget" "profile suggestion: references OCTO_PROFILE=budget"

assert_contains "$SKILL_CONTENT" "reduce costs" "profile suggestion: mentions reducing costs"

# ── Minimum data requirement ─────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "2\+.*completed.*step" "minimum data: requires 2+ completed steps"

# ── Display format examples ──────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "Spent: \\\$2\.40.*Est\. remaining: \\\$3\.60.*Total: ~\\\$6\.00" "display example: standard format present"

assert_contains "$SKILL_CONTENT" "Budget ceiling: \\\$5\.00.*projected to exceed by \\\$1\.00" "display example: budget overrun format present"

assert_contains "$SKILL_CONTENT" "OCTO_PROFILE=budget to reduce costs" "display example: profile tip format present"

# ── Integration notes ────────────────────────────────────────────────────────

assert_contains "$SKILL_CONTENT" "octopus-hud" "integration: references octopus-hud hook"

assert_contains "$SKILL_CONTENT" "metrics-tracker" "integration: references metrics-tracker.sh"

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

assert_not_contains "$SKILL_CONTENT" "gsd-2" "no attribution: does not reference gsd-2"

assert_not_contains "$SKILL_CONTENT" "github\.com/[a-z].*source" "no attribution: no source repo references"
test_summary
