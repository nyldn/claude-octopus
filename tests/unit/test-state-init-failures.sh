#!/usr/bin/env bash
# Initialization must propagate failures even when sourced into a condition.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "workflow state initialization failures"
test_case "initialization preserves recoverable state and reports each failed operation"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_INIT'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

helper = os.environ.get('OCTO_INIT_STATE_TEST_HELPER', str(Path(sys.argv[1]) / 'scripts/state-manager.sh'))
shell = os.environ.get('OCTO_INIT_STATE_TEST_SHELL', 'bash')
failures = []
checked = 0
for conditional in (False, True):
    for scenario in ('mkdir', 'project identity', 'digest failure', 'empty digest', 'render', 'corrupt backup'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            directory = Path(temporary)
            state_dir = directory / 'state'
            state_dir.mkdir()
            state = state_dir / 'state.json'
            marker = directory / 'reached'
            if scenario == 'corrupt backup':
                state.write_text('{broken state retained for recovery\n')
            original = state.read_bytes() if state.exists() else None
            injection = {
                'mkdir': 'mkdir() { if [[ "${!#}" == "$STATE_DIR/context" ]]; then command touch "$FAILURE_MARKER"; return 23; fi; command mkdir "$@"; }; ',
                'digest failure': 'sha256sum() { command touch "$FAILURE_MARKER"; return 23; }; ',
                'empty digest': 'sha256sum() { command touch "$FAILURE_MARKER"; return 0; }; ',
                'project identity': 'state_project_id() { command touch "$FAILURE_MARKER"; return 23; }; ',
                'render': 'cat() { command touch "$FAILURE_MARKER"; return 23; }; ',
                'corrupt backup': 'mv() { command touch "$FAILURE_MARKER"; return 23; }; ',
            }[scenario]
            call = 'if init_state; then exit 0; else exit $?; fi' if conditional else 'set +e; init_state; exit $?'
            env = dict(os.environ, OCTOPUS_WORKFLOW_STATE_DIR=str(state_dir), FAILURE_MARKER=str(marker))
            result = subprocess.run([shell, '-c', 'source "$1"; ' + injection + call, 'test', helper],
                                    env=env, capture_output=True, text=True, timeout=10)
            retained = state.read_bytes() if state.exists() else None
            if not (marker.exists() and result.returncode != 0 and retained == original and 'SUCCESS:' not in result.stdout):
                failures.append(f'{scenario}: conditional={conditional}, exit={result.returncode}, reached={marker.exists()}, preserved={retained == original}, stderr={result.stderr}')
            checked += 1
for invalid in ('', ' \n\t', 'null', '[]', '42', '{}\n{}', '{broken'):
    with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
        directory = Path(temporary)
        state = directory / 'state.json'
        state.write_text(invalid)
        env = dict(os.environ, OCTOPUS_WORKFLOW_STATE_DIR=str(directory))
        result = subprocess.run([helper, 'init_state'], env=env, capture_output=True, timeout=10)
        try:
            document = json.loads(state.read_text())
        except ValueError:
            document = None
        backups = list(directory.glob('state.json.corrupt.*'))
        if (result.returncode != 0 or not isinstance(document, dict) or document.get('metrics', {}).get('phases_completed') != 0
                or len(backups) != 1 or backups[0].read_text() != invalid):
            failures.append(f'invalid state not recoverably initialized: {invalid!r}')
        checked += 1
        before = state.read_bytes()
        retry = subprocess.run([helper, 'init_state'], env=env, capture_output=True, timeout=10)
        if retry.returncode != 0 or state.read_bytes() != before:
            failures.append('repeat initialization changed saved state')
        checked += 1
print(f'{checked - len(failures)}/{checked} production initialization failure/recovery controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_INIT
then test_pass; else test_fail "initialization accepted a failed operation or invalid state"; fi
test_case "failed default identity cannot read or modify a shared or previous namespace"
if python3 -I - "$PROJECT_ROOT/scripts/state-manager.sh" "$TEST_TMP_DIR" <<'PY_IDENTITY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

checked = 0
for scenario in ('failure', 'empty'):
    for mode in ('cli', 'sourced', 'resourced', 'override'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            directory = Path(temporary)
            workspace = directory / 'workspace'
            state = workspace / 'projects/state.json'
            state.parent.mkdir(parents=True)
            state.write_text('{"context":{},"metrics":{},"decisions":[]}\n')
            before = state.read_bytes()
            marker = directory / 'survived'
            injection = 'sha256sum() { return ' + ('23' if scenario == 'failure' else '0') + '; }; '
            program = injection + '''
if [[ "$2" == resourced ]]; then
    OCTOPUS_WORKFLOW_STATE_DIR="$3/saved" source "$1" || exit 24
    unset OCTOPUS_WORKFLOW_STATE_DIR
fi
if [[ "$2" == override ]]; then export OCTOPUS_WORKFLOW_STATE_DIR="$3/explicit"; fi
if source "$1"; then
    [[ "$2" == override ]] || { update_context define corrupted; exit 0; }
    [[ "$STATE_FILE" == "$3/explicit/state.json" ]] || exit 25
    command touch "$4"
    exit 0
fi
[[ -z "${STATE_DIR:-}${STATE_FILE:-}${BACKUP_FILE:-}" ]] || exit 26
command touch "$4"
exit 1
'''
            env = dict(os.environ, CLAUDE_PLUGIN_DATA=str(workspace))
            env.pop('OCTOPUS_WORKFLOW_STATE_DIR', None)
            if mode == 'cli':
                program = injection + 'export -f sha256sum; exec bash "$1" update_context define corrupted'
            result = subprocess.run(['bash', '-c', program, 'test', sys.argv[1], mode, str(directory), str(marker)],
                                    env=env, capture_output=True, text=True, timeout=10)
            assert state.read_bytes() == before, (scenario, mode, 'shared state modified')
            assert not (state.parent / 'state.json.backup').exists(), (scenario, mode, 'shared state read for backup')
            if mode == 'override':
                assert result.returncode == 0 and marker.exists(), (scenario, mode, result.stderr)
            else:
                assert result.returncode != 0, (scenario, mode, 'identity failure accepted')
                if mode != 'cli':
                    assert marker.exists(), (scenario, mode, 'source exited its caller or retained a namespace', result.stderr)
            checked += 1
print(f'{checked}/{checked} actual default-namespace identity controls passed')
PY_IDENTITY
then test_pass; else test_fail "identity failure admitted an unrelated state namespace"; fi

test_case "directory destinations cannot report successful initialization"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_DIRECTORY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

helper = os.environ.get('OCTO_INIT_STATE_TEST_HELPER', str(Path(sys.argv[1]) / 'scripts/state-manager.sh'))
checked = 0
for conditional in (False, True):
    for late in (False, True):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            directory = Path(temporary)
            state = directory / 'state.json'
            if not late:
                state.mkdir()
                (state / 'retained').write_text('retain this directory')
            inject = '''
obstruct() { command mkdir "$STATE_FILE" && command touch "$STATE_FILE/retained"; }
mv() { if [[ "${2:-}" == "$STATE_FILE" ]]; then obstruct || return 1; fi; command mv "$@"; }
python3() { if [[ "${3:-}" == *os.replace* ]]; then obstruct || return 1; fi; command python3 "$@"; }
''' if late else ''
            call = 'if init_state; then exit 0; else exit $?; fi' if conditional else 'init_state; exit $?'
            result = subprocess.run(['bash', '-c', 'source "$1"; ' + inject + call, 'test', helper],
                env=dict(os.environ, OCTOPUS_WORKFLOW_STATE_DIR=str(directory)), capture_output=True, text=True, timeout=10)
            assert result.returncode != 0 and 'SUCCESS:' not in result.stdout, (conditional, late, result.stdout, result.stderr)
            assert state.is_dir() and sorted(p.name for p in state.iterdir()) == ['retained'], 'directory modified'
            assert not list(directory.glob('state.json.tmp.*')), 'unpublished temporary state retained'
            checked += 1
print(f'{checked}/{checked} directory destination controls passed')
PY_DIRECTORY
then test_pass; else test_fail "directory destination accepted or modified"; fi

test_summary
