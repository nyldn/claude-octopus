#!/bin/bash
# tests/unit/test-mode-switching.sh
# Tests two-mode system (Dev Work vs Knowledge Work)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$SCRIPT_DIR/../helpers/mock-helpers.sh"

test_suite "Two-Mode System (Dev Work vs Knowledge Work)"

# Setup: Create a temporary config for testing
TEST_CONFIG_DIR="$HOME/.claude-octopus-test"
TEST_CONFIG_FILE="$TEST_CONFIG_DIR/user-config.yaml"

setup_test_config() {
    mkdir -p "$TEST_CONFIG_DIR"
}

cleanup_test_config() {
    rm -rf "$TEST_CONFIG_DIR"
}

test_dev_command_disables_knowledge_mode() {
    test_case "dev command disables knowledge mode"

    setup_test_config

    # Create config with knowledge mode enabled
    cat > "$TEST_CONFIG_FILE" << 'EOF'
version: "1.1"
created_at: "2024-01-01T00:00:00"
updated_at: "2024-01-01T00:00:00"

intent:
  primary: "general"
  all: [general]

resource_tier: "standard"
knowledge_work_mode: "true"

available_keys:
  openai: false
  gemini: false

settings:
  opus_budget: "balanced"
  default_complexity: 2
  prefer_gemini_for_analysis: false
  max_parallel_agents: 3
EOF

    # Run dev command with test config
    local output=$(USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" dev 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "dev command should succeed"

    # Check that mode was disabled
    local mode_value=$(grep "^knowledge_work_mode:" "$TEST_CONFIG_FILE" | sed 's/.*: *//' | tr -d '"')

    if [[ "$mode_value" == "false" ]]; then
        if echo "$output" | grep -qi "dev.*work.*mode\|development.*mode"; then
            test_pass
        else
            test_fail "Should show Dev Work mode message: $output"
        fi
    else
        test_fail "Config should have knowledge_work_mode: false, got: $mode_value"
    fi

    cleanup_test_config
}

test_km_on_enables_knowledge_mode() {
    test_case "km on command enables knowledge mode"

    setup_test_config

    # Create config with knowledge mode disabled
    cat > "$TEST_CONFIG_FILE" << 'EOF'
version: "1.1"
created_at: "2024-01-01T00:00:00"
updated_at: "2024-01-01T00:00:00"

intent:
  primary: "general"
  all: [general]

resource_tier: "standard"
knowledge_work_mode: "false"

available_keys:
  openai: false
  gemini: false

settings:
  opus_budget: "balanced"
  default_complexity: 2
  prefer_gemini_for_analysis: false
  max_parallel_agents: 3
EOF

    # Run km on command with test config
    local output=$(USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode on 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "km on command should succeed"

    # Check that mode was enabled
    local mode_value=$(grep "^knowledge_work_mode:" "$TEST_CONFIG_FILE" | sed 's/.*: *//' | tr -d '"')

    if [[ "$mode_value" == "true" ]]; then
        if echo "$output" | grep -qi "knowledge.*work.*mode"; then
            test_pass
        else
            test_fail "Should show Knowledge Work mode message: $output"
        fi
    else
        test_fail "Config should have knowledge_work_mode: true, got: $mode_value"
    fi

    cleanup_test_config
}

test_mode_persists_across_sessions() {
    test_case "mode setting persists across sessions"

    setup_test_config

    # Create initial config with dev mode
    cat > "$TEST_CONFIG_FILE" << 'EOF'
version: "1.1"
created_at: "2024-01-01T00:00:00"
updated_at: "2024-01-01T00:00:00"

intent:
  primary: "general"
  all: [general]

resource_tier: "standard"
knowledge_work_mode: "false"

available_keys:
  openai: false
  gemini: false

settings:
  opus_budget: "balanced"
  default_complexity: 2
  prefer_gemini_for_analysis: false
  max_parallel_agents: 3
EOF

    # Switch to knowledge mode
    USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode on >/dev/null 2>&1

    # Verify persistence by checking status
    local status_output=$(USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode status 2>&1)

    if echo "$status_output" | grep -qi "knowledge.*work.*mode.*enabled"; then
        # Switch back to dev mode
        USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" dev >/dev/null 2>&1

        # Verify dev mode persists
        local status_output2=$(USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode status 2>&1)

        if echo "$status_output2" | grep -qi "dev.*work.*mode.*active\|development.*mode.*active"; then
            test_pass
        else
            test_fail "Dev mode should persist: $status_output2"
        fi
    else
        test_fail "Knowledge mode should persist: $status_output"
    fi

    cleanup_test_config
}

test_backward_compatibility_old_config() {
    test_case "backward compatibility with configs missing knowledge_work_mode"

    setup_test_config

    # Create old config without knowledge_work_mode field
    cat > "$TEST_CONFIG_FILE" << 'EOF'
version: "1.0"
created_at: "2024-01-01T00:00:00"
updated_at: "2024-01-01T00:00:00"

intent:
  primary: "general"
  all: [general]

resource_tier: "standard"

available_keys:
  openai: false
  gemini: false

settings:
  opus_budget: "balanced"
  default_complexity: 2
  prefer_gemini_for_analysis: false
  max_parallel_agents: 3
EOF

    # Run status command - should default to dev mode
    local output=$(USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode status 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "status should succeed with old config"

    # Should show dev mode as default
    if echo "$output" | grep -qi "dev.*work.*mode\|development.*mode"; then
        test_pass
    else
        test_fail "Old config should default to Dev mode: $output"
    fi

    cleanup_test_config
}

# Run all tests
test_dev_command_disables_knowledge_mode
test_km_on_enables_knowledge_mode
test_mode_persists_across_sessions
test_backward_compatibility_old_config

test_summary
