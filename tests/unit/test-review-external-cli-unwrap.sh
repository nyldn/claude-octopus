#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "review parses trust-wrapped external CLI output"

REVIEW_SH="$PROJECT_ROOT/scripts/lib/review.sh"
VALIDATION_SH="$PROJECT_ROOT/scripts/lib/validation.sh"

log() { :; }
source "$REVIEW_SH" >/dev/null 2>&1 || true
source "$VALIDATION_SH" >/dev/null 2>&1 || true

findings_document='{"findings":[{"file":"src/app.ts","line":3,"severity":"normal","category":"correctness","title":"Kept","detail":"Null dereference on empty input","confidence":0.9,"verdict":"confirmed"}]}'
wrapped_document="$(OCTOPUS_SECURITY_V870=true wrap_cli_output codex "$findings_document")"

test_case "the trust wrapper alone makes a valid findings document unparseable"
if [[ "$(printf '%s\n' "$wrapped_document" | head -n 1)" == '<external-cli-output provider="codex" '* ]] &&
   [[ "$(printf '%s\n' "$wrapped_document" | tail -n 1)" == '</external-cli-output>' ]] &&
   ! printf '%s' "$wrapped_document" | review_normalize_findings_json >/dev/null 2>&1; then
    test_pass
else
    test_fail "unexpected wrapper shape: $wrapped_document"
fi

test_case "a wrapped single findings document normalizes after unwrapping"
unwrapped_document="$(printf '%s\n' "$wrapped_document" | review_strip_external_cli_wrapper 2>/dev/null || true)"
normalized_document="$(printf '%s' "$unwrapped_document" | review_normalize_findings_json 2>/dev/null || true)"
if [[ "$unwrapped_document" == "$findings_document" ]] &&
   [[ "$(printf '%s' "$normalized_document" | jq -r '[.findings[] | "\(.title)=\(.verdict)"] | join(",")' 2>/dev/null || true)" == "Kept=confirmed" ]]; then
    test_pass
else
    test_fail "wrapped document did not normalize: unwrapped=[$unwrapped_document] normalized=[$normalized_document]"
fi

test_case "blank lines around the wrapper do not prevent unwrapping"
padded_unwrapped="$(printf '\n%s\n\n' "$wrapped_document" | review_strip_external_cli_wrapper 2>/dev/null || true)"
if [[ "$(printf '%s' "$padded_unwrapped" | review_normalize_findings_json 2>/dev/null | jq -r '.findings[0].title' 2>/dev/null || true)" == "Kept" ]]; then
    test_pass
else
    test_fail "padded wrapper was not removed: [$padded_unwrapped]"
fi

test_case "wrapped invalid findings JSON still fails normalization after unwrapping"
invalid_ok=true
invalid_payloads=(
    '{"findings":[{"title":"Unterminated"}'
    $'{"findings":[{"title":"First"}]}\n{"findings":[{"title":"Second"}]}'
    '{"findings":[null]}'
)
for invalid_payload in "${invalid_payloads[@]}"; do
    wrapped_invalid="$(OCTOPUS_SECURITY_V870=true wrap_cli_output codex "$invalid_payload")"
    unwrapped_invalid="$(printf '%s\n' "$wrapped_invalid" | review_strip_external_cli_wrapper 2>/dev/null || true)"
    if [[ "$unwrapped_invalid" != "$invalid_payload" ]] ||
       printf '%s' "$unwrapped_invalid" | review_normalize_findings_json >/dev/null 2>&1; then
        invalid_ok=false
        invalid_failure="payload=[$invalid_payload] unwrapped=[$unwrapped_invalid]"
    fi
done
if [[ "$invalid_ok" == true ]]; then
    test_pass
else
    test_fail "invalid wrapped payload was accepted or not unwrapped: $invalid_failure"
fi

test_case "unwrapped provider output passes through unchanged"
fenced_document="$(printf '%s\n%s\n%s' '```json' "$findings_document" '```')"
passthrough_ok=true
for passthrough_input in "$findings_document" "$fenced_document"; do
    passthrough_output="$(printf '%s\n' "$passthrough_input" | review_strip_external_cli_wrapper 2>/dev/null || printf 'helper-failed')"
    if [[ "$passthrough_output" != "$passthrough_input" ]]; then
        passthrough_ok=false
        passthrough_failure="input=[$passthrough_input] output=[$passthrough_output]"
    fi
