#!/bin/bash
# tests/integration/test-debate-integration.sh
# Integration tests for AI Debate Hub (wolverin0/claude-skills)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "AI Debate Hub Integration Tests"

test_submodule_structure() {
    test_case "Submodule has complete structure"

    local submodule_dir="$PROJECT_ROOT/.dependencies/claude-skills"

    if [[ ! -d "$submodule_dir" ]]; then
        test_skip "Submodule not initialized"
        return 0
    fi

    # Check for key files
    local has_readme=false
    local has_skill=false
    local has_viewer=false

    [[ -f "$submodule_dir/README.md" ]] && has_readme=true
    [[ -f "$submodule_dir/skills/debate.md" ]] && has_skill=true
    [[ -f "$submodule_dir/viewer.html" ]] && has_viewer=true

    if [[ "$has_readme" == "true" ]] && \
       [[ "$has_skill" == "true" ]] && \
       [[ "$has_viewer" == "true" ]]; then
        test_pass
    else
        test_fail "Submodule incomplete: readme=$has_readme skill=$has_skill viewer=$has_viewer"
        return 1
    fi
}

test_gitmodules_config() {
    test_case ".gitmodules correctly configured"

    local gitmodules="$PROJECT_ROOT/.gitmodules"

    if [[ ! -f "$gitmodules" ]]; then
        test_fail ".gitmodules not found"
        return 1
    fi

    if grep -q 'path = .dependencies/claude-skills' "$gitmodules" && \
       grep -q 'url = https://github.com/wolverin0/claude-skills' "$gitmodules"; then
        test_pass
    else
        test_fail ".gitmodules missing correct configuration"
        return 1
    fi
}

test_integration_skill_completeness() {
    test_case "Integration skill has all required sections"

    local skill_file="$PROJECT_ROOT/.claude/skills/debate-integration.md"

    if [[ ! -f "$skill_file" ]]; then
        test_fail "Integration skill not found"
        return 1
    fi

    # Check for key sections
    local has_attribution=false
    local has_enhancements=false
    local has_quality_gates=false
    local has_cost_tracking=false
    local has_document_export=false

    grep -q "wolverin0" "$skill_file" && has_attribution=true
    grep -q "Claude-Octopus Enhancement" "$skill_file" && has_enhancements=true
    grep -q "Quality Gates" "$skill_file" && has_quality_gates=true
    grep -q "Cost Tracking" "$skill_file" && has_cost_tracking=true
    grep -q "Document Export" "$skill_file" && has_document_export=true

    if [[ "$has_attribution" == "true" ]] && \
       [[ "$has_enhancements" == "true" ]] && \
       [[ "$has_quality_gates" == "true" ]] && \
       [[ "$has_cost_tracking" == "true" ]] && \
       [[ "$has_document_export" == "true" ]]; then
        test_pass
    else
        test_fail "Integration skill missing sections: attribution=$has_attribution enhancements=$has_enhancements quality=$has_quality_gates cost=$has_cost_tracking export=$has_document_export"
        return 1
    fi
}

test_plugin_json_structure() {
    test_case "plugin.json has complete dependencies structure"

    local plugin_json="$PROJECT_ROOT/.claude-plugin/plugin.json"

    # Check for dependencies section with all required fields
    if grep -A 20 '"dependencies"' "$plugin_json" | grep -q '"claude-skills"' && \
       grep -A 20 '"dependencies"' "$plugin_json" | grep -q '"repository"' && \
       grep -A 20 '"dependencies"' "$plugin_json" | grep -q '"author": "wolverin0"' && \
       grep -A 20 '"dependencies"' "$plugin_json" | grep -q '"license": "MIT"' && \
       grep -A 20 '"dependencies"' "$plugin_json" | grep -q '"type": "submodule"' && \
       grep -A 20 '"dependencies"' "$plugin_json" | grep -q '"version": "v4.7"' && \
       grep -A 20 '"dependencies"' "$plugin_json" | grep -q '"integration"'; then
        test_pass
    else
        test_fail "plugin.json missing complete dependencies structure"
        return 1
    fi
}

test_skills_registration_order() {
    test_case "Skills registered in correct order (original before integration)"

    local plugin_json="$PROJECT_ROOT/.claude-plugin/plugin.json"

    # Extract skills array and check order
    local skills=$(grep -A 100 '"skills":' "$plugin_json" | grep -B 1 -A 1 'debate')

    if echo "$skills" | grep -m 1 'debate' | grep -q '.dependencies/claude-skills/skills/debate.md'; then
        test_pass
    else
        test_fail "Skills not in correct order (original should come before integration)"
        return 1
    fi
}

