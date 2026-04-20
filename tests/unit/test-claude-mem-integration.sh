#!/usr/bin/env bash
# Tests for claude-mem companion integration (v9.0.0)
# Validates: bridge script, doctor check, skill hints, observation wiring, provider report card
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "claude-mem companion integration (v9.0.0)"

ORCH_MAIN="$PROJECT_ROOT/scripts/orchestrate.sh"
# Combined search target (functions decomposed to lib/ in v9.7.7+)
ORCH=$(mktemp)
trap 'rm -f "$ORCH"' EXIT
cat "$ORCH_MAIN" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ORCH" 2>/dev/null
BRIDGE="$PROJECT_ROOT/scripts/claude-mem-bridge.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── 1. Bridge script exists and is executable ────────────────────────

if [[ -x "$BRIDGE" ]]; then
    pass "claude-mem-bridge.sh exists and is executable"
else
    fail "claude-mem-bridge.sh exists and is executable" "missing or not executable"
fi

# ── 2. Bridge script has all subcommands ─────────────────────────────

for cmd in available search observe context; do
    if grep -c "${cmd})" "$BRIDGE" >/dev/null 2>&1; then
        pass "Bridge subcommand: $cmd"
    else
        fail "Bridge subcommand: $cmd" "case dispatch missing for $cmd"
    fi
done

# ── 3. Bridge has fault-tolerant curl (max-time, 2>/dev/null) ────────

if grep -c 'max-time' "$BRIDGE" >/dev/null 2>&1; then
    pass "Bridge uses curl timeout (max-time)"
else
    fail "Bridge uses curl timeout" "no max-time in curl calls"
fi

if grep -c '2>/dev/null' "$BRIDGE" >/dev/null 2>&1; then
    pass "Bridge suppresses stderr (fault-tolerant)"
else
    fail "Bridge suppresses stderr" "missing 2>/dev/null"
fi

# ── 4. Doctor check for companion plugin ─────────────────────────────

if grep -c 'companion-claude-mem' "$ORCH" >/dev/null 2>&1; then
    pass "Doctor: companion-claude-mem check exists"
else
    fail "Doctor: companion-claude-mem check exists" "no doctor_add for companion-claude-mem"
fi

if grep -c 'thedotmack/claude-mem' "$ORCH" >/dev/null 2>&1; then
    pass "Doctor: checks thedotmack/claude-mem plugin cache"
else
    fail "Doctor: checks thedotmack/claude-mem plugin cache" "no plugin cache path check"
fi

# ── 5. Skill hints for claude-mem MCP tools ──────────────────────────

for skill in flow-discover flow-define flow-develop flow-deliver; do
    if grep -c 'claude-mem' "$PROJECT_ROOT/.claude/skills/${skill}.md" >/dev/null 2>&1; then
        pass "Skill hint: ${skill}.md mentions claude-mem"
    else
        fail "Skill hint: ${skill}.md mentions claude-mem" "no claude-mem reference"
    fi
done

for skill in skill-debate skill-deep-research; do
    if grep -c 'claude-mem' "$PROJECT_ROOT/.claude/skills/${skill}.md" >/dev/null 2>&1; then
        pass "Skill hint: ${skill}.md mentions claude-mem"
    else
        fail "Skill hint: ${skill}.md mentions claude-mem" "no claude-mem reference"
    fi
done

# ── 6. Smart router claude-mem hint ──────────────────────────────────

if grep -c 'claude-mem' "$PROJECT_ROOT/.claude/commands/auto.md" >/dev/null 2>&1; then
    pass "Smart router: auto.md mentions claude-mem"
else
    fail "Smart router: auto.md mentions claude-mem" "no claude-mem reference in router"
fi

# ── 7. Observation wiring in save_session_checkpoint ─────────────────

# v9.22.0 memory refactor: save_session_checkpoint now routes through memory_observe
# (lib/memory.sh), which delegates to the claude-mem or mcp-memory-service bridge.
# Accept either the legacy direct-bridge call or the new façade.
if grep -qE 'bridge_script.*observe|claude-mem-bridge.*observe|memory_observe[[:space:]]|"\$bridge"[[:space:]]+observe' "$ORCH"; then
    pass "Wired: save_session_checkpoint calls bridge observe (or memory_observe façade)"
