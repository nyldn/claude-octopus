#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$ROOT/scripts/lib/dispatch.sh"
source "$ROOT/scripts/lib/workflows.sh"
log_file="$TEST_TMP_DIR/adequacy-json.log"
log() { printf '%s %s\n' "$1" "$2" >> "$log_file"; }
test_suite "tangle adequacy JSON v1 contract"

pass_json='{"schema_version":1,"verdict":"pass","reasons":["Decomposition is adequate."],"scope_review":[]}'
fail_json='{"schema_version":1,"verdict":"fail","reasons":["The artifact has no owner."],"scope_review":[{"action":"add_write","path":"app/build.gradle.kts","reason":"The build artifact needs an explicit owner."}]}'

test_case "valid adequacy PASS JSON is accepted"
tangle_adequacy_json_output_usable "$pass_json" && test_pass || test_fail "valid PASS JSON rejected"

test_case "valid adequacy FAIL JSON is accepted"
tangle_adequacy_json_output_usable "$fail_json" && test_pass || test_fail "valid FAIL JSON rejected"

test_case "JSON review renders into historical internal format"
rendered="$(tangle_materialize_adequacy_response "$fail_json")"
if [[ "$rendered" == *"VERDICT: FAIL"* && "$rendered" == *"REASONS:"* && "$rendered" == *"ADD_WRITE: app/build.gradle.kts"* ]] && ! tangle_decomposition_adequacy_verdict "$rendered"; then
  test_pass
else
  test_fail "JSON review did not render correctly: $rendered"
fi

test_case "fenced adequacy JSON is repaired deterministically"
fenced=$'```json\n'"$pass_json"$'\n```'
tangle_adequacy_json_output_usable "$fenced" && test_pass || test_fail "fenced JSON rejected"

test_case "single JSON object surrounded by prose is repaired"
wrapped=$'Review result follows.\n'"$pass_json"$'\nEnd.'
tangle_adequacy_json_output_usable "$wrapped" && test_pass || test_fail "wrapped JSON rejected"

test_case "multiple adequacy JSON objects fail closed"
tangle_adequacy_json_output_usable "$pass_json $fail_json" && test_fail "multiple objects accepted" || test_pass

test_case "PASS without scope_review is accepted as an empty review"
pass_without_scope='{"schema_version":1,"verdict":"pass","reasons":["Decomposition is adequate."]}'
rendered="$(tangle_materialize_adequacy_response "$pass_without_scope")"
if [[ "$rendered" == *"VERDICT: PASS"* && "$rendered" == *"SCOPE_REVIEW: NONE"* ]]; then
  test_pass
else
  test_fail "PASS without scope_review rejected: $rendered"
fi

test_case "FAIL without scope_review still fails closed"
bad='{"schema_version":1,"verdict":"fail","reasons":["The artifact has no owner."]}'
tangle_adequacy_json_output_usable "$bad" && test_fail "FAIL without scope_review accepted" || test_pass

test_case "PASS cannot contain scope actions"
bad='{"schema_version":1,"verdict":"pass","reasons":["Looks good."],"scope_review":[{"action":"add_write","path":"src/a.ts","reason":"Contradiction."}]}'
tangle_adequacy_json_output_usable "$bad" && test_fail "PASS with scope action accepted" || test_pass

test_case "scope action rejects glob paths"
bad='{"schema_version":1,"verdict":"fail","reasons":["Needs scope."],"scope_review":[{"action":"add_write","path":"src/**","reason":"Too broad."}]}'
tangle_adequacy_json_output_usable "$bad" && test_fail "glob scope accepted" || test_pass

test_case "scope action rejects dot-segment traversal"
bad='{"schema_version":1,"verdict":"fail","reasons":["Needs scope."],"scope_review":[{"action":"add_write","path":"src/../.env","reason":"Unsafe path."}]}'
tangle_adequacy_json_output_usable "$bad" && test_fail "dot-segment path accepted" || test_pass

test_case "scope action permits a normalized leading dot slash"
good='{"schema_version":1,"verdict":"fail","reasons":["Needs scope."],"scope_review":[{"action":"add_write","path":"./src/a.ts","reason":"Concrete path."}]}'
tangle_adequacy_json_output_usable "$good" && test_pass || test_fail "leading dot slash rejected"

