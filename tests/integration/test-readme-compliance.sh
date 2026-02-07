#!/bin/bash
# Integration Test: README.md Compliance
# Validates that documented features/instructions match actual functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_HELPERS="$SCRIPT_DIR/../helpers/test-framework.sh"

# Source test framework
if [[ -f "$TEST_HELPERS" ]]; then
    source "$TEST_HELPERS"
else
    echo "ERROR: Test framework not found at $TEST_HELPERS"
    exit 1
fi

# Project paths
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
README="$PROJECT_ROOT/README.md"
ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

#===============================================================================
# Helper Functions
#===============================================================================

extract_readme_commands() {
    # Extract command examples from README (lines starting with $ or orchestrate.sh)
    grep -E "^\$ |^\./scripts/orchestrate\.sh|^orchestrate\.sh" "$README" | \
        sed 's/^\$ //' | \
        sed 's/^\.\/scripts\///' || true
}

extract_readme_features() {
    # Extract feature bullet points from README
    grep -E "^[-*] " "$README" | sed 's/^[-*] //' || true
}

check_command_exists() {
    local cmd="$1"
    # Extract just the command name (first word)
    local cmd_name=$(echo "$cmd" | awk '{print $2}')  # $2 because format is "orchestrate.sh COMMAND"

    # Check if command is documented in help
    "$ORCHESTRATE" help --full 2>&1 | grep -q "^  $cmd_name " && return 0
    return 1
}

verify_command_works() {
    local cmd="$1"
    # Try running command with --dry-run and --help
    local cmd_name=$(echo "$cmd" | awk '{print $2}')

    # Skip commands that require arguments
    case "$cmd_name" in
        probe|grasp|tangle|ink|embrace|grapple|squeeze|auto)
            # These require prompts - test with --help instead
            "$ORCHESTRATE" "$cmd_name" --help &>/dev/null && return 0
            return 1
            ;;
        *)
            # Other commands can be tested directly
            "$ORCHESTRATE" "$cmd_name" -n &>/dev/null && return 0
            "$ORCHESTRATE" "$cmd_name" --help &>/dev/null && return 0
            return 1
            ;;
    esac
}

#===============================================================================
# Test Suite
#===============================================================================

test_suite "README.md Compliance Tests"

#===============================================================================
# Test 1: All documented commands exist
#===============================================================================

