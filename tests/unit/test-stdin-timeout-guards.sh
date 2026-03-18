#!/usr/bin/env bash
# Tests for stdin timeout guards — verify all hook files use timeout-guarded cat reads
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/hooks"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── Verify timeout-guarded cat in each hook file ────────────────────────────

for hook in context-reinforcement.sh octopus-statusline.sh user-prompt-submit.sh \
            subagent-result-capture.sh budget-gate.sh task-completion-checkpoint.sh; do
    hook_file="$HOOKS_DIR/$hook"
    if [[ ! -f "$hook_file" ]]; then
        fail "$hook exists" "file not found: $hook_file"
        continue
    fi

    if grep -q 'timeout.*cat' "$hook_file" 2>/dev/null; then
        pass "$hook has timeout-guarded cat"
    else
        fail "$hook has timeout-guarded cat" "no 'timeout.*cat' pattern found"
    fi
done

# ── Verify no bare INPUT=$(cat) without timeout remains ─────────────────────

for hook in context-reinforcement.sh octopus-statusline.sh user-prompt-submit.sh \
            subagent-result-capture.sh task-completion-checkpoint.sh; do
    hook_file="$HOOKS_DIR/$hook"
    [[ ! -f "$hook_file" ]] && continue

    # Match bare cat without timeout (but skip comments)
    if grep -v '^#' "$hook_file" | grep -qE '\$\(cat\)$|=\$\(cat\)' 2>/dev/null; then
        fail "$hook has no bare cat" "found unguarded \$(cat)"
    else
        pass "$hook has no bare cat"
    fi
done

# ── budget-gate uses timeout on cat drain ───────────────────────────────────

if grep -v '^#' "$HOOKS_DIR/budget-gate.sh" | grep -q 'timeout.*cat.*dev.null' 2>/dev/null; then
    pass "budget-gate.sh drains stdin with timeout"
else
    fail "budget-gate.sh drains stdin with timeout" "expected timeout cat > /dev/null pattern"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "stdin-timeout-guards: $PASS_COUNT/$TEST_COUNT passed"
[[ $FAIL_COUNT -gt 0 ]] && echo "FAILURES: $FAIL_COUNT" && exit 1
echo "All tests passed."
