#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

log() { :; }
source "$PROJECT_ROOT/scripts/lib/providers.sh"

test_suite "Bounded Claude --bare authentication probe"

test_case "non-live test and remote probe suppression never launches Claude"
probe_marker="$TEST_TMP_DIR/claude-called"
claude() { : > "$probe_marker"; }
rc=0
OCTOPUS_SKIP_PROVIDER_PROBES=true _octo_bare_auth_probe >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 125 && ! -e "$probe_marker" ]]; then test_pass
else test_fail "suppressed probe rc=$rc launched=$([[ -e "$probe_marker" ]] && echo yes || echo no)"; fi
unset -f claude

test_case "probe uses the shared timeout with a bounded default"
timeout_args="$TEST_TMP_DIR/timeout-args"
run_with_timeout() {
    printf '%s\n' "$*" > "$timeout_args"
    return 124
}
rc=0
OCTOPUS_SKIP_PROVIDER_PROBES=false _octo_bare_auth_probe >/dev/null 2>&1 || rc=$?
args=$(cat "$timeout_args" 2>/dev/null || true)
if [[ "$rc" -eq 124 && "$args" == "5 claude --bare --print --model claude-haiku-4-5-20251001" ]]; then test_pass
else test_fail "unexpected timeout contract: rc=$rc args=$args"; fi

test_case "invalid and excessive timeout overrides are clamped"
OCTOPUS_BARE_PROBE_TIMEOUT=bogus OCTOPUS_SKIP_PROVIDER_PROBES=false _octo_bare_auth_probe >/dev/null 2>&1 || true
invalid_args=$(cat "$timeout_args" 2>/dev/null || true)
OCTOPUS_BARE_PROBE_TIMEOUT=999 OCTOPUS_SKIP_PROVIDER_PROBES=false _octo_bare_auth_probe >/dev/null 2>&1 || true
clamped_args=$(cat "$timeout_args" 2>/dev/null || true)
if [[ "$invalid_args" == 5\ * && "$clamped_args" == 30\ * ]]; then test_pass
else test_fail "timeout validation failed: invalid=$invalid_args clamped=$clamped_args"; fi

test_case "non-live suite runner suppresses provider probes without changing live suites"
runner="$PROJECT_ROOT/tests/run-all-tests.sh"
if grep -Fq 'if [[ "$test_file" == "$SCRIPT_DIR/live/"* ]]' "$runner" &&
   grep -Fq 'OCTOPUS_SKIP_PROVIDER_PROBES=true bash "$test_file"' "$runner"; then
    test_pass
else
    test_fail "test runner does not isolate non-live provider probes from live suites"
fi

test_case "standalone doctor loads the bounded probe helper"
if bash -c 'source "$1"; declare -f _octo_bare_auth_probe >/dev/null' \
    _ "$PROJECT_ROOT/scripts/lib/doctor.sh"; then
    test_pass
else
    test_fail "lib/doctor.sh does not provide the bounded bare-auth probe standalone"
fi

test_summary
