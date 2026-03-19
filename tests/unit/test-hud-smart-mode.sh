#!/usr/bin/env bash
# Tests for HUD smart mode, timeout fallback, Octo column, and context bridge fixes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/hooks"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ═══════════════════════════════════════════════════════════════════════════════
# Group 1: Timeout fallback — hooks work without GNU timeout
# ═══════════════════════════════════════════════════════════════════════════════

echo "── Group 1: Timeout fallback ──"

# All 6 hooks must have the timeout fallback guard
# Hooks (not statusline) must have timeout guard — statusline doesn't need it
# because Claude Code cancels in-flight statusline scripts on new updates
for hook in user-prompt-submit.sh subagent-result-capture.sh \
            context-reinforcement.sh task-completion-checkpoint.sh; do
    if grep -q 'command -v timeout' "$HOOKS_DIR/$hook" 2>/dev/null; then
        pass "$hook has timeout availability check"
    else
        fail "$hook has timeout availability check" "missing 'command -v timeout' guard"
    fi
done

# Drain-only hooks should use plain cat (no timeout wrapper needed)
for hook in context-awareness.sh budget-gate.sh; do
    if grep -q 'cat > /dev/null' "$HOOKS_DIR/$hook" 2>/dev/null; then
        pass "$hook drains stdin with plain cat"
    else
        fail "$hook drains stdin with plain cat" "still using timeout for drain"
    fi
done

# No hook should have bare 'timeout 3 cat' without the guard
for hook in user-prompt-submit.sh subagent-result-capture.sh \
            context-reinforcement.sh task-completion-checkpoint.sh; do
    # Count lines with 'timeout 3 cat' NOT preceded by 'if command -v timeout'
    unguarded=$(grep -n 'timeout 3 cat' "$HOOKS_DIR/$hook" 2>/dev/null | while read -r line; do
        lineno=$(echo "$line" | cut -d: -f1)
        prev=$((lineno - 1))
        if ! sed -n "${prev}p" "$HOOKS_DIR/$hook" | grep -q 'command -v timeout'; then
            echo "unguarded"
        fi
    done)
    if [[ -z "$unguarded" ]]; then
        pass "$hook has no unguarded timeout calls"
    else
        fail "$hook has no unguarded timeout calls" "found bare 'timeout 3 cat'"
    fi
done

# Statusline uses plain cat (Claude Code cancels in-flight scripts per official docs)
if grep -q 'input=\$(cat 2>/dev/null' "$HOOKS_DIR/octopus-statusline.sh"; then
    pass "octopus-statusline.sh uses plain cat (no timeout needed for statusline)"
else
    fail "octopus-statusline.sh uses plain cat" "unexpected stdin pattern"
fi

# Statusline has Node version check before ESM delegation
if grep -q 'NODE_MAJOR.*16' "$HOOKS_DIR/octopus-statusline.sh"; then
    pass "octopus-statusline.sh checks Node >= 16 before HUD delegation"
else
    fail "octopus-statusline.sh checks Node >= 16 before HUD delegation" "missing version check"
fi

# Statusline has 3-tier fallback (Node → jq → pure bash)
if grep -q 'TIER 1' "$HOOKS_DIR/octopus-statusline.sh" && \
   grep -q 'TIER 2' "$HOOKS_DIR/octopus-statusline.sh" && \
   grep -q 'TIER 3' "$HOOKS_DIR/octopus-statusline.sh"; then
    pass "octopus-statusline.sh has 3-tier fallback (Node → jq → pure bash)"
else
    fail "octopus-statusline.sh has 3-tier fallback" "missing tier markers"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Group 2: Smart HUD — column factory and smart mode
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Group 2: Smart HUD ──"

HUD="$HOOKS_DIR/octopus-hud.mjs"

if grep -q 'function smartColumns' "$HUD" 2>/dev/null; then
    pass "HUD has smartColumns function"
else
    fail "HUD has smartColumns function" "missing smartColumns"
fi

if grep -q 'columnFactory' "$HUD" 2>/dev/null; then
    pass "HUD uses column factory pattern"
else
    fail "HUD uses column factory pattern" "missing columnFactory"
fi

if grep -q 'config\.columns' "$HUD" && grep -q 'for.*of config\.columns' "$HUD"; then
    pass "HUD iterates columns in config order"
else
    fail "HUD iterates columns in config order" "columns not built from config order"
fi

# Smart mode should auto-detect OAuth vs API-key
if grep -q 'isOAuth' "$HUD" 2>/dev/null; then
    pass "HUD detects OAuth subscription status"
else
    fail "HUD detects OAuth subscription status" "missing isOAuth detection"
fi

# Smart mode hides Cost for OAuth, shows for API-key
if grep -qE 'isOAuth.*Cost|Cost.*isOAuth' "$HUD" 2>/dev/null || \
   grep -B2 'Cost' "$HUD" | grep -q 'isOAuth'; then
    pass "HUD conditionally shows Cost based on auth type"
else
    fail "HUD conditionally shows Cost based on auth type" "Cost not gated on isOAuth"
fi

