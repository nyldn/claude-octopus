#!/usr/bin/env python3
"""Sample changed-path metadata without opening file contents."""
import os
import subprocess
import sys

def fractional_pre_epoch_signature(path, size):
    """Preserve the installed stat's legacy rounding, including signed zero."""
    for option, pattern in (("-f", "%z:%m"), ("-c", "%s:%Y")):
        try:
            result = subprocess.run(["stat", option, pattern, path],
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                    timeout=2, check=False)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0:
            return result.stdout.rstrip(b"\n")
    return str(size).encode() + b":unknown"


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
            if st.st_mtime_ns < 0 and st.st_mtime_ns % 1_000_000_000:
                # BSD, GNU and uutils stat do not all format this case alike.
                # Only these rare files need the legacy metadata-only command.
                signature = fractional_pre_epoch_signature(path, st.st_size)
            else:
                signature = (str(st.st_size) + ":" + str(st.st_mtime_ns // 1_000_000_000)).encode()
    except OSError:
        # A concurrent rename or permission failure must not read file data.
        signature = b"0:unknown"
    out.write(b"path=" + rel + b";" + signature + b"\n")
