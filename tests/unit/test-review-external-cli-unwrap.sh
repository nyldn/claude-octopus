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

test_case "debate exclusions are read from a wrapped debate result"
debate_start="$(grep -nF 'debate_result=$(echo "$debate_result"' "$REVIEW_SH" | head -n 1 | cut -d: -f1)"
debate_end="$(grep -nF 'exclude_titles=$(echo "$debate_result"' "$REVIEW_SH" | head -n 1 | cut -d: -f1)"
if [[ -z "$debate_start" || -z "$debate_end" ]]; then
    test_fail "could not locate the debate result parsing lines in review.sh"
else
    {
        printf '%s\n' 'review_test_debate_exclusions() {'
        printf '%s\n' '    local debate_result="$1"'
        sed -n "${debate_start},${debate_end}p" "$REVIEW_SH"
        printf '%s\n' '    printf "%s\n" "$exclude_titles"'
        printf '%s\n' '}'
    } > "$TEST_TMP_DIR/debate-parse.sh"
    source "$TEST_TMP_DIR/debate-parse.sh"
    wrapped_debate="$(OCTOPUS_SECURITY_V870=true wrap_cli_output codex '{"include":["Kept"],"exclude":["Contested"]}')"
    debate_exclusions="$(review_test_debate_exclusions "$wrapped_debate" 2>/dev/null || true)"
    if [[ "$debate_exclusions" == "Contested" ]]; then
        test_pass
    else
        test_fail "wrapped debate result produced exclusions [$debate_exclusions]"
    fi
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
        implementation-verifier) provider_output="$VERIFIER_OUTPUT" ;;
        implementation-synthesizer)
            provider_output="$(printf '%s\n' "$2" | sed -n 's/^Findings: //p' | jq -c '{findings: map(. + {synthesized: true})}')" ;;
        *) return 1 ;;
    esac
    OCTOPUS_SECURITY_V870=true wrap_cli_output "$1" "$provider_output"
}
render_terminal_report() { :; }
print_provider_report() { :; }
gh() { return 1; }
review_run '{"target":"staged","debate":"off","publish":"never"}'
HARNESS

e2e_round1_output='{"findings":[{"file":"src/app.ts","line":3,"severity":"normal","category":"correctness","title":"Kept","detail":"Null dereference on empty input","confidence":0.9},{"file":"src/app.ts","line":8,"severity":"normal","category":"correctness","title":"Dismissed","detail":"Guarded by the caller","confidence":0.6}]}'
e2e_verifier_output='{"findings":[{"file":"src/app.ts","line":3,"severity":"normal","category":"correctness","title":"Kept","detail":"Null dereference on empty input","confidence":0.9,"verdict":"confirmed"},{"file":"src/app.ts","line":8,"severity":"normal","category":"correctness","title":"Dismissed","detail":"Guarded by the caller","confidence":0.6,"verdict":"false-positive"}]}'
e2e_expected_findings='[{"title":"Kept","verdict":"confirmed","synthesized":true}]'

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
    jq -c '[.findings[] | {title, verdict, synthesized}]' "$findings_file"
}

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

test_summary
