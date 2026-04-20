#!/bin/bash
# Test suite for CC v2.1.78-83 feature detection sync
# Validates new SUPPORTS_* flags, detection blocks, PLUGIN_DATA migration,
# hook registrations, agent frontmatter, and doctor tips.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "for CC v2.1.78-83 feature detection sync"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCH="$PLUGIN_DIR/scripts/orchestrate.sh"
PROVIDERS="$PLUGIN_DIR/scripts/lib/providers.sh"
HOOKS_JSON="$PLUGIN_DIR/.claude-plugin/hooks.json"
AGENTS_DIR="$PLUGIN_DIR/agents/personas"
HOOKS_DIR="$PLUGIN_DIR/hooks"
DOCTOR="$PLUGIN_DIR/scripts/lib/doctor.sh"

# Concatenate all sources for grep-based analysis
ALL_SRC=$(mktemp)
trap 'rm -f "$ALL_SRC"' EXIT
cat "$ORCH" "$PLUGIN_DIR/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

PASS=0
FAIL=0
TOTAL=0

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

suite() {
  echo ""
  echo "━━━ $1 ━━━"
}

# ── 1. Flag Declarations ─────────────────────────────────────────────────────
suite "Flag Declarations in orchestrate.sh"

for flag in SUPPORTS_STOP_FAILURE_HOOK SUPPORTS_PLUGIN_DATA_DIR SUPPORTS_AGENT_EFFORT \
            SUPPORTS_CWD_CHANGED_HOOK SUPPORTS_FILE_CHANGED_HOOK SUPPORTS_MANAGED_SETTINGS_D \
            SUPPORTS_ENV_SCRUB SUPPORTS_AGENT_INITIAL_PROMPT; do
  if grep -q "^${flag}=false" "$ORCH"; then
    pass "$flag declared"
  else
    fail "$flag declared" "not found in orchestrate.sh"
  fi
done

# ── 2. Detection Blocks ──────────────────────────────────────────────────────
suite "Version Detection Blocks in providers.sh"

if grep -q 'version_compare.*CLAUDE_CODE_VERSION.*2\.1\.78' "$PROVIDERS"; then
  pass "v2.1.78 detection block exists"
else
  fail "v2.1.78 detection block exists" "not found in providers.sh"
fi

if grep -q 'version_compare.*CLAUDE_CODE_VERSION.*2\.1\.83' "$PROVIDERS"; then
  pass "v2.1.83 detection block exists"
else
  fail "v2.1.83 detection block exists" "not found in providers.sh"
fi

# Verify flags are set in the correct version blocks
if grep -A5 '2\.1\.78' "$PROVIDERS" | grep -q 'SUPPORTS_STOP_FAILURE_HOOK=true'; then
  pass "STOP_FAILURE_HOOK set in v2.1.78 block"
else
  fail "STOP_FAILURE_HOOK set in v2.1.78 block" "flag not in correct version block"
fi

if grep -A8 '2\.1\.83' "$PROVIDERS" | grep -q 'SUPPORTS_CWD_CHANGED_HOOK=true'; then
  pass "CWD_CHANGED_HOOK set in v2.1.83 block"
else
  fail "CWD_CHANGED_HOOK set in v2.1.83 block" "flag not in correct version block"
fi

# ── 3. PLUGIN_DATA Migration ─────────────────────────────────────────────────
suite "CLAUDE_PLUGIN_DATA Workspace Migration"

if grep -q 'CLAUDE_PLUGIN_DATA' "$ORCH"; then
  pass "WORKSPACE_DIR checks CLAUDE_PLUGIN_DATA"
else
  fail "WORKSPACE_DIR checks CLAUDE_PLUGIN_DATA" "not referenced in orchestrate.sh"
fi

# Verify it's checked BEFORE the legacy fallback
plugin_data_line=$(grep -n 'CLAUDE_PLUGIN_DATA' "$ORCH" | head -1 | cut -d: -f1)
legacy_line=$(grep -n 'claude-octopus' "$ORCH" | grep WORKSPACE | head -1 | cut -d: -f1)
if [[ -n "$plugin_data_line" && -n "$legacy_line" && "$plugin_data_line" -lt "$legacy_line" ]]; then
  pass "CLAUDE_PLUGIN_DATA checked before legacy fallback"
else
  fail "CLAUDE_PLUGIN_DATA checked before legacy fallback" "order issue: plugin_data=$plugin_data_line legacy=$legacy_line"
fi

# ── 4. Hook Registrations ────────────────────────────────────────────────────
suite "Hook Event Registrations"

