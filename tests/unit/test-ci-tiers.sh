#!/usr/bin/env bash
# Exercise the actual required-gate scripts and complete shard inventory.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$PROJECT_ROOT/tests/helpers/test-framework.sh"
test_suite "CI tiers"

test_case "required gates reject failures and skipped coverage"
if python3 - "$PROJECT_ROOT" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys

root = Path(sys.argv[1])
workflow = (root / '.github/workflows/test.yml').read_text()
jobs = dict(re.findall(r'^  ([\w-]+):\n(.*?)(?=^  [\w-]+:|\Z)', workflow, re.M | re.S))

def script(job):
    """Read the aggregate's shell gate from the workflow itself."""
    marker = '        run: |\n'
    assert marker in jobs[job], (job, 'missing multiline run block')
    return jobs[job].split(marker, 1)[1]

def check(job, updates, expected):
    """Execute a gate with the same status values GitHub supplies."""
    values = {
        'github.event_name': 'pull_request',
        'needs.classify-changes.result': 'success',
        'needs.classify-changes.outputs.full_unit': 'false',
        'needs.smoke.result': 'success',
        'needs.portability-lint.result': 'success',
        'needs.unit-focused.result': 'success',
        'needs.unit-full.result': 'skipped',
        'needs.symlinked-path.result': 'success',
        'needs.integration-heavy.result': 'success',
        'needs.smoke-required.result': 'success',
        'needs.unit-required.result': 'success',
        'needs.integration.result': 'success',
    }
    values.update(updates)
    body = script(job)
    for key, value in values.items():
        body = body.replace('${{ ' + key + ' }}', value)
    assert '${{' not in body, (job, body)
    rc = subprocess.run(['bash', '-eo', 'pipefail', '-c', body],
                        env=dict(os.environ, GITHUB_STEP_SUMMARY=os.devnull)).returncode
    assert (rc == 0) == expected, (job, updates, rc)

for job in ('smoke-required', 'unit-required', 'integration'):
    assert '    if: always()' in jobs[job], job
    check(job, {}, True)
    for status in ('failure', 'cancelled', 'skipped'):
        check(job, {'needs.classify-changes.result': status}, False)
for job, dependency in [('smoke-required', 'smoke'), ('smoke-required', 'portability-lint'),
                        ('unit-required', 'unit-focused'), ('unit-required', 'symlinked-path'),
                        ('integration', 'integration-heavy')]:
    for status in ('failure', 'cancelled', 'skipped'):
        check(job, {'needs.' + dependency + '.result': status}, False)
check('test-summary', {}, True)
for dependency in ('smoke-required', 'unit-required', 'integration', 'portability-lint'):
    for status in ('failure', 'cancelled', 'skipped'):
        check('test-summary', {'needs.' + dependency + '.result': status}, False)
for event in ('push', 'schedule', 'workflow_dispatch', 'merge_group'):
    check('unit-required', {'github.event_name': event}, False)
    check('unit-required', {'github.event_name': event, 'needs.unit-full.result': 'success'}, True)
check('unit-required', {'needs.classify-changes.outputs.full_unit': 'true'}, False)
check('unit-required', {'needs.classify-changes.outputs.full_unit': ''}, False)
check('unit-required', {'needs.classify-changes.outputs.full_unit': 'true',
                       'needs.unit-full.result': 'success'}, True)

# Integration has no unit artifacts to consume. A unit failure must still
# leave an independently useful integration result.
assert re.search(r'^    needs: smoke$', jobs['integration-heavy'], re.M)
assert not re.search(r'^    if:', jobs['integration-heavy'], re.M)
assert 'make test-integration' in jobs['integration-heavy']
assert 'make test-symlink-sensitive' in jobs['symlinked-path']
assert not re.search(r'make test-unit(?:\s|$)', jobs['symlinked-path'])
assert 'unit-deep' not in jobs
assert 'make test-smoke' in jobs['smoke']
assert not re.search(r'^    if:', jobs['smoke'], re.M)
assert 'make sync-check' in jobs['smoke']
assert 'package-integrity' not in jobs  # packaging is already in smoke
PY
then test_pass; else test_fail "a required gate accepted missing coverage"; fi

