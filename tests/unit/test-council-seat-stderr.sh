#!/usr/bin/env bash
# Council seat failure capture (sail-cruisey #3032).
#
# Council seats run detached, so when a Claude seat exited non-zero the only
# trace was "Agent claude failed with exit code 1" in the caller's log and
# "no-response" in summary.json. run_agent_sync now appends each failed attempt
# (exit code, provider stderr, or the stdout tail when stderr is empty) to the
# file named by _OCTOPUS_SEAT_STDERR_FILE, and the advice phase records it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Council seat stderr capture"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/agent-sync.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/secure.sh"

# Drive the real run_agent_sync failure path with a fake provider. Mirrors the
# harness in test-agent-sync-signal-retry.sh.
run_failing_seat() (
    local scenario="$1" mode="$2" capture="$3" agent="${4:-claude}"
    local fixture_root="$TEST_TMP_DIR/$scenario"
    local fake_provider="$fixture_root/provider.sh"
    mkdir -p "$fixture_root/results"
    export RESULTS_DIR="$fixture_root/results"
    cat > "$fake_provider" <<EOF
#!/usr/bin/env bash
case "$mode" in
    stderr) printf 'ERROR: claude session limit reached (key sk-abcdefghijklmnopqrstuvwxyz0123)\n' >&2 ;;
    stdout) printf '{"type":"result","is_error":true,"result":"Invalid model: claude-fable-5-1"}\n' ;;
    stdout-error) printf 'ERROR: authentication failed (key sk-abcdefghijklmnopqrstuvwxyz0123)\n' ;;
    stderr-cut) printf 'sk-abcdefghijklmnopqrstuvwxyz0123%16352s' '' >&2 ;;
    stdout-cut) printf 'sk-abcdefghijklmnopqrstuvwxyz0123%4064s' '' ;;
    stderr-basic) printf 'Authorization: Basic Zml4dHVyZS11c2VyOmZpeHR1cmUtcGFzcw==\n' >&2 ;;
    stdout-basic) printf 'aUtHoRiZaTiOn: bAsIc Zml4dHVyZS11c2VyOmZpeHR1cmUtcGFzcw==\n' ;;
    silent) : ;;
    segv) printf 'agy native crash\n' >&2; exit 139 ;;
esac
exit 1
EOF
    chmod 755 "$fake_provider"

    log() { :; }
    classify_task() { printf 'standard\n'; }
    get_role_for_context() { printf 'reviewer\n'; }
    apply_persona() { printf '%s\n' "$2"; }
    load_earned_skills() { :; }
    build_provider_context() { :; }
    enforce_context_budget() { printf '%s\n' "$1"; }
    get_agent_model() { printf 'fixture-model\n'; }
    estimate_agent_call_cost() { printf '0.000000\n'; }
    check_provider_health() { return 0; }
    record_agent_call() { :; }
    get_agent_command() { printf '%s\n' "$fake_provider"; }
    build_provider_env() { PROVIDER_ENV_ARRAY=(); }
    run_with_timeout() { shift; "$@"; }
    stop_quota_watcher() { :; }
    update_agent_status() { :; }
    octo_estimate_tokens_for_file() { printf '0\n'; }
    write_agent_status() { :; }

    set +e
    _OCTOPUS_SEAT_STDERR_FILE="$capture" OCTOPUS_PERSISTENCE_AVAILABLE=true \
        run_agent_sync "$agent" 'review this change' 30 reviewer council >/dev/null 2>&1
)

CAP_DIR="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/seat-stderr.XXXXXX")"

test_case "a Claude seat that exits non-zero leaves its provider stderr in the capture file"
cap="$CAP_DIR/stderr/02-code-reviewer.log"
run_failing_seat stderr-case stderr "$cap" && rc=0 || rc=$?
if [[ "$rc" == 1 && -s "$cap" ]] &&
   grep -q '^== .* claude exited 1: ' "$cap" &&
   grep -q '^-- stderr --$' "$cap" &&
   grep -q 'claude session limit reached' "$cap"; then
    test_pass
