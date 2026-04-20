#!/bin/bash
# Test suite for v8.40.0 — Claude Code v2.1.70-71 feature detection sync
# Validates new SUPPORTS_* flags, detection blocks, and wired integrations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "for v8.40.0 — Claude Code v2.1.70-71 feature detection sync"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCH="$PLUGIN_DIR/scripts/orchestrate.sh"
ALL_SRC=$(mktemp)
cat "$ORCH" "$PLUGIN_DIR/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT
HOOK="$PLUGIN_DIR/hooks/subagent-result-capture.sh"

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
# Suite 1: New flag declarations (6 flags)
# ─────────────────────────────────────────────────────────────────────
suite "1. v8.40.0 Flag Declarations"

# v2.1.70/v2.1.71 flags pruned in v9.5 (banner-only, no runtime behavior)
# Suite 1 now validates that pruned flags are gone
suite "1. v8.40.0 Flag Pruning (v9.5)"

for flag in SUPPORTS_VSCODE_PLAN_VIEW SUPPORTS_IMAGE_CACHE_COMPACTION \
            SUPPORTS_RENAME_WHILE_PROCESSING SUPPORTS_NATIVE_LOOP \
            SUPPORTS_RUNTIME_DEBUG SUPPORTS_FAST_BRIDGE_RECONNECT; do
  if grep -q "^${flag}=false" "$ALL_SRC"; then
    fail "$flag should have been pruned but still declared"
  else
    pass "$flag correctly pruned"
  fi
done

# ─────────────────────────────────────────────────────────────────────
# Suite 2: v2.1.70/v2.1.71 detection blocks removed
# ─────────────────────────────────────────────────────────────────────
suite "2. Version Detection Blocks Pruned"

if grep -q 'version_compare.*"2\.1\.70"' "$ALL_SRC"; then
  fail "v2.1.70 detection block should have been removed"
else
  pass "v2.1.70 detection block correctly removed"
fi

if grep -q 'version_compare.*"2\.1\.71"' "$ALL_SRC"; then
  fail "v2.1.71 detection block should have been removed"
else
  pass "v2.1.71 detection block correctly removed"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 3: Pruned flag logging removed
# ─────────────────────────────────────────────────────────────────────
suite "3. Flag Logging Pruned"

if grep -q 'VSCode Plan:.*SUPPORTS_VSCODE_PLAN_VIEW' "$ALL_SRC"; then
  fail "Pruned VSCode Plan flag still in logging"
else
  pass "VSCode Plan logging correctly removed"
fi

if grep -q 'Native Loop:.*SUPPORTS_NATIVE_LOOP' "$ALL_SRC"; then
  fail "Pruned Native Loop flag still in logging"
else
  pass "Native Loop logging correctly removed"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 4: Wired flag — SUPPORTS_EFFORT_CALLOUT
# ─────────────────────────────────────────────────────────────────────
suite "4. Effort Callout Wiring"

if grep -q 'SUPPORTS_EFFORT_CALLOUT.*true' "$ALL_SRC" | head -1 && \
   grep -q 'log "USER".*Effort' "$ALL_SRC"; then
  pass "SUPPORTS_EFFORT_CALLOUT wired to user-visible effort display"
else
  fail "SUPPORTS_EFFORT_CALLOUT not wired"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 5: Wired flag — SUPPORTS_HOOK_AGENT_FIELDS
# ─────────────────────────────────────────────────────────────────────
suite "5. Hook Agent Fields Wiring"

if grep -q 'agent_type' "$HOOK"; then
  pass "subagent-result-capture.sh captures agent_type"
else
  fail "subagent-result-capture.sh missing agent_type capture"
fi

if grep -q 'Agent-Type' "$HOOK"; then
  pass "agent_type written to result file"
else
  fail "agent_type not written to result file"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 6: Wired flag — SUPPORTS_MEMORY_LEAK_FIXES
# ─────────────────────────────────────────────────────────────────────
suite "6. Memory Leak Fixes Wiring"

if grep -q 'leak_safe_boost' "$ALL_SRC" && \
   grep -q 'SUPPORTS_MEMORY_LEAK_FIXES.*true' "$ALL_SRC"; then
  pass "SUPPORTS_MEMORY_LEAK_FIXES wired to timeout boost"
else
  fail "SUPPORTS_MEMORY_LEAK_FIXES not wired to timeout boost"
fi

# ─────────────────────────────────────────────────────────────────────
# Suite 7: Total flag count validation
# ─────────────────────────────────────────────────────────────────────
suite "7. Flag Count"

FLAG_COUNT=$(grep -c '^SUPPORTS_.*=false' "$ALL_SRC")
if [[ "$FLAG_COUNT" -ge 80 ]]; then
  pass "Total SUPPORTS_* flags: $FLAG_COUNT (expected >= 80)"
else
  fail "Total SUPPORTS_* flags: $FLAG_COUNT (expected >= 80)"
fi

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
test_summary
