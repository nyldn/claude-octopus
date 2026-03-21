#!/usr/bin/env bash
# Tests for skill template generation system
# Verifies: gen-skill-docs.sh, shared blocks, .tmpl files, placeholder resolution
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
BLOCKS_DIR="$PROJECT_ROOT/skills/blocks"
GEN_SCRIPT="$PROJECT_ROOT/scripts/gen-skill-docs.sh"

TEST_COUNT=0; PASS_COUNT=0; FAIL_COUNT=0
pass() { TEST_COUNT=$((TEST_COUNT+1)); PASS_COUNT=$((PASS_COUNT+1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT+1)); FAIL_COUNT=$((FAIL_COUNT+1)); echo "FAIL: $1 — $2"; }

# ── Generator script exists and is executable ────────────────────────────────

if [[ -f "$GEN_SCRIPT" ]]; then
    pass "gen-skill-docs.sh exists"
else
    fail "gen-skill-docs.sh exists" "not found at $GEN_SCRIPT"
fi

if [[ -x "$GEN_SCRIPT" ]]; then
    pass "gen-skill-docs.sh is executable"
else
    fail "gen-skill-docs.sh is executable" "missing execute permission"
fi

# ── Shared blocks directory and expected files ───────────────────────────────

if [[ -d "$BLOCKS_DIR" ]]; then
    pass "skills/blocks/ directory exists"
else
    fail "skills/blocks/ directory exists" "not found at $BLOCKS_DIR"
fi

expected_blocks="preamble.md provider-setup.md visual-indicators.md quality-gates.md command-reference.md"
for block_file in $expected_blocks; do
    if [[ -f "$BLOCKS_DIR/$block_file" ]]; then
        pass "block file $block_file exists"
    else
        fail "block file $block_file exists" "not found in $BLOCKS_DIR"
    fi
done

# ── Block content validation ─────────────────────────────────────────────────

if grep -q 'generated from a template' "$BLOCKS_DIR/preamble.md" 2>/dev/null; then
    pass "preamble.md contains template notice"
else
    fail "preamble.md contains template notice" "missing expected content"
fi

if grep -q 'command -v codex' "$BLOCKS_DIR/provider-setup.md" 2>/dev/null; then
    pass "provider-setup.md contains provider check"
else
    fail "provider-setup.md contains provider check" "missing expected content"
fi

if grep -q 'OPENAI_API_KEY' "$BLOCKS_DIR/visual-indicators.md" 2>/dev/null; then
    pass "visual-indicators.md references API keys"
else
    fail "visual-indicators.md references API keys" "missing expected content"
fi

if grep -q 'Quality Dimensions' "$BLOCKS_DIR/quality-gates.md" 2>/dev/null; then
    pass "quality-gates.md contains quality dimensions"
else
    fail "quality-gates.md contains quality dimensions" "missing expected content"
fi

if grep -q 'COMMAND_LIST' "$BLOCKS_DIR/command-reference.md" 2>/dev/null; then
    pass "command-reference.md contains COMMAND_LIST placeholder"
else
    fail "command-reference.md contains COMMAND_LIST placeholder" "missing expected content"
fi

# ── Template files exist (at least 4) ───────────────────────────────────────

