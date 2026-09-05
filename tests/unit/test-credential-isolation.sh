#!/bin/bash
# Test suite for credential isolation (v8.32.0)
# Verifies build_provider_env() scopes keys per provider and
# no cross-provider credential leakage occurs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "for credential isolation (v8.32.0)"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$PLUGIN_DIR"
ORCH="$PLUGIN_DIR/scripts/orchestrate.sh"
# v9.12: Search orchestrate.sh + lib/*.sh for decomposed functions.
# Keep all suite temporaries under the test framework's TEST_TMP_DIR so its
# existing EXIT/INT/TERM cleanup remains authoritative.
ALL_SRC="$TEST_TMP_DIR/all-src"
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

# 1.2 Codex scoping — default OpenAI credential or the effective configured
# provider credential, never both.
CODEX_DEFAULT_HOME="$TEST_TMP_DIR/codex-default-home"
mkdir -p "$CODEX_DEFAULT_HOME"
test_case "Codex default provider includes OPENAI_API_KEY"
codex_default_env=$(HOME="$CODEX_DEFAULT_HOME" OPENAI_API_KEY="openai-test-key" bash -c '
  set -eo pipefail
  unset CODEX_HOME
  source "$1/scripts/lib/provider-routing.sh"
  build_provider_env codex
  printf "%s\n" "${PROVIDER_ENV_ARRAY[@]}"
' _ "$PLUGIN_DIR")
if echo "$codex_default_env" | grep -qx 'OPENAI_API_KEY=openai-test-key'; then
  test_pass
else
  test_fail "Codex default env missing OPENAI_API_KEY"
fi

if echo "$codex_default_env" | grep -q 'GEMINI_API_KEY'; then
  fail "Codex env leaks GEMINI_API_KEY"
else
  pass "Codex env does NOT contain GEMINI_API_KEY"
fi

# 1.2b Codex CLI config preservation — CODEX_HOME + configured env_key
CODEX_RUNTIME_HOME="$TEST_TMP_DIR/codex-runtime"
mkdir -p "$CODEX_RUNTIME_HOME"
cat > "$CODEX_RUNTIME_HOME/config.toml" <<'EOF'
model_provider = "router"
model = "example/model"

[model_providers.router]
name = "Router"
base_url = "https://router.example/v1"
env_key = "ROUTER_API_KEY"
wire_api = "chat"
EOF
OLD_HOME="${HOME:-}"
OLD_CODEX_HOME="${CODEX_HOME:-}"
OLD_OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OLD_ROUTER_API_KEY="${ROUTER_API_KEY:-}"
OLD_GEMINI_API_KEY="${GEMINI_API_KEY:-}"
export HOME="$CODEX_RUNTIME_HOME-home"
export CODEX_HOME="$CODEX_RUNTIME_HOME"
export OPENAI_API_KEY="openai-test-key"
export ROUTER_API_KEY="router-test-key"
export GEMINI_API_KEY="gemini-should-not-leak"
source "$PLUGIN_DIR/scripts/lib/provider-routing.sh"
build_provider_env codex
CODEX_RUNTIME_ENV=" ${PROVIDER_ENV_ARRAY[*]} "
if echo "$CODEX_RUNTIME_ENV" | grep -q " CODEX_HOME=$CODEX_RUNTIME_HOME "; then
  pass "Codex env preserves CODEX_HOME"
else
  fail "Codex env missing CODEX_HOME"
fi
if echo "$CODEX_RUNTIME_ENV" | grep -q " ROUTER_API_KEY=router-test-key "; then
  pass "Codex env includes config.toml env_key"
else
  fail "Codex env missing config.toml env_key"
fi
if echo "$CODEX_RUNTIME_ENV" | grep -q " OPENAI_API_KEY="; then
  fail "Codex configured provider receives unused OPENAI_API_KEY"
else
  pass "Codex configured provider omits unused OPENAI_API_KEY"
fi
if echo "$CODEX_RUNTIME_ENV" | grep -q " GEMINI_API_KEY="; then
  fail "Codex env leaks unrelated provider key"
else
  pass "Codex env does NOT leak unrelated provider key"
fi
export HOME="$OLD_HOME"
if [[ -n "$OLD_CODEX_HOME" ]]; then export CODEX_HOME="$OLD_CODEX_HOME"; else unset CODEX_HOME; fi
if [[ -n "$OLD_OPENAI_API_KEY" ]]; then export OPENAI_API_KEY="$OLD_OPENAI_API_KEY"; else unset OPENAI_API_KEY; fi
if [[ -n "$OLD_ROUTER_API_KEY" ]]; then export ROUTER_API_KEY="$OLD_ROUTER_API_KEY"; else unset ROUTER_API_KEY; fi
if [[ -n "$OLD_GEMINI_API_KEY" ]]; then export GEMINI_API_KEY="$OLD_GEMINI_API_KEY"; else unset GEMINI_API_KEY; fi
rm -rf "$CODEX_RUNTIME_HOME" "$CODEX_RUNTIME_HOME-home"

# 1.2c Codex provider credentials must follow the effective TOML provider,
# independent of table order, comments, and inactive profiles.
codex_fixture_env() {
  local fixture_home="$1"
  CODEX_HOME="$fixture_home" \
  HOME="$fixture_home/home" \
  OPENAI_API_KEY="openai-unused" \
  DIRECT_API_KEY="direct-unused" \
  ROUTER_API_KEY="router-selected" \
  UNUSED_API_KEY="unused-key" \
  bash -c '
    set -eo pipefail
    source "$1/scripts/lib/provider-routing.sh"
    build_provider_env codex
    printf "%s\n" "${PROVIDER_ENV_ARRAY[@]}"
  ' _ "$PLUGIN_DIR"
}

CODEX_REORDERED_HOME="$TEST_TMP_DIR/codex-reordered"
mkdir -p "$CODEX_REORDERED_HOME/home"
cat > "$CODEX_REORDERED_HOME/config.toml" <<'EOF'
model_provider = "router"

[model_providers.unused]
env_key = "UNUSED_API_KEY"

[model_providers.router]
env_key = "ROUTER_API_KEY"
EOF
test_case "Codex credential selection ignores provider table order"
reordered_env="$(codex_fixture_env "$CODEX_REORDERED_HOME")"
if [[ "$reordered_env" == *$'\nROUTER_API_KEY=router-selected'* || "$reordered_env" == ROUTER_API_KEY=router-selected* ]] \
  && [[ "$reordered_env" != *"UNUSED_API_KEY="* ]] \
  && [[ "$reordered_env" != *"OPENAI_API_KEY="* ]]; then
  test_pass
else
  test_fail "Codex forwarded a credential for an inactive provider"
fi

CODEX_PROFILE_HOME="$TEST_TMP_DIR/codex-profile"
mkdir -p "$CODEX_PROFILE_HOME/home"
cat > "$CODEX_PROFILE_HOME/config.toml" <<'EOF'
model_provider = "direct"
profile = "work"

[model_providers.direct]
env_key = "DIRECT_API_KEY"

[profiles.work]
model_provider = "router"

[model_providers.router]
env_key = "ROUTER_API_KEY"
EOF
test_case "Codex credential selection applies the active profile"
profile_env="$(codex_fixture_env "$CODEX_PROFILE_HOME")"
if [[ "$profile_env" == *"ROUTER_API_KEY=router-selected"* ]] \
  && [[ "$profile_env" != *"DIRECT_API_KEY="* ]] \
  && [[ "$profile_env" != *"OPENAI_API_KEY="* ]]; then
  test_pass
else
  test_fail "Codex ignored the active profile's provider"
fi

CODEX_COMMENT_HOME="$TEST_TMP_DIR/codex-comments"
mkdir -p "$CODEX_COMMENT_HOME/home"
cat > "$CODEX_COMMENT_HOME/config.toml" <<'EOF'
# model_provider = "unused"
model_provider = "router" # selected provider

[model_providers.unused]
# env_key = "UNUSED_API_KEY"
name = "text # is not a comment"

[model_providers.router]
env_key = "ROUTER_API_KEY" # selected credential
EOF
test_case "Codex credential selection parses TOML comments structurally"
comment_env="$(codex_fixture_env "$CODEX_COMMENT_HOME")"
if [[ "$comment_env" == *"ROUTER_API_KEY=router-selected"* ]] \
  && [[ "$comment_env" != *"UNUSED_API_KEY="* ]] \
  && [[ "$comment_env" != *"OPENAI_API_KEY="* ]]; then
  test_pass
else
  test_fail "Codex TOML comments changed credential selection"
fi

CODEX_MISSING_HOME="$TEST_TMP_DIR/codex-missing-key"
mkdir -p "$CODEX_MISSING_HOME/home"
cat > "$CODEX_MISSING_HOME/config.toml" <<'EOF'
model_provider = "router"

[model_providers.unused]
env_key = "UNUSED_API_KEY"

[model_providers.router]
base_url = "http://127.0.0.1:11434/v1"
EOF
test_case "Codex provider without env_key forwards no provider credential"
missing_env="$(codex_fixture_env "$CODEX_MISSING_HOME")"
if [[ "$missing_env" != *"UNUSED_API_KEY="* ]] \
  && [[ "$missing_env" != *"OPENAI_API_KEY="* ]] \
  && [[ "$missing_env" != *"DIRECT_API_KEY="* ]] \
  && [[ "$missing_env" != *"ROUTER_API_KEY="* ]]; then
  test_pass
else
  test_fail "Codex forwarded an unrelated key for a provider without env_key"
fi

test_case "Codex TOML fallback resolves the same effective provider"
fallback_key=$(OCTOPUS_FORCE_CODEX_TOML_FALLBACK=1 \
  python3 "$PLUGIN_DIR/scripts/helpers/read-codex-config.py" "$CODEX_PROFILE_HOME/config.toml")
if [[ "$fallback_key" == "ROUTER_API_KEY" ]]; then
  test_pass
else
  test_fail "fallback parser resolved '$fallback_key' instead of ROUTER_API_KEY"
fi

CODEX_INVALID_PROFILE_HOME="$TEST_TMP_DIR/codex-invalid-profile"
mkdir -p "$CODEX_INVALID_PROFILE_HOME/home"
cat > "$CODEX_INVALID_PROFILE_HOME/config.toml" <<'EOF'
model_provider = "router"
profile = "missing"

[model_providers.router]
env_key = "ROUTER_API_KEY"
EOF
test_case "Codex missing active profile fails closed"
invalid_profile_env="$(codex_fixture_env "$CODEX_INVALID_PROFILE_HOME")"
if [[ "$invalid_profile_env" != *"_API_KEY="* ]]; then
  test_pass
else
  test_fail "missing active profile caused a credential to be forwarded"
fi

# 1.3 AGY scoping — only Antigravity's explicit credentials/config are
# forwarded into its minimal environment. Legacy gemini IDs canonicalize to
# this same case arm and can never recover the retired Gemini credential path.
AGY_ENV=$(awk 'index($0, "agy*|antigravity)"){flag=1} flag{print; if (/^[[:space:]]*;;[[:space:]]*$/) exit}' "$PLUGIN_DIR/scripts/lib/provider-routing.sh")
if [[ -z "$AGY_ENV" ]]; then
  fail "AGY env block not found"
elif echo "$AGY_ENV" | grep -q 'AGY_AUTH_TOKEN' && \
     echo "$AGY_ENV" | grep -q 'ANTIGRAVITY_API_KEY'; then
  pass "AGY env includes Antigravity credentials"
else
  fail "AGY env missing Antigravity credentials"
fi

if echo "$AGY_ENV" | grep -q 'OPENAI_API_KEY'; then
  fail "AGY env leaks OPENAI_API_KEY"
else
  pass "AGY env does NOT contain OPENAI_API_KEY"
fi

# 1.4 Perplexity — shell function provider, env -i skipped (#300)
# perplexity_execute is a bash function dispatched by get_agent_command();
# env -i cannot exec shell functions, so build_provider_env returns empty.
PERP_CASE=$(grep -A10 '^[[:space:]]*perplexity\*)' "$PLUGIN_DIR/scripts/lib/provider-routing.sh" | head -11 || true)
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

# 1.6 Missing API keys are tolerated under set -e (#336)
for provider in codex agy perplexity openrouter; do
  test_case "build_provider_env $provider tolerates absent API keys under set -e"
  tmp_home="$TEST_TMP_DIR/missing-${provider}-home"
  tmp_pwd="$TEST_TMP_DIR/missing-${provider}-pwd"
  mkdir -p "$tmp_home" "$tmp_pwd"
  case_output=""
  if case_output=$(HOME="$tmp_home" bash -c '
      set -eo pipefail
      cd "$1"
      unset OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY PERPLEXITY_API_KEY OPENROUTER_API_KEY
      source "$2/scripts/lib/provider-routing.sh"
      build_provider_env "$3"
      echo ok
    ' _ "$tmp_pwd" "$PLUGIN_DIR" "$provider" 2>&1); then
    if [[ "$case_output" == *"ok"* ]]; then
      test_pass
    else
      test_fail "build_provider_env $provider returned without confirmation"
    fi
  else
    test_fail "build_provider_env $provider exited under set -e: $case_output"
  fi
done

# 1.7 AGY: unset credentials must not become empty-but-set variables.
test_case "AGY env omits Antigravity credentials entirely when unset"
tmp_home="$TEST_TMP_DIR/agy-unset-home"
mkdir -p "$tmp_home"
agy_env_output=$(HOME="$tmp_home" bash -c '
    set -eo pipefail
    unset AGY_AUTH_TOKEN ANTIGRAVITY_API_KEY
    cd "$1"
    source "$2/scripts/lib/provider-routing.sh"
    build_provider_env agy
    printf "%s\n" "${PROVIDER_ENV_ARRAY[@]}"
  ' _ "$tmp_home" "$PLUGIN_DIR" 2>&1)
if echo "$agy_env_output" | grep -qE '^(AGY_AUTH_TOKEN|ANTIGRAVITY_API_KEY)='; then
  test_fail "AGY credentials present as empty-but-set: $agy_env_output"
else
  test_pass
fi

# 1.8 AGY forwards its explicit config and API-key inputs.
test_case "AGY env forwards AGY_CONFIG and ANTIGRAVITY_API_KEY when set"
tmp_home="$TEST_TMP_DIR/agy-forward-home"
mkdir -p "$tmp_home"
agy_env_output=$(HOME="$tmp_home" AGY_CONFIG="/tmp/agy-config" ANTIGRAVITY_API_KEY="agy-key" bash -c '
    set -eo pipefail
    source "$1/scripts/lib/provider-routing.sh"
    build_provider_env agy
    printf "%s\n" "${PROVIDER_ENV_ARRAY[@]}"
  ' _ "$PLUGIN_DIR" 2>&1)
if echo "$agy_env_output" | grep -qx 'AGY_CONFIG=/tmp/agy-config' \
  && echo "$agy_env_output" | grep -qx 'ANTIGRAVITY_API_KEY=agy-key'; then
  test_pass
else
  test_fail "AGY_CONFIG/ANTIGRAVITY_API_KEY not forwarded: $agy_env_output"
fi

# 1.9 Tool-loop helpers execute model-requested shell commands, so they must
# receive only their selected credential and explicit runtime configuration.
test_case "qualified OpenAI-compatible tool-loop env excludes ambient secrets"
if OCTOPUS_AUDIT_SENTINEL="must-not-cross" \
   OPENAI_API_KEY="unrelated-openai-key" \
   OPENAI_COMPAT_API_KEY_ENV="COMPAT_TEST_KEY" \
   COMPAT_TEST_KEY="compat-test-key" \
   bash -c '
      set -eo pipefail
      source "$1/scripts/lib/provider-routing.sh"
      build_provider_env "openai-compatible-agent:vendor/model"
      "${PROVIDER_ENV_ARRAY[@]}" bash -c '\''
        set -e
        test -z "${OCTOPUS_AUDIT_SENTINEL:-}"
        test -z "${OPENAI_API_KEY:-}"
        test "${COMPAT_TEST_KEY:-}" = "compat-test-key"
      '\''
    ' _ "$PLUGIN_DIR"; then
  test_pass
else
  test_fail "qualified OpenAI-compatible helper inherited ambient credentials or lost its selected key"
fi

test_case "Atlas tool-loop env excludes ambient secrets"
if OCTOPUS_AUDIT_SENTINEL="must-not-cross" \
   OPENAI_API_KEY="unrelated-openai-key" \
   ATLASCLOUD_API_KEY="atlas-test-key" \
   bash -c '
      set -eo pipefail
      source "$1/scripts/lib/provider-routing.sh"
      build_provider_env "atlascloud-agent:qwen/model"
      "${PROVIDER_ENV_ARRAY[@]}" bash -c '\''
        set -e
        test -z "${OCTOPUS_AUDIT_SENTINEL:-}"
        test -z "${OPENAI_API_KEY:-}"
        test "${ATLASCLOUD_API_KEY:-}" = "atlas-test-key"
      '\''
    ' _ "$PLUGIN_DIR"; then
  test_pass
else
  test_fail "Atlas helper inherited ambient credentials or lost ATLASCLOUD_API_KEY"
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

PARALLEL_SKILL="$(resolve_claude_skill_path "flow-parallel")"

# 3.1 launch.sh template strips provider keys
if grep -q 'unset OPENAI_API_KEY' "$PARALLEL_SKILL"; then
  pass "launch.sh template strips OPENAI_API_KEY"
else
  fail "launch.sh template does NOT strip OPENAI_API_KEY"
fi

if grep -q 'unset.*AGY_AUTH_TOKEN.*ANTIGRAVITY_API_KEY' "$PARALLEL_SKILL"; then
  pass "launch.sh template strips AGY credentials"
else
  fail "launch.sh template does NOT strip AGY credentials"
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
SHARED_ADAPTER_SRC="$PLUGIN_DIR/shared/adapter-runtime.mjs"

# 4.1 MCP server does not unconditionally pass all keys
if grep -q 'OPENAI_API_KEY: process.env.OPENAI_API_KEY,' "$MCP_SRC"; then
  fail "MCP server unconditionally passes OPENAI_API_KEY"
else
  pass "MCP server conditionally passes OPENAI_API_KEY"
fi

# 4.2 MCP server uses the shared, value-filtered provider allowlist
if grep -q 'providerEnvironment(PROVIDER_ENV_ALLOWLIST)' "$MCP_SRC" &&
   grep -q '../../shared/adapter-runtime.mjs' "$MCP_SRC" &&
   grep -q 'export function providerEnvironment' "$SHARED_ADAPTER_SRC" &&
   jq -e '.schema_version == 1 and (.names | index("OPENAI_API_KEY") != null)' \
      "$PLUGIN_DIR/config/provider-env-allowlist.json" >/dev/null; then
  pass "MCP server uses the shared provider environment allowlist"
else
  fail "MCP server missing shared provider environment filtering"
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
if echo "$codex_default_env" | grep -q '\\\"'; then
  fail "Codex env contains escaped quotes — causes literal quote chars after read -ra (Issue #117)"
else
  pass "Codex env free of escaped quotes"
fi

# 6.2 AGY env line must not contain escaped quotes around values
if echo "$AGY_ENV" | grep -q '\\\"'; then
  fail "AGY env contains escaped quotes — causes literal quote chars after read -ra (Issue #117)"
else
  pass "AGY env free of escaped quotes"
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
