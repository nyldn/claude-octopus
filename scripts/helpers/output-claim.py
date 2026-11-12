#!/usr/bin/env python3
"""Acquire parallel output claims, reclaiming one only after its owner is gone.

The owning invocation keeps an flock on its owner lock through a descriptor that
every worker and provider it starts inherits. flock locks belong to the open
file description, so the lock stays held until the controller and all of those
descendants have exited. A claim whose owner lock can be taken is stale.
"""

import fcntl
import json
import os
import re
import shutil
import sys
import tempfile

OWNER_RECORD = "owner"
OWNER_LOCK_PREFIX = ".parallel-owner."
GUARD = ".output-claims.lock"
ACQUIRED, OWNED, RECLAIMED = 0, 10, 11
SEAT_PATTERN = re.compile(r"[A-Za-z0-9_.:-]{1,256}")
ENTRY_FIELDS = ("seat", "output", "run", "workspace")


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


def seat_entry(seat, output, run, workspace):
    """Name a seat by the run that recorded it and that run's output spelling.

    Runs can share a results directory, and each can spell it differently, so
    only these fields identify the status row a reclaimer must reconcile.
    """
    return {"seat": seat, "output": output, "run": run, "workspace": workspace}


def recorded_seats(lines):
    """Seat entries the record's owner dispatched or inherited."""
    entries = []
    for line in lines[1:]:
        kind, _, value = line.partition(" ")
        if kind not in ("seat", "reconcile"):
            continue
        try:
            entry = json.loads(value)
        except ValueError:
            continue
        if (isinstance(entry, dict) and set(entry) == set(ENTRY_FIELDS)
                and all(isinstance(entry[field], str) for field in ENTRY_FIELDS)
                and valid_seat(entry["seat"]) and entry["output"]):
            entries.append(entry)
    return entries


def unique_entries(entries):
    """Drop repeated entries while keeping their first-recorded order."""
    return list({json.dumps(entry, sort_keys=True): entry for entry in entries}.values())


def absolute_path(path):
    """Make a path absolute without collapsing its parent segments.

    os.path.abspath would turn "link/../results" into "results" before the
    link resolves, so the helper could address a different directory than the
    shell. Leaving ".." in place lets the kernel resolve it as the shell does.
    """
    return path if os.path.isabs(path) else os.path.join(os.getcwd(), path)


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


def record_owner(claim, owner_lock, entry=None, reconcile=()):
    """Create an exclusive owner record inside a private prepared claim.

    The record names the seat dispatched for the output and every stale seat
    inherited from exited owners, so whoever reclaims or releases the claim
    can still cancel those seats after an interruption.
    """
    lines = [owner_lock]
    if entry:
        lines.append("seat " + json.dumps(entry, sort_keys=True))
    lines += ["reconcile " + json.dumps(stale, sort_keys=True)
              for stale in reconcile if stale != entry]
    descriptor = os.open(os.path.join(claim, OWNER_RECORD),
                         os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as record:
        record.write("\n".join(lines) + "\n")


def acquire(claim, owner_lock, seat="", output="", run="", workspace=""):
    """Publish a complete claim, replacing only an exited owner's record."""
    claim = absolute_path(claim)
    owner_lock = absolute_path(owner_lock)
    # tempfile returns lexically normalized names, so give it, and the guard,
    # the directory the kernel resolves for this claim.
    directory = os.path.realpath(os.path.dirname(claim))
    if seat and not valid_seat(seat):
        raise ValueError(f"invalid seat ID: {seat!r}")
    if "\n" in output or "\r" in output:
        raise ValueError("output path must be a single line")
    with open(os.path.join(directory, GUARD), "a", encoding="utf-8") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        # Publish only a complete owner record. A killed preparer can leave a
        # private directory, but cannot strand an ownerless claim at this path.
        prepared = tempfile.mkdtemp(prefix=".output-claim.", dir=directory)
        published = False
        try:
            stale = os.path.lexists(claim)
            stale_seats = []
            if stale:
                stale_lock = recorded_owner_lock(claim)
                if (os.path.islink(claim) or stale_lock is None
                        or not owner_has_exited(stale_lock)):
                    return OWNED
                try:
                    if os.listdir(claim) != [OWNER_RECORD]:
                        return OWNED
                except OSError:
                    return OWNED
                stale_seats = unique_entries(recorded_seats(read_record(claim)))
            entry = seat_entry(seat, output, run, workspace) if seat and output else None
            record_owner(prepared, owner_lock, entry, stale_seats)
            if stale:
                # Replace the exited owner's record in one rename. The public
                # claim then always holds a complete record naming every stale
                # seat, so a crash at any point leaves them reconcilable.
                try:
                    os.rename(os.path.join(prepared, OWNER_RECORD),
                              os.path.join(claim, OWNER_RECORD))
                except OSError:
                    return OWNED
            else:
                os.rename(prepared, claim)
            published = True
            if stale:
                for stale_seat in stale_seats:
                    print(json.dumps(stale_seat, sort_keys=True))
                return RECLAIMED
            return ACQUIRED
        finally:
            try:
                shutil.rmtree(prepared)
            except FileNotFoundError:
                pass
            except OSError:
                # The published claim no longer needs this scratch directory.
                if not published:
                    raise


def release(claim, owner_lock):
    """Retire a claim under the acquisition guard without losing its owner."""
    claim = absolute_path(claim)
    owner_lock = absolute_path(owner_lock)
    # tempfile returns lexically normalized names, so give it, and the guard,
    # the directory the kernel resolves for this claim.
    directory = os.path.realpath(os.path.dirname(claim))
    with open(os.path.join(directory, GUARD), "a", encoding="utf-8") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        if not os.path.lexists(claim):
            return ACQUIRED
        if recorded_owner_lock(claim) != owner_lock:
            return OWNED
        try:
            with tempfile.TemporaryDirectory(prefix=".retired-claim.",
                                             dir=directory) as retired:
                os.rename(claim, retired)
        except OSError:
            return OWNED
    return ACQUIRED


def main():
    """Dispatch lock acquisition and claim operations for the shell executor."""
    if len(sys.argv) == 3 and sys.argv[1] == "hold":
        return hold(sys.argv[2])
    if len(sys.argv) in (4, 6, 8) and sys.argv[1] == "acquire":
        return acquire(*sys.argv[2:])
    if len(sys.argv) == 4 and sys.argv[1] == "release":
        return release(sys.argv[2], sys.argv[3])
    print("usage: output-claim.py hold FD | acquire CLAIM OWNER_LOCK [SEAT OUTPUT [RUN WORKSPACE]] | release CLAIM OWNER_LOCK", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"output claim: {error}", file=sys.stderr)
        sys.exit(1)