else
    test_fail "rc=$rc capture=$(tr '\n' '|' < "$cap" 2>/dev/null)"
fi

test_case "captured stderr is private and secrets in the reason header and body are scrubbed"
mode="$(stat -c '%a' "$cap" 2>/dev/null || stat -f '%Lp' "$cap" 2>/dev/null)"
if [[ "$mode" == 600 ]] && ! grep -q 'sk-abcdefghijklmnopqrstuvwxyz0123' "$cap" &&
   grep -q '^== .*Exit code 1: claude session limit reached (key \[REDACTED-API-KEY\])' "$cap" &&
   grep -q '^ERROR: claude session limit reached (key \[REDACTED-API-KEY\])' "$cap"; then
    test_pass
else
    test_fail "mode=$mode capture=$(tr '\n' '|' < "$cap")"
fi

test_case "when stderr is empty the stdout tail is captured instead (CLIs that print errors there)"
cap="$CAP_DIR/stderr/stdout-case.log"
run_failing_seat stdout-case stdout "$cap" || true
if grep -q '^-- stdout tail (stderr was empty) --$' "$cap" && grep -q 'Invalid model: claude-fable-5-1' "$cap"; then
    test_pass
else
    test_fail "capture=$(tr '\n' '|' < "$cap" 2>/dev/null)"
fi

test_case "stdout-only errors redact secrets from both the extracted reason and captured body"
cap="$CAP_DIR/stderr/stdout-error.log"
run_failing_seat stdout-error stdout-error "$cap" || true
if [[ -s "$cap" ]] && ! grep -q 'sk-abcdefghijklmnopqrstuvwxyz0123' "$cap" &&
   grep -q '^== .*Exit code 1: authentication failed (key \[REDACTED-API-KEY\])' "$cap" &&
   grep -q '^ERROR: authentication failed (key \[REDACTED-API-KEY\])' "$cap"; then
    test_pass
else
    test_fail "stdout error was not fully redacted"
fi

test_case "without the sanitizer no provider diagnostic is persisted"
cap="$CAP_DIR/stderr/no-sanitizer.log"
(unset -f sanitize_secrets; run_failing_seat no-sanitizer stderr "$cap") || true
if [[ ! -e "$cap" ]]; then test_pass; else test_fail "capture exists without a sanitizer"; fi

for stream in stderr stdout; do
    test_case "$stream credentials crossing the byte-tail boundary are redacted before truncation"
    cap="$CAP_DIR/stderr/$stream-cut.log"
    run_failing_seat "$stream-cut" "$stream-cut" "$cap" || true
    if [[ -s "$cap" ]] && ! grep -q 'abcdefghijklmnopqrstuvwxyz0123' "$cap" &&
       grep -q 'REDACTED-API-KEY' "$cap"; then
        test_pass
    else
        test_fail "$stream capture retained a credential fragment at the byte boundary"
    fi
done

