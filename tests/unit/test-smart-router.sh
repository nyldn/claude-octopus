#!/usr/bin/env bash
# Tests for /octo:auto smart router v3.0 — routing table integrity, priority ordering, and completeness
# (renamed from /octo:octo in v9.5.0; legacy octo.md is a redirect)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "(renamed from /octo:octo in v9.5.0; legacy octo.md is a redirect)"

OCTO_MD="$PROJECT_ROOT/.claude/commands/auto.md"
LEGACY_MD="$PROJECT_ROOT/.claude/commands/octo.md"
COMMANDS_DIR="$PROJECT_ROOT/.claude/commands"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }
assert_contains() {
  local file="$1" pattern="$2" label="$3"
  [[ $(grep -cE "$pattern" "$file") -gt 0 ]] && pass "$label" || fail "$label" "missing: $pattern"
}

# ── auto.md exists and has v3.0 metadata ──────────────────────────────────────

[[ -f "$OCTO_MD" ]] && pass "auto.md exists" || fail "auto.md exists" "file not found"
assert_contains "$OCTO_MD" "version: 3\\.0\\.0" "version is 3.0.0"
assert_contains "$OCTO_MD" "updated: 2026" "updated date is current year"

# ── legacy octo.md exists and redirects to auto ──────────────────────────────

[[ -f "$LEGACY_MD" ]] && pass "legacy octo.md exists" || fail "legacy octo.md exists" "file not found"
assert_contains "$LEGACY_MD" "Legacy.*Redirect" "legacy octo.md is a redirect"
assert_contains "$LEGACY_MD" "octo:auto" "legacy octo.md references /octo:auto"

# ── EXECUTION CONTRACT structure ──────────────────────────────────────────────

assert_contains "$OCTO_MD" "EXECUTION CONTRACT" "has EXECUTION CONTRACT section"
assert_contains "$OCTO_MD" "STEP 1.*Input Validation" "STEP 1: Input Validation"
assert_contains "$OCTO_MD" "STEP 2.*Meta Command" "STEP 2: Meta Command Check"
assert_contains "$OCTO_MD" "STEP 3.*Analyze Intent" "STEP 3: Analyze Intent"
assert_contains "$OCTO_MD" "STEP 4.*Determine Confidence" "STEP 4: Determine Confidence"
assert_contains "$OCTO_MD" "STEP 5.*Route" "STEP 5: Route Based on Confidence"
assert_contains "$OCTO_MD" "STEP 6.*Visual Indicators" "STEP 6: Display Visual Indicators"
assert_contains "$OCTO_MD" "STEP 7.*Routing" "STEP 7: Record Routing Decision"

# ── Priority ordering exists ──────────────────────────────────────────────────

assert_contains "$OCTO_MD" "Priority 1.*Specialized" "Priority 1 — Specialized section"
assert_contains "$OCTO_MD" "Priority 2.*Core" "Priority 2 — Core section"
assert_contains "$OCTO_MD" "Priority 3.*Build" "Priority 3 — Build section"

# ── All 17 routable workflows have valid skill targets ────────────────────────

# Extract skill targets from routing table (octo:xxx patterns)
SKILL_TARGETS=(
  "octo:embrace"
  "octo:parallel"
  "octo:spec"
  "octo:security"
  "octo:tdd"
  "octo:debug"
  "octo:design-ui-ux"
  "octo:prd"
  "octo:brainstorm"
  "octo:deck"
  "octo:docs"
  "octo:discover"
  "octo:review"
  "octo:debate"
  "octo:develop"
  "octo:plan"
  "octo:quick"
)

for target in "${SKILL_TARGETS[@]}"; do
  # Verify target appears in octo.md routing table
  [[ $(grep -c "$target" "$OCTO_MD") -gt 0 ]] && \
    pass "routes to $target" || \
    fail "routes to $target" "not found in routing table"
done

# ── Verify each routed skill has a matching command or skill file ──────────────

