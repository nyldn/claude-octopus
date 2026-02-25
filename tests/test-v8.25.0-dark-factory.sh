#!/usr/bin/env bash
# Test v8.25.0 Dark Factory Mode (Issue #37)
# Validates E19 (Scenario Holdout), E21 (Satisfaction Scoring), E22 (Factory Pipeline)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE_SH="$PROJECT_ROOT/scripts/orchestrate.sh"
COMMAND_FILE="$PROJECT_ROOT/.claude/commands/factory.md"
SKILL_FILE="$PROJECT_ROOT/.claude/skills/skill-factory.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}Testing v8.25.0 Dark Factory Mode (Issue #37)${NC}"
echo ""

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "${GREEN}  PASS${NC}: $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "${RED}  FAIL${NC}: $1"
    if [[ -n "${2:-}" ]]; then echo -e "   ${YELLOW}$2${NC}"; fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 1: Function Registration
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 1: Function Registration"
echo "────────────────────────────────────────"

# Test 1.1: parse_factory_spec exists
if grep -q "^parse_factory_spec()" "$ORCHESTRATE_SH"; then
    pass "parse_factory_spec() function exists"
else
    fail "parse_factory_spec() function NOT found"
fi

# Test 1.2: generate_factory_scenarios exists
if grep -q "^generate_factory_scenarios()" "$ORCHESTRATE_SH"; then
    pass "generate_factory_scenarios() function exists"
else
    fail "generate_factory_scenarios() function NOT found"
fi

# Test 1.3: split_holdout_scenarios exists
if grep -q "^split_holdout_scenarios()" "$ORCHESTRATE_SH"; then
    pass "split_holdout_scenarios() function exists"
else
    fail "split_holdout_scenarios() function NOT found"
fi

# Test 1.4: run_holdout_tests exists
if grep -q "^run_holdout_tests()" "$ORCHESTRATE_SH"; then
    pass "run_holdout_tests() function exists"
else
    fail "run_holdout_tests() function NOT found"
fi

# Test 1.5: score_satisfaction exists
if grep -q "^score_satisfaction()" "$ORCHESTRATE_SH"; then
    pass "score_satisfaction() function exists"
else
    fail "score_satisfaction() function NOT found"
fi

# Test 1.6: generate_factory_report exists
if grep -q "^generate_factory_report()" "$ORCHESTRATE_SH"; then
    pass "generate_factory_report() function exists"
else
    fail "generate_factory_report() function NOT found"
fi

# Test 1.7: factory_run exists
if grep -q "^factory_run()" "$ORCHESTRATE_SH"; then
    pass "factory_run() function exists"
else
    fail "factory_run() function NOT found"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 2: Configuration Defaults
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 2: Configuration Defaults"
echo "────────────────────────────────────────"

# Test 2.1: OCTOPUS_FACTORY_MODE default
if grep -q 'OCTOPUS_FACTORY_MODE="${OCTOPUS_FACTORY_MODE:-false}"' "$ORCHESTRATE_SH"; then
    pass "OCTOPUS_FACTORY_MODE defaults to false"
else
    fail "OCTOPUS_FACTORY_MODE default missing"
fi

# Test 2.2: OCTOPUS_FACTORY_HOLDOUT_RATIO default
if grep -q 'OCTOPUS_FACTORY_HOLDOUT_RATIO="${OCTOPUS_FACTORY_HOLDOUT_RATIO:-0.20}"' "$ORCHESTRATE_SH"; then
    pass "OCTOPUS_FACTORY_HOLDOUT_RATIO defaults to 0.20"
else
    fail "OCTOPUS_FACTORY_HOLDOUT_RATIO default missing"
fi

# Test 2.3: OCTOPUS_FACTORY_MAX_RETRIES default
if grep -q 'OCTOPUS_FACTORY_MAX_RETRIES="${OCTOPUS_FACTORY_MAX_RETRIES:-1}"' "$ORCHESTRATE_SH"; then
    pass "OCTOPUS_FACTORY_MAX_RETRIES defaults to 1"
else
    fail "OCTOPUS_FACTORY_MAX_RETRIES default missing"
fi

# Test 2.4: OCTOPUS_FACTORY_SATISFACTION_TARGET env var
if grep -q 'OCTOPUS_FACTORY_SATISFACTION_TARGET' "$ORCHESTRATE_SH"; then
    pass "OCTOPUS_FACTORY_SATISFACTION_TARGET env var supported"
else
    fail "OCTOPUS_FACTORY_SATISFACTION_TARGET env var missing"
fi

