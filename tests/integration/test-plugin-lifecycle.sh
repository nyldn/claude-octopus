#!/bin/bash
# tests/integration/test-plugin-lifecycle.sh
# Tests plugin installation, verification, and uninstallation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Plugin Lifecycle"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#==============================================================================
# Setup and Cleanup
#==============================================================================

setup_test_env() {
    # Save original state if plugin is installed
    ORIGINAL_STATE=$(claude plugin list 2>/dev/null | grep -c "claude-octopus" || echo "0")

    # Ensure clean state for testing
    if [[ "$ORIGINAL_STATE" != "0" ]]; then
        echo -e "${YELLOW}  → Uninstalling existing plugin for clean test...${NC}"
        claude plugin uninstall claude-octopus --scope user 2>/dev/null || true
        rm -rf ~/.claude/plugins/cache/nyldn-plugins/claude-octopus 2>/dev/null || true
    fi
}

restore_original_state() {
    if [[ "$ORIGINAL_STATE" != "0" ]]; then
        echo -e "${YELLOW}  → Restoring original plugin state...${NC}"
        claude plugin marketplace add https://github.com/nyldn/claude-octopus 2>/dev/null || true
        claude plugin install claude-octopus@nyldn-plugins --scope user 2>/dev/null || true
    fi
}

#==============================================================================
# Test: Claude CLI Available
#==============================================================================

test_claude_cli_available() {
    test_case "Claude CLI is available"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not found in PATH"
        return 0
    fi

    test_pass
}

#==============================================================================
# Test: Add Marketplace
#==============================================================================

