#!/usr/bin/env python3
"""Fingerprint Tangle correction changes without following worktree symlinks."""

import hashlib
import os
import stat
import subprocess
import sys


def git(root, *args):
    return subprocess.check_output(["git", "-C", root, *args], stderr=subprocess.DEVNULL)


def worktree_entry(root_fd, path):
    parts = path.split(b"/")
    directory = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        name = parts[-1]
        entry = os.stat(name, dir_fd=directory, follow_symlinks=False)
        if stat.S_ISLNK(entry.st_mode):
            return b"link:" + os.readlink(name, dir_fd=directory)
        if not stat.S_ISREG(entry.st_mode):
            return f"mode:{entry.st_mode:o}".encode("ascii")
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(fd, "rb") as source:
            opened = os.fstat(source.fileno())
            if not stat.S_ISREG(opened.st_mode):
                raise OSError("path changed type while fingerprinting")
            digest = hashlib.sha256()
            for chunk in iter(lambda: source.read(65536), b""):
                digest.update(chunk)
        return f"file:{opened.st_mode:o}:{digest.hexdigest()}".encode("ascii")
    except FileNotFoundError:
        return b"missing"
    finally:
        os.close(directory)


def fingerprint(root):
    status = git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames")
    staged = git(root, "diff", "--cached", "--raw", "--no-abbrev", "--no-renames",
                 "--no-ext-diff", "--no-textconv", "-z")
    digest = hashlib.sha256()
    digest.update(hashlib.sha256(staged).digest())
    digest.update(hashlib.sha256(status).digest())
    root_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for entry in status.split(b"\0")[:-1]:
            digest.update(worktree_entry(root_fd, entry[3:]) + b"\0")
    finally:
        os.close(root_fd)
    return digest.hexdigest()


if __name__ == "__main__":
    try:
        print(fingerprint(sys.argv[1]))
    except (OSError, subprocess.CalledProcessError):
        sys.exit(1)
