#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "================================================================"
echo "  Command Naming Format Test (octo: prefix)"
echo "================================================================"
echo ""

FAILED=0
PASSED=0

echo "Test 1: All command files use 'octo:' prefix..."
COMMANDS_DIR="$PROJECT_ROOT/.claude/commands"

if [ ! -d "$COMMANDS_DIR" ]; then
    echo -e "${RED}✗${NC} Commands directory not found: $COMMANDS_DIR"
    exit 1
fi

for cmd_file in "$COMMANDS_DIR"/*.md; do
    if [ ! -f "$cmd_file" ]; then
        continue
    fi
    
    filename=$(basename "$cmd_file")
    cmd_value=$(sed -n '2p' "$cmd_file" | grep -o 'command: .*' | sed 's/command: //' || true)
    
    if [[ -n "$cmd_value" ]] && [[ "$cmd_value" =~ ^octo: ]]; then
        echo -e "${GREEN}✓${NC} $filename: $cmd_value"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $filename: '$cmd_value' does not use octo: prefix"
        ((FAILED++))
    fi
done

echo ""
echo "Test 2: No /octo: references in skill files..."
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

if [ ! -d "$SKILLS_DIR" ]; then
    echo -e "${RED}✗${NC} Skills directory not found: $SKILLS_DIR"
    exit 1
fi

co_refs=$(grep -l "/octo:" "$SKILLS_DIR"/*.md 2>/dev/null || true)

if [ -z "$co_refs" ]; then
    echo -e "${GREEN}✓${NC} No /octo: references found in skill files"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} Found /octo: references in:"
    for f in $co_refs; do
        echo "   - $(basename "$f")"
    done
    ((FAILED++))
fi

echo ""
echo "================================================================"
echo "  Test Results Summary"
echo "================================================================"
echo ""
echo "Total Checks: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
