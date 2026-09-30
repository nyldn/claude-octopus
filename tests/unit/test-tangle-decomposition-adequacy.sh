#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "tangle decomposition adequacy"
export OCTOPUS_TANGLE_CODE_REVIEW=false
source "$PROJECT_ROOT/scripts/lib/testing.sh"
source "$WORKFLOWS"

CYAN=""; GREEN=""; MAGENTA=""; NC=""
TMUX_MODE=false
DRY_RUN=false
SUPPORTS_PARALLEL_FILE_SAFETY=false
RESULTS_DIR="$TEST_TMP_DIR/results"
WORKSPACE_DIR="$RESULTS_DIR/workspace"
mkdir -p "$WORKSPACE_DIR/.octo/agents"
boundary_probe_status=0

SCENARIO_FILE="$RESULTS_DIR/scenario"
ADEQUACY_COUNT_FILE="$RESULTS_DIR/adequacy-count"
REDECOMPOSE_COUNT_FILE="$RESULTS_DIR/redecompose-count"
RECONSIDER_COUNT_FILE="$RESULTS_DIR/reconsider-count"
RECONSIDER_ATTEMPTS_FILE="$RESULTS_DIR/reconsider-attempts"
SPAWN_FILE="$RESULTS_DIR/spawns"
DECOMPOSE_PROMPT_FILE="$RESULTS_DIR/decompose-prompt"
REDECOMPOSE_PROMPT_FILE="$RESULTS_DIR/redecompose-prompt"
RECONSIDER_PROMPT_FILE="$RESULTS_DIR/reconsider-prompt"
ADEQUACY_PROMPT_FILE="$RESULTS_DIR/adequacy-prompt"
LOG_FILE="$RESULTS_DIR/tangle.log"

log() { printf '%s %s\n' "${1:-}" "${2:-}" >> "$LOG_FILE"; }
octopus_phase_banner() { :; }
display_workflow_cost_estimate() { return 0; }
reset_provider_lockouts() { :; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
octopus_tangle_execution_boundary_probe() { [[ "$boundary_probe_status" -eq 0 ]]; }
design_review_ceremony() {
    local out_var="${3:-}"
    if [[ -n "$out_var" ]]; then
        printf -v "$out_var" '%s' 'DESIGN_RESOLUTION_MARKER: create the externally observable deliverable, preserving reversible boundaries.'
    fi
}
validate_tangle_results() { return 0; }
tangle_contextual_review_gate() { return 0; }

get_role_agent() {
    case "$1" in
        code-reviewer) printf "%s\n" "codex-review" ;;
        implementer-heavy) printf "%s\n" "codex" ;;
        architect) printf "%s\n" "claude-opus" ;;
        *) printf "%s\n" "agy" ;;
    esac
}
_octopus_profile_route_json() { printf "%s\n" "null"; }

counter_next() {
    local file="$1" n=0
    [[ -f "$file" ]] && n=$(cat "$file")
    n=$((n + 1))
    printf '%s' "$n" > "$file"
    printf '%s\n' "$n"
}

run_agent_sync() {
    local supervised="${OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED:-}"
    local prompt="$2"
    local scenario
    scenario=$(cat "$SCENARIO_FILE")
    case "$supervised" in
        tangle-dispatch-watcher)
            printf '%s' "$prompt" > "$DECOMPOSE_PROMPT_FILE"
            if [[ "$scenario" == "no-parseable" ]]; then
                printf '%s\n' "I'll explore the repository structure first."
            elif [[ "$scenario" == "planner-reject" ]]; then
                printf '%s\n' '1. [CODING] Build requested application — Files: package.json — Creates: web/ — Task: Create the app and update package.json build scripts required to run it.'
            else
                printf '%s\n' '1. [CODING] Build requested application — Files: scripts/lib/workflows.sh — Task: Build the requested externally observable application.'
            fi
            ;;
        tangle-redecompose-validation)
            counter_next "$REDECOMPOSE_COUNT_FILE" >/dev/null
            printf '%s' "$prompt" > "$REDECOMPOSE_PROMPT_FILE"
            printf '%s\n' '1. [CODING] Create requested application — Reads: scripts/lib/ — Creates: web/package.json, web/src/main.tsx — Task: Materialize the requested externally observable application.'
            ;;
        tangle-decomposition-reconsideration)
            local reconsider_n
            reconsider_n=$(counter_next "$RECONSIDER_COUNT_FILE")
            printf '%s|%s|%s\n' "$1" "${4:-}" "${5:-}" >> "$RECONSIDER_ATTEMPTS_FILE"
            printf '%s' "$prompt" > "$RECONSIDER_PROMPT_FILE"
            if [[ "$scenario" == "reconsider-fallback" && "$reconsider_n" -eq 1 ]]; then
                printf '%s\n' "I'll ground-check the reviewer claims before deciding."
            elif [[ "$scenario" == "reconsider-empty-decisions" ]]; then
                cat <<'EOF'
{"schema_version":1,"decisions":[],"decomposition":{"schema_version":1,"subtasks":[{"id":1,"kind":"coding","title":"Create requested application","reads":["scripts/lib/workflows.sh"],"files":["web/src/main.tsx"],"creates":["web/package.json"],"task":"Materialize the requested externally observable application and its runnable entry point."}]}}
EOF
            elif [[ "$scenario" == "reconsider-third-fallback" && "$reconsider_n" -le 2 ]]; then
                printf '%s\n' "I'll inspect the repo context before deciding."
            elif [[ "$scenario" == "reconsider-exhaust" ]]; then
                printf '%s\n' "I'll inspect the repo context before deciding."
            elif [[ "$scenario" == "planner-reject" ]]; then
                cat <<'EOF'
