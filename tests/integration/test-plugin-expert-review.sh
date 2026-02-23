#!/bin/bash
# tests/integration/test-plugin-expert-review.sh
# Expert review of claude-octopus as a Claude Code plugin
# Reviews: plugin structure, skills quality, commands, hooks, marketplace readiness

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Import test framework
source "$SCRIPT_DIR/../helpers/test-framework.sh"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

#==============================================================================
# Helper Functions
#==============================================================================

print_test_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

assert_file_exists() {
    local file="$1"
    local description="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ -f "$PROJECT_ROOT/$file" ]]; then
        echo "  ✓ $description"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo "  ✗ $description (missing: $file)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

assert_dir_exists_custom() {
    local dir="$1"
    local description="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ -d "$PROJECT_ROOT/$dir" ]]; then
        echo "  ✓ $description"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo "  ✗ $description (missing: $dir)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ ! -f "$PROJECT_ROOT/$file" ]]; then
        echo "  ✗ $description (file missing: $file)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    if grep -q "$pattern" "$PROJECT_ROOT/$file"; then
        echo "  ✓ $description"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo "  ✗ $description (pattern not found: $pattern)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

assert_valid_json() {
    local file="$1"
    local description="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ ! -f "$PROJECT_ROOT/$file" ]]; then
        echo "  ✗ $description (file missing: $file)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    if python3 -c "import json; json.load(open('$PROJECT_ROOT/$file'))" 2>/dev/null; then
        echo "  ✓ $description"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo "  ✗ $description (invalid JSON)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

assert_gitignored() {
    local pattern="$1"
    local description="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if grep -q "^$pattern" "$PROJECT_ROOT/.gitignore"; then
        echo "  ✓ $description"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo "  ✗ $description (pattern not in .gitignore: $pattern)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

#==============================================================================
# Plugin Structure Tests
#==============================================================================

test_plugin_metadata() {
    print_test_header "Plugin Metadata Files"

    assert_file_exists ".claude-plugin/plugin.json" "plugin.json exists"
    assert_valid_json ".claude-plugin/plugin.json" "plugin.json is valid JSON"
    assert_file_contains ".claude-plugin/plugin.json" '"version"' "plugin.json has version field"
    assert_file_contains ".claude-plugin/plugin.json" '"name".*octo' "plugin.json has correct name"
    assert_file_contains ".claude-plugin/plugin.json" '"skills"' "plugin.json declares skills"
    assert_file_contains ".claude-plugin/plugin.json" '"commands"' "plugin.json declares commands"

    assert_file_exists ".claude-plugin/marketplace.json" "marketplace.json exists"
    assert_valid_json ".claude-plugin/marketplace.json" "marketplace.json is valid JSON"

    assert_file_exists ".claude-plugin/hooks.json" "hooks.json exists"
    assert_valid_json ".claude-plugin/hooks.json" "hooks.json is valid JSON"
}

test_essential_documentation() {
    print_test_header "Essential Documentation"

    assert_file_exists "README.md" "README.md exists"
    assert_file_exists "LICENSE" "LICENSE exists"
    assert_file_exists "CHANGELOG.md" "CHANGELOG.md exists"
    assert_file_exists "SECURITY.md" "SECURITY.md exists"

    # README should mention Claude Code
    assert_file_contains "README.md" "Claude Code\|claude-code" "README mentions Claude Code"

    # README should have installation instructions
    assert_file_contains "README.md" "install\|Installation" "README has installation section"
}

test_skills_structure() {
    print_test_header "Skills Structure"

    # Check that skills directory exists
    assert_dir_exists_custom ".claude/skills" "skills directory exists"

    # Verify key skills exist (from plugin.json)
    assert_file_exists ".claude/skills/flow-discover.md" "flow-discover skill exists"
    assert_file_exists ".claude/skills/flow-define.md" "flow-define skill exists"

    # Check that skills have proper frontmatter structure
    local skill_file="$PROJECT_ROOT/.claude/skills/flow-discover.md"
    if [[ -f "$skill_file" ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        if head -1 "$skill_file" | grep -q "^---$"; then
            echo "  ✓ Skills use YAML frontmatter"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "  ✗ Skills should use YAML frontmatter (---)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    fi
}

test_commands_structure() {
    print_test_header "Commands Structure"

    # Check that commands directory exists
    assert_dir_exists_custom ".claude/commands" "commands directory exists"

    # Verify key commands exist
    assert_file_exists ".claude/commands/setup.md" "setup command exists"
    assert_file_exists ".claude/commands/debate.md" "debate command exists"
}

test_gitignore_best_practices() {
    print_test_header "Git Ignore Best Practices"

    # Development artifacts should be gitignored
    assert_gitignored ".dev/" "Development directory (.dev/) is gitignored"
    assert_gitignored "test-results\*.xml" "Test results are gitignored"
    assert_gitignored "coverage-report" "Coverage reports are gitignored"
    assert_gitignored "\.DS_Store" "macOS .DS_Store is gitignored"
    assert_gitignored "tests/tmp/" "Test temp files are gitignored"
    assert_gitignored "\*.log" "Log files are gitignored"

    # Temporary and runtime files
    assert_gitignored "tmp/" "tmp/ directory is gitignored"
    assert_gitignored "temp/" "temp/ directory is gitignored"

    # Results directory (workspace artifacts)
    assert_gitignored "results/" "results/ directory is gitignored"
}

test_root_directory_cleanliness() {
    print_test_header "Root Directory Organization"

    # Check for files that shouldn't be committed
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ ! -f "$PROJECT_ROOT/.DS_Store" ]]; then
        echo "  ✓ No .DS_Store in root"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  ⚠ .DS_Store found in root (should be removed)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Check that coverage reports are not committed (they're generated)
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if git ls-files --error-unmatch "$PROJECT_ROOT/coverage-report.html" &>/dev/null; then
        echo "  ⚠ coverage-report.html is tracked by git (should be gitignored)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    else
        echo "  ✓ Coverage reports not tracked by git"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
}

test_version_consistency() {
    print_test_header "Version Consistency"

    # Extract versions from different files
    local plugin_version=$(grep -o '"version".*"[0-9.]*"' "$PROJECT_ROOT/.claude-plugin/plugin.json" | grep -o '[0-9.]*' | head -1)
    local package_version=$(grep -o '"version".*"[0-9.]*"' "$PROJECT_ROOT/package.json" | grep -o '[0-9.]*' | head -1)

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ "$plugin_version" == "$package_version" ]]; then
        echo "  ✓ plugin.json and package.json versions match ($plugin_version)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  ✗ Version mismatch: plugin.json=$plugin_version, package.json=$package_version"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Check if CHANGELOG mentions the current version
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if grep -q "$plugin_version" "$PROJECT_ROOT/CHANGELOG.md"; then
        echo "  ✓ CHANGELOG.md mentions current version ($plugin_version)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  ✗ CHANGELOG.md doesn't mention current version ($plugin_version)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

test_skill_quality() {
    print_test_header "Skill Quality Checks"

    # Check that skills are properly documented
    local skill_count=0
    local skills_with_description=0

    for skill_file in "$PROJECT_ROOT/.claude/skills"/*.md; do
        [[ -f "$skill_file" ]] || continue
        skill_count=$((skill_count + 1))

        # Check for description or documentation section
        if grep -qi "description:\|## \|### " "$skill_file"; then
            skills_with_description=$((skills_with_description + 1))
        fi
    done

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ $skills_with_description -eq $skill_count ]]; then
        echo "  ✓ All $skill_count skills have documentation"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  ⚠ $((skill_count - skills_with_description)) of $skill_count skills lack documentation"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

test_plugin_json_schema() {
    print_test_header "Plugin.json Schema Validation"

    # Check required fields (using relative path from PROJECT_ROOT)
    assert_file_contains ".claude-plugin/plugin.json" '"name"' "plugin.json has 'name' field"
    assert_file_contains ".claude-plugin/plugin.json" '"version"' "plugin.json has 'version' field"
    assert_file_contains ".claude-plugin/plugin.json" '"description"' "plugin.json has 'description' field"
    assert_file_contains ".claude-plugin/plugin.json" '"author"' "plugin.json has 'author' field"
    assert_file_contains ".claude-plugin/plugin.json" '"repository"' "plugin.json has 'repository' field"
    assert_file_contains ".claude-plugin/plugin.json" '"keywords"' "plugin.json has 'keywords' field"

    # Check that skills array is not empty
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local skills_count=$(grep -o '\.claude/skills/[^"]*\.md' "$PROJECT_ROOT/.claude-plugin/plugin.json" | wc -l | tr -d ' ')
    if [[ $skills_count -gt 0 ]]; then
        echo "  ✓ plugin.json declares $skills_count skills"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  ✗ plugin.json has no skills declared"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

test_marketplace_readiness() {
    print_test_header "Marketplace Readiness"

    # Check marketplace.json has required fields (using relative path)
    # Marketplace.json can have either registry format or direct plugin format
    assert_file_contains ".claude-plugin/marketplace.json" '"name"' "marketplace.json has name field"
    assert_file_contains ".claude-plugin/marketplace.json" '"description"' "marketplace.json has description field"
    assert_file_contains ".claude-plugin/marketplace.json" '"plugins"\|"keywords"' "marketplace.json has plugins array or keywords"

    # Check for assets
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ -d "$PROJECT_ROOT/assets" ]]; then
        echo "  ✓ assets/ directory exists"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  ⚠ assets/ directory missing (recommended for marketplace)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

test_security_considerations() {
    print_test_header "Security Considerations"

    # Check that no hardcoded secrets are in git (look for actual secret values, not variable names)
    # Pattern: looks for "API_KEY=" or "SECRET=" followed by actual values (not just variable references)
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if git ls-files | xargs grep -E "(API_KEY|SECRET|PASSWORD)\s*=\s*['\"][^'\"]{20,}" 2>/dev/null | grep -v "\.md$\|test" | grep -q .; then
        echo "  ⚠ Potential hardcoded secrets found in tracked files"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    else
        echo "  ✓ No hardcoded secrets in tracked files"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi

    # Check that .env is gitignored
    assert_gitignored "\.env" ".env files are gitignored"
}

#==============================================================================
# Main Test Execution
#==============================================================================

main() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Claude Code Plugin Expert Review${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "Reviewing: claude-octopus v7.1.0"
    echo ""

    # Run all test suites
    test_plugin_metadata
    test_essential_documentation
    test_skills_structure
    test_commands_structure
    test_gitignore_best_practices
    test_root_directory_cleanliness
    test_version_consistency
    test_skill_quality
    test_plugin_json_schema
    test_marketplace_readiness
    test_security_considerations

    # Print summary
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Expert Review Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "Total checks: $TOTAL_TESTS"
    echo -e "${GREEN}✓ Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}✗ Failed: $FAILED_TESTS${NC}"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo "🎉 Plugin structure meets Claude Code best practices!"
        return 0
    else
        echo "⚠️  Plugin has $FAILED_TESTS issues to address"
        return 1
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
