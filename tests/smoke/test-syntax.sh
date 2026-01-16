#!/bin/bash
# tests/smoke/test-syntax.sh
# Validates shell script syntax

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Syntax Validation"

test_orchestrate_syntax() {
    test_case "orchestrate.sh has valid syntax"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    if [[ ! -f "$orchestrate" ]]; then
        test_fail "orchestrate.sh not found"
        return 1
    fi

    # Run bash syntax check
    if bash -n "$orchestrate" 2>/dev/null; then
        test_pass
    else
        test_fail "Syntax error in orchestrate.sh"
        return 1
    fi
}

test_setup_skill_syntax() {
    test_case ".claude/skills/setup.md has valid frontmatter"

    local setup_skill="$PROJECT_ROOT/.claude/skills/setup.md"

    if [[ ! -f "$setup_skill" ]]; then
        test_fail "setup.md not found"
        return 1
    fi

    # Check frontmatter exists
    if head -n 1 "$setup_skill" | grep -q "^---$"; then
        test_pass
    else
        test_fail "No frontmatter found in setup.md"
        return 1
    fi
}

test_helper_scripts_syntax() {
    test_case "All test helper scripts have valid syntax"

    local helpers_dir="$SCRIPT_DIR/../helpers"
    local failed=0

    for script in "$helpers_dir"/*.sh; do
        if [[ -f "$script" ]]; then
            if ! bash -n "$script" 2>/dev/null; then
                echo "  Syntax error in: $(basename "$script")"
                failed=1
            fi
        fi
    done

    if [[ $failed -eq 0 ]]; then
        test_pass
    else
        test_fail "One or more helper scripts have syntax errors"
        return 1
    fi
}

test_executable_permissions() {
    test_case "orchestrate.sh is executable"

    local orchestrate="$PROJECT_ROOT/scripts/orchestrate.sh"

    if [[ -x "$orchestrate" ]]; then
        test_pass
    else
        test_fail "orchestrate.sh is not executable"
        return 1
    fi
}

# Run tests
test_orchestrate_syntax
test_setup_skill_syntax
test_helper_scripts_syntax
test_executable_permissions

test_summary
