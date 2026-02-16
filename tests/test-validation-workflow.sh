#!/usr/bin/env bash
# Test: Validation Workflow (Issue #14)
# Tests skill-validate.md with 5-step workflow and quality scoring

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")/plugin"
VALIDATE_SKILL="${PLUGIN_DIR}/.claude/skills/skill-validate.md"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "Testing Validation Workflow (v7.24.0)"
echo "====================================="
echo ""

# Test 1: Skill file exists
echo "Test 1: Skill file structure"
echo "-----------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if [[ -f "$VALIDATE_SKILL" ]]; then
    echo -e "${GREEN}✓${NC} skill-validate.md exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} skill-validate.md missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Plugin registration
echo ""
echo "Test 2: Plugin registration"
echo "---------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q "skill-validate.md" "${PLUGIN_DIR}/.claude-plugin/plugin.json" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Skill registered in plugin.json"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Skill not registered in plugin.json"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: 5-step workflow documented
echo ""
echo "Test 3: Workflow steps"
echo "----------------------"

workflow_steps=(
    "Step 1.*Scope Analysis"
    "Step 2.*Multi-AI Debate"
    "Step 3.*Quality Scoring"
    "Step 4.*Issue Extraction"
    "Step 5.*Validation Report"
)

for step in "${workflow_steps[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -Pqi "$step" "$VALIDATE_SKILL" 2>/dev/null || grep -Eqi "$step" "$VALIDATE_SKILL" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Workflow step documented: $step"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Workflow step missing: $step"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 4: Quality dimensions (4D scoring)
echo ""
echo "Test 4: Quality dimensions"
echo "--------------------------"

dimensions=(
    "Code Quality"
    "Security"
    "Best Practices"
    "Completeness"
)

for dimension in "${dimensions[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qi "$dimension" "$VALIDATE_SKILL"; then
        echo -e "${GREEN}✓${NC} Dimension present: $dimension"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Dimension missing: $dimension"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 5: Pass threshold
echo ""
echo "Test 5: Pass threshold"
echo "----------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "75" "$VALIDATE_SKILL" && (grep -qi "threshold" "$VALIDATE_SKILL" || grep -qi "pass" "$VALIDATE_SKILL"); then
    echo -e "${GREEN}✓${NC} Pass threshold (75/100) documented"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Pass threshold not documented"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Issue severity levels
echo ""
echo "Test 6: Issue severity levels"
echo "------------------------------"

severity_levels=(
    "Critical"
    "High"
    "Medium"
    "Low"
)

for level in "${severity_levels[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qi "$level" "$VALIDATE_SKILL"; then
        echo -e "${GREEN}✓${NC} Severity level: $level"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Severity level missing: $level"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 7: Visual indicators
echo ""
echo "Test 7: Visual indicators"
echo "-------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -q "🐙" "$VALIDATE_SKILL" && grep -q "🛡️" "$VALIDATE_SKILL"; then
    echo -e "${GREEN}✓${NC} Visual indicators present (🐙 🛡️)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Visual indicators missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: AI provider integration
echo ""
echo "Test 8: AI provider integration"
echo "--------------------------------"

providers=(
    "Codex"
    "Gemini"
    "Claude"
)

for provider in "${providers[@]}"; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qi "$provider" "$VALIDATE_SKILL"; then
        echo -e "${GREEN}✓${NC} Provider integrated: $provider"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Provider missing: $provider"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# Test 9: Execution contract
echo ""
echo "Test 9: Execution enforcement"
echo "------------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "EXECUTION CONTRACT" "$VALIDATE_SKILL"; then
    echo -e "${GREEN}✓${NC} Execution contract present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Execution contract missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 10: Validation gates
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "validation_gates" "$VALIDATE_SKILL" || grep -qi "Validation Gate" "$VALIDATE_SKILL"; then
    echo -e "${GREEN}✓${NC} Validation gates present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Validation gates missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 11: Report generation
echo ""
echo "Test 11: Report generation"
echo "--------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "VALIDATION_REPORT.md" "$VALIDATE_SKILL"; then
    echo -e "${GREEN}✓${NC} Validation report template present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Validation report template missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "ISSUES.md" "$VALIDATE_SKILL"; then
    echo -e "${GREEN}✓${NC} Issues list template present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Issues list template missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 12: AskUserQuestion integration
echo ""
echo "Test 12: Interactive questions"
echo "-------------------------------"
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "AskUserQuestion" "$VALIDATE_SKILL"; then
    echo -e "${GREEN}✓${NC} Interactive questions integrated"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Interactive questions not integrated"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 13: orchestrate.sh execution
TESTS_RUN=$((TESTS_RUN + 1))

if grep -qi "orchestrate.sh" "$VALIDATE_SKILL"; then
    echo -e "${GREEN}✓${NC} orchestrate.sh integration present"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} orchestrate.sh integration missing"
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
    echo -e "${GREEN}✓ All Phase 3 tests passed!${NC}"
    echo ""
    echo "Phase 3 (Validation Workflow) is complete:"
    echo "  ✓ Skill file created"
    echo "  ✓ Plugin registration"
    echo "  ✓ 5-step workflow"
    echo "  ✓ 4D quality scoring"
    echo "  ✓ Pass threshold (75/100)"
    echo "  ✓ Issue severity levels"
    echo "  ✓ Visual indicators"
    echo "  ✓ AI provider integration"
    echo "  ✓ Execution enforcement"
    echo "  ✓ Validation gates"
    echo "  ✓ Report generation"
    echo "  ✓ Interactive questions"
    echo "  ✓ orchestrate.sh integration"
    exit 0
fi