else
    fail "Wired: save_session_checkpoint calls bridge observe" "no bridge observe or memory_observe call found"
fi

# ── 8. SessionStart memory hook queries claude-mem ───────────────────

if grep -c 'BRIDGE_SCRIPT\|claude-mem-bridge' "$PROJECT_ROOT/hooks/session-start-memory.sh" >/dev/null 2>&1; then
    pass "Wired: session-start-memory.sh queries claude-mem context"
else
    fail "Wired: session-start-memory.sh queries claude-mem context" "no bridge reference in hook"
fi

# ── 9. Provider report card function exists ──────────────────────────

if grep -c 'print_provider_report' "$ORCH" >/dev/null 2>&1; then
    pass "Function: print_provider_report exists"
else
    fail "Function: print_provider_report exists" "no print_provider_report function"
fi

# ── 10. Provider report card called at end of review_run ─────────────

report_context=$(grep -A2 'render_terminal_report' "$ORCH" | grep -c 'print_provider_report' || true)
if [[ $report_context -gt 0 ]]; then
    pass "Wired: print_provider_report called in review_run"
else
    # Check broader — might be after the terminal report block
    if grep -c 'print_provider_report.*provider_status_file' "$ORCH" >/dev/null 2>&1; then
        pass "Wired: print_provider_report called in review_run"
    else
        fail "Wired: print_provider_report called in review_run" "not called after findings output"
    fi
fi

# ── 11. Persistent fallback log in doctor ────────────────────────────

if grep -c 'provider-fallbacks.log' "$ORCH" >/dev/null 2>&1; then
    pass "Doctor: reads provider-fallbacks.log"
else
    fail "Doctor: reads provider-fallbacks.log" "no fallback log reference in doctor"
fi

if grep -c 'provider-fallbacks.*providers.*warn' "$ORCH" >/dev/null 2>&1; then
    pass "Doctor: warns on recent fallbacks"
else
    # Try alternate pattern
    if grep -c 'doctor_add.*provider-fallback' "$ORCH" >/dev/null 2>&1; then
        pass "Doctor: warns on recent fallbacks"
    else
        fail "Doctor: warns on recent fallbacks" "no doctor_add for fallback warning"
    fi
fi

# ── 12. Review default focus is all areas ────────────────────────────

if grep -c '"correctness","security","architecture","tdd"' "$ORCH" >/dev/null 2>&1; then
    pass "Review: default focus includes all 4 areas"
else
    fail "Review: default focus includes all 4 areas" "focus default not updated to all areas"
fi

# ── 13. Review auto-skip in pipeline context ─────────────────────────

if grep -c 'OCTOPUS_WORKFLOW_PHASE' "$PROJECT_ROOT/.claude/commands/review.md" >/dev/null 2>&1; then
    pass "Review: auto-skips prompts in pipeline context"
else
    fail "Review: auto-skips prompts in pipeline context" "no OCTOPUS_WORKFLOW_PHASE check in review.md"
fi

# ── 14. Codex auth preflight in review_run ───────────────────────────

if grep -c 'check_codex_auth_freshness' "$ORCH" >/dev/null 2>&1; then
    # Verify it's in review_run context, not just the function definition
    review_context=$(sed -n '/^review_run()/,/^}/p' "$ORCH" | grep -c 'check_codex_auth_freshness' || true)
    if [[ $review_context -gt 0 ]]; then
        pass "Review: Codex auth preflight wired in review_run"
    else
        fail "Review: Codex auth preflight wired in review_run" "check_codex_auth_freshness exists but not in review_run"
    fi
fi

# ── 15. Fallback status tracking in review_run ───────────────────────

if grep -c 'provider_status_file' "$ORCH" >/dev/null 2>&1; then
    pass "Review: provider status tracking file used"
else
    fail "Review: provider status tracking file used" "no provider_status_file in review_run"
fi
test_summary
