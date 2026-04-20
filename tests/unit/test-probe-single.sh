#!/usr/bin/env bash
# Tests for probe-single command: single-agent probe for multi-agentic skill dispatch (v8.54.0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "probe-single command: single-agent probe for multi-agentic skill dispatch (v8.54.0)"

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
trap 'rm -f "$ALL_SRC"' EXIT
cat "$ORCHESTRATE" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }
assert_contains() {
  local output="$1" pattern="$2" label="$3"
  echo "$output" | grep -qE "$pattern" && pass "$label" || fail "$label" "missing: $pattern"
}

# ── probe_single_agent function exists ────────────────────────────────────────

assert_contains "$(grep -c 'probe_single_agent()' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "probe_single_agent: function exists"

# ── probe-single dispatch case exists ─────────────────────────────────────────

assert_contains "$(grep -c 'probe-single)' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "probe-single: dispatch case exists"

# ── probe-single calls probe_single_agent ────────────────────────────────────

assert_contains "$(grep -A10 'probe-single)' "$ALL_SRC" | head -15)" \
  "probe_single_agent" "probe-single: dispatch calls probe_single_agent()"

# ── probe_single_agent writes result files ───────────────────────────────────

assert_contains "$(grep -A200 'probe_single_agent()' "$ALL_SRC" | head -220)" \
  'RESULTS_DIR.*agent_type.*task_id.*\.md' "probe_single_agent: writes result file to RESULTS_DIR"

# ── probe_single_agent calls apply_persona ───────────────────────────────────

assert_contains "$(grep -A100 'probe_single_agent()' "$ALL_SRC" | head -120)" \
  "apply_persona" "probe_single_agent: calls apply_persona()"

# ── probe_single_agent calls enforce_context_budget ──────────────────────────

assert_contains "$(grep -A100 'probe_single_agent()' "$ALL_SRC" | head -120)" \
  "enforce_context_budget" "probe_single_agent: calls enforce_context_budget()"

# ── probe_single_agent calls get_agent_command ───────────────────────────────

assert_contains "$(grep -A120 'probe_single_agent()' "$ALL_SRC" | head -140)" \
  "get_agent_command" "probe_single_agent: calls get_agent_command()"

# ── probe_single_agent has auth retry logic ──────────────────────────────────

assert_contains "$(grep -A200 'probe_single_agent()' "$ALL_SRC" | head -220)" \
  "auth_attempt|max_auth_retries" "probe_single_agent: has auth retry logic"

# ── probe_single_agent outputs result file path ──────────────────────────────

assert_contains "$(grep -A250 'probe_single_agent()' "$ALL_SRC" | head -270)" \
  'echo.*result_file' "probe_single_agent: outputs result file path on stdout"

# ── probe_single_agent handles timeout status ────────────────────────────────

assert_contains "$(grep -A250 'probe_single_agent()' "$ALL_SRC" | head -270)" \
  "Status: TIMEOUT" "probe_single_agent: handles TIMEOUT status"

# ── probe_single_agent handles failure status ────────────────────────────────

assert_contains "$(grep -A250 'probe_single_agent()' "$ALL_SRC" | head -270)" \
  "Status: FAILED" "probe_single_agent: handles FAILED status"

# ── flow-discover.md references probe-single ─────────────────────────────────

FLOW_DISCOVER="$PROJECT_ROOT/.claude/skills/flow-discover.md"
assert_contains "$(grep -c 'probe-single' "$FLOW_DISCOVER" 2>/dev/null || echo 0)" \
  "[1-9]" "flow-discover.md: references probe-single command"

# ── flow-discover.md has intensity parsing ───────────────────────────────────

assert_contains "$(grep -c 'intensity' "$FLOW_DISCOVER" 2>/dev/null || echo 0)" \
  "[1-9]" "flow-discover.md: has intensity parsing"

# ── flow-discover.md uses Agent tool (not single Bash probe) ─────────────────