test_case "scope action rejects protected git paths"
bad='{"schema_version":1,"verdict":"fail","reasons":["Needs scope."],"scope_review":[{"action":"add_write","path":".GIT/hooks/pre-commit","reason":"Protected path."}]}'
tangle_adequacy_json_output_usable "$bad" && test_fail "protected git path accepted" || test_pass

test_case "schema version rejects JSON booleans"
bad='{"schema_version":true,"verdict":"pass","reasons":["Looks good."],"scope_review":[]}'
tangle_adequacy_json_output_usable "$bad" && test_fail "boolean schema version accepted" || test_pass

test_case "unknown fields fail closed"
bad='{"schema_version":1,"verdict":"pass","reasons":["Ok."],"scope_review":[],"extra":true}'
tangle_adequacy_json_output_usable "$bad" && test_fail "unknown field accepted" || test_pass

test_case "legacy textual review remains accepted but deprecated"
legacy=$'VERDICT: PASS\nREASONS: adequate\nSCOPE_REVIEW: NONE'
: > "$log_file"
if tangle_decomposition_adequacy_response_valid "$legacy" && tangle_materialize_adequacy_response "$legacy" >/dev/null && grep -q 'Deprecated Tangle textual adequacy compatibility path used' "$log_file"; then
  test_pass
else
  test_fail "legacy compatibility path missing or unlogged"
fi

test_case "materialized JSON review is structurally valid without the deprecation warning"
: > "$log_file"
rendered="$(tangle_materialize_adequacy_response "$pass_json")"
if tangle_adequacy_legacy_response_valid "$rendered" && ! grep -q 'Deprecated Tangle textual adequacy' "$log_file"; then
  test_pass
else
  test_fail "materialized JSON review rejected or logged as deprecated"
fi

test_case "architect adequacy ratio raises only the tangle architect budget"
export OCTOPUS_CONTEXT_BUDGET=12000
export OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=1024
export OCTOPUS_CONTEXT_OVERHEAD_TOKENS=512
export OCTOPUS_OVERSIZE_STRATEGY=fail
probe=$(printf 'x%.0s' {1..24000})
unset OCTOPUS_TANGLE_ADEQUACY_CONTEXT_BUDGET_RATIO
base_status=0
enforce_context_budget "$probe" architect codex tangle >/dev/null 2>&1 || base_status=$?
export OCTOPUS_TANGLE_ADEQUACY_CONTEXT_BUDGET_RATIO=80
override_status=0
enforce_context_budget "$probe" architect codex tangle >/dev/null 2>&1 || override_status=$?
unset OCTOPUS_TANGLE_ADEQUACY_CONTEXT_BUDGET_RATIO OCTOPUS_CONTEXT_BUDGET OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS OCTOPUS_CONTEXT_OVERHEAD_TOKENS OCTOPUS_OVERSIZE_STRATEGY
if [[ "$base_status" -ne 0 && "$override_status" -eq 0 ]]; then
  test_pass
else
  test_fail "adequacy ratio did not widen only the scoped architect budget: base=$base_status override=$override_status"
fi

test_case "invalid adequacy ratio fails closed"
export OCTOPUS_CONTEXT_BUDGET=12000 OCTOPUS_TANGLE_ADEQUACY_CONTEXT_BUDGET_RATIO=101 OCTOPUS_OVERSIZE_STRATEGY=fail
status=0
enforce_context_budget "small" architect codex tangle >/dev/null 2>&1 || status=$?
unset OCTOPUS_CONTEXT_BUDGET OCTOPUS_TANGLE_ADEQUACY_CONTEXT_BUDGET_RATIO OCTOPUS_OVERSIZE_STRATEGY
[[ "$status" -ne 0 ]] && test_pass || test_fail "ratio above 100 was accepted"

test_case "adequacy fallback failure status is preserved"
saved_fallback_chain_function="$(declare -f run_agent_sync_fallback_chain)"
run_agent_sync_fallback_chain() { return 37; }
status=0
tangle_decomposition_adequacy_review "Original task" "Proposed decomposition" >/dev/null 2>&1 || status=$?
eval "$saved_fallback_chain_function"
[[ "$status" -eq 37 ]] && test_pass || test_fail "fallback failure status changed to $status"

test_summary
