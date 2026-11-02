#!/usr/bin/env bash
# A smoke-test failure that is not a definitive quota or auth rejection must not
# outlive the run that saw it. An unknown error, a timeout or a sandbox denial
# once wrote the provider to the quota-dead cache, and the next preflight then
# reported it as "degraded (quota)" without calling it (sail-cruisey #2905).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "smoke failures and the quota-dead cache"

log() { :; }
unset CODEX_SANDBOX SANDBOX_RUNTIME OCTOPUS_QUOTA_DEAD_TTL || true

WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
HOME="$TEST_TMP_DIR/home"
mkdir -p "$WORKSPACE_DIR" "$HOME"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/smoke.sh"

pass_count=0
fail_count=0
skip_count=0

reset_cache() {
    rm -f "$(octo_quota_dead_file)" "$(octo_quota_dead_meta_file)"
    _OCTO_QUOTA_RUN_DEAD=" "
    _OCTO_QUOTA_RUN_RECHECK=" "
}

# A fresh shell that sources the libraries again: what the next preflight sees.
next_run_is_dead() {
    WORKSPACE_DIR="$WORKSPACE_DIR" bash -c '
        log() { :; }
        source "$1/scripts/lib/quota-watcher.sh"
        octo_quota_is_dead "$2"' _ "$PROJECT_ROOT" "$1"
}

for result in "UNKNOWN:model" "TIMEOUT:model" "SANDBOX_DENIED:model" "MODEL_NOT_FOUND:model" "POLICY_BLOCKED:model"; do
    test_case "a ${result%%:*} smoke result is not written to the quota-dead cache"
    reset_cache
    _smoke_tally_result "claude" "$result"
    if [[ ! -s "$(octo_quota_dead_file)" ]] && ! next_run_is_dead claude; then
        test_pass
    else
        test_fail "${result%%:*} was cached: $(cat "$(octo_quota_dead_file)" 2>/dev/null)"
    fi
done

test_case "an unknown smoke failure still excludes the provider for the rest of this run"
reset_cache
_smoke_tally_result "claude" "UNKNOWN:model"
if octo_quota_is_dead claude; then
    test_pass
else
    test_fail "a provider that just failed its smoke test is selectable again in the same run"
fi

test_case "a passing smoke result clears the run-local exclusion"
_smoke_tally_result "claude" "PASS"
if ! octo_quota_is_dead claude; then
    test_pass
else
    test_fail "claude passed but stayed excluded"
fi

for result in "AUTH_FAILURE:model" "RATE_LIMITED:model"; do
    test_case "a ${result%%:*} smoke result is cached with its own timestamp"
    reset_cache
    _smoke_tally_result "agy" "$result"
    if grep -qxF agy "$(octo_quota_dead_file)" 2>/dev/null &&
       grep -qE '^agy	[0-9]+	[0-9]+$' "$(octo_quota_dead_meta_file)" 2>/dev/null &&
       next_run_is_dead agy; then
        test_pass
    else
        test_fail "${result%%:*} was not cached per provider: file=$(cat "$(octo_quota_dead_file)" 2>/dev/null) meta=$(cat "$(octo_quota_dead_meta_file)" 2>/dev/null)"
    fi
done

test_case "nothing is cached while running inside a Codex sandbox"
reset_cache
CODEX_SANDBOX=seatbelt _smoke_tally_result "agy" "AUTH_FAILURE:model"
if [[ ! -s "$(octo_quota_dead_file)" ]] && ! next_run_is_dead agy && octo_quota_is_dead agy; then
    test_pass
else
    test_fail "a sandboxed auth failure was cached: $(cat "$(octo_quota_dead_file)" 2>/dev/null)"
fi

test_case "nothing is cached while running inside a sandbox runtime"
reset_cache
SANDBOX_RUNTIME=1 _smoke_tally_result "agy" "RATE_LIMITED:model"
if [[ ! -s "$(octo_quota_dead_file)" ]]; then
    test_pass
else
    test_fail "a sandboxed rate-limit failure was cached"
fi

test_case "Operation not permitted is classified as a sandbox denial"
if [[ "$(_classify_smoke_error 'bash: /dev/fd/62: Operation not permitted')" == SANDBOX_DENIED ]] &&
   [[ "$(_classify_smoke_error 'connect EPERM 127.0.0.1:443 (forbidden by sandbox)')" == SANDBOX_DENIED ]] &&
   [[ "$(_classify_smoke_error 'Error: 401 Unauthorized')" == AUTH_FAILURE ]]; then
    test_pass
else
    test_fail "sandbox stderr was not classified as SANDBOX_DENIED"
fi

test_case "the sandbox denial message names the sandbox, not the provider"
out="$(RED="" YELLOW="" NC="" DIM="" _display_smoke_test_error claude SANDBOX_DENIED model)"
if [[ "$out" == *sandbox* && "$out" != *"unknown error"* ]]; then
    test_pass
else
    test_fail "unexpected message: $out"
fi

test_case "preflight labels a cached quota entry as cached, with when it was written"
reset_cache
octo_quota_mark_dead codex 3600
marked="$(cut -f2 "$(octo_quota_dead_meta_file)")"
expected_time="$(date -r "$marked" +%H:%M 2>/dev/null || date -d "@$marked" +%H:%M)"
readiness="$(
    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/preflight.sh" 2>/dev/null
    codex() { :; }
    export "OPENAI_API_KEY=sk-test-not-a-real-key"
    octo_provider_readiness_result codex static 2>/dev/null
)"
if jq -e --arg t "$expected_time" '.reason_code == "quota" and (.remediation | test("cached " + $t)) and (.remediation | test("not re-checked"))' <<< "$readiness" >/dev/null 2>&1; then
    test_pass
