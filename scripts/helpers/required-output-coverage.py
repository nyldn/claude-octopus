#!/usr/bin/env python3
"""Check declared output scopes without treating read context as deliverables."""
import os
from pathlib import Path
import subprocess
import sys


def missing_outputs(root, paths, baseline):
    root = Path(root).resolve(strict=True)
    deleted = set()
    if baseline and len(baseline) == 40 and all(c in "0123456789abcdefABCDEF" for c in baseline):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_OPTIONAL_LOCKS="0")
        proc = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", str(root), "diff", "--no-ext-diff", "--no-textconv", "--name-only", "--diff-filter=D", "-z", baseline, "--"], env=env, capture_output=True, timeout=10, check=True)
        deleted = set(os.fsdecode(proc.stdout).split("\0"))
    for raw in paths:
        path = Path(raw)
        # Scope validation owns write authority. Never let coverage widen reads.
        if path.is_absolute() or ".." in path.parts or ".git" in path.parts:
            yield raw
            continue
        candidate = root / path
        try:
            relative = candidate.resolve().relative_to(root)
            current = root
            for part in relative.parts:
                current /= part
                if current.is_symlink():
                    raise ValueError("symbolic output")
            # Check lexical parents too: resolve() must not hide an alias.
            current = root
            for part in path.parts:
                current /= part
                if current.is_symlink():
                    raise ValueError("symbolic output")
            if candidate.is_file():
                continue
            if candidate.is_dir():
                found = False
                for directory, dirs, files in os.walk(candidate, followlinks=False):
                    dirs[:] = [d for d in dirs if d != ".git" and not Path(directory, d).is_symlink()]
                    if any(Path(directory, f).is_file() and not Path(directory, f).is_symlink() for f in files):
                        found = True
                        break
                if found:
                    continue
            elif path.as_posix() in deleted:
                continue
        except (OSError, ValueError):
            pass
        yield raw


if __name__ == "__main__":
    payload = sys.stdin.read(1048577)
    if len(payload) > 1048576:
        raise SystemExit("Output scope input too large")
    paths = [p.strip() for p in payload.splitlines() if p.strip()]
    if len(paths) > 4096:
        raise SystemExit("Too many output scopes")
    for item in missing_outputs(sys.argv[1], paths, sys.argv[2] if len(sys.argv) > 2 else ""):
        print(item)
