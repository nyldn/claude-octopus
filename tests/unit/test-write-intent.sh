#!/usr/bin/env bash
# tests/unit/test-write-intent.sh
# Enforces the write-intent principle (agents/principles/write-intent.md):
#   - Mode-switch commands MUST carry the idempotence check in their instructions
#   - Version-advisory hook MUST exist and be wired into SessionStart hooks.json
#   - Principle file itself MUST exist and be well-formed
#
# Regression target: the v9.29 bug where /octo:dev silently created
# .claude/claude-octopus.local.md for a user already in default Dev Work Mode.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Write-intent principle enforcement (v9.30+)"

# ═══════════════════════════════════════════════════════════════════════════════
# Principle file exists and is well-formed
# ═══════════════════════════════════════════════════════════════════════════════

test_principle_file_exists() {
    test_case "agents/principles/write-intent.md exists"
    if [[ -f "$PROJECT_ROOT/agents/principles/write-intent.md" ]]; then
        test_pass
    else
        test_fail "principle file not found"
    fi
}

test_principle_has_idempotence_section() {
    test_case "principle mandates idempotence check before Write"
    local content
    content=$(<"$PROJECT_ROOT/agents/principles/write-intent.md")
    if grep -qi "idempotence\|already match\|skip the Write" <<< "$content"; then
        test_pass
    else
        test_fail "principle does not mention idempotence / already-matching state"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# /octo:dev carries the idempotence guard
# ═══════════════════════════════════════════════════════════════════════════════

test_dev_checks_existing_state_first() {
    test_case "/octo:dev instructions check current state before writing"
    local content
    content=$(<"$PROJECT_ROOT/.claude/commands/dev.md")
    # Must mention both: "does NOT exist → show confirmation only" AND "already in Dev Work Mode"
    if grep -qi "do not create the file\|Do not rewrite the file" <<< "$content"; then
        test_pass
    else
        test_fail "dev.md does not instruct 'do not create/rewrite' when already in target mode"
    fi
}

test_dev_references_write_intent_principle() {
    test_case "/octo:dev cross-references the write-intent principle"
    local content
    content=$(<"$PROJECT_ROOT/.claude/commands/dev.md")
    if grep -q 'write-intent\.md\|write-intent-principle' <<< "$content"; then
        test_pass
    else
        test_fail "dev.md does not reference agents/principles/write-intent.md"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# /octo:km carries the idempotence guard
# ═══════════════════════════════════════════════════════════════════════════════

test_km_checks_existing_state_first() {
    test_case "/octo:km instructions check current state before writing"
    local content
    content=$(<"$PROJECT_ROOT/.claude/commands/km.md")
    if grep -qi "do not create the file\|Do not rewrite the file" <<< "$content"; then
        test_pass
    else
        test_fail "km.md does not instruct 'do not create/rewrite' when target mode matches current"
    fi
}

test_km_references_write_intent_principle() {
    test_case "/octo:km cross-references the write-intent principle"
    local content
    content=$(<"$PROJECT_ROOT/.claude/commands/km.md")
    if grep -q 'write-intent\.md\|write-intent-principle' <<< "$content"; then
        test_pass
    else
        test_fail "km.md does not reference agents/principles/write-intent.md"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Version-advisory SessionStart hook
# ═══════════════════════════════════════════════════════════════════════════════

test_version_advisory_hook_exists() {
    test_case "hooks/version-advisory.sh exists and is executable"
    local hook="$PROJECT_ROOT/hooks/version-advisory.sh"
    if [[ -f "$hook" && -x "$hook" ]]; then
        test_pass
    else
        test_fail "hook missing or not executable: $hook"
    fi
}

test_version_advisory_wired_in_hooks_json() {
    test_case "version-advisory.sh registered in SessionStart hooks"
    local hooks_json="$PROJECT_ROOT/.claude-plugin/hooks.json"
    if command -v jq >/dev/null 2>&1; then
        # Check that some SessionStart hook references version-advisory.sh
        local found
        found=$(jq -r '.SessionStart[]?.hooks[]?.command // empty' "$hooks_json" 2>/dev/null | grep -c 'version-advisory\.sh' || true)
        found=${found:-0}
        if [[ "$found" -ge 1 ]]; then
            test_pass
        else
            test_fail "hooks.json has no SessionStart entry pointing to version-advisory.sh"
        fi
    else
        # jq missing — fall back to grep
        if grep -q 'version-advisory\.sh' "$hooks_json"; then
            test_pass
        else
            test_fail "hooks.json does not reference version-advisory.sh"
        fi
    fi
}

test_version_advisory_skips_on_first_run() {
    test_case "version-advisory.sh exits silently when setup-complete marker is absent"
    local hook="$PROJECT_ROOT/hooks/version-advisory.sh"
    # Simulate: fresh HOME with no .setup-complete, stubbed plugin root
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    output=$(HOME="$tmpdir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$hook" 2>&1 || true)
    rm -rf "$tmpdir"
    if [[ -z "$output" ]]; then
        test_pass
    else
        test_fail "first-run should be silent, got output: $output"
    fi
}

test_version_advisory_seeds_on_unknown_last_seen() {
    test_case "version-advisory.sh seeds state.json silently when last_seen_version missing"
    local hook="$PROJECT_ROOT/hooks/version-advisory.sh"
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude-octopus"
    touch "$tmpdir/.claude-octopus/.setup-complete"
    local output
    output=$(HOME="$tmpdir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$hook" 2>&1 || true)
    local seeded
    seeded=$(jq -r '.last_seen_version // empty' "$tmpdir/.claude-octopus/state.json" 2>/dev/null)
    rm -rf "$tmpdir"
    if [[ -z "$output" && -n "$seeded" ]]; then
        test_pass
    else
        test_fail "expected silent seed; got output='$output' seeded='$seeded'"
    fi
}

test_version_advisory_emits_on_version_change() {
    test_case "version-advisory.sh emits advisory when version jumps"
    local hook="$PROJECT_ROOT/hooks/version-advisory.sh"
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude-octopus"
    touch "$tmpdir/.claude-octopus/.setup-complete"
    # Seed state with a stale old version
    echo '{"last_seen_version":"9.28.0"}' > "$tmpdir/.claude-octopus/state.json"
    local output
    output=$(HOME="$tmpdir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$hook" 2>&1 || true)
    rm -rf "$tmpdir"
    if grep -qi 'updated.*9\.28\.0.*9\.29' <<< "$output" && grep -q '/octo:setup\|OCTOPUS_LEGACY_ROLES' <<< "$output"; then
        test_pass
    else
        test_fail "advisory missing or malformed. Got: $output"
    fi
}

test_version_advisory_silent_when_no_change() {
    test_case "version-advisory.sh stays silent on second run (same version)"
    local hook="$PROJECT_ROOT/hooks/version-advisory.sh"
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude-octopus"
    touch "$tmpdir/.claude-octopus/.setup-complete"
    # First run: seeds silently
    HOME="$tmpdir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$hook" >/dev/null 2>&1 || true
    # Second run: should produce nothing
    local output
    output=$(HOME="$tmpdir" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$hook" 2>&1 || true)
    rm -rf "$tmpdir"
    if [[ -z "$output" ]]; then
        test_pass
    else
        test_fail "expected silent second run, got: $output"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

test_principle_file_exists
test_principle_has_idempotence_section
test_dev_checks_existing_state_first
test_dev_references_write_intent_principle
test_km_checks_existing_state_first
test_km_references_write_intent_principle
test_version_advisory_hook_exists
test_version_advisory_wired_in_hooks_json
test_version_advisory_skips_on_first_run
test_version_advisory_seeds_on_unknown_last_seen
test_version_advisory_emits_on_version_change
test_version_advisory_silent_when_no_change

test_summary