done
if [[ "$passthrough_ok" == true ]] &&
   [[ "$(printf '%s' "$findings_document" | review_normalize_findings_json 2>/dev/null | jq -r '.findings[0].title' 2>/dev/null || true)" == "Kept" ]]; then
    test_pass
else
    test_fail "unwrapped output changed: ${passthrough_failure:-normalization failed}"
fi

test_case "only one exact enclosing wrapper is removed"
near_miss_inputs=(
    $'<external-cli-output provider="codex" trust="untrusted">\n{"findings":[]}'
    $'{"findings":[]}\n</external-cli-output>'
    $'Preface\n<external-cli-output provider="codex">\n{"findings":[]}\n</external-cli-output>'
    $'<external-cli-output provider="codex">\n{"findings":[]}\n</external-cli-output>\nTrailer'
    $'<external-cli-output-shadow provider="codex">\n{"findings":[]}\n</external-cli-output>'
    $'<external-cli-output provider="codex">{"findings":[]}\n</external-cli-output>'
    $'<external-cli-output provider="codex">\n{"findings":[]}\n</external-cli-output> '
)
near_miss_ok=true
for near_miss_input in "${near_miss_inputs[@]}"; do
    near_miss_output="$(printf '%s\n' "$near_miss_input" | review_strip_external_cli_wrapper 2>/dev/null || printf 'helper-failed')"
    if [[ "$near_miss_output" != "$near_miss_input" ]]; then
        near_miss_ok=false
        near_miss_failure="input=[$near_miss_input] output=[$near_miss_output]"
    fi
done
double_wrapped="$(OCTOPUS_SECURITY_V870=true wrap_cli_output codex "$wrapped_document")"
outer_removed="$(printf '%s\n' "$double_wrapped" | review_strip_external_cli_wrapper 2>/dev/null || true)"
if [[ "$near_miss_ok" == true ]] &&
   [[ "$outer_removed" == "$wrapped_document" ]] &&
   ! printf '%s' "$outer_removed" | review_normalize_findings_json >/dev/null 2>&1; then
    test_pass
else
    test_fail "non-enclosing wrapper text was altered: ${near_miss_failure:-nested wrapper lost more than its outer layer: [$outer_removed]}"
fi

test_case "format-only recovery parses a wrapped reformatted document without the python fallback"
recovery_document='{"findings":[{"file":"package.json","line":7,"severity":"normal","category":"correctness","title":"Recovered","detail":"same finding","confidence":0.9}]}'
original_sync="$(declare -f review_run_agent_sync_progress)"
# review_run_agent_sync_progress: Return inert provider fixtures or the requested verifier failure.
review_run_agent_sync_progress() { OCTOPUS_SECURITY_V870=true wrap_cli_output "$1" "$recovery_document"; }
python3() { return 127; }
recovered="$(review_recover_malformed_findings codex implementation-logic-reviewer '{findings:[{severity:normal,title:"Recovered"}]}' test-recovery 2>/dev/null || true)"
unset -f python3
unset -f review_run_agent_sync_progress
eval "$original_sync"
if [[ "$(printf '%s' "$recovered" | jq -r '[.[].title] | join(",")' 2>/dev/null || true)" == "Recovered" ]]; then
    test_pass
else
    test_fail "wrapped recovery output was not parsed: [$recovered]"
fi

debate_candidate='{"file":"src/app.ts","line":8,"severity":"normal","category":"correctness","title":"Contested","detail":"Guarded by the caller","confidence":0.6,"verdict":"needs-debate","debate_id":"finding-1"}'
debate_candidates="$(jq -cn --argjson finding "$debate_candidate" '[$finding]')"

test_case "wrapped evidence-backed debate decisions exclude the identified finding"
debate_document='{"decisions":[{"debate_id":"finding-1","decision":"exclude","reason":"Caller guards empty input","evidence":"src/app.ts:8 if (!input) return"}]}'
wrapped_debate="$(OCTOPUS_SECURITY_V870=true wrap_cli_output codex "$debate_document")"
unwrapped_debate="$(printf '%s\n' "$wrapped_debate" | review_strip_external_cli_wrapper)"
debate_decisions="$(printf '%s\n%s\n' "$debate_candidates" "$unwrapped_debate" | review_resolve_debate_decisions)"
if [[ "$unwrapped_debate" == "$debate_document" ]] &&
   printf '%s' "$debate_decisions" | jq -e --argjson finding "$debate_candidate" '
       length == 1 and .[0].decision == "exclude" and
       .[0].debate_id == "finding-1" and .[0].finding == $finding and
       .[0].reason == "Caller guards empty input" and
       .[0].evidence == "src/app.ts:8 if (!input) return"
   ' >/dev/null; then
    test_pass
