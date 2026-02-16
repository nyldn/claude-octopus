#!/usr/bin/env bash
# Test: Model Configuration (Issue #16)
# Tests 4-tier precedence: env vars > overrides > config > defaults

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")/plugin"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"
CONFIG_FILE="${HOME}/.claude-octopus/config/providers.json"
BACKUP_FILE="${CONFIG_FILE}.backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Backup existing config
backup_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo "Backed up existing config to $BACKUP_FILE"
    fi
}

# Restore config
restore_config() {
    if [[ -f "$BACKUP_FILE" ]]; then
        mv "$BACKUP_FILE" "$CONFIG_FILE"
        echo "Restored config from backup"
    elif [[ -f "$CONFIG_FILE" ]]; then
        rm "$CONFIG_FILE"
        echo "Removed test config"
    fi
}

# Source orchestrate.sh functions
source "$ORCHESTRATE_SH"

# Test assertion
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: $expected"
        echo "  Got: $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Setup
echo "Setting up test environment..."
backup_config

# Clean slate
unset OCTOPUS_CODEX_MODEL
unset OCTOPUS_GEMINI_MODEL
rm -f "$CONFIG_FILE"

echo ""
echo "Running Model Configuration Tests..."
echo "===================================="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 1: Priority 4 - Hard-coded defaults (no config file)
# ══════════════════════════════════════════════════════════════════════════════
echo "Test Group 1: Hard-coded Defaults"
echo "----------------------------------"

result=$(get_agent_model "codex")
assert_equals "gpt-5.1-codex-max" "$result" "Codex default model"

result=$(get_agent_model "gemini")
assert_equals "gemini-3-pro-preview" "$result" "Gemini default model"

result=$(get_agent_model "claude")
assert_equals "claude-sonnet-4.5" "$result" "Claude default model"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 2: Priority 3 - Config file defaults
# ══════════════════════════════════════════════════════════════════════════════
echo "Test Group 2: Config File Defaults"
echo "-----------------------------------"

# Create config with custom defaults
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "1.0",
  "providers": {
    "codex": {"model": "claude-opus-4-5", "fallback": "claude-sonnet-4-5"},
    "gemini": {"model": "gemini-2.0-pro-exp", "fallback": "gemini-2.0-flash-exp"}
  },
  "overrides": {}
}
EOF

result=$(get_agent_model "codex")
assert_equals "claude-opus-4-5" "$result" "Codex config file model"

result=$(get_agent_model "gemini")
assert_equals "gemini-2.0-pro-exp" "$result" "Gemini config file model"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 3: Priority 2 - Config file overrides
# ══════════════════════════════════════════════════════════════════════════════
echo "Test Group 3: Config File Overrides"
echo "------------------------------------"

# Add overrides to config
jq '.overrides.codex = "gpt-5.2-codex"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
jq '.overrides.gemini = "gemini-3-flash-preview"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

result=$(get_agent_model "codex")
assert_equals "gpt-5.2-codex" "$result" "Codex override model"

result=$(get_agent_model "gemini")
assert_equals "gemini-3-flash-preview" "$result" "Gemini override model"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 4: Priority 1 - Environment variables (highest)
# ══════════════════════════════════════════════════════════════════════════════
echo "Test Group 4: Environment Variables (Highest Priority)"
echo "-------------------------------------------------------"

export OCTOPUS_CODEX_MODEL="claude-sonnet-4-5"
export OCTOPUS_GEMINI_MODEL="gemini-2.0-flash-thinking-exp-01-21"

result=$(get_agent_model "codex")
assert_equals "claude-sonnet-4-5" "$result" "Codex env var model (overrides config)"

result=$(get_agent_model "gemini")
assert_equals "gemini-2.0-flash-thinking-exp-01-21" "$result" "Gemini env var model (overrides config)"

unset OCTOPUS_CODEX_MODEL
unset OCTOPUS_GEMINI_MODEL

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 5: set_provider_model function
# ══════════════════════════════════════════════════════════════════════════════
echo "Test Group 5: set_provider_model Function"
echo "------------------------------------------"

# Reset config
rm -f "$CONFIG_FILE"

# Set codex model
set_provider_model "codex" "claude-opus-4-5" > /dev/null 2>&1
result=$(get_agent_model "codex")
assert_equals "claude-opus-4-5" "$result" "Set codex model via function"

# Set gemini model
set_provider_model "gemini" "gemini-2.0-pro-exp" > /dev/null 2>&1
result=$(get_agent_model "gemini")
assert_equals "gemini-2.0-pro-exp" "$result" "Set gemini model via function"

# Set session override
set_provider_model "codex" "gpt-5.2" "--session" > /dev/null 2>&1
result=$(get_agent_model "codex")
assert_equals "gpt-5.2" "$result" "Set codex session override"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 6: reset_provider_model function
# ══════════════════════════════════════════════════════════════════════════════
echo "Test Group 6: reset_provider_model Function"
echo "--------------------------------------------"

# Reset specific override
reset_provider_model "codex" > /dev/null 2>&1
result=$(get_agent_model "codex")
assert_equals "claude-opus-4-5" "$result" "Reset codex override (falls back to config default)"

# Add more overrides
set_provider_model "codex" "test-model-1" "--session" > /dev/null 2>&1
set_provider_model "gemini" "test-model-2" "--session" > /dev/null 2>&1

# Reset all
reset_provider_model "all" > /dev/null 2>&1
result_codex=$(get_agent_model "codex")
result_gemini=$(get_agent_model "gemini")
assert_equals "claude-opus-4-5" "$result_codex" "Reset all - codex back to config default"
assert_equals "gemini-2.0-pro-exp" "$result_gemini" "Reset all - gemini back to config default"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Test 7: Error handling
# ══════════════════════════════════════════════════════════════════════════════
echo "Test Group 7: Error Handling"
echo "-----------------------------"

# Invalid provider
if set_provider_model "invalid" "model" 2>/dev/null; then
    echo -e "${RED}✗${NC} Should reject invalid provider"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC} Rejects invalid provider"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Empty model
if set_provider_model "codex" "" 2>/dev/null; then
    echo -e "${RED}✗${NC} Should reject empty model"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}✓${NC} Rejects empty model"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Cleanup and Summary
# ══════════════════════════════════════════════════════════════════════════════
restore_config

echo "===================================="
echo "Test Summary"
echo "===================================="
echo "Total tests: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
else
    echo "Failed: 0"
fi
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
