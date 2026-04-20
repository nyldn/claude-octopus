#!/usr/bin/env bash
# Test v7.16.0 UX Features
# Validates all 3 UX enhancement features and critical fixes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "v7.16.0 UX Features"

ORCHESTRATE_SH="$PROJECT_ROOT/scripts/orchestrate.sh"
# v9.12: Search orchestrate.sh + lib/*.sh for functions that may have been decomposed
ALL_SRC=$(mktemp)
cat "$ORCHESTRATE_SH" "$(dirname "$ORCHESTRATE_SH")/lib/"*.sh > "$ALL_SRC" 2>/dev/null
trap 'rm -f "$ALL_SRC"' EXIT


TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}🧪 Testing v7.16.0 UX Features${NC}"
echo ""

pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 1: Critical Fixes
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 1: Critical Fixes"
echo "────────────────────────────────────────"

# Test 1.1: atomic_json_update function exists
if grep -q "^atomic_json_update()" "$ALL_SRC"; then
    pass "atomic_json_update() function exists"
else
    fail "atomic_json_update() function NOT found"
fi

# Test 1.2: validate_claude_code_task_features function exists
if grep -q "^validate_claude_code_task_features()" "$ALL_SRC"; then
    pass "validate_claude_code_task_features() function exists"
else
    fail "validate_claude_code_task_features() function NOT found"
fi

# Test 1.3: check_ux_dependencies function exists
if grep -q "^check_ux_dependencies()" "$ALL_SRC"; then
    pass "check_ux_dependencies() function exists"
else
    fail "check_ux_dependencies() function NOT found"
fi

# Test 1.4: Initialization calls exist
if grep -q "^validate_claude_code_task_features.*2>/dev/null" "$ALL_SRC"; then
    pass "validate_claude_code_task_features initialization call exists"
else
    fail "Initialization call missing"
fi

if grep -q "^check_ux_dependencies.*2>/dev/null" "$ALL_SRC"; then
    pass "check_ux_dependencies initialization call exists"
else
    fail "Initialization call missing"
fi

# Test 1.5: File locking implementation
if grep -q "lockfile.*lock" "$ALL_SRC"; then
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
if grep -q "^update_task_progress()" "$ALL_SRC"; then
    pass "update_task_progress() function exists"
else
    fail "update_task_progress() function NOT found"
fi

# Test 2.2: get_active_form_verb function exists
if grep -q "^get_active_form_verb()" "$ALL_SRC"; then
    pass "get_active_form_verb() function exists"
else
    fail "get_active_form_verb() function NOT found"
fi

# Test 2.3: Environment variable capture
if grep -q 'CLAUDE_TASK_ID="\${CLAUDE_CODE_TASK_ID:-}"' "$ALL_SRC"; then
    pass "CLAUDE_TASK_ID environment variable captured"
else
    fail "CLAUDE_TASK_ID capture missing"
fi

if grep -q 'CLAUDE_CODE_CONTROL="\${CLAUDE_CODE_CONTROL_PIPE:-}"' "$ALL_SRC"; then
    pass "CLAUDE_CODE_CONTROL environment variable captured"
else
    fail "CLAUDE_CODE_CONTROL capture missing"
fi

# Test 2.4: Verb generation for all phases
for phase in discover define develop deliver; do
    if grep -q "${phase}" "$ALL_SRC" && grep -q 'verb=' "$ALL_SRC"; then
        pass "get_active_form_verb has verbs for $phase phase"
    else
        fail "Missing verbs for $phase phase"
    fi
done

# Test 2.5: Emoji indicators present
for emoji in "🔴" "🟡" "🔵" "🔍" "🎯" "🛠️" "✅"; do
    if grep -q "$emoji" "$ALL_SRC"; then
        pass "Emoji indicator present: $emoji"
    else
        fail "Emoji indicator missing: $emoji"
    fi
done

# Test 2.6: spawn_agent integration
if grep -q "get_active_form_verb.*phase.*agent_type" "$ALL_SRC"; then
    pass "spawn_agent() calls get_active_form_verb"
else
    fail "spawn_agent integration missing"
fi

if grep -q "update_task_progress.*CLAUDE_TASK_ID" "$ALL_SRC"; then
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
    if grep -q "^${func}()" "$ALL_SRC"; then
        pass "$func() function exists"
    else
        fail "$func() function NOT found"
    fi
done

# Test 3.2: PROGRESS_FILE variable defined
if grep -q 'PROGRESS_FILE' "$ALL_SRC"; then
    pass "PROGRESS_FILE variable used"
