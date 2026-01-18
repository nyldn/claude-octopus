#!/bin/bash
# Script: Automatically fix YAML frontmatter in command files
# Changes 'name:' to 'command:' in all command files

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "================================================================"
echo "  Fix Command YAML Frontmatter"
echo "================================================================"
echo ""

COMMANDS_DIR="$PROJECT_ROOT/.claude/commands"
FIXED=0
SKIPPED=0

if [ ! -d "$COMMANDS_DIR" ]; then
    echo -e "${RED}Error: Commands directory not found: $COMMANDS_DIR${NC}"
    exit 1
fi

for cmd_file in "$COMMANDS_DIR"/*.md; do
    if [ ! -f "$cmd_file" ]; then
        continue
    fi

    filename=$(basename "$cmd_file")

    # Check if file uses 'name:' instead of 'command:'
    if grep -q "^name:" "$cmd_file"; then
        echo -e "${YELLOW}Fixing:${NC} $filename"

        # Create backup
        cp "$cmd_file" "$cmd_file.bak"

        # Replace 'name:' with 'command:' (only the first occurrence in frontmatter)
        # Use awk to only replace in the frontmatter section
        awk '
            BEGIN { in_frontmatter=0; frontmatter_count=0; }
            /^---$/ {
                frontmatter_count++;
                if (frontmatter_count == 1) in_frontmatter=1;
                if (frontmatter_count == 2) in_frontmatter=0;
                print;
                next;
            }
            in_frontmatter && /^name:/ {
                sub(/^name:/, "command:");
            }
            { print }
        ' "$cmd_file.bak" > "$cmd_file"

        # Remove backup if successful
        rm "$cmd_file.bak"

        echo -e "${GREEN}✓${NC} Fixed: $filename"
        ((FIXED++))
    else
        echo -e "${GREEN}✓${NC} OK: $filename (already uses 'command:')"
        ((SKIPPED++))
    fi
done

echo ""
echo "================================================================"
echo "  Summary"
echo "================================================================"
echo ""
echo "Files fixed: ${GREEN}${FIXED}${NC}"
echo "Files already correct: ${SKIPPED}"
echo ""

if [ $FIXED -gt 0 ]; then
    echo -e "${GREEN}Frontmatter fixed successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run tests: ./tests/unit/test-command-frontmatter.sh"
    echo "  2. Commit changes if tests pass"
else
    echo -e "${GREEN}All command files already use 'command:' field${NC}"
fi