else
    test_fail "wrapped evidence-backed exclusion was lost: [$debate_decisions]"
fi

test_case "wrapped unsupported bare debate exclusions retain the original finding"
bare_debate_document='{"include":[],"exclude":["finding-1"]}'
wrapped_bare_debate="$(OCTOPUS_SECURITY_V870=true wrap_cli_output codex "$bare_debate_document")"
unwrapped_bare_debate="$(printf '%s\n' "$wrapped_bare_debate" | review_strip_external_cli_wrapper)"
bare_debate_decisions="$(printf '%s\n%s\n' "$debate_candidates" "$unwrapped_bare_debate" | review_resolve_debate_decisions)"
if [[ "$unwrapped_bare_debate" == "$bare_debate_document" ]] &&
   printf '%s' "$bare_debate_decisions" | jq -e --argjson finding "$debate_candidate" '
       length == 1 and .[0].decision == "retain" and
       .[0].debate_id == "finding-1" and .[0].finding == $finding and
       (.[0].reason | length > 0)
   ' >/dev/null; then
    test_pass
else
    test_fail "unsupported bare exclusion removed or changed its candidate: [$bare_debate_decisions]"
fi

REVIEW_HARNESS="$TEST_TMP_DIR/review-run-harness.sh"
cat > "$REVIEW_HARNESS" <<'HARNESS'
set -eo pipefail
source "$REVIEW_SH"
source "$VALIDATION_SH"
log() { printf '%s\n' "$*" >> "$HARNESS_LOG"; }
check_codex_auth_freshness() { return 0; }
review_single_provider_is_available() { return 0; }
parse_review_md() { REVIEW_ALWAYS_CHECK=""; REVIEW_STYLE_RULES=""; REVIEW_SKIP_PATTERNS=""; }
review_collect_diff() { printf '%s\n' 'diff --git a/src/app.ts b/src/app.ts' '+const value = input.trim();'; }
build_review_fleet() { printf '%s\n' 'claude-sonnet:implementation-logic-reviewer:correctness'; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
spawn_agent_capture_pid() {
    printf '%s\n' '## Output' "$ROUND1_OUTPUT" '## Status: SUCCESS' > "${RESULTS_DIR}/$(octo_agent_spec_slug "$1")-$3.md"
    printf '%s\n' 424242
}
review_supervise_round1() { :; }
review_run_agent_sync_progress() {
    local provider_output
    printf 'SYNC %s %s\n' "$1" "$3" >> "$HARNESS_LOG"
    case "$3" in
        implementation-verifier)
            [[ "${VERIFIER_FAIL:-false}" != true ]] || return "${VERIFIER_EXIT:-1}"
            provider_output="$VERIFIER_OUTPUT" ;;
        implementation-synthesizer)
            provider_output="$(printf '%s\n' "$2" | sed -n 's/^Findings: //p' | jq -c --arg reverse "${SYNTHESIS_REVERSE:-false}" --arg fields "${SYNTHESIS_DOCUMENT_FIELDS:-false}" '{findings:(if $reverse == "true" then reverse else . end)} + (if $fields == "true" then {warning:"Partial reviewer fleet",verification_status:"incomplete",error:"untrusted error",extra:"untrusted"} else {} end)')" ;;
        *) return 1 ;;
    esac
    OCTOPUS_SECURITY_V870=true wrap_cli_output "$1" "$provider_output"
}
render_terminal_report() { :; }
print_provider_report() { :; }
# gh: Expose only a synthetic PR when publication is explicitly enabled.
gh() { [[ "${PUBLICATION_FIXTURE:-false}" == true ]] || return 1; echo 999; }
post_inline_comments() { echo PUBLISHED >> "$HARNESS_LOG"; }
review_pr_metadata() { echo '{"number":999,"headRefOid":"fixture"}'; }
review_run '{"target":"staged","debate":"off","publish":"auto"}'
HARNESS

