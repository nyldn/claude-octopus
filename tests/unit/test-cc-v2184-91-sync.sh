#!/bin/bash
# Test suite for CC v2.1.84-91 feature detection sync (v9.18-v9.19)
# Validates 13 new SUPPORTS_* flags, 5 version cascade blocks,
# 3 new hook events, bin/octopus executable, doctor tips, and --bare wiring.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCH="$PLUGIN_DIR/scripts/orchestrate.sh"
PROVIDERS="$PLUGIN_DIR/scripts/lib/providers.sh"
DISPATCH="$PLUGIN_DIR/scripts/lib/dispatch.sh"
AGENT_UTILS="$PLUGIN_DIR/scripts/lib/agent-utils.sh"
HOOKS_JSON="$PLUGIN_DIR/.claude-plugin/hooks.json"
HOOKS_DIR="$PLUGIN_DIR/hooks"
DOCTOR="$PLUGIN_DIR/scripts/lib/doctor.sh"

# Concatenate all sources for grep-based analysis
ALL_SRC=$(mktemp)
trap 'rm -f "$ALL_SRC"' EXIT
cat "$ORCH" "$PLUGIN_DIR/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

PASS=0
FAIL=0
TOTAL=0

pass() {
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ✅ PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ❌ FAIL: $1 — $2"
}

suite() {
  echo ""
  echo "━━━ $1 ━━━"
}

# ── 1. Flag Declarations (v9.18 + v9.19) ────────────────────────────────────
suite "1. Flag Declarations in orchestrate.sh"

# v9.18 flags
for flag in SUPPORTS_SKILL_EFFORT SUPPORTS_RATE_LIMIT_STATUSLINE \
            SUPPORTS_TASK_CREATED_HOOK SUPPORTS_SKILL_PATHS SUPPORTS_USER_CONFIG \
            SUPPORTS_HOOK_CONDITIONAL_IF SUPPORTS_HOOK_ASK_ANSWER SUPPORTS_SKILL_DESC_250 \
            SUPPORTS_TASKOUTPUT_DEPRECATED; do
  if grep -q "^${flag}=false" "$ORCH"; then
    pass "$flag declared"
  else
    fail "$flag declared" "not found in orchestrate.sh"
  fi
done

# v9.19 flags
for flag in SUPPORTS_POST_COMPACT_HOOK SUPPORTS_ELICITATION_HOOKS \
            SUPPORTS_BARE_FLAG SUPPORTS_MODEL_CAP_ENV_VARS SUPPORTS_CONSOLE_AUTH \
            SUPPORTS_WORKTREE_HTTP_HOOKS SUPPORTS_SESSION_ID_HEADER SUPPORTS_DEEP_LINK_5K \
            SUPPORTS_MARKETPLACE_OFFLINE SUPPORTS_PLUGIN_EXECUTABLES SUPPORTS_MCP_RESULT_SIZE \
            SUPPORTS_DISABLE_SKILL_SHELL SUPPORTS_MULTILINE_DEEP_LINKS; do
  if grep -q "^${flag}=false" "$ORCH"; then
    pass "$flag declared"
  else
    fail "$flag declared" "not found in orchestrate.sh"
  fi
done

# ── 2. Version Detection Blocks ─────────────────────────────────────────────
suite "2. Version Detection Blocks in providers.sh"

for version in 2.1.84 2.1.85 2.1.86 2.1.87 2.1.88 2.1.89 2.1.90 2.1.91; do
  if grep -q "version_compare.*CLAUDE_CODE_VERSION.*${version}" "$PROVIDERS"; then
    pass "v${version} detection block exists"
  else
    fail "v${version} detection block" "not found in providers.sh"
  fi
done

# ── 3. Version Block Ordering ────────────────────────────────────────────────
suite "3. Version Cascade Ordering"

# Extract version numbers from cascade, verify ascending order
prev=""
out_of_order=0
while IFS= read -r line; do
  ver=$(echo "$line" | grep -o '"2\.[0-9]\.[0-9]*"' | tr -d '"')
  if [[ -n "$prev" && -n "$ver" ]]; then
    if [[ "$(printf '%s\n%s' "$prev" "$ver" | sort -V | head -1)" != "$prev" ]]; then
      ((out_of_order++)) || true
    fi
  fi
  [[ -n "$ver" ]] && prev="$ver"
done < <(grep 'version_compare.*CLAUDE_CODE_VERSION' "$PROVIDERS")

if [[ $out_of_order -eq 0 ]]; then
  pass "Version cascade is in ascending order"
else
  fail "Version cascade ordering" "$out_of_order inversions found"
fi

# ── 4. Hook Event Registrations ──────────────────────────────────────────────
suite "4. Hook Events in hooks.json"

for event in PostCompact Elicitation ElicitationResult; do
  if grep -q "\"${event}\"" "$HOOKS_JSON"; then
    pass "$event event registered"
  else
    fail "$event event" "not found in hooks.json"
  fi
done

# Verify hook scripts exist and are executable
for script in post-compact.sh elicitation-handler.sh; do
  if [[ -x "$HOOKS_DIR/$script" ]]; then
    pass "$script exists and is executable"
  else
    fail "$script" "missing or not executable"
  fi
done

# ── 5. Plugin Executable ─────────────────────────────────────────────────────
suite "5. Plugin Executable (bin/octopus)"

if [[ -x "$PLUGIN_DIR/bin/octopus" ]]; then
  pass "bin/octopus exists and is executable"
else
  fail "bin/octopus" "missing or not executable"
fi