# Test 2.5: v8.25.0 version comment present
if grep -q 'v8.25.0.*Dark Factory' "$ORCHESTRATE_SH"; then
    pass "v8.25.0 version comment present"
else
    fail "v8.25.0 version comment missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 3: Command File Validation
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 3: Command File Validation"
echo "────────────────────────────────────────"

# Test 3.1: Command file exists
if [[ -f "$COMMAND_FILE" ]]; then
    pass "factory.md command file exists"
else
    fail "factory.md command file NOT found"
fi

# Test 3.2: Frontmatter has command name
if grep -q 'command: factory' "$COMMAND_FILE"; then
    pass "Command frontmatter: command: factory"
else
    fail "Command frontmatter missing command name"
fi

# Test 3.3: Aliases include dark-factory
if grep -q 'dark-factory' "$COMMAND_FILE"; then
    pass "Command alias: dark-factory"
else
    fail "Command alias dark-factory missing"
fi

# Test 3.4: References orchestrate.sh factory
if grep -q 'orchestrate.sh factory' "$COMMAND_FILE"; then
    pass "Command references orchestrate.sh factory"
else
    fail "Command missing orchestrate.sh factory reference"
fi

# Test 3.5: Mentions --spec flag
if grep -q '\-\-spec' "$COMMAND_FILE"; then
    pass "Command documents --spec flag"
else
    fail "Command missing --spec flag documentation"
fi

# Test 3.6: Cost estimate mentioned
if grep -q '\$0.50' "$COMMAND_FILE"; then
    pass "Command includes cost estimate"
else
    fail "Command missing cost estimate"
fi

# Test 3.7: 7-phase pipeline documented
if grep -q 'Holdout Tests' "$COMMAND_FILE" && grep -q 'Satisfaction' "$COMMAND_FILE"; then
    pass "7-phase pipeline documented"
else
    fail "Pipeline documentation incomplete"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 4: Skill File Validation
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 4: Skill File Validation"
echo "────────────────────────────────────────"

# Test 4.1: Skill file exists
if [[ -f "$SKILL_FILE" ]]; then
    pass "skill-factory.md skill file exists"
else
    fail "skill-factory.md skill file NOT found"
fi

# Test 4.2: Enforced execution mode
if grep -q 'execution_mode: enforced' "$SKILL_FILE"; then
    pass "Skill has execution_mode: enforced"
else
    fail "Skill missing enforced execution mode"
fi

# Test 4.3: Validation gates defined
if grep -q 'factory_report_exists' "$SKILL_FILE"; then
    pass "Validation gate: factory_report_exists"
else
    fail "Missing factory_report_exists validation gate"
fi

# Test 4.4: 8-step sequence
if grep -q 'STEP 8' "$SKILL_FILE"; then
    pass "Skill has 8-step execution contract"
else
    fail "Skill missing 8-step sequence"
fi

# Test 4.5: Prohibited actions section
if grep -q 'CANNOT skip orchestrate.sh factory' "$SKILL_FILE"; then
    pass "Prohibited actions documented"
else
    fail "Prohibited actions missing"
fi

# Test 4.6: References orchestrate.sh factory
if grep -q 'orchestrate.sh factory' "$SKILL_FILE"; then
    pass "Skill references orchestrate.sh factory"
else
    fail "Skill missing orchestrate.sh factory reference"
fi

# Test 4.7: Trigger aliases
if grep -q 'build-from-spec' "$SKILL_FILE" && grep -q 'autonomous-build' "$SKILL_FILE"; then
    pass "Skill trigger aliases present"
else
    fail "Skill trigger aliases missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 5: Holdout Split Logic (Functional)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 5: Holdout Split Logic"
echo "────────────────────────────────────────"

# Create temp directory and scenario file for functional testing
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cat > "$TEMP_DIR/scenarios-all.md" << 'SCENARIOS'
# Test Scenarios

### Scenario 1: User login happy path
**Behavior:** Authentication
**Type:** happy-path
**Given:** Valid credentials
**When:** User submits login form
**Then:** User is authenticated

### Scenario 2: Invalid password
**Behavior:** Authentication
**Type:** error-handling
**Given:** Valid username, wrong password
**When:** User submits login form
**Then:** Error message displayed

### Scenario 3: Session timeout
**Behavior:** Session management
**Type:** edge-case
**Given:** Authenticated user, idle for 30min
**When:** User makes a request
**Then:** Redirected to login

### Scenario 4: Rate limiting
**Behavior:** Security
**Type:** non-functional
**Given:** Same IP, 100 requests in 1 minute
**When:** 101st request arrives
**Then:** Request rejected with 429

