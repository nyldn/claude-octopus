#!/usr/bin/env python3
"""A repaired old summary cannot impersonate an observed running round."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

WAITER = Path(sys.argv[1]).resolve()


def write_json(path, value):
    temporary = path.with_name(path.name + ".next")
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


def check(initial):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        pool = root / "pool"
        pool.mkdir()
        count = root / "polls"
        bin_dir = root / "bin"
        bin_dir.mkdir()
        sleeper = bin_dir / "sleep"
        sleeper.write_text("#!" + sys.executable + "\n" + r'''
import os, sys, time
from pathlib import Path
path = Path(os.environ["OCTO_WAIT_COUNT"])
value = int(path.read_text()) + 1 if path.exists() else 1
next_path = path.with_suffix(".next")
next_path.write_text(str(value))
next_path.replace(path)
time.sleep(float(sys.argv[1]))
''')
        sleeper.chmod(0o755)
        old = pool / "20260101-000000-aaaaaa"
        new = pool / "20260101-000001-bbbbbb"
        old.mkdir()
        key = "repair:summary"

        def beacon(directory, state, order):
            write_json(directory / "run-status.json", {"run_id": directory.name, "state": state,
                       "supersede_key": key, "created_order": order, "superseded": False})

        beacon(old, initial, 1)
        (old / "summary.json").write_text("{torn")
        env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                   OCTO_WAIT_COUNT=str(count))
        process = subprocess.Popen(["/bin/bash", str(WAITER), "--pool", str(pool),
                                    "--supersede-key", key, "--settle", "8", "--interval", "1",
                                    "--timeout", "12"], env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)

        def observed(target):
            deadline = time.monotonic() + 10
            while not count.exists() or int(count.read_text()) < target:
                if process.poll() is not None:
                    output, error = process.communicate()
                    raise AssertionError("old summary bypassed settle: " + output + error)
                if time.monotonic() >= deadline:
                    raise AssertionError("waiter did not reach observed poll " + str(target))
                time.sleep(.02)

        try:
            observed(1)
            write_json(old / "summary.json", {"run_id": old.name, "status": "completed"})
            beacon(old, "finished", 1)
            observed(2)
            new.mkdir()
            beacon(new, "running", 2)
            observed(3)
            write_json(new / "summary.json", {"run_id": new.name, "status": "completed"})
            beacon(new, "finished", 2)
            output, error = process.communicate(timeout=12)
            assert process.returncode == 0 and output.strip() == str(new / "summary.json"), (output, error)
            print(initial + ": returned the newer round")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()


for state in ("finished", "unknown"):
    check(state)
