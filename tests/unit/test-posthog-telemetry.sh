#!/bin/bash
# Test suite for PostHog telemetry integration
# Validates: opt-in gate, anonymous ID, event buffering, flush, scrubbing, hooks.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$PLUGIN_DIR/hooks/telemetry-posthog.sh"
HOOKS_JSON="$PLUGIN_DIR/.claude-plugin/hooks.json"

PASS=0 FAIL=0 TOTAL=0
pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  ❌ FAIL: $1 — $2"; }
suite() { echo ""; echo "━━━ $1 ━━━"; }

# ── Static analysis ──────────────────────────────────────────────────────────
suite "Static Analysis"

if [[ -x "$HOOK" ]]; then pass "telemetry-posthog.sh is executable"
else fail "telemetry-posthog.sh is executable" "missing or not +x"; fi

if bash -n "$HOOK" 2>/dev/null; then pass "Syntax valid"
else fail "Syntax valid" "bash -n failed"; fi

if grep -q 'POSTHOG_PROJECT_KEY' "$HOOK"; then pass "Checks POSTHOG_PROJECT_KEY"
else fail "Checks POSTHOG_PROJECT_KEY" "env var not referenced"; fi

if grep -q 'POSTHOG_OPT_OUT' "$HOOK"; then pass "Has POSTHOG_OPT_OUT kill switch"
else fail "Has POSTHOG_OPT_OUT kill switch" "not found"; fi

if grep -q 'posthog-anon-id' "$HOOK"; then pass "Uses persistent anonymous ID"
else fail "Uses persistent anonymous ID" "no anon-id file"; fi

if grep -q 'uuid' "$HOOK"; then pass "Anonymous ID is UUID-based"
else fail "Anonymous ID is UUID-based" "no uuid generation"; fi

if grep -q '_scrub' "$HOOK"; then pass "Has scrubbing function"
else fail "Has scrubbing function" "no _scrub"; fi

if grep -q 'sk-.*REDACTED\|AIza.*REDACTED' "$HOOK"; then pass "Scrubs API keys"
else fail "Scrubs API keys" "no key redaction patterns"; fi

if grep -q '/batch/' "$HOOK"; then pass "Uses PostHog /batch endpoint for flush"
else fail "Uses PostHog /batch endpoint" "no batch flush"; fi

if grep -q 'posthog-events.jsonl' "$HOOK"; then pass "Buffers events to local file"
else fail "Buffers events to local file" "no buffer file"; fi

# ── hooks.json registration ──────────────────────────────────────────────────
suite "Hook Registration"

if grep -q 'telemetry-posthog.sh' "$HOOKS_JSON"; then pass "Registered in hooks.json"
else fail "Registered in hooks.json" "not found"; fi

if grep -q 'CLAUDE_HOOK_EVENT=SessionStart.*telemetry-posthog' "$HOOKS_JSON"; then pass "SessionStart hook registered"
else fail "SessionStart hook registered" "not found"; fi

if grep -q 'CLAUDE_HOOK_EVENT=SessionEnd.*telemetry-posthog' "$HOOKS_JSON"; then pass "SessionEnd hook registered"
else fail "SessionEnd hook registered" "not found"; fi

if grep -q 'CLAUDE_HOOK_EVENT=Stop.*telemetry-posthog' "$HOOKS_JSON"; then pass "Stop hook registered"
else fail "Stop hook registered" "not found"; fi

# ── Functional: opt-in gate ──────────────────────────────────────────────────
suite "Functional: Opt-in Gate"

# Without POSTHOG_PROJECT_KEY → exits cleanly
if POSTHOG_PROJECT_KEY="" bash "$HOOK" </dev/null >/dev/null 2>&1; then
    pass "Exits cleanly without POSTHOG_PROJECT_KEY"
else
    fail "Exits cleanly without POSTHOG_PROJECT_KEY" "non-zero exit"
fi

# With OPT_OUT=1 → exits cleanly even with key set
if POSTHOG_PROJECT_KEY="phc_test" POSTHOG_OPT_OUT=1 bash "$HOOK" </dev/null >/dev/null 2>&1; then
    pass "POSTHOG_OPT_OUT=1 disables telemetry"
else
    fail "POSTHOG_OPT_OUT=1 disables telemetry" "non-zero exit"
fi

# ── Functional: event buffering ──────────────────────────────────────────────
suite "Functional: Event Buffering"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Buffer a session start event
POSTHOG_PROJECT_KEY="phc_test_key_not_real" \
POSTHOG_HOST="http://localhost:99999" \
CLAUDE_PLUGIN_DATA="$TEST_DIR" \
CLAUDE_HOOK_EVENT="SessionStart" \
CLAUDE_SESSION_ID="test-session" \
bash "$HOOK" </dev/null >/dev/null 2>&1 || true

if [[ -f "$TEST_DIR/.posthog-events.jsonl" ]]; then
    pass "Event buffered to .posthog-events.jsonl"

    if grep -q 'octopus.session.start' "$TEST_DIR/.posthog-events.jsonl"; then
        pass "Buffer contains octopus.session.start event"
    else
        fail "Buffer contains session start" "event name not found"
    fi

    if grep -q 'phc_test_key_not_real' "$TEST_DIR/.posthog-events.jsonl"; then
        pass "Event includes api_key"
    else
        fail "Event includes api_key" "key not in event"
    fi
else
    fail "Event buffered" "file not created"
    fail "Buffer contents" "no file to check"
    fail "Event api_key" "no file to check"
fi

# Check anon ID was created
if [[ -f "$TEST_DIR/.posthog-anon-id" ]]; then
    anon_id=$(cat "$TEST_DIR/.posthog-anon-id")
    if [[ -n "$anon_id" && "$anon_id" != *"$HOSTNAME"* ]]; then
        pass "Anonymous ID generated (not hostname)"
    else
        fail "Anonymous ID generated" "got: $anon_id"
    fi
else
    fail "Anonymous ID file created" "not found"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
echo "═══════════════════════════════════════════"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
