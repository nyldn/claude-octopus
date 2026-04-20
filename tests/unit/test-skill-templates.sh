#!/usr/bin/env bash
# Tests for skill template generation system
# Verifies: gen-skill-docs.sh, shared blocks, .tmpl files, placeholder resolution
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "skill template generation system"

SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
BLOCKS_DIR="$PROJECT_ROOT/skills/blocks"
GEN_SCRIPT="$PROJECT_ROOT/scripts/gen-skill-docs.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

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

# ── Shared blocks directory ────────────────────────────────────────────────────

if [[ -d "$BLOCKS_DIR" ]]; then
    pass "skills/blocks/ directory exists"
    expected_blocks="provider-check.md"
    for block_file in $expected_blocks; do
        if [[ -f "$BLOCKS_DIR/$block_file" ]]; then
            pass "block file $block_file exists"
        else
            fail "block file $block_file exists" "not found in $BLOCKS_DIR"
        fi
    done
else
    fail "skills/blocks/ directory exists" "not found"
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

    if grep -q '{{PROVIDER_CHECK}}' "$tmpl_file" 2>/dev/null; then
        pass "$tmpl_name has PROVIDER_CHECK placeholder"
    else
        fail "$tmpl_name has PROVIDER_CHECK placeholder" "missing {{PROVIDER_CHECK}}"
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

# ── Flow skill files exist and have valid structure ──────────────────────────
# Note: since v9.10.2, flow-*.md are directly authored (not generated from blocks)

for md_name in flow-discover.md flow-define.md flow-develop.md flow-deliver.md; do
    md_file="$SKILLS_DIR/$md_name"
    if [[ -f "$md_file" ]]; then
        pass "$md_name exists"
    else
        fail "$md_name exists" "not found in $SKILLS_DIR"
        continue
    fi

    # Must have YAML frontmatter with execution_mode: enforced
    if head -5 "$md_file" | grep -q '^---$'; then
        pass "$md_name has YAML frontmatter"
    else
        fail "$md_name has YAML frontmatter" "missing --- delimiter"
    fi

    if grep -q 'execution_mode: enforced' "$md_file" 2>/dev/null; then
        pass "$md_name has enforced execution mode"
    else
        fail "$md_name has enforced execution mode" "missing execution_mode: enforced"
    fi

    # Must reference orchestrate.sh (the actual execution contract)
    if grep -q 'orchestrate.sh' "$md_file" 2>/dev/null; then
        pass "$md_name references orchestrate.sh"
    else
        fail "$md_name references orchestrate.sh" "missing orchestrate.sh reference"
    fi
done

# ── Template system dry-run (only if gen-skill-docs.sh and blocks exist) ─────

if [[ -x "$GEN_SCRIPT" && -d "$BLOCKS_DIR" ]]; then
    # Intentionally make a file stale
    echo "# stale marker" >> "$SKILLS_DIR/flow-discover.md"

    stale_exit=0
    stale_output=$("$GEN_SCRIPT" --dry-run 2>&1) || stale_exit=$?

    if [[ $stale_exit -ne 0 ]]; then
        pass "--dry-run exits non-zero when files are stale"
    else
        fail "--dry-run exits non-zero when files are stale" "exit code was 0"
    fi

    # Restore fresh state
    "$GEN_SCRIPT" > /dev/null 2>&1
else
    pass "template generation skipped (blocks removed, skills directly authored)"
fi
test_summary