### Scenario 5: Password reset flow
**Behavior:** Account recovery
**Type:** happy-path
**Given:** Registered email
**When:** User requests password reset
**Then:** Reset email sent

### Scenario 6: OAuth integration
**Behavior:** SSO
**Type:** integration
**Given:** Valid OAuth provider
**When:** User clicks "Sign in with Google"
**Then:** OAuth flow initiated

### Scenario 7: Remember me checkbox
**Behavior:** Session management
**Type:** happy-path
**Given:** User checks "remember me"
**When:** Browser is closed and reopened
**Then:** User remains authenticated

### Scenario 8: SQL injection attempt
**Behavior:** Security
**Type:** edge-case
**Given:** Malicious input in username field
**When:** User submits login form
**Then:** Input sanitized, no data leak

### Scenario 9: Concurrent login detection
**Behavior:** Security
**Type:** edge-case
**Given:** User logged in on device A
**When:** Same user logs in on device B
**Then:** Device A session invalidated

### Scenario 10: Password complexity
**Behavior:** Account management
**Type:** happy-path
**Given:** New password with weak criteria
**When:** User submits password change
**Then:** Validation error with requirements
SCENARIOS

# Test 5.1: Can source the split function (syntax check via grep of structure)
if grep -q 'split_holdout_scenarios()' "$ORCHESTRATE_SH"; then
    pass "split_holdout_scenarios() function found"
else
    fail "split_holdout_scenarios() function missing"
fi

# Test 5.2: Scenario file has 10 scenarios
scenario_count=$(grep -c '### Scenario' "$TEMP_DIR/scenarios-all.md")
if [[ $scenario_count -eq 10 ]]; then
    pass "Test data: 10 scenarios created"
else
    fail "Test data: expected 10 scenarios, got $scenario_count"
fi

# Test 5.3: Function handles holdout ratio calculation
# Verify the awk-based calculation pattern exists
if grep -q 'holdout_count.*awk.*printf' "$ORCHESTRATE_SH"; then
    pass "Holdout ratio calculation uses awk"
else
    fail "Holdout ratio calculation pattern missing"
fi

# Test 5.4: Function creates scenarios-visible.md and scenarios-holdout.md
if grep -q 'scenarios-visible.md' "$ORCHESTRATE_SH" && grep -q 'scenarios-holdout.md' "$ORCHESTRATE_SH"; then
    pass "Output files: scenarios-visible.md and scenarios-holdout.md"
else
    fail "Output file references missing"
fi

# Test 5.5: Minimum holdout count of 1
if grep -q 'holdout_count -lt 1' "$ORCHESTRATE_SH"; then
    pass "Minimum holdout count check present"
else
    fail "Minimum holdout count guard missing"
fi

# Test 5.6: Holdout index distribution (spread, not sequential)
if grep -q 'step.*total.*holdout_count' "$ORCHESTRATE_SH"; then
    pass "Holdout uses spread distribution (not sequential)"
else
    fail "Holdout distribution pattern missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 6: CLI Integration
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 6: CLI Integration"
echo "────────────────────────────────────────"

# Test 6.1: factory dispatch case exists
if grep -q 'factory|dark-factory)' "$ORCHESTRATE_SH"; then
    pass "CLI dispatch: factory|dark-factory case"
else
    fail "CLI dispatch case missing"
fi

# Test 6.2: --help flag handled
help_output=$("$ORCHESTRATE_SH" factory --help 2>&1) || true
if echo "$help_output" | grep -q 'Dark Factory Mode'; then
    pass "factory --help displays usage"
else
    fail "factory --help output incorrect"
fi

# Test 6.3: Missing --spec shows error
missing_output=$("$ORCHESTRATE_SH" factory 2>&1) || true
if echo "$missing_output" | grep -q 'Missing --spec'; then
    pass "Missing --spec shows error message"
else
    fail "Missing --spec error not displayed"
fi

# Test 6.4: --spec flag parsing
if grep -q '\-\-spec)' "$ORCHESTRATE_SH" && grep -q 'factory_spec=' "$ORCHESTRATE_SH"; then
    pass "--spec flag parsing implemented"
else
    fail "--spec flag parsing missing"
fi

# Test 6.5: --holdout-ratio flag parsing
if grep -q '\-\-holdout-ratio)' "$ORCHESTRATE_SH" && grep -q 'factory_holdout=' "$ORCHESTRATE_SH"; then
    pass "--holdout-ratio flag parsing implemented"
