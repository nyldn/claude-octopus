#!/usr/bin/env bash
# Test command registration and file integrity
# Validates that all command files exist and are registered

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"
COMMANDS_DIR="$PROJECT_ROOT/.claude/commands"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}🧪 Testing command registration${NC}"
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

# Test 1: plugin.json exists
echo "Test 1: Checking plugin.json exists..."
if [[ -f "$PLUGIN_JSON" ]]; then
    pass "plugin.json found"
else
    fail "plugin.json not found" "Expected: $PLUGIN_JSON"
    exit 1
fi

# Test 2: plugin.json has commands array
echo ""
echo "Test 2: Checking commands array in plugin.json..."
if grep -q '"commands"' "$PLUGIN_JSON"; then
    pass "Commands array exists in plugin.json"
else
    fail "Commands array missing" "plugin.json should have commands array"
fi

# Test 3: Extract all registered commands
echo ""
echo "Test 3: Extracting registered commands..."
REGISTERED_COMMANDS=$(grep -o '"\./\.claude/commands/[^"]*"' "$PLUGIN_JSON" || true)
COMMAND_COUNT=$(echo "$REGISTERED_COMMANDS" | grep -c '.md' || echo 0)

if [[ $COMMAND_COUNT -gt 0 ]]; then
    pass "Found $COMMAND_COUNT registered commands"
    info "Registered commands:"
    echo "$REGISTERED_COMMANDS" | sed 's/^/     /'
else
    fail "No commands registered" "plugin.json should register command files"
fi

# Test 4: Verify each registered command file exists
echo ""
echo "Test 4: Checking if all registered command files exist..."
MISSING_FILES=0
while IFS= read -r cmd_path; do
    # Extract filename from path
    cmd_file=$(echo "$cmd_path" | sed 's/.*\/\([^"]*\)".*/\1/')
    full_path="$COMMANDS_DIR/$cmd_file"

    if [[ -f "$full_path" ]]; then
        pass "Command file exists: $cmd_file"
    else
        fail "Missing command file" "File not found: $full_path"
        ((MISSING_FILES++))
    fi
done <<< "$REGISTERED_COMMANDS"

# Test 5: Verify multi.md is registered
echo ""
echo "Test 5: Checking multi.md registration..."
if echo "$REGISTERED_COMMANDS" | grep -q 'multi\.md'; then
    pass "multi.md is registered"
else
    fail "multi.md not registered" "plugin.json should include multi.md"
fi

# Test 6: Verify all .md files in commands dir are registered
echo ""
echo "Test 6: Checking for unregistered command files..."
UNREGISTERED=0
if [[ -d "$COMMANDS_DIR" ]]; then
    for cmd_file in "$COMMANDS_DIR"/*.md; do
        if [[ -f "$cmd_file" ]]; then
            basename=$(basename "$cmd_file")
            if ! echo "$REGISTERED_COMMANDS" | grep -q "$basename"; then
                fail "Unregistered command file" "File exists but not in plugin.json: $basename"
                ((UNREGISTERED++))
            fi
        fi
    done

    if [[ $UNREGISTERED -eq 0 ]]; then
        pass "All command files are registered"
    fi
else
    fail "Commands directory not found" "Expected: $COMMANDS_DIR"
fi

# Test 7: Check each command file has valid frontmatter
echo ""
echo "Test 7: Validating command file frontmatter..."
INVALID_FRONTMATTER=0
if [[ -d "$COMMANDS_DIR" ]]; then
    for cmd_file in "$COMMANDS_DIR"/*.md; do
        if [[ -f "$cmd_file" ]]; then
            basename=$(basename "$cmd_file")

            # Check for opening ---
            if ! head -1 "$cmd_file" | grep -q '^---$'; then
                fail "Invalid frontmatter" "$basename missing opening ---"
                ((INVALID_FRONTMATTER++))
                continue
            fi

            # Check for command: field
            if ! grep -q '^command:' "$cmd_file"; then
                fail "Missing command field" "$basename has no command: field"
                ((INVALID_FRONTMATTER++))
                continue
            fi

            # Check for description: field
            if ! grep -q '^description:' "$cmd_file"; then
                fail "Missing description field" "$basename has no description: field"
                ((INVALID_FRONTMATTER++))
                continue
            fi
        fi
    done

    if [[ $INVALID_FRONTMATTER -eq 0 ]]; then
        pass "All command files have valid frontmatter"
    fi
fi

# Test 8: Verify key commands exist
echo ""
echo "Test 8: Checking for essential commands..."
ESSENTIAL_COMMANDS=("multi.md" "debate.md" "research.md" "review.md" "setup.md")
MISSING_ESSENTIAL=0

for essential in "${ESSENTIAL_COMMANDS[@]}"; do
    if [[ -f "$COMMANDS_DIR/$essential" ]]; then
        pass "Essential command exists: $essential"
    else
        fail "Missing essential command" "Expected: $essential"
        ((MISSING_ESSENTIAL++))
    fi
done

# Test 9: Check for duplicate command names in frontmatter
echo ""
echo "Test 9: Checking for duplicate command names..."
COMMAND_NAMES=()
DUPLICATES=0

if [[ -d "$COMMANDS_DIR" ]]; then
    for cmd_file in "$COMMANDS_DIR"/*.md; do
        if [[ -f "$cmd_file" ]]; then
            cmd_name=$(grep '^command:' "$cmd_file" | sed 's/command:[[:space:]]*//' | tr -d '\r')

            # Check if this command name already exists
            if [[ ${#COMMAND_NAMES[@]} -gt 0 ]] && [[ " ${COMMAND_NAMES[@]} " =~ " ${cmd_name} " ]]; then
                fail "Duplicate command name" "Command '$cmd_name' appears in multiple files"
                ((DUPLICATES++))
            else
                COMMAND_NAMES+=("$cmd_name")
            fi
        fi
    done

    if [[ $DUPLICATES -eq 0 ]]; then
        pass "No duplicate command names found"
        info "Unique commands: ${#COMMAND_NAMES[@]}"
    fi
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
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
