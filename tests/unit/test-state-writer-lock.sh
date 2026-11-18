#!/usr/bin/env bash
# Pause the first real jq read so concurrent writers cannot accidentally pass.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "workflow state writer transactions"
test_case "CLI and sourced writers serialize read through publication"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_LOCK'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

root = Path(sys.argv[1])
helper = Path(os.environ.get('OCTO_WRITER_LOCK_TEST_HELPER', str(root / 'scripts/state-manager.sh')))
failures = []
operations = [
    ('complete_define', ['{synthesis}', 'second context', 'second decision']),
    ('set_current_workflow', ['tangle', 'develop']),
    ('write_decision', ['develop', 'second decision', 'reason']),
    ('write_blocker', ['second blocker', 'develop']),
    ('update_blocker_status', ['existing blocker', 'resolved']),
    ('update_context', ['develop', 'second context']),
    ('update_metrics', ['execution_time', '42']),
    ('init_state', []),
]
for mode in ('cli', 'sourced'):
    for operation, arguments in operations:
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            directory = Path(temporary)
            env = dict(os.environ, OCTOPUS_WORKFLOW_STATE_DIR=str(directory / 'state'))
            subprocess.run([str(helper), 'init_state'], env=env, check=True, capture_output=True)
            subprocess.run([str(helper), 'write_blocker', 'existing blocker', 'define'], env=env, check=True, capture_output=True)
            first_synthesis = directory / 'first.md'
            second_synthesis = directory / 'second.md'
            first_synthesis.write_text('first synthesis')
            second_synthesis.write_text('second synthesis')
            shim = directory / 'bin'
            shim.mkdir()
            state_file = directory / 'state/state.json'
            wrapper = shim / 'jq'
            wrapper.write_text('#!/usr/bin/env bash\nset -euo pipefail\n'
                'last="${!#}"\n'
                'if [[ "$last" == "$BARRIER_STATE" ]]; then\n'
                '  if [[ "${BARRIER_FIRST:-}" == 1 && ! -f "$BARRIER_DIR/first-read" ]]; then\n'
                '    "' + shutil.which('jq') + '" "$@" > "$BARRIER_DIR/snapshot"\n'
                '    touch "$BARRIER_DIR/first-read"\n'
                '    for ((i=0; i<500; i++)); do\n'
                '      [[ ! -f "$BARRIER_DIR/release" ]] || { cat "$BARRIER_DIR/snapshot"; exit 0; }\n'
                '      sleep 0.01\n'
                '    done\n'
                '    exit 24\n'
                '  elif [[ "${BARRIER_FIRST:-}" != 1 ]]; then touch "$BARRIER_DIR/second-read"; fi\n'
                'fi\nexec "' + shutil.which('jq') + '" "$@"\n')
            wrapper.chmod(0o755)
            # Publish contention only after the real exclusive mkdir returns
            # EEXIST while the first writer still holds the production lock.
            python_wrapper = shim / 'python3'
            python_wrapper.write_text('#!/usr/bin/env bash\n'
                'rc=0\n"' + shutil.which('python3') + '" "$@" || rc=$?\n'
                'if [[ "${1:-}" == - && "${2:-}" == "$BARRIER_STATE.lock" && "$rc" == 75 && "${BARRIER_FIRST:-}" != 1 ]]; then\n'
                '  touch "$BARRIER_DIR/second-lock-attempt"\nfi\nexit "$rc"\n')
            python_wrapper.chmod(0o755)
            env.update(PATH=str(shim) + os.pathsep + env['PATH'], BARRIER_DIR=str(directory), BARRIER_STATE=str(state_file))
            first = subprocess.Popen([str(helper), 'complete_define', str(first_synthesis), 'first context', 'first decision'],
                                     env=dict(env, BARRIER_FIRST='1'), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            second = None
            try:
                deadline = time.monotonic() + 5
                while not (directory / 'first-read').exists() and time.monotonic() < deadline and first.poll() is None:
                    time.sleep(0.01)
                assert (directory / 'first-read').exists(), 'first writer never reached production state read'
                args = [a.replace('{synthesis}', str(second_synthesis)) for a in arguments]
                command = ([str(helper), operation, *args] if mode == 'cli' else
                           ['bash', '-c', 'source "$1"; shift; "$@"', 'test', str(helper), operation, *args])
                second = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                deadline = time.monotonic() + 3
                while not (directory / 'second-lock-attempt').exists() and second.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                attempted_lock = (directory / 'second-lock-attempt').exists()
                entered_early = (directory / 'second-read').exists()
                (directory / 'release').touch()
                first.communicate(timeout=10)
                second.communicate(timeout=10)
                state = json.loads(state_file.read_text())
                valid = first.returncode == second.returncode == 0 and attempted_lock and not entered_early
                valid &= state['context']['define'] in ('first context', 'second context')
                valid &= state['metrics']['phases_completed'] == (2 if operation == 'complete_define' else 1)
                valid &= len(state['decisions']) == (2 if operation in ('complete_define', 'write_decision') else 1)
                valid &= len(state['phase_completions']['define']) == (2 if operation == 'complete_define' else 1)
                if operation == 'set_current_workflow': valid &= state['current_workflow'] == 'tangle'
                if operation == 'write_blocker': valid &= len(state['blockers']) == 2
                if operation == 'update_blocker_status': valid &= state['blockers'][0]['status'] == 'resolved'
                if operation == 'update_context': valid &= state['context']['develop'] == 'second context'
                if operation == 'update_metrics': valid &= state['metrics']['total_execution_time_minutes'] == 42
                if not valid:
                    failures.append(f'{mode} {operation}: first={first.returncode} second={second.returncode} attempted_lock={attempted_lock}, entered_early={entered_early}, state={state}')
            finally:
                (directory / 'release').touch()
                for child in (first, second):
                    if child is not None and child.poll() is None:
                        child.kill()
                        child.communicate()
print(f'{len(operations) * 2 - len(failures)}/{len(operations) * 2} coordinated writer controls passed')
for failure in failures: print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_LOCK
then test_pass; else test_fail "shared state lost concurrent updates or admitted an unlocked read"; fi
test_summary
