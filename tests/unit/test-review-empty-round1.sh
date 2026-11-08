#!/usr/bin/env bash
# Exercise the full review pipeline with inert providers only.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "complete empty review"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/scripts/lib/review.sh"
log() { :; }
check_codex_auth_freshness() { return 0; }
parse_review_md() { REVIEW_ALWAYS_CHECK=""; REVIEW_STYLE_RULES=""; REVIEW_SKIP_PATTERNS=""; }
review_collect_diff() {
    if [[ "$CASE" == changed && -e "$TMP/dispatched" ]]; then echo changed; else echo original; fi
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
        finding:security) body='{"findings":[{"file":"a","line":1,"title":"bug","detail":"bad","category":"logic","severity":"normal","confidence":0.9}]}' ;;
    esac
    printf '## Output\n%s\n## Status: %s\n' "$body" "$status" > "$RESULTS_DIR/$(octo_agent_spec_slug "$1")-$3.md"
    echo 999999
}
review_recover_malformed_findings() { return 1; }
review_run_agent_sync_progress() {
    echo "$3" >> "$TMP/calls"
    case "$3" in
        implementation-verifier) echo '{"findings":[]}' ;;
        *) echo '{"findings":[]}' ;;
    esac
}
review_phase_provider() { echo "$1"; }
review_resolve_history_context() { :; }
octo_proof_enabled() { return 0; }
octo_proof_init() { echo "$TMP/proof"; }
octo_proof_event() { :; }
octo_proof_artifact() { :; }
octo_proof_claim() { :; }
octo_proof_capture_provider_status() { cp "$2" "$TMP/provider-status"; }
octo_proof_finalize() { echo "$2" > "$TMP/verdict"; }
render_terminal_report() { :; }
print_provider_report() { :; }
gh() { [[ "$CASE" == publication ]] && echo 123; }
post_inline_comments() { return 1; }
git() { return 1; }
export HOME="$TMP/home" TMPDIR="$TMP"
mkdir -p "$HOME"
for CASE in clean missing timeout failed malformed prose finding changed zero publication allfailed statusless multi warning error; do
    test_case "$CASE dispatches downstream stages or fails closed"
    RESULTS_DIR="$TMP/$CASE"; mkdir -p "$RESULTS_DIR"
    rm -f "$TMP/dispatched" "$TMP/calls" "$TMP/round1-calls"
    rc=0
    profile='{"publish":"never","history":"fresh","debate":"off"}'
    [[ "$CASE" != publication ]] || profile='{"publish":"ask","history":"fresh","debate":"off"}'
    review_run "$profile" <<< y > "$TMP/output" 2>&1 || rc=$?
    count=0; [[ ! -f "$TMP/calls" ]] || count=$(wc -l < "$TMP/calls" | tr -d ' ')
    if [[ "$CASE" == clean ]]; then
        if [[ "$rc" == 0 && "$count" == 0 && "$(wc -l < "$TMP/round1-calls" | tr -d ' ')" == 2 ]] && jq -e '.findings == [] and (.warning // "") == ""' "$RESULTS_DIR"/review-findings-*.json >/dev/null; then
            if [[ "$(cat "$TMP/verdict")" == pass ]] && [[ "$(wc -l < "$TMP/provider-status" | tr -d ' ')" -ge 2 ]]; then test_pass; else test_fail "provider proof missing"; fi
        else test_fail "rc=$rc calls=$count $(cat "$TMP/output")"; fi
    elif [[ "$CASE" == publication && "$rc" != 0 && "$(cat "$TMP/verdict")" == fail ]]; then test_pass
    elif [[ "$CASE" != publication && ( "$count" -ge 2 || "$rc" != 0 ) ]]; then test_pass
    else test_fail "unsafe short circuit: rc=$rc calls=$count $(cat "$TMP/output")"; fi
done
test_summary
