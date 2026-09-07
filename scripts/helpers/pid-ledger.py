#!/usr/bin/env python3
"""Maintain worker registrations under the shared ledger lock."""

import fcntl
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def identity(pid):
    if not pid.isdecimal() or int(pid) <= 1:
        return ""
    try:
        if sys.platform.startswith("linux"):
            # comm may contain spaces and parentheses. Fields after its final
            # closing parenthesis start at state; starttime is field 22.
            fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
            if fields[0] == "Z":
                return ""
            boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
            value = f"{boot}:{pid}:{fields[19]}"
        else:
            result = subprocess.run(
                ["ps", "-o", "lstart=", "-o", "uid=", "-o", "stat=", "-p", pid],
                capture_output=True, text=True, timeout=2,
                env={**os.environ, "LC_ALL": "C"}, check=False,
            )
            fields = result.stdout.split()
            if result.returncode or not fields or fields[-1].startswith("Z"):
                return ""
            value = f"{pid}:" + " ".join(fields[:-1])
        return hashlib.sha256(value.encode()).hexdigest()
    except (OSError, IndexError, subprocess.TimeoutExpired):
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
    if action == "verify":
        token = args[0]
        return 0 if token and identity(pid) == token else 1
    if action == "register":
        agent, task = args
        if not agent or any(not field or "\n" in field or "\r" in field
                            for field in (agent, task)) or ":" in task:
            return 1
        token = identity(pid)
        if not token:
            return 1
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
    except (OSError, ValueError) as error:
        print(f"PID ledger: {error}", file=sys.stderr)
        sys.exit(1)
