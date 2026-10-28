#!/usr/bin/env bash
# Preflight checks the council roster a session pins with
# OCTOPUS_COUNCIL_DEFAULT_PROVIDERS, and says when it ran inside a sandbox
# (sail-cruisey #2901: a Codex-led session pins claude,agy; Codex is the lead).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Preflight council roster"

log() { case "$1" in INFO|WARN|ERROR) shift; printf '%s\n' "$*" ;; esac; }
export HOME="$TEST_TMP_DIR/home"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
mkdir -p "$HOME" "$WORKSPACE_DIR"
RED="" GREEN="" YELLOW="" CYAN="" DIM="" NC=""
PREFLIGHT_CACHE_FILE="$WORKSPACE_DIR/.preflight-cache"
PREFLIGHT_CACHE_TTL=3600
source "$PROJECT_ROOT/scripts/lib/preflight.sh"
source "$PROJECT_ROOT/scripts/lib/config-display.sh"
unset OCTOPUS_COUNCIL_DEFAULT_PROVIDERS CODEX_SANDBOX SANDBOX_RUNTIME

test_case "no roster pinned: nothing to check"
if [[ -z "$(octo_preflight_roster)" ]] && [[ -z "$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=auto octo_preflight_roster)" ]]; then test_pass
else test_fail "unexpected roster"; fi

test_case "a pinned roster yields its canonical seats once each"
got="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS='claude,agy,claude:claude-opus-5-5' octo_preflight_roster | tr '\n' ' ')"
if [[ "$got" == "claude agy " ]]; then test_pass; else test_fail "got '$got'"; fi

test_case "an invalid roster is rejected"
if ! OCTOPUS_COUNCIL_DEFAULT_PROVIDERS='claude,nope' octo_preflight_roster >/dev/null 2>&1; then test_pass
else test_fail "invalid roster accepted"; fi

for whitespace_roster in '   ' $'\t' $'\n' ' , , '; do
    test_case "a roster without any seats is rejected ($(printf '%q' "$whitespace_roster"))"
    if OCTOPUS_COUNCIL_DEFAULT_PROVIDERS="$whitespace_roster" octo_preflight_roster >/dev/null 2>&1; then
        test_fail "whitespace-only roster accepted"
    else test_pass; fi
done

# preflight_check with every probe stubbed: readiness from a table, no smoke.
READY_CALLS="$TEST_TMP_DIR/ready-calls"
# Providers named in STUB_UNREADY report degraded; the rest are available.
STUB_UNREADY=""
octo_provider_readiness_result() {
    printf '%s\n' "$1" >> "$READY_CALLS"
    local status=available reason=ready
    [[ " $STUB_UNREADY " == *" $1 "* ]] && status=degraded reason=auth-required
    # As the real readiness does for a provider the registry cannot detect.
    octo_provider_has_capability "$1" detect || status=missing reason=not-detectable
    printf '{"provider":"%s","status":"%s","reason_code":"%s","remediation":"Log in to %s."}\n' "$1" "$status" "$reason" "$1"
}
check_codex_auth_freshness() { return 0; }
detect_enterprise_backend() { :; }
provider_smoke_test() { return 0; }
run_preflight() { rm -f "$READY_CALLS" "$PREFLIGHT_CACHE_FILE"; preflight_check true 2>&1; }

test_case "an invalid whitespace roster fails before any provider is checked"
out="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=$' \t\n' run_preflight)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && ! -e "$READY_CALLS" && "$out" == *"is not a valid council roster"* &&
      "$(preflight_cache_read)" == 1 ]]; then test_pass
else test_fail "rc=$rc out=$out"; fi

test_case "with claude,agy pinned, preflight checks exactly those seats and names the list"
STUB_UNREADY=""
out="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy run_preflight)" && rc=0 || rc=$?
calls="$(tr '\n' ' ' < "$READY_CALLS")"
if [[ "$rc" -eq 0 && "$calls" == "claude agy " && "$out" == *"council roster from OCTOPUS_COUNCIL_DEFAULT_PROVIDERS: claude agy"* && "$out" != *codex* ]]; then test_pass
else test_fail "rc=$rc calls='$calls' out=$out"; fi

test_case "a roster seat that is not ready fails preflight and is named"
STUB_UNREADY="agy"
out="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy run_preflight)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"seat(s) not ready: agy"* && "$out" == *"✗ agy"* ]]; then test_pass
else test_fail "rc=$rc out=$out"; fi

