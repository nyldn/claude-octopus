#!/usr/bin/env bash
# Test: Z-index Detection (Issue #15)
# Tests browser-based z-index and stacking context analysis in extract workflow

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")/plugin"
EXTRACT_COMMAND="${PLUGIN_DIR}/.claude/commands/extract.md"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "Testing Z-Index Detection (v7.24.0)"
echo "===================================="
echo ""

# Test 1: Step 4.5 exists in extract.md
echo "Test 1: Z-index step added"
echo "---------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q "Step 4.5" "$EXTRACT_COMMAND" && grep -q "Z-index" "$EXTRACT_COMMAND"; then
    echo -e "${GREEN}✓${NC} Step 4.5: Z-index detection added to extract.md"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Step 4.5 not found in extract.md"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Browser MCP integration
echo ""
echo "Test 2: Browser MCP integration"
echo "--------------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q "mcp__claude_in_chrome__javascript_tool" "$EXTRACT_COMMAND"; then
    echo -e "${GREEN}✓${NC} Browser MCP integration present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Browser MCP integration missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: Z-index detection script
echo ""
echo "Test 3: Z-index detection logic"
echo "--------------------------------"

detection_features=(
    "getComputedStyle"
    "zIndex"
    "position"
    "createsStackingContext"
    "getStackingContextParent"
)

for feature in "${detection_features[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "$feature" "$EXTRACT_COMMAND"; then
        echo -e "${GREEN}✓${NC} Detection feature: $feature"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Detection feature missing: $feature"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 4: Stacking context detection
echo ""
echo "Test 4: Stacking context detection"
echo "-----------------------------------"

stacking_properties=(
    "opacity"
    "transform"
    "filter"
    "perspective"
    "isolation"
)

for prop in "${stacking_properties[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qi "$prop" "$EXTRACT_COMMAND"; then
        echo -e "${GREEN}✓${NC} Stacking property checked: $prop"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Stacking property not checked: $prop"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 5: Conflict detection
echo ""
echo "Test 5: Overlap/conflict detection"
echo "-----------------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q "conflicts" "$EXTRACT_COMMAND" && grep -q "overlaps" "$EXTRACT_COMMAND"; then
    echo -e "${GREEN}✓${NC} Conflict detection implemented"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Conflict detection missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Output sections
echo ""
echo "Test 6: Output sections"
echo "-----------------------"

output_sections=(
    "Layer Hierarchy"
    "Stacking Context Tree"
    "Recommendations"
)

for section in "${output_sections[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qi "$section" "$EXTRACT_COMMAND"; then
        echo -e "${GREEN}✓${NC} Output section: $section"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Output section missing: $section"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 7: Graceful degradation
echo ""
echo "Test 7: Graceful degradation"
echo "-----------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q "checkBrowserMCP" "$EXTRACT_COMMAND"; then
    echo -e "${GREEN}✓${NC} Browser MCP availability check present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Browser MCP availability check missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "skipped" "$EXTRACT_COMMAND" || grep -qi "not available" "$EXTRACT_COMMAND"; then
    echo -e "${GREEN}✓${NC} Graceful degradation messaging present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Graceful degradation messaging missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: Live URL detection
echo ""
echo "Test 8: Live URL vs codebase detection"
echo "---------------------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q "isLiveURL" "$EXTRACT_COMMAND"; then
    echo -e "${GREEN}✓${NC} Live URL detection implemented"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Live URL detection missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 9: Recommendations
echo ""
echo "Test 9: Z-index recommendations"
echo "--------------------------------"

recommendations=(
    "Standardize"
    "scale"
    "Minimize"
    "Avoid Inline"
)

for rec in "${recommendations[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qi "$rec" "$EXTRACT_COMMAND"; then
        echo -e "${GREEN}✓${NC} Recommendation present: $rec"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Recommendation missing: $rec"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 10: Helper functions
echo ""
echo "Test 10: Helper functions"
echo "-------------------------"

helpers=(
    "generateZIndexSection"
    "buildStackingContextTree"
    "checkBrowserMCP"
    "isLiveURL"
)

for helper in "${helpers[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "$helper" "$EXTRACT_COMMAND"; then
        echo -e "${GREEN}✓${NC} Helper function: $helper"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Helper function missing: $helper"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

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
    echo -e "${GREEN}✓ All Phase 4 tests passed!${NC}"
    echo ""
    echo "Phase 4 (Z-Index Detection) is complete:"
    echo "  ✓ Step 4.5 added to extract.md"
    echo "  ✓ Browser MCP integration"
    echo "  ✓ Z-index detection logic"
    echo "  ✓ Stacking context detection"
    echo "  ✓ Conflict detection"
    echo "  ✓ Output sections (hierarchy, tree, recommendations)"
    echo "  ✓ Graceful degradation"
    echo "  ✓ Live URL detection"
    echo "  ✓ Recommendations"
    echo "  ✓ Helper functions"
    exit 0
fi
