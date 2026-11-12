"""Measure preparation with an already-running monotonic clock process."""
import signal
import sys
import time
from pathlib import Path

root = Path(sys.argv[1])
started = None


def begin(_signal, _frame):
    global started
    if started is None:
        started = time.monotonic()


def finish(_signal, _frame):
    if started is None:
        raise SystemExit("Preparation never started")
    elapsed = time.monotonic() - started
    (root / "preparation.elapsed").write_text(str(elapsed) + "\n")
    raise SystemExit(0)


def expired(_signal, _frame):
    raise SystemExit("Preparation clock did not receive a stop signal")


signal.signal(signal.SIGUSR1, begin)
signal.signal(signal.SIGUSR2, finish)
signal.signal(signal.SIGALRM, expired)
signal.alarm(15)
(root / "clock.ready").write_text("ready\n")
while True:
    signal.pause()