DECISIONS:
- REJECT MOVE_TO_READS: package.json — package.json must be modified to add the build/start scripts required by the requested app.
DECOMPOSITION:
1. [CODING] Build requested application — Files: package.json — Creates: web/ — Task: Create the app and modify package.json with the required build/start scripts.
EOF
            else
                cat <<'EOF'
DECISIONS:
- ACCEPT MOVE_TO_READS: scripts/lib/workflows.sh — the existing workflow is context only; the requested application belongs in a new web tree.
DECOMPOSITION:
1. [CODING] Create requested application — Reads: scripts/lib/workflows.sh — Creates: web/package.json, web/src/main.tsx — Task: Materialize the requested externally observable application.
EOF
            fi
            ;;
        tangle-decomposition-adequacy)
            local n
            n=$(counter_next "$ADEQUACY_COUNT_FILE")
            printf '%s' "$prompt" > "$ADEQUACY_PROMPT_FILE"
            case "$scenario" in
                second-fail)
                    printf '%s\n' 'VERDICT: FAIL' 'REASONS: scopes still cannot materialize the requested deliverable' 'SCOPE_REVIEW:' '- MOVE_TO_READS: scripts/lib/workflows.sh — context only'
                    ;;
                second-review-unusable)
                    if [[ "$n" -eq 1 ]]; then
                        printf '%s\n' 'VERDICT: FAIL' 'REASONS: scopes still cannot materialize the requested deliverable' 'SCOPE_REVIEW:' '- MOVE_TO_READS: scripts/lib/workflows.sh — context only'
                    else
                        printf '%s\n' 'The adequacy reviewer did not return a usable response.'
                    fi
                    ;;
                reconsider-empty-decisions)
                    if [[ "$n" -eq 1 ]]; then
                        printf '%s\n' 'VERDICT: FAIL' 'REASONS: decomposition omits the runnable entry point but current file scopes can be retained' 'SCOPE_REVIEW: NONE'
                    else
                        printf '%s\n' 'VERDICT: PASS' 'REASONS: reconsidered decomposition now materializes the runnable entry point' 'SCOPE_REVIEW: NONE'
                    fi
                    ;;
                adequacy-repair|reconsider-fallback|reconsider-third-fallback|reconsider-exhaust)
                    if [[ "$n" -eq 1 ]]; then
                        printf '%s\n' 'VERDICT: FAIL' 'REASONS: existing workflow file is context-only and the app artifact is missing' 'SCOPE_REVIEW:' '- MOVE_TO_READS: scripts/lib/workflows.sh — context only; create the app in a new tree'
                    else
                        printf '%s\n' 'VERDICT: PASS' 'REASONS: write scope is limited to the new application artifacts' 'SCOPE_REVIEW: NONE'
                    fi
                    ;;
                planner-reject)
                    if [[ "$n" -eq 1 ]]; then
                        printf '%s\n' 'VERDICT: FAIL' 'REASONS: package.json may only be context' 'SCOPE_REVIEW:' '- MOVE_TO_READS: package.json — verify whether a manifest edit is truly required'
                    elif [[ "$prompt" == *"REJECT MOVE_TO_READS: package.json"* ]]; then
                        printf '%s\n' 'VERDICT: PASS' 'REASONS: planner justified the package.json modification with a concrete build-script requirement' 'SCOPE_REVIEW: NONE'
                    else
                        printf '%s\n' 'VERDICT: FAIL' 'REASONS: planner rejection rationale was not supplied to second review' 'SCOPE_REVIEW:' '- MOVE_TO_READS: package.json — unresolved'
                    fi
                    ;;
                *)
                    printf '%s\n' 'VERDICT: PASS' 'REASONS: decomposition is adequate' 'SCOPE_REVIEW: NONE'
                    ;;
            esac
            ;;
        *)
            printf '%s\n' 'unexpected run_agent_sync call' >&2
            return 1
            ;;
    esac
}

