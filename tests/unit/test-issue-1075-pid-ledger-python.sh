#!/usr/bin/env bash
# Regression for #1075 (review follow-up): coverage for
# _octopus_pid_ledger_resolve_python's actual selection behavior, which had
# no dedicated test — only the orchestrate.sh spawn exit-code fix was
# covered. Exercises: OCTO_PYTHON tried first with fallthrough on capability
# failure, per-process caching (probes once, not once per call), the final
# fallback not trusting a stale/nonexistent OCTO_PYTHON as a hard pin
# (regression flagged in PR #1076 review), and the non-Linux skip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "PID-ledger python interpreter resolution (#1075)"

PID_LEDGER_SH="$PROJECT_ROOT/scripts/lib/pid-ledger.sh"
# A restricted-PATH fixture still needs to actually launch bash: `PATH=dir
# bash -c ...` resolves the *bash* lookup itself against the overridden
# PATH (a well-known bash quirk for VAR=value command prefixes), so a PATH
# that doesn't contain bash fails with "command not found" before the
# fixture script ever runs. Always invoke bash by absolute path instead.
BASH_BIN="$(command -v bash)"

# A fake interpreter that reports itself pidfd-capable/incapable without
# touching the real os/signal modules, so the fixture doesn't depend on this
# host's actual pidfd support.
make_fake_python() {
    local path="$1" capable="$2"
    cat > "$path" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "-c" ]]; then
    exit $([[ "$capable" == "true" ]] && echo 0 || echo 1)
fi
echo "fake-python-invoked-with-non-probe-args: \$*" >&2
exit 1
EOF
    chmod +x "$path"
}

setup_bin_dir() {
    local dir="$TEST_TMP_DIR/pyresolve-bin-$$-$RANDOM"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

test_case "OCTO_PYTHON is tried first when it passes the capability check"
bindir="$(setup_bin_dir)"
make_fake_python "$bindir/octo-python" true
make_fake_python "$bindir/python3" true
result="$(
    PATH="$bindir:$PATH" OCTO_PYTHON="$bindir/octo-python" "$BASH_BIN" -c '
        source "'"$PID_LEDGER_SH"'"
        _octopus_pid_ledger_resolve_python
        echo "$_OCTO_PID_LEDGER_PYTHON"
    '
)"
if [[ "$result" == "$bindir/octo-python" ]]; then
    test_pass
else
    test_fail "expected OCTO_PYTHON candidate to be chosen, got: $result"
fi

test_case "a capability-failing OCTO_PYTHON falls through to the next candidate, not a hard pin"
bindir="$(setup_bin_dir)"
make_fake_python "$bindir/octo-python" false
make_fake_python "$bindir/python3" true
result="$(
    PATH="$bindir:$PATH" OCTO_PYTHON="$bindir/octo-python" "$BASH_BIN" -c '
        source "'"$PID_LEDGER_SH"'"
        _octopus_pid_ledger_resolve_python
        echo "$_OCTO_PID_LEDGER_PYTHON"
    '
)"
if [[ "$result" == "python3" ]]; then
    test_pass
else
    test_fail "expected fallthrough to the capable python3 candidate (bare name from the static candidate list), got: $result"
fi

test_case "resolution is cached: the capability probe subprocess runs once across repeated calls"
bindir="$(setup_bin_dir)"
probe_count_file="$TEST_TMP_DIR/probe-count-$$"
: > "$probe_count_file"
cat > "$bindir/python3" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "-c" ]]; then
    echo x >> "$probe_count_file"
    exit 0
fi
exit 0
EOF
chmod +x "$bindir/python3"
result="$(
    PATH="$bindir:$PATH" "$BASH_BIN" -c '
        source "'"$PID_LEDGER_SH"'"
        _octopus_pid_ledger_resolve_python
        _octopus_pid_ledger_resolve_python
        _octopus_pid_ledger_resolve_python
        echo "$_OCTO_PID_LEDGER_PYTHON"
    '
)"
probe_calls=$(wc -l < "$probe_count_file")
if [[ "$result" == "python3" && "$probe_calls" -eq 1 ]]; then
    test_pass
else
    test_fail "expected exactly 1 capability-probe subprocess across 3 resolve calls, got $probe_calls (resolved: $result)"
fi

test_case "a nonexistent OCTO_PYTHON does not become the final fallback (regression: must not hard-fail every ledger call)"
bindir="$(setup_bin_dir)"
# No python3 at all on PATH, and no candidate passes — forces the final
# fallback path. Before this fix, an unresolved OCTO_PYTHON was trusted
# verbatim here, so every subsequent "$_OCTO_PID_LEDGER_PYTHON" ... call
# would fail with "command not found" — a regression pre-#1075 code never
# had, since it never consulted OCTO_PYTHON at all.
result="$(
    PATH="$bindir" OCTO_PYTHON="/nonexistent/path/to/python3" "$BASH_BIN" -c '
        source "'"$PID_LEDGER_SH"'"
        _octopus_pid_ledger_resolve_python
        echo "$_OCTO_PID_LEDGER_PYTHON"
    ' 2>/dev/null
)"
if [[ "$result" == "python3" ]]; then
    test_pass
else
    test_fail "expected the safe 'python3' fallback, not the unresolved OCTO_PYTHON override; got: $result"
fi

test_case "a valid but capability-failing OCTO_PYTHON is still preferred over the bare default in the final fallback"
bindir="$(setup_bin_dir)"
make_fake_python "$bindir/octo-python" false
# No other candidate exists on PATH at all, so the loop exhausts everything
# and falls through — but OCTO_PYTHON is a real, executable file, so it
# should still be preferred over a bare "python3" that isn't even on PATH.
result="$(
    PATH="$bindir" OCTO_PYTHON="$bindir/octo-python" "$BASH_BIN" -c '
        source "'"$PID_LEDGER_SH"'"
        _octopus_pid_ledger_resolve_python
        echo "$_OCTO_PID_LEDGER_PYTHON"
    ' 2>/dev/null
)"
if [[ "$result" == "$bindir/octo-python" ]]; then
    test_pass
else
    test_fail "expected the executable-but-incapable OCTO_PYTHON to still win the final fallback over a bare 'python3'; got: $result"
fi

test_case "the capability probe is skipped entirely on a non-Linux uname"
bindir="$(setup_bin_dir)"
cat > "$bindir/uname" <<'EOF'
#!/usr/bin/env bash
echo "Darwin"
EOF
chmod +x "$bindir/uname"
# A python3 that would fail the capability probe if it were ever invoked
# with -c; if the non-Linux skip works, resolution should go straight to
# the default without calling it that way at all.
cat > "$bindir/python3" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-c" ]]; then
    echo "PROBE WAS INVOKED ON NON-LINUX" >&2
    exit 1
fi
exit 0
EOF
chmod +x "$bindir/python3"
result="$(
    PATH="$bindir:$PATH" "$BASH_BIN" -c '
        source "'"$PID_LEDGER_SH"'"
        _octopus_pid_ledger_resolve_python
        echo "$_OCTO_PID_LEDGER_PYTHON"
    ' 2>"$TEST_TMP_DIR/nonlinux-stderr.log"
)"
if [[ "$result" == "python3" ]] && ! grep -q "PROBE WAS INVOKED" "$TEST_TMP_DIR/nonlinux-stderr.log" 2>/dev/null; then
    test_pass
else
    test_fail "expected the probe to be skipped on a non-Linux uname and fall back to plain python3; got result=$result, stderr=$(cat "$TEST_TMP_DIR/nonlinux-stderr.log" 2>/dev/null)"
fi

test_summary
