#!/usr/bin/env bash
# Compose the real validator/recovery functions in the workflow's OR-list.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Tangle retry failure propagation"

retry_propagation_fixture() (
    local scenario="$1"
    source "$PROJECT_ROOT/scripts/lib/testing.sh" || return 1
    source "$PROJECT_ROOT/scripts/lib/workflows.sh" || return 1
    RESULTS_DIR="$TEST_TMP_DIR/retry-propagation-$scenario"
    mkdir -p "$RESULTS_DIR" || return 1
    local events="$RESULTS_DIR/events" logs="$RESULTS_DIR/log"
    : > "$events"
    : > "$logs"
    local fixture_result_file="$RESULTS_DIR/codex-tangle-propagation-0.md"
    local before="$RESULTS_DIR/before" state="$RESULTS_DIR/state"
    printf 'before\n' > "$before"
    printf 'before\n' > "$state"
    local retry_behavior=fatal review_round=initial
    local expected_rc=75 expected_decisions=1 expected_sleeps=0
    local expected_reviews=0 expected_corrections=0 expected_delivery=0 expected_snapshots=0
    local validation_rc=0 rc=0 decision=none
    RED="" GREEN="" YELLOW="" NC="" DIM="" _BOX_TOP="" _BOX_BOT=""
    LOOP_UNTIL_APPROVED=true CI_MODE=true MAX_QUALITY_RETRIES=1
    OCTOPUS_ANTISYCOPHANCY=false OCTOPUS_FILE_VALIDATION=false
    OCTOPUS_TANGLE_CODE_REVIEW=true OCTOPUS_TANGLE_INK=true
    OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=bounded OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS=1
    OCTOPUS_TANGLE_CORRECTION_HARD_CAP=2
    unset TANGLE_WORKTREE_BEFORE_STATE_DIGEST OCTOPUS_TANGLE_VALIDATION_CORRECTION_FILE
    unset OCTOPUS_TANGLE_VALIDATION_CORRECTION_STATUS OCTOPUS_TANGLE_VALIDATION_CORRECTION_CHANGED

    event() { printf '%s\n' "$1" >> "$events"; }
    count() { awk -v key="$1" '$0 == key { n++ } END { print n+0 }' "$events"; }
    log() { printf '%s %s\n' "$1" "$2" >> "$logs"; }
    sleep() { event sleep; }
    record_task_metric() { :; }
    write_structured_decision() { event decision; }
    get_gate_threshold() { echo 75; }
    lock_provider() { :; }
    check_explicit_file_coverage() { :; }
    check_tangle_worktree_changes() { printf 'src/fixture.txt\n'; }
    tangle_authorized_write_scopes() { printf 'src/fixture.txt\n'; }
    tangle_authorized_read_scopes() { :; }
    tangle_changed_paths_outside_write_scopes() { :; }
    snapshot_tangle_worktree_state() { event snapshot; printf 'after\n'; }
    ink_deliver() { event delivery; }
    run_agent_sync() { event unexpected-provider; return 91; }
    evaluate_quality_branch() {
        if [[ "$1" -ge 75 ]]; then echo proceed
        elif [[ "$2" -eq 0 ]]; then echo retry
        else echo abort; fi
    }
    write_result() {
        printf '# Agent: codex\n# Task ID: tangle-propagation-0\n# Role: implementer\n# Prompt: fixture\n\n## Output\nfixture result\n\n## Status: %s\n' "$1" > "$fixture_result_file"
    }
    retry_failed_subtasks() {
        event retry
        if [[ "$retry_behavior" == completed-failure ]]; then return 0; fi
        # A late success artifact must not erase a supervision/cleanup error.
        write_result SUCCESS
        [[ "$retry_behavior" != fatal ]]
    }
    tangle_build_develop_review_context() { printf '%s/context.md\n' "$RESULTS_DIR"; }
    tangle_run_context_code_review() {
        event review
        review_round="$3"
        TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings.json"
        printf '{"findings":[]}\n' > "$TANGLE_REVIEW_FINDINGS_FILE"
    }
    tangle_review_findings_valid() { [[ -f "$1" ]]; }
    tangle_ensure_scope_contract_finding() { :; }
    tangle_review_blocking_count() {
        if [[ "$scenario" == correction-fatal || "$scenario" == quality-recovery ]] \
            && [[ "$review_round" == initial ]]; then echo 1; else echo 0; fi
    }
    tangle_findings_signature() { printf '%s\n' "$review_round"; }
    tangle_normal_finding_keys() { printf '%s\n' "$review_round"; }
    tangle_validation_signature() { printf '%s\n' "$review_round"; }
    tangle_resolved_finding_count() { echo 1; }
    tangle_apply_review_corrections() {
        event correction
        TANGLE_CORRECTION_STATUS=success TANGLE_CORRECTION_CHANGED=1
        TANGLE_CORRECTION_CONTAMINATION="" TANGLE_CORRECTION_FILE=""
        [[ "$scenario" != quality-recovery ]] || write_result SUCCESS
        return 0
    }
    write_result FAILED

    case "$scenario" in
        direct-fatal|retry-success)
            if [[ "$scenario" == retry-success ]]; then
                retry_behavior=success expected_rc=0 expected_decisions=2 expected_sleeps=1 expected_delivery=1
            fi
            validate_tangle_results propagation "Analyze fixture outputs" || validation_rc=$?
            rc="$validation_rc"
            [[ "$rc" -ne 0 ]] || ink_deliver fixture
            ;;
        changed-worktree|completed-failure)
            if [[ "$scenario" == completed-failure ]]; then
                retry_behavior=completed-failure expected_rc=1 expected_decisions=2
                expected_sleeps=1 expected_reviews=1 expected_snapshots=1
            fi
            # This is the same real wrapper -> recovery -> review chain as
            # tangle_develop, including the OR-list that disables errexit.
            tangle_validate_results_with_scope_contract propagation "Analyze fixture outputs" \
                "$before" "1. [CODING] fixture" "" "" "$state" || validation_rc=$?
            if tangle_should_attempt_contextual_review "$validation_rc" "$state"; then
                decision=allow
                tangle_contextual_review_gate propagation prompt ctx subtasks \
                    "$RESULTS_DIR/tangle-validation-propagation.md" "$before" "$validation_rc" codex \
                    "" "" "$state" || rc=$?
            else
                decision=deny
                rc="$validation_rc"
            fi
            ;;
        entry-fatal)
            expected_decisions=0
            tangle_contextual_review_gate propagation prompt ctx subtasks \
                "$RESULTS_DIR/validation.md" "$before" 75 codex || rc=$?
            ;;
        correction-fatal|quality-recovery)
            expected_reviews=1 expected_corrections=1
            local initial_rc=0
            if [[ "$scenario" == quality-recovery ]]; then
                initial_rc=1 expected_rc=0 expected_reviews=2 expected_delivery=1
            fi
            tangle_contextual_review_gate propagation prompt ctx subtasks \
                "$RESULTS_DIR/validation.md" "$before" "$initial_rc" codex \
                "" "" "$state" || rc=$?
            ;;
    esac

    printf 'scenario=%s rc=%s decisions=%s sleeps=%s reviews=%s corrections=%s delivery=%s snapshots=%s recovery=%s\n' \
        "$scenario" "$rc" "$(count decision)" "$(count sleep)" "$(count review)" \
        "$(count correction)" "$(count delivery)" "$(count snapshot)" "$decision"
    [[ "$rc" -eq "$expected_rc" && "$(count decision)" -eq "$expected_decisions" \
        && "$(count sleep)" -eq "$expected_sleeps" && "$(count review)" -eq "$expected_reviews" \
        && "$(count correction)" -eq "$expected_corrections" && "$(count delivery)" -eq "$expected_delivery" \
        && "$(count snapshot)" -eq "$expected_snapshots" && "$(count unexpected-provider)" -eq 0 ]] || return 1
    if [[ "$scenario" == changed-worktree ]]; then [[ "$decision" == deny ]] || return 1; fi
    if [[ "$scenario" == completed-failure ]]; then [[ "$decision" == allow ]] || return 1; fi
    if [[ "$scenario" != entry-fatal && "$expected_rc" -eq 75 ]]; then
        [[ -n "$FAILED_SUBTASKS" ]] && grep -c '^ERROR ' "$logs" > /dev/null || return 1
    fi
)

for scenario in direct-fatal changed-worktree entry-fatal correction-fatal retry-success completed-failure quality-recovery; do
    test_case "$scenario preserves the retry supervision contract"
    if retry_propagation_fixture "$scenario" > "$TEST_TMP_DIR/$scenario.log" 2>&1; then
        test_pass
    else
        cat "$TEST_TMP_DIR/$scenario.log"
        test_fail "retry propagation control failed; see $TEST_TMP_DIR/$scenario.log"
    fi
done
test_summary