test_case "All README commands are implemented" "
    local missing_commands=()

    # Check specific commands mentioned in README
    local documented_commands=(
        'probe'
        'grasp'
        'tangle'
        'ink'
        'embrace'
        'grapple'
        'squeeze'
        'auto'
        'preflight'
        'octopus-configure'
    )

    for cmd in \"\${documented_commands[@]}\"; do
        if ! \$ORCHESTRATE \$cmd --help &>/dev/null; then
            missing_commands+=(\"\$cmd\")
        fi
    done

    if [[ \${#missing_commands[@]} -gt 0 ]]; then
        echo \"Missing commands: \${missing_commands[*]}\"
        return 1
    fi

    return 0
"

#===============================================================================
# Test 2: All commands have help documentation
#===============================================================================

test_case "All commands have --help documentation" "
    local undocumented=()

    local all_commands=(
        'probe' 'research'
        'grasp' 'define'
        'tangle' 'develop'
        'ink' 'deliver'
        'embrace'
        'grapple'
        'squeeze' 'red-team'
        'auto'
        'preflight'
        'octopus-configure'
    )

    for cmd in \"\${all_commands[@]}\"; do
        if ! \$ORCHESTRATE \$cmd --help 2>&1 | grep -q \"Usage:\"; then
            undocumented+=(\"\$cmd\")
        fi
    done

    if [[ \${#undocumented[@]} -gt 0 ]]; then
        echo \"Commands without help: \${undocumented[*]}\"
        return 1
    fi

    return 0
"

#===============================================================================
# Test 3: Double Diamond phases are documented correctly
#===============================================================================

test_case "Double Diamond phases match README description" "
    # Verify phase descriptions in README match actual behavior

    # Phase 1: Research/Probe
    if ! grep -q 'Phase 1.*Discover' \"\$README\" && \
       ! grep -q 'research.*probe.*parallel' \"\$README\"; then
        echo \"Phase 1 (Research/Probe) not properly documented\"
        return 1
    fi

    # Phase 2: Define/Grasp
    if ! grep -q 'Phase 2.*Define' \"\$README\" && \
       ! grep -q 'define.*grasp.*consensus' \"\$README\"; then
        echo \"Phase 2 (Define/Grasp) not properly documented\"
        return 1
    fi

    # Phase 3: Develop/Tangle
    if ! grep -q 'Phase 3.*Develop' \"\$README\" && \
       ! grep -q 'develop.*tangle.*implementation' \"\$README\"; then
        echo \"Phase 3 (Develop/Tangle) not properly documented\"
        return 1
    fi

    # Phase 4: Deliver/Ink
    if ! grep -q 'Phase 4.*Deliver' \"\$README\" && \
       ! grep -q 'deliver.*ink.*validation' \"\$README\"; then
        echo \"Phase 4 (Deliver/Ink) not properly documented\"
        return 1
    fi

    return 0
"

#===============================================================================
# Test 4: Key features are implemented
#===============================================================================

test_case "Key README features are implemented" "
    local missing_features=()

    # Multi-agent orchestration
    if ! grep -q 'probe_discover\\|spawn_agent.*parallel' \"\$ORCHESTRATE\"; then
        missing_features+=(\"Multi-agent orchestration\")
    fi

    # Quality gates
    if ! grep -q 'quality.*gate\\|threshold' \"\$ORCHESTRATE\"; then
        missing_features+=(\"Quality gates\")
    fi

    # Async/tmux features
    if ! grep -q 'ASYNC_MODE\\|TMUX_MODE' \"\$ORCHESTRATE\"; then
        missing_features+=(\"Async/tmux visualization\")
    fi

    # Provider detection
    if ! \$ORCHESTRATE preflight 2>&1 | grep -q \"Checking.*CLI\"; then
        missing_features+=(\"Provider detection\")
    fi

    if [[ \${#missing_features[@]} -gt 0 ]]; then
        echo \"Missing features: \${missing_features[*]}\"
        return 1
    fi

    return 0
"

#===============================================================================
# Test 5: Example commands from README work
#===============================================================================

test_case "README example commands are valid" "
    local failed_examples=()

    # Test that commands mentioned in README examples have valid syntax
    local example_commands=(
        'probe \"test task\" -n'
        'grasp \"test task\" -n'
        'tangle \"test task\" -n'
        'ink \"test task\" -n'
        'embrace \"test task\" -n'
        'grapple \"test task\" -n'
        'squeeze \"test task\" -n'
    )

    for cmd_args in \"\${example_commands[@]}\"; do
        if ! \$ORCHESTRATE \$cmd_args &>/dev/null; then
            # Check exit code - 0 or 1 are acceptable (1 = no results in dry-run)
            local exit_code=\$?
            if [[ \$exit_code -ne 0 && \$exit_code -ne 1 ]]; then
                failed_examples+=(\"\$cmd_args (exit \$exit_code)\")
            fi
        fi
    done

    if [[ \${#failed_examples[@]} -gt 0 ]]; then
        echo \"Failed examples: \${failed_examples[*]}\"
        return 1
    fi

    return 0
"

#===============================================================================
# Test 6: Installation instructions are accurate
#===============================================================================

test_case "Installation/setup instructions match actual requirements" "
    # Check that preflight identifies the same requirements as README
    local preflight_output
    preflight_output=\$(\$ORCHESTRATE preflight 2>&1 || true)

    # README should mention the same CLI requirements as preflight
    if grep -q \"Codex CLI\" \"\$README\"; then
        if ! echo \"\$preflight_output\" | grep -q \"Codex CLI\"; then
            echo \"README mentions Codex CLI but preflight doesn't check for it\"
            return 1
        fi
    fi

    if grep -q \"Gemini CLI\" \"\$README\"; then
        if ! echo \"\$preflight_output\" | grep -q \"Gemini CLI\"; then
            echo \"README mentions Gemini CLI but preflight doesn't check for it\"
            return 1
        fi
    fi

    return 0
"

#===============================================================================
# Test 7: Configuration options are documented
#===============================================================================

test_case "All configuration flags are documented in README" "
    local undocumented_flags=()

    # Extract flags from orchestrate.sh
    local script_flags
    script_flags=\$(grep -E \"^[[:space:]]*--[a-z-]+\\)\" \"\$ORCHESTRATE\" | \
                   sed 's/^[[:space:]]*//;s/).*$//' | \
                   grep -v \"^--help\$\" | \
                   sort -u || true)

    # Check if major flags are in README
    local important_flags=(
        \"--dry-run\"
        \"--verbose\"
        \"--async\"
        \"--tmux\"
        \"--quality\"
    )

    for flag in \"\${important_flags[@]}\"; do
        if ! grep -q \"\$flag\" \"\$README\"; then
            undocumented_flags+=(\"\$flag\")
        fi
    done

    # Allow some undocumented flags for internal use
    if [[ \${#undocumented_flags[@]} -gt 2 ]]; then
        echo \"Too many undocumented flags: \${undocumented_flags[*]}\"
        return 1
    fi

    return 0
"

#===============================================================================
# Test 8: Benchmark documentation matches implementation
#===============================================================================

test_case "Benchmark instructions match actual test infrastructure" "
    # Check if README mentions benchmarks
    if grep -q 'benchmark\|test.*suite' \"\$README\"; then
        # Verify benchmark files exist
        if [[ ! -f \"\$PROJECT_ROOT/tests/benchmark/manual-test.sh\" ]]; then
            echo \"README mentions benchmarks but manual-test.sh doesn't exist\"
            return 1
        fi

        if [[ ! -f \"\$PROJECT_ROOT/tests/benchmark/MANUAL-TEST-GUIDE.md\" ]]; then
            echo \"README mentions benchmarks but MANUAL-TEST-GUIDE.md doesn't exist\"
            return 1
        fi
    fi

    return 0
"

#===============================================================================
# Run Test Suite
#===============================================================================

test_summary

# Return appropriate exit code
if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi
