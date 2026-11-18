#!/usr/bin/env bash
# Project initialization must not write through a workspace-supplied .octo link.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "project initialization symlink boundary"
test_case "CLI and sourced initialization preserve linked targets and recover after refusal"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_BOUNDARY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

helper = os.environ.get('OCTO_PROJECT_INIT_TEST_HELPER', str(Path(sys.argv[1]) / 'scripts/octo-state.sh'))
failures = []
checked = 0
for mode in ('cli', 'sourced', 'conditional'):
    for kind in ('empty', 'initialized', 'missing', 'file'):
        for relative in (False, True):
            with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                directory = Path(temporary)
                project = directory / 'project'
                project.mkdir()
                target = directory / 'target'
                if kind == 'file':
                    target.write_bytes(b'existing external file\n')
                elif kind != 'missing':
                    target.mkdir()
                    (target / 'retained').write_bytes(b'existing external content\n')
                    if kind == 'initialized':
                        (target / 'STATE.md').write_bytes(b'existing external state\n')
                def snapshot():
                    if not target.exists():
                        return None
                    if target.is_file():
                        return target.read_bytes()
                    return sorted((str(p.relative_to(target)), p.read_bytes() if p.is_file() else None)
                                  for p in target.rglob('*'))
                before = snapshot()
                link = project / '.octo'
                destination = '../target' if relative else str(target)
                link.symlink_to(destination)
                env = dict(os.environ, OCTOPUS_PROJECT_PERSISTENCE='true')
                command = ([ 'bash', helper, 'init_project'] if mode == 'cli' else
                           ['bash', '-c', 'source "$1"; shift; ' +
                            ('if init_project "$@"; then exit 0; else exit $?; fi' if mode == 'conditional'
                             else 'set +e; init_project "$@"; exit $?'), 'test', helper])
                result = subprocess.run(command, cwd=project, env=env, capture_output=True, text=True, timeout=10)
                valid = (result.returncode != 0 and '.octo' in result.stderr and 'symlink' in result.stderr
                         and 'Initialized .octo/' not in result.stdout and link.is_symlink()
                         and os.readlink(link) == destination and snapshot() == before)
                if not valid:
                    failures.append(f'{mode}, {kind}, relative={relative}: refusal or target preservation failed')
                checked += 1
                after_refusal = snapshot()
                # An explicit preview still inspects a linked workspace without writing.
                skipped = subprocess.run(command + ['--dry-run'], cwd=project, env=env,
                                         capture_output=True, timeout=10)
                assert skipped.returncode == 0 and snapshot() == after_refusal, 'dry run changed the target'
                # Removing the obstruction permits a real project initialization.
                link.unlink()
                retry = subprocess.run(command, cwd=project, env=env, capture_output=True, timeout=10)
                assert retry.returncode == 0 and not link.is_symlink() and snapshot() == after_refusal, 'retry changed the external target'
                assert all((link / name).is_file() for name in
                           ('STATE.md', 'PROJECT.md', 'ROADMAP.md', 'config.json', 'ISSUES.md', 'LESSONS.md'))
print(f'{checked - len(failures)}/{checked} production symlink refusal, dry-run and retry scenarios passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_BOUNDARY
then test_pass; else test_fail "project initialization crossed its symlink boundary"; fi
test_summary
