#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$ROOT/scripts/lib/dispatch.sh"
source "$ROOT/scripts/lib/workflows.sh"
log_file="$TEST_TMP_DIR/reconsideration-json.log"
log() { printf '%s %s\n' "$1" "$2" >> "$log_file"; }
test_suite "tangle reconsideration JSON v1 contract"

adequacy=$'VERDICT: FAIL\nREASONS:\n- missing ownership\nSCOPE_REVIEW:\n- ADD_WRITE: app/build.gradle.kts — own build file\n- MOVE_TO_READS: docs/plan.md — context only'
expected="$(tangle_reconsideration_expected_scope_review_json "$adequacy")"
export TANGLE_RECONSIDERATION_EXPECTED_SCOPE_REVIEW_JSON="$expected"
valid='{"schema_version":1,"decisions":[{"action":"add_write","path":"app/build.gradle.kts","decision":"accept","reason":"The build task owns this file."},{"action":"move_to_reads","path":"docs/plan.md","decision":"accept","reason":"The plan is context only."}],"decomposition":{"schema_version":1,"subtasks":[{"id":1,"kind":"reasoning","title":"Audit","reads":["docs/plan.md"],"files":[],"creates":[],"task":"Audit the contract."},{"id":2,"kind":"coding","title":"Implement","reads":["docs/plan.md"],"files":["app/build.gradle.kts"],"creates":[],"task":"Implement and test."}]}}'

test_case "valid reconsideration JSON v1 is accepted with exact coverage"
if tangle_reconsideration_response_valid "$valid"; then test_pass; else test_fail "valid reconsideration rejected"; fi

test_case "nested decomposition renders into existing wire format"
wire="$(tangle_reconsideration_subtasks "$valid")"
if tangle_decomposition_wire_output_usable "$wire" && [[ "$wire" == *"2. [CODING] Implement"* && "$wire" == *"Files: app/build.gradle.kts"* ]]; then test_pass; else test_fail "nested decomposition did not render: $wire"; fi

test_case "decisions render human-readable adjudication"
decisions="$(tangle_reconsideration_decisions "$valid")"
if [[ "$decisions" == *"ACCEPT ADD_WRITE: app/build.gradle.kts"* && "$decisions" == *"ACCEPT MOVE_TO_READS: docs/plan.md"* ]]; then test_pass; else test_fail "decision rendering wrong: $decisions"; fi

test_case "missing adequacy recommendation fails coverage"
missing='{"schema_version":1,"decisions":[{"action":"add_write","path":"app/build.gradle.kts","decision":"accept","reason":"Own it."}],"decomposition":{"schema_version":1,"subtasks":[{"id":1,"kind":"coding","title":"Implement","reads":[],"files":["app/build.gradle.kts"],"creates":[],"task":"Implement."}]}}'
if tangle_reconsideration_response_valid "$missing"; then test_fail "missing recommendation accepted"; else test_pass; fi

test_case "extra recommendation identity fails coverage"
extra='{"schema_version":1,"decisions":[{"action":"add_write","path":"app/build.gradle.kts","decision":"accept","reason":"Own it."},{"action":"move_to_reads","path":"docs/plan.md","decision":"accept","reason":"Context."},{"action":"remove_write","path":"src/extra.ts","decision":"reject","reason":"Not requested."}],"decomposition":{"schema_version":1,"subtasks":[{"id":1,"kind":"coding","title":"Implement","reads":[],"files":["app/build.gradle.kts"],"creates":[],"task":"Implement."}]}}'
if tangle_reconsideration_response_valid "$extra"; then test_fail "extra recommendation accepted"; else test_pass; fi

test_case "duplicate decision identity fails closed"
dupe='{"schema_version":1,"decisions":[{"action":"add_write","path":"app/build.gradle.kts","decision":"accept","reason":"One."},{"action":"add_write","path":"app/build.gradle.kts","decision":"reject","reason":"Two."},{"action":"move_to_reads","path":"docs/plan.md","decision":"accept","reason":"Context."}],"decomposition":{"schema_version":1,"subtasks":[{"id":1,"kind":"coding","title":"Implement","reads":[],"files":["app/build.gradle.kts"],"creates":[],"task":"Implement."}]}}'
if tangle_reconsideration_response_valid "$dupe"; then test_fail "duplicate decision accepted"; else test_pass; fi

test_case "invalid nested decomposition fails closed"
bad_nested='{"schema_version":1,"decisions":[{"action":"add_write","path":"app/build.gradle.kts","decision":"accept","reason":"Own."},{"action":"move_to_reads","path":"docs/plan.md","decision":"accept","reason":"Context."}],"decomposition":{"schema_version":1,"subtasks":[{"id":1,"kind":"coding","title":"Bad","reads":[],"files":[],"creates":[],"task":"No write scope."}]}}'
if tangle_reconsideration_response_valid "$bad_nested"; then test_fail "invalid nested decomposition accepted"; else test_pass; fi