test_case "without a roster, preflight still checks the non-Claude providers"
STUB_UNREADY=""
out="$(run_preflight)" && rc=0 || rc=$?
calls=" $(tr '\n' ' ' < "$READY_CALLS")"
expected=" $(_preflight_provider_candidates | tr '\n' ' ')"
if [[ "$rc" -eq 0 && "$calls" == "$expected" && "$calls" != *" claude "* && "$out" != *"council roster"* ]]; then test_pass
else test_fail "rc=$rc calls='$calls' expected='$expected'"; fi

for blocked_status in missing degraded; do
    test_case "without a roster, $blocked_status providers still fail preflight"
    out="$(
        octo_provider_readiness_result() {
            printf '{"provider":"%s","status":"%s","reason_code":"test-unready","remediation":"Configure provider."}\n' "$1" "$blocked_status"
        }
        run_preflight
    )" && rc=0 || rc=$?
    if [[ "$rc" -ne 0 && "$(preflight_cache_read)" == 1 ]]; then test_pass
    else test_fail "rc=$rc out=$out"; fi
done

test_case "a cached pass is reused only for the same roster"
STUB_UNREADY=""
rm -f "$PREFLIGHT_CACHE_FILE"
OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy preflight_check true >/dev/null 2>&1
if OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy preflight_cache_valid && [[ "$(preflight_cache_read)" == 0 ]] &&
   ! preflight_cache_valid && ! OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=codex,agy preflight_cache_valid; then test_pass
else test_fail "cache: $(cat "$PREFLIGHT_CACHE_FILE" | tr '\n' '|')"; fi

test_case "inside a sandbox, an unready seat comes with the run-outside remedy"
STUB_UNREADY="claude"
out="$(CODEX_SANDBOX=seatbelt OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy run_preflight)" || true
plain="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy run_preflight)" || true
if [[ "$out" == *"inside the Codex sandbox (CODEX_SANDBOX=seatbelt)"* && "$out" == *"outside the sandbox"* && "$plain" != *"sandbox"* ]]; then test_pass
else test_fail "out=$out"; fi

# openai-tools is a valid council seat the registry gives no detect capability
# (api-configured-runtime-has-no-local-cli-detection), so readiness reports it
# not-detectable on every run. Preflight cannot check it; it must not fail on it.
test_case "a roster seat with no provider detection is not checked and does not fail preflight"
STUB_UNREADY=""
out="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,openai-tools run_preflight)" && rc=0 || rc=$?
calls="$(tr '\n' ' ' < "$READY_CALLS")"
if [[ "$rc" -eq 0 && "$calls" == "claude " && "$out" == *"openai-tools: not checked"* && "$out" != *"not ready"* ]]; then test_pass
else test_fail "rc=$rc calls='$calls' out=$out"; fi

test_case "an undetectable seat does not hide an unready one"
STUB_UNREADY="claude"
out="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,openai-tools run_preflight)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"seat(s) not ready: claude"* && "$out" != *"not ready: claude openai-tools"* ]]; then test_pass
else test_fail "rc=$rc out=$out"; fi

test_case "a roster with only undetectable seats passes without claiming they were checked"
STUB_UNREADY=""
out="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=openai-tools run_preflight)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && ! -e "$READY_CALLS" && "$out" == *"openai-tools: not checked"* &&
      "$out" == *"Preflight completed with unchecked council seats: openai-tools"* &&
      "$out" != *"All 8 tentacles accounted for and ready to work!"* &&
      "$out" != *"NO AI PROVIDERS FOUND"* && "$out" != *"PROVIDERS FOUND BUT NOT READY"* ]] &&
   [[ "$(preflight_cache_read)" == 0 ]]; then test_pass
else test_fail "rc=$rc out=$out"; fi

# Static readiness accepts codex from ~/.codex/auth.json alone; the OAuth
# freshness check is what catches an expired token. A pinned seat must not be
# waved through because another seat is ready.
test_case "an expired Codex token fails a roster that pins codex"
STUB_UNREADY=""
check_codex_auth_freshness() { return 1; }
out="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=codex,agy run_preflight)" && rc=0 || rc=$?
check_codex_auth_freshness() { return 0; }
if [[ "$rc" -ne 0 && "$out" == *"seat(s) not ready: codex"* && "$out" == *"codex login"* ]]; then test_pass
else test_fail "rc=$rc out=$out"; fi

test_case "the readiness loop does not redirect through /dev/fd (denied in macOS sandboxes)"
if ! grep -nE '^[^#]*[0-9]?> >\(' "$PROJECT_ROOT/scripts/lib/preflight.sh" >/dev/null; then test_pass
else test_fail "process-substitution redirect found"; fi

