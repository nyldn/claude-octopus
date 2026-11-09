#!/usr/bin/env python3
"""Sample changed-path metadata without opening file contents."""
import os
import sys

root = os.fsencode(sys.argv[1])
out = sys.stdout.buffer
for rel in sys.stdin.buffer.read().split(b"\0"):
    if not rel or rel == b".octo" or rel.startswith(b".octo/"):
        continue
    signature = b"missing"
    try:
        path = os.path.join(root, rel)
        # The shell implementation first tests -e, then stats the link itself.
        if os.path.exists(path):
            st = os.lstat(path)
            signature = (str(st.st_size) + ":" + str(st.st_mtime_ns // 1_000_000_000)).encode()
    except OSError:
        # A concurrent rename or permission failure must not read file data.
        signature = b"0:unknown"
    out.write(b"path=" + rel + b";" + signature + b"\n")