test_case "glob decision path fails closed"
bad_glob='{"schema_version":1,"decisions":[{"action":"add_write","path":"app/**","decision":"accept","reason":"Too broad."}],"decomposition":{"schema_version":1,"subtasks":[{"id":1,"kind":"coding","title":"Implement","reads":[],"files":["app/build.gradle.kts"],"creates":[],"task":"Implement."}]}}'
export TANGLE_RECONSIDERATION_EXPECTED_SCOPE_REVIEW_JSON='[{"action":"add_write","path":"app/**"}]'
if tangle_reconsideration_json_output_usable "$bad_glob"; then test_fail "glob decision accepted"; else test_pass; fi
export TANGLE_RECONSIDERATION_EXPECTED_SCOPE_REVIEW_JSON="$expected"

test_case "whitespace-only decision reason fails closed"
blank_reason='''{"schema_version":1,"decisions":[{"action":"add_write","path":"app/build.gradle.kts","decision":"accept","reason":"   "},{"action":"move_to_reads","path":"docs/plan.md","decision":"accept","reason":"Context."}],"decomposition":{"schema_version":1,"subtasks":[{"id":1,"kind":"coding","title":"Implement","reads":[],"files":["app/build.gradle.kts"],"creates":[],"task":"Implement."}]}}'''
if tangle_reconsideration_json_output_usable "$blank_reason"; then test_fail "blank reason accepted"; else test_pass; fi

test_case "fenced JSON is accepted"
fenced=$'```json\n'"$valid"$'\n```'
if tangle_reconsideration_response_valid "$fenced"; then test_pass; else test_fail "fenced JSON rejected"; fi

test_case "legacy textual reconsideration remains accepted but deprecated"
legacy=$'DECISIONS:\n- ACCEPT ADD_WRITE: app/build.gradle.kts — legacy\nDECOMPOSITION:\n1. [CODING] Legacy — Files: app/build.gradle.kts — Task: implement'
: > "$log_file"
if tangle_reconsideration_response_valid "$legacy" && tangle_reconsideration_decisions "$legacy" >/dev/null && grep -q 'Deprecated Tangle textual reconsideration compatibility path used' "$log_file"; then test_pass; else test_fail "legacy reconsideration compatibility missing"; fi

test_case "reconsideration budget widens researcher only when scoped env is set"
export OCTOPUS_CONTEXT_BUDGET=12000 OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=1024 OCTOPUS_CONTEXT_OVERHEAD_TOKENS=512 OCTOPUS_OVERSIZE_STRATEGY=fail
probe=$(printf 'x%.0s' {1..30000})
unset OCTOPUS_TANGLE_RECONSIDERATION_CONTEXT_BUDGET_RATIO
base=0; enforce_context_budget "$probe" researcher codex tangle >/dev/null 2>&1 || base=$?
export OCTOPUS_TANGLE_RECONSIDERATION_CONTEXT_BUDGET_RATIO=90
unmarked=0; enforce_context_budget "$probe" researcher codex tangle >/dev/null 2>&1 || unmarked=$?
export TANGLE_RECONSIDERATION_ACTIVE=1
wide=0; enforce_context_budget "$probe" researcher codex tangle >/dev/null 2>&1 || wide=$?
unset TANGLE_RECONSIDERATION_ACTIVE OCTOPUS_TANGLE_RECONSIDERATION_CONTEXT_BUDGET_RATIO OCTOPUS_CONTEXT_BUDGET OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS OCTOPUS_CONTEXT_OVERHEAD_TOKENS OCTOPUS_OVERSIZE_STRATEGY
if [[ "$base" -ne 0 && "$unmarked" -ne 0 && "$wide" -eq 0 ]]; then test_pass; else test_fail "reconsideration budget not scoped correctly: base=$base unmarked=$unmarked wide=$wide"; fi

test_case "invalid reconsideration ratio fails closed"
export OCTOPUS_CONTEXT_BUDGET=12000 OCTOPUS_TANGLE_RECONSIDERATION_CONTEXT_BUDGET_RATIO=101 OCTOPUS_OVERSIZE_STRATEGY=fail TANGLE_RECONSIDERATION_ACTIVE=1
status=0; enforce_context_budget small researcher codex tangle >/dev/null 2>&1 || status=$?
unset OCTOPUS_CONTEXT_BUDGET OCTOPUS_TANGLE_RECONSIDERATION_CONTEXT_BUDGET_RATIO OCTOPUS_OVERSIZE_STRATEGY TANGLE_RECONSIDERATION_ACTIVE
[[ "$status" -ne 0 ]] && test_pass || test_fail "ratio above 100 accepted"

unset TANGLE_RECONSIDERATION_EXPECTED_SCOPE_REVIEW_JSON
test_summary