test_case "a sanitizer that emits output and then fails cannot persist a partial diagnostic"
cap="$CAP_DIR/stderr/failed-sanitizer.log"
(
    sanitize_secrets() {
        if (( $# )); then printf '%s\n' "$1"; else cat; fi
        return 1
    }
    run_failing_seat failed-sanitizer stderr "$cap"
) || true
if [[ ! -e "$cap" ]]; then test_pass; else test_fail "capture exists after sanitization failed"; fi

test_case "a silent failure still records the exit code"
cap="$CAP_DIR/stderr/silent-case.log"
run_failing_seat silent-case silent "$cap" || true
if grep -q '^== .* claude exited 1: ' "$cap" && grep -q '^-- no stderr or stdout --$' "$cap"; then
    test_pass
else
    test_fail "capture=$(tr '\n' '|' < "$cap" 2>/dev/null)"
fi

test_case "without a capture file nothing is written"
before="$(find "$CAP_DIR" -type f | wc -l | tr -d ' ')"
run_failing_seat no-capture stderr "" || true
after="$(find "$CAP_DIR" -type f | wc -l | tr -d ' ')"
if [[ "$before" == "$after" ]]; then test_pass; else test_fail "files before=$before after=$after"; fi

test_case "an AGY SIGSEGV retry records both failed attempts, not just the last"
cap="$CAP_DIR/stderr/agy-segv.log"
run_failing_seat agy-segv segv "$cap" agy || true
if [[ "$(grep -c '^== .* agy exited 139: ' "$cap")" == 2 ]] && grep -q 'SIGSEGV; retrying once' "$cap" &&
   [[ "$(grep -c 'agy native crash' "$cap")" == 2 ]]; then
    test_pass
else
    test_fail "capture=$(tr '\n' '|' < "$cap" 2>/dev/null)"
fi

# ── Advice phase: the seat record and warnings carry the cause.
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/council.sh" 2>/dev/null

for stream in stderr stdout; do
    test_case "$stream Basic authorization is redacted from captures and failure details"
    cap="$CAP_DIR/stderr/$stream-basic.log"
    run_failing_seat "$stream-basic" "$stream-basic" "$cap" || true
    detail="$(council_seat_failure_detail "$cap" 1)"
    if [[ -s "$cap" ]] && ! grep -Fq 'Zml4dHVyZS11c2VyOmZpeHR1cmUtcGFzcw==' "$cap" &&
       grep -Fq '[REDACTED-BASIC]' "$cap" && [[ "$detail" == *'[REDACTED-BASIC]'* ]] &&
       [[ "$detail" != *'Zml4dHVyZS11c2VyOmZpeHR1cmUtcGFzcw=='* ]]; then
        test_pass
    else
        test_fail "$stream Basic authorization was retained in diagnostic output"
    fi
done

# Exercise both retained streams and the summary/warning detail with inert
# credentials. Keep the original dispatch tests above as the integration path.
for stream in stderr stdout; do
    while IFS='|' read -r label input secret; do
        # Assemble this inert token so secret scanners do not flag the fixture.
        if [[ "$label" == slack-app ]]; then
            input="xoxa-$input"; secret="xoxa-$secret"
        fi
        test_case "$stream $label is redacted before capture and failure detail"
        cap="$CAP_DIR/stderr/$stream-$label.log"
        err="$CAP_DIR/provider.err"; out="$CAP_DIR/provider.out"
        : > "$err"; : > "$out"
        if [[ "$stream" == stderr ]]; then
            printf '%s\n' "$input" > "$err"
        else
            printf '%s\n' "$input" > "$out"
        fi
        _OCTOPUS_SEAT_STDERR_FILE="$cap" octo_capture_seat_failure claude 1 "$input" "$err" "$out"
        detail="$(council_seat_failure_detail "$cap" 1)"
        if [[ -s "$cap" && "$detail" == *'[REDACTED-'* && "$detail" != *"$secret"* ]] &&
           ! grep -Fq "$secret" "$cap"; then
            test_pass
        else
            test_fail "$stream $label was retained in the capture or failure detail"
        fi
    done <<'CREDENTIALS'
json-basic|{"Authorization":"Basic dXNlcjpwYXNz"}|dXNlcjpwYXNz
bare-basic|bAsIc dXNlcjpwYXNz|dXNlcjpwYXNz
lower-bearer|authorization: bearer fixture-credential-value-12345|fixture-credential-value-12345
mixed-bearer|{"Authorization":"bEaReR fixture+credential/value~12345="}|fixture+credential/value~12345=
fine-grained-pat|github_pat_fixturecredential1234567890|github_pat_fixturecredential1234567890
github-app|ghs_fixturecredential1234567890|ghs_fixturecredential1234567890
perplexity|pplx-fixturecredential1234567890|pplx-fixturecredential1234567890
google|AIzaFixtureCredential1234567890|AIzaFixtureCredential1234567890
huggingface|hf_fixturecredential1234567890|hf_fixturecredential1234567890
aws-session|ASIA1234567890ABCDEF|ASIA1234567890ABCDEF
slack-app|fixturecredential1234567890|fixturecredential1234567890
CREDENTIALS
done

test_case "Basic prose survives argument and stdin sanitization"
prose='basic usage; Basic example'
if [[ "$(sanitize_secrets "$prose")" == "$prose" &&
      "$(printf '%s\n' "$prose" | sanitize_secrets)" == "$prose" ]]; then
    test_pass
else
    test_fail "ordinary Basic prose was redacted"
fi

_advice_run() {
    local d="$1" roster="$2"
    mkdir -p "$d/responses"
    COUNCIL_RUN_DIR="$d"
    COUNCIL_ROSTER_JSON="$roster"
    COUNCIL_FIXTURE=""
    COUNCIL_TIMEOUT_WARNINGS=""
    COUNCIL_SEAT_RECORDS_JSON='[]'
    council_run_chair_fallback() { :; }
    council_run_advice_phase >/dev/null 2>&1 || true
    unset -f council_run_chair_fallback
}

test_case "advice phase records a failed Claude seat's exit code, cause, and stderr file in summary data"
d="$(mktemp -d "$TEST_TMP_DIR/council-seat-fail.XXXXXX")"
council_dispatch_member_detached() {
    # Stand-in for run_agent_sync appending its failure capture.
    mkdir -p "$(dirname "$_OCTOPUS_SEAT_STDERR_FILE")"
    printf '== 2026-10-17T03:12:42Z claude exited 1: Exit code 1\n-- stdout tail (stderr was empty) --\nError: nested Claude session refused (CLAUDECODE is set)\n' \
        >> "$_OCTOPUS_SEAT_STDERR_FILE"
    return 1
}
_advice_run "$d" '[{"persona":"code-reviewer","seat":"verifier","provider":"claude","provider_org":"anthropic","model":"claude-fable-5-1"}]'
unset -f council_dispatch_member_detached
rec="$(jq -c '.[0]' <<< "$COUNCIL_SEAT_RECORDS_JSON")"
if jq -e --arg f "$d/stderr/00-code-reviewer.log" '.status == "no-response" and .failure.exit_code == 1
        and .failure.detail == "Error: nested Claude session refused (CLAUDECODE is set)"
        and .failure.stderr_file == $f' <<< "$rec" >/dev/null &&
   [[ -s "$d/stderr/00-code-reviewer.log" ]] &&
   [[ "$COUNCIL_TIMEOUT_WARNINGS" == "seat claude (code-reviewer) exited 1: Error: nested Claude session refused (CLAUDECODE is set); full output in $d/stderr/00-code-reviewer.log" ]]; then
    test_pass
else
    test_fail "record=$rec warns=[$COUNCIL_TIMEOUT_WARNINGS]"
fi

test_case "a failure before any provider ran still names a cause and a file"
d="$(mktemp -d "$TEST_TMP_DIR/council-seat-early.XXXXXX")"
council_dispatch_member_detached() { return 1; }
_advice_run "$d" '[{"persona":"code-reviewer","seat":"verifier","provider":"claude","provider_org":"anthropic","model":"m"}]'
unset -f council_dispatch_member_detached
rec="$(jq -c '.[0]' <<< "$COUNCIL_SEAT_RECORDS_JSON")"
if jq -e '.failure.exit_code == 1 and (.failure.detail | contains("before a provider produced output"))' <<< "$rec" >/dev/null &&
   grep -q '^== .* dispatch exited 1$' "$d/stderr/00-code-reviewer.log"; then
    test_pass
else
    test_fail "record=$rec"
fi

test_case "a seat that succeeds keeps no stderr file and no failure field"
d="$(mktemp -d "$TEST_TMP_DIR/council-seat-ok.XXXXXX")"
council_dispatch_member_detached() {
    mkdir -p "$(dirname "$_OCTOPUS_SEAT_STDERR_FILE")"
    printf 'stale attempt\n' >> "$_OCTOPUS_SEAT_STDERR_FILE"
    printf 'Reviewed the plan; the guard is correct.\n\nVERDICT: APPROVE\n' > "$3"
    return 0
}
_advice_run "$d" '[{"persona":"code-reviewer","seat":"verifier","provider":"claude","provider_org":"anthropic","model":"m"}]'
unset -f council_dispatch_member_detached
rec="$(jq -c '.[0]' <<< "$COUNCIL_SEAT_RECORDS_JSON")"
if jq -e 'has("failure") | not' <<< "$rec" >/dev/null && [[ ! -e "$d/stderr/00-code-reviewer.log" ]]; then
    test_pass
else
    test_fail "record=$rec files=$(ls "$d/stderr" 2>/dev/null)"
fi

test_case "an accepted advice response removes its capture even when the provider exited nonzero"
d="$(mktemp -d "$TEST_TMP_DIR/council-seat-salvaged.XXXXXX")"
council_dispatch_member_detached() {
    mkdir -p "$(dirname "$_OCTOPUS_SEAT_STDERR_FILE")"
    printf 'trailing transport error\n' > "$_OCTOPUS_SEAT_STDERR_FILE"
    printf 'Reviewed scripts/lib/agent-sync.sh:1289; the capture guard handles missing sanitizers.\n\nVERDICT: APPROVE\n' > "$3"
    return 1
}
_advice_run "$d" '[{"persona":"code-reviewer","seat":"verifier","provider":"claude","provider_org":"anthropic","model":"m"}]'
unset -f council_dispatch_member_detached
rec="$(jq -c '.[0]' <<< "$COUNCIL_SEAT_RECORDS_JSON")"
if jq -e '.status == "responded" and .verdict == "APPROVE" and (has("failure") | not)' <<< "$rec" >/dev/null &&
   [[ ! -e "$d/stderr/00-code-reviewer.log" && -z "$COUNCIL_TIMEOUT_WARNINGS" ]]; then
    test_pass
else
    test_fail "accepted response retained failure metadata or capture: $rec"
fi

test_case "a rejected chair-fallback attempt keeps its capture even when it left a partial response"
# _advice_run unset its chair-fallback stub, which also removed the real one.
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/council.sh" 2>/dev/null
d="$(mktemp -d "$TEST_TMP_DIR/council-fallback.XXXXXX")"; mkdir -p "$d/responses"
COUNCIL_RUN_DIR="$d"; COUNCIL_FIXTURE=""; COUNCIL_TIMEOUT_WARNINGS=""; COUNCIL_SEAT_RECORDS_JSON='[]'
council_pick_provider() { printf 'claude\n'; }
council_provider_is_available() { return 0; }
council_dispatch_member_detached() {
    mkdir -p "$(dirname "$_OCTOPUS_SEAT_STDERR_FILE")"
    printf '== 2026-10-17T03:12:42Z claude exited 1: Exit code 1\n-- stderr --\nError: rate limited\n' >> "$_OCTOPUS_SEAT_STDERR_FILE"
    printf 'Let me start by reading the plan\n' > "$3"
    return 1
}
council_run_chair_fallback sha256:test >/dev/null 2>&1 || true
unset -f council_pick_provider council_provider_is_available council_dispatch_member_detached
logs="$({ find "$d/stderr" -name '*chair-fallback*.log' 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [[ "$logs" -ge 1 && "$COUNCIL_TIMEOUT_WARNINGS" == *"(chair fallback "*") exited 1: Error: rate limited; full output in $d/stderr/"* ]] &&
   [[ -z "$(find "$d/responses" -name '*chair-fallback*' 2>/dev/null || true)" ]]; then
    test_pass
else
    test_fail "logs=$logs warns=[$COUNCIL_TIMEOUT_WARNINGS]"
fi

test_summary