# Context column should be last in smart mode
if grep -q '"Context"' "$HUD" 2>/dev/null; then
    # Check that Context is pushed last in smartColumns
    last_push=$(grep -n 'cols\.push' "$HUD" | grep 'Context' | tail -1 | cut -d: -f1)
    return_line=$(grep -n 'return cols' "$HUD" | head -1 | cut -d: -f1)
    if [[ -n "$last_push" && -n "$return_line" ]] && [[ "$last_push" -lt "$return_line" ]]; then
        # Check no other push between Context push and return
        between=$(sed -n "$((last_push+1)),$((return_line-1))p" "$HUD" | grep 'cols\.push' || true)
        if [[ -z "$between" ]]; then
            pass "Context is last column in smart mode"
        else
            fail "Context is last column in smart mode" "other columns pushed after Context"
        fi
    else
        fail "Context is last column in smart mode" "couldn't verify push order"
    fi
else
    fail "Context is last column in smart mode" "Context column not found"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Group 3: Octo brand column
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Group 3: Octo brand column ──"

if grep -q '"Octo"' "$HUD" 2>/dev/null; then
    pass "HUD has Octo column"
else
    fail "HUD has Octo column" "missing Octo in column definitions"
fi

if grep -q 'OCTO_VERSION' "$HUD" 2>/dev/null; then
    pass "HUD reads plugin version for Octo column"
else
    fail "HUD reads plugin version for Octo column" "missing OCTO_VERSION"
fi

if grep -q 'package\.json' "$HUD" 2>/dev/null; then
    pass "HUD reads version from package.json"
else
    fail "HUD reads version from package.json" "no package.json reference"
fi

# Octo should be first in ALL_COLUMNS
if grep -q '"Octo".*"5h Usage"' "$HUD" 2>/dev/null; then
    pass "Octo is first in ALL_COLUMNS"
else
    fail "Octo is first in ALL_COLUMNS" "Octo not at position 0"
fi

# Effort level symbol in Octo column
if grep -q 'effortSymbol' "$HUD" 2>/dev/null; then
    pass "Octo column includes effort level indicator"
else
    fail "Octo column includes effort level indicator" "missing effort symbol"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Group 4: Context bridge uses stdin session_id
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Group 4: Context bridge session_id ──"

# Bash statusline should extract session_id from stdin JSON
if grep -q 'session_id' "$HOOKS_DIR/octopus-statusline.sh" && \
   grep -q 'jq.*session_id' "$HOOKS_DIR/octopus-statusline.sh"; then
    pass "Bash statusline extracts session_id from stdin"
else
    fail "Bash statusline extracts session_id from stdin" "no jq session_id extraction"
fi

# HUD should use input.session_id for bridge
if grep -q 'input?.session_id\|input\.session_id' "$HUD" 2>/dev/null; then
    pass "HUD uses input.session_id for bridge"
else
    fail "HUD uses input.session_id for bridge" "still using only env var"
fi

# Context-awareness should exit when session ID is unknown (no unsafe /tmp glob)
if grep -q 'SESSION.*unknown.*exit 0' "$HOOKS_DIR/context-awareness.sh" 2>/dev/null; then
    pass "Context-awareness exits when session ID unknown"
else
    fail "Context-awareness exits when session ID unknown" "missing unknown session guard"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Group 5: HUD functional test (requires node)
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Group 5: HUD functional test ──"

if command -v node &>/dev/null; then
    # Test with OAuth-like data (usage present → should hide Cost, show Usage)
    TEST_INPUT='{"session_id":"test-123","model":{"id":"claude-opus-4-6","display_name":"Opus 4.6"},"context_window":{"used_percentage":25},"cost":{"total_cost_usd":1.5,"total_lines_added":10,"total_lines_removed":5},"version":"2.1.79","effort_level":"high"}'
    HUD_OUTPUT=$(echo "$TEST_INPUT" | node "$HUD" 2>/dev/null) || HUD_OUTPUT=""

    if [[ -n "$HUD_OUTPUT" ]]; then
        pass "HUD produces output from test data"
    else
        fail "HUD produces output from test data" "empty output"
    fi

    if echo "$HUD_OUTPUT" | grep -q "Octo"; then
        pass "HUD output contains Octo column"
    else
        fail "HUD output contains Octo column" "Octo not in output"
    fi

    # Strip ANSI codes and non-breaking spaces for content matching
    STRIPPED=$(echo "$HUD_OUTPUT" | sed $'s/\x1b\[[0-9;]*m//g' | tr '\xc2\xa0' ' ')
    if echo "$STRIPPED" | grep -q "Opus"; then
        pass "HUD output shows model name"
    else
        fail "HUD output shows model name" "model not in output"
    fi

    # Verify bridge file was written with correct session_id
    BRIDGE_FILE="/tmp/octopus-ctx-test-123.json"
    if [[ -f "$BRIDGE_FILE" ]]; then
        if grep -q '"session_id":"test-123"' "$BRIDGE_FILE"; then
            pass "Bridge file uses stdin session_id"
        else
            fail "Bridge file uses stdin session_id" "wrong session_id in bridge"
        fi
        rm -f "$BRIDGE_FILE"
    else
        fail "Bridge file uses stdin session_id" "bridge file not created"
    fi
else
    echo "SKIP: Node.js not available — skipping functional HUD tests"
fi

# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════"
echo "hud-smart-mode: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
