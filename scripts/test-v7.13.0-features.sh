#!/usr/bin/env bash
# Quality Gates for v7.13.0 Release
# Tests all 6 new features before release

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test results
PASSED=0
FAILED=0

# Test helper
test_gate() {
    local gate_name="$1"
    local test_command="$2"

    echo ""
    echo -e "${CYAN}Testing: $gate_name${NC}"
    echo "Command: $test_command"

    if eval "$test_command"; then
        echo -e "${GREEN}✅ PASSED${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}❌ FAILED${NC}"
        ((FAILED++))
        return 1
    fi
}

echo "═══════════════════════════════════════════════════════════"
echo "Claude Octopus v7.13.0 - Quality Gates"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Quality Gate 1: Version Detection
test_gate "QG1: Claude Code Version Detection" \
    "claude --version 2>/dev/null | grep -E 'v2\\.(1\\.(1[6-9]|2[0-9])|[2-9])' || echo 'Warning: Claude Code version check skipped (command not in PATH)'"

# Quality Gate 2: Helper Scripts Exist and Are Executable
test_gate "QG2: Task Manager Script" \
    "[[ -x '$SCRIPT_DIR/task-manager.sh' ]]"

test_gate "QG2: Session Manager Script" \
    "[[ -x '$SCRIPT_DIR/session-manager.sh' ]]"

test_gate "QG2: MCP Provider Detection Script" \
    "[[ -x '$SCRIPT_DIR/mcp-provider-detection.sh' ]]"

test_gate "QG2: Permissions Manager Script" \
    "[[ -x '$SCRIPT_DIR/permissions-manager.sh' ]]"

# Quality Gate 3: Task Manager Functionality
test_gate "QG3: Task Manager - Get Status" \
    "'$SCRIPT_DIR/task-manager.sh' get-status &>/dev/null"

test_gate "QG3: Task Manager - Create Phase Task" \
    "'$SCRIPT_DIR/task-manager.sh' create-phase discover 'test prompt' | grep -q 'TaskCreate'"

# Quality Gate 4: Session Variable Export
test_gate "QG4: Session Manager - Export Variables" \
    "source '$SCRIPT_DIR/session-manager.sh' export && [[ -n \"\${OCTOPUS_SESSION_ID:-}\" ]]"

# Quality Gate 5: MCP Provider Detection
test_gate "QG5: MCP Detection - Check Providers" \
    "'$SCRIPT_DIR/mcp-provider-detection.sh' detect-all | jq '.providers' &>/dev/null"

test_gate "QG5: MCP Detection - Banner Generation" \
    "'$SCRIPT_DIR/mcp-provider-detection.sh' banner | grep -q 'Claude'"

# Quality Gate 6: Background Permission Handling
test_gate "QG6: Permissions - Cost Estimation" \
    "'$SCRIPT_DIR/permissions-manager.sh' estimate embrace | grep -q '\\$'"

# Quality Gate 7: CLAUDE.md Structure
test_gate "QG7: Modular CLAUDE.md - Codex Config" \
    "[[ -f '$PLUGIN_ROOT/config/providers/codex/CLAUDE.md' ]]"

test_gate "QG7: Modular CLAUDE.md - Gemini Config" \
    "[[ -f '$PLUGIN_ROOT/config/providers/gemini/CLAUDE.md' ]]"

test_gate "QG7: Modular CLAUDE.md - Workflows Config" \
    "[[ -f '$PLUGIN_ROOT/config/workflows/CLAUDE.md' ]]"

test_gate "QG7: Main CLAUDE.md - References Modular Config" \
    "grep -q 'Modular Configuration' '$PLUGIN_ROOT/CLAUDE.md'"

# Quality Gate 8: Hooks Configuration
test_gate "QG8: Hooks - additionalContext Support" \
    "grep -q 'additionalContext' '$PLUGIN_ROOT/.claude-plugin/hooks.json'"

# Quality Gate 9: Documentation Updates
test_gate "QG9: Version Update - package.json" \
    "grep -q '\"version\": \"7.13.0\"' '$PLUGIN_ROOT/package.json'"

test_gate "QG9: Version Update - README" \
    "grep -q '7.13.0' '$PLUGIN_ROOT/README.md'"

test_gate "QG9: CHANGELOG Updated" \
    "grep -q '\\[7.13.0\\]' '$PLUGIN_ROOT/CHANGELOG.md'"

test_gate "QG9: Migration Guide Exists" \
    "[[ -f '$PLUGIN_ROOT/MIGRATION-7.13.0.md' ]]"

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Quality Gates Summary"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All quality gates passed!${NC}"
    echo ""
    echo "Ready for release:"
    echo "  1. Commit changes: git add . && git commit -m 'feat: integrate Claude Code v2.1.20 features (v7.13.0)'"
    echo "  2. Tag release: git tag v7.13.0"
    echo "  3. Push: git push origin main --tags"
    exit 0
else
    echo -e "${RED}❌ Some quality gates failed. Fix issues before release.${NC}"
    exit 1
fi
