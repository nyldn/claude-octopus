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
failures = []
checked = 0
for conditional in (False, True):
    for scenario in ('mkdir', 'project identity', 'render', 'corrupt backup'):
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
                'project identity': 'state_project_id() { command touch "$FAILURE_MARKER"; return 23; }; ',
                'render': 'cat() { command touch "$FAILURE_MARKER"; return 23; }; ',
                'corrupt backup': 'mv() { command touch "$FAILURE_MARKER"; return 23; }; ',
            }[scenario]
            call = 'if init_state; then exit 0; else exit $?; fi' if conditional else 'set +e; init_state; exit $?'
            env = dict(os.environ, OCTOPUS_WORKFLOW_STATE_DIR=str(state_dir), FAILURE_MARKER=str(marker))
            result = subprocess.run(['bash', '-c', 'source "$1"; ' + injection + call, 'test', helper],
                                    env=env, capture_output=True, text=True, timeout=10)
            retained = state.read_bytes() if state.exists() else None
            if not (marker.exists() and result.returncode != 0 and retained == original and 'SUCCESS:' not in result.stdout):
                failures.append(f'{scenario}: conditional={conditional}, exit={result.returncode}, reached={marker.exists()}, preserved={retained == original}')
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
test_summary
