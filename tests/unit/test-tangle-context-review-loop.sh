#!/usr/bin/env bash
# Static tests for tangle contextual review/correction loop wiring.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle contextual review loop"

WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
HELP="$PROJECT_ROOT/scripts/lib/usage-help.sh"

assert_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    test_case "$label"
    if grep -q "$pattern" "$file"; then
        test_pass
    else
        test_fail "missing pattern: $pattern"
    fi
}

assert_contains "$WORKFLOWS" "tangle_build_develop_review_context" "tangle builds review context"
assert_contains "$WORKFLOWS" "tangle_run_context_code_review" "tangle runs contextual code review"
assert_contains "$WORKFLOWS" "contextFile" "review profile passes contextFile"
assert_contains "$WORKFLOWS" "plan-conformance" "review focus includes plan conformance"
assert_contains "$WORKFLOWS" "tangle_apply_review_corrections" "tangle applies review corrections"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE" "correction loop supports explicit bounded mode"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_CORRECTION_STALL_WINDOW" "correction loop uses stall watchdog"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_DEADLINE:-0" "initial tangle deadline defaults to no absolute timeout"
assert_contains "$WORKFLOWS" "decompose_prompt" "decomposition prompt is present"
assert_contains "$WORKFLOWS" '"$decompose_prompt" 0' "decomposition runs without absolute timeout"
assert_contains "$WORKFLOWS" "_tangle_max_wait" "initial tangle deadline is optional"
assert_contains "$WORKFLOWS" "failed but left partial writes" "partial writes continue to validation/review"
assert_contains "$WORKFLOWS" 'run_agent_sync "$correction_agent" "$correction_prompt" 0' "corrections run without absolute timeout"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_CODE_REVIEW" "code review gate is toggleable"
assert_contains "$WORKFLOWS" "Contextual code review warning" "review warnings are blocking"
assert_contains "$WORKFLOWS" "No changes found to review" "legacy no-diff message is detected"
assert_contains "$WORKFLOWS" "not treating review warning/no-diff as improvement" "no-diff review is blocking"
assert_contains "$WORKFLOWS" "Skipping ink/deliver because tangle validation gate returned non-zero" "ink is skipped when validation fails"
assert_contains "$HELP" "Contextual code review" "develop help documents contextual review"
assert_contains "$HELP" "OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE" "develop help documents bounded mode"
assert_contains "$HELP" "OCTOPUS_TANGLE_CORRECTION_STALL_WINDOW" "develop help documents stall window"
assert_contains "$WORKFLOWS" "OCTOPUS_INK_REVIEW_TIMEOUT:-0" "ink review has no wall timeout by default"

REVIEW="$PROJECT_ROOT/scripts/lib/review.sh"
assert_contains "$REVIEW" "\"warning\":\"No changes found to review\"" "review no-diff writes warning"
assert_contains "$REVIEW" "return 1" "review no-diff returns non-zero"

QUALITY="$PROJECT_ROOT/scripts/lib/quality.sh"
assert_contains "$QUALITY" "OCTOPUS_DESIGN_REVIEW_TIMEOUT:-0" "design review uses no wall timeout by default"
assert_contains "$QUALITY" "timeout=none" "design review reports no wall timeout"

HEARTBEAT="$PROJECT_ROOT/scripts/lib/heartbeat.sh"
assert_contains "$HEARTBEAT" "timeout_secs=0 means no absolute timeout" "timeout zero disables absolute timeout"
SPAWN="$PROJECT_ROOT/scripts/lib/spawn.sh"
assert_contains "$SPAWN" "TIMEOUT=0 means no absolute timeout" "spawn respects TIMEOUT=0"
assert_contains "$SPAWN" "OCTOPUS_GEMINI_TIMEOUT" "gemini timeout can be explicitly overridden"

TESTING="$PROJECT_ROOT/scripts/lib/testing.sh"
assert_contains "$TESTING" "OCTOPUS_TANGLE_VALIDATION_CORRECTION_FILE" "post-correction validation overlay is wired"
assert_contains "$TESTING" "Static Subtask Rate Before Correction Overlay" "post-correction validation reports static subtask rate"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_VALIDATION_CORRECTION_CHANGED" "correction loop passes validation overlay context"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS" "correction loop has convergence guard"
assert_contains "$WORKFLOWS" "tangle_review_blocking_count" "review blocking count helper exists"
assert_contains "$WORKFLOWS" "fail closed" "malformed review findings fail closed"
assert_contains "$WORKFLOWS" "OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED" "unbounded agent calls document external supervision"
assert_contains "$WORKFLOWS" "stat -f '%z'" "correction progress size uses BSD stat fallback"
assert_contains "$WORKFLOWS" "defaulting to 1 round" "bounded correction mode has implicit cap"
assert_contains "$WORKFLOWS" "tangle_process_is_active_non_zombie" "tangle watcher treats zombies as terminal"
assert_contains "$WORKFLOWS" "exited or became zombie without completion marker" "tangle watcher logs zombie missing-marker grace"
assert_contains "$WORKFLOWS" "OCTOPUS_TANGLE_CONVERGENCE_VALIDATION_PROGRESS" "convergence guard does not treat validation rerenders as progress by default"
assert_contains "$WORKFLOWS" "validation signature changed but blocker best did not improve" "convergence guard logs ignored validation-only movement"
assert_contains "$WORKFLOWS" "interrupted-partial" "correction loop stops on interrupted partial writes"
assert_contains "$WORKFLOWS" "rc=" "interrupted correction logs provider exit code"

test_summary
