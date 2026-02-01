#!/usr/bin/env bash
# clean-deployment.sh - Remove development artifacts from plugin/ directory
# This script ensures the deployment folder stays clean and focused

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🧹 Cleaning deployment directory..."
echo ""

# Track what was cleaned
files_removed=0

# Remove runtime workspace
if [ -d ".claude-octopus" ]; then
    rm -rf .claude-octopus/
    echo -e "${GREEN}✓${NC} Removed .claude-octopus/ (runtime workspace)"
    ((files_removed++))
fi

# Remove development tools
if [ -d "component-analyzer" ]; then
    rm -rf component-analyzer/
    echo -e "${GREEN}✓${NC} Removed component-analyzer/ (dev tool)"
    ((files_removed++))
fi

# Remove generated reports
if [ -d "reports" ]; then
    rm -rf reports/
    echo -e "${GREEN}✓${NC} Removed reports/ (generated reports)"
    ((files_removed++))
fi

# Remove source experiments (if it exists and is dev-only)
if [ -d "src" ]; then
    rm -rf src/
    echo -e "${GREEN}✓${NC} Removed src/ (dev experiments)"
    ((files_removed++))
fi

# Remove test artifacts
if ls test-results*.xml 1> /dev/null 2>&1; then
    rm -f test-results*.xml
    echo -e "${GREEN}✓${NC} Removed test-results*.xml (test artifacts)"
    ((files_removed++))
fi

# Remove backup files
backup_count=$(find . -name "*.bak" -type f | wc -l | tr -d ' ')
if [ "$backup_count" -gt 0 ]; then
    find . -name "*.bak" -type f -delete
    echo -e "${GREEN}✓${NC} Removed $backup_count *.bak files"
    ((files_removed++))
fi

# Remove macOS artifacts
if find . -name ".DS_Store" -type f | grep -q .; then
    find . -name ".DS_Store" -type f -delete
    echo -e "${GREEN}✓${NC} Removed .DS_Store files"
    ((files_removed++))
fi

# Remove editor temp files
temp_count=$(find . -name "*~" -type f | wc -l | tr -d ' ')
if [ "$temp_count" -gt 0 ]; then
    find . -name "*~" -type f -delete
    echo -e "${GREEN}✓${NC} Removed $temp_count editor temp files"
    ((files_removed++))
fi

echo ""
if [ $files_removed -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment directory already clean${NC}"
else
    echo -e "${GREEN}✅ Cleaned $files_removed artifact(s)${NC}"
fi

echo ""
echo "Deployment size:"
du -sh .

exit 0
