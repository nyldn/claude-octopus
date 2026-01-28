#!/usr/bin/env bash
# Test Enforcement Pattern Implementation
# Validates that all orchestrate.sh-based skills use the Validation Gate Pattern

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Skills that must use enforcement pattern
ENFORCE_SKILLS=(
    "$PROJECT_ROOT/.claude/skills/skill-deep-research.md"
    "$PROJECT_ROOT/.claude/skills/flow-discover.md"
    "$PROJECT_ROOT/.claude/skills/flow-define.md"
    "$PROJECT_ROOT/.claude/skills/flow-develop.md"
    "$PROJECT_ROOT/.claude/skills/flow-deliver.md"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}🧪 Testing Enforcement Pattern Implementation${NC}"
echo ""

# Helper functions
pass() {
    ((TEST_COUNT++))
    ((PASS_COUNT++))
    echo -e "${GREEN}✅ PASS${NC}: $1"
}

fail() {
    ((TEST_COUNT++))
    ((FAIL_COUNT++))
    echo -e "${RED}❌ FAIL${NC}: $1"
    echo -e "   ${YELLOW}$2${NC}"
}

info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

# Test 1: Check CLAUDE.md has enforcement best practices
echo "Test 1: Checking CLAUDE.md for enforcement best practices..."
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
if grep -q "Enforcement Best Practices" "$CLAUDE_MD" && \
   grep -q "Validation Gate Pattern" "$CLAUDE_MD"; then
    pass "CLAUDE.md documents Validation Gate Pattern"
else
    fail "CLAUDE.md missing enforcement documentation" \
         "Should have 'Enforcement Best Practices' section with 'Validation Gate Pattern'"
fi

# Test 2: Check each skill file exists
echo ""
echo "Test 2: Checking all enforcement-pattern skills exist..."
all_exist=true
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if [[ ! -f "$skill_file" ]]; then
        all_exist=false
        fail "Skill file missing: $(basename "$skill_file")" "Expected: $skill_file"
    fi
done
if $all_exist; then
    pass "All 5 enforcement-pattern skills exist"
fi

# Test 3: Check frontmatter has execution_mode: enforced
echo ""
echo "Test 3: Checking frontmatter has 'execution_mode: enforced'..."
skills_with_mode=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "^execution_mode: enforced" "$skill_file"; then
        ((skills_with_mode++))
    else
        fail "$(basename "$skill_file") missing 'execution_mode: enforced'" \
             "Should be in frontmatter YAML"
    fi
