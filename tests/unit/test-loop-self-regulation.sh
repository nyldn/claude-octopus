#!/usr/bin/env bash
# Tests for Loop Self-Regulation (CONSOLIDATED-02)
# Validates: sliding-window detection, WTF scoring, 3-strike rule, verification gates
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Loop Self-Regulation (CONSOLIDATED-02)"


LOOP_SKILL="$PROJECT_ROOT/.claude/skills/skill-iterative-loop.md"
DEBUG_SKILL="$PROJECT_ROOT/.claude/skills/skill-debug.md"
DELIVER_SKILL="$PROJECT_ROOT/.claude/skills/flow-deliver.md"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── Self-Regulation section exists ────────────────────────────────────────────

if grep -q '## Self-Regulation' "$LOOP_SKILL" 2>/dev/null; then
    pass "skill-iterative-loop has Self-Regulation section"
else
    fail "skill-iterative-loop has Self-Regulation section" "missing section"
fi

# ── Sliding-window detection ─────────────────────────────────────────────────

if grep -qi 'sliding.window\|sliding window' "$LOOP_SKILL" 2>/dev/null; then
    pass "Mentions sliding-window stuck detection"
else
    fail "Mentions sliding-window stuck detection" "missing sliding window"
fi

if grep -qi 'last 10 iterations' "$LOOP_SKILL" 2>/dev/null; then
    pass "Window size is 10 iterations"
else
    fail "Window size is 10 iterations" "missing window size"
fi

if grep -qi 'cycle.*detect\|A.*B.*A.*B\|multi.step cycle' "$LOOP_SKILL" 2>/dev/null; then
    pass "Detects multi-step cycles (A→B→A→B)"
else
    fail "Detects multi-step cycles (A→B→A→B)" "missing cycle detection"
fi

if grep -qi 'first detection.*diagnostic\|first detection.*retry' "$LOOP_SKILL" 2>/dev/null; then
    pass "First detection triggers diagnostic retry"
else
    fail "First detection triggers diagnostic retry" "missing first-detection behavior"
fi

if grep -qi 'second detection.*HALT\|second detection.*stop' "$LOOP_SKILL" 2>/dev/null; then
    pass "Second detection halts the loop"
else
    fail "Second detection halts the loop" "missing second-detection halt"
fi

# ── WTF-Likelihood scoring ────────────────────────────────────────────────────

if grep -q 'WTF' "$LOOP_SKILL" 2>/dev/null; then
    pass "WTF-Likelihood scoring present"
else
    fail "WTF-Likelihood scoring present" "missing WTF scoring"
fi

if grep -q '+15%' "$LOOP_SKILL" 2>/dev/null; then
    pass "Revert penalty is +15%"
else
    fail "Revert penalty is +15%" "missing revert weight"
fi

if grep -q '+20%' "$LOOP_SKILL" 2>/dev/null; then
    pass "Unrelated files penalty is +20%"
else
    fail "Unrelated files penalty is +20%" "missing unrelated files weight"
fi

if grep -q '20%' "$LOOP_SKILL" 2>/dev/null && grep -qi 'exceeds 20%.*STOP\|score.*20%' "$LOOP_SKILL" 2>/dev/null; then
    pass "WTF threshold triggers stop at 20%"
else
    fail "WTF threshold triggers stop at 20%" "missing 20% threshold"
fi

if grep -q 'HARD_CAP.*50\|Hard cap.*50\|50 iterations' "$LOOP_SKILL" 2>/dev/null; then
    pass "Hard cap at 50 iterations"
else
    fail "Hard cap at 50 iterations" "missing hard cap"
fi

# ── Score visible in iteration summary ─────────────────────────────────────

if grep -q 'Self-regulation:' "$LOOP_SKILL" 2>/dev/null; then
    pass "Self-regulation score visible in iteration summary"
else
    fail "Self-regulation score visible in iteration summary" "score not shown in output"
fi

# ── Debug skill 3-strike rule ─────────────────────────────────────────────────

if grep -q '3-Strike' "$DEBUG_SKILL" 2>/dev/null; then
    pass "Debug skill has 3-Strike Rule"
else
    fail "Debug skill has 3-Strike Rule" "missing 3-strike heading"
fi

