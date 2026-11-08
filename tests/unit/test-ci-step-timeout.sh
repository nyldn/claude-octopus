#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Bounded CI step"

# Every fixture uses the real helper and has an independent outer deadline.
check_ci_step() {
    python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" "$1" <<'PY'
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time

root, tmp, case = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
helper = root / "tests/helpers/run-ci-step.py"
work = tmp / case
work.mkdir(mode=0o700)
log = work / "logs" / "output.log"
base = [sys.executable, str(helper), "--timeout", "1", "--log", str(log), "--"]

def run(code, *args, prefix=None):
    """Execute an inert command with an independent outer deadline."""
    return subprocess.run((prefix or base) + [sys.executable, "-c", code, *map(str, args)],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=8)

def stopped(pid):
    """Treat absent or zombie fixture processes as terminated."""
    result = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)],
                            stdout=subprocess.PIPE, text=True, timeout=2)
    return not result.stdout.strip() or result.stdout.strip().startswith("Z")

def assert_stopped(pids):
    """Wait for owned fixtures, then clean up any survivors."""
    try:
        for _ in range(50):
            if all(stopped(pid) for pid in pids):
                return
            time.sleep(.02)
        raise AssertionError(f"owned children survived: {pids}")
    finally:
        for pid in pids:
            if not stopped(pid):
                os.kill(pid, signal.SIGKILL)

if case == "success":
    result = run("print('success-output')")
    assert result.returncode == 0, result.stdout
    assert result.stdout == log.read_bytes() == b"success-output\n"
    assert stat.S_IMODE(log.stat().st_mode) == 0o600
    assert stat.S_IMODE(log.parent.stat().st_mode) == 0o700
elif case == "nonzero":
    result = run("import sys; print('failed-output'); sys.exit(7)")
    assert result.returncode == 7, result.stdout
    assert result.stdout == log.read_bytes() == b"failed-output\n"
elif case == "timeout":
    result = run("import time; print('partial-output', flush=True); time.sleep(30)")
    assert result.returncode == 124, result.stdout
    assert b"partial-output" in result.stdout and b"timed out after 1s" in result.stdout
    assert b"time.sleep(30)" in result.stdout
    assert result.stdout == log.read_bytes()
elif case == "selfsignal":
    caller_group = os.getpgrp()
    result = run("import os,signal; print('before-group-signal', flush=True); os.killpg(os.getpgrp(), signal.SIGTERM)")
    assert result.returncode == 143, result.stdout
    assert result.stdout == log.read_bytes() == b"before-group-signal\n"
    assert os.getpgrp() == caller_group
    os.killpg(caller_group, 0)
elif case in ("tree", "interrupt"):
    pidfile = work / "pids"
    fixture = """import os,signal,subprocess,sys,time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([sys.executable, '-c', 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)'])
Path(sys.argv[1]).write_text(f'{os.getpid()} {child.pid}')
print('tree-started', flush=True)
time.sleep(30)
"""
    caller_group = os.getpgrp()
    if case == "tree":
        result = run(fixture, pidfile)
        assert result.returncode == 124, result.stdout
    else:
        command = base.copy()
        command[command.index("1")] = "5"
        process = subprocess.Popen(command + [sys.executable, "-c", fixture, str(pidfile)],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 3
            while not pidfile.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            assert pidfile.exists(), "fixture did not start"
            process.send_signal(signal.SIGTERM)
            output, _ = process.communicate(timeout=4)
            assert process.returncode == 143, output
            assert b"interrupted by signal 15" in output
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=2)
    pids = list(map(int, pidfile.read_text().split()))
    assert_stopped(pids)
    assert os.getpgrp() == caller_group
    os.killpg(caller_group, 0)
elif case == "invalid":
    marker = work / "should-not-exist"
    fixture = "from pathlib import Path; import sys; Path(sys.argv[1]).touch()"
    for invalid in ("0", "-1", "nan", "inf", "bad"):
        prefix = base.copy()
        prefix[prefix.index("1")] = invalid
        assert run(fixture, marker, prefix=prefix).returncode != 0
        assert not marker.exists()
    public = work / "public"
    public.mkdir()
    public.chmod(0o755)
    prefix = base.copy()
    prefix[prefix.index(str(log))] = str(public / "output.log")
    assert run(fixture, marker, prefix=prefix).returncode == 125
    assert not marker.exists()
    log.parent.mkdir(mode=0o700)
    log.symlink_to(marker)
    assert run(fixture, marker).returncode == 125
    assert not marker.exists()
elif case == "tail":
    limit = 16 * 1024 * 1024
    prefix = base.copy()
    prefix[prefix.index("1")] = "5"
    result = run("import sys; sys.stdout.write('x' * (17 * 1024 * 1024)); print('TAIL-END')", prefix=prefix)
    assert result.returncode == 0
    assert len(log.read_bytes()) == limit
    assert result.stdout == log.read_bytes()
    assert result.stdout.endswith(b"TAIL-END\n")
else:
    raise AssertionError(case)
PY
}

for scenario in success nonzero timeout selfsignal tree interrupt invalid tail; do
    test_case "CI step $scenario"
    if check_ci_step "$scenario"; then test_pass; else test_fail "$scenario contract failed"; fi
done
test_summary