spawn_agent_capture_pid() {
    local task_id="$3"
    printf '%s\n' "$task_id" >> "$SPAWN_FILE"
    printf '0\n' > "$WORKSPACE_DIR/.octo/agents/${task_id}.done"
    printf '%s\n' "$$"
}

reset_scenario() {
    printf '%s' "$1" > "$SCENARIO_FILE"
    printf '0' > "$ADEQUACY_COUNT_FILE"
    printf '0' > "$REDECOMPOSE_COUNT_FILE"
    printf '0' > "$RECONSIDER_COUNT_FILE"
    : > "$RECONSIDER_ATTEMPTS_FILE"
    : > "$SPAWN_FILE"
    : > "$DECOMPOSE_PROMPT_FILE"
    : > "$REDECOMPOSE_PROMPT_FILE"
    : > "$RECONSIDER_PROMPT_FILE"
    : > "$ADEQUACY_PROMPT_FILE"
    : > "$LOG_FILE"
}

run_case() {
    local scenario="$1"
    reset_scenario "$scenario"
    tangle_develop 'Build the requested externally observable application with a usable entry point.' > "$RESULTS_DIR/${scenario}.out" 2>&1
}

load_reconsider_attempts() {
    local attempt
    attempts=()
    while IFS= read -r attempt; do
        attempts+=("$attempt")
    done < "$RECONSIDER_ATTEMPTS_FILE"
}

test_case "adequacy verdict parser accepts only explicit PASS"
if tangle_decomposition_adequacy_verdict $'VERDICT: PASS\nREASONS: ok' && ! tangle_decomposition_adequacy_verdict $'VERDICT: FAIL\nREASONS: no' && ! tangle_decomposition_adequacy_verdict 'looks good'; then
    test_pass
else
    test_fail "adequacy verdict parser did not fail closed"
fi

test_case "adequacy reasons parser preserves multiline reviewer guidance"
multiline=$'VERDICT: FAIL\n\nREASONS:\n- missing requested artifact\n- scope cannot contain deliverable'
reasons=$(tangle_decomposition_adequacy_reasons "$multiline")
if [[ "$reasons" == *"missing requested artifact"* ]] && [[ "$reasons" == *"scope cannot contain deliverable"* ]]; then
    test_pass
else
    test_fail "multiline adequacy reasons were lost: $reasons"
fi

test_case "reasoning subtasks require exactly one non-empty Task clause"
valid_reasoning='1. [REASONING] Review the implementation — Task: inspect the requested behavior.'
spaced_reasoning='1. [REASONING] Review the implementation —  Task: inspect the requested behavior.'
missing_task='1. [REASONING] Review the implementation — Reads: scripts/lib/workflows.sh'
empty_task='1. [REASONING] Review the implementation — Task:'
repeated_task='1. [REASONING] Review the implementation — Task: inspect it — Task: and report.'
if tangle_validate_subtask_task_clauses "$valid_reasoning" && \
   tangle_validate_subtask_task_clauses "$spaced_reasoning" && \
   ! tangle_validate_subtask_task_clauses "$missing_task" && \
   ! tangle_validate_subtask_task_clauses "$empty_task" && \
   ! tangle_validate_subtask_task_clauses "$repeated_task"; then
    test_pass
else
    test_fail "reasoning Task clause validation did not fail closed"
fi

test_case "initial decomposer receives design-review synthesis"
reset_scenario "adequacy-repair"
run_case "adequacy-repair"
if grep -q 'DESIGN_RESOLUTION_MARKER' "$DECOMPOSE_PROMPT_FILE"; then
    test_pass
else
    test_fail "design-review synthesis was not present in decomposition prompt"
fi

test_case "non-decomposition output triggers redecompose rather than repair"
run_case "no-parseable"
if [[ "$(cat "$REDECOMPOSE_COUNT_FILE")" -eq 1 ]] && grep -q "Previous non-usable output:" "$REDECOMPOSE_PROMPT_FILE" && ! grep -q "Reformatted subtasks:" "$RESULTS_DIR/no-parseable.out"; then
    test_pass
else
    test_fail "unparseable output was not routed through first-principles redecomposition"
fi