test_case "the /octo:preflight dashboard reports only the pinned roster"
unset -f octo_provider_readiness_result
source "$PROJECT_ROOT/scripts/lib/preflight.sh"
json="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy bash "$PROJECT_ROOT/scripts/helpers/preflight.sh" --json 2>/dev/null)"
all="$(bash "$PROJECT_ROOT/scripts/helpers/preflight.sh" --json 2>/dev/null)"
if jq -e '.roster == ["claude","agy"] and ([.results[].provider] == ["claude","agy"])' <<< "$json" >/dev/null &&
   jq -e --argjson n "$(wc -w <<< "$(octo_provider_ids detect)")" '.roster == null and (.results | length) == $n' <<< "$all" >/dev/null; then test_pass
else test_fail "json=$(jq -c '{roster,p:[.results[].provider]}' <<< "$json")"; fi

test_case "the dashboard lists an undetectable roster seat as not checked, not as unready"
txt="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=openai-tools bash "$PROJECT_ROOT/scripts/helpers/preflight.sh" 2>/dev/null)"
json="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=openai-tools bash "$PROJECT_ROOT/scripts/helpers/preflight.sh" --json 2>/dev/null)"
if [[ "$txt" == *"Council roster ready"* && "$txt" == *"Not checked by preflight"*"openai-tools"* && "$txt" != *"not ready: openai-tools"* &&
      "$txt" != *"Needs attention: 1"* ]] &&
   jq -e '.roster_unchecked == ["openai-tools"] and .providers_degraded == 0 and (.results | length) == 0' <<< "$json" >/dev/null; then test_pass
else test_fail "txt=$txt json=$(jq -c '{roster,roster_unchecked}' <<< "$json")"; fi

test_case "the smoke test skips providers outside the roster"
source "$PROJECT_ROOT/scripts/lib/smoke.sh"
if OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy _smoke_in_roster agy &&
   ! OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy _smoke_in_roster codex && _smoke_in_roster codex; then test_pass
else test_fail "smoke roster gate wrong"; fi


# A pinned roster needs every seat the smoke test launched to pass: claude
# passing must not cover for agy failing auth. Without a roster one pass is
# still enough (single-provider mode).
smoke_bin="$TEST_TMP_DIR/smoke-bin"
mkdir -p "$smoke_bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$smoke_bin/agy"
printf '#!/usr/bin/env bash\nexit 0\n' > "$smoke_bin/claude"
chmod +x "$smoke_bin/agy" "$smoke_bin/claude"
secure_tempfile() { mktemp "$TEST_TMP_DIR/${1:-tmp}.XXXXXX"; }
SMOKE_CALLS="$TEST_TMP_DIR/smoke-calls"
_smoke_test_provider() {
    printf '%s\n' "$1" >> "$SMOKE_CALLS"
    case "$1" in
        claude) echo "PASS" > "$3" ;;
        agy) echo "AUTH_ERROR:agy-test" > "$3" ;;
        *) echo "SKIP" > "$3" ;;
    esac
}
_display_smoke_test_error() { :; }
octo_quota_mark_dead() { :; }
octo_quota_clear_dead() { :; }
SKIP_SMOKE_TEST=false
SMOKE_TEST_CACHE_FILE="$WORKSPACE_DIR/.smoke-cache"
# The suite runner sets OCTOPUS_SKIP_PROVIDER_PROBES, which skips the smoke
# test entirely; clear the skip switches so it really runs.
run_smoke() (
    unset OCTOPUS_SKIP_PROVIDER_PROBES CLAUDE_CODE_REMOTE OCTOPUS_REMOTE_SESSION
    rm -f "$SMOKE_TEST_CACHE_FILE" "$SMOKE_CALLS"
    PATH="$smoke_bin:/usr/bin:/bin" provider_smoke_test true >/dev/null 2>&1
)
smoke_called() { [[ "$(sort "$SMOKE_CALLS" 2>/dev/null | tr '\n' ' ')" == "agy claude " ]]; }

test_case "with a roster pinned, one failed seat fails the smoke test"
if OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=claude,agy run_smoke; then test_fail "claude,agy passed with agy failing auth"
elif ! smoke_called; then test_fail "smoke probes did not run: $(tr '\n' ' ' < "$SMOKE_CALLS" 2>/dev/null)"
else test_pass; fi

test_case "without a roster, one passing provider still passes the smoke test"
if ! run_smoke; then test_fail "no-roster smoke failed with claude passing"
elif ! smoke_called; then test_fail "smoke probes did not run: $(tr '\n' ' ' < "$SMOKE_CALLS" 2>/dev/null)"
else test_pass; fi

test_summary
