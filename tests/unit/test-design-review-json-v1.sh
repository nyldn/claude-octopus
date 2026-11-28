#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "design review JSON v1 contracts"
export HOME="$TEST_TMP_DIR/home"
export PLUGIN_DIR="$ROOT"
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
mkdir -p "$HOME" "$WORKSPACE_DIR"
source "$ROOT/scripts/lib/quality.sh"
LOG_FILE="$TEST_TMP_DIR/design-review-json.log"
log() { printf '%s %s\n' "$1" "$2" >> "$LOG_FILE"; }

seat='{"schema_version":1,"approach":["Keep boundaries explicit."],"dependencies":["Existing API contract."],"risks":[{"risk":"State leak.","mitigation":"Isolate cache by user."}],"testing":["Run focused unit tests."],"integration":["Preserve pairing flow."]}'
synthesis='{"schema_version":1,"conflicts":["Ordering differs."],"gaps":["Artifact ownership."],"resolution":"Preserve the contract and integrate auth before pairing.","risks":[{"risk":"Migration drift.","mitigation":"Validate end to end."}],"decisions":["Keep one integration owner."]}'

test_case "valid seat JSON materializes canonically"
materialized="$(design_review_materialize_seat "$seat")"
if jq -e '((.schema_version>=1)) and ((.approach|length)==1)' <<<"$materialized" >/dev/null && [[ "$(design_review_seat_source_format "$seat")" == json-v1 ]]; then test_pass; else test_fail "seat JSON not canonical"; fi

test_case "valid synthesis JSON materializes canonically"
materialized_s="$(design_review_materialize_synthesis "$synthesis")"
if jq -e '((.schema_version>=1)) and ((.resolution|length)>0)' <<<"$materialized_s" >/dev/null && [[ "$(design_review_synthesis_source_format "$synthesis")" == json-v1 ]]; then test_pass; else test_fail "synthesis JSON not canonical"; fi

test_case "canonical synthesis retains structured policy findings"
with_findings="$(jq -c '.policy_findings = [{"source":"AGENTS.md","quote":"Keep the public API stable."}]' <<< "$synthesis")"
if materialized_s="$(design_review_materialize_synthesis "$with_findings")" &&
    jq -e '.policy_findings == [{"source":"AGENTS.md","quote":"Keep the public API stable."}]' <<< "$materialized_s" >/dev/null; then
    test_pass
else
    test_fail "policy findings did not survive synthesis validation"
fi

test_case "boolean schema_version is rejected"
bool_seat='''{"schema_version":true,"approach":["Keep boundaries explicit."],"dependencies":[],"risks":[],"testing":[],"integration":[]}'''
if design_review_approach_valid "$bool_seat"; then test_fail "boolean schema_version accepted"; else test_pass; fi

test_case "numeric schema_version is accepted and canonicalized"
numeric_seat='''{"schema_version":1.0,"approach":["Keep boundaries explicit."],"dependencies":[],"risks":[],"testing":[],"integration":[]}'''
numeric_synthesis='''{"schema_version":1.0,"conflicts":[],"gaps":[],"resolution":"Keep boundaries explicit.","risks":[],"decisions":[]}'''
canonical_seat="$(design_review_materialize_seat "$numeric_seat")"
canonical_synthesis="$(design_review_materialize_synthesis "$numeric_synthesis")"
if jq -e '(.schema_version == 1) and (.schema_version|type == "number")' <<<"$canonical_seat" >/dev/null && jq -e '(.schema_version == 1) and (.schema_version|type == "number")' <<<"$canonical_synthesis" >/dev/null; then test_pass; else test_fail "numeric schema_version was not canonicalized"; fi

test_case "schema and helper agree on array maximum"
long_seat='''{"schema_version":1,"approach":["A"],"dependencies":["1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20","21"],"risks":[],"testing":[],"integration":[]}'''
if design_review_approach_valid "$long_seat"; then test_fail "21-item array accepted"; else test_pass; fi

test_case "fenced seat JSON is accepted"
fenced=$'```json\n'"$seat"$'\n```'
design_review_approach_valid "$fenced" && test_pass || test_fail "fenced seat JSON rejected"

test_case "invalid JSON attempt is not wrapped as legacy prose"
bad='Here is JSON: {"schema_version":1,"approach":[]}'
if design_review_approach_valid "$bad"; then test_fail "invalid JSON was wrapped as legacy"; else test_pass; fi

test_case "legacy seat prose is converted to JSON"
legacy='Architecture: preserve existing contracts and isolate the change behind a narrow interface. Risks: validate malformed state and provider failures. Testing: run focused unit coverage and integration verification before delivery.'
wrapped="$(design_review_materialize_seat "$legacy")"
if jq -e '(.schema_version>=1) and (.approach[0]|contains("Architecture:"))' <<<"$wrapped" >/dev/null && [[ "$(design_review_seat_source_format "$legacy")" == legacy-text ]]; then test_pass; else test_fail "legacy seat was not wrapped"; fi

test_case "legacy synthesis prose is converted to JSON"
legacy_s='CONFLICTS: Reviewers differ on sequencing but agree on preserving the contract. GAPS: Explicit artifact ownership and retry behavior require validation. RESOLUTION: Keep the existing architecture, assign an integration owner, and validate the complete flow before delivery.'
wrapped_s="$(design_review_materialize_synthesis "$legacy_s")"
if jq -e '(.schema_version>=1) and (.resolution|contains("RESOLUTION:"))' <<<"$wrapped_s" >/dev/null && [[ "$(design_review_synthesis_source_format "$legacy_s")" == legacy-text ]]; then test_pass; else test_fail "legacy synthesis was not wrapped"; fi

test_case "seat recovery stores JSON even for legacy provider output"
run_agent_sync_consultative() { printf '%s\n' "$legacy"; }
design_review_candidate_agents() { :; }
out=""; agent=""
design_review_run_seat_with_recovery provider design-code-reviewer prompt 0 provider out agent
if jq -e '((.schema_version>=1)) and ((.approach|length)==1)' <<<"$out" >/dev/null && [[ "$agent" == provider ]] && grep -q 'Deprecated free-text design-review seat' "$LOG_FILE"; then test_pass; else test_fail "seat recovery did not canonicalize JSON"; fi

test_case "synthesis recovery stores JSON even for legacy provider output"
run_agent_sync_consultative() { printf '%s\n' "$legacy_s"; }
out=""; agent=""
design_review_run_synthesis_with_recovery provider prompt 0 provider out agent
if jq -e '((.schema_version>=1)) and ((.resolution|length)>0)' <<<"$out" >/dev/null && [[ "$agent" == provider ]] && grep -q 'Deprecated free-text design-review synthesis' "$LOG_FILE"; then test_pass; else test_fail "synthesis recovery did not canonicalize JSON"; fi

test_case "human synthesis renderer is derived from JSON"
human="$(design_review_json_helper human-synthesis "$synthesis")"
if [[ "$human" == *"Resolution: Preserve the contract"* && "$human" == *"Conflicts: Ordering differs."* ]]; then test_pass; else test_fail "human rendering wrong: $human"; fi

test_summary