test_case "full tier shards cover every suite exactly once per supported OS"
if python3 - "$PROJECT_ROOT" <<'PY'
from pathlib import Path
import re
import shlex
import subprocess
import sys

root = Path(sys.argv[1])
workflow = (root / '.github/workflows/test.yml').read_text()
job = re.search(r'^  unit-full:\n(.*?)(?=^  [\w-]+:|\Z)', workflow, re.M | re.S)[1]
lanes = re.findall(r'^          - os: (\S+)\n            shard_index: (\d+)\n            shard_count: (\d+)$', job, re.M)
assert lanes, 'missing full-unit matrix entries'
oses = {lane[0] for lane in lanes}
assert oses == {'ubuntu-latest', 'macos-latest'}
command = re.search(r'^        run: (python3 tests/helpers/run-ci-step.py .+)$', job, re.M)[1]
assert re.search(r'^          SHARD_INDEX: \$\{\{ matrix.shard_index \}\}$', job, re.M)
assert re.search(r'^          SHARD_COUNT: \$\{\{ matrix.shard_count \}\}$', job, re.M)
assert '${{' not in command, 'pass workflow expressions through the environment'
for lane in ('unit-focused', 'unit-full'):
    lane_job = re.search(r'^  ' + lane + r':\n(.*?)(?=^  [\w-]+:|\Z)', workflow, re.M | re.S)[1]
    lane_command = re.search(r'^        run: (python3 tests/helpers/run-ci-step.py .+)$', lane_job, re.M)[1]
    lane_parts = shlex.split(lane_command)
    timeout = int(next(part.split('=', 1)[1] for part in lane_parts if part.startswith('--timeout=')))
    job_timeout = int(re.search(r'^    timeout-minutes: (\d+)$', lane_job, re.M)[1]) * 60
    assert 0 < timeout < job_timeout - 60, (lane, timeout, job_timeout)
    log_path = lane_parts[lane_parts.index('--log') + 1]
    assert log_path.startswith('$RUNNER_TEMP/'), (lane, log_path)
    artifact_path = '${{ runner.temp }}/' + log_path[len('$RUNNER_TEMP/'):]
    assert artifact_path in lane_job and 'if: failure() || cancelled()' in lane_job, lane

def suites(args):
    """List the real runner's selected suites without starting providers."""
    output = subprocess.check_output(['bash', 'tests/run-all.sh', *args, '--list'],
                                     cwd=root, text=True)
    return re.findall(r'^  - (unit/[^\n]+\.sh)$', output, re.M)

expected = suites(['unit'])
assert 'unit/test-council-command.sh' in expected
for os_name in oses:
    os_lanes = [(int(index), int(count)) for name, index, count in lanes if name == os_name]
    counts = {count for _, count in os_lanes}
    assert len(counts) == 1 and next(iter(counts)) > 0, (os_name, counts)
    count = next(iter(counts))
    assert sorted(index for index, _ in os_lanes) == list(range(count)), (os_name, os_lanes)
    selected = []
    for index, count in os_lanes:
        parts = shlex.split(command.replace('$SHARD_INDEX', str(index)).replace('$SHARD_COUNT', str(count)))
        runner_command = parts[parts.index('--') + 1:]
        assert runner_command[:2] == ['./tests/run-all.sh', 'unit'], runner_command
        args = runner_command[1:]
        subset = suites(args)
        assert subset, (os_name, index)
        selected.extend(subset)
    assert sorted(selected) == sorted(expected), os_name
    assert len(selected) == len(set(selected)), os_name
PY
then test_pass; else test_fail "the full tier dropped or duplicated a unit suite"; fi

test_summary
