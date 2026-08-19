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
        REVIEW_RCS=(${REVIEW_RC_SEQUENCE:-})
        CORRECTION_STATUSES=(${CORRECTION_STATUS_SEQUENCE:-})
        KEY_SEQ="${FINDING_KEY_SEQUENCE:-}"
        IDX_FILE="$RESULTS_DIR/count-idx"
        REVIEW_IDX_FILE="$RESULTS_DIR/review-idx"
        KEY_IDX_FILE="$RESULTS_DIR/key-idx"
        VALIDATE_CALLS_FILE="$RESULTS_DIR/validate-calls"
        REVIEW_CALLS_FILE="$RESULTS_DIR/context-review-calls"
        echo 0 > "$IDX_FILE"
        echo 0 > "$REVIEW_IDX_FILE"
        echo 0 > "$KEY_IDX_FILE"
        echo 0 > "$VALIDATE_CALLS_FILE"
        echo 0 > "$REVIEW_CALLS_FILE"
        CORRECTION_CALLS=0
        CORRECTION_STRATEGIES=()

        source "$2/scripts/lib/workflows.sh" 2>/dev/null

        tangle_build_develop_review_context() { echo "$RESULTS_DIR/ctx-$7.md"; }
        tangle_run_context_code_review() {
            local ridx rc calls
            calls=$(cat "$REVIEW_CALLS_FILE")
            echo $((calls + 1)) > "$REVIEW_CALLS_FILE"
            TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings-$3.json"
            echo "{\"findings\":[]}" > "$TANGLE_REVIEW_FINDINGS_FILE"
            ridx=$(cat "$REVIEW_IDX_FILE")
            rc="${REVIEW_RCS[$ridx]:-0}"
            echo $((ridx + 1)) > "$REVIEW_IDX_FILE"
            return "$rc"
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
        tangle_normal_finding_keys() {
            local idx c i
            idx=$(cat "$KEY_IDX_FILE")
            echo $((idx + 1)) > "$KEY_IDX_FILE"
            if [[ -n "$KEY_SEQ" ]]; then
                printf "%s\n" "$KEY_SEQ" | sed -n "$((idx + 1))p" | tr "," "\n"
            else
                c="${COUNTS[$idx]:-0}"
                for ((i=1; i<=c; i++)); do echo "same-$i"; done
            fi
        }
        tangle_validation_signature() { echo "vsig"; }
        tangle_apply_review_corrections() {
            CORRECTION_STRATEGIES+=("${6:-}")
            local status="${CORRECTION_STATUSES[$((CORRECTION_CALLS))]:-done}"
            CORRECTION_CALLS=$((CORRECTION_CALLS + 1))
            TANGLE_CORRECTION_STATUS="$status"
            TANGLE_CORRECTION_CONTAMINATION=""
            TANGLE_CORRECTION_FILE="$RESULTS_DIR/corr-$CORRECTION_CALLS.md"
            case "$status" in
                failed-no-progress)
                    TANGLE_CORRECTION_CHANGED=0
                    return 1
                    ;;
                interrupted-partial)
                    TANGLE_CORRECTION_CHANGED=0
                    return 1
                    ;;
                *)
                    TANGLE_CORRECTION_CHANGED=1
                    return 0
                    ;;
            esac
        }
        validate_tangle_results() {
            local calls
            calls=$(cat "$VALIDATE_CALLS_FILE")
            echo $((calls + 1)) > "$VALIDATE_CALLS_FILE"
            return 0
        }

        rc=0
        tangle_contextual_review_gate tg "prompt" "ctx" "subtasks" \
            "$RESULTS_DIR/validation.md" "$RESULTS_DIR/wt.txt" 0 codex || rc=$?
        if [[ "${ASSERT_STRATEGIES:-0}" == "1" ]]; then
            echo "rounds=$CORRECTION_CALLS rc=$rc strategies=${CORRECTION_STRATEGIES[*]} validate=$(cat "$VALIDATE_CALLS_FILE") reviews=$(cat "$REVIEW_CALLS_FILE")"
        else
            echo "rounds=$CORRECTION_CALLS rc=$rc"
        fi
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

test_case "partial review warning with actionable blockers continues correction loop"
out=$(REVIEW_RC_SEQUENCE="0 1 0" run_gate "2 1 0")
if [[ "$out" == "rounds=2 rc=0" ]]; then
    test_pass
else
    test_fail "expected rounds=2 rc=0, got '$out'"
fi

test_case "partial review warning with zero blockers remains fatal"
out=$(REVIEW_RC_SEQUENCE="0 1" run_gate "1 0")
if [[ "$out" == "rounds=1 rc=1" ]]; then
    test_pass
else
    test_fail "expected rounds=1 rc=1, got '$out'"
fi

