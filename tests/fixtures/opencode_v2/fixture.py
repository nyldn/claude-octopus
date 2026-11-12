#!/usr/bin/env python3
"""Exercise both OpenCode generations without auth, installs, or model calls."""
import json
import os
import signal
import time
from itertools import product
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(os.environ.get("OCTO_TEST_ROOT", Path(__file__).resolve().parents[3]))

class OpenCodeFixture(unittest.TestCase):
    def setUp(self):
            self.tmp = tempfile.TemporaryDirectory()
            self.addCleanup(self.tmp.cleanup)
            self.base = Path(self.tmp.name)
            self.bin = self.base / "bin"
            self.bin.mkdir()
            # Private wrappers keep fixture overwrites away from host executables.
            for name in (
                    "awk", "base64", "basename", "bash", "cat", "chmod", "cmp", "cp", "cut",
                    "date", "dirname", "env", "expr", "false", "file", "find", "getconf",
                    "git", "gtimeout", "grep", "head", "hostname", "id", "jq", "kill",
                    "ln", "mkdir", "mktemp", "mv", "od", "openssl", "pgrep", "pkill",
                    "printf", "ps", "readlink", "realpath", "rm", "rmdir", "sed", "setsid",
                    "sh", "sha256sum", "shasum", "sleep", "sort", "stat", "tail", "tee",
                    "timeout", "touch", "tr", "true", "uname", "uniq", "wc", "which",
                    "whoami", "xargs"):
                executable = shutil.which(name)
                if executable:
                    private_copy = self.bin / name
                    private_copy.write_text("#!/bin/sh\nexec " + shlex.quote(executable) + ' "$@"\n')
                    private_copy.chmod(0o755)
            python = self.bin / "python3"
            python.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable) + ' "$@"\n')
            python.chmod(0o755)
            self.data = self.base / "data" / "opencode"
            self.data.mkdir(parents=True)
            self.marker = self.base / "called"
            self.cli = self.bin / "opencode"
            self.cli.write_text("""#!/bin/sh
printf called >> "$PROBE_MARKER"
if [ "$1" = --version ]; then sleep "${VERSION_DELAY:-0}"; printf '%s\\n' "${CLI_VERSION:-1.18.34}"; exit 0; fi
if [ "$1" = --pure ]; then exit 64; fi
if [ "$1" = run ]; then
    [ "$OPENCODE_PURE" = 1 ] || exit 65
    printf '%s\\n' "$*"
else
    [ "$1 $2" = 'auth list' ] || exit 66
    case "${CLI_VERSION:-1.18.34}" in
        2.*) [ "$*" = 'auth list --standalone --format json' ] || exit 67 ;;
    esac
    sleep "${AUTH_DELAY:-0}"
    if [ -n "${AUTH_LIST_FILE:-}" ]; then cat "$AUTH_LIST_FILE"; exit 0; fi
    case "$*" in
        *--format*) [ "$*" = 'auth list --standalone --format json' ] || exit 67; printf '%s\\n' "$AUTH_JSON" ;;
        *) printf '%s\\n' "$AUTH_LIST" ;;
    esac
    exit "${AUTH_RC:-0}"
fi
""")
            self.cli.chmod(0o755)
            self.env = {
                "PATH": str(self.bin),
                "HOME": str(self.base / "home"),
                "TMPDIR": str(self.base),
                "XDG_DATA_HOME": str(self.base / "data"),
                "PLUGIN_DIR": str(ROOT),
                "PROBE_MARKER": str(self.marker),
                "AUTH_LIST": "└  2 credentials",
                "AUTH_JSON": json.dumps([{"id": "openai", "connections": [{"type": "credential", "label": "Default"}]}]),
                "OCTO_ALLOWED_PROVIDERS": "opencode",
                "OCTOPUS_SKIP_PROVIDER_PROBES": "false",
            }
            Path(self.env["HOME"]).mkdir()

    def shell(self, script, *, root=ROOT, timeout=8):
            return subprocess.run(["bash", "-c", script], env=self.env, cwd=root,
                                  text=True, capture_output=True, timeout=timeout)

    def production_inventory(self):
            return next(line for line in (ROOT / "scripts/orchestrate.sh").read_text().splitlines()
                        if line.startswith("AVAILABLE_AGENTS=")) + "\n"

    def readiness(self, kind):
            result = self.shell(f'source scripts/lib/preflight.sh; octo_provider_readiness_result opencode {kind}')
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
