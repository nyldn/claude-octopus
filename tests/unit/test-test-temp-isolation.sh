#!/usr/bin/env bash
# Verify private TMPDIR support without sharing parent and nested fixture roots.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
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
print('PASS: TMPDIR placement, unique nested roots, and independent cleanup')
PY
