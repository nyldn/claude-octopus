#!/usr/bin/env bash
# Tests for compound init-workflow command in orchestrate.sh dispatch block
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "compound init-workflow command in orchestrate.sh dispatch block"

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── init-workflow dispatch case exists ──────────────────────────────────────

if grep -q 'init-workflow)' "$ORCHESTRATE" 2>/dev/null; then
    pass "init-workflow dispatch case exists"
else
    fail "init-workflow dispatch case exists" "not found in orchestrate.sh"
fi

# ── Returns JSON with expected fields ───────────────────────────────────────

INIT_BLOCK=$(grep -A80 'init-workflow)' "$ORCHESTRATE" | head -85)

for field in workflow providers models capabilities files paths; do
    if echo "$INIT_BLOCK" | grep -q "\"$field\"" 2>/dev/null; then
        pass "init-workflow JSON has '$field' field"
    else
        fail "init-workflow JSON has '$field' field" "missing in output"
    fi
done

# ── Provider detection for all 4 providers ──────────────────────────────────

for provider in codex gemini claude perplexity; do
    if echo "$INIT_BLOCK" | grep -q "${provider}" 2>/dev/null; then
        pass "init-workflow detects $provider provider"
    else
        fail "init-workflow detects $provider provider" "missing $provider detection"
    fi
done

# ── Model resolution uses get_agent_model ───────────────────────────────────

if echo "$INIT_BLOCK" | grep -q 'get_agent_model' 2>/dev/null; then
    pass "init-workflow uses get_agent_model for resolution"
else
    fail "init-workflow uses get_agent_model for resolution" "missing get_agent_model call"
fi

# ── Resolves 4 key roles ───────────────────────────────────────────────────

for role in researcher implementer reviewer synthesizer; do
    if echo "$INIT_BLOCK" | grep -q "$role" 2>/dev/null; then
        pass "init-workflow resolves $role role model"
    else
        fail "init-workflow resolves $role role model" "missing $role"
    fi
done

# ── Has --help flag ─────────────────────────────────────────────────────────

if echo "$INIT_BLOCK" | grep -q '\-\-help' 2>/dev/null; then
    pass "init-workflow has --help support"
else
    fail "init-workflow has --help support" "missing --help handler"
fi
test_summary
