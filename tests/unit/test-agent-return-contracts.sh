#!/usr/bin/env bash
# Tests for agent return contracts — verify all agents have Output Contract section
# and score_result_file has contract compliance factor
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_DIR="$PROJECT_ROOT/.claude/agents"
ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

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

SCORE_FN=$(grep -A60 'score_result_file()' "$ORCHESTRATE" | head -65)
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

echo ""
echo "═══════════════════════════════════════════════════"
echo "agent-return-contracts: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
