"""Install inert client capability stubs for dispatch contract tests."""
import shutil
from pathlib import Path


def install(root, scripts):
    helpers = scripts / "helpers"
    helpers.mkdir(exist_ok=True)
    for name in ("refinement-input-boundary.py", "refinement-codex-policy.py"):
        shutil.copy2(root / "scripts/helpers" / name, helpers / name)
    binaries = scripts / "fake-clients"
    binaries.mkdir()
    for name in ("codex", "claude", "custom-claude"):
        binary = binaries / name
        binary.write_text("#!/bin/sh\ncase \"$1\" in\n--help) echo --restricted --safe-mode;;\nsandbox) exit \"${TEST_BOUNDARY_FAILURE:-0}\";;\n*) exit 90;;\nesac\n")
        binary.chmod(0o755)
    return str(binaries)
