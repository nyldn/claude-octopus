#!/usr/bin/env python3
"""Write a private file atomically without following path symlinks."""

from __future__ import annotations

import os
import stat
import sys
import uuid
from typing import Tuple


MAX_INPUT = 1024 * 1024


class UnsafePath(Exception):
    pass


def directory_flags() -> int:
    if not hasattr(os, "O_NOFOLLOW"):
        raise UnsafePath("this platform cannot reject directory symlinks")
    return (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_CLOEXEC", 0)
        | os.O_NOFOLLOW
    )


def validate_ancestor(fd: int) -> None:
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode):
        raise UnsafePath("path component is not a directory")
    permissions = stat.S_IMODE(info.st_mode)
    shared_write = permissions & (stat.S_IWGRP | stat.S_IWOTH)
    if shared_write and not permissions & stat.S_ISVTX:
        raise UnsafePath("path component is writable by another user")


def validate_private_directory(fd: int) -> None:
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise UnsafePath("destination directory has the wrong owner")
    try:
        os.fchmod(fd, 0o700)
    except OSError as exc:
        raise UnsafePath("destination directory permissions cannot be secured") from exc


def open_child_directory(parent_fd: int, name: str) -> int:
    flags = directory_flags()
    for _attempt in range(3):
        try:
            return os.open(name, flags, dir_fd=parent_fd)
        except FileNotFoundError:
            try:
                os.mkdir(name, 0o700, dir_fd=parent_fd)
            except FileExistsError:
                continue
            except OSError as exc:
                raise UnsafePath("destination directory cannot be created") from exc
        except OSError as exc:
            raise UnsafePath("destination path contains an unsafe component") from exc
    raise UnsafePath("destination path changed during creation")


def resolve_trusted_root(target: str) -> str:
    absolute = os.path.abspath(target)
    for variable in ("HOME", "TMPDIR"):
        raw_root = os.environ.get(variable)
        if not raw_root:
            continue
        lexical_root = os.path.abspath(raw_root)
        try:
            inside_root = os.path.commonpath((absolute, lexical_root)) == lexical_root
        except ValueError:
            inside_root = False
        if not inside_root:
            continue
        resolved_root = os.path.realpath(lexical_root)
        relative = os.path.relpath(absolute, lexical_root)
        return os.path.join(resolved_root, relative)
    return absolute


def open_destination_directory(target: str) -> Tuple[int, str]:
    absolute = resolve_trusted_root(target)
    directory, filename = os.path.split(absolute)
    if not filename or filename in {".", ".."}:
        raise UnsafePath("destination filename is invalid")

    components = [component for component in directory.split(os.sep) if component]
    current_fd = os.open(os.sep, directory_flags())
    try:
        validate_ancestor(current_fd)
        for index, component in enumerate(components):
            next_fd = open_child_directory(current_fd, component)
            os.close(current_fd)
            current_fd = next_fd
            if index == len(components) - 1:
                validate_private_directory(current_fd)
            else:
                validate_ancestor(current_fd)
        if not components:
            validate_private_directory(current_fd)
        return current_fd, filename
    except Exception:
        os.close(current_fd)
        raise


def validate_existing_file(directory_fd: int, filename: str) -> None:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NONBLOCK", 0)
    flags |= os.O_NOFOLLOW
    try:
        fd = os.open(filename, flags, dir_fd=directory_fd)
    except FileNotFoundError:
        return
    except OSError as exc:
        raise UnsafePath("destination file is unsafe") from exc
    try:
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
        ):
            raise UnsafePath("destination is not a private regular file")
    finally:
        os.close(fd)


def read_payload() -> bytes:
    payload = sys.stdin.buffer.read(MAX_INPUT + 1)
    if len(payload) > MAX_INPUT:
        raise UnsafePath("input exceeds 1 MiB")
    return payload


def atomic_write(target: str, payload: bytes) -> None:
    directory_fd, filename = open_destination_directory(target)
    temp_name = "." + filename + ".tmp." + uuid.uuid4().hex
    temp_fd = -1
    try:
        validate_existing_file(directory_fd, filename)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
        temp_fd = os.open(temp_name, flags, 0o600, dir_fd=directory_fd)
        offset = 0
        while offset < len(payload):
            offset += os.write(temp_fd, payload[offset:])
        os.fchmod(temp_fd, 0o600)
        os.fsync(temp_fd)
        os.close(temp_fd)
        temp_fd = -1
        os.replace(
            temp_name,
            filename,
            src_dir_fd=directory_fd,
            dst_dir_fd=directory_fd,
        )
        os.fsync(directory_fd)
    finally:
        if temp_fd >= 0:
            os.close(temp_fd)
        try:
            os.unlink(temp_name, dir_fd=directory_fd)
        except OSError:
            pass
        os.close(directory_fd)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: private-atomic-write.py TARGET", file=sys.stderr)
        return 2
    try:
        atomic_write(sys.argv[1], read_payload())
    except (OSError, UnsafePath) as exc:
        print(f"private write refused: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
