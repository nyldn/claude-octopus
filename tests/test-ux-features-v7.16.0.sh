#!/usr/bin/env bash
# Test v7.16.0 UX Features
# Validates all 3 UX enhancement features and critical fixes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE_SH="$PROJECT_ROOT/scripts/orchestrate.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}🧪 Testing v7.16.0 UX Features${NC}"
echo ""

pass() {
    ((PASS_COUNT++))
    ((TEST_COUNT++))
    echo -e "${GREEN}✅ PASS${NC}: $1"
}

fail() {
    ((FAIL_COUNT++))
    ((TEST_COUNT++))
    echo -e "${RED}❌ FAIL${NC}: $1"
    [[ -n "${2:-}" ]] && echo -e "   ${YELLOW}$2${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 1: Critical Fixes
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 1: Critical Fixes"
echo "────────────────────────────────────────"

# Test 1.1: atomic_json_update function exists
if grep -q "^atomic_json_update()" "$ORCHESTRATE_SH"; then
    pass "atomic_json_update() function exists"
else
    fail "atomic_json_update() function NOT found"
fi

# Test 1.2: validate_claude_code_task_features function exists
if grep -q "^validate_claude_code_task_features()" "$ORCHESTRATE_SH"; then
    pass "validate_claude_code_task_features() function exists"
else
    fail "validate_claude_code_task_features() function NOT found"
fi

# Test 1.3: check_ux_dependencies function exists
if grep -q "^check_ux_dependencies()" "$ORCHESTRATE_SH"; then
    pass "check_ux_dependencies() function exists"
else
    fail "check_ux_dependencies() function NOT found"
fi

# Test 1.4: Initialization calls exist
if grep -q "^validate_claude_code_task_features.*2>/dev/null" "$ORCHESTRATE_SH"; then
    pass "validate_claude_code_task_features initialization call exists"
else
    fail "Initialization call missing"
fi

if grep -q "^check_ux_dependencies.*2>/dev/null" "$ORCHESTRATE_SH"; then
    pass "check_ux_dependencies initialization call exists"
else
    fail "Initialization call missing"
fi

# Test 1.5: File locking implementation
if grep -q "lockfile.*lock" "$ORCHESTRATE_SH"; then
    pass "File locking mechanism present"
else
    fail "File locking mechanism missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 2: Feature 1 - Enhanced Spinner Verbs
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 2: Feature 1 - Enhanced Spinner Verbs"
echo "────────────────────────────────────────"

# Test 2.1: update_task_progress function exists
if grep -q "^update_task_progress()" "$ORCHESTRATE_SH"; then
    pass "update_task_progress() function exists"
else
    fail "update_task_progress() function NOT found"
fi

# Test 2.2: get_active_form_verb function exists
if grep -q "^get_active_form_verb()" "$ORCHESTRATE_SH"; then
    pass "get_active_form_verb() function exists"
else
    fail "get_active_form_verb() function NOT found"
fi

# Test 2.3: Environment variable capture
if grep -q 'CLAUDE_TASK_ID="\${CLAUDE_CODE_TASK_ID:-}"' "$ORCHESTRATE_SH"; then
    pass "CLAUDE_TASK_ID environment variable captured"
else
    fail "CLAUDE_TASK_ID capture missing"
fi

if grep -q 'CLAUDE_CODE_CONTROL="\${CLAUDE_CODE_CONTROL_PIPE:-}"' "$ORCHESTRATE_SH"; then
    pass "CLAUDE_CODE_CONTROL environment variable captured"
else
    fail "CLAUDE_CODE_CONTROL capture missing"
fi

# Test 2.4: Verb generation for all phases
for phase in discover define develop deliver; do
    if grep -q "\"$phase\")" "$ORCHESTRATE_SH" && grep -A10 "\"$phase\")" "$ORCHESTRATE_SH" | grep -q "codex.*verb="; then
        pass "get_active_form_verb has verbs for $phase phase"
    else
        fail "Missing verbs for $phase phase"
    fi
done

# Test 2.5: Emoji indicators present
for emoji in "🔴" "🟡" "🔵" "🔍" "🎯" "🛠️" "✅"; do
    if grep -q "$emoji" "$ORCHESTRATE_SH"; then
        pass "Emoji indicator present: $emoji"
    else
        fail "Emoji indicator missing: $emoji"
    fi
done

# Test 2.6: spawn_agent integration
if grep -q "get_active_form_verb.*phase.*agent_type" "$ORCHESTRATE_SH"; then
    pass "spawn_agent() calls get_active_form_verb"
else
    fail "spawn_agent integration missing"
fi

if grep -q "update_task_progress.*CLAUDE_TASK_ID" "$ORCHESTRATE_SH"; then
    pass "spawn_agent() calls update_task_progress"
else
    fail "Task progress update missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 3: Feature 2 - Enhanced Progress Indicators
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 3: Feature 2 - Enhanced Progress Indicators"
echo "────────────────────────────────────────"

# Test 3.1: All progress tracking functions exist
for func in init_progress_tracking update_agent_status display_progress_summary cleanup_old_progress_files; do
    if grep -q "^${func}()" "$ORCHESTRATE_SH"; then
        pass "$func() function exists"
    else
        fail "$func() function NOT found"
    fi
done

# Test 3.2: PROGRESS_FILE variable defined
if grep -q 'PROGRESS_FILE=.*progress-.*json' "$ORCHESTRATE_SH"; then
    pass "PROGRESS_FILE variable defined"
else
    fail "PROGRESS_FILE variable missing"
fi

# Test 3.3: probe_discover integration
if grep -q "init_progress_tracking.*discover" "$ORCHESTRATE_SH"; then
    pass "probe_discover() initializes progress tracking"
else
    fail "probe_discover integration missing"
fi

if grep -q "display_progress_summary" "$ORCHESTRATE_SH"; then
    pass "Workflows display progress summary"
else
    fail "display_progress_summary not called"
fi

# Test 3.4: Agent status tracking
if grep -q 'update_agent_status.*"running"' "$ORCHESTRATE_SH"; then
    pass "Agents marked as 'running'"
else
    fail "Running status tracking missing"
fi

if grep -q 'update_agent_status.*"completed"' "$ORCHESTRATE_SH"; then
    pass "Agents marked as 'completed'"
else
    fail "Completed status tracking missing"
fi

if grep -q 'update_agent_status.*"failed"' "$ORCHESTRATE_SH"; then
    pass "Agents marked as 'failed'"
else
    fail "Failed status tracking missing"
fi

# Test 3.5: Summary format elements
if grep -q "WORKFLOW SUMMARY" "$ORCHESTRATE_SH"; then
    pass "Workflow summary header present"
else
    fail "Summary header missing"
fi

if grep -q "Provider Results:" "$ORCHESTRATE_SH"; then
    pass "Provider results section present"
else
    fail "Provider results section missing"
fi

if grep -q "Total Cost:" "$ORCHESTRATE_SH"; then
    pass "Cost summary present"
else
    fail "Cost summary missing"
fi

if grep -q "Total Time:" "$ORCHESTRATE_SH"; then
    pass "Time summary present"
else
    fail "Time summary missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 4: Feature 3 - Timeout Visibility
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 4: Feature 3 - Timeout Visibility"
echo "────────────────────────────────────────"

# Test 4.1: Enhanced timeout error messages
if grep -q "TIMEOUT EXCEEDED" "$ORCHESTRATE_SH"; then
    pass "Enhanced timeout error header present"
else
    fail "Timeout error header missing"
fi

if grep -q "Possible solutions:" "$ORCHESTRATE_SH"; then
    pass "Actionable timeout solutions provided"
else
    fail "Timeout solutions missing"
fi

if grep -q "Increase timeout:" "$ORCHESTRATE_SH"; then
    pass "Timeout increase suggestion present"
else
    fail "Timeout suggestion missing"
fi

# Test 4.2: Timeout tracking in update_agent_status
if grep -q "timeout_warning" "$ORCHESTRATE_SH"; then
    pass "Timeout warning tracking present"
else
    fail "Timeout warning tracking missing"
fi

if grep -q "timeout_pct" "$ORCHESTRATE_SH"; then
    pass "Timeout percentage calculation present"
else
    fail "Timeout percentage missing"
fi

if grep -q "timeout_ms" "$ORCHESTRATE_SH"; then
    pass "Timeout milliseconds tracking present"
else
    fail "Timeout ms tracking missing"
fi

if grep -q "remaining_ms" "$ORCHESTRATE_SH"; then
    pass "Remaining time tracking present"
else
    fail "Remaining time tracking missing"
fi

# Test 4.3: 80% threshold check
if grep -q "80" "$ORCHESTRATE_SH" && grep -A5 -B5 "80" "$ORCHESTRATE_SH" | grep -q "timeout_pct"; then
    pass "80% threshold implemented"
else
    fail "80% threshold missing"
fi

# Test 4.4: Timeout warning display
if grep -q "Approaching timeout" "$ORCHESTRATE_SH"; then
    pass "Timeout warning message present"
else
    fail "Timeout warning message missing"
fi

if grep -q "Timeout Guidance:" "$ORCHESTRATE_SH"; then
    pass "Timeout guidance section present"
else
    fail "Timeout guidance section missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 5: Integration & Functionality
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 5: Integration & Functionality"
echo "────────────────────────────────────────"

# Test 5.1: Basic functionality
if "$ORCHESTRATE_SH" help >/dev/null 2>&1; then
    pass "orchestrate.sh help command works"
else
    fail "orchestrate.sh help command failed"
fi

# Test 5.2: Graceful degradation checks
if grep -q 'TASK_PROGRESS_ENABLED.*!= "true"' "$ORCHESTRATE_SH"; then
    pass "Task progress graceful degradation present"
else
    fail "Task progress degradation missing"
fi

if grep -q 'PROGRESS_TRACKING_ENABLED.*!= "true"' "$ORCHESTRATE_SH"; then
    pass "Progress tracking graceful degradation present"
else
    fail "Progress tracking degradation missing"
fi

# Test 5.3: Atomic updates with jq
if grep -q "atomic_json_update.*jq" "$ORCHESTRATE_SH"; then
    pass "Atomic JSON updates use atomic_json_update()"
else
    fail "Atomic updates not using helper function"
fi

# Test 5.4: Cleanup on startup
if grep -q "cleanup_old_progress_files" "$ORCHESTRATE_SH"; then
    pass "Old progress files cleanup integrated"
else
    fail "Cleanup not integrated"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Final Summary
# ═══════════════════════════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Test Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Total tests:  ${BLUE}${TEST_COUNT}${NC}"
echo -e "Passed:       ${GREEN}${PASS_COUNT}${NC}"
echo -e "Failed:       ${RED}${FAIL_COUNT}${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✅ All v7.16.0 UX feature tests passed!${NC}"
    echo ""
    echo -e "${BLUE}ℹ${NC}  All 3 UX features successfully implemented:"
    echo "  ✅ Critical Fixes (file locking, env validation, dependencies)"
    echo "  ✅ Feature 1: Enhanced Spinner Verbs"
    echo "  ✅ Feature 2: Enhanced Progress Indicators"
    echo "  ✅ Feature 3: Timeout Visibility"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
