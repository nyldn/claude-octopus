#!/usr/bin/env bash
# tests/unit/test-agent-output-cap.sh
# Asserts the run_agent_sync output cap + partial-writes diagnostics introduced
# in v9.23.0. These are static grep-level assertions so the suite stays fast
# and hermetic (no real CLI dispatch). Behavioural verification lives in
# tests/integration/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_SYNC="$PROJECT_ROOT/scripts/lib/agent-sync.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── Output cap is declared with a sane default ──────────────────────
if grep -q 'OCTOPUS_AGENT_MAX_OUTPUT_BYTES:-262144' "$AGENT_SYNC"; then
    pass "output cap defaults to 256 KiB (OCTOPUS_AGENT_MAX_OUTPUT_BYTES)"
else
    fail "output cap default" "OCTOPUS_AGENT_MAX_OUTPUT_BYTES:-262144 not found"
fi

# ── Cap respects 0 as a disable sentinel ────────────────────────────
if grep -q '_max_bytes -gt 0' "$AGENT_SYNC"; then
    pass "cap honours 0 as disable sentinel"
else
    fail "cap disable sentinel" "missing '\$_max_bytes -gt 0' guard"
fi

# ── Truncation is tail-biased (codex summary lives at the end) ──────
if grep -q '_tail="\${output: -\$_tail_bytes}"' "$AGENT_SYNC"; then
    pass "truncation preserves tail (deliverable summary)"
else
    fail "tail-biased truncation" "tail slice not applied"
fi

# ── Truncation banner is emitted between head and tail ──────────────
if grep -q 'OUTPUT TRUNCATED' "$AGENT_SYNC"; then
    pass "truncation banner is emitted"
else
    fail "truncation banner" "OUTPUT TRUNCATED marker missing"
fi

# ── Partial-writes detection only runs on timeout exit codes ────────
if grep -qE 'exit_code -eq 124 \|\| \$exit_code -eq 143|exit_code -eq 124 \|\| exit_code -eq 143' "$AGENT_SYNC"; then
    pass "partial-writes probe gated on 124/143 (timeout exit codes)"
else
    fail "partial-writes gate" "timeout exit-code guard missing"
fi

# ── Partial-writes probe scopes to dispatch CWD + dispatch start ────
if grep -q 'find "\$_dispatch_cwd" -type f -newermt "@\${_dispatch_start}"' "$AGENT_SYNC"; then
    pass "partial-writes probe scoped to dispatch CWD + start time"
else
    fail "partial-writes scope" "find with -newermt@dispatch_start not found"
fi

# ── Noise paths excluded from probe ─────────────────────────────────
if grep -q "not -path '\*/\.git/\*'" "$AGENT_SYNC" && \
   grep -q "not -path '\*/node_modules/\*'" "$AGENT_SYNC"; then
    pass "partial-writes probe excludes .git and node_modules"
else
    fail "noise exclusions" ".git / node_modules -not -path filters missing"
fi

echo ""
echo "Total: $TEST_COUNT | Pass: $PASS_COUNT | Fail: $FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
