#!/usr/bin/env bash
# Test octo-state.sh functionality
# Validates project state management for Claude Octopus v7.22.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "octo-state.sh functionality"

OCTO_STATE="$PROJECT_ROOT/scripts/octo-state.sh"


TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Test directory (created fresh each run)
TEST_DIR=""

echo -e "${BLUE}🧪 Testing octo-state.sh (v7.22.0 Project Lifecycle)${NC}"
echo ""

# Helper functions
pass() { test_case "$1"; test_pass; }

fail() { test_case "$1"; test_fail "${2:-$1}"; }

info() { echo "$1"; }

# Setup test directory
setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    info "Test directory: $TEST_DIR"
}

# Cleanup test directory
cleanup() {
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Trap to cleanup on exit
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: Script exists and is executable
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test 1: Checking octo-state.sh exists and is executable..."
if [[ -f "$OCTO_STATE" ]]; then
    pass "octo-state.sh exists"
else
    fail "octo-state.sh not found" "Expected: $OCTO_STATE"
    exit 1
fi

if [[ -x "$OCTO_STATE" ]]; then
    pass "octo-state.sh is executable"
else
    fail "octo-state.sh is not executable" "Run: chmod +x $OCTO_STATE"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: Help command
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 2: Checking help command..."
if "$OCTO_STATE" help 2>&1 | grep -q "Octo State Manager"; then
    pass "Help command works"
else
    fail "Help command failed" "Did not find expected output"
fi

if "$OCTO_STATE" help 2>&1 | grep -q "init_project"; then
    pass "Help mentions init_project command"
else
    fail "Help missing init_project" "Should document init_project command"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: init_project --dry-run
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 3: Checking init_project --dry-run..."
setup

output=$("$OCTO_STATE" init_project --dry-run 2>&1)
if echo "$output" | grep -q "DRY RUN"; then
    pass "init_project --dry-run shows dry run message"
else
    fail "init_project --dry-run failed" "Did not show DRY RUN message"
fi

if [[ ! -d ".octo" ]]; then
    pass "init_project --dry-run did not create directory"
else
    fail "init_project --dry-run created directory" "Should not create files in dry-run mode"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: init_project (actual)
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 4: Checking init_project..."

output=$("$OCTO_STATE" init_project 2>&1)
if echo "$output" | grep -q "SUCCESS"; then
    pass "init_project succeeds"
else
    fail "init_project failed" "$output"
fi

# Check directory structure
if [[ -d ".octo" ]]; then
    pass ".octo/ directory created"
else
    fail ".octo/ directory not created" "Expected .octo/ to exist"
fi

if [[ -d ".octo/phases" ]]; then
    pass ".octo/phases/ directory created"
else
    fail ".octo/phases/ directory not created" "Expected .octo/phases/ to exist"
fi

if [[ -d ".octo/codebase" ]]; then
    pass ".octo/codebase/ directory created"
else
    fail ".octo/codebase/ directory not created" "Expected .octo/codebase/ to exist"
fi

# Check files
for file in STATE.md PROJECT.md ROADMAP.md config.json ISSUES.md LESSONS.md; do
    if [[ -f ".octo/$file" ]]; then
        pass ".octo/$file created"
    else
        fail ".octo/$file not created" "Expected .octo/$file to exist"
    fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: init_project (idempotent)
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 5: Checking init_project idempotency..."

output=$("$OCTO_STATE" init_project 2>&1)
if echo "$output" | grep -q "already exists"; then
    pass "init_project is idempotent (warns on existing)"
else
    fail "init_project not idempotent" "Should warn when .octo/ exists"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: read_state
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 6: Checking read_state..."

output=$("$OCTO_STATE" read_state 2>&1)
if echo "$output" | grep -q "schema="; then
    pass "read_state returns schema"
else
    fail "read_state missing schema" "Should return schema=value"
fi

if echo "$output" | grep -q "current_phase=1"; then
    pass "read_state returns current_phase=1"
else
    fail "read_state wrong phase" "Should return current_phase=1"
fi

if echo "$output" | grep -q "status=ready"; then
    pass "read_state returns status=ready"
else
    fail "read_state wrong status" "Should return status=ready"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: write_state
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 7: Checking write_state..."

"$OCTO_STATE" write_state --phase 2 --status planning --position "Planning phase 2" 2>&1
output=$("$OCTO_STATE" read_state 2>&1)

if echo "$output" | grep -q "current_phase=2"; then
    pass "write_state updates phase"
else
    fail "write_state did not update phase" "Expected current_phase=2"
fi

if echo "$output" | grep -q "status=planning"; then
    pass "write_state updates status"
else
    fail "write_state did not update status" "Expected status=planning"
fi

if echo "$output" | grep -q "current_position=Planning phase 2"; then
    pass "write_state updates position"
else
    fail "write_state did not update position" "Expected position='Planning phase 2'"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: write_state with blocker
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 8: Checking write_state with blocker..."

"$OCTO_STATE" write_state --status blocked --blocker "Waiting for API access" 2>&1

if grep -q "Waiting for API access" .octo/STATE.md; then
    pass "write_state adds blocker"
else
    fail "write_state did not add blocker" "Blocker text not found in STATE.md"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: update_phase shorthand
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 9: Checking update_phase shorthand..."

"$OCTO_STATE" update_phase 3 "Building auth module" building 2>&1
output=$("$OCTO_STATE" read_state 2>&1)

if echo "$output" | grep -q "current_phase=3"; then
    pass "update_phase updates phase"
else
    fail "update_phase did not update phase" "Expected current_phase=3"
fi

if echo "$output" | grep -q "status=building"; then
    pass "update_phase updates status"
else
    fail "update_phase did not update status" "Expected status=building"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: Validation - invalid status
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 10: Checking validation (invalid status)..."

if ! "$OCTO_STATE" write_state --status invalid_status 2>&1; then
    pass "Invalid status rejected"
else
    fail "Invalid status accepted" "Should reject 'invalid_status'"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: Validation - invalid phase
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 11: Checking validation (invalid phase)..."

if ! "$OCTO_STATE" write_state --phase -1 2>&1; then
    pass "Negative phase rejected"
else
    fail "Negative phase accepted" "Should reject phase=-1"
fi

if ! "$OCTO_STATE" write_state --phase abc 2>&1; then
    pass "Non-numeric phase rejected"
else
    fail "Non-numeric phase accepted" "Should reject phase=abc"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: get_context_tier - minimal
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 12: Checking get_context_tier minimal..."

output=$("$OCTO_STATE" get_context_tier minimal 2>&1)
if echo "$output" | grep -q "Context Tier: minimal"; then
    pass "get_context_tier minimal works"
else
    fail "get_context_tier minimal failed" "Did not show tier name"
fi

if echo "$output" | grep -q "STATE.md"; then
    pass "get_context_tier minimal includes STATE.md"
else
    fail "get_context_tier minimal missing STATE.md" "Should include STATE.md"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: get_context_tier - planning
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 13: Checking get_context_tier planning..."

output=$("$OCTO_STATE" get_context_tier planning 2>&1)
if echo "$output" | grep -q "PROJECT.md"; then
    pass "get_context_tier planning includes PROJECT.md"
else
    fail "get_context_tier planning missing PROJECT.md" "Should include PROJECT.md"
fi

if echo "$output" | grep -q "ROADMAP.md"; then
    pass "get_context_tier planning includes ROADMAP.md"
else
    fail "get_context_tier planning missing ROADMAP.md" "Should include ROADMAP.md"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: get_context_tier - auto
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 14: Checking get_context_tier auto..."

# Set status to building (should auto-detect execution tier)
"$OCTO_STATE" write_state --status building 2>&1
output=$("$OCTO_STATE" get_context_tier auto 2>&1)

if echo "$output" | grep -q "Context Tier: execution"; then
    pass "get_context_tier auto detects execution tier for building status"
else
    fail "get_context_tier auto failed" "Should detect execution tier for building status"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: History tracking
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 15: Checking history tracking..."

# History should contain multiple entries from our updates
history_count=$(grep -c "^\- \[" .octo/STATE.md || echo 0)
if [[ "$history_count" -ge 3 ]]; then
    pass "History tracks multiple updates (found $history_count entries)"
else
    fail "History not tracking updates" "Found only $history_count entries, expected 3+"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: config.json structure
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 16: Checking config.json structure..."

if grep -q '"interaction_mode"' .octo/config.json; then
    pass "config.json has interaction_mode"
else
    fail "config.json missing interaction_mode" "Should have interaction_mode field"
fi

if grep -q '"model_routing"' .octo/config.json; then
    pass "config.json has model_routing"
else
    fail "config.json missing model_routing" "Should have model_routing field"
fi

if grep -q '"context_tier"' .octo/config.json; then
    pass "config.json has context_tier"
else
    fail "config.json missing context_tier" "Should have context_tier field"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TEST: Unknown command handling
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Test 17: Checking unknown command handling..."

if ! "$OCTO_STATE" unknown_command 2>&1; then
    pass "Unknown command rejected"
else
    fail "Unknown command accepted" "Should reject unknown commands"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Test Summary${NC}"
test_summary
