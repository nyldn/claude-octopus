#!/usr/bin/env bash
# Tests for metric verification mode in skill-iterative-loop.md and commands/loop.md (v9.8.0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "metric verification mode in skill-iterative-loop.md and commands/loop.md (v9.8.0)"

SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-iterative-loop.md"
COMMAND_FILE="$PROJECT_ROOT/.claude/commands/loop.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

SKILL_CONTENT="$(<"$SKILL_FILE")"
COMMAND_CONTENT="$(<"$COMMAND_FILE")"

# ── Skill: Metric Verification Mode section exists ───────────────────────────

if grep -q '## Metric Verification Mode' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: has 'Metric Verification Mode' section"
else
    fail "skill: has 'Metric Verification Mode' section" "section heading not found"
fi

# ── Skill: git commit with experiment: prefix ────────────────────────────────

if grep -q 'experiment:' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: mentions git commit with experiment: prefix"
else
    fail "skill: mentions git commit with experiment: prefix" "experiment: prefix not found"
fi

# ── Skill: git revert on regression ──────────────────────────────────────────

if grep -q 'git revert HEAD --no-edit' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: mentions git revert on regression"
else
    fail "skill: mentions git revert on regression" "git revert pattern not found"
fi

# ── Skill: Guard command documented ──────────────────────────────────────────

if grep -q 'Guard.*command' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: documents Guard command"
else
    fail "skill: documents Guard command" "Guard command not documented"
fi

# ── Skill: JSONL experiment log ──────────────────────────────────────────────

if grep -q '\.jsonl' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: mentions JSONL experiment log"
else
    fail "skill: mentions JSONL experiment log" ".jsonl not found"
fi

# ── Skill: experiments directory path ────────────────────────────────────────

if grep -q '\.claude-octopus/experiments' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: specifies .claude-octopus/experiments/ directory"
else
    fail "skill: specifies .claude-octopus/experiments/ directory" "experiments directory path not found"
fi

# ── Skill: Direction parameter ───────────────────────────────────────────────

if grep -q 'Direction.*higher.*lower\|Direction.*lower.*higher' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: documents Direction parameter (higher/lower)"
else
    fail "skill: documents Direction parameter (higher/lower)" "Direction higher|lower not found"
fi

# ── Skill: baseline on iteration 0 ──────────────────────────────────────────

if grep -q 'Iteration 0.*Baseline\|Establish Baseline\|baseline' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: establishes baseline on iteration 0"
else
    fail "skill: establishes baseline on iteration 0" "baseline establishment not found"
fi

# ── Skill: resume behavior documented ────────────────────────────────────────

if grep -q 'Resume Behavior\|resume.*experiment' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: documents resume behavior"
else
    fail "skill: documents resume behavior" "resume behavior not documented"
fi

# ── Skill: atomic one-change-per-iteration principle ─────────────────────────

if grep -q 'One change per iteration\|one atomic change\|ONE focused change' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: enforces one change per iteration"
else
    fail "skill: enforces one change per iteration" "atomic change principle not found"
fi

# ── Skill: simplicity wins principle ─────────────────────────────────────────

if grep -q 'Simplicity wins\|simplicity wins' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: includes simplicity wins principle"
else
    fail "skill: includes simplicity wins principle" "simplicity wins not found"
fi

# ── Skill: mechanical verification (not subjective) ─────────────────────────

if grep -q 'Mechanical verification\|mechanical.*verification\|no subjective' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: emphasizes mechanical (not subjective) verification"
else
    fail "skill: emphasizes mechanical (not subjective) verification" "mechanical verification not found"
fi

# ── Skill: log entry has required JSON fields ────────────────────────────────

has_all_fields=true
for field in iteration timestamp metric best status description commit; do
    if ! grep -q "\"$field\"" <<< "$SKILL_CONTENT" 2>/dev/null; then
        has_all_fields=false
        break
    fi
done
if $has_all_fields; then
    pass "skill: log entry has all required JSON fields"
else
    fail "skill: log entry has all required JSON fields" "missing field: $field"
fi

# ── Skill: fallback to standard behavior ─────────────────────────────────────

if grep -q 'Falls back.*standard\|Falls back.*current\|no metric.*specified' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: falls back to standard behavior without metric"
else
    fail "skill: falls back to standard behavior without metric" "fallback behavior not documented"
fi

# ── Skill: Iterations parameter (bounded mode) ──────────────────────────────

if grep -q 'Iterations.*N\|Iterations.*max' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: documents Iterations parameter for bounded mode"
else
    fail "skill: documents Iterations parameter for bounded mode" "Iterations parameter not found"
fi

# ── Skill: kept/reverted/error statuses ──────────────────────────────────────

has_all_statuses=true
for status in kept reverted error; do
    if ! grep -q "\"$status\"" <<< "$SKILL_CONTENT" 2>/dev/null; then
        has_all_statuses=false
        break
    fi
done
if $has_all_statuses; then
    pass "skill: documents kept/reverted/error statuses"
else
    fail "skill: documents kept/reverted/error statuses" "missing status: $status"
fi

# ── Skill: no attribution references ─────────────────────────────────────────

if grep -qi 'autoresearch\|karpathy\|pi-autoresearch' <<< "$SKILL_CONTENT" 2>/dev/null; then
    fail "skill: no attribution references" "found prohibited attribution reference"
else
    pass "skill: no attribution references"
fi

# ── Skill: original content preserved ────────────────────────────────────────

if grep -q '## The Process' <<< "$SKILL_CONTENT" 2>/dev/null; then
    pass "skill: original content preserved (The Process section exists)"
else
    fail "skill: original content preserved (The Process section exists)" "original section missing"
fi

# ── Command: references metric mode ──────────────────────────────────────────

if grep -q 'Metric.*Mode\|metric.*mode\|Metric.*Verification' <<< "$COMMAND_CONTENT" 2>/dev/null; then
    pass "command: references metric mode"
else
    fail "command: references metric mode" "metric mode not referenced in loop.md"
fi

# ── Command: shows metric example ────────────────────────────────────────────

if grep -q 'Metric:.*Direction:' <<< "$COMMAND_CONTENT" 2>/dev/null; then
    pass "command: shows metric mode example with Metric: and Direction:"
else
    fail "command: shows metric mode example with Metric: and Direction:" "example not found"
fi

# ── Command: documents Guard parameter ───────────────────────────────────────

if grep -q 'Guard:' <<< "$COMMAND_CONTENT" 2>/dev/null; then
    pass "command: documents Guard parameter"
else
    fail "command: documents Guard parameter" "Guard: not found in loop.md"
fi

# ── Command: documents Iterations parameter ──────────────────────────────────

if grep -q 'Iterations:' <<< "$COMMAND_CONTENT" 2>/dev/null; then
    pass "command: documents Iterations parameter"
else
    fail "command: documents Iterations parameter" "Iterations: not found in loop.md"
fi

# ── Command: original content preserved ──────────────────────────────────────

if grep -q '## Integration with Other Skills' <<< "$COMMAND_CONTENT" 2>/dev/null; then
    pass "command: original content preserved (Integration section exists)"
else
    fail "command: original content preserved (Integration section exists)" "original section missing"
fi

# ── Command: no attribution references ───────────────────────────────────────

if grep -qi 'autoresearch\|karpathy\|pi-autoresearch' <<< "$COMMAND_CONTENT" 2>/dev/null; then
    fail "command: no attribution references" "found prohibited attribution reference"
else
    pass "command: no attribution references"
fi
test_summary
