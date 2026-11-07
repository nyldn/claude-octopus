#!/usr/bin/env python3
"""Acquire parallel output claims, reclaiming one only after its owner is gone.

The owning invocation keeps an flock on its owner lock through a descriptor that
every worker and provider it starts inherits. flock locks belong to the open
file description, so the lock stays held until the controller and all of those
descendants have exited. A claim whose owner lock can be taken is stale.
"""

import fcntl
import os
import sys
import tempfile

OWNER_RECORD = "owner"
OWNER_LOCK_PREFIX = ".parallel-owner."
GUARD = ".output-claims.lock"
ACQUIRED, OWNED, RECLAIMED = 0, 10, 11


def hold(descriptor):
    fcntl.flock(int(descriptor), fcntl.LOCK_EX | fcntl.LOCK_NB)
    return 0


def recorded_owner_lock(claim):
    try:
        descriptor = os.open(os.path.join(claim, OWNER_RECORD), os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return None
    with os.fdopen(descriptor, encoding="utf-8") as record:
        owner_lock = record.read(4096).strip()
    name = os.path.basename(owner_lock)
    if (not name.startswith(OWNER_LOCK_PREFIX)
            or os.path.realpath(os.path.dirname(owner_lock))
            != os.path.realpath(os.path.dirname(claim))):
        return None
    return owner_lock


def owner_has_exited(owner_lock):
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


def record_owner(claim, owner_lock):
    descriptor = os.open(os.path.join(claim, OWNER_RECORD),
                         os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as record:
        record.write(owner_lock + "\n")


def acquire(claim, owner_lock):
    claim = os.path.abspath(claim)
    owner_lock = os.path.abspath(owner_lock)
    with open(os.path.join(os.path.dirname(claim), GUARD), "a", encoding="utf-8") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        # Publish only a complete owner record. A killed preparer can leave a
        # private directory, but cannot strand an ownerless claim at this path.
        with tempfile.TemporaryDirectory(prefix=".output-claim.", dir=os.path.dirname(claim)) as prepared:
            record_owner(prepared, owner_lock)
            outcome = ACQUIRED
            if os.path.lexists(claim):
                stale_lock = recorded_owner_lock(claim)
                if stale_lock is None or not owner_has_exited(stale_lock):
                    return OWNED
                try:
                    if os.listdir(claim) != [OWNER_RECORD]:
                        return OWNED
                    # Retire the complete record atomically before deleting it.
                    # A crash or cleanup error must never leave an ownerless
                    # public claim that all later acquisitions treat as live.
                    with tempfile.TemporaryDirectory(prefix=".retired-claim.",
                                                     dir=os.path.dirname(claim)) as retired:
                        os.rename(claim, retired)
                except OSError:
                    return OWNED
                outcome = RECLAIMED
            os.rename(prepared, claim)
            return outcome


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "hold":
        return hold(sys.argv[2])
    if len(sys.argv) == 4 and sys.argv[1] == "acquire":
        return acquire(sys.argv[2], sys.argv[3])
    print("usage: output-claim.py hold FD | acquire CLAIM OWNER_LOCK", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"output claim: {error}", file=sys.stderr)
        sys.exit(1)
