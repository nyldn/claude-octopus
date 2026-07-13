#!/bin/bash
# tests/smoke/test-costs-command.sh
# Static analysis tests for the /octo:costs command
# Validates: file existence, frontmatter, plugin.json registration, content correctness

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Costs Command (/octo:costs)"

COSTS_CMD="$PROJECT_ROOT/commands/costs.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

# ── File existence ───────────────────────────────────────────────────

test_costs_file_exists() {
    test_case "costs.md command file exists"
    if [[ -f "$COSTS_CMD" ]]; then
        test_pass
    else
        test_fail "costs.md not found at $COSTS_CMD"
    fi
}

# ── Frontmatter validation ──────────────────────────────────────────

test_costs_has_frontmatter() {
    test_case "costs.md has valid YAML frontmatter"
    local first_line
    first_line=$(head -1 "$COSTS_CMD")
    if [[ "$first_line" == "---" ]]; then
        test_pass
    else
        test_fail "costs.md does not start with YAML frontmatter delimiter"
    fi
}

test_costs_frontmatter_command_field() {
    test_case "frontmatter contains command: costs"
    if grep -c '^command: costs' "$COSTS_CMD" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "frontmatter missing 'command: costs'"
    fi
}

test_costs_frontmatter_description() {
    test_case "frontmatter contains description field"
    if grep -c '^description:' "$COSTS_CMD" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "frontmatter missing description"
    fi
}

# ── Plugin.json registration ────────────────────────────────────────

test_costs_registered_in_plugin_json() {
    test_case "costs.md is registered in plugin.json commands array"
    if grep -c 'commands/costs.md' "$PLUGIN_JSON" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "costs.md not found in plugin.json commands array"
    fi
}

# ── Content validation ──────────────────────────────────────────────

test_costs_has_provider_cost_references() {
    test_case "contains provider cost reference table"
    local content
    content=$(<"$COSTS_CMD")
    local found=0
    for provider in "Claude Opus" "Claude Sonnet" "Codex CLI" "Gemini CLI" "Perplexity"; do
        if echo "$content" | grep -c "$provider" >/dev/null 2>&1; then
            found=$((found + 1))
        fi
    done
    if [[ $found -ge 4 ]]; then
        test_pass
    else
        test_fail "expected at least 4 provider cost references, found $found"
    fi
}

test_costs_mentions_session_view() {
    test_case "mentions session-level view"
    if grep -ci 'session' "$COSTS_CMD" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "no mention of session view"
    fi
}

test_costs_mentions_cumulative_view() {
    test_case "mentions cumulative view"
    if grep -ci 'cumulative' "$COSTS_CMD" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "no mention of cumulative view"
    fi
}

test_costs_has_workflow_breakdown() {
    test_case "contains workflow breakdown section"
    if grep -Ec 'Workflow.*Breakdown|Per-Workflow|workflow.*breakdown' "$COSTS_CMD" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "no workflow breakdown section found"
    fi
}

# ── Attribution check ───────────────────────────────────────────────

test_costs_no_attribution_references() {
    test_case "no attribution references to source repos"
    local content
    content=$(<"$COSTS_CMD")
    local violations=0
    for term in "gsd-2" "strategic-audit" "get-shit-done"; do
        if echo "$content" | grep -ci "$term" >/dev/null 2>&1; then
            echo "  found banned reference: $term"
            violations=$((violations + 1))
        fi
    done
    if [[ $violations -eq 0 ]]; then
        test_pass
    else
        test_fail "found $violations attribution references that should not be present"
    fi
}

# ── Run all tests ───────────────────────────────────────────────────

test_costs_file_exists
test_costs_has_frontmatter
test_costs_frontmatter_command_field
test_costs_frontmatter_description
test_costs_registered_in_plugin_json
test_costs_has_provider_cost_references
test_costs_mentions_session_view
test_costs_mentions_cumulative_view
test_costs_has_workflow_breakdown
test_costs_no_attribution_references

test_summary