e2e_round1_output='{"findings":[{"file":"src/app.ts","line":3,"severity":"normal","category":"correctness","title":"Kept","detail":"Null dereference on empty input","confidence":0.9},{"file":"src/app.ts","line":8,"severity":"normal","category":"correctness","title":"Dismissed","detail":"Guarded by the caller","confidence":0.6}]}'
e2e_verifier_output='{"findings":[{"file":"src/app.ts","line":3,"severity":"normal","category":"correctness","title":"Kept","detail":"Null dereference on empty input","confidence":0.9,"verdict":"confirmed"},{"file":"src/app.ts","line":8,"severity":"normal","category":"correctness","title":"Dismissed","detail":"Guarded by the caller","confidence":0.6,"verdict":"false-positive"}]}'
e2e_expected_findings='[{"title":"Kept","verdict":"confirmed"}]'

run_review_harness() {
    local run_dir="$1"
    shift
    mkdir -p "$run_dir/home" "$run_dir/tmp" "$run_dir/results"
    : > "$run_dir/log"
    env -i PATH="$PATH" HOME="$run_dir/home" TMPDIR="$run_dir/tmp" \
        RESULTS_DIR="$run_dir/results" HARNESS_LOG="$run_dir/log" \
        REVIEW_SH="$REVIEW_SH" VALIDATION_SH="$VALIDATION_SH" \
        ROUND1_OUTPUT="$e2e_round1_output" VERIFIER_OUTPUT="$e2e_verifier_output" \
        "$@" "$BASH" "$REVIEW_HARNESS" > "$run_dir/output" 2>&1
}

review_harness_findings() {
    local findings_file
    findings_file="$(find "$1/results" -name 'review-findings-*.json' -type f | head -n 1)"
    [[ -n "$findings_file" ]] || return 1
    jq -c '[.findings[] | {title, verdict}]' "$findings_file"
}

# review_harness_diagnostics: Summarize the isolated review result when a behavioral assertion fails.
review_harness_diagnostics() {
    printf 'rc=%s findings=%s log=[%s] output=[%s]' "$2" \
        "$(review_harness_findings "$1" 2>/dev/null || printf 'missing')" \
        "$(grep -E '^(WARN|ERROR|SYNC)' "$1/log" 2>/dev/null | tr '\n' ';')" \
        "$(tail -n 5 "$1/output" 2>/dev/null | tr '\n' ';')"
}

test_case "default fleet applies codex verifier verdicts from trust-wrapped output"
default_run="$TEST_TMP_DIR/default-fleet"
default_rc=0
run_review_harness "$default_run" OCTOPUS_SECURITY_V870=true || default_rc=$?
if [[ "$default_rc" -eq 0 ]] &&
   grep -qx 'SYNC codex implementation-verifier' "$default_run/log" &&
   [[ "$(review_harness_findings "$default_run" 2>/dev/null || true)" == "$e2e_expected_findings" ]] &&
   ! grep -q 'preserving Round 1 findings' "$default_run/log"; then
    test_pass
else
    test_fail "$(review_harness_diagnostics "$default_run" "$default_rc")"
fi

test_case "single-provider codex applies verifier verdicts and synthesis from trust-wrapped output"
single_run="$TEST_TMP_DIR/single-codex"
single_rc=0
run_review_harness "$single_run" OCTOPUS_SECURITY_V870=true OCTOPUS_REVIEW_SINGLE_PROVIDER=codex || single_rc=$?
if [[ "$single_rc" -eq 0 ]] &&
   grep -qx 'SYNC codex implementation-verifier' "$single_run/log" &&
   grep -qx 'SYNC codex implementation-synthesizer' "$single_run/log" &&
   [[ "$(review_harness_findings "$single_run" 2>/dev/null || true)" == "$e2e_expected_findings" ]] &&
   ! grep -q 'preserving Round 1 findings' "$single_run/log" &&
   ! grep -q 'synthesis returned invalid' "$single_run/log"; then
    test_pass
else
    test_fail "$(review_harness_diagnostics "$single_run" "$single_rc")"
fi


