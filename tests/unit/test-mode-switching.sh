#!/bin/bash
# tests/unit/test-mode-switching.sh
# Tests two-mode system (Dev Work vs Knowledge Work)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$SCRIPT_DIR/../helpers/mock-helpers.sh"

test_suite "Two-Mode System (Dev Work vs Knowledge Work)"

# Setup: Create a temporary config for testing
TEST_CONFIG_DIR="$TEST_TMP_DIR/mode-switching-config"
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
        # Match actual output format: "Switched to 🔧 Dev Mode (forced)"
        if echo "$output" | grep -qi "Dev Mode"; then
            test_pass
        else
            test_fail "Should show Dev Mode message: $output"
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
        # Match actual output format: "Switched to 🎓 Knowledge Mode (forced)"
        if echo "$output" | grep -qi "Knowledge Mode"; then
            test_pass
        else
            test_fail "Should show Knowledge Mode message: $output"
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

    # Match actual output format: "🎓 Knowledge Mode FORCED"
    if echo "$status_output" | grep -qi "Knowledge Mode"; then
        # Switch back to dev mode
        USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" dev >/dev/null 2>&1

        # Verify dev mode persists
        local status_output2=$(USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode status 2>&1)

        # Match actual output: "🔧 Dev Mode FORCED" or "Auto-Detect Mode"
        if echo "$status_output2" | grep -qi "Dev Mode"; then
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

    # Run status command - should default to auto-detect (no knowledge_work_mode field)
    local output=$(USER_CONFIG_FILE="$TEST_CONFIG_FILE" "$PROJECT_ROOT/scripts/orchestrate.sh" knowledge-mode status 2>&1)
    local exit_code=$?

    assert_success "$exit_code" "status should succeed with old config"

    # Without knowledge_work_mode field, defaults to auto-detect mode
    # Match actual output: "Auto-Detect Mode" or "Dev Mode"
    if echo "$output" | grep -qi "Auto-Detect Mode\|Dev Mode"; then
        test_pass
    else
        test_fail "Old config should default to Auto-Detect or Dev mode: $output"
    fi

    cleanup_test_config
}

test_codex_knowledge_mode_recipe() {
    local skill="$PROJECT_ROOT/codex-skills/skill-knowledge-work/SKILL.md"
    local env_dir="$TEST_TMP_DIR/codex-knowledge-mode" action mode recipe output
    local config="$env_dir/.user-config"
    local -a mode_env=(env -i "PATH=$PATH" "HOME=$env_dir"
        "CODEX_SESSION_ID=fixture" "CLAUDE_OCTOPUS_WORKSPACE=$env_dir"
        "OCTO_ROOT=$PROJECT_ROOT" "CODEX_PLUGIN_ROOT=$PROJECT_ROOT"
        "CLAUDE_PLUGIN_ROOT=$PROJECT_ROOT")
    mkdir -p "$env_dir"
    printf '%s\n' 'version: "1.0"' 'resource_tier: "standard"' > "$config"

    while read -r action mode; do
        test_case "Codex knowledge work recipe runs km $action against the installed helper"
        recipe=$(awk -F '`' -v action="$action" '$2 ~ /^bash / && $2 ~ (" km " action "$") {print $2; exit}' "$skill")
        if [[ -z "$recipe" ]]; then
            test_fail "No generated Codex shell recipe for km $action"
            continue
        fi
        if ! output=$(cd "$env_dir" && "${mode_env[@]}" bash -c "$recipe" 2>&1); then
            test_fail "Installed helper failed: $output"
            continue
        fi
        if grep -Fxq 'resource_tier: "standard"' "$config" &&
            [[ "$(grep '^knowledge_work_mode:' "$config")" == "knowledge_work_mode: \"$mode\"" ]] &&
            { [[ "$action" != status ]] || [[ "$output" == *"Auto-Detect Mode"* ]]; }; then
            test_pass
        else
            test_fail "km $action did not preserve and report the expected mode $mode"
        fi
    done <<'MODES'
on true
off false
auto auto
status auto
MODES

    test_case "initializing an empty linked config leaves the backing file untouched"
    local backing_file="$env_dir/empty-config"
    rm "$config"
    touch "$backing_file"
    ln -s "$backing_file" "$config"
    if output=$(cd "$env_dir" && "${mode_env[@]}" bash "$PROJECT_ROOT/scripts/orchestrate.sh" km on 2>&1) &&
        [[ ! -L "$config" && ! -s "$backing_file" ]] &&
        grep -Fxq 'knowledge_work_mode: "true"' "$config"; then
        test_pass
    else
        test_fail "Mode initialization did not safely replace the empty config path: $output"
    fi
}

# Run all tests
test_dev_command_disables_knowledge_mode
test_km_on_enables_knowledge_mode
test_mode_persists_across_sessions
test_backward_compatibility_old_config
test_codex_knowledge_mode_recipe

test_summary
