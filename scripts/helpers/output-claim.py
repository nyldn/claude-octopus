#!/usr/bin/env python3
"""Acquire parallel output claims, reclaiming one only after its owner is gone.

The owning invocation keeps an flock on its owner lock through a descriptor that
every worker and provider it starts inherits. flock locks belong to the open
file description, so the lock stays held until the controller and all of those
descendants have exited. A claim whose owner lock can be taken is stale.
"""

import fcntl
import os
import re
import sys
import tempfile

OWNER_RECORD = "owner"
OWNER_LOCK_PREFIX = ".parallel-owner."
GUARD = ".output-claims.lock"
ACQUIRED, OWNED, RECLAIMED = 0, 10, 11
SEAT_PATTERN = re.compile(r"[A-Za-z0-9_.:-]{1,256}")


def hold(descriptor):
    """Lock the descriptor inherited by this invocation and its descendants."""
    fcntl.flock(int(descriptor), fcntl.LOCK_EX | fcntl.LOCK_NB)
    return 0


def read_record(claim):
    """Return the owner record's lines without following a symlink."""
    try:
        descriptor = os.open(os.path.join(claim, OWNER_RECORD), os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return []
    with os.fdopen(descriptor, encoding="utf-8") as record:
        return record.read(65536).splitlines()


def valid_seat(seat):
    """Accept only the characters octo_spawn_contract_seat_id can produce."""
    return bool(SEAT_PATTERN.fullmatch(seat))


def recorded_seats(lines):
    """Seats the record's owner dispatched or inherited for its output path."""
    return [line.split(" ", 1)[1] for line in lines[1:]
            if line.split(" ", 1)[0] in ("seat", "reconcile")
            and " " in line and valid_seat(line.split(" ", 1)[1])]


def recorded_owner_lock(claim):
    """Read a validated sibling owner-lock path without following a symlink."""
    lines = read_record(claim)
    if not lines:
        return None
    owner_lock = lines[0].strip()
    name = os.path.basename(owner_lock)
    if (not name.startswith(OWNER_LOCK_PREFIX)
            or os.path.realpath(os.path.dirname(owner_lock))
            != os.path.realpath(os.path.dirname(claim))):
        return None
    return owner_lock


def owner_has_exited(owner_lock):
    """Require an existing lock that no controller or descendant still holds."""
    try:
        descriptor = os.open(owner_lock, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return False
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return False
    finally:
        os.close(descriptor)
    return True


def record_owner(claim, owner_lock, seat="", output="", reconcile=()):
    """Create an exclusive owner record inside a private prepared claim.

    The record names the seat dispatched for the output and every stale seat
    inherited from exited owners, so whoever reclaims or releases the claim
    can still cancel those seats after an interruption.
    """
    lines = [owner_lock]
    if seat and output:
        lines += ["seat " + seat, "output " + output]
        lines += ["reconcile " + stale for stale in reconcile if stale != seat]
    descriptor = os.open(os.path.join(claim, OWNER_RECORD),
                         os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as record:
        record.write("\n".join(lines) + "\n")


def acquire(claim, owner_lock, seat="", output=""):
    """Publish a complete claim, replacing only an exited owner's record."""
    claim = os.path.abspath(claim)
    owner_lock = os.path.abspath(owner_lock)
    if seat and not valid_seat(seat):
        raise ValueError(f"invalid seat ID: {seat!r}")
    if "\n" in output or "\r" in output:
        raise ValueError("output path must be a single line")
    with open(os.path.join(os.path.dirname(claim), GUARD), "a", encoding="utf-8") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        # Publish only a complete owner record. A killed preparer can leave a
        # private directory, but cannot strand an ownerless claim at this path.
        with tempfile.TemporaryDirectory(prefix=".output-claim.", dir=os.path.dirname(claim)) as prepared:
            stale = os.path.lexists(claim)
            stale_seats = []
            if stale:
                stale_lock = recorded_owner_lock(claim)
                if stale_lock is None or not owner_has_exited(stale_lock):
                    return OWNED
                try:
                    if os.listdir(claim) != [OWNER_RECORD]:
                        return OWNED
                except OSError:
                    return OWNED
                stale_seats = list(dict.fromkeys(recorded_seats(read_record(claim))))
            record_owner(prepared, owner_lock, seat, output, stale_seats)
            if stale:
                try:
                    # Retire the complete record atomically before deleting it.
                    # A crash or cleanup error must never leave an ownerless
                    # public claim that all later acquisitions treat as live.
                    with tempfile.TemporaryDirectory(prefix=".retired-claim.",
                                                     dir=os.path.dirname(claim)) as retired:
                        os.rename(claim, retired)
                except OSError:
                    return OWNED
            os.rename(prepared, claim)
            if stale:
                for stale_seat in stale_seats:
                    print(stale_seat)
                return RECLAIMED
            return ACQUIRED


def release(claim, owner_lock):
    """Retire a claim under the acquisition guard without losing its owner."""
    claim = os.path.abspath(claim)
    owner_lock = os.path.abspath(owner_lock)
    with open(os.path.join(os.path.dirname(claim), GUARD), "a", encoding="utf-8") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        if not os.path.lexists(claim):
            return ACQUIRED
        if recorded_owner_lock(claim) != owner_lock:
            return OWNED
        try:
            with tempfile.TemporaryDirectory(prefix=".retired-claim.",
                                             dir=os.path.dirname(claim)) as retired:
                os.rename(claim, retired)
        except OSError:
            return OWNED
    return ACQUIRED


def main():
    """Dispatch lock acquisition and claim operations for the shell executor."""
    if len(sys.argv) == 3 and sys.argv[1] == "hold":
        return hold(sys.argv[2])
    if len(sys.argv) in (4, 6) and sys.argv[1] == "acquire":
        return acquire(*sys.argv[2:])
    if len(sys.argv) == 4 and sys.argv[1] == "release":
        return release(sys.argv[2], sys.argv[3])
    print("usage: output-claim.py hold FD | acquire CLAIM OWNER_LOCK [SEAT OUTPUT] | release CLAIM OWNER_LOCK", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"output claim: {error}", file=sys.stderr)
        sys.exit(1)
