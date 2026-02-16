#!/usr/bin/env bash
# Test: Smart Router (Issue #13)
# Tests /octo command with intent detection and routing

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")/plugin"
OCTO_COMMAND="${PLUGIN_DIR}/.claude/commands/octo.md"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "Testing Smart Router (v7.24.0)"
echo "=============================="
echo ""

# Test 1: Command file exists
echo "Test 1: Command file structure"
echo "-------------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if [[ -f "$OCTO_COMMAND" ]]; then
    echo -e "${GREEN}✓${NC} octo.md command file exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} octo.md command file missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Plugin registration
echo ""
echo "Test 2: Plugin registration"
echo "---------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q "octo.md" "${PLUGIN_DIR}/.claude-plugin/plugin.json" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Command registered in plugin.json"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Command not registered in plugin.json"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: Intent detection keywords
echo ""
echo "Test 3: Intent detection keywords"
echo "----------------------------------"

intent_keywords=(
    "research:discover"
    "build:develop"
    "validate:validate"
    "debate:debate"
    "lifecycle:embrace"
    "plan:plan"
)

for keyword_pair in "${intent_keywords[@]}"; do
    IFS=':' read -r keyword workflow <<< "$keyword_pair"
    TESTS_RUN=$((TESTS_RUN + 1))

    if grep -qi "$keyword" "$OCTO_COMMAND" && grep -qi "$workflow" "$OCTO_COMMAND"; then
        echo -e "${GREEN}✓${NC} Intent '$keyword' → '$workflow' documented"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Intent '$keyword' → '$workflow' missing"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 4: Confidence scoring
echo ""
echo "Test 4: Confidence scoring"
echo "--------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "confidence" "$OCTO_COMMAND" && grep -qi "threshold" "$OCTO_COMMAND"; then
    echo -e "${GREEN}✓${NC} Confidence scoring documented"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Confidence scoring not documented"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: Routing table
echo ""
echo "Test 5: Routing table"
echo "---------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "routing table" "$OCTO_COMMAND" || grep -qi "routes to" "$OCTO_COMMAND"; then
    echo -e "${GREEN}✓${NC} Routing table documented"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Routing table not documented"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Visual indicators integration
echo ""
echo "Test 6: Visual indicators"
echo "-------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "🐙" "$OCTO_COMMAND" || grep -qi "visual indicator" "$OCTO_COMMAND"; then
    echo -e "${GREEN}✓${NC} Visual indicators documented"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Visual indicators not documented"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: Execution contract
echo ""
echo "Test 7: Execution contract"
echo "--------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "EXECUTION CONTRACT" "$OCTO_COMMAND"; then
    echo -e "${GREEN}✓${NC} Execution contract present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Execution contract missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: Validation gates
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "validation gates" "$OCTO_COMMAND" || grep -qi "✅" "$OCTO_COMMAND"; then
    echo -e "${GREEN}✓${NC} Validation gates present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Validation gates missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 9: Check for all target workflows
echo ""
echo "Test 9: Target workflow coverage"
echo "---------------------------------"

target_workflows=(
    "discover"
    "develop"
    "validate"
    "debate"
    "embrace"
    "plan"
)

for workflow in "${target_workflows[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))

    if grep -qi "/octo:${workflow}" "$OCTO_COMMAND"; then
        echo -e "${GREEN}✓${NC} Routes to /octo:${workflow}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Missing route to /octo:${workflow}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 10: Examples present
echo ""
echo "Test 10: Usage examples"
echo "-----------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "example" "$OCTO_COMMAND" && grep -qi "\`\`\`" "$OCTO_COMMAND"; then
    echo -e "${GREEN}✓${NC} Usage examples present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Usage examples missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
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
    echo -e "${GREEN}✓ All Phase 2 tests passed!${NC}"
    echo ""
    echo "Phase 2 (Smart Router) is complete:"
    echo "  ✓ Command file created"
    echo "  ✓ Plugin registration"
    echo "  ✓ Intent detection keywords"
    echo "  ✓ Confidence scoring"
    echo "  ✓ Routing table"
    echo "  ✓ Visual indicators"
    echo "  ✓ Execution contract"
    echo "  ✓ Validation gates"
    echo "  ✓ Target workflows"
    echo "  ✓ Usage examples"
    exit 0
fi