if grep -q '"StopFailure"' "$HOOKS_JSON"; then
  pass "StopFailure registered in hooks.json"
else
  fail "StopFailure registered in hooks.json" "event not found"
fi

if grep -q '"CwdChanged"' "$HOOKS_JSON"; then
  pass "CwdChanged registered in hooks.json"
else
  fail "CwdChanged registered in hooks.json" "event not found"
fi

# Verify hook scripts exist and are executable
if [[ -x "$HOOKS_DIR/stop-failure-log.sh" ]]; then
  pass "stop-failure-log.sh exists and is executable"
else
  fail "stop-failure-log.sh exists and is executable" "missing or not executable"
fi

if [[ -x "$HOOKS_DIR/cwd-changed.sh" ]]; then
  pass "cwd-changed.sh exists and is executable"
else
  fail "cwd-changed.sh exists and is executable" "missing or not executable"
fi

# ── 5. Agent Frontmatter ─────────────────────────────────────────────────────
suite "Agent effort/maxTurns/initialPrompt Frontmatter"

# effort: high on research agents
for agent in code-reviewer security-auditor debugger performance-engineer docs-architect; do
  if grep -q '^effort: high' "$AGENTS_DIR/${agent}.md" 2>/dev/null; then
    pass "$agent has effort: high"
  else
    fail "$agent has effort: high" "missing or wrong value"
  fi
done

# effort: medium on balanced agents
for agent in backend-architect frontend-developer database-architect tdd-orchestrator ai-engineer; do
  if grep -q '^effort: medium' "$AGENTS_DIR/${agent}.md" 2>/dev/null; then
    pass "$agent has effort: medium"
  else
    fail "$agent has effort: medium" "missing or wrong value"
  fi
done

# maxTurns present on all agents
agents_without_maxturns=0
for f in "$AGENTS_DIR"/*.md; do
  if ! grep -q '^maxTurns:' "$f" 2>/dev/null; then
    agents_without_maxturns=$((agents_without_maxturns + 1))
  fi
done
if [[ "$agents_without_maxturns" -eq 0 ]]; then
  pass "All agents have maxTurns"
else
  fail "All agents have maxTurns" "$agents_without_maxturns agents missing maxTurns"
fi

# initialPrompt on key agents
for agent in code-reviewer security-auditor debugger performance-engineer; do
  if grep -q '^initialPrompt:' "$AGENTS_DIR/${agent}.md" 2>/dev/null; then
    pass "$agent has initialPrompt"
  else
    fail "$agent has initialPrompt" "missing"
  fi
done

# No invalid effort values
invalid_effort=$(grep -rh '^effort:' "$AGENTS_DIR/"*.md 2>/dev/null | { grep -vc 'effort: \(low\|medium\|high\|max\)' || true; })
invalid_effort="${invalid_effort// /}"
if [[ "${invalid_effort:-0}" -eq 0 ]]; then
  pass "No invalid effort values in agents"
else
  fail "No invalid effort values in agents" "$invalid_effort agents have invalid effort"
fi

# ── 6. Doctor Tips ────────────────────────────────────────────────────────────
suite "Doctor Tips"

if grep -q 'SUPPORTS_STOP_FAILURE_HOOK' "$DOCTOR"; then
  pass "Doctor checks StopFailure"
else
  fail "Doctor checks StopFailure" "missing tip"
fi

if grep -q 'SUPPORTS_CWD_CHANGED_HOOK' "$DOCTOR"; then
  pass "Doctor checks CwdChanged"
else
  fail "Doctor checks CwdChanged" "missing tip"
fi

if grep -q 'CLAUDE_PLUGIN_DATA' "$DOCTOR"; then
  pass "Doctor mentions CLAUDE_PLUGIN_DATA"
else
  fail "Doctor mentions CLAUDE_PLUGIN_DATA" "not referenced"
fi

# ── 7. Log Line Coverage ─────────────────────────────────────────────────────
suite "Detection Log Lines"

if grep -q 'StopFailure Hook.*SUPPORTS_STOP_FAILURE_HOOK' "$PROVIDERS"; then
  pass "Log line includes StopFailure Hook"
else
  fail "Log line includes StopFailure Hook" "not in providers.sh log output"
fi

if grep -q 'CwdChanged Hook.*SUPPORTS_CWD_CHANGED_HOOK' "$PROVIDERS"; then
  pass "Log line includes CwdChanged Hook"
else
  fail "Log line includes CwdChanged Hook" "not in providers.sh log output"
fi
test_summary