test_case "semantic FAIL triggers one planner reconsideration and then spawns"
run_case "adequacy-repair"
if [[ "$(cat "$ADEQUACY_COUNT_FILE")" -eq 2 ]] && [[ "$(cat "$RECONSIDER_COUNT_FILE")" -eq 1 ]] && [[ "$(cat "$REDECOMPOSE_COUNT_FILE")" -eq 0 ]] && [[ -s "$SPAWN_FILE" ]] && grep -q 'ACCEPT MOVE_TO_READS: scripts/lib/workflows.sh' "$RESULTS_DIR/adequacy-repair.out"; then
    test_pass
else
    test_fail "adequacy FAIL did not perform one bounded planner reconsideration before spawn"
fi

test_case "planner may reject reviewer scope advice with explicit rationale"
run_case "planner-reject"
if [[ "$(cat "$ADEQUACY_COUNT_FILE")" -eq 2 ]] && [[ "$(cat "$RECONSIDER_COUNT_FILE")" -eq 1 ]] && [[ -s "$SPAWN_FILE" ]] && grep -q 'REJECT MOVE_TO_READS: package.json' "$RESULTS_DIR/planner-reject.out" && grep -q 'REJECT MOVE_TO_READS: package.json' "$ADEQUACY_PROMPT_FILE"; then
    test_pass
else
    test_fail "planner rejection was not preserved as advisory adjudication for second review"
fi

test_case "planner reconsideration may materialize an empty decisions list when scope review is empty"
run_case "reconsider-empty-decisions"
if [[ "$(cat "$ADEQUACY_COUNT_FILE")" -eq 2 ]] && [[ "$(cat "$RECONSIDER_COUNT_FILE")" -eq 1 ]] && [[ -s "$SPAWN_FILE" ]]; then
    test_pass
else
    test_fail "empty-but-valid reconsideration decisions incorrectly aborted the implementation"
fi

test_case "unusable planner reconsideration advances through configured fallback chain"
run_case "reconsider-fallback"
first_attempt=$(sed -n '1p' "$RECONSIDER_ATTEMPTS_FILE")
second_attempt=$(sed -n '2p' "$RECONSIDER_ATTEMPTS_FILE")
if [[ "$(cat "$ADEQUACY_COUNT_FILE")" -eq 2 ]] && [[ "$(cat "$RECONSIDER_COUNT_FILE")" -eq 2 ]] && [[ -s "$SPAWN_FILE" ]] && \
   [[ "$first_attempt" == "agy|researcher|tangle" ]] && [[ "$second_attempt" == "codex-review|researcher|tangle" ]] && \
   grep -q "Fallback chain 'default': agy failed (semantic-invalid); trying next candidate" "$LOG_FILE"; then
    test_pass
else
    test_fail "semantic planner fallback did not use the configured chain while preserving researcher/tangle semantics"
fi

test_case "two unusable planner responses advance from code-reviewer routing to implementer-heavy routing"
run_case "reconsider-third-fallback"
load_reconsider_attempts
if [[ "$(cat "$ADEQUACY_COUNT_FILE")" -eq 2 ]] && [[ "$(cat "$RECONSIDER_COUNT_FILE")" -eq 3 ]] && [[ -s "$SPAWN_FILE" ]] && \
   [[ "${attempts[0]:-}" == 'agy|researcher|tangle' ]] && \
   [[ "${attempts[1]:-}" == "codex-review|researcher|tangle" ]] && \
   [[ "${attempts[2]:-}" == "codex|researcher|tangle" ]] && \
   [[ "${#attempts[@]}" -eq 3 ]]; then
    test_pass
else
    test_fail "planner fallback did not advance through primary -> code-reviewer -> implementer-heavy routing"
fi

test_case "configured fallback chain exhausts through architect and aborts before spawn"
reset_scenario "reconsider-exhaust"
status=0
tangle_develop 'Build the requested externally observable application with a usable entry point.' > "$RESULTS_DIR/reconsider-exhaust.out" 2>&1 || status=$?
load_reconsider_attempts
if [[ "$status" -ne 0 ]] && [[ "$(cat "$RECONSIDER_COUNT_FILE")" -eq 4 ]] && [[ ! -s "$SPAWN_FILE" ]] && \
   [[ "${attempts[0]:-}" == 'agy|researcher|tangle' ]] && \
   [[ "${attempts[1]:-}" == "codex-review|researcher|tangle" ]] && \
   [[ "${attempts[2]:-}" == "codex|researcher|tangle" ]] && \
   [[ "${attempts[3]:-}" == "claude-opus|researcher|tangle" ]] && \
   grep -q "Fallback chain 'default' exhausted without a usable result" "$LOG_FILE"; then
    test_pass
