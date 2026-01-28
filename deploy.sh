#!/usr/bin/env bash
# Claude Octopus - Deployment Validation Script
# Ensures repository is clean and ready for public deployment before pushing

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}║        Claude Octopus - Deployment Validation            ║${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNINGS=0

pass() {
    ((CHECKS_PASSED++))
    echo -e "${GREEN}✅ PASS${NC}: $1"
}

fail() {
    ((CHECKS_FAILED++))
    echo -e "${RED}❌ FAIL${NC}: $1"
    [ -n "${2:-}" ] && echo -e "   ${YELLOW}→ $2${NC}"
}

warn() {
    ((CHECKS_WARNINGS++))
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    [ -n "${2:-}" ] && echo -e "   → $2"
}

info() {
    echo -e "${BLUE}ℹ️${NC}  $1"
}

# Check 1: Git working tree
echo "Check 1: Git Working Tree Status"
if git diff-index --quiet HEAD --; then
    pass "Working tree is clean"
else
    fail "Uncommitted changes detected" "Commit or stash changes before deploying"
fi
echo ""

# Check 2: Development artifacts
echo "Check 2: Development Workspace Isolation"
if [ -d "dev-workspace" ]; then
    if git check-ignore dev-workspace/ >/dev/null 2>&1; then
        pass "dev-workspace/ is properly gitignored"
    else
        fail "dev-workspace/ is NOT gitignored" "Add to .gitignore"
    fi
else
    warn "dev-workspace/ directory doesn't exist" "Optional: Create for development artifacts"
fi

# Check for legacy .dev directory
if [ -d ".dev" ]; then
    if git check-ignore .dev/ >/dev/null 2>&1; then
        warn ".dev/ directory still exists" "Consider migrating to dev-workspace/"
    else
        fail ".dev/ is NOT gitignored" "This should not be committed"
    fi
fi
echo ""

# Check 3: Sensitive files
echo "Check 3: Sensitive Data Protection"
sensitive_files=$(git ls-files | grep -E "\.env$|secret|credential|\.key$|password" || true)
if [ -z "$sensitive_files" ]; then
    pass "No sensitive files tracked in git"
else
    fail "Sensitive files found in repository" "$sensitive_files"
fi

# Check for hardcoded secrets
hardcoded_secrets=$(grep -r "sk-proj-[A-Za-z0-9]\{40,\}\|AIza[A-Za-z0-9_-]\{30,\}\|ghp_[A-Za-z0-9]\{36,\}" \
    --include="*.js" --include="*.sh" --include="*.json" \
    --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null || true)
if [ -z "$hardcoded_secrets" ]; then
    pass "No hardcoded API keys or secrets found"
else
    fail "Hardcoded secrets detected" "Remove before deploying"
    echo "$hardcoded_secrets"
fi
echo ""

# Check 4: Required files
echo "Check 4: Required Deployment Files"
required_files=(
    "README.md"
    "LICENSE"
    "CONTRIBUTING.md"
    "SECURITY.md"
    ".gitignore"
    ".claude-plugin/plugin.json"
    ".claude-plugin/marketplace.json"
    "package.json"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        pass "$file exists"
    else
        fail "$file MISSING" "Required for deployment"
    fi
done
echo ""

# Check 5: Version consistency
echo "Check 5: Version Synchronization"
if [ -f ".claude-plugin/plugin.json" ]; then
    plugin_version=$(jq -r '.version' .claude-plugin/plugin.json 2>/dev/null || echo "unknown")
    marketplace_version=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json 2>/dev/null || echo "unknown")
    package_version=$(jq -r '.version' package.json 2>/dev/null || echo "unknown")

    if [ "$plugin_version" = "$marketplace_version" ] && [ "$plugin_version" = "$package_version" ]; then
        pass "All versions synchronized: v$plugin_version"
    else
        fail "Version mismatch detected" "plugin: $plugin_version, marketplace: $marketplace_version, package: $package_version"
    fi
fi
echo ""

# Check 6: Test suite
echo "Check 6: Test Suite Validation"
if [ -f "tests/run-all-tests.sh" ]; then
    pass "Test suite exists"
    info "Run './tests/run-all-tests.sh' to verify all tests pass"
    # Don't auto-run tests during deploy validation (too slow)
else
    warn "No test suite found" "Tests recommended for quality assurance"
fi
echo ""

# Check 7: .gitignore completeness
echo "Check 7: .gitignore Coverage"
critical_ignores=(".DS_Store" ".env" "*.log" "dev-workspace")
for item in "${critical_ignores[@]}"; do
    if git check-ignore "$item" >/dev/null 2>&1 || grep -q "^${item}\$\|${item}/" .gitignore; then
        pass "$item is gitignored"
    else
        fail "$item NOT gitignored" "Add to .gitignore"
    fi
done
echo ""

# Check 8: Clean deployment directory
echo "Check 8: Deployment Directory Cleanliness"
untracked=$(git ls-files --others --exclude-standard | grep -v "dev-workspace" || true)
if [ -z "$untracked" ]; then
    pass "No untracked files in deployment directory"
else
    warn "Untracked files found" "Consider adding to .gitignore or committing"
    echo "$untracked" | head -10
fi
echo ""

# Summary
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Deployment Validation Summary${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "Checks passed:  ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Checks failed:  ${RED}$CHECKS_FAILED${NC}"
echo -e "Warnings:       ${YELLOW}$CHECKS_WARNINGS${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}║              ✅ DEPLOYMENT APPROVED ✅                   ║${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Repository is ready for deployment.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. git push origin main"
    echo "  2. Verify GitHub Actions (if configured)"
    echo "  3. Test plugin installation: /plugin install claude-octopus@nyldn-plugins"
    echo ""
    exit 0
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                          ║${NC}"
    echo -e "${RED}║              ❌ DEPLOYMENT BLOCKED ❌                    ║${NC}"
    echo -e "${RED}║                                                          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}Fix the issues above before deploying.${NC}"
    echo ""
    exit 1
fi