# Verify it has proper shebang
if head -1 "$PLUGIN_DIR/bin/octopus" | grep -q '^#!/usr/bin/env bash'; then
  pass "bin/octopus has bash shebang"
else
  fail "bin/octopus shebang" "expected #!/usr/bin/env bash"
fi

# Verify help command doesn't error
if "$PLUGIN_DIR/bin/octopus" help >/dev/null 2>&1; then
  pass "bin/octopus help runs without error"
else
  fail "bin/octopus help" "exits with non-zero"
fi

# ── 6. --bare Flag Wiring ────────────────────────────────────────────────────
suite "6. --bare Flag Wiring"

if grep -q '_BARE_OPT' "$DISPATCH"; then
  pass "_BARE_OPT used in dispatch.sh"
else
  fail "_BARE_OPT in dispatch.sh" "not found"
fi

if grep -q '_BARE_OPT' "$AGENT_UTILS"; then
  pass "_BARE_OPT used in agent-utils.sh"
else
  fail "_BARE_OPT in agent-utils.sh" "not found"
fi

# Safe default guard
if grep -q '_BARE_OPT="\${_BARE_OPT:-}"' "$AGENT_UTILS"; then
  pass "_BARE_OPT has safe default in agent-utils.sh"
else
  fail "_BARE_OPT safe default" "missing guard in agent-utils.sh"
fi

# Set and exported in providers.sh
if grep -q 'export _BARE_OPT' "$PROVIDERS"; then
  pass "_BARE_OPT exported in providers.sh"
else
  fail "_BARE_OPT export" "not exported in providers.sh"
fi

# ── 7. Doctor Tips ───────────────────────────────────────────────────────────
suite "7. Doctor Tips for v9.19 Flags"

for tip_id in post-compact-hook bare-flag model-cap-env-vars console-auth \
              plugin-executables mcp-result-size marketplace-offline \
              disable-skill-shell rate-limit-hud-fallback managed-settings-fragment \
              elicitation-hooks session-id-header deep-link-5k \
              worktree-http-hooks multiline-deep-links; do
  if grep -q "\"${tip_id}\"" "$DOCTOR"; then
    pass "Doctor tip '$tip_id' exists"
  else
    fail "Doctor tip '$tip_id'" "not found in doctor.sh"
  fi
done

# ── 8. Managed Settings Fragment ─────────────────────────────────────────────
suite "8. Managed Settings Infrastructure"

if [[ -f "$PLUGIN_DIR/managed-settings.d/octopus-defaults.json" ]]; then
  pass "managed-settings.d/octopus-defaults.json exists"
else
  fail "managed-settings fragment" "file missing"
fi

# Session-start-memory deploys it
if grep -q 'managed-settings.d' "$HOOKS_DIR/session-start-memory.sh"; then
  pass "session-start-memory.sh deploys managed-settings fragment"
else
  fail "managed-settings deployment" "not found in session-start-memory.sh"
fi

# Atomic write pattern (tmpfile + mv)
if grep -q '_tmp.*SETTINGS_DEST' "$HOOKS_DIR/session-start-memory.sh" && \
   grep -q 'mv.*_tmp' "$HOOKS_DIR/session-start-memory.sh"; then
  pass "Atomic write pattern for managed-settings"
else
  fail "Atomic write" "non-atomic write in session-start-memory.sh"
fi

# ── 9. HUD Rate Limit Fallback ──────────────────────────────────────────────
suite "9. HUD Rate Limit Fallback"

HUD="$HOOKS_DIR/octopus-hud.mjs"

if grep -q 'parseInputRateLimits' "$HUD"; then
  pass "parseInputRateLimits function exists in HUD"
else
  fail "parseInputRateLimits" "not found in octopus-hud.mjs"
fi

if grep -q 'input\.rate_limits' "$HUD"; then
  pass "input.rate_limits passed to getUsage()"
else
  fail "input.rate_limits" "not passed to getUsage() in main()"
fi

# Error cache falls through to fallback
if grep -q 'cache\.data.*return.*parseInputRateLimits' "$HUD" || \
   grep -A2 'cache\.data' "$HUD" | grep -q 'parseInputRateLimits'; then
  pass "Error cache falls through to rate limit fallback"
else
  fail "Error cache fallthrough" "cached error may bypass inputRateLimits"
fi

# ── 10. Cleanup: Orphaned Files ──────────────────────────────────────────────
suite "10. Orphan Cleanup"

if [[ ! -f "$HOOKS_DIR/session-sync.sh" ]]; then
  pass "session-sync.sh removed (merged into session-start-memory.sh)"
else
  fail "session-sync.sh" "orphaned file still exists"
fi

if ! grep -q 'session-sync' "$PLUGIN_DIR/scripts/lib/hook-profile.sh"; then
  pass "session-sync removed from hook-profile.sh allowlist"
else
  fail "session-sync in hook-profile" "stale reference remains"
fi

# ── 11. Hook Script Consistency ──────────────────────────────────────────────
suite "11. Hook Script Consistency (set -euo pipefail)"

missing_pipefail=0
for hook in "$HOOKS_DIR"/*.sh; do
  name=$(basename "$hook")
  # Skip one-liner delegates
  [[ "$name" == "statusline-resolver.sh" ]] && continue
  if ! grep -q 'set -euo pipefail' "$hook"; then
    fail "$name" "missing set -euo pipefail"
    ((missing_pipefail++)) || true
  fi
done
if [[ $missing_pipefail -eq 0 ]]; then
  pass "All hook scripts have set -euo pipefail"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS passed, $FAIL failed (of $TOTAL)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
