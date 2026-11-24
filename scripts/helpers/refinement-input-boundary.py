#!/usr/bin/env python3
"""Stage only the blind request, then enforce the selected client's read boundary."""
import importlib.util
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import tempfile


def codex_boundary(directory, helper):
    """Exercise the same permissions profile locally before any provider call."""
    spec = importlib.util.spec_from_file_location("refinement_policy", helper)
    policy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(policy)
    # This sentinel is invented test data, never a user's credential file.
    with tempfile.TemporaryDirectory(prefix="octopus-refine-denied-") as outside:
        denied = Path(outside) / "canary"
        denied.write_text("not-a-real-secret")
        command = ('/bin/cat ' + shlex.quote(str(directory / "request.txt"))
                   + ' >/dev/null && ! /bin/cat ' + shlex.quote(str(denied))
                   + ' >/dev/null 2>&1')
        result = subprocess.run(
            ["codex", "sandbox", *policy.flags([]), "-P", policy.profile_name(directory),
             "-C", str(directory), "--", "/bin/sh", "-c", command],
            capture_output=True, timeout=15)
        if result.returncode:
            raise ValueError("Codex cannot enforce the scoped judge read boundary")


def main():
    scripts, provider, timeout, prompt, task, output = sys.argv[1:]
    scripts = Path(scripts).resolve(strict=True)
    prompt = Path(prompt).resolve(strict=True)
    output = Path(output).resolve(strict=True)
    staged = None

    def interrupted(signum, _frame):
        # Clean before unwinding subprocess.run: its child may ignore TERM and
        # prevent that context manager from returning before the controller KILL.
        if staged is not None:
            staged.cleanup()
        raise SystemExit(128 + signum)

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, interrupted)
    try:
        # A new empty directory prevents project instructions, symlinks, or
        # other run files from becoming implicit judge inputs.
        staged = tempfile.TemporaryDirectory(prefix="octopus-refine-input-")
        with staged as temporary:
            directory = Path(temporary).resolve()
            request = directory / "request.txt"
            request.write_bytes(prompt.read_bytes())
            request.chmod(0o400)
            os.environ["OCTOPUS_REFINEMENT_INPUT_DIR"] = str(directory)
            os.environ["OCTOPUS_PROJECT_DIR"] = str(directory)
            os.environ.pop("CLAUDE_PROJECT_DIR", None)
            if provider.split(":", 1)[0].startswith("codex"):
                codex_boundary(directory, scripts / "helpers/refinement-codex-policy.py")
            else:
                launcher = shlex.split(os.environ["OCTOPUS_CLAUDE_BIN"])
                help_result = subprocess.run([launcher[0], "--help"], capture_output=True,
                                             text=True, timeout=15, check=True)
                if not all(flag in help_result.stdout for flag in ("--restricted", "--safe-mode")):
                    raise ValueError("Claude requires --restricted and --safe-mode for judging")
            return subprocess.run(
                [str(scripts / "orchestrate.sh"), "--timeout", timeout,
                 "probe-single", provider, "--perspective-file", str(request), task,
                 "--output-dir", str(output)], cwd=directory).returncode
    except (ValueError, OSError, subprocess.SubprocessError):
        # Provider diagnostics or configuration may contain sensitive data.
        print("ERROR: cannot establish the refinement input boundary; no judge dispatched",
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