test_add_marketplace() {
    test_case "Add nyldn/claude-octopus marketplace"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not available"
        return 0
    fi

    # Add marketplace
    local output=$(claude plugin marketplace add https://github.com/nyldn/claude-octopus 2>&1)
    local exit_code=$?

    # Check if marketplace was added or already exists
    if [[ $exit_code -eq 0 ]] || echo "$output" | grep -qi "already exists\|already added"; then
        test_pass
    else
        test_fail "Failed to add marketplace: $output"
    fi
}

#==============================================================================
# Test: Install Plugin
#==============================================================================

test_install_plugin() {
    test_case "Install claude-octopus@nyldn-plugins"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not available"
        return 0
    fi

    # Install plugin
    local output=$(claude plugin install claude-octopus@nyldn-plugins --scope user 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        test_fail "Installation failed: $output"
        return 1
    fi

    # Wait briefly for installation to complete
    sleep 2

    test_pass
}

#==============================================================================
# Test: Verify Plugin Installed
#==============================================================================

test_verify_installed() {
    test_case "Verify plugin appears in list"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not available"
        return 0
    fi

    local output=$(claude plugin list 2>&1)

    if echo "$output" | grep -q "claude-octopus"; then
        test_pass
    else
        test_fail "Plugin not found in list: $output"
    fi
}

#==============================================================================
# Test: Verify Plugin Files Exist
#==============================================================================

test_verify_files_exist() {
    test_case "Verify plugin files were installed"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not available"
        return 0
    fi

    # Check for plugin files in cache directory
    local cache_dir="$HOME/.claude/plugins/cache/nyldn-plugins/claude-octopus"

    if [[ ! -d "$cache_dir" ]]; then
        test_fail "Plugin cache directory not found: $cache_dir"
        return 1
    fi

    # Find the version directory (e.g., 4.9.4)
    local version_dir=$(find "$cache_dir" -maxdepth 1 -type d ! -name "claude-octopus" -exec basename {} \; | head -1)

    if [[ -z "$version_dir" ]]; then
        test_fail "No version directory found in $cache_dir"
        return 1
    fi

    local plugin_dir="$cache_dir/$version_dir"

    # Check for critical plugin files
    local required_files=(
        ".claude-plugin/plugin.json"
        ".claude-plugin/marketplace.json"
        "scripts/orchestrate.sh"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "$plugin_dir/$file" ]]; then
            test_fail "Required file missing: $file (looked in $plugin_dir)"
            return 1
        fi
    done

    test_pass
}

#==============================================================================
# Test: Verify Plugin Configuration
#==============================================================================

test_verify_plugin_config() {
    test_case "Verify plugin.json is valid"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not available"
        return 0
    fi

    local cache_dir="$HOME/.claude/plugins/cache/nyldn-plugins/claude-octopus"
    local version_dir=$(find "$cache_dir" -maxdepth 1 -type d ! -name "claude-octopus" -exec basename {} \; | head -1)

    if [[ -z "$version_dir" ]]; then
        test_fail "No version directory found"
        return 1
    fi

    local plugin_json="$cache_dir/$version_dir/.claude-plugin/plugin.json"

    if [[ ! -f "$plugin_json" ]]; then
        test_fail "plugin.json not found at $plugin_json"
        return 1
    fi

    # Verify JSON is valid and contains expected fields
    if ! command -v jq &>/dev/null; then
        test_skip "jq not available for JSON validation"
        return 0
    fi

    local name=$(jq -r '.name' "$plugin_json" 2>/dev/null)
    local skills=$(jq -r '.skills | length' "$plugin_json" 2>/dev/null)

    if [[ "$name" != "octo" ]]; then
        test_fail "Plugin name mismatch: expected 'octo', got '$name'"
        return 1
    fi

    if [[ "$skills" -lt 1 ]]; then
        test_fail "No skills defined in plugin.json"
        return 1
    fi

    test_pass
}

#==============================================================================
# Test: Update Plugin
#==============================================================================

test_update_plugin() {
    test_case "Update plugin to latest version"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not available"
        return 0
    fi

    # Update plugin
    local output=$(claude plugin update claude-octopus --scope user 2>&1)
    local exit_code=$?

    # Update may say "already up to date" which is fine
    if [[ $exit_code -eq 0 ]] || echo "$output" | grep -qi "up to date\|already at latest"; then
        test_pass
    else
        test_fail "Update failed: $output"
    fi
}

#==============================================================================
# Test: Uninstall Plugin
#==============================================================================

test_uninstall_plugin() {
    test_case "Uninstall claude-octopus plugin"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not available"
        return 0
    fi

    # Uninstall plugin
    local output=$(claude plugin uninstall claude-octopus --scope user 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        test_fail "Uninstallation failed: $output"
        return 1
    fi

    # Wait briefly for uninstallation to complete
    sleep 1

    test_pass
}

#==============================================================================
# Test: Verify Plugin Removed
#==============================================================================

test_verify_removed() {
    test_case "Verify plugin no longer in list"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not available"
        return 0
    fi

    local output=$(claude plugin list 2>&1)

    # Plugin should not appear in list (or should show as not installed)
    if echo "$output" | grep -q "claude-octopus.*enabled"; then
        test_fail "Plugin still appears as enabled: $output"
        return 1
    fi

    test_pass
}

#==============================================================================
# Test: Reinstall After Uninstall
#==============================================================================

test_reinstall() {
    test_case "Reinstall plugin after uninstall"

    if ! command -v claude &>/dev/null; then
        test_skip "Claude CLI not available"
        return 0
    fi

    # Reinstall
    local output=$(claude plugin install claude-octopus@nyldn-plugins --scope user 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        test_fail "Reinstallation failed: $output"
        return 1
    fi

    # Wait briefly
    sleep 2

    # Verify it's back
    local list_output=$(claude plugin list 2>&1)
    if echo "$list_output" | grep -q "claude-octopus"; then
        test_pass
    else
        test_fail "Plugin not found after reinstall"
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

main() {
    echo -e "${YELLOW}Setting up test environment...${NC}"
    setup_test_env

    # Run test sequence
    test_claude_cli_available || exit 1
    test_add_marketplace
    test_install_plugin
    test_verify_installed
    test_verify_files_exist
    test_verify_plugin_config
    test_update_plugin
    test_uninstall_plugin
    test_verify_removed
    test_reinstall
    test_uninstall_plugin  # Clean up after test

    echo -e "\n${YELLOW}Restoring original state...${NC}"
    restore_original_state

    test_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
