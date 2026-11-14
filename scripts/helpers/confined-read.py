#!/usr/bin/env python3
"""Read a bounded preview through directory descriptors without following links."""

import os
import stat
import sys


def read_preview(root, path, max_bytes, max_lines):
    """Keep validation and reading on the same regular-file descriptor."""
    # Callers supply the physical trusted root. Do not resolve it again after
    # approval: a replacement symlink must not become a new trusted root.
    root = os.path.abspath(root)
    if not path.startswith(root.rstrip(os.sep) + os.sep):
        raise ValueError("path outside root")
    components = path[len(root.rstrip(os.sep)) + 1:].split(os.sep)
    if any(part in ("", ".", "..") for part in components):
        raise ValueError("invalid path component")
    # Linux O_PATH permits traversal of execute-only ancestors without listing
    # them. Keep no-follow/type checks and the portable read-only fallback.
    directory_flags = getattr(os, 'O_PATH', os.O_RDONLY) | os.O_DIRECTORY | os.O_NOFOLLOW
    directory = os.open(os.sep, directory_flags)
    try:
        for part in root.split(os.sep):
            if not part:
                continue
            child = os.open(part, directory_flags, dir_fd=directory)
            os.close(directory)
            directory = child
        for part in components[:-1]:
            child = os.open(part, directory_flags, dir_fd=directory)
            os.close(directory)
            directory = child
        descriptor = os.open(
            components[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=directory,
        )
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise ValueError("not a regular file")
            data = os.read(descriptor, max_bytes)
        finally:
            os.close(descriptor)
    finally:
        os.close(directory)
    # Ignore an incomplete UTF-8 tail and strip terminal control characters.
    preview = "\n".join(data.decode("utf-8", errors="ignore").split("\n")[:max_lines])
    return "".join(char for char in preview if char in "\n\t" or char.isprintable())


def main():
    try:
        root, path, byte_limit, line_limit = sys.argv[1:]
        byte_limit, line_limit = int(byte_limit), int(line_limit)
        if not 0 < byte_limit <= 1048576 or not 0 < line_limit <= 10000:
            return 1
        preview = read_preview(root, path, byte_limit, line_limit)
    except (OSError, ValueError):
        return 1
    sys.stdout.write(preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
