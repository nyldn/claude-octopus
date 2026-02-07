#!/bin/bash
# Test: Command YAML frontmatter validation
# Validates that all command files use 'command:' field (not 'name:')

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "================================================================"
echo "  Command YAML Frontmatter Validation Test"
echo "================================================================"
echo ""

FAILED=0
PASSED=0

# Test 1: Check all command files use 'command:' field
echo "Testing: All command files use 'command:' field (not 'name:')..."
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

    # Check if file has YAML frontmatter
    if ! head -1 "$cmd_file" | grep -q "^---$"; then
        echo -e "${RED}✗${NC} $filename: Missing YAML frontmatter"
        ((FAILED++))
        continue
    fi

    # Check if it uses 'command:' field
    if grep -q "^command:" "$cmd_file"; then
        echo -e "${GREEN}✓${NC} $filename uses 'command:' field"
        ((PASSED++))
    else
        # Check if it incorrectly uses 'name:' field
        if grep -q "^name:" "$cmd_file"; then
            echo -e "${RED}✗${NC} $filename uses 'name:' instead of 'command:'"
            echo -e "   ${YELLOW}FIX:${NC} Change 'name:' to 'command:' in YAML frontmatter"
            echo -e "   ${YELLOW}RUN:${NC} ./scripts/fix-command-frontmatter.sh"
            ((FAILED++))
        else
            echo -e "${RED}✗${NC} $filename: No 'command:' or 'name:' field found"
            ((FAILED++))
        fi
    fi
done

echo ""
echo "================================================================"
echo "  Test Results Summary"
echo "================================================================"
echo ""
echo "Total Tests: $((PASSED + FAILED))"
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    echo ""
    echo "To fix YAML frontmatter issues, run:"
    echo "  ./scripts/fix-command-frontmatter.sh"
    exit 1
fi
