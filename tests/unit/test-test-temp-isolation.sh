#!/usr/bin/env bash
# Verify private TMPDIR support without sharing parent and nested fixture roots.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "Test temporary directory isolation"
test_case "fixture placement, relative bases, nested cleanup, and explicit overrides"
if python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='octopus-framework-temp-') as base:
    child = Path(base) / 'child.sh'
    child.write_text('''set -eu
unset TEST_TMP_DIR
source "$1/tests/helpers/test-framework.sh"
test_suite nested >/dev/null
printf '%s' "$TEST_TMP_DIR"
''')
    parent = Path(base) / 'parent.sh'
    parent.write_text('''set -eu
unset TEST_TMP_DIR
source "$1/tests/helpers/test-framework.sh"
test_suite parent >/dev/null
[[ "$TEST_TMP_DIR" == "${TMPDIR%/}/"* && "$TEST_TMP_DIR" != *//* ]] || exit 11
mkdir -p "$TEST_TMP_DIR"
touch "$TEST_TMP_DIR/parent-marker"
child_root="$(bash "$2" "$1")"
[[ "$child_root" == "${TMPDIR%/}/"* && "$child_root" != "$TEST_TMP_DIR" ]] || exit 12
[[ ! -d "$child_root" && -f "$TEST_TMP_DIR/parent-marker" ]] || exit 13
printf '%s' "$TEST_TMP_DIR"
''')
    for supplied in [base, base + '/']:
        result = subprocess.run(['bash', str(parent), str(root), str(child)],
                                env=dict(os.environ, TMPDIR=supplied), text=True,
                                capture_output=True, check=True)
        assert not Path(result.stdout).exists(), 'parent cleanup did not run'
    explicit = str(Path(base) / 'explicit')
    result = subprocess.run(['bash', '-c', 'source "$1"; printf "%s" "$TEST_TMP_DIR"',
                             'test', str(root / 'tests/helpers/test-framework.sh')],
                            env=dict(os.environ, TMPDIR=base, TEST_TMP_DIR=explicit),
                            text=True, capture_output=True, check=True)
    assert result.stdout == explicit, 'explicit override was changed'
    launch = Path(base) / 'launch'
    (launch / 'relative-tmp').mkdir(parents=True)
    moved = launch / 'elsewhere'
    moved.mkdir()
    relative = Path(base) / 'relative.sh'
    relative.write_text('''set -eu
unset TEST_TMP_DIR
source "$1/tests/helpers/test-framework.sh"
test_suite relative >/dev/null
[[ "$TEST_TMP_DIR" == /* ]] || exit 21
decoy="$2/relative-tmp/$(basename "$TEST_TMP_DIR")"
mkdir -p "$decoy"
touch "$decoy/preserve"
printf '%s' "$TEST_TMP_DIR"
cd "$2"
''')
    result = subprocess.run(['bash', str(relative), str(root), str(moved)], cwd=launch,
                            env=dict(os.environ, TMPDIR='relative-tmp'),
                            text=True, capture_output=True, check=True)
    original = Path(result.stdout)
    assert original.parent == (launch / 'relative-tmp').resolve(), 'relative base was not anchored'
    assert not original.exists(), 'fixture survived cleanup after changing directory'
    assert (moved / 'relative-tmp' / original.name / 'preserve').is_file(), 'cleanup removed a different directory'
PY
then
    test_pass
else
    test_fail "temporary fixture ownership or cleanup regression"
fi
test_summary
