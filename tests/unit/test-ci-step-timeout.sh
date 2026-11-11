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
base = [sys.executable, str(helper), "--timeout", "3", "--log", str(log), "--"]

def run(code, *args, prefix=None):
    """Execute an inert command with an independent outer deadline."""
    return subprocess.run((prefix or base) + [sys.executable, "-c", code, *map(str, args)],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=12)

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
    assert b"partial-output" in result.stdout and b"timed out after 3s" in result.stdout
    assert b"time.sleep(30)" in result.stdout
    assert result.stdout == log.read_bytes()
elif case == "selfsignal":
    caller_group = os.getpgrp()
    result = run("import os,signal; print('before-group-signal', flush=True); os.killpg(os.getpgrp(), signal.SIGTERM)")
    assert result.returncode == 143, result.stdout
    assert result.stdout == log.read_bytes() == b"before-group-signal\n"
    assert os.getpgrp() == caller_group
    os.killpg(caller_group, 0)
elif case in ("tree", "interrupt", "cleanup-interrupt"):
    pidfile = work / "pids"
    output_ready = work / "output-ready"
    cleanup_marker = work / "cleanup-started"
    cleanup_release = work / "cleanup-release"
    fixture = """import os,signal,subprocess,sys,time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([sys.executable, '-c', 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)'])
Path(sys.argv[1]).write_text(f'{os.getpid()} {child.pid}')
print('tree-started', flush=True)
if sys.argv[2] != 'tree':
    # Exceed both pipe capacity and the retained-output limit before signalling.
    print('x' * (17 * 1024 * 1024), flush=True)
Path(sys.argv[3]).touch()
time.sleep(30)
"""
    caller_group = os.getpgrp()
    command = base.copy()
    if case == "interrupt":
        command[command.index("--timeout") + 1] = "5"
    elif case == "cleanup-interrupt":
        launcher = r'''
import importlib.util
from pathlib import Path
import sys

helper, marker, release = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("ci_cleanup_interrupt", helper)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original_load = module.load_supervisor

def synchronized_load():
    """Pause the real terminator at its first cleanup wait."""
    run = original_load()
    original_terminate = run.__globals__["_terminate_process_tree"]
    clock = run.__globals__["time"]
    original_sleep = clock.sleep
    cleaning = False

    def terminate(*args):
        """Track the real cleanup call without replacing its signals or waits."""
        nonlocal cleaning
        cleaning = True
        try:
            return original_terminate(*args)
        finally:
            cleaning = False

    def cleanup_sleep(seconds):
        """Let the harness deliver its first signal during the cleanup wait."""
        if cleaning and not Path(marker).exists():
            Path(marker).touch()
            while not Path(release).exists():
                original_sleep(.01)
        original_sleep(seconds)

    run.__globals__["_terminate_process_tree"] = terminate
    clock.sleep = cleanup_sleep
    return run

module.load_supervisor = synchronized_load
sys.argv = [helper, *sys.argv[4:]]
raise SystemExit(module.main())
'''
        command = [sys.executable, "-c", launcher, str(helper), str(cleanup_marker),
                   str(cleanup_release), *base[2:]]
    process = subprocess.Popen(command + [sys.executable, "-c", fixture, str(pidfile), case, str(output_ready)],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 5
        while not output_ready.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(.01)
        assert pidfile.exists() and output_ready.exists(), "fixture did not finish emitting before timeout"
        if case == "cleanup-interrupt":
            deadline = time.monotonic() + 5
            while not cleanup_marker.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(.01)
            assert cleanup_marker.exists(), "fixture did not enter its cleanup wait"
        if case != "tree":
            process.send_signal(signal.SIGTERM)
            cleanup_release.touch()
        output, _ = process.communicate(timeout=8)
        assert process.returncode == (124 if case == "tree" else 143), output
        if case != "tree":
            emitted, separator, diagnostic = output.partition(b"\nCI step interrupted by signal 15: ")
            assert separator and emitted.startswith(b"x" * 1024), "interruption dropped captured output"
            assert emitted == b"x" * len(emitted), "retained output is not the emitted tail"
            assert output == log.read_bytes()
            assert len(output) == 16 * 1024 * 1024
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        if pidfile.exists():
            assert_stopped(list(map(int, pidfile.read_text().split())))
    assert os.getpgrp() == caller_group
    os.killpg(caller_group, 0)
elif case == "invalid":
    marker = work / "should-not-exist"
    fixture = "from pathlib import Path; import sys; Path(sys.argv[1]).touch()"
    for invalid in ("0", "-1", "nan", "inf", "bad"):
        prefix = base.copy()
        prefix[prefix.index("--timeout") + 1] = invalid
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
    prefix[prefix.index("--timeout") + 1] = "5"
    result = run("import sys; sys.stdout.write('x' * (17 * 1024 * 1024)); print('TAIL-END')", prefix=prefix)
    assert result.returncode == 0
    assert len(log.read_bytes()) == limit
    assert result.stdout == log.read_bytes()
    assert result.stdout.endswith(b"TAIL-END\n")
else:
    raise AssertionError(case)
PY
}

for scenario in success nonzero timeout selfsignal tree interrupt cleanup-interrupt invalid tail; do
    test_case "CI step $scenario"
    if check_ci_step "$scenario"; then test_pass; else test_fail "$scenario contract failed"; fi
done
test_summary
