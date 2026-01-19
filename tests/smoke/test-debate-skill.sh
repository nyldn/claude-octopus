#!/bin/bash
# tests/smoke/test-debate-skill.sh
# Tests AI Debate Hub integration (wolverin0/claude-skills)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "AI Debate Hub Integration"

test_submodule_exists() {
    test_case "Git submodule .dependencies/claude-skills exists"

    if [[ -f "$PROJECT_ROOT/.gitmodules" ]]; then
        test_pass
    else
        test_fail ".gitmodules not found"
        return 1
    fi
}

test_submodule_initialized() {
    test_case "Submodule is initialized with debate.md skill"

    local skill_file="$PROJECT_ROOT/.dependencies/claude-skills/skills/debate.md"

    if [[ -f "$skill_file" ]]; then
        test_pass
    else
        test_fail "debate.md skill not found at $skill_file"
        echo "  Hint: Run 'git submodule update --init --recursive'"
        return 1
    fi
}

test_integration_skill_exists() {
    test_case "Integration layer skill exists (skill-debate-integration.md)"

    local integration_file="$PROJECT_ROOT/.claude/skills/skill-debate-integration.md"

    if [[ -f "$integration_file" ]]; then
        test_pass
    else
        test_fail "skill-debate-integration.md not found at $integration_file"
        return 1
    fi
}

test_skill_has_frontmatter() {
    test_case "skill-debate-integration.md has YAML frontmatter"

    local integration_file="$PROJECT_ROOT/.claude/skills/skill-debate-integration.md"

    if grep -q "^---$" "$integration_file" && \
       grep -q "^name: skill-debate-integration$" "$integration_file" && \
       grep -q "^description:" "$integration_file"; then
        test_pass
    else
        test_fail "skill-debate-integration.md missing required YAML frontmatter"
        return 1
    fi
}

test_skill_has_attribution() {
    test_case "skill-debate-integration.md includes wolverin0 attribution"

    local integration_file="$PROJECT_ROOT/.claude/skills/skill-debate-integration.md"

    if grep -q "wolverin0" "$integration_file" && \
       grep -q "https://github.com/wolverin0/claude-skills" "$integration_file"; then
        test_pass
    else
        test_fail "Missing attribution to wolverin0"
        return 1
    fi
}

test_plugin_json_includes_skills() {
    test_case "plugin.json includes both debate skills"

    local plugin_file="$PROJECT_ROOT/.claude-plugin/plugin.json"

    if grep -q ".claude/skills/skill-debate.md" "$plugin_file" && \
       grep -q ".claude/skills/skill-debate-integration.md" "$plugin_file"; then
        test_pass
    else
        test_fail "plugin.json missing debate skill references"
        return 1
    fi
}

test_plugin_json_has_dependencies_section() {
    test_case "plugin.json maintains debate skill integration"

    local plugin_file="$PROJECT_ROOT/.claude-plugin/plugin.json"

    # NOTE: Dependencies section was removed in v7.6.3 as it's not supported by Claude Code validator
    # We verify integration by checking that debate skills are included instead
    if grep -q "skill-debate" "$plugin_file"; then
        test_pass
    else
        test_fail "plugin.json missing debate skill integration"
        return 1
    fi
}

test_original_skill_content() {
    test_case "Original debate.md skill contains expected content"

    local skill_file="$PROJECT_ROOT/.dependencies/claude-skills/skills/debate.md"

    if [[ ! -f "$skill_file" ]]; then
        test_skip "Submodule not initialized"
        return 0
    fi

    if grep -q "AI Debate Hub" "$skill_file" && \
       grep -q "Gemini" "$skill_file" && \
       grep -q "Codex" "$skill_file"; then
        test_pass
    else
        test_fail "Original debate.md missing expected content"
        return 1
    fi
}

test_debate_command_routing() {
    test_case "Debate command routing exists in orchestrate.sh"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    if grep -q "debate|deliberate|consensus)" "$orchestrate" && \
       grep -q "wolverin0" "$orchestrate"; then
        test_pass
    else
        test_fail "orchestrate.sh missing debate command routing or attribution"
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
    test_case "CHANGELOG.md documents AI Debate Hub integration"

    local changelog="$PROJECT_ROOT/CHANGELOG.md"

    if grep -q "AI Debate Hub" "$changelog" && \
       grep -q "wolverin0" "$changelog" && \
       grep -q "7.4.0" "$changelog"; then
        test_pass
    else
        test_fail "CHANGELOG.md missing AI Debate Hub integration notes"
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
    # Extract version from marketplace.json plugins array
    local marketplace_version=$(grep -A 3 '"claude-octopus"' "$marketplace_json" | grep '"version"' | sed 's/.*"version": *"\([^"]*\)".*/\1/')

    if [[ "$plugin_version" == "$package_version" ]] && \
       [[ "$package_version" == "$marketplace_version" ]]; then
        test_pass
    else
        test_fail "Version mismatch: plugin=$plugin_version, package=$package_version, marketplace=$marketplace_version"
        return 1
    fi
}

# Run all tests
test_submodule_exists
test_submodule_initialized
test_integration_skill_exists
test_skill_has_frontmatter
test_skill_has_attribution
test_plugin_json_includes_skills
test_plugin_json_has_dependencies_section
test_original_skill_content
test_debate_command_routing
test_readme_attribution
test_changelog_attribution
test_version_consistency

test_summary
