#!/usr/bin/env python3
"""Run a CI command with a deadline and a private, bounded output log."""

from __future__ import annotations

import argparse
import importlib.util
import math
import os
from pathlib import Path
import shlex
import signal
import stat
import subprocess
import sys

OUTPUT_LIMIT = 16 * 1024 * 1024


class Interrupted(BaseException):
    def __init__(self, signum: int):
        self.signum = signum


def positive_seconds(value: str) -> float:
    """Parse a finite deadline greater than zero."""
    try:
        seconds = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("timeout must be positive, finite seconds") from error
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError("timeout must be positive, finite seconds")
    return seconds


def open_private_log(path: Path):
    """Create a private regular log without following links."""
    old_umask = os.umask(0o077)
    try:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        parent = path.parent.resolve(strict=True)
        parent_stat = parent.stat()
        if parent_stat.st_uid != os.getuid() or stat.S_IMODE(parent_stat.st_mode) & 0o077:
            raise ValueError("log parent must be owned by the current user with mode 0700 or stricter")
        flags = os.O_WRONLY | os.O_CREAT | os.O_NONBLOCK | os.O_NOFOLLOW
        descriptor = os.open(parent / path.name, flags, 0o600)
        try:
            log_stat = os.fstat(descriptor)
            if not stat.S_ISREG(log_stat.st_mode) or log_stat.st_uid != os.getuid():
                raise ValueError("log must be a regular file owned by the current user")
            if log_stat.st_nlink != 1:
                raise ValueError("log must not have multiple hard links")
            os.fchmod(descriptor, 0o600)
            os.ftruncate(descriptor, 0)
            return os.fdopen(descriptor, "wb")
        except BaseException:
            os.close(descriptor)
            raise
    finally:
        os.umask(old_umask)


def load_supervisor():
    """Load the repository's process supervisor by its resolved path."""
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location(
        "octopus_ci_process_supervisor", root / "shared" / "process_supervisor.py"
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load shared process supervisor")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.run_bounded_process


def main() -> int:
    """Run the command and retain its result, including timeout output."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=positive_seconds, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command or args.command[0] != "--" or len(args.command) == 1:
        parser.error("provide -- COMMAND ARGS after the options")
    command = args.command[1:]
    label = shlex.join(command)
    try:
        log = open_private_log(args.log)
    except Exception as error:
        print(f"CI step did not start: cannot create private log: {error}", file=sys.stderr)
        return 125

    def interrupt(signum, _frame):
        """Start supervised cleanup after the first runner interruption."""
        # A second runner signal must not interrupt the supervisor's cleanup.
        for name in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(name, signal.SIG_IGN)
        raise Interrupted(signum)

    previous = {}
    output = ""
    message = ""
    status = 125
    try:
        for name in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            previous[name] = signal.signal(name, interrupt)
        try:
            run_bounded_process = load_supervisor()
            status, output = run_bounded_process(
                command, Path.cwd(), args.timeout, shell=False,
                output_limit=OUTPUT_LIMIT, kill_grace=0.5,
            )
            if status < 0:
                status = 128 - status
        except subprocess.TimeoutExpired as error:
            output = error.output or ""
            status = 124
            message = f"CI step timed out after {args.timeout:g}s: {label}\n"
        except Interrupted as error:
            output = getattr(error, "output", "")
            status = 128 + error.signum
            message = f"CI step interrupted by signal {error.signum}: {label}\n"
        except Exception as error:
            output = getattr(error, "output", "")
            status = 125
            message = f"CI step failed: {error}: {label}\n"
        payload = (output + ("\n" if output and not output.endswith("\n") else "") + message)
        tail = payload.encode("utf-8", errors="replace")[-OUTPUT_LIMIT:]
        log.write(tail)
        log.flush()
        os.fsync(log.fileno())
        sys.stdout.buffer.write(tail)
        sys.stdout.buffer.flush()
    except (OSError, ValueError) as error:
        print(f"CI step output could not be retained: {error}", file=sys.stderr)
        status = 125
    finally:
        log.close()
        for name, handler in previous.items():
            signal.signal(name, handler)
    return status


if __name__ == "__main__":
    sys.exit(main())