test_case "single failed-no-progress round consumes convergence budget and retries"
out=$(ASSERT_STRATEGIES=1 CORRECTION_STATUS_SEQUENCE="failed-no-progress done" OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS=3 run_gate "2 1 0")
if [[ "$out" == "rounds=3 rc=0 strategies=delta single-finding delta validate=2 reviews=3" ]]; then
    test_pass
else
    test_fail "expected failed-no-progress retry to recover, got '$out'"
fi

test_case "three consecutive failed-no-progress rounds stop at convergence limit"
out=$(ASSERT_STRATEGIES=1 CORRECTION_STATUS_SEQUENCE="failed-no-progress failed-no-progress failed-no-progress done" OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS=3 run_gate "2 1 0")
if [[ "$out" == "rounds=3 rc=1 strategies=delta single-finding single-finding validate=0 reviews=1" ]]; then
    test_pass
else
    test_fail "expected three failed-no-progress rounds to stop, got '$out'"
fi

test_case "interrupted correction remains terminal"
out=$(ASSERT_STRATEGIES=1 CORRECTION_STATUS_SEQUENCE="interrupted-partial done" OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS=3 run_gate "2 1 0")
if [[ "$out" == "rounds=1 rc=1 strategies=delta validate=0 reviews=1" ]]; then
    test_pass
else
    test_fail "expected interrupted correction to remain terminal, got '$out'"
fi

test_case "static blockers trip convergence guard (default 3 no-progress rounds)"
out=$(OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS=3 run_gate "5 5 5 5 5 5 5 5 5 5")
if [[ "$out" == "rounds=3 rc=1" ]]; then
    test_pass
else
    test_fail "expected rounds=3 rc=1, got '$out'"
fi

test_case "resolved blocker identities reset convergence even without a new best count"
# Best count reaches 3, then later reviews expose different blockers. Each round
# resolves at least one blocker from the immediately previous review, so the
# no-progress watchdog must not stop before the hard cap / eventual convergence.
out=$(FINDING_KEY_SEQUENCE=$'a,b,c,d,e,f,g\na,b,c\nd,e,f,g,h,i,j\nd,e,f,g,h,i,j\ne,f,g,h,i' OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS=3 OCTOPUS_TANGLE_CORRECTION_HARD_CAP=5 run_gate "7 3 7 7 5 0")
if [[ "$out" == "rounds=5 rc=0" ]]; then
    test_pass
else
    test_fail "expected identity-aware progress to continue to zero, got '$out'"
fi

test_case "rewritten count without resolved identities still trips convergence guard"
out=$(FINDING_KEY_SEQUENCE=$'a,b,c,d,e\na,b,c,d,e\na,b,c,d,e\na,b,c,d,e' OCTOPUS_TANGLE_CONVERGENCE_NO_PROGRESS_ROUNDS=3 run_gate "5 5 5 5 5")
if [[ "$out" == "rounds=3 rc=1" ]]; then
    test_pass
else
    test_fail "expected unchanged blocker identities to stop at 3 rounds, got '$out'"
fi

finding_identity_probe() {
    local findings_json="$1"
    local findings_file
    findings_file="$(mktemp "$TMP_DIR/findings.XXXXXX")"
    printf '%s\n' "$findings_json" > "$findings_file"
    bash -c 'source "$1/scripts/lib/workflows.sh" 2>/dev/null; tangle_normal_finding_keys "$2"' \
        _ "$PROJECT_ROOT" "$findings_file"
}

test_case "case-distinct paths remain distinct blocker identities"
keys="$(finding_identity_probe '{"findings":[{"severity":"normal","file":"Src/API.ts","title":"Bug"},{"severity":"normal","file":"Src/api.ts","title":"Bug"}]}')"
if [[ "$(printf '%s\n' "$keys" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 2 ]]; then
    test_pass
else
    test_fail "case-distinct paths collapsed: $(tr '\n' ';' <<< "$keys")"
fi

test_case "delimiter-containing file and title tuples cannot collide"
previous_keys="$(finding_identity_probe '{"findings":[{"severity":"normal","file":"src/a|b.ts","title":"c"},{"severity":"normal","file":"src/a","title":"b.ts|c"}]}')"
current_keys="$(finding_identity_probe '{"findings":[{"severity":"normal","file":"src/a","title":"b.ts|c"}]}')"
resolved_count="$(bash -c 'source "$1/scripts/lib/workflows.sh" 2>/dev/null; tangle_resolved_finding_count "$2" "$3"' \
    _ "$PROJECT_ROOT" "$previous_keys" "$current_keys")"
if [[ "$(printf '%s\n' "$previous_keys" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 2 && "$resolved_count" -eq 1 ]]; then
    test_pass
else
    test_fail "delimiter tuples collided: previous=$(tr '\n' ';' <<< "$previous_keys") resolved=$resolved_count"
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