else
    test_fail "readiness did not label the cached entry: $readiness"
fi

test_case "a run-local failure is reported as this run's failure, not a cached quota mark"
reset_cache
octo_quota_mark_failed_this_run codex
readiness="$(
    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/preflight.sh" 2>/dev/null
    codex() { :; }
    export "OPENAI_API_KEY=sk-test-not-a-real-key"
    octo_provider_readiness_result codex static 2>/dev/null
)"
if jq -e '.status == "degraded" and .reason_code == "health-failed" and (.remediation | test("not cached")) and (.remediation | test("[Cc]ached [0-9]|quota") | not)' <<< "$readiness" >/dev/null 2>&1; then
    test_pass
else
    test_fail "run-local failure reported as: $readiness"
fi

test_case "a cached mark without its own timestamp is labelled cached with no time"
reset_cache
octo_quota_mark_dead agy 3600
octo_quota_mark_dead codex
readiness="$(
    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/preflight.sh" 2>/dev/null
    codex() { :; }
    export "OPENAI_API_KEY=sk-test-not-a-real-key"
    octo_provider_readiness_result codex static 2>/dev/null
)"
if jq -e '.reason_code == "quota" and (.remediation | test("\\(cached, not re-checked\\)"))' <<< "$readiness" >/dev/null 2>&1; then
    test_pass
else
    test_fail "a shared mtime was shown as codex's mark time: $readiness"
fi

# provider_smoke_test with every probe stubbed: claude passes, agy as given.
smoke_bin="$TEST_TMP_DIR/smoke-bin"
mkdir -p "$smoke_bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$smoke_bin/agy"
printf '#!/usr/bin/env bash\nexit 0\n' > "$smoke_bin/claude"
chmod +x "$smoke_bin/agy" "$smoke_bin/claude"
secure_tempfile() { mktemp "$TEST_TMP_DIR/${1:-tmp}.XXXXXX"; }
STUB_AGY_RESULT="PASS"
_smoke_test_provider() {
    case "$1" in
        claude) echo "PASS" > "$3" ;;
        agy) echo "$STUB_AGY_RESULT" > "$3" ;;
        *) echo "SKIP" > "$3" ;;
    esac
}
SKIP_SMOKE_TEST=false
SMOKE_TEST_CACHE_FILE="$WORKSPACE_DIR/.smoke-cache"
PREFLIGHT_CACHE_TTL=3600
run_smoke() {
    reset_cache
    rm -f "$SMOKE_TEST_CACHE_FILE"
    pass_count=0 fail_count=0 skip_count=0
    (
        unset OCTOPUS_SKIP_PROVIDER_PROBES CLAUDE_CODE_REMOTE OCTOPUS_REMOTE_SESSION OCTOPUS_COUNCIL_DEFAULT_PROVIDERS
        RED="" YELLOW="" GREEN="" NC="" DIM="" CYAN=""
        PATH="$smoke_bin:/usr/bin:/bin" provider_smoke_test true >/dev/null 2>&1
    )
}

test_case "a degraded smoke pass with an unknown failure does not cache a pass"
STUB_AGY_RESULT="UNKNOWN:model"
if run_smoke && [[ "$(sed -n '3p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null)" == 1 ]] && ! smoke_test_cache_valid; then
    test_pass
else
    test_fail "the next process would reuse a pass: cache=$(tr '\n' '|' < "$SMOKE_TEST_CACHE_FILE" 2>/dev/null)"
fi

test_case "a timeout does not stop a smoke pass from being cached (slow is not dead)"
STUB_AGY_RESULT="TIMEOUT:model"
if run_smoke && [[ "$(sed -n '3p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null)" == 0 ]]; then
    test_pass
else
    test_fail "cache=$(tr '\n' '|' < "$SMOKE_TEST_CACHE_FILE" 2>/dev/null)"
fi

test_case "a clean smoke pass is still cached"
STUB_AGY_RESULT="PASS"
if run_smoke && [[ "$(sed -n '3p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null)" == 0 ]]; then
    test_pass
else
    test_fail "cache=$(tr '\n' '|' < "$SMOKE_TEST_CACHE_FILE" 2>/dev/null)"
fi

test_case "preflight does not cache a pass after an inconclusive smoke failure"
pf_out="$(
    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/config-display.sh" 2>/dev/null
    source "$PROJECT_ROOT/scripts/lib/preflight.sh" 2>/dev/null
    PREFLIGHT_CACHE_FILE="$WORKSPACE_DIR/.preflight-cache"
    rm -f "$PREFLIGHT_CACHE_FILE"
    RED="" YELLOW="" GREEN="" NC="" DIM="" CYAN=""
    octo_provider_readiness_result() { printf '{"provider":"%s","status":"available","reason_code":"ready","remediation":""}\n' "$1"; }
    check_codex_auth_freshness() { return 0; }
    detect_enterprise_backend() { :; }
    init_workspace() { :; }
    provider_smoke_test() { octo_quota_mark_failed_this_run agy; return 0; }
    preflight_check true >/dev/null 2>&1; rc=$?
    printf '%s %s\n' "$rc" "$(preflight_cache_read 2>/dev/null)"
)"
if [[ "$pf_out" == "0 1" ]]; then
    test_pass
else
    test_fail "rc and cached status: $pf_out"
fi

test_summary
