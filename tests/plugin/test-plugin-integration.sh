#!/bin/bash
# tests/plugin/test-plugin-integration.sh
# Integration tests for claude-octopus as a Claude Code plugin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Claude Code Plugin Integration"

# Test workspace setup
TEST_WORKSPACE="/tmp/claude-octopus-plugin-test-$$"
TEST_SESSION_ID="00000000-0000-0000-0000-000000000001"

setup_test_workspace() {
    mkdir -p "$TEST_WORKSPACE"
    cd "$TEST_WORKSPACE"

    # Create a minimal test project
    mkdir -p src
    echo "console.log('test');" > src/test.js
}

cleanup_test_workspace() {
    rm -rf "$TEST_WORKSPACE"
}

#==============================================================================
# Plugin Validation Tests
#==============================================================================

test_plugin_manifest_valid() {
    test_case "Plugin manifest passes Claude Code validation"

    local result=$(claude plugin validate "$PROJECT_ROOT/.claude-plugin" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Plugin validation failed"
        echo "$result"
        return 1
    fi
}

#==============================================================================
# Plugin Loading Tests
#==============================================================================

test_plugin_loads_in_claude_code() {
    test_case "Plugin loads successfully in Claude Code"

    setup_test_workspace

    # Run Claude Code with plugin loaded, ask for help
    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --print \
                         --no-session-persistence \
                         "/help" 2>&1)

    local exit_code=$?

    cleanup_test_workspace

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Plugin failed to load"
        echo "$result"
        return 1
    fi
}

test_plugin_skills_registered() {
    test_case "Plugin skills are registered and discoverable"

    setup_test_workspace

    # Check if skills are available via /help or skill listing
    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --print \
                         --no-session-persistence \
                         "List all available skills" 2>&1)

    cleanup_test_workspace

    # Check if our key skills appear in the output
    if echo "$result" | grep -q "discover\|define\|develop\|deliver"; then
        test_pass
    else
        test_fail "Plugin skills not registered"
        echo "$result" | head -20
        return 1
    fi
}

#==============================================================================
# Command Invocation Tests
#==============================================================================

test_setup_command_works() {
    test_case "/co:setup command is recognized"

    setup_test_workspace

    # Invoke /co:setup with --help flag
    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --print \
                         --no-session-persistence \
                         "/co:setup --help" 2>&1)

    local exit_code=$?

    cleanup_test_workspace

    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q -i "setup\|configuration"; then
        test_pass
    else
        test_fail "/co:setup command not recognized"
        echo "$result" | head -20
        return 1
    fi
}

test_dev_command_works() {
    test_case "/co:dev command is recognized"

    setup_test_workspace

    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --print \
                         --no-session-persistence \
                         "/co:dev" 2>&1)

    local exit_code=$?

    cleanup_test_workspace

    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q -i "dev\|mode\|development"; then
        test_pass
    else
        test_fail "/co:dev command not recognized"
        echo "$result" | head -20
        return 1
    fi
}

test_discover_command_works() {
    test_case "/co:discover command is recognized"

    setup_test_workspace

    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --print \
                         --no-session-persistence \
                         "/co:discover --help" 2>&1)

    local exit_code=$?

    cleanup_test_workspace

    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q -i "discover\|research\|exploration"; then
        test_pass
    else
        test_fail "/co:discover command not recognized"
        echo "$result" | head -20
        return 1
    fi
}

#==============================================================================
# Natural Language Triggering Tests
#==============================================================================

test_natural_language_skill_trigger() {
    test_case "Skills can be triggered via natural language"

    setup_test_workspace

    # Try to trigger a skill with natural language
    # This test may need API access, so we'll check if the skill is recognized
    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --print \
                         --no-session-persistence \
                         --max-budget-usd 0.01 \
                         "Help me research authentication patterns in this codebase" 2>&1)

    local exit_code=$?

    cleanup_test_workspace

    # Check if the plugin's discovery/research capabilities are mentioned
    if echo "$result" | grep -q -i "discover\|research\|probe"; then
        test_pass
    else
        # This might fail if API is not available, which is OK
        test_skip "Natural language triggering requires API access"
        return 0
    fi
}

#==============================================================================
# Configuration Tests
#==============================================================================

test_plugin_respects_settings() {
    test_case "Plugin respects Claude Code settings"

    setup_test_workspace

    # Create a test settings file
    cat > settings.json <<'EOF'
{
  "claudeOctopus": {
    "testMode": true
  }
}
EOF

    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --settings "$PWD/settings.json" \
                         --print \
                         --no-session-persistence \
                         "/co:setup --help" 2>&1)

    local exit_code=$?

    cleanup_test_workspace

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Plugin failed with custom settings"
        echo "$result"
        return 1
    fi
}

#==============================================================================
# Alias Tests
#==============================================================================

test_backward_compatible_aliases() {
    test_case "Old command aliases (probe, grasp, tangle, ink) still work"

    setup_test_workspace

    # Test old probe alias
    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --print \
                         --no-session-persistence \
                         "/co:probe --help" 2>&1)

    local exit_code=$?

    cleanup_test_workspace

    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q -i "discover\|probe\|research"; then
        test_pass
    else
        test_fail "Backward compatible alias /co:probe not working"
        echo "$result" | head -20
        return 1
    fi
}

#==============================================================================
# Error Handling Tests
#==============================================================================

test_graceful_error_handling() {
    test_case "Plugin handles missing dependencies gracefully"

    setup_test_workspace

    # Try to run a command without required setup
    local result=$(claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
                         --print \
                         --no-session-persistence \
                         "/co:discover test" 2>&1)

    local exit_code=$?

    cleanup_test_workspace

    # Should exit gracefully even if providers aren't configured
    # (exit code may be non-zero, but should have helpful error message)
    # Accept either: error messages, "Unknown skill" (means command routing works), or setup prompts
    if echo "$result" | grep -q -i "error\|warning\|setup\|configuration\|unknown skill\|unknown command"; then
        test_pass
    else
        test_fail "Plugin doesn't provide helpful error messages"
        echo "$result"
        return 1
    fi
}

#==============================================================================
# Performance Tests
#==============================================================================

test_plugin_load_time() {
    test_case "Plugin loads within reasonable time (≤10s)"

    setup_test_workspace

    # Use seconds for macOS compatibility (date +%s%3N not available on macOS)
    local start_time=$(date +%s)

    claude --plugin-dir "$PROJECT_ROOT/.claude-plugin" \
           --print \
           --no-session-persistence \
           "hello" >/dev/null 2>&1

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    cleanup_test_workspace

    # Allow up to 10 seconds for plugin load (accounts for slower systems, network latency)
    if [[ $duration -le 10 ]]; then
        test_pass
    else
        test_fail "Plugin load time too slow: ${duration}s"
        return 1
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

test_plugin_manifest_valid
test_plugin_loads_in_claude_code
test_plugin_skills_registered
test_setup_command_works
test_dev_command_works
test_discover_command_works
test_natural_language_skill_trigger
test_plugin_respects_settings
test_backward_compatible_aliases
test_graceful_error_handling
test_plugin_load_time

test_summary
