#!/usr/bin/env bash
# Tests for CC v2.1.76 feature detection sync
# Validates: 6 new SUPPORTS_* flags, v2.1.76 detection block, wiring, doctor checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── 1. Flag declarations exist ────────────────────────────────────────

for flag in SUPPORTS_MCP_ELICITATION SUPPORTS_ELICITATION_HOOKS \
            SUPPORTS_WORKTREE_SPARSE_PATHS SUPPORTS_POST_COMPACT_HOOK \
            SUPPORTS_EFFORT_COMMAND SUPPORTS_BG_PARTIAL_RESULTS; do
    if grep -c "${flag}=false" "$ORCH" >/dev/null 2>&1; then
        pass "Declaration: $flag"
    else
        fail "Declaration: $flag" "missing ${flag}=false in orchestrate.sh"
    fi
done

# ── 2. v2.1.76 detection block exists and sets all 6 flags ───────────

if grep -c 'version_compare.*2\.1\.76' "$ORCH" >/dev/null 2>&1; then
    pass "v2.1.76 detection block exists"
else
    fail "v2.1.76 detection block exists" "no version_compare for 2.1.76"
fi

v2176_block=$(grep -A15 'version_compare.*2\.1\.76' "$ORCH" | head -15)

for flag in SUPPORTS_MCP_ELICITATION SUPPORTS_ELICITATION_HOOKS \
            SUPPORTS_WORKTREE_SPARSE_PATHS SUPPORTS_POST_COMPACT_HOOK \
            SUPPORTS_EFFORT_COMMAND SUPPORTS_BG_PARTIAL_RESULTS; do
    if echo "$v2176_block" | grep -c "$flag=true" >/dev/null 2>&1; then
        pass "v2.1.76 block sets: $flag"
    else
        fail "v2.1.76 block sets: $flag" "not found in v2.1.76 detection block"
    fi
done

# ── 3. Logging lines for new flags ───────────────────────────────────

for label in "MCP Elicitation" "Elicitation Hooks" "Worktree Sparse Paths" \
             "Post Compact Hook" "Effort Command" "BG Partial Results"; do
    if grep -c "$label" "$ORCH" >/dev/null 2>&1; then
        pass "Log line: $label"
    else
        fail "Log line: $label" "missing from logging output"
    fi
done

# ── 4. Wiring: spawn_agent BG partial results ────────────────────────

if grep -c 'SUPPORTS_BG_PARTIAL_RESULTS.*true' "$ORCH" >/dev/null 2>&1; then
    if grep -c 'background agent partial results' "$ORCH" >/dev/null 2>&1; then
        pass "Wired: SUPPORTS_BG_PARTIAL_RESULTS in spawn_agent"
    else
        fail "Wired: SUPPORTS_BG_PARTIAL_RESULTS in spawn_agent" "no spawn_agent log for BG partial results"
    fi
fi

# ── 5. Wiring: doctor effort-command ─────────────────────────────────

if grep -c 'doctor_add.*effort-command' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor effort-command check"
else
    fail "Wired: doctor effort-command check" "no doctor_add for effort-command"
fi

# ── 6. Wiring: doctor worktree-sparse-paths ──────────────────────────

if grep -c 'doctor_add.*worktree-sparse-paths' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor worktree-sparse-paths check"
else
    fail "Wired: doctor worktree-sparse-paths check" "no doctor_add for worktree-sparse-paths"
fi

# ── 7. Wiring: doctor MCP elicitation ────────────────────────────────

if grep -c 'doctor_add.*mcp-elicitation' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor mcp-elicitation check"
else
    fail "Wired: doctor mcp-elicitation check" "no doctor_add for mcp-elicitation"
fi

# ── 8. Wiring: doctor plugin-dir one-path warning ────────────────────

if grep -c 'doctor_add.*plugin-dir-one-path' "$ORCH" >/dev/null 2>&1; then
    pass "Wired: doctor plugin-dir-one-path warning"
else
    fail "Wired: doctor plugin-dir-one-path warning" "no doctor_add for plugin-dir behavioral change"
fi

# ── 9. Flag comments reference correct CC version ────────────────────

for flag_ver in "MCP_ELICITATION.*v2.1.76" "ELICITATION_HOOKS.*v2.1.76" \
                "WORKTREE_SPARSE_PATHS.*v2.1.76" "POST_COMPACT_HOOK.*v2.1.76" \
                "EFFORT_COMMAND.*v2.1.76" "BG_PARTIAL_RESULTS.*v2.1.76"; do
    if grep -cE "$flag_ver" "$ORCH" >/dev/null 2>&1; then
        pass "Version comment: $flag_ver"
    else
        fail "Version comment: $flag_ver" "missing or wrong version in comment"
    fi
done

# ── 10. Total flag count validation (100 total with 6 new) ───────────

flag_count=$(grep -c 'SUPPORTS_.*=false' "$ORCH" || true)
if [[ $flag_count -ge 100 ]]; then
    pass "Total flag count: $flag_count (expected >= 100)"
else
    fail "Total flag count: $flag_count" "expected >= 100 flags"
fi

# ── 11. Version_compare block count (31 total) ──────────────────────

block_count=$(grep -c 'version_compare.*CLAUDE_CODE_VERSION' "$ORCH" || true)
if [[ $block_count -ge 31 ]]; then
    pass "Version compare block count: $block_count (expected >= 31)"
else
    fail "Version compare block count: $block_count" "expected >= 31 blocks"
fi

# ── 12. No v2.1.75 block (no plugin-relevant changes) ───────────────

if grep -c 'version_compare.*2\.1\.75' "$ORCH" >/dev/null 2>&1; then
    fail "No v2.1.75 block" "unexpected v2.1.75 detection block found (v2.1.75 has no plugin-relevant changes)"
else
    pass "No v2.1.75 block (correct — v2.1.75 has no plugin-relevant changes)"
fi

# ── 13. Doctor checks use correct CC version references ──────────────

if grep -c 'CC v2.1.76.*effort' "$ORCH" >/dev/null 2>&1; then
    pass "Doctor: effort check references CC v2.1.76"
else
    fail "Doctor: effort check references CC v2.1.76" "doctor effort check missing v2.1.76 reference"
fi

if grep -c 'CC v2.1.76.*sparse' "$ORCH" >/dev/null 2>&1; then
    pass "Doctor: sparse paths check references CC v2.1.76"
else
    fail "Doctor: sparse paths check references CC v2.1.76" "doctor sparse paths check missing v2.1.76 reference"
fi

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "==============================================="
echo "CC v2.1.76 sync tests: $PASS_COUNT/$TEST_COUNT passed"
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "$FAIL_COUNT FAILED"
    exit 1
fi
echo "All tests passed."