for failure in quota timeout malformed copilot partial empty duplicate unverified; do
    test_case "verifier $failure preserves uncertainty through synthesis"
    failure_run="$TEST_TMP_DIR/failed-$failure"
    old_verifier="$e2e_verifier_output"
    e2e_verifier_output='not valid JSON'
    case "$failure" in
        partial) e2e_verifier_output="$(printf '%s' "$old_verifier" | jq '{findings:[.findings[0]]}')" ;;
        empty) e2e_verifier_output='{"findings":[]}' ;;
        unverified) e2e_verifier_output="$(printf '%s' "$old_verifier" | jq '.findings[0].verdict="unverified"')" ;;
        duplicate) e2e_verifier_output="$(printf '%s' "$old_verifier" | jq '{findings:[.findings[0],.findings[0]]}')" ;;
    esac
    failure_rc=0
    if [[ "$failure" == malformed || "$failure" == partial || "$failure" == empty || "$failure" == duplicate || "$failure" == unverified ]]; then
        run_review_harness "$failure_run" PUBLICATION_FIXTURE=true || failure_rc=$?
    else
        if [[ "$failure" == copilot ]]; then
            run_review_harness "$failure_run" PUBLICATION_FIXTURE=true VERIFIER_FAIL=true OCTOPUS_REVIEW_SINGLE_PROVIDER=copilot || failure_rc=$?
        else
            verifier_exit=1; [[ "$failure" != timeout ]] || verifier_exit=124
            run_review_harness "$failure_run" PUBLICATION_FIXTURE=true VERIFIER_FAIL=true VERIFIER_EXIT="$verifier_exit" || failure_rc=$?
        fi
    fi
    e2e_verifier_output="$old_verifier"
    result_file="$(find "$failure_run/results" -name 'review-findings-*.json' -type f | head -1)"
    if [[ "$failure_rc" -eq 1 && -n "$result_file" ]] && jq -e '
        .verification_status == "incomplete" and (.warning | contains("unverified")) and
        (.findings | length == 2) and all(.findings[]; .verdict == "unverified")
    ' "$result_file" >/dev/null && ! grep -q PUBLISHED "$failure_run/log"; then
        test_pass
    else
        test_fail "$(review_harness_diagnostics "$failure_run" "$failure_rc")"
    fi
done

test_case "verified high-confidence review can still publish in the inert harness"
positive_run="$TEST_TMP_DIR/publish-positive"
positive_rc=0
run_review_harness "$positive_run" PUBLICATION_FIXTURE=true || positive_rc=$?
if [[ "$positive_rc" == 0 ]] && grep -q '^PUBLISHED$' "$positive_run/log"; then test_pass; else test_fail "positive publication fixture did not publish"; fi

for kind in identical distinct-verdicts; do
    test_case "complete duplicate-location verification retains each verdict: $kind"
    saved_round1="$e2e_round1_output"; saved_verifier="$e2e_verifier_output"
    if [[ "$kind" == identical ]]; then
        e2e_round1_output="$(printf '%s' "$saved_round1" | jq '{findings:[.findings[0],.findings[0]]}')"
        e2e_verifier_output="$(printf '%s' "$e2e_round1_output" | jq '.findings |= map(. + {verdict:"confirmed"})')"
    else
        e2e_round1_output="$(printf '%s' "$saved_round1" | jq '{findings:[.findings[0],(.findings[0] + {detail:"Distinct second provider evidence"})]}')"
        e2e_verifier_output="$(printf '%s' "$e2e_round1_output" | jq '.findings[0].verdict="false-positive" | .findings[1].verdict="confirmed"')"
    fi
    duplicate_run="$TEST_TMP_DIR/complete-duplicate-$kind"; duplicate_rc=0
    run_review_harness "$duplicate_run" PUBLICATION_FIXTURE=true || duplicate_rc=$?
    e2e_round1_output="$saved_round1";e2e_verifier_output="$saved_verifier"
    findings="$(find "$duplicate_run/results" -name 'review-findings-*.json' -type f | head -1)"
    expected_count=1; [[ "$kind" != identical ]] || expected_count=2
    if [[ "$duplicate_rc" == 0 && -n "$findings" ]] && jq -e --argjson count "$expected_count" '
        .verification_status != "incomplete" and (.findings|length == $count) and .findings[0].verdict == "confirmed"
    ' "$findings" >/dev/null && grep -q '^PUBLISHED$' "$duplicate_run/log"; then
        if [[ "$kind" == distinct-verdicts ]] && ! jq -e '.findings[0].detail == "Distinct second provider evidence"' "$findings" >/dev/null; then
            test_fail "a false positive displaced the independently confirmed finding"
        else test_pass; fi
    else test_fail "$(review_harness_diagnostics "$duplicate_run" "$duplicate_rc")"; fi
