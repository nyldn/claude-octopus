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

test_costs_uses_deterministic_helper() {
    test_case "delegates cost calculation to usage-report.sh"
    if grep -Fq 'scripts/helpers/usage-report.sh' "$COSTS_CMD" &&
       grep -Fq -- '--view costs' "$COSTS_CMD" &&
       ! grep -Eq 'STEP 2: Parse|Per-Query Estimate|calculated from the Cost Reference' "$COSTS_CMD"; then
        test_pass
    else
        test_fail "costs.md must delegate to usage-report.sh --view costs without model-side math"
    fi
}

test_costs_selects_one_output_format() {
    test_case "table and JSON formats share one mutually exclusive helper invocation"
    local invocation_count
    invocation_count="$(grep -Fc '"$helper" --view costs --format "$format"' "$COSTS_CMD" || true)"
    if [[ "$invocation_count" -eq 1 ]] &&
       grep -Fq 'format="table"' "$COSTS_CMD" &&
       grep -Fq 'format="json"' "$COSTS_CMD" &&
       grep -Fq 'case " $ARGUMENTS " in' "$COSTS_CMD" &&
       ! grep -Fq '${ARGUMENTS' "$COSTS_CMD" &&
       grep -Fq 'For JSON, emit only the helper output' "$COSTS_CMD"; then
        test_pass
    else
        test_fail "costs must select one format before invoking the helper, with banner-free JSON"
    fi
}

test_costs_rendered_arguments_select_format() {
    test_case "rendered command arguments select table and JSON behavior"
    local runtime_root command_script table_script json_script table_output json_output
    runtime_root="$TEST_TMP_DIR/costs-runtime"
    mkdir -p "$runtime_root/scripts/helpers"
    cat > "$runtime_root/scripts/helpers/usage-report.sh" <<'HELPER'
#!/usr/bin/env bash
printf '%s\n' "$*"
HELPER
    chmod +x "$runtime_root/scripts/helpers/usage-report.sh"
    command_script="$(awk '/^```bash$/{capture=1; next} capture && /^```$/{exit} capture{print}' "$COSTS_CMD")"
    table_script="$(sed 's/\$ARGUMENTS//g' <<<"$command_script")"
    json_script="$(sed 's/\$ARGUMENTS/--format json/g' <<<"$command_script")"
    table_output="$(CLAUDE_PLUGIN_ROOT="$runtime_root" bash -c "$table_script")"
    json_output="$(CLAUDE_PLUGIN_ROOT="$runtime_root" bash -c "$json_script")"
    if [[ "$table_output" == "--view costs --format table" ]] &&
       [[ "$json_output" == "--view costs --format json" ]]; then
        test_pass
    else
        test_fail "rendered formats diverged: table=$table_output json=$json_output"
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

test_costs_mentions_compatibility_destination() {
    test_case "identifies /octo:usage as the canonical destination"
    if grep -Fq '/octo:usage' "$COSTS_CMD"; then
        test_pass
    else
        test_fail "costs compatibility command must name /octo:usage"
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
test_costs_uses_deterministic_helper
test_costs_selects_one_output_format
test_costs_rendered_arguments_select_format
test_costs_mentions_session_view
test_costs_mentions_compatibility_destination
test_costs_has_workflow_breakdown
test_costs_no_attribution_references

test_summary
