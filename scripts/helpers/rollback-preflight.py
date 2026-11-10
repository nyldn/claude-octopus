#!/usr/bin/env python3
"""Reject rollback when committed checkpoints cannot recover local work."""

import os
from pathlib import PurePosixPath
import subprocess
import sys


def check_tree(checkpoint):
    """Allow ignored files only when checkpoint restoration cannot touch them."""
    root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"]).rstrip(b"\n")

    def git(*arguments):
        return subprocess.check_output(["git", "-C", os.fsdecode(root), *arguments])

    if git("status", "--porcelain=v1", "--untracked-files=all"):
        raise ValueError("preserve staged, unstaged and untracked work first")
    # Status omits assume-unchanged and skip-worktree edits. Leave the user's
    # flags intact and require deliberate preservation before any restoration.
    for entry in git("ls-files", "-v", "-z").split(b"\0"):
        if entry and (entry[:1].islower() or entry[:1] == b"S"):
            raise ValueError("preserve work and clear assume-unchanged/skip-worktree flags before rollback")
    commit = git("rev-parse", "--verify", "--end-of-options", checkpoint + "^{commit}").strip().decode("ascii")
    paths = {os.fsdecode(path) for path in git("ls-tree", "-rz", "--name-only", commit).split(b"\0") if path}
    # Excluding a child path cannot stop restore from replacing its directory.
    # A historical file/symlink at .octo would destroy current protected lessons.
    if ".octo" in paths and os.path.lexists(os.path.join(os.fsdecode(root), ".octo", "LESSONS.md")):
        raise ValueError("checkpoint replaces .octo and would remove protected LESSONS.md")
    directories = {str(parent) for path in paths for parent in PurePosixPath(path).parents}
    ignored = git("ls-files", "-z", "--others", "--ignored", "--exclude-standard")
    for raw_path in ignored.split(b"\0"):
        if not raw_path:
            continue
        # Git collapses ignored nested repositories to a directory entry.
        path = os.fsdecode(raw_path).rstrip("/")
        if path in paths or path in directories or any(str(parent) in paths for parent in PurePosixPath(path).parents):
            raise ValueError(f"preserve ignored path {path!r} before restoring this checkpoint")


def main():
    """Fail closed on unavailable Git state or a local-file collision."""
    if len(sys.argv) != 2:
        print("usage: rollback-preflight.py CHECKPOINT", file=sys.stderr)
        return 2
    try:
        check_tree(sys.argv[1])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Rollback stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
