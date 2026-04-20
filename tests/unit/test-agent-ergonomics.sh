#!/usr/bin/env bash
# Tests for agent ergonomics: readonly frontmatter, user-scope agents, resume command
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "agent ergonomics: readonly frontmatter, user-scope agents, resume command"

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"
# Functions decomposed to lib/ in v9.7.7+; combine all sources for grep
ALL_SRC=$(mktemp)
trap 'rm -f "$ALL_SRC"' EXIT
cat "$ORCHESTRATE" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }
assert_contains() {
  local output="$1" pattern="$2" label="$3"
  echo "$output" | grep -qE "$pattern" && pass "$label" || fail "$label" "missing: $pattern"
}

# ── readonly frontmatter ─────────────────────────────────────────────────────

assert_contains "$(grep -c 'get_agent_readonly' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "get_agent_readonly: function exists"

# apply_tool_policy must accept a 3rd arg and check is_readonly
assert_contains "$(grep -A15 'apply_tool_policy()' "$ALL_SRC" | head -20)" \
  "agent_name" "apply_tool_policy: accepts agent_name 3rd param"

# apply_persona must accept a 4th arg and pass it through
assert_contains "$(grep -A8 'apply_persona()' "$ALL_SRC" | head -12)" \
  "agent_name" "apply_persona: accepts agent_name 4th param"

# readonly: true triggers a TOOL POLICY restriction message
assert_contains "$(grep -E 'readonly.*true|is_readonly' "$ALL_SRC" | head -5)" \
  "is_readonly|readonly" "readonly: is_readonly guard exists in apply_tool_policy"

# get_agent_readonly parses within frontmatter delimiters (not just head -20)
assert_contains "$(grep -A15 'get_agent_readonly()' "$ALL_SRC")" \
  "awk|BEGIN.*in_fm|frontmatter" "get_agent_readonly: parses within frontmatter delimiters"

# ── readonly example persona ──────────────────────────────────────────────────
ARCHITECT="$PROJECT_ROOT/agents/personas/backend-architect.md"
assert_contains "$(grep 'readonly' "$ARCHITECT" 2>/dev/null)" \
  "readonly.*true" "backend-architect: has readonly: true frontmatter"

# ── user-scope agents ─────────────────────────────────────────────────────────
assert_contains "$(grep -c 'USER_AGENTS_DIR' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "USER_AGENTS_DIR: constant defined"

assert_contains "$(grep 'USER_AGENTS_DIR' "$ALL_SRC" | grep 'claude/agents' | head -3)" \
  "claude/agents" "USER_AGENTS_DIR: points to ~/.claude/agents"

assert_contains "$(grep -A15 'get_agent_description()' "$ALL_SRC" | head -20)" \
  "USER_AGENTS_DIR" "get_agent_description: checks USER_AGENTS_DIR fallback"

# ── agent-resume dispatch ────────────────────────────────────────────────────
assert_contains "$(grep -c 'agent-resume' "$ORCHESTRATE" 2>/dev/null || echo 0)" \
  "[1-9]" "agent-resume: dispatch case exists in orchestrate.sh"

assert_contains "$(grep -A5 'agent-resume' "$ORCHESTRATE" | head -10)" \
  "resume_agent" "agent-resume: calls resume_agent() function"

# ── /octo:resume command file ─────────────────────────────────────────────────
RESUME_CMD="$PROJECT_ROOT/.claude/commands/resume.md"
assert_contains "$(cat "$RESUME_CMD" 2>/dev/null)" \
  "agent-resume" "resume command: references agent-resume backend"
assert_contains "$(cat "$RESUME_CMD" 2>/dev/null)" \
  "Agent Teams" "resume command: mentions Agent Teams requirement"
assert_contains "$(grep 'resume' "$PROJECT_ROOT/.claude-plugin/plugin.json" 2>/dev/null)" \
  "resume" "resume command: registered in plugin.json"
test_summary
