#!/usr/bin/env bash
# Regression coverage for the fail-closed changed-scope local CI gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "changed-scope local CI selection"

CI_CHANGED="$PROJECT_ROOT/scripts/ci-changed.sh"
RUN_ALL="$PROJECT_ROOT/tests/run-all-tests.sh"

plan_for() {
    bash "$CI_CHANGED" --list --changed "$1" 2>&1 || true
}

test_case "changed-scope entrypoint and manifest exist"
if [[ -x "$CI_CHANGED" && -f "$PROJECT_ROOT/tests/changed-scope.tsv" ]]; then
    test_pass
else
    test_fail "missing executable scripts/ci-changed.sh or tests/changed-scope.tsv"
fi

test_case "review-only changes select review suites without Council"
review_plan="$(plan_for 'scripts/lib/review.sh')"
if grep -q '^Mode: focused$' <<< "$review_plan" &&
   grep -q 'tests/unit/test-review-aggregation-robustness.sh' <<< "$review_plan" &&
   ! grep -q 'test-council-command.sh' <<< "$review_plan"; then
    test_pass
else
    test_fail "review selection was not focused and auditable: $review_plan"
fi

test_case "shared orchestrator changes select the full matrix"
orchestrator_plan="$(plan_for 'scripts/orchestrate.sh')"
if grep -q '^Mode: full$' <<< "$orchestrator_plan" &&
   grep -q 'scripts/orchestrate.sh' <<< "$orchestrator_plan"; then
    test_pass
else
    test_fail "orchestrator change did not fail closed: $orchestrator_plan"
fi

test_case "generator changes select the full matrix"
generator_plan="$(plan_for 'scripts/sync-readme.py')"
if grep -q '^Mode: full$' <<< "$generator_plan" &&
   grep -q 'scripts/sync-readme.py' <<< "$generator_plan"; then
    test_pass
else
    test_fail "generator change did not fail closed: $generator_plan"
fi

test_case "selector and manifest changes select the full matrix"
selector_plan="$(plan_for 'scripts/ci-changed.sh')"
manifest_plan="$(plan_for 'tests/changed-scope.tsv')"
if grep -q '^Mode: full$' <<< "$selector_plan" &&
   grep -q '^Mode: full$' <<< "$manifest_plan"; then
    test_pass
else
    test_fail "gate implementation changes did not fail closed"
fi

test_case "unknown paths select the full matrix"
unknown_plan="$(plan_for 'scripts/lib/new-unmapped-surface.sh')"
if grep -q '^Mode: full$' <<< "$unknown_plan" &&
   grep -q 'unmapped' <<< "$unknown_plan"; then
    test_pass
else
    test_fail "unknown change did not fail closed: $unknown_plan"
fi

test_case "missing comparison bases select the full matrix"
missing_base_plan="$(bash "$CI_CHANGED" --list --base 'refs/heads/does-not-exist' 2>&1 || true)"
if grep -q '^Mode: full$' <<< "$missing_base_plan" &&
   grep -q 'no valid comparison base' <<< "$missing_base_plan"; then
    test_pass
else
    test_fail "missing comparison base did not fail closed: $missing_base_plan"
fi

test_case "automatic base selection never narrows to the previous commit"
if ! grep -q 'BASE_REF="HEAD~1"' "$CI_CHANGED"; then
    test_pass
else
    test_fail "automatic HEAD~1 fallback can omit earlier branch commits"
fi

test_case "known harness-local artifacts do not force the full matrix"
harness_plan="$(plan_for '.beads.gate.lock')"
if grep -q '^Mode: focused$' <<< "$harness_plan" &&
   grep -q 'tests/unit/test-suite-reachability.sh' <<< "$harness_plan" &&
   ! grep -q 'unmapped changed path' <<< "$harness_plan"; then
    test_pass
else
    test_fail "known harness-local artifact changed the source-test scope: $harness_plan"
fi

test_case "changed test suites select themselves"
self_plan="$(plan_for 'tests/unit/test-ci-changed.sh')"
if grep -q '^Mode: focused$' <<< "$self_plan" &&
   grep -q 'tests/unit/test-ci-changed.sh' <<< "$self_plan"; then
    test_pass
else
    test_fail "changed unit suite was not selected: $self_plan"
fi

test_case "model-resolution changes select provider suites without Council"
model_plan="$(plan_for 'scripts/lib/model-resolver.sh')"
if grep -q '^Mode: focused$' <<< "$model_plan" &&
   grep -q 'tests/unit/test-resolve-model.sh' <<< "$model_plan" &&
   grep -q 'tests/unit/test-agy-provider.sh' <<< "$model_plan" &&
   ! grep -q 'test-council-command.sh' <<< "$model_plan"; then
    test_pass
else
    test_fail "model-resolution selection was not proportional: $model_plan"
fi

test_case "v10 owned surfaces select their focused contract suites"
run_contract_plan="$(plan_for 'scripts/lib/run-contract.sh')"
doctor_plan="$(plan_for 'scripts/lib/doctor.sh')"
registry_plan="$(plan_for 'scripts/lib/provider-registry.sh')"
observability_plan="$(plan_for 'scripts/lib/error-tracking.sh')"
routing_plan="$(plan_for 'data/routing/v10-eval-cases.json')"
if grep -q '^Mode: focused$' <<< "$run_contract_plan" &&
   grep -q 'test-run-contract-v10.sh' <<< "$run_contract_plan" &&
   grep -q 'test-v10-cancellation-recovery.sh' <<< "$run_contract_plan" &&
   grep -q '^Mode: focused$' <<< "$doctor_plan" &&
   grep -q 'test-doctor-v10.sh' <<< "$doctor_plan" &&
   grep -q '^Mode: focused$' <<< "$registry_plan" &&
   grep -q 'test-provider-registry.sh' <<< "$registry_plan" &&
   grep -q '^Mode: focused$' <<< "$observability_plan" &&
   grep -q 'test-run-observability-v10.sh' <<< "$observability_plan" &&
   grep -q '^Mode: focused$' <<< "$routing_plan" &&
   grep -q 'test-routing-evals-v10.sh' <<< "$routing_plan"; then
    test_pass
