#!/usr/bin/env bash
# validate-no-hardcoded-paths.sh - Ensure no hardcoded local paths in deployment
# Prevents privacy leaks and environment-specific configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 Checking for hardcoded local paths..."
echo ""

violations=0

# Check for absolute user paths in deployment files (only git-tracked files)
echo "Checking for absolute user paths (/Users/*, /home/*)..."
hardcoded_users=$(git ls-files | grep -E "\.(md|sh|js|json|yaml)$" | \
  xargs grep -n "/Users/[^/]*/\|/home/[^/]*/" 2>/dev/null | \
  grep -v "~/" | \
  grep -v "# Example:" | \
  grep -v "# Note:" | \
  grep -v "Example:" || true)

if [ -n "$hardcoded_users" ]; then
    echo -e "${RED}✗ Found hardcoded user paths:${NC}"
    echo "$hardcoded_users" | head -10
    echo ""
    ((violations++))
else
    echo -e "${GREEN}✓ No hardcoded user paths found${NC}"
fi

# Check for specific developer usernames (only git-tracked files)
echo ""
echo "Checking for developer usernames..."
dev_usernames=$(git ls-files | grep -E "\.(md|sh|js|json)$" | \
  xargs grep -n "/Users/chris\|/home/chris\|/Users/.*/git/" 2>/dev/null || true)

if [ -n "$dev_usernames" ]; then
    echo -e "${RED}✗ Found developer username in paths:${NC}"
    echo "$dev_usernames" | wc -l | xargs echo "  Occurrences:"
    echo ""
    echo "  First 5 occurrences:"
    echo "$dev_usernames" | head -5
    echo ""
    ((violations++))
else
    echo -e "${GREEN}✓ No developer usernames in paths${NC}"
fi

# Check for absolute repository paths (only git-tracked files)
echo ""
echo "Checking for absolute git repository paths..."
git_paths=$(git ls-files | grep -E "\.(md|sh)$" | \
  xargs grep -n "git/claude-octopus\|/claude-octopus/plugin/" 2>/dev/null || true)

if [ -n "$git_paths" ]; then
    echo -e "${RED}✗ Found absolute git repository paths:${NC}"
    echo "$git_paths" | wc -l | xargs echo "  Occurrences:"
    echo ""
    ((violations++))
else
    echo -e "${GREEN}✓ No absolute git repository paths${NC}"
fi

# Check for hardcoded workspace paths (should be relative or ~/...)
echo ""
echo "Checking for hardcoded workspace paths..."
workspace_paths=$(grep -rn "\.claude-octopus" \
  --include="*.sh" --include="*.js" \
  --exclude-dir=.git --exclude-dir=tests \
  . 2>/dev/null | \
  grep -v "~/" | \
  grep -v "\${" | \
  grep -v "# " | \
  grep -v "//" || true)

if [ -n "$workspace_paths" ]; then
    echo -e "${YELLOW}⚠ Found potential hardcoded workspace paths:${NC}"
    echo "$workspace_paths" | head -5
    echo ""
    echo -e "${YELLOW}  (Check if these should use ~/ or variables)${NC}"
else
    echo -e "${GREEN}✓ No hardcoded workspace paths${NC}"
fi

echo ""
echo "======================================"
if [ $violations -eq 0 ]; then
    echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
    echo "No hardcoded local paths found in deployment files"
    exit 0
else
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo "$violations violation(s) found"
    echo ""
    echo "Fix these issues:"
    echo "  1. Replace /Users/username/... with relative paths or ~/"
    echo "  2. Replace absolute git paths with relative paths"
    echo "  3. Use environment variables for dynamic paths"
    echo "  4. Move development docs with paths to .gitignore"
    echo ""
    exit 1
fi
