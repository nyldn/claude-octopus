#!/usr/bin/env bash
# Test suite for AI Debate Hub integration
# Verifies skill-debate.md, command routing, attribution, and version consistency

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "AI Debate Hub Integration"

test_debate_skill_exists() {
    test_case "Debate skill exists (skill-debate.md)"

    local skill_file="$PROJECT_ROOT/.claude/skills/skill-debate.md"

    if [[ -f "$skill_file" ]]; then
        test_pass
    else
        test_fail "skill-debate.md not found at $skill_file"
        return 1
    fi
}

test_skill_has_frontmatter() {
    test_case "skill-debate.md has YAML frontmatter"

    local skill_file="$PROJECT_ROOT/.claude/skills/skill-debate.md"

    if grep -q "^---$" "$skill_file" && \
       grep -q "^name: skill-debate$" "$skill_file" && \
       grep -q "^description:" "$skill_file"; then
        test_pass
    else
        test_fail "skill-debate.md missing required YAML frontmatter"
        return 1
    fi
}

test_skill_has_attribution() {
    test_case "skill-debate.md includes wolverin0 attribution"

    local skill_file="$PROJECT_ROOT/.claude/skills/skill-debate.md"

    if grep -q "wolverin0" "$skill_file" && \
       grep -q "https://github.com/wolverin0/claude-skills" "$skill_file"; then
        test_pass
    else
        test_fail "Missing attribution to wolverin0"
        return 1
    fi
}

test_plugin_json_includes_debate() {
    test_case "plugin.json includes debate skill"

    local plugin_file="$PROJECT_ROOT/.claude-plugin/plugin.json"

    if grep -q ".claude/skills/skill-debate.md" "$plugin_file"; then
        test_pass
    else
        test_fail "plugin.json missing debate skill reference"
        return 1
    fi
}

test_debate_skill_content() {
    test_case "skill-debate.md contains expected content"

    local skill_file="$PROJECT_ROOT/.claude/skills/skill-debate.md"

    if [[ ! -f "$skill_file" ]]; then
        test_fail "skill-debate.md not found"
        return 1
    fi

    if grep -q "Debate" "$skill_file" && \
       grep -q "Gemini" "$skill_file" && \
       grep -q "Codex" "$skill_file"; then
        test_pass
    else
        test_fail "skill-debate.md missing expected content"
        return 1
    fi
}

test_debate_has_quality_gates() {
    test_case "skill-debate.md includes quality gates (merged from integration)"

    local skill_file="$PROJECT_ROOT/.claude/skills/skill-debate.md"

    if grep -q "Quality Gates" "$skill_file" && \
       grep -q "Cost Tracking" "$skill_file"; then
        test_pass
    else
        test_fail "skill-debate.md missing quality gates or cost tracking sections"
        return 1
    fi
}

test_debate_command_routing() {
    test_case "Debate command routing exists in orchestrate.sh"

    local orch="$PROJECT_ROOT/scripts/orchestrate.sh"
    local libs="$PROJECT_ROOT/scripts/lib/*.sh"

    if grep -rq "debate|deliberate|consensus)" $orch $libs && \
       grep -rq "wolverin0" $orch $libs; then
        test_pass
    else
        test_fail "orchestrate.sh/lib missing debate command routing or attribution"
        return 1
    fi
}

test_readme_attribution() {
    test_case "README.md includes AI Debate Hub attribution"

    local readme="$PROJECT_ROOT/README.md"

    if grep -q "wolverin0" "$readme" && \
       grep -q "AI Debate Hub" "$readme" && \
       grep -q "https://github.com/wolverin0/claude-skills" "$readme"; then
        test_pass
    else
        test_fail "README.md missing AI Debate Hub attribution"
        return 1
    fi
}

test_changelog_attribution() {
    test_case "CHANGELOG.md has version entries"

    local changelog="$PROJECT_ROOT/CHANGELOG.md"

    if [[ -f "$changelog" ]] && grep -q '\[8\.' "$changelog"; then
        test_pass
    else
        test_fail "CHANGELOG.md missing or has no version entries"
        return 1
    fi
}

test_version_consistency() {
    test_case "Version consistency across all files"

    local plugin_json="$PROJECT_ROOT/.claude-plugin/plugin.json"
    local package_json="$PROJECT_ROOT/package.json"
    local marketplace_json="$PROJECT_ROOT/.claude-plugin/marketplace.json"

    local plugin_version=$(grep '"version"' "$plugin_json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
    local package_version=$(grep '"version"' "$package_json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')

    if ! command -v jq >/dev/null 2>&1; then
        test_fail "jq is required to parse marketplace.json"
        return 1
    fi

    local marketplace_version
    if ! marketplace_version=$(jq -r '.plugins[] | select(.name == "octo") | .version // empty' "$marketplace_json"); then
        test_fail "Unable to parse octo version from marketplace.json"
        return 1
    fi

    if [[ "$plugin_version" == "$package_version" ]] && \
       [[ "$package_version" == "$marketplace_version" ]]; then
        test_pass
    else
        test_fail "Version mismatch: plugin=$plugin_version, package=$package_version, marketplace=$marketplace_version"
        return 1
    fi
}

# Run all tests
test_debate_skill_exists
test_skill_has_frontmatter
test_skill_has_attribution
test_plugin_json_includes_debate
test_debate_skill_content
test_debate_has_quality_gates
test_debate_command_routing
test_readme_attribution
test_changelog_attribution
test_version_consistency

test_summary