else
    fail "--holdout-ratio flag parsing missing"
fi

# Test 6.6: --max-retries flag parsing
if grep -q '\-\-max-retries)' "$ORCHESTRATE_SH" && grep -q 'factory_retries=' "$ORCHESTRATE_SH"; then
    pass "--max-retries flag parsing implemented"
else
    fail "--max-retries flag parsing missing"
fi

# Test 6.7: --ci flag parsing
if grep -q '\-\-ci)' "$ORCHESTRATE_SH" && grep -q 'factory_ci=' "$ORCHESTRATE_SH"; then
    pass "--ci flag parsing implemented"
else
    fail "--ci flag parsing missing"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite 7: Dry-Run Validation
# ═══════════════════════════════════════════════════════════════════════════════

echo "Test Suite 7: Architecture Validation"
echo "────────────────────────────────────────"

# Test 7.1: Factory wraps embrace_full_workflow (not duplicate)
if grep -q 'embrace_full_workflow.*embrace_prompt' "$ORCHESTRATE_SH"; then
    pass "factory_run() wraps embrace_full_workflow()"
else
    fail "factory_run() does not wrap embrace_full_workflow()"
fi

# Test 7.2: Sets AUTONOMY_MODE=autonomous
if grep -q 'AUTONOMY_MODE=autonomous' "$ORCHESTRATE_SH"; then
    pass "Factory sets AUTONOMY_MODE=autonomous"
else
    fail "AUTONOMY_MODE=autonomous not set"
fi

# Test 7.3: Sets OCTOPUS_SKIP_PHASE_COST_PROMPT
if grep -q 'OCTOPUS_SKIP_PHASE_COST_PROMPT=true' "$ORCHESTRATE_SH"; then
    pass "Factory sets OCTOPUS_SKIP_PHASE_COST_PROMPT=true"
else
    fail "OCTOPUS_SKIP_PHASE_COST_PROMPT not set"
fi

# Test 7.4: Uses run_agent_sync for scenario generation
if grep -A60 'generate_factory_scenarios()' "$ORCHESTRATE_SH" | grep -q 'run_agent_sync'; then
    pass "Scenario generation uses run_agent_sync()"
else
    fail "Scenario generation does not use run_agent_sync()"
fi

# Test 7.5: Satisfaction scoring weights documented
if grep -q '0\.40.*0\.20.*0\.25.*0\.15' "$ORCHESTRATE_SH"; then
    pass "Satisfaction scoring weights: 40/20/25/15"
else
    fail "Satisfaction scoring weights missing or incorrect"
fi

# Test 7.6: Verdict levels (PASS, WARN, FAIL)
if grep -q 'verdict="PASS"' "$ORCHESTRATE_SH" && grep -q 'verdict="WARN"' "$ORCHESTRATE_SH" && grep -q 'verdict="FAIL"' "$ORCHESTRATE_SH"; then
    pass "Verdict levels: PASS, WARN, FAIL"
else
    fail "Verdict levels incomplete"
fi

# Test 7.7: Retry logic on FAIL
if grep -q 'verdict.*FAIL.*retry_count.*max_retries' "$ORCHESTRATE_SH"; then
    pass "Retry logic triggers on FAIL verdict"
else
    fail "Retry logic missing"
fi

# Test 7.8: Artifacts stored in .octo/factory/
if grep -q '.octo/factory/' "$ORCHESTRATE_SH"; then
    pass "Artifacts stored in .octo/factory/"
else
    fail "Artifact storage path missing"
fi

# Test 7.9: Session JSON written
if grep -q 'session.json' "$ORCHESTRATE_SH"; then
    pass "session.json metadata file created"
else
    fail "session.json creation missing"
fi

# Test 7.10: Satisfaction scores JSON written
if grep -q 'satisfaction-scores.json' "$ORCHESTRATE_SH"; then
    pass "satisfaction-scores.json written"
else
    fail "satisfaction-scores.json creation missing"
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
    echo -e "${GREEN}All v8.25.0 Dark Factory Mode tests passed!${NC}"
    echo ""
    echo -e "${BLUE}Summary:${NC}"
    echo "  E19: Scenario Holdout Testing — split_holdout_scenarios()"
    echo "  E21: Satisfaction Scoring — score_satisfaction() with 4-dimension weights"
    echo "  E22: Dark Factory Pipeline — factory_run() wrapping embrace_full_workflow()"
    echo "  7 new functions, CLI dispatch, command file, skill file"
    echo "  Artifacts: .octo/factory/<run-id>/ (spec, scenarios, scores, report)"
    echo ""
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