for target in "${SKILL_TARGETS[@]}"; do
  # Strip "octo:" prefix to get command name
  cmd_name="${target#octo:}"
  cmd_file="$COMMANDS_DIR/${cmd_name}.md"
  skill_pattern="$SKILLS_DIR/*${cmd_name}*"

  if [[ -f "$cmd_file" ]] || ls $skill_pattern >/dev/null 2>&1; then
    pass "$target has backing file"
  else
    fail "$target has backing file" "no command or skill file found for $cmd_name"
  fi
done

# ── Bug fix: no reference to non-existent "validate" skill ────────────────────

if [[ $(grep -c 'Skill.*"validate"' "$OCTO_MD") -eq 0 ]]; then
  pass "no reference to non-existent 'validate' skill (P0 fix)"
else
  fail "no reference to non-existent 'validate' skill" "found Skill: validate — should be review"
fi

# ── Decision tree (not percentage-based) confidence scoring ───────────────────

assert_contains "$OCTO_MD" "decision tree" "uses decision tree for confidence"
if [[ $(grep -c "matching keywords.*total keywords.*100" "$OCTO_MD") -eq 0 ]]; then
  pass "no percentage-based scoring formula"
else
  fail "no percentage-based scoring formula" "found old percentage formula"
fi

# ── Input length guard ────────────────────────────────────────────────────────

assert_contains "$OCTO_MD" "500 characters" "has input length guard (500 chars)"

# ── Meta command handler ──────────────────────────────────────────────────────

assert_contains "$OCTO_MD" "help.*list.*commands" "meta command check includes help/list/commands"

# ── Complete fallback menu has 17 entries ──────────────────────────────────────

MENU_COUNT=$(grep -c '/octo:' "$OCTO_MD" | head -1)
# The menu section plus routing table references — at minimum 17 unique workflow mentions
UNIQUE_WORKFLOWS=$(grep -oE 'octo:[a-z-]+' "$OCTO_MD" | sort -u | wc -l | tr -d ' ')
if [[ $UNIQUE_WORKFLOWS -ge 17 ]]; then
  pass "at least 17 unique workflow references ($UNIQUE_WORKFLOWS found)"
else
  fail "at least 17 unique workflow references" "only $UNIQUE_WORKFLOWS found, expected >= 17"
fi

# ── Fallback menu has category groupings ──────────────────────────────────────

assert_contains "$OCTO_MD" "Core Workflows:" "fallback menu has Core Workflows category"
assert_contains "$OCTO_MD" "Engineering:" "fallback menu has Engineering category"
assert_contains "$OCTO_MD" "Creative.*Documentation:" "fallback menu has Creative & Documentation category"

# ── Routing memory / learning ─────────────────────────────────────────────────

assert_contains "$OCTO_MD" "auto-memory" "references auto-memory for routing corrections"
assert_contains "$OCTO_MD" "routing.log" "references routing.log for analytics"

# ── Visual indicators section ─────────────────────────────────────────────────

assert_contains "$OCTO_MD" "CLAUDE OCTOPUS ACTIVATED" "has visual indicator banner template"

# ── Prohibited actions ────────────────────────────────────────────────────────

assert_contains "$OCTO_MD" "Prohibited" "has Prohibited Actions section"
assert_contains "$OCTO_MD" "MUST use Skill tool" "prohibits simulating workflow execution"

# ── No chain workflows documentation (removed — not implemented) ──────────────

if [[ $(grep -ci "chain workflow" "$OCTO_MD") -eq 0 ]]; then
  pass "no chain workflows documentation (removed unimplemented feature)"
else
  fail "no chain workflows documentation" "found 'chain workflow' — was supposed to be removed"
fi

# ── No model override example (security concern removed) ──────────────────────

if [[ $(grep -c "OCTOPUS_CODEX_MODEL" "$OCTO_MD") -eq 0 ]]; then
  pass "no model override example (security concern removed)"
else
  fail "no model override example" "found OCTOPUS_CODEX_MODEL — should be removed"
fi

# ── File size reduction ───────────────────────────────────────────────────────

LINE_COUNT=$(wc -l < "$OCTO_MD" | tr -d ' ')
if [[ $LINE_COUNT -le 250 ]]; then
  pass "file is $LINE_COUNT lines (reduced from 382)"
else
  fail "file size reduction" "file is $LINE_COUNT lines, expected <= 250 (was 382)"
fi
test_summary
