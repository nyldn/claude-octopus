#!/usr/bin/env bash
# Exercise production writers under conditional callers where errexit is disabled.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "workflow state writer failure propagation"
test_case "failed transforms and publications preserve state without reporting success"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

root = Path(sys.argv[1])
helper = os.environ.get('OCTO_WRITER_TEST_HELPER', str(root / 'scripts/state-manager.sh'))
failures = []
checked = 0
operations = [
    ['set_current_workflow', 'tangle', 'develop'],
    ['write_decision', 'develop', 'decision', 'reason'],
    ['write_blocker', 'blocker', 'develop'],
    ['update_blocker_status', 'existing', 'resolved'],
    ['update_context', 'develop', 'context'],
    ['update_metrics', 'phases_completed', '1'],
    ['update_metrics', 'execution_time', '42'],
    ['update_metrics', 'provider', 'codex'],
]
with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
    directory = Path(temporary)
    env = dict(os.environ, OCTOPUS_WORKFLOW_STATE_DIR=str(directory / 'state'))
    subprocess.run([helper, 'init_state'], env=env, check=True, capture_output=True)
    state_file = directory / 'state/state.json'
    before = state_file.read_bytes()
    marker = directory / 'injected'
    for operation in operations:
        for failure in ('jq', 'object jq', 'atomic_write', 'cp', 'replace'):
            if failure == 'object jq' and operation[0] not in ('write_decision', 'write_blocker'):
                continue
            state_file.write_bytes(before)
            marker.unlink(missing_ok=True)
            injection = failure + '() { command touch "$FAILURE_MARKER"; return 23; }; '
            if failure == 'jq':
                injection = 'jq() { if [[ "${!#}" == "$STATE_FILE" ]]; then command touch "$FAILURE_MARKER"; return 23; fi; command jq "$@"; }; '
            if failure == 'object jq':
                injection = 'jq() { if [[ "${1:-}" == -n ]]; then command touch "$FAILURE_MARKER"; return 23; fi; command jq "$@"; }; '
            if failure == 'replace':
                injection = 'python3() { if [[ "${3:-}" == *os.replace* ]]; then command touch "$FAILURE_MARKER"; return 23; fi; command python3 "$@"; }; '
            result = subprocess.run(['bash', '-c', 'source "$1"; shift; ' + injection +
                'if "$@"; then exit 0; else exit $?; fi', 'test', helper, *operation],
                env=dict(env, FAILURE_MARKER=str(marker)), capture_output=True, text=True, timeout=10)
            valid = (marker.exists() and result.returncode != 0 and
                     state_file.read_bytes() == before and 'SUCCESS:' not in result.stdout and
                     not list(state_file.parent.glob('state.json.tmp.*')))
            if not valid:
                failures.append(f'{operation}: {failure}, exit={result.returncode}, reached={marker.exists()}')
            checked += 1
    for content in ('', ' \n\t', 'null', '[]', '42', 'true', '{}\n{}'):
        state_file.write_bytes(before)
        result = subprocess.run(['bash', '-c', 'source "$1"; if atomic_write "$2"; then exit 0; else exit $?; fi',
                                 'test', helper, content], env=env, capture_output=True, timeout=10)
        if result.returncode == 0 or state_file.read_bytes() != before:
            failures.append(f'invalid state document accepted: {content!r}')
        checked += 1
    # The actual sourced caller stays alive after its writer dies. Simulate the
    # supported Bash 3.2 path by removing BASHPID before starting that writer.
    state_file.write_bytes(before)
    writer_file = directory / 'writer'
    ready = directory / 'ready'
    release = directory / 'release'
    program = '''source "$1"
unset BASHPID
cp() {
    command python3 -I -c 'import os, signal; from pathlib import Path; Path(os.environ["WRITER_FILE"]).write_text(str(os.getppid())); Path(os.environ["READY"]).touch(); os.kill(os.getppid(), signal.SIGSTOP)'
    command cp "$@"
}
update_context develop interrupted &
writer=$!
wait "$writer" || :
for ((i=0; i<2000; i++)); do [[ ! -f "$RELEASE" ]] || exit 0; sleep 0.01; done
exit 24
'''
    parent = subprocess.Popen(['bash', '-c', program, 'test', helper],
        env=dict(env, READY=str(ready), WRITER_FILE=str(writer_file), RELEASE=str(release)),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    writer = None
    try:
        deadline = time.monotonic() + 5
        while not ready.exists() and parent.poll() is None and time.monotonic() < deadline:
            time.sleep(0.01)
        assert ready.exists(), 'writer never reached production backup'
        writer = int(writer_file.read_text())
        owner = int((directory / 'state/state.json.lock/pid').read_text())
        if owner != writer:
            failures.append(f'Bash 3.2 fallback owner={owner}, actual writer={writer}, sourcing parent={parent.pid}')
        checked += 1
        os.kill(writer, signal.SIGKILL)
        # Keep the sourcing parent alive while a separate writer reclaims.
        result = subprocess.run([helper, 'update_context', 'develop', 'recovered'],
            env=dict(env, OCTO_EVENT_LOCK_STALE_SECS='0'), capture_output=True, timeout=15)
        if parent.poll() is not None or result.returncode != 0:
            failures.append('abandoned Bash 3.2 writer lock cannot recover while parent lives')
        checked += 1
    finally:
        release.touch()
        if writer is not None:
            try:
                os.kill(writer, signal.SIGKILL)
            except ProcessLookupError:
                pass
        parent.communicate(timeout=10)
print(f'{checked - len(failures)}/{checked} production writer failure/recovery controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "state writer lost data or accepted a failed update"; fi
test_summary