else
    test_fail "configured fallback chain did not exhaust through architect before failing closed"
fi

test_case "second semantic FAIL aborts before implementation spawn"
reset_scenario "second-fail"
status=0
tangle_develop 'Build the requested externally observable application with a usable entry point.' > "$RESULTS_DIR/second-fail.out" 2>&1 || status=$?
if [[ "$status" -ne 0 ]] && [[ "$(cat "$ADEQUACY_COUNT_FILE")" -eq 2 ]] && [[ "$(cat "$RECONSIDER_COUNT_FILE")" -eq 1 ]] && [[ ! -s "$SPAWN_FILE" ]] && grep -q 'remains semantically inadequate' "$LOG_FILE"; then
    test_pass
else
    test_fail "second adequacy FAIL did not fail closed before spawn"
fi


test_case "adaptive mode continues after bounded reconsideration remains semantically imperfect"
export OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive
reset_scenario "second-fail"
adaptive_status=0
tangle_develop 'Build the requested externally observable application with a usable entry point.' > "$RESULTS_DIR/second-fail-adaptive.out" 2>&1 || adaptive_status=$?
unset OCTOPUS_TANGLE_WRITE_SCOPE_MODE
if [[ "$adaptive_status" -eq 0 ]] && [[ "$(cat "$ADEQUACY_COUNT_FILE")" -eq 2 ]] && [[ "$(cat "$RECONSIDER_COUNT_FILE")" -eq 1 ]] && [[ -s "$SPAWN_FILE" ]] && grep -q 'continuing in adaptive write-scope mode' "$LOG_FILE"; then
    test_pass
else
    test_fail "adaptive mode did not continue to implementation spawn after second semantic FAIL"
fi


test_case "adaptive mode fails closed when the second adequacy review is unusable"
export OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive
reset_scenario "second-review-unusable"
unusable_status=0
tangle_develop 'Build the requested externally observable application with a usable entry point.' > "$RESULTS_DIR/second-review-unusable.out" 2>&1 || unusable_status=$?
unset OCTOPUS_TANGLE_WRITE_SCOPE_MODE
if [[ "$unusable_status" -ne 0 ]] && [[ "$(cat "$RECONSIDER_COUNT_FILE")" -eq 1 ]] && [[ ! -s "$SPAWN_FILE" ]] && grep -q 'Second decomposition adequacy review did not complete' "$LOG_FILE"; then
    test_pass
else
    test_fail "adaptive mode continued after the second adequacy review failed to complete"
fi


test_case "adaptive mode fails closed before spawn without an execution boundary"
export OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive
export OCTOPUS_TANGLE_EXECUTION_BOUNDARY=true
boundary_probe_status=1
reset_scenario "second-fail"
boundary_status=0
tangle_develop 'Build the requested externally observable application with a usable entry point.' > "$RESULTS_DIR/second-fail-no-boundary.out" 2>&1 || boundary_status=$?
boundary_probe_status=0
unset OCTOPUS_TANGLE_WRITE_SCOPE_MODE
if [[ "$boundary_status" -eq 125 ]] && [[ ! -s "$SPAWN_FILE" ]] && grep -q 'no enforceable filesystem boundary is available' "$LOG_FILE" && [[ -z "${OCTOPUS_TANGLE_EXECUTION_BOUNDARY:-}" ]]; then
    test_pass
else
    test_fail "adaptive mode spawned or left the execution-boundary flag enabled without an enforceable boundary"
fi


test_case "duplicate Creates clauses are rejected"
duplicate_creates='1. [CODING] Build UI — Files: package.json — Creates: web/ — Creates: tmp/ — Task: build UI.'
if tangle_validate_parallel_write_scopes "$duplicate_creates" >/dev/null 2>&1; then
    test_fail "duplicate Creates clauses were accepted"
else
    test_pass
fi

test_case "adequacy response validator accepts structured PASS and FAIL but rejects prose"
if tangle_decomposition_adequacy_response_valid $'VERDICT: PASS\nREASONS: ok\nSCOPE_REVIEW: NONE' && \
   tangle_decomposition_adequacy_response_valid $'VERDICT: FAIL\nREASONS: scope issue\nSCOPE_REVIEW:\n- MOVE_TO_READS: foo — context only' && \
   ! tangle_decomposition_adequacy_response_valid $'VERDICT: PASS\nVERDICT: FAIL\nREASONS: contradictory\nSCOPE_REVIEW: NONE' && \
   ! tangle_decomposition_adequacy_response_valid 'looks fine'; then
    test_pass
else
    test_fail "adequacy response validator did not preserve PASS/FAIL semantics"
fi

test_summary