done


test_case "nonempty terminal report exposes incomplete verification and publication block"
warning_file="$TEST_TMP_DIR/incomplete-findings.json"
printf '%s' "$e2e_round1_output" | jq '. + {verification_status:"incomplete", warning:"Verifier output was invalid"}' > "$warning_file"
terminal_output="$(render_terminal_report "$warning_file")"
if [[ "$terminal_output" == *"Verifier output was invalid"* && "$terminal_output" == *"Findings remain unverified and publication is disabled"* && "$terminal_output" == *"Kept"* ]]; then test_pass; else test_fail "terminal hid incomplete verification: $terminal_output"; fi

test_case "valid synthesis ordering survives without changing any verified finding"
saved_verifier="$e2e_verifier_output"
e2e_verifier_output="$(printf '%s' "$e2e_verifier_output" | jq '.findings |= map(.verdict="confirmed")')"
ordered_run="$TEST_TMP_DIR/ordered-synthesis"; ordered_rc=0
run_review_harness "$ordered_run" SYNTHESIS_REVERSE=true || ordered_rc=$?
e2e_verifier_output="$saved_verifier"
ordered_file="$(find "$ordered_run/results" -name 'review-findings-*.json' -type f | head -1)"
if [[ "$ordered_rc" == 0 && -n "$ordered_file" ]] &&
   jq -e '[.findings[].title] == ["Dismissed","Kept"] and all(.findings[]; .verdict == "confirmed")' "$ordered_file" >/dev/null &&
   ! grep -q 'synthesis changed verified findings' "$ordered_run/log"; then
    test_pass
else test_fail "$(review_harness_diagnostics "$ordered_run" "$ordered_rc")"; fi

test_case "synthesis document fields cannot override trusted verification state"
fields_run="$TEST_TMP_DIR/synthesis-document-fields"; fields_rc=0
run_review_harness "$fields_run" PUBLICATION_FIXTURE=true SYNTHESIS_DOCUMENT_FIELDS=true || fields_rc=$?
fields_file="$(find "$fields_run/results" -name 'review-findings-*.json' -type f | head -1)"
if [[ "$fields_rc" == 0 && -n "$fields_file" ]] &&
   jq -e '(.findings | length == 1) and .findings[0].verdict == "confirmed" and
       (has("warning") or has("verification_status") or has("error") or has("extra") | not)' "$fields_file" >/dev/null &&
   grep -q '^PUBLISHED$' "$fields_run/log"; then
    test_pass
else test_fail "$(review_harness_diagnostics "$fields_run" "$fields_rc")"; fi

test_case "reports retain distinct verified records while collapsing exact duplicates"
verified_file="$TEST_TMP_DIR/distinct-verified-records.json"
printf '%s' "$findings_document" | jq '{findings:[(.findings[0] + {detail:"first verified defect"}),(.findings[0] + {detail:"second verified defect"}),(.findings[0] + {detail:"first verified defect"} | to_entries | reverse | from_entries)]}' > "$verified_file"
verified_normalized="$(review_normalize_findings_json < "$verified_file")"
verified_terminal="$(render_terminal_report "$verified_file")"
verified_publication="$(
    gh() {
        if [[ "$1 $2" == 'repo view' ]]; then echo fixture/repo
        elif [[ "$1 $2" == 'pr view' ]]; then echo 0123456789012345678901234567890123456789
        else return 1; fi
    }
    review_post_safe_body() { [[ "$3" != review-line ]] || printf 'INLINE:%s\n' "$2"; return 0; }
    post_inline_comments 999 "$verified_file"
)"
if printf '%s' "$verified_normalized" | jq -e '[.findings[].detail] == ["first verified defect","second verified defect"]' >/dev/null &&
   [[ "$verified_terminal" == *"first verified defect"* && "$verified_terminal" == *"second verified defect"* &&
      "$verified_publication" == *"first verified defect"* && "$verified_publication" == *"second verified defect"* &&
      "$(printf '%s' "$verified_publication" | grep -c '^INLINE:')" == 2 ]]; then
    test_pass
else test_fail "normalization or reporting dropped verified evidence: $verified_normalized"; fi

test_summary
