#!/bin/bash
# Test suite for credential isolation (v8.32.0)
# Verifies build_provider_env() scopes keys per provider and
# no cross-provider credential leakage occurs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "for credential isolation (v8.32.0)"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCH="$PLUGIN_DIR/scripts/orchestrate.sh"
# v9.12: Search orchestrate.sh + lib/*.sh for decomposed functions
ALL_SRC=$(mktemp)
cat "$ORCH" "$PLUGIN_DIR/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT

PASS=0
FAIL=0
TOTAL=0

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

suite() {
  echo ""
  echo "━━━ $1 ━━━"
}

# ─────────────────────────────────────────────────────────────────────
# Suite 1: build_provider_env() function exists and is correct
# ─────────────────────────────────────────────────────────────────────
suite "1. build_provider_env() Function"

# 1.1 Function exists
if grep -q '^build_provider_env()' "$ALL_SRC"; then
  pass "build_provider_env() function exists"
else
  fail "build_provider_env() function missing"
fi

# 1.2 Codex scoping — only OPENAI_API_KEY
CODEX_ENV=$(grep -A5 'codex\*)' "$ALL_SRC" | grep 'PROVIDER_ENV_ARRAY=.*env -i' | head -1)
if echo "$CODEX_ENV" | grep -q 'OPENAI_API_KEY'; then
  pass "Codex env includes OPENAI_API_KEY"
else
  fail "Codex env missing OPENAI_API_KEY"
fi

if echo "$CODEX_ENV" | grep -q 'GEMINI_API_KEY'; then
  fail "Codex env leaks GEMINI_API_KEY"
else
  pass "Codex env does NOT contain GEMINI_API_KEY"
fi

# 1.3 Gemini scoping — only GEMINI_API_KEY + GOOGLE_API_KEY
GEMINI_ENV=$(grep -A5 'gemini\*)' "$ALL_SRC" | grep 'PROVIDER_ENV_ARRAY=.*env -i' | head -1)
if echo "$GEMINI_ENV" | grep -q 'GEMINI_API_KEY'; then
  pass "Gemini env includes GEMINI_API_KEY"
else
  fail "Gemini env missing GEMINI_API_KEY"
fi

if echo "$GEMINI_ENV" | grep -q 'OPENAI_API_KEY'; then
  fail "Gemini env leaks OPENAI_API_KEY"
else
  pass "Gemini env does NOT contain OPENAI_API_KEY"
fi

# 1.4 Perplexity — shell function provider, env -i skipped (#300)
# perplexity_execute is a bash function dispatched by get_agent_command();
# env -i cannot exec shell functions, so build_provider_env returns empty.
PERP_CASE=$(grep -A50 'build_provider_env()' "$ALL_SRC" | grep -A5 'perplexity\*)' | head -6)
PERP_ENV=$(echo "$PERP_CASE" | grep 'env -i' | head -1 || true)
if echo "$PERP_CASE" | grep -q 'resolve_provider_env.*PERPLEXITY_API_KEY'; then
  pass "Perplexity resolves PERPLEXITY_API_KEY before dispatch"
else
  fail "Perplexity missing PERPLEXITY_API_KEY resolve"
fi

if echo "$PERP_CASE" | grep -q 'return 0'; then
  pass "Perplexity correctly returns empty env prefix (shell function)"
else
  fail "Perplexity should return 0 (no env -i for shell function provider)"
fi

if grep -q 'PROVIDER_ENV_ARRAY=()' "$ALL_SRC" && grep -q 'PROVIDER_ENV_ARRAY\[@\]' "$ALL_SRC"; then
  pass "Provider env uses argv array tokens"
else
  fail "Provider env array token handling missing"
fi

if grep -A20 'build_provider_env()' "$ALL_SRC" | grep -q 'MINGW.*return 0\|MSYS.*return 0\|Windows.*return 0'; then
  fail "Windows still disables env isolation instead of preserving PATH spaces with arrays"
else
  pass "Windows PATH spaces do not disable env isolation"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 2: build_provider_env() is wired into spawn_agent()
# ─────────────────────────────────────────────────────────────────────
suite "2. spawn_agent() Integration"

