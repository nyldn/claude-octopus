#!/usr/bin/env bash
# Tests for agent return contracts — verify all agents have Output Contract section
# and score_result_file has contract compliance factor
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "agent return contracts — verify all agents have Output Contract section"

AGENTS_DIR="$PROJECT_ROOT/.claude/agents"
ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"
# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
trap 'rm -f "$ALL_SRC"' EXIT
cat "$ORCHESTRATE" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── All 10 agents have Output Contract section ──────────────────────────────

for agent_file in "$AGENTS_DIR"/*.md; do
    name=$(basename "$agent_file" .md)
    if grep -q '## Output Contract' "$agent_file" 2>/dev/null; then
        pass "$name has Output Contract section"
    else
        fail "$name has Output Contract section" "missing '## Output Contract'"
    fi
done

# ── All agents have COMPLETE/BLOCKED/PARTIAL status markers ─────────────────

for agent_file in "$AGENTS_DIR"/*.md; do
    name=$(basename "$agent_file" .md)
    if grep -q 'COMPLETE' "$agent_file" && grep -q 'BLOCKED' "$agent_file" && grep -q 'PARTIAL' "$agent_file"; then
        pass "$name has COMPLETE/BLOCKED/PARTIAL statuses"
    else
        fail "$name has COMPLETE/BLOCKED/PARTIAL statuses" "missing one or more status markers"
    fi
done

# ── All agents have Confidence field in PARTIAL section ─────────────────────

for agent_file in "$AGENTS_DIR"/*.md; do
    name=$(basename "$agent_file" .md)
    if grep -q 'Confidence:' "$agent_file" 2>/dev/null; then
        pass "$name has Confidence field"
    else
        fail "$name has Confidence field" "missing Confidence:"
    fi
done

# ── score_result_file has contract compliance factor ────────────────────────

SCORE_FN=$(grep -A60 'score_result_file()' "$ALL_SRC" | head -65)
if echo "$SCORE_FN" | grep -q 'Factor 5.*[Cc]ontract' 2>/dev/null; then
    pass "score_result_file has Factor 5: contract compliance"
else
    fail "score_result_file has Factor 5: contract compliance" "missing Factor 5 comment"
fi

if echo "$SCORE_FN" | grep -q 'COMPLETE\|BLOCKED\|PARTIAL' 2>/dev/null; then
    pass "score_result_file checks for contract status markers"
else
    fail "score_result_file checks for contract status markers" "no status marker check"
fi
test_summary
