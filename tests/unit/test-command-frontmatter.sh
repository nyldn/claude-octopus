#!/bin/bash
# Test: Command YAML frontmatter validation
# Validates that all command files use 'command:' field (not 'name:')

set -euo pipefail


# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Command YAML frontmatter validation"


echo "================================================================"
echo "  Command YAML Frontmatter Validation Test"
echo "================================================================"
echo ""

FAILED=0
PASSED=0

# Test 1: Check all command files use 'command:' field
echo "Testing: All command files use 'command:' field (not 'name:')..."
COMMANDS_DIR="$PROJECT_ROOT/commands"

if [ ! -d "$COMMANDS_DIR" ]; then
    echo -e "${RED}✗${NC} Commands directory not found: $COMMANDS_DIR"
    exit 1
fi

echo "Testing: Octopus does not shadow Claude Code native /doctor..."
if [ -f "$COMMANDS_DIR/doctor.md" ]; then
    echo -e "${RED}✗${NC} doctor.md must not be registered as an Octopus slash command"
    echo -e "   ${YELLOW}FIX:${NC} Keep Octopus diagnostics in skills/runtime only so native /doctor remains accessible"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓${NC} no doctor.md command file present"
    PASSED=$((PASSED + 1))
fi

if jq -e '.commands[]? | select(. == "./commands/doctor.md")' "$PROJECT_ROOT/.claude-plugin/plugin.json" >/dev/null; then
    echo -e "${RED}✗${NC} plugin.json must not register commands/doctor.md"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓${NC} plugin.json does not register doctor.md"
    PASSED=$((PASSED + 1))
fi

if grep -R "^command:[[:space:]]*doctor$" "$COMMANDS_DIR" >/dev/null 2>&1; then
    echo -e "${RED}✗${NC} no Octopus command may use frontmatter 'command: doctor'"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓${NC} no command frontmatter claims doctor"
    PASSED=$((PASSED + 1))
fi

for cmd_file in "$COMMANDS_DIR"/*.md; do
    if [ ! -f "$cmd_file" ]; then
        continue
    fi

    filename=$(basename "$cmd_file")

    # Check if file has YAML frontmatter
    if ! head -1 "$cmd_file" | grep -q "^---$"; then
        echo -e "${RED}✗${NC} $filename: Missing YAML frontmatter"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Check if it uses 'command:' field
    if grep -q "^command:" "$cmd_file"; then
        echo -e "${GREEN}✓${NC} $filename uses 'command:' field"
        PASSED=$((PASSED + 1))
    else
        # Check if it incorrectly uses 'name:' field
        if grep -q "^name:" "$cmd_file"; then
            echo -e "${RED}✗${NC} $filename uses 'name:' instead of 'command:'"
            echo -e "   ${YELLOW}FIX:${NC} Change 'name:' to 'command:' in YAML frontmatter"
            echo -e "   ${YELLOW}RUN:${NC} ./scripts/fix-command-frontmatter.sh"
            FAILED=$((FAILED + 1))
        else
            echo -e "${RED}✗${NC} $filename: No 'command:' or 'name:' field found"
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo "================================================================"
echo "Passed: $PASSED  Failed: $FAILED"

# v9.44: propagate failures — this test previously always exited 0 because it
# tracks its own counters instead of the shared harness's (bug: doctor.md
# regression in 6e0cb4a shipped despite three red ✗ assertions above).
if [ "$FAILED" -gt 0 ]; then
    echo "RESULT: FAIL ($FAILED check(s) failed)"
    exit 1
fi
test_summary