# 2.1 spawn_agent calls build_provider_env
if grep -c 'build_provider_env' "$ALL_SRC" | grep -q '^[2-9]\|^[1-9][0-9]'; then
  pass "build_provider_env called from spawn_agent (not just defined)"
else
  fail "build_provider_env is dead code — only defined, never called"
fi

# 2.2 Credential isolation log line exists
if grep -q 'Credential isolation active' "$ALL_SRC"; then
  pass "Credential isolation debug logging present"
else
  fail "Missing credential isolation debug logging"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 3: /octo:parallel launch.sh credential stripping
# ─────────────────────────────────────────────────────────────────────
suite "3. Parallel Work Package Isolation"

PARALLEL_SKILL="$PLUGIN_DIR/.claude/skills/flow-parallel.md"

# 3.1 launch.sh template strips provider keys
if grep -q 'unset OPENAI_API_KEY' "$PARALLEL_SKILL"; then
  pass "launch.sh template strips OPENAI_API_KEY"
else
  fail "launch.sh template does NOT strip OPENAI_API_KEY"
fi

if grep -q 'unset.*GEMINI_API_KEY' "$PARALLEL_SKILL"; then
  pass "launch.sh template strips GEMINI_API_KEY"
else
  fail "launch.sh template does NOT strip GEMINI_API_KEY"
fi

if grep -q 'unset.*PERPLEXITY_API_KEY' "$PARALLEL_SKILL"; then
  pass "launch.sh template strips PERPLEXITY_API_KEY"
else
  fail "launch.sh template does NOT strip PERPLEXITY_API_KEY"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 4: MCP Server env filtering
# ─────────────────────────────────────────────────────────────────────
suite "4. MCP Server Credential Handling"

MCP_SRC="$PLUGIN_DIR/mcp-server/src/index.ts"

# 4.1 MCP server does not unconditionally pass all keys
if grep -q 'OPENAI_API_KEY: process.env.OPENAI_API_KEY,' "$MCP_SRC"; then
  fail "MCP server unconditionally passes OPENAI_API_KEY"
else
  pass "MCP server conditionally passes OPENAI_API_KEY"
fi

# 4.2 MCP server uses conditional spread
if grep -c 'process.env.OPENAI_API_KEY &&' "$MCP_SRC" | grep -q '^[1-9]'; then
  pass "MCP server uses conditional spread for provider keys"
else
  fail "MCP server missing conditional spread pattern"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 5: Security flag and disable switch
# ─────────────────────────────────────────────────────────────────────
suite "5. Security Controls"

# 5.1 OCTOPUS_SECURITY_V870 disable switch exists
if grep -q 'OCTOPUS_SECURITY_V870' "$ALL_SRC"; then
  pass "OCTOPUS_SECURITY_V870 disable switch exists"
else
  fail "Missing OCTOPUS_SECURITY_V870 disable switch"
fi

# 5.2 Security defaults to enabled (true)
if grep -q 'OCTOPUS_SECURITY_V870:-true' "$ALL_SRC"; then
  pass "Security defaults to enabled"
else
  fail "Security does not default to enabled"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 6: No literal quotes in env values (Issue #117)
# read -ra treats escaped quotes as literal characters, corrupting
# HOME/PATH and causing 401 auth failures in Codex CLI.
# ─────────────────────────────────────────────────────────────────────
suite "6. No Literal Quotes in build_provider_env() (Issue #117)"

# 6.1 Codex env line must not contain escaped quotes around values
if echo "$CODEX_ENV" | grep -q '\\\"'; then
  fail "Codex env contains escaped quotes — causes literal quote chars after read -ra (Issue #117)"
else
  pass "Codex env free of escaped quotes"
fi

# 6.2 Gemini env line must not contain escaped quotes around values
if echo "$GEMINI_ENV" | grep -q '\\\"'; then
  fail "Gemini env contains escaped quotes — causes literal quote chars after read -ra (Issue #117)"
else
  pass "Gemini env free of escaped quotes"
fi

# 6.3 Perplexity env line must not contain escaped quotes around values
if echo "$PERP_ENV" | grep -q '\\\"'; then
  fail "Perplexity env contains escaped quotes — causes literal quote chars after read -ra (Issue #117)"
else
  pass "Perplexity env free of escaped quotes"
fi

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
test_summary
