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

fake_bin="$TEST_TMP_DIR/bin"
timeout_args="$TEST_TMP_DIR/timeout-args"
mkdir -p "$fake_bin"
cat > "$fake_bin/gtimeout" <<'SH'
#!/bin/sh
printf '%s\n' "$*" > "$OCTO_TIMEOUT_ARGS_FILE"
exit 124
SH
chmod +x "$fake_bin/gtimeout"
export OCTO_TIMEOUT_ARGS_FILE="$timeout_args"
export PATH="$fake_bin:$PATH"

test_case "probe keeps the TERM-to-KILL grace inside its total default budget"
rc=0
OCTOPUS_SKIP_PROVIDER_PROBES=false _octo_bare_auth_probe >/dev/null 2>&1 || rc=$?
args=$(cat "$timeout_args" 2>/dev/null || true)
if [[ "$rc" -eq 124 && "$args" == "-k 2 3 claude --bare --print --model claude-haiku-4-5-20251001" ]]; then
    test_pass
else
    test_fail "unexpected total-budget timeout contract: rc=$rc args=$args"
fi

test_case "invalid and arbitrarily large timeout overrides are normalized before arithmetic"
OCTOPUS_BARE_PROBE_TIMEOUT=bogus OCTOPUS_SKIP_PROVIDER_PROBES=false \
    _octo_bare_auth_probe >/dev/null 2>&1 || true
invalid_args=$(cat "$timeout_args" 2>/dev/null || true)
OCTOPUS_BARE_PROBE_TIMEOUT=999999999999999999999999999999999999999 \
    OCTOPUS_SKIP_PROVIDER_PROBES=false _octo_bare_auth_probe >/dev/null 2>&1 || true
clamped_args=$(cat "$timeout_args" 2>/dev/null || true)
if [[ "$invalid_args" == "-k 2 3 "* && "$clamped_args" == "-k 2 28 "* ]]; then
    test_pass
else
    test_fail "timeout validation failed: invalid=$invalid_args clamped=$clamped_args"
fi

test_case "zero-padded positive timeout overrides retain their numeric value"
OCTOPUS_BARE_PROBE_TIMEOUT=00029 OCTOPUS_SKIP_PROVIDER_PROBES=false \
    _octo_bare_auth_probe >/dev/null 2>&1 || true
padded_args=$(cat "$timeout_args" 2>/dev/null || true)
if [[ "$padded_args" == "-k 2 27 "* ]]; then
    test_pass
else
    test_fail "zero-padded timeout did not normalize to 29 seconds: args=$padded_args"
fi

test_case "one-second probe budgets use a hard cap without extending for grace"
OCTOPUS_BARE_PROBE_TIMEOUT=1 OCTOPUS_SKIP_PROVIDER_PROBES=false \
    _octo_bare_auth_probe >/dev/null 2>&1 || true
short_args=$(cat "$timeout_args" 2>/dev/null || true)
if [[ "$short_args" == "-s KILL 1 claude --bare --print --model claude-haiku-4-5-20251001" ]]; then
    test_pass
else
    test_fail "short timeout extended past the configured cap: args=$short_args"
fi

test_case "portable fallback hard-kills a TERM-ignoring probe at the total cap"
manual_bin="$TEST_TMP_DIR/manual-bin"
mkdir -p "$manual_bin"
ln -sf /bin/sleep "$manual_bin/sleep"
ln -sf /usr/bin/pkill "$manual_bin/pkill"
if command -v setsid >/dev/null 2>&1; then
    ln -sf "$(command -v setsid)" "$manual_bin/setsid"
elif command -v perl >/dev/null 2>&1; then
    ln -sf "$(command -v perl)" "$manual_bin/perl"
fi
stubborn_probe="$TEST_TMP_DIR/stubborn-probe.sh"
cat > "$stubborn_probe" <<'SH'
#!/bin/sh
trap '' TERM
while :; do sleep 1; done
SH
chmod +x "$stubborn_probe"
SECONDS=0
rc=0
(
    PATH="$manual_bin"
    _octo_run_bare_probe_with_timeout 1 1 0 "$stubborn_probe" \
        >/dev/null 2>&1
) || rc=$?
elapsed=$SECONDS
if [[ "$rc" -ne 0 && "$elapsed" -le 2 ]]; then
    test_pass
else
    test_fail "portable fallback exceeded cap or lost failure: rc=$rc elapsed=${elapsed}s"
fi

test_case "portable fallback kills the complete probe process tree"
grandchild_pid_file="$TEST_TMP_DIR/grandchild.pid"
descendant_wrapper="$TEST_TMP_DIR/descendant-wrapper.sh"
descendant_probe="$TEST_TMP_DIR/descendant-probe.sh"
cat > "$descendant_wrapper" <<'SH'
#!/bin/sh
sleep 30 &
printf '%s\n' "$!" > "$OCTO_GRANDCHILD_PID_FILE"
wait
SH
cat > "$descendant_probe" <<'SH'
#!/bin/sh
trap '' TERM
"$OCTO_DESCENDANT_WRAPPER" &
wait
SH
chmod +x "$descendant_wrapper" "$descendant_probe"
export OCTO_GRANDCHILD_PID_FILE="$grandchild_pid_file"
export OCTO_DESCENDANT_WRAPPER="$descendant_wrapper"
rc=0
(
    PATH="$manual_bin"
    # Process creation can exceed one second on loaded macOS CI hosts. Give the
    # fixture enough time to publish its PID before asserting whole-tree kill.
    _octo_run_bare_probe_with_timeout 3 3 0 "$descendant_probe" \
        >/dev/null 2>&1
) || rc=$?
grandchild_pid=$(cat "$grandchild_pid_file" 2>/dev/null || true)
if [[ -n "$grandchild_pid" ]] && kill -0 "$grandchild_pid" 2>/dev/null; then
    kill -KILL "$grandchild_pid" 2>/dev/null || true
    wait "$grandchild_pid" 2>/dev/null || true
    test_fail "portable fallback left grandchild pid=$grandchild_pid running"
elif [[ "$rc" -ne 0 && -n "$grandchild_pid" ]]; then
    test_pass
else
    test_fail "portable fallback did not exercise descendant fixture: rc=$rc pid=$grandchild_pid"
fi

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