assert_contains "$(grep -c 'run_in_background.*true' "$FLOW_DISCOVER" 2>/dev/null || echo 0)" \
  "[1-9]" "flow-discover.md: uses Agent(run_in_background=true)"

# ── flow-discover.md preserves test markers ──────────────────────────────────

# Use grep -c on file directly to avoid both arg size limits and SIGPIPE (grep -q + pipefail)
[[ $(grep -c "execution_mode: enforced" "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: preserves execution_mode: enforced" || \
  fail "flow-discover.md: preserves execution_mode: enforced" "missing: execution_mode: enforced"

[[ $(grep -c "orchestrate_sh_executed" "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: preserves orchestrate_sh_executed validation gate" || \
  fail "flow-discover.md: preserves orchestrate_sh_executed validation gate" "missing: orchestrate_sh_executed"

[[ $(grep -c "synthesis_file_exists" "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: preserves synthesis_file_exists validation gate" || \
  fail "flow-discover.md: preserves synthesis_file_exists validation gate" "missing: synthesis_file_exists"

[[ $(grep -c "probe-synthesis" "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: preserves probe-synthesis reference" || \
  fail "flow-discover.md: preserves probe-synthesis reference" "missing: probe-synthesis"

[[ $(grep -c "Perplexity" "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: preserves Perplexity indicator" || \
  fail "flow-discover.md: preserves Perplexity indicator" "missing: Perplexity"

[[ $(grep -c "EXECUTION CONTRACT" "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: preserves EXECUTION CONTRACT header" || \
  fail "flow-discover.md: preserves EXECUTION CONTRACT header" "missing: EXECUTION CONTRACT"

# ── research.md has intensity AskUserQuestion ────────────────────────────────

RESEARCH_CMD="$PROJECT_ROOT/.claude/commands/research.md"
assert_contains "$(grep -c 'Research Intensity' "$RESEARCH_CMD" 2>/dev/null || echo 0)" \
  "[1-9]" "research.md: has Research Intensity AskUserQuestion"

assert_contains "$(grep -c 'intensity=' "$RESEARCH_CMD" 2>/dev/null || echo 0)" \
  "[1-9]" "research.md: passes intensity in Skill args"

# ── discover.md aligns intensity question ────────────────────────────────────

DISCOVER_CMD="$PROJECT_ROOT/.claude/commands/discover.md"
assert_contains "$(grep -c 'Research Intensity' "$DISCOVER_CMD" 2>/dev/null || echo 0)" \
  "[1-9]" "discover.md: has Research Intensity header"

assert_contains "$(grep -c 'intensity=' "$DISCOVER_CMD" 2>/dev/null || echo 0)" \
  "[1-9]" "discover.md: passes intensity in Skill args"

# ── research report template structure ──────────────────────────────────────

[[ $(grep -c 'Executive Summary' "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: synthesis template has Executive Summary section" || \
  fail "flow-discover.md: synthesis template has Executive Summary section" "missing: Executive Summary"

[[ $(grep -c 'Sources' "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: synthesis template has Sources section" || \
  fail "flow-discover.md: synthesis template has Sources section" "missing: Sources"

[[ $(grep -c 'Methodology' "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: synthesis template has Methodology section" || \
  fail "flow-discover.md: synthesis template has Methodology section" "missing: Methodology"

[[ $(grep -c 'inference' "$FLOW_DISCOVER") -gt 0 ]] && \
  pass "flow-discover.md: quality rule requires source or inference marking" || \
  fail "flow-discover.md: quality rule requires source or inference marking" "missing: inference rule"

# ── backward compat: probe_discover still exists ─────────────────────────────

assert_contains "$(grep -c 'probe_discover()' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "probe_discover: original function still exists (backward compat)"

# ── backward compat: discover|research|probe dispatch still exists ───────────

assert_contains "$(grep -c 'discover|research|probe)' "$ALL_SRC" 2>/dev/null || echo 0)" \
  "[1-9]" "discover|research|probe: original dispatch still exists (backward compat)"
test_summary
