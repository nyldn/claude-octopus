#!/usr/bin/env python3
"""Run OpenCode admission without loading credential-bearing project code."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def within(path, root):
    return path == root or root in path.parents


def refuse(reason):
    print("OpenCode admission refused: " + reason, file=sys.stderr)
    return 125


def main():
    mode, project, *args = sys.argv[1:]
    roots = {Path(project).resolve()}
    if Path.cwd().resolve() != Path.home().resolve():
        roots.add(Path.cwd().resolve())
    selected = shutil.which("opencode")
    if selected is None:
        return 1
    executable = Path(selected).resolve()
    if any(within(executable, root) for root in roots):
        return refuse("the selected executable is inside the project")
    env = dict(os.environ)
    env.update(OPENCODE_PURE="1", OPENCODE_CONFIG_PROJECT_DISABLE="1",
               OPENCODE_DISABLE_PROJECT_CONFIG="1")
    env.pop("KEENABLE_API_KEY", None)
    if mode != "login":
        for name in list(env):
            if any(part in name for part in ("API_KEY", "SECRET", "PASSWORD", "CREDENTIAL")) or "_TOKEN" in name:
                del env[name]
    for name in ("HOME", "XDG_CONFIG_HOME", "OPENCODE_CONFIG_DIR", "OPENCODE_CONFIG"):
        if env.get(name):
            path = Path(env[name]).resolve()
            if any(within(path, root) for root in roots):
                return refuse("a selected configuration path is inside the project")
            env[name] = os.path.abspath(env[name])
    # Inline configuration can name project plugins without a path selector.
    env.pop("OPENCODE_CONFIG_CONTENT", None)
    env["PATH"] = os.pathsep.join(
        str(path) for entry in env.get("PATH", "").split(os.pathsep)
        for path in [Path(entry or ".").resolve()]
        if not any(within(path, root) for root in roots))
    if mode.startswith("login"):
        with tempfile.TemporaryDirectory(prefix="octopus-opencode-probe-", dir="/tmp") as directory:
            completed = subprocess.run([str(executable), *args], env=env, cwd=directory,
                                       stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        completed = subprocess.run([str(executable), *args], env=env,
                                   stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return completed.returncode if completed.returncode >= 0 else 128 - completed.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError):
        sys.exit(refuse("the isolated probe could not start"))