tmpl_count=$(find "$SKILLS_DIR" -maxdepth 1 -name '*.tmpl' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$tmpl_count" -ge 4 ]]; then
    pass "at least 4 .tmpl files exist ($tmpl_count found)"
else
    fail "at least 4 .tmpl files exist" "only $tmpl_count found"
fi

# ── Verify the 4 DD flow templates exist ─────────────────────────────────────

for tmpl_name in flow-discover.tmpl flow-define.tmpl flow-develop.tmpl flow-deliver.tmpl; do
    if [[ -f "$SKILLS_DIR/$tmpl_name" ]]; then
        pass "$tmpl_name exists"
    else
        fail "$tmpl_name exists" "not found in $SKILLS_DIR"
    fi
done

# ── Templates contain placeholders ──────────────────────────────────────────

for tmpl_name in flow-discover.tmpl flow-define.tmpl flow-develop.tmpl flow-deliver.tmpl; do
    tmpl_file="$SKILLS_DIR/$tmpl_name"
    [[ -f "$tmpl_file" ]] || continue

    if grep -q '{{PREAMBLE}}' "$tmpl_file" 2>/dev/null; then
        pass "$tmpl_name has PREAMBLE placeholder"
    else
        fail "$tmpl_name has PREAMBLE placeholder" "missing {{PREAMBLE}}"
    fi

    if grep -q '{{PROVIDER_SETUP}}' "$tmpl_file" 2>/dev/null; then
        pass "$tmpl_name has PROVIDER_SETUP placeholder"
    else
        fail "$tmpl_name has PROVIDER_SETUP placeholder" "missing {{PROVIDER_SETUP}}"
    fi

    if grep -q '{{VISUAL_INDICATORS}}' "$tmpl_file" 2>/dev/null; then
        pass "$tmpl_name has VISUAL_INDICATORS placeholder"
    else
        fail "$tmpl_name has VISUAL_INDICATORS placeholder" "missing {{VISUAL_INDICATORS}}"
    fi
done

# Quality gates placeholder only in develop and deliver templates
for tmpl_name in flow-develop.tmpl flow-deliver.tmpl; do
    tmpl_file="$SKILLS_DIR/$tmpl_name"
    [[ -f "$tmpl_file" ]] || continue

    if grep -q '{{QUALITY_GATES}}' "$tmpl_file" 2>/dev/null; then
        pass "$tmpl_name has QUALITY_GATES placeholder"
    else
        fail "$tmpl_name has QUALITY_GATES placeholder" "missing {{QUALITY_GATES}}"
    fi
done

# ── --dry-run mode works (files are fresh after generation) ──────────────────

dry_run_output=$("$GEN_SCRIPT" --dry-run 2>&1) || true
dry_run_exit=$?

# First regenerate to ensure freshness
"$GEN_SCRIPT" > /dev/null 2>&1

# Now dry-run should pass
dry_run_output=$("$GEN_SCRIPT" --dry-run 2>&1)
dry_run_exit=$?

if [[ $dry_run_exit -eq 0 ]]; then
    pass "--dry-run exits 0 when files are fresh"
else
    fail "--dry-run exits 0 when files are fresh" "exit code was $dry_run_exit"
fi

if echo "$dry_run_output" | grep -q 'OK'; then
    pass "--dry-run reports OK for fresh files"
else
    fail "--dry-run reports OK for fresh files" "no OK in output"
fi

# ── Generated .md files have NO unresolved {{...}} placeholders ──────────────

for md_name in flow-discover.md flow-define.md flow-develop.md flow-deliver.md; do
    md_file="$SKILLS_DIR/$md_name"
    [[ -f "$md_file" ]] || continue

    unresolved=$(grep -c '{{[A-Z_]*}}' "$md_file" 2>/dev/null || true)
    if [[ "$unresolved" -eq 0 ]]; then
        pass "$md_name has no unresolved placeholders"
    else
        fail "$md_name has no unresolved placeholders" "found $unresolved unresolved {{...}} patterns"
    fi
done

# ── Generated files contain expected shared block content ────────────────────

for md_name in flow-discover.md flow-define.md flow-develop.md flow-deliver.md; do
    md_file="$SKILLS_DIR/$md_name"
    [[ -f "$md_file" ]] || continue

    # Preamble block
    if grep -q 'generated from a template' "$md_file" 2>/dev/null; then
        pass "$md_name contains preamble block"
    else
        fail "$md_name contains preamble block" "missing template notice"
    fi

    # Provider setup block
    if grep -q 'command -v codex' "$md_file" 2>/dev/null; then
        pass "$md_name contains provider setup block"
    else
        fail "$md_name contains provider setup block" "missing provider check"
    fi

    # Visual indicators block
    if grep -q 'This is NOT optional' "$md_file" 2>/dev/null; then
        pass "$md_name contains visual indicators block"
    else
        fail "$md_name contains visual indicators block" "missing visual indicators"
    fi
done

# Quality gates block in develop and deliver only
for md_name in flow-develop.md flow-deliver.md; do
    md_file="$SKILLS_DIR/$md_name"
    [[ -f "$md_file" ]] || continue

    if grep -q 'Quality Dimensions' "$md_file" 2>/dev/null; then
        pass "$md_name contains quality gates block"
    else
        fail "$md_name contains quality gates block" "missing quality gates"
    fi
done

# ── Generated files preserve skill frontmatter ──────────────────────────────

for md_name in flow-discover.md flow-define.md flow-develop.md flow-deliver.md; do
    md_file="$SKILLS_DIR/$md_name"
    [[ -f "$md_file" ]] || continue

    if head -5 "$md_file" | grep -q '^---$'; then
        pass "$md_name starts with YAML frontmatter"
    else
        fail "$md_name starts with YAML frontmatter" "missing --- delimiter"
    fi

    if grep -q 'execution_mode: enforced' "$md_file" 2>/dev/null; then
        pass "$md_name has enforced execution mode"
    else
        fail "$md_name has enforced execution mode" "missing execution_mode: enforced"
    fi
done

# ── --dry-run detects stale files ────────────────────────────────────────────

# Intentionally make a file stale
echo "# stale marker" >> "$SKILLS_DIR/flow-discover.md"

stale_exit=0
stale_output=$("$GEN_SCRIPT" --dry-run 2>&1) || stale_exit=$?

if [[ $stale_exit -ne 0 ]]; then
    pass "--dry-run exits non-zero when files are stale"
else
    fail "--dry-run exits non-zero when files are stale" "exit code was 0"
fi

if echo "$stale_output" | grep -q 'STALE'; then
    pass "--dry-run reports STALE for modified files"
else
    fail "--dry-run reports STALE for modified files" "no STALE in output"
fi

# Restore fresh state
"$GEN_SCRIPT" > /dev/null 2>&1

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS_COUNT/$TEST_COUNT passed, $FAIL_COUNT failed ==="

[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1