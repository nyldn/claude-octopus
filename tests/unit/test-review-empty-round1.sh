#!/usr/bin/env bash
# Exercise the full review pipeline with inert providers only.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "complete empty review"
TMP="$TEST_TMP_DIR/review-empty"
mkdir -p "$TMP"
source "$ROOT/scripts/lib/review.sh"
log() { :; }
check_codex_auth_freshness() { return 0; }
# Settings are consumed by the sourced review pipeline.
# shellcheck disable=SC2034
parse_review_md() { REVIEW_ALWAYS_CHECK=""; REVIEW_STYLE_RULES=""; REVIEW_SKIP_PATTERNS=""; }
# The caller owns the snapshot through Bash dynamic scope.
# shellcheck disable=SC2154
review_collect_diff() {
    if [[ -e "$TMP/dispatched" ]]; then
        [[ "$CASE" != diff-error ]] || return 42
        if [[ "$CASE" == changed ]]; then echo changed; return; fi
        if [[ "$CASE" == snapshot-bad ]]; then
            printf '%s\n' '{"findings":[],"warning":"corrupted snapshot"}' > "$round1_findings_file"
        fi
    fi
    echo original
}
build_review_fleet() {
    [[ "$CASE" != zero ]] || return 0
    printf 'codex:logic:logic\nclaude-sonnet:security:security\n'
}
review_agent_for_seat() { echo "$1"; }
fleet_dispatch_begin() { :; }
fleet_dispatch_end() { :; }
review_supervise_round1() { :; }
review_wait_for_result_status() { :; }
spawn_agent_capture_pid() {
    touch "$TMP/dispatched"
    echo "$1/$4" >> "$TMP/round1-calls"
    [[ "$CASE" != missing || "$4" != security ]] || return 1
    local body='{"findings":[]}' status=SUCCESS
    case "$CASE:$4" in
        timeout:security) status=TIMEOUT ;;
        allfailed:*) status=FAILED ;;
        statusless:security) status=RUNNING ;;
        multi:security) body='{"findings":[]} {"findings":[]}' ;;
        warning:security) body='{"findings":[],"warning":"review incomplete"}' ;;
        error:security) body='{"findings":[],"error":"provider could not inspect files"}' ;;
        failed:security) status=FAILED ;;
        malformed:security) body='{"findings":"bad"}' ;;
        prose:security) body='No issues.' ;;
        finding:security|finding-publication:security) body='{"findings":[{"file":"a","line":1,"title":"bug","detail":"bad","category":"logic","severity":"normal","confidence":0.9}]}' ;;
    esac
    printf '## Output\n%s\n## Status: %s\n' "$body" "$status" > "$RESULTS_DIR/$(octo_agent_spec_slug "$1")-$3.md"
    echo 999999
}
review_recover_malformed_findings() { return 1; }
review_run_agent_sync_progress() {
    echo "$3" >> "$TMP/calls"
    case "$3" in
        implementation-verifier)
            if [[ "$CASE" == finding-publication ]]; then
                echo '{"findings":[{"file":"a","line":1,"title":"bug","detail":"bad","category":"logic","severity":"normal","confidence":0.9,"verdict":"confirmed"}]}'
            else echo '{"findings":[]}'; fi ;;
        *) echo '{"findings":[]}' ;;
    esac
}
review_phase_provider() { echo "$1"; }
review_resolve_history_context() { :; }
octo_proof_enabled() { return 0; }
octo_proof_init() { echo "$TMP/proof"; }
octo_proof_event() { :; }
octo_proof_artifact() {
    if [[ "$2" == review-findings && "$CASE" == proof-* ]]; then
        [[ -f "$TMP/findings-before-proof" ]] || cp "$3" "$TMP/findings-before-proof"
        [[ "$CASE" != proof-artifact && "$CASE" != proof-artifact-finalize ]] || return 42
    fi
}
octo_proof_claim() { [[ "$CASE" != proof-claim ]]; }
octo_proof_capture_provider_status() {
    printf '%s\n' "$2" > "$TMP/provider-state-path"
    [[ "$CASE" != proof-status ]] || return 42
    cp "$2" "$TMP/provider-status"
}
octo_proof_finalize() {
    echo "$2" >> "$TMP/finalize-attempts"
    [[ "$CASE" != proof-finalize && "$CASE" != proof-artifact-finalize ]] || return 42
    echo "$2" > "$TMP/verdict"
}
render_terminal_report() { :; }
print_provider_report() {
    printf '%s\n' "$1" > "$TMP/provider-report-path"
    cp "$1" "$TMP/reported-status"
}
gh() { [[ "$CASE" == publication || "$CASE" == finding-publication ]] && echo 123; }
post_inline_comments() { touch "$TMP/publication-attempt"; return 1; }
git() { return 1; }
export HOME="$TMP/home" TMPDIR="$TMP"
mkdir -p "$HOME"
for CASE in clean missing timeout failed malformed prose finding changed diff-error snapshot-bad zero publication finding-publication allfailed statusless multi warning error proof-artifact proof-claim proof-status proof-finalize proof-artifact-finalize; do
    test_case "$CASE dispatches downstream stages or fails closed"
    RESULTS_DIR="$TMP/$CASE"; mkdir -p "$RESULTS_DIR"
    rm -f "$TMP/dispatched" "$TMP/calls" "$TMP/round1-calls" "$TMP/verdict" "$TMP/provider-status" "$TMP/provider-state-path" "$TMP/publication-attempt"
    rm -f "$TMP/findings-before-proof" "$TMP/finalize-attempts" "$TMP/provider-report-path" "$TMP/reported-status"
    rc=0
    profile='{"publish":"never","history":"fresh","debate":"off"}'
    [[ "$CASE" != publication && "$CASE" != finding-publication ]] || profile='{"publish":"ask","history":"fresh","debate":"off"}'
    review_run "$profile" <<< y > "$TMP/output" 2>&1 || rc=$?
    count=0; [[ ! -f "$TMP/calls" ]] || count=$(wc -l < "$TMP/calls" | tr -d ' ')
    verdict=""; [[ ! -f "$TMP/verdict" ]] || verdict="$(cat "$TMP/verdict")"
    calls=""; [[ ! -f "$TMP/calls" ]] || calls="$(cat "$TMP/calls")"
    case "$CASE" in
        proof-*)
            if [[ "$rc" == 1 && "$count" == 0 && -s "$TMP/reported-status" && -f "$TMP/provider-report-path" ]] &&
               grep -c '^fail$' "$TMP/finalize-attempts" >/dev/null &&
               [[ ! -e "$(cat "$TMP/provider-report-path")" ]] &&
               cmp -s "$TMP/findings-before-proof" "$RESULTS_DIR"/review-findings-*.json; then
                test_pass
            else test_fail "proof failure lost findings, finalization or cleanup: rc=$rc $(cat "$TMP/output")"; fi ;;
        clean)
            if [[ "$rc" == 0 && "$count" == 0 && "$verdict" == pass && "$(wc -l < "$TMP/round1-calls" | tr -d ' ')" == 2 ]] &&
               jq -e '.findings == [] and (.warning // "") == ""' "$RESULTS_DIR"/review-findings-*.json >/dev/null &&
               [[ -s "$TMP/provider-status" ]]; then test_pass; else test_fail "clean review lost reports or used downstream models"; fi ;;
        changed|diff-error|snapshot-bad)
            case "$CASE" in
                changed) expected_warning='Diff changed during review' ;;
                diff-error) expected_warning='Could not collect the current diff' ;;
                snapshot-bad) expected_warning='Round 1 snapshot could not be verified' ;;
            esac
            if [[ "$rc" == 1 && "$count" == 0 && "$verdict" == fail && -s "$TMP/provider-status" && -f "$TMP/provider-state-path" ]] &&
               [[ ! -e "$(cat "$TMP/provider-state-path")" ]] &&
               jq -e --arg warning "$expected_warning" '.warning == $warning' "$RESULTS_DIR"/review-findings-*.json >/dev/null; then
                test_pass
            else test_fail "gate failure did not close its proof and report: rc=$rc calls=$calls verdict=$verdict"; fi ;;
        zero|allfailed)
            if [[ "$rc" == 1 && "$count" == 0 && "$verdict" == fail ]] &&
               jq -e '.warning | length > 0' "$RESULTS_DIR"/review-findings-*.json >/dev/null; then test_pass; else test_fail "fleet failure missed its warning proof"; fi ;;
        publication)
            [[ "$rc" == 1 && "$count" == 0 && "$verdict" == fail ]] && test_pass || test_fail "empty publication failure returned success" ;;
        finding-publication)
            [[ "$rc" == 1 && "$calls" == $'implementation-verifier\nimplementation-synthesizer' && "$verdict" == fail && -f "$TMP/publication-attempt" ]] && test_pass || test_fail "nonempty publication failure: rc=$rc calls=$calls verdict=$verdict $(cat "$TMP/output")" ;;
        *)
            if [[ "$calls" == $'implementation-verifier\nimplementation-synthesizer' && "$rc" == 0 && -n "$verdict" ]]; then
                test_pass
            else test_fail "expected verified downstream stages: rc=$rc calls=$calls $(cat "$TMP/output")"; fi ;;
    esac
done
test_summary
