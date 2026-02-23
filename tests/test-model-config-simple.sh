#!/usr/bin/env bash
# Test: Model Configuration (Issue #16)
# Simple integration tests that don't require sourcing orchestrate.sh

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${HOME}/.claude-octopus/config/providers.json"
BACKUP_FILE="${CONFIG_FILE}.backup"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "Testing Model Configuration (v7.24.0)"
echo "======================================"
echo ""

# Backup existing config
if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo "✓ Backed up existing config"
fi

# Test 1: Config file structure
echo "Test 1: Configuration file structure"
echo "-------------------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if [[ -f "$CONFIG_FILE" ]]; then
    if jq -e '.version and .providers and .overrides' "$CONFIG_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Config file has correct structure"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Config file structure invalid"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    echo -e "${RED}✗${NC} Config file doesn't exist"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Default provider models
echo ""
echo "Test 2: Default provider models"
echo "--------------------------------"

for provider in codex gemini; do
    TESTS_RUN=$((TESTS_RUN + 1))
    model=$(jq -r ".providers.${provider}.model" "$CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$model" && "$model" != "null" ]]; then
        echo -e "${GREEN}✓${NC} ${provider} has default model: $model"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} ${provider} missing default model"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 3: Command file exists
echo ""
echo "Test 3: Command registration"
echo "-----------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if [[ -f "${PLUGIN_DIR}/.claude/commands/model-config.md" ]]; then
    echo -e "${GREEN}✓${NC} model-config.md command file exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} model-config.md command file missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: Plugin registration
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "model-config.md" "${PLUGIN_DIR}/.claude-plugin/plugin.json" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Command registered in plugin.json"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Command not registered in plugin.json"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: orchestrate.sh has new functions
echo ""
echo "Test 4: orchestrate.sh enhancements"
echo "------------------------------------"

for func in get_agent_model set_provider_model reset_provider_model; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "^${func}()" "${PLUGIN_DIR}/scripts/orchestrate.sh" 2>/dev/null || \
       grep -q "^${func} ()" "${PLUGIN_DIR}/scripts/orchestrate.sh" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Function exists: ${func}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Function missing: ${func}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 6: Check for environment variable support
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "OCTOPUS_CODEX_MODEL" "${PLUGIN_DIR}/scripts/orchestrate.sh"; then
    echo -e "${GREEN}✓${NC} Environment variable support (OCTOPUS_CODEX_MODEL)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Missing environment variable support"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "OCTOPUS_GEMINI_MODEL" "${PLUGIN_DIR}/scripts/orchestrate.sh"; then
    echo -e "${GREEN}✓${NC} Environment variable support (OCTOPUS_GEMINI_MODEL)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Missing environment variable support"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Restore backup
if [[ -f "$BACKUP_FILE" ]]; then
    mv "$BACKUP_FILE" "$CONFIG_FILE"
    echo ""
    echo "✓ Restored config from backup"
fi

# Summary
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo "Total tests: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    exit 1
else
    echo "Failed: 0"
    echo ""
    echo -e "${GREEN}✓ All Phase 1 tests passed!${NC}"
    echo ""
    echo "Phase 1 (Model Configuration) is complete:"
    echo "  ✓ Config file structure"
    echo "  ✓ Default models configured"
    echo "  ✓ Command file created"
    echo "  ✓ Plugin registration"
    echo "  ✓ orchestrate.sh functions"
    echo "  ✓ Environment variable support"
    exit 0
fi