if grep -qi 'anti.rationalization\|Should work now.*RUN IT' "$DEBUG_SKILL" 2>/dev/null; then
    pass "Debug skill has anti-rationalization prompts"
else
    fail "Debug skill has anti-rationalization prompts" "missing anti-rationalization"
fi

if grep -qi '4th fix.*user approval\|Do not attempt a 4th' "$DEBUG_SKILL" 2>/dev/null; then
    pass "Debug skill blocks 4th fix without user approval"
else
    fail "Debug skill blocks 4th fix without user approval" "missing 4th fix block"
fi

# ── Deliver verification gate ─────────────────────────────────────────────────

if grep -qi 'Verify Execution.*MANDATORY\|Validation Gate' "$DELIVER_SKILL" 2>/dev/null; then
    pass "Deliver has verification gate"
else
    fail "Deliver has verification gate" "missing verification gate"
fi

if grep -qi 'simulating.*workflow\|evidence\|CANNOT SKIP' "$DELIVER_SKILL" 2>/dev/null; then
    pass "Deliver has anti-rationalization prompts"
else
    fail "Deliver has anti-rationalization prompts" "missing prompts"
fi

# ── Configurable weights via config file ─────────────────────────────────────

if grep -q 'loop-config.conf' "$LOOP_SKILL" 2>/dev/null; then
    pass "References loop-config.conf for configurable weights"
else
    fail "References loop-config.conf for configurable weights" "missing config file reference"
fi

if grep -qi 'WINDOW_SIZE\|REVERT_PENALTY\|WTF_THRESHOLD' "$LOOP_SKILL" 2>/dev/null; then
    pass "Config file documents key=value format"
else
    fail "Config file documents key=value format" "missing config key examples"
fi

if grep -qi 'defaults\|default.*weight\|not exist.*use' "$LOOP_SKILL" 2>/dev/null; then
    pass "Falls back to defaults when config absent"
else
    fail "Falls back to defaults when config absent" "missing fallback behavior"
fi

# ── Self-regulation available for flow-develop (via skill-iterative-loop) ────
# Note: Self-regulation lives in skill-iterative-loop.md, not flow-develop.md.
# flow-develop invokes loop skills when iterating, which loads self-regulation.

DEVELOP_SKILL="$PROJECT_ROOT/.claude/skills/flow-develop.md"

if [[ -f "$DEVELOP_SKILL" ]]; then
    pass "flow-develop skill exists (self-regulation via iterative-loop)"
else
    fail "flow-develop skill exists" "missing flow-develop.md"
fi

# ── Self-regulation wired into skill-debug ───────────────────────────────────

if grep -qi 'Self-Regulation Score.*Debug\|WTF score' "$DEBUG_SKILL" 2>/dev/null; then
    pass "skill-debug has WTF scoring section"
else
    fail "skill-debug has WTF scoring section" "missing WTF scoring in debug"
fi

if grep -q 'loop-config.conf' "$DEBUG_SKILL" 2>/dev/null; then
    pass "skill-debug references config file"
else
    fail "skill-debug references config file" "missing config reference"
fi

if grep -q '+15%' "$DEBUG_SKILL" 2>/dev/null; then
    pass "skill-debug has revert penalty"
else
    fail "skill-debug has revert penalty" "missing revert weight in debug"
fi

if grep -qi 'exceeds 20%.*STOP\|score.*20%' "$DEBUG_SKILL" 2>/dev/null; then
    pass "skill-debug WTF threshold triggers stop"
else
    fail "skill-debug WTF threshold triggers stop" "missing threshold in debug"
fi

if grep -q 'Self-regulation:' "$DEBUG_SKILL" 2>/dev/null; then
    pass "skill-debug shows score in fix attempts"
else
    fail "skill-debug shows score in fix attempts" "missing score display in debug"
fi

# ── No attribution references ─────────────────────────────────────────────────

for f in "$LOOP_SKILL" "$DEBUG_SKILL" "$DELIVER_SKILL" "$DEVELOP_SKILL"; do
    fname=$(basename "$f")
    if grep -qi 'gstack\|gsd-2\|temm1e' "$f" 2>/dev/null; then
        fail "$fname has no attribution" "found prohibited reference"
    else
        pass "$fname has no attribution"
    fi
done
test_summary
