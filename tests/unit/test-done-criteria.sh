#!/usr/bin/env bash
# Tests for done-criteria.sh — compound task detection and DONE criteria injection
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "done-criteria.sh — compound task detection and DONE criteria injection"

HOOK="$PROJECT_ROOT/hooks/done-criteria.sh"
HOOKS_JSON="$PROJECT_ROOT/.claude-plugin/hooks.json"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── File existence and permissions ────────────────────────────────────────────

if [[ -f "$HOOK" ]]; then
    pass "Hook script exists"
else
    fail "Hook script exists" "not found: $HOOK"
fi

if [[ -x "$HOOK" ]]; then
    pass "Hook script is executable"
else
    fail "Hook script is executable" "not executable"
fi

# ── Valid bash syntax ─────────────────────────────────────────────────────────

if bash -n "$HOOK" 2>/dev/null; then
    pass "Hook has valid bash syntax"
else
    fail "Hook has valid bash syntax" "syntax error"
fi

# ── Registered in hooks.json ──────────────────────────────────────────────────

if grep -q 'done-criteria.sh' "$HOOKS_JSON" 2>/dev/null; then
    pass "Registered in hooks.json"
else
    fail "Registered in hooks.json" "done-criteria.sh not found in hooks.json"
fi

if grep -B5 'done-criteria.sh' "$HOOKS_JSON" 2>/dev/null | grep -q 'UserPromptSubmit'; then
    pass "Registered under UserPromptSubmit event"
else
    # Check broader context — the hook might be further from the section heading
    if python3 -c "
import json, sys
with open('$HOOKS_JSON') as f:
    h = json.load(f)
found = False
for entry in h.get('UserPromptSubmit', []):
    for hook in entry.get('hooks', []):
        if 'done-criteria' in hook.get('command', ''):
            found = True
sys.exit(0 if found else 1)
" 2>/dev/null; then
        pass "Registered under UserPromptSubmit event"
    else
        fail "Registered under UserPromptSubmit event" "not under UserPromptSubmit"
    fi
fi

# ── Numbered list detection ───────────────────────────────────────────────────

if grep -q '[0-9]\+\[.)\]' "$HOOK" 2>/dev/null || grep -qE '\[0-9\]' "$HOOK" 2>/dev/null; then
    pass "Detects numbered list patterns"
else
    fail "Detects numbered list patterns" "no numbered list regex found"
fi

# ── Conjunction/verb patterns ─────────────────────────────────────────────────

if grep -q 'and\|then\|also\|additionally' "$HOOK" 2>/dev/null; then
    pass "Detects conjunction patterns (and/then/also)"
else
    fail "Detects conjunction patterns (and/then/also)" "missing conjunction detection"
fi

if grep -qE 'verb_pattern|add\|create\|fix\|update' "$HOOK" 2>/dev/null; then
    pass "Has action verb patterns for compound detection"
else
    fail "Has action verb patterns for compound detection" "missing verb patterns"
fi

# ── Bullet list detection ────────────────────────────────────────────────────

if grep -q 'bullet_count\|bullet' "$HOOK" 2>/dev/null; then
    pass "Detects bullet list patterns"
else
    fail "Detects bullet list patterns" "missing bullet detection"
fi

if grep -qE 'bullet_count.*-ge 2|>= *2' "$HOOK" 2>/dev/null; then
    pass "Requires 2+ bullets for compound detection"
else
    fail "Requires 2+ bullets for compound detection" "missing threshold"
fi

# ── Kill switch ───────────────────────────────────────────────────────────────

if grep -q 'OCTO_DONE_CRITERIA' "$HOOK" 2>/dev/null; then
    pass "Has OCTO_DONE_CRITERIA kill switch"
else
    fail "Has OCTO_DONE_CRITERIA kill switch" "missing kill switch"
fi

if grep -qE 'OCTO_DONE_CRITERIA.*off' "$HOOK" 2>/dev/null; then
    pass "Kill switch disables on 'off'"
else
    fail "Kill switch disables on 'off'" "kill switch not wired to off"
fi

# ── Timeout guard on stdin ────────────────────────────────────────────────────

if grep -q 'timeout.*cat' "$HOOK" 2>/dev/null; then
    pass "Has timeout guard on stdin read"
else
    fail "Has timeout guard on stdin read" "missing timeout guard"
fi

# ── Output format ────────────────────────────────────────────────────────────

if grep -q 'additionalContext' "$HOOK" 2>/dev/null; then
    pass "Returns additionalContext in JSON output"
else
    fail "Returns additionalContext in JSON output" "missing additionalContext"
fi

if grep -qi 'verifiable completion criteria\|completion criteria' "$HOOK" 2>/dev/null; then
    pass "Mentions verifiable completion criteria"
else
    fail "Mentions verifiable completion criteria" "missing criteria language"
fi

# ── Short prompt skip ─────────────────────────────────────────────────────────

if grep -qE '#prompt.*lt 30|\$\{#prompt\}.*-lt 30' "$HOOK" 2>/dev/null; then
    pass "Skips short prompts (< 30 chars)"
else
    fail "Skips short prompts (< 30 chars)" "missing short prompt guard"
fi

# ── No attribution references ────────────────────────────────────────────────

if grep -qi 'temm1e\|DONE Definition Engine' "$HOOK" 2>/dev/null; then
    fail "No attribution references" "found prohibited attribution"
else
    pass "No attribution references"
fi
test_summary