done
if [[ $skills_with_mode -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have 'execution_mode: enforced'"
fi

# Test 4: Check for pre_execution_contract in frontmatter
echo ""
echo "Test 4: Checking frontmatter has 'pre_execution_contract'..."
skills_with_contract=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "pre_execution_contract:" "$skill_file"; then
        ((skills_with_contract++))
    else
        fail "$(basename "$skill_file") missing 'pre_execution_contract'" \
             "Should list blocking prerequisites in frontmatter"
    fi
done
if [[ $skills_with_contract -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have 'pre_execution_contract'"
fi

# Test 5: Check for validation_gates in frontmatter
echo ""
echo "Test 5: Checking frontmatter has 'validation_gates'..."
skills_with_gates=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "validation_gates:" "$skill_file"; then
        ((skills_with_gates++))
    else
        fail "$(basename "$skill_file") missing 'validation_gates'" \
             "Should list post-execution verifications in frontmatter"
    fi
done
if [[ $skills_with_gates -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have 'validation_gates'"
fi

# Test 6: Check for EXECUTION CONTRACT section
echo ""
echo "Test 6: Checking for 'EXECUTION CONTRACT' section..."
skills_with_contract_section=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)" "$skill_file"; then
        ((skills_with_contract_section++))
    else
        fail "$(basename "$skill_file") missing EXECUTION CONTRACT section" \
             "Should have '## ⚠️ EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)'"
    fi
done
if [[ $skills_with_contract_section -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have EXECUTION CONTRACT section"
fi

# Test 7: Check for blocking step structure (STEP 1, STEP 2, etc.)
echo ""
echo "Test 7: Checking for numbered blocking steps (STEP 1, STEP 2, etc.)..."
skills_with_steps=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "### STEP 1:" "$skill_file" && \
       grep -q "### STEP 2:" "$skill_file"; then
        ((skills_with_steps++))
    else
        fail "$(basename "$skill_file") missing numbered blocking steps" \
             "Should have '### STEP 1:', '### STEP 2:', etc."
    fi
done
if [[ $skills_with_steps -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have numbered blocking steps"
fi

# Test 8: Check for imperative language ("MUST", "PROHIBITED", "CANNOT SKIP")
echo ""
echo "Test 8: Checking for imperative language..."
skills_with_imperatives=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    must_count=$(grep -c "You MUST" "$skill_file" || echo 0)
    prohibited_count=$(grep -c "PROHIBITED from" "$skill_file" || echo 0)
    cannot_skip_count=$(grep -c "CANNOT SKIP\|DO NOT PROCEED" "$skill_file" || echo 0)

    if [[ $must_count -ge 1 && $prohibited_count -ge 1 && $cannot_skip_count -ge 1 ]]; then
        ((skills_with_imperatives++))
    else
        fail "$(basename "$skill_file") weak imperative language" \
             "Should use 'You MUST', 'PROHIBITED from', 'CANNOT SKIP/DO NOT PROCEED'"
    fi
done
if [[ $skills_with_imperatives -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills use strong imperative language"
fi

# Test 9: Check for Bash tool invocation (not just examples)
echo ""
echo "Test 9: Checking for Bash tool invocation of orchestrate.sh..."
skills_with_bash_call=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "\${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" "$skill_file" && \
       grep -q "You MUST execute this command via the Bash tool" "$skill_file"; then
        ((skills_with_bash_call++))
    else
        fail "$(basename "$skill_file") missing explicit Bash tool requirement" \
             "Should require 'You MUST execute this command via the Bash tool'"
    fi
done
if [[ $skills_with_bash_call -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills require Bash tool for orchestrate.sh"
fi

# Test 10: Check for validation gate implementation
echo ""
echo "Test 10: Checking for validation gate implementation..."
skills_with_validation=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -qi "validation gate" "$skill_file" && \
       grep -q "VALIDATION FAILED\|VALIDATION PASSED" "$skill_file"; then
        ((skills_with_validation++))
    else
        fail "$(basename "$skill_file") missing validation gate" \
             "Should have 'Validation Gate' with VALIDATION FAILED/PASSED checks"
    fi
done
if [[ $skills_with_validation -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills implement validation gates"
fi

# Test 11: Check for synthesis file verification
echo ""
echo "Test 11: Checking for synthesis file verification..."
skills_with_file_check=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "find.*results.*-name.*synthesis.*-mmin" "$skill_file" || \
       grep -q "find.*results.*-name.*validation.*-mmin" "$skill_file"; then
        ((skills_with_file_check++))
    else
        fail "$(basename "$skill_file") missing synthesis file check" \
             "Should use 'find' with -mmin to verify recent synthesis files"
    fi
done
if [[ $skills_with_file_check -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills verify synthesis/validation files exist"
fi

# Test 12: Check for prohibition statements
echo ""
echo "Test 12: Checking for explicit prohibition statements..."
skills_with_prohibitions=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    prohibition_count=$(grep -c "❌" "$skill_file" || echo 0)

    if [[ $prohibition_count -ge 3 ]]; then
        ((skills_with_prohibitions++))
    else
        fail "$(basename "$skill_file") missing prohibition statements" \
             "Should have at least 3 ❌ prohibition statements"
    fi
done
if [[ $skills_with_prohibitions -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills have explicit prohibition statements"
fi

# Test 13: Check for task management integration
echo ""
echo "Test 13: Checking for task management integration..."
skills_with_tasks=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "TaskCreate" "$skill_file" && \
       grep -q "TaskUpdate" "$skill_file"; then
        ((skills_with_tasks++))
    else
        fail "$(basename "$skill_file") missing task management" \
             "Should reference TaskCreate and TaskUpdate"
    fi
done
if [[ $skills_with_tasks -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills integrate task management"
fi

# Test 14: Check for error handling without fallback
echo ""
echo "Test 14: Checking for no-fallback error handling..."
skills_with_no_fallback=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "DO NOT substitute" "$skill_file" && \
       grep -q "Report the failure" "$skill_file"; then
        ((skills_with_no_fallback++))
    else
        fail "$(basename "$skill_file") missing no-fallback error handling" \
             "Should say 'DO NOT substitute' and 'Report the failure'"
    fi
done
if [[ $skills_with_no_fallback -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills enforce no-fallback error handling"
fi

# Test 15: Check for provider availability check
echo ""
echo "Test 15: Checking for provider availability check..."
skills_with_provider_check=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "command -v codex" "$skill_file" && \
       grep -q "command -v gemini" "$skill_file"; then
        ((skills_with_provider_check++))
    else
        fail "$(basename "$skill_file") missing provider availability check" \
             "Should check 'command -v codex' and 'command -v gemini'"
    fi
done
if [[ $skills_with_provider_check -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills check provider availability"
fi

# Test 16: Check for visual indicators (🐙 banner)
echo ""
echo "Test 16: Checking for visual indicators requirement..."
skills_with_indicators=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "🐙.*CLAUDE OCTOPUS ACTIVATED" "$skill_file"; then
        ((skills_with_indicators++))
    else
        fail "$(basename "$skill_file") missing visual indicators" \
             "Should require '🐙 **CLAUDE OCTOPUS ACTIVATED**' banner"
    fi
done
if [[ $skills_with_indicators -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills require visual indicators (🐙 banner)"
fi

# Test 17: Check for cost and time estimates
echo ""
echo "Test 17: Checking for cost and time estimates..."
skills_with_estimates=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "💰 Estimated Cost" "$skill_file" && \
       grep -q "⏱️.*Estimated Time" "$skill_file"; then
        ((skills_with_estimates++))
    else
        fail "$(basename "$skill_file") missing cost/time estimates" \
             "Should show '💰 Estimated Cost' and '⏱️ Estimated Time'"
    fi
done
if [[ $skills_with_estimates -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills display cost and time estimates"
fi

# Test 18: Check for attribution footer
echo ""
echo "Test 18: Checking for multi-AI attribution..."
skills_with_attribution=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    if grep -q "Multi-AI.*powered by Claude Octopus" "$skill_file" && \
       grep -q "Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude" "$skill_file"; then
        ((skills_with_attribution++))
    else
        fail "$(basename "$skill_file") missing attribution footer" \
             "Should include 'Multi-AI powered by Claude Octopus' and provider list"
    fi
done
if [[ $skills_with_attribution -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills include multi-AI attribution"
fi

# Test 19: Verify no suggestive language remains
echo ""
echo "Test 19: Checking for removal of suggestive language..."
skills_without_suggestive=0
for skill_file in "${ENFORCE_SKILLS[@]}"; do
    # Check EXECUTION CONTRACT section only (not examples)
    # Look for patterns that suggest Claude has options rather than requirements
    contract_section=$(sed -n '/EXECUTION CONTRACT/,/^#[^#]/p' "$skill_file")

    # Check for phrases that make actions optional for Claude
    if echo "$contract_section" | grep -q "Claude should\|you should execute\|recommended to execute\|consider calling"; then
        suggestive_count=1
    else
        suggestive_count=0
    fi

    if [[ $suggestive_count -eq 0 ]]; then
        ((skills_without_suggestive++))
    else
        fail "$(basename "$skill_file") has suggestive language in EXECUTION CONTRACT" \
             "Should use imperative for Claude's actions: 'Claude should', 'you should execute', 'recommended to execute', 'consider calling'"
    fi
done
if [[ $skills_without_suggestive -eq ${#ENFORCE_SKILLS[@]} ]]; then
    pass "All 5 skills removed suggestive language from contracts"
fi

# Test 20: Check skill-specific validation files
echo ""
echo "Test 20: Checking skill-specific synthesis file patterns..."
specific_checks=0

# skill-deep-research & flow-discover use probe-synthesis
if grep -q "probe-synthesis-\*.md" "$PROJECT_ROOT/.claude/skills/skill-deep-research.md" && \
   grep -q "probe-synthesis-\*.md" "$PROJECT_ROOT/.claude/skills/flow-discover.md"; then
    ((specific_checks++))
fi

# flow-define uses grasp-synthesis
if grep -q "grasp-synthesis-\*.md" "$PROJECT_ROOT/.claude/skills/flow-define.md"; then
    ((specific_checks++))
fi

# flow-develop uses tangle-synthesis
if grep -q "tangle-synthesis-\*.md" "$PROJECT_ROOT/.claude/skills/flow-develop.md"; then
    ((specific_checks++))
fi

# flow-deliver uses ink-validation
if grep -q "ink-validation-\*.md" "$PROJECT_ROOT/.claude/skills/flow-deliver.md"; then
    ((specific_checks++))
fi

if [[ $specific_checks -eq 4 ]]; then
    pass "All skills validate correct synthesis file patterns"
else
    fail "Some skills have wrong synthesis file patterns" \
         "probe→probe-synthesis, define→grasp-synthesis, develop→tangle-synthesis, deliver→ink-validation"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Test Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total tests:  ${BLUE}$TEST_COUNT${NC}"
echo -e "Passed:       ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed:       ${RED}$FAIL_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✅ All enforcement pattern tests passed!${NC}"
    echo ""
    info "All 5 orchestrate.sh skills properly enforce the Validation Gate Pattern"
    exit 0
else
    echo -e "${RED}❌ Some enforcement tests failed${NC}"
    exit 1
fi
