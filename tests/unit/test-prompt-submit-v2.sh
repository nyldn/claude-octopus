#!/usr/bin/env bash
# Tests for v9.6.0 enhanced UserPromptSubmit hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$PROJECT_ROOT/hooks/user-prompt-submit.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── Confidence levels ───────────────────────────────────────────────

if grep -q 'CONFIDENCE' "$HOOK" 2>/dev/null; then
    pass "Has CONFIDENCE variable"
else
    fail "Has CONFIDENCE variable" "missing CONFIDENCE"
fi

if grep -q '"HIGH"' "$HOOK" 2>/dev/null; then
    pass "Has HIGH confidence level"
else
    fail "Has HIGH confidence level" "missing HIGH"
fi

if grep -q '"LOW"' "$HOOK" 2>/dev/null; then
    pass "Has LOW confidence level"
else
    fail "Has LOW confidence level" "missing LOW"
fi

# ── Multi-keyword detection for HIGH confidence ─────────────────────

if grep -q 'KEYWORD_HITS' "$HOOK" 2>/dev/null; then
    pass "Tracks keyword hit count"
else
    fail "Tracks keyword hit count" "missing KEYWORD_HITS"
fi

if grep -qE 'KEYWORD_HITS.*2|HITS -ge 2' "$HOOK" 2>/dev/null; then
    pass "HIGH confidence requires 2+ keyword hits"
else
    fail "HIGH confidence requires 2+ keyword hits" "missing threshold"
fi

# ── Persona context injection on HIGH confidence ─────────────────────

if grep -q 'PERSONA_HINT\|persona' "$HOOK" 2>/dev/null; then
    pass "Has persona context injection"
else
    fail "Has persona context injection" "missing PERSONA_HINT"
fi

if grep -q 'Security auditor\|security-audit.*persona' "$HOOK" 2>/dev/null; then
    pass "Maps security-audit to security auditor persona"
else
    fail "Maps security-audit to security auditor persona" "missing mapping"
fi

if grep -q 'Code reviewer\|code-review.*persona' "$HOOK" 2>/dev/null; then
    pass "Maps code-review to code reviewer persona"
else
    fail "Maps code-review to code reviewer persona" "missing mapping"
fi

# ── Provider pre-warming ────────────────────────────────────────────

if grep -q 'primed_providers' "$HOOK" 2>/dev/null; then
    pass "Writes primed_providers to session"
else
    fail "Writes primed_providers to session" "missing provider priming"
fi

if grep -q 'OPENAI_API_KEY\|codex' "$HOOK" 2>/dev/null; then
    pass "Checks for Codex/OpenAI provider"
else
    fail "Checks for Codex/OpenAI provider" "missing codex check"
fi

if grep -q 'GEMINI_API_KEY\|gemini' "$HOOK" 2>/dev/null; then
    pass "Checks for Gemini provider"
else
    fail "Checks for Gemini provider" "missing gemini check"
fi

# ── Octopus branding ────────────────────────────────────────────────

if grep -q '🐙' "$HOOK" 2>/dev/null; then
    pass "Uses 🐙 branding in output"
else
    fail "Uses 🐙 branding in output" "missing octopus emoji"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "prompt-submit-v2: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
