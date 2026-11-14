#!/usr/bin/env bash
# Descriptor reads must reject replacement links and bound long single lines.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Confined preview reader"
test_case "descriptor confinement, replacement races, and bounded reads"
if PYTHONDONTWRITEBYTECODE=1 python3 - "$SCRIPT_DIR/../../scripts/helpers/confined-read.py" "$TEST_TMP_DIR" <<'PY'
import importlib.util
import os
from pathlib import Path
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("confined_read", sys.argv[1])
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
root = Path(sys.argv[2]).resolve() / "corpus"
root.mkdir()
secret = root.parent / "secret"
secret.write_text("EXTERNAL_SECRET")
target = root / "report.md"
target.write_text("safe preview\n")
assert reader.read_preview(str(root), str(target), 100, 80) == "safe preview\n"

# Linux path descriptors need search permission, not directory-list permission.
if hasattr(os, 'O_PATH') and os.geteuid() != 0:
    ancestor = root.parent / 'search-only'
    searchable_root = ancestor / 'readable'
    searchable_root.mkdir(parents=True)
    readable = searchable_root / 'report.md'
    readable.write_text('reachable without listing ancestors')
    ancestor.chmod(0o100)
    try:
        assert readable.read_text() == 'reachable without listing ancestors'
        assert reader.read_preview(str(searchable_root), str(readable), 100, 80) == readable.read_text()
    finally:
        ancestor.chmod(0o700)

def rejects(path):
    try:
        reader.read_preview(str(root), str(path), 100, 80)
    except (OSError, ValueError):
        return
    raise AssertionError("unsafe path accepted")

rejects(secret)
target.unlink()
target.symlink_to(secret)
rejects(target)
target.unlink()
target.write_text("safe preview")
real_open = os.open

def replace_before_open(path, flags, **kwargs):
    if path == "report.md":
        target.unlink()
        target.symlink_to(secret)
    return real_open(path, flags, **kwargs)

# The swap occurs after the directory was opened, exactly before the leaf open.
with patch.object(reader.os, "open", replace_before_open):
    rejects(target)
target.unlink()
target.write_text("safe preview")
directory = root / "nested"
directory.mkdir()
(directory / "report.md").write_text("safe nested")
outside = root.parent / "external"
outside.mkdir()
(outside / "report.md").write_text("EXTERNAL_SECRET")

def replace_directory(path, flags, **kwargs):
    if path == "nested":
        directory.rename(root / "original")
        directory.symlink_to(outside)
    return real_open(path, flags, **kwargs)

with patch.object(reader.os, "open", replace_directory):
    rejects(directory / "report.md")

target.write_text("x" * 2000000)
assert len(reader.read_preview(str(root), str(target), 16384, 80)) == 16384
target.write_text("a\n" * 100)
assert reader.read_preview(str(root), str(target), 1000, 80).count("\n") == 79
target.unlink()
os.mkfifo(target)
rejects(target)
PY
then test_pass
else test_fail "confined read regression failed"
fi
test_summary