else
    test_fail "v10 focused mappings were incomplete or unsafe"
fi

test_case "shared v10 lifecycle libraries retain the full matrix"
sync_plan="$(plan_for 'scripts/lib/agent-sync.sh')"
heartbeat_plan="$(plan_for 'scripts/lib/heartbeat.sh')"
if grep -q '^Mode: full$' <<< "$sync_plan" &&
   grep -q '^Mode: full$' <<< "$heartbeat_plan"; then
    test_pass
else
    test_fail "shared lifecycle mappings narrowed below the full matrix"
fi

test_case "selection output is deterministic"
first_plan="$(bash "$CI_CHANGED" --list --changed 'scripts/lib/review.sh' --changed 'scripts/lib/model-resolver.sh' 2>&1 || true)"
second_plan="$(bash "$CI_CHANGED" --list --changed 'scripts/lib/model-resolver.sh' --changed 'scripts/lib/review.sh' 2>&1 || true)"
if [[ "$first_plan" == "$second_plan" ]]; then
    test_pass
else
    test_fail "identical changed files produced different plans"
fi

test_case "one unsafe file makes a mixed change set full"
mixed_plan="$(bash "$CI_CHANGED" --list --changed 'scripts/lib/review.sh' --changed 'scripts/orchestrate.sh' 2>&1 || true)"
if grep -q '^Mode: full$' <<< "$mixed_plan"; then
    test_pass
else
    test_fail "mixed safe and unsafe changes did not fail closed: $mixed_plan"
fi

test_case "test runner accepts one explicit suite without defaulting to all"
runner_list="$(bash "$RUN_ALL" --list --suite=unit/test-ci-changed.sh 2>&1 || true)"
if grep -q 'Discovered:.*1 test suites' <<< "$runner_list" &&
   grep -q 'unit/test-ci-changed.sh' <<< "$runner_list" &&
   ! grep -q 'unit/test-council-command.sh' <<< "$runner_list"; then
    test_pass
else
    test_fail "explicit suite selection expanded to the default matrix: $runner_list"
fi

test_case "test harness disables production Tangle worktree isolation by default"
preserved_tangle_setting="$(OCTOPUS_TANGLE_RUN_WORKTREE=true bash -c 'source "$1"; printf "%s" "$OCTOPUS_TANGLE_RUN_WORKTREE"' _ "$PROJECT_ROOT/tests/helpers/test-framework.sh")"
if [[ "${OCTOPUS_TANGLE_RUN_WORKTREE:-}" == "false" ]] &&
   [[ "$preserved_tangle_setting" == "true" ]] &&
   grep -q '^unset OCTOPUS_TANGLE_RUN_WORKTREE' "$PROJECT_ROOT/tests/unit/test-tangle-run-worktree.sh"; then
    test_pass
else
    test_fail "ordinary unit suites can still create production-style Tangle worktrees"
fi

test_case "test runner reports its slowest suites"
timing_output="$(bash "$RUN_ALL" --suite=unit/test-suite-reachability.sh 2>&1 || true)"
if grep -q '^Slowest suites:' <<< "$timing_output" &&
   grep -Eq '^[[:space:]]+[0-9]+s[[:space:]]+unit/test-suite-reachability\.sh$' <<< "$timing_output"; then
    test_pass
else
    test_fail "runner did not emit actionable per-suite timing: $timing_output"
fi

test_case "test runner rejects non-suite explicit paths"
invalid_runner_output="$TEST_TMP_DIR/invalid-runner.out"
if bash "$RUN_ALL" --list --suite=changed-scope.tsv > "$invalid_runner_output" 2>&1; then
    invalid_runner_rc=0
else
    invalid_runner_rc=$?
fi
if [[ "$invalid_runner_rc" -eq 2 ]] &&
   grep -q 'Explicit suite must be' "$invalid_runner_output" &&
   ! grep -q 'test-council-command.sh' "$invalid_runner_output"; then
    test_pass
else
    test_fail "invalid explicit path did not fail safely: rc=$invalid_runner_rc"
fi

test_case "Makefile and agent instructions expose proportional gates"
if grep -q '^ci-changed:' "$PROJECT_ROOT/Makefile" &&
   grep -q 'make ci-changed' "$PROJECT_ROOT/RTK.md" &&
   grep -q 'make ci-changed' "$PROJECT_ROOT/AGENTS.md" &&
   grep -q 'make ci-changed' "$PROJECT_ROOT/CLAUDE.md" &&
   grep -q 'tests/changed-scope.tsv' "$PROJECT_ROOT/docs/DEVELOPER.md"; then
    test_pass
else
    test_fail "changed-scope command or iterative versus final guidance is missing"
fi

test_case "GitHub CI retains authoritative full coverage"
if grep -Fq 'run: ./tests/run-all.sh unit --shard-index=${{ matrix.shard_index }} --shard-count=${{ matrix.shard_count }}' "$PROJECT_ROOT/.github/workflows/test.yml" &&
   grep -q 'run: make test-integration' "$PROJECT_ROOT/.github/workflows/test.yml" &&
   ! grep -q 'make ci-changed' "$PROJECT_ROOT/.github/workflows/test.yml"; then
    test_pass
else
    test_fail "GitHub CI no longer runs the full unit matrix and integration job"
fi

test_summary