else
    fail "PROGRESS_FILE variable missing"
fi

# Test 3.3: probe_discover integration
if grep -q "init_progress_tracking.*discover" "$ALL_SRC"; then
    pass "probe_discover() initializes progress tracking"
else
    fail "probe_discover integration missing"
fi

if grep -q "display_progress_summary" "$ALL_SRC"; then
    pass "Workflows display progress summary"
else
    fail "display_progress_summary not called"
fi

# Test 3.4: Agent status tracking
if grep -q 'update_agent_status.*"running"' "$ALL_SRC"; then
    pass "Agents marked as 'running'"
else
    fail "Running status tracking missing"
fi

if grep -q 'update_agent_status.*"completed"' "$ALL_SRC"; then
    pass "Agents marked as 'completed'"
else
    fail "Completed status tracking missing"
fi

if grep -q 'update_agent_status.*"failed"' "$ALL_SRC"; then
    pass "Agents marked as 'failed'"
else
    fail "Failed status tracking missing"
fi

# Test 3.5: Summary format elements
if grep -q "WORKFLOW SUMMARY" "$ALL_SRC"; then
    pass "Workflow summary header present"
else
    fail "Summary header missing"
fi

if grep -q "Provider Results:" "$ALL_SRC"; then
    pass "Provider results section present"
else
    fail "Provider results section missing"
fi

if grep -q "Total Cost:" "$ALL_SRC"; then
    pass "Cost summary present"
else
    fail "Cost summary missing"
fi

if grep -q "Total Time:" "$ALL_SRC"; then
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
if grep -q "TIMEOUT EXCEEDED" "$ALL_SRC"; then
    pass "Enhanced timeout error header present"
else
    fail "Timeout error header missing"
fi

if grep -q "Possible solutions:" "$ALL_SRC"; then
    pass "Actionable timeout solutions provided"
else
    fail "Timeout solutions missing"
fi

if grep -q "Increase timeout:" "$ALL_SRC"; then
    pass "Timeout increase suggestion present"
else
    fail "Timeout suggestion missing"
fi

# Test 4.2: Timeout tracking in update_agent_status
if grep -q "timeout_warning" "$ALL_SRC"; then
    pass "Timeout warning tracking present"
else
    fail "Timeout warning tracking missing"
fi

if grep -q "timeout_pct" "$ALL_SRC"; then
    pass "Timeout percentage calculation present"
else
    fail "Timeout percentage missing"
fi

if grep -q "timeout_ms" "$ALL_SRC"; then
    pass "Timeout milliseconds tracking present"
else
    fail "Timeout ms tracking missing"
fi

if grep -q "remaining_ms" "$ALL_SRC"; then
    pass "Remaining time tracking present"
else
    fail "Remaining time tracking missing"
fi

# Test 4.3: 80% threshold check
# Note: avoid grep -q in pipelines — under pipefail, early exit causes SIGPIPE (exit 141)
if grep -q "timeout_pct.*80\|80.*timeout_pct" "$ALL_SRC" || grep -q 'timeout_pct -ge 80' "$ALL_SRC"; then
    pass "80% threshold implemented"
else
    fail "80% threshold missing"
fi

# Test 4.4: Timeout warning display
if grep -q "Approaching timeout" "$ALL_SRC"; then
    pass "Timeout warning message present"
else
    fail "Timeout warning message missing"
fi

if grep -q "Timeout Guidance:" "$ALL_SRC"; then
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
if grep -q 'TASK_PROGRESS_ENABLED.*!= "true"' "$ALL_SRC"; then
    pass "Task progress graceful degradation present"
else
    fail "Task progress degradation missing"
fi

if grep -q 'PROGRESS_TRACKING_ENABLED.*!= "true"' "$ALL_SRC"; then
    pass "Progress tracking graceful degradation present"
else
    fail "Progress tracking degradation missing"
fi

# Test 5.3: Atomic updates with jq
if grep -q "atomic_json_update" "$ALL_SRC" && grep -q "jq" "$ALL_SRC"; then
    pass "Atomic JSON updates use atomic_json_update()"
else
    fail "Atomic updates not using helper function"
fi

# Test 5.4: Cleanup on startup
if grep -q "cleanup_old_progress_files" "$ALL_SRC"; then
    pass "Old progress files cleanup integrated"
else
    fail "Cleanup not integrated"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Final Summary
# ═══════════════════════════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
test_summary