test_readme_complete_attribution() {
    test_case "README has complete attribution section"

    local readme="$PROJECT_ROOT/README.md"

    # Check for all attribution elements
    if grep -q "Attribution & Open Source Collaboration" "$readme" && \
       grep -q "wolverin0" "$readme" && \
       grep -q "https://github.com/wolverin0/claude-skills" "$readme" && \
       grep -q "MIT" "$readme" && \
       grep -q "git submodule" "$readme"; then
        test_pass
    else
        test_fail "README missing complete attribution"
        return 1
    fi
}

test_changelog_complete_release_notes() {
    test_case "CHANGELOG has complete v7.4.0 release notes"

    local changelog="$PROJECT_ROOT/CHANGELOG.md"

    if grep -q "7.4.0" "$changelog" && \
       grep -q "AI Debate Hub Integration" "$changelog" && \
       grep -q "wolverin0" "$changelog" && \
       grep -q "Git Submodule Integration" "$changelog" && \
       grep -q "Hybrid Approach" "$changelog"; then
        test_pass
    else
        test_fail "CHANGELOG missing complete v7.4.0 release notes"
        return 1
    fi
}

test_marketplace_json_updated() {
    test_case "marketplace.json updated to v7.4.0"

    local marketplace="$PROJECT_ROOT/.claude-plugin/marketplace.json"

    if grep -q '"version": "7.4.0"' "$marketplace" && \
       grep -q "AI Debate Hub integration" "$marketplace"; then
        test_pass
    else
        test_fail "marketplace.json not updated for v7.4.0"
        return 1
    fi
}

test_package_json_updated() {
    test_case "package.json updated to v7.4.0"

    local package="$PROJECT_ROOT/package.json"

    if grep -q '"version": "7.4.0"' "$package"; then
        test_pass
    else
        test_fail "package.json not updated to v7.4.0"
        return 1
    fi
}

test_no_duplicate_attributions() {
    test_case "No duplicate wolverin0 attributions in unexpected places"

    # Count attributions (should be in specific files only)
    # Exclude .dev (research docs), tests (test files), and standard exclusions
    local count=$(grep -r "wolverin0" "$PROJECT_ROOT" \
        --include="*.md" \
        --include="*.json" \
        --include="*.sh" \
        --exclude-dir=".dependencies" \
        --exclude-dir="node_modules" \
        --exclude-dir=".git" \
        --exclude-dir=".dev" \
        --exclude-dir="tests" 2>/dev/null | wc -l)

    # Should have multiple attributions (README, CHANGELOG, plugin.json, orchestrate.sh, debate-integration.md)
    # But not hundreds (would indicate duplication bug)
    if (( count > 5 && count < 50 )); then
        test_pass
    else
        test_fail "Unexpected attribution count: $count (expected 5-50)"
        return 1
    fi
}

test_contributing_section_exists() {
    test_case "README has Contributing section with upstream guidance"

    local readme="$PROJECT_ROOT/README.md"

    if grep -q "## Contributing" "$readme" && \
       grep -A 20 "## Contributing" "$readme" | grep -iq "upstream" && \
       grep -A 20 "## Contributing" "$readme" | grep -q "wolverin0/claude-skills"; then
        test_pass
    else
        test_fail "README missing Contributing section or upstream guidance"
        return 1
    fi
}

test_acknowledgments_section_complete() {
    test_case "README Acknowledgments section includes all dependencies"

    local readme="$PROJECT_ROOT/README.md"

    if grep -q "## Acknowledgments" "$readme" && \
       grep -A 10 "## Acknowledgments" "$readme" | grep -q "wolverin0/claude-skills" && \
       grep -A 20 "## Acknowledgments" "$readme" | grep -q "obra/superpowers"; then
        test_pass
    else
        test_fail "README Acknowledgments incomplete"
        return 1
    fi
}

# Run all integration tests
test_submodule_structure
test_gitmodules_config
test_integration_skill_completeness
test_plugin_json_structure
test_skills_registration_order
test_readme_complete_attribution
test_changelog_complete_release_notes
test_marketplace_json_updated
test_package_json_updated
test_no_duplicate_attributions
test_contributing_section_exists
test_acknowledgments_section_complete

test_summary
