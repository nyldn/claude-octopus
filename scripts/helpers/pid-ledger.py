#!/usr/bin/env python3
"""Maintain worker registrations under the shared ledger lock."""

import fcntl
import os
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from process_control import Process, StaleProcess, UnsupportedPlatform, snapshot


def identity(pid):
    if not pid.isdecimal() or int(pid) <= 1:
        return ""
    try:
        return snapshot(int(pid)).token
    except (OSError, ValueError, IndexError, StaleProcess, UnsupportedPlatform):
        return ""


def update(path, action, pid, agent, task, token):
    # flock works on macOS as well as Linux through Python's standard library.
    # Use the same separate lock file as workflow cancellation/pruning.
    with open(str(path) + ".lock", "a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            rows = path.read_text().splitlines()
        except FileNotFoundError:
            rows = []
        if action == "register":
            rows.append(":".join((pid, agent, task, token)))
        elif action == "prune":
            rows = [row for row in rows if not (
                len(parts := row.split(":")) >= 3 and parts[2].startswith(task)
            )]
        else:
            rows = [row for row in rows if not (
                (parts := row.split(":")) and len(parts) in (3, 4)
                and parts[0] == pid and parts[2] == task
                and (parts[3] if len(parts) == 4 else "") == token
            )]
        fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as output:
                output.writelines(row + "\n" for row in rows)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def main():
    action, ledger, pid, *args = sys.argv[1:]
    if action == "verified":
        # Read one atomic ledger snapshot; native termination rechecks each
        # retained identity before binding its signals to the process instance.
        for row in Path(ledger).read_text().splitlines():
            fields = row.split(":")
            if len(fields) != 4 or not fields[2].startswith(pid):
                continue
            if fields[3] and identity(fields[0]) == fields[3]:
                print(row)
        return 0
    if action == "verify":
        token = args[0]
        return 0 if token and identity(pid) == token else 1
    if action == "register":
        agent, task = args
        if not agent or any(not field or "\n" in field or "\r" in field
                            for field in (agent, task)) or ":" in task:
            return 1
        # Reject workers before provider dispatch if the host cannot cancel them.
        with Process(int(pid)) as process:
            token = process.info.token
        # Provider-qualified model IDs contain colons; keep the row four fields.
        encoded_agent = agent.replace("%", "%25").replace(":", "%3A")
        update(Path(ledger), action, pid, encoded_agent, task, token)
        print(token)
    elif action == "remove":
        task, token = args
        update(Path(ledger), action, pid, "", task, token)
    elif action == "prune":
        update(Path(ledger), action, "", "", pid, "")
    else:
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, StaleProcess, UnsupportedPlatform) as error:
        print(f"PID ledger: {error}", file=sys.stderr)
        sys.exit(1)
