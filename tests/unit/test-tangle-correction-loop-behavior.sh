#!/usr/bin/env bash
# Behavioral tests for tangle_contextual_review_gate (PR #593 correction loop).
# Drives the extracted loop with stubbed review/correction functions and asserts
# round counts and exit codes — complements the static grep assertions in
# test-tangle-context-review-loop.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle correction loop behavior"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export RESULTS_DIR="$TMP_DIR/results"
mkdir -p "$RESULTS_DIR"

# ── Harness ────────────────────────────────────────────────────────────────
# run_gate <blocker-count-sequence...>
# Each stubbed review round pops the next count from the sequence. Correction
# and validation always "succeed with changes". Prints "rounds=<n> rc=<n>".
run_gate() {
    local seq="$*"
    bash -c '
        set -u
        log() { :; }
        octo_event_emit() { :; }
        write_agent_status() { :; }
        record_agents_batch_complete() { :; }
        ink_deliver() { :; }
        run_agent_sync() { :; }
        octopus_agent_override() { echo "codex"; }

        COUNTS=($1)
        IDX_FILE="$RESULTS_DIR/count-idx"
        echo 0 > "$IDX_FILE"
        CORRECTION_CALLS=0

        source "$2/scripts/lib/workflows.sh" 2>/dev/null

        tangle_build_develop_review_context() { echo "$RESULTS_DIR/ctx-$7.md"; }
        tangle_run_context_code_review() {
            TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings-$3.json"
            echo "{\"findings\":[]}" > "$TANGLE_REVIEW_FINDINGS_FILE"
            return 0
        }
        # Stub state lives in a file: these stubs run inside command
        # substitutions, so in-shell variable increments would be lost.
        tangle_review_blocking_count() {
            local idx c
            idx=$(cat "$IDX_FILE")
            c="${COUNTS[$idx]:-0}"
            if [[ $idx -lt $(( ${#COUNTS[@]} - 1 )) ]]; then
                echo $((idx + 1)) > "$IDX_FILE"
            fi
            echo "$c"
        }
        tangle_findings_signature() { echo "sig-$(cat "$IDX_FILE")"; }
        tangle_validation_signature() { echo "vsig"; }
        tangle_apply_review_corrections() {
            CORRECTION_CALLS=$((CORRECTION_CALLS + 1))
            TANGLE_CORRECTION_STATUS="done"
            TANGLE_CORRECTION_CHANGED=1
            TANGLE_CORRECTION_CONTAMINATION=""
            TANGLE_CORRECTION_FILE="$RESULTS_DIR/corr-$CORRECTION_CALLS.md"
            return 0
        }
        validate_tangle_results() { return 0; }

        rc=0
        tangle_contextual_review_gate tg "prompt" "ctx" "subtasks" \
            "$RESULTS_DIR/validation.md" "$RESULTS_DIR/wt.txt" 0 codex || rc=$?
        echo "rounds=$CORRECTION_CALLS rc=$rc"
    ' _ "$seq" "$PROJECT_ROOT"
}

# ── Cases ──────────────────────────────────────────────────────────────────

test_case "zero initial blockers: no correction rounds, exit 0"
out=$(run_gate "0")
if [[ "$out" == "rounds=0 rc=0" ]]; then
    test_pass
else
    test_fail "expected rounds=0 rc=0, got '$out'"
fi

test_case "decreasing blockers converge to zero: exit 0 after 3 rounds"
out=$(run_gate "3 2 1 0")
if [[ "$out" == "rounds=3 rc=0" ]]; then
    test_pass
else
    test_fail "expected rounds=3 rc=0, got '$out'"
fi

test_case "static blockers trip convergence guard (default 3 no-progress rounds)"
out=$(OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS=3 run_gate "5 5 5 5 5 5 5 5 5 5")
if [[ "$out" == "rounds=3 rc=1" ]]; then
    test_pass
else
    test_fail "expected rounds=3 rc=1, got '$out'"
fi

test_case "hard cap stops improving-but-never-zero loop"
# counts keep improving (each round is a new best), so the convergence guard
# never fires — only the absolute ceiling can stop this.
out=$(OCTOPUS_TANGLE_CORRECTION_HARD_CAP=4 run_gate "20 19 18 17 16 15 14 13 12 11 10 9 8")
if [[ "$out" == "rounds=4 rc=1" ]]; then
    test_pass
else
    test_fail "expected rounds=4 rc=1, got '$out'"
fi

test_case "hard cap closes the convergence-guard-disabled foot-gun"
out=$(OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS=0 OCTOPUS_TANGLE_CORRECTION_HARD_CAP=5 run_gate "9 8 7 6 5 4 4 4 4 4 4 4 4 4 4")
if [[ "$out" == "rounds=5 rc=1" ]]; then
    test_pass
else
    test_fail "expected rounds=5 rc=1, got '$out'"
fi

test_case "default hard cap is 10 when unset"
out=$(OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS=0 run_gate "30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15")
if [[ "$out" == "rounds=10 rc=1" ]]; then
    test_pass
else
    test_fail "expected rounds=10 rc=1, got '$out'"
fi

test_case "bounded mode round cap still enforced"
out=$(OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=bounded OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS=2 run_gate "8 7 6 5 4 3")
if [[ "$out" == "rounds=2 rc=1" ]]; then
    test_pass
else
    test_fail "expected rounds=2 rc=1, got '$out'"
fi

test_summary
