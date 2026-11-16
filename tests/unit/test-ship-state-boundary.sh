#!/usr/bin/env bash
# Exercise the actual delivery-state update against redirected and special files.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Shipping state boundary"
test_case "shipment history writes only a regular unlinked project state file"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
from pathlib import Path
import re
import resource
import signal
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
controls = 0
original = (root / 'config/templates/STATE.md.template').read_text().replace('{{STATUS}}', 'ready')
original = original.replace('**Phase:** {{CURRENT_PHASE}}', '**Current Phase:** 4')
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'skill-ship/SKILL.md'
    if not entry.exists():
        continue
    section = entry.read_text().split('#### Step 1: Update STATE.md', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for scenario in ('regular', 'partial write', 'legacy status', 'historical status', 'historical legacy status',
                     'historical status only', 'directory sync', 'directory sync failure',
                     'missing status', 'missing state', 'missing archive', 'missing validation',
                     'parent link', 'leaf link', 'dangling link', 'hard link', 'directory', 'fifo'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            directory = Path(temporary)
            project = directory / 'project'
            project.mkdir()
            state = project / '.octo'
            state.mkdir()
            outside = directory / 'outside'
            outside.mkdir()
            victim = outside / 'STATE.md'
            victim.write_text(original)
            target = state / 'STATE.md'
            if scenario == 'parent link':
                state.rmdir()
                state.symlink_to(outside, target_is_directory=True)
            elif scenario == 'leaf link':
                target.symlink_to(victim)
            elif scenario == 'dangling link':
                target.symlink_to(outside / 'missing')
            elif scenario == 'hard link':
                os.link(victim, target)
            elif scenario == 'directory':
                target.mkdir()
            elif scenario == 'fifo':
                os.mkfifo(target)
            elif scenario != 'missing state':
                target.write_text(original)
                target.chmod(0o600)
            before = original
            if scenario == 'legacy status':
                before = original.replace('**Status:** ready', 'status: complete')
                target.write_text(before)
            elif scenario == 'missing status':
                before = original.replace('**Status:** ready', 'Other field: keep')
                target.write_text(before)
            elif scenario.startswith('historical'):
                if scenario == 'historical status only':
                    before = original.replace('**Status:** ready', 'Other field: keep')
                historical = ('status: complete' if scenario == 'historical legacy status'
                              else '**Status:** ready')
                before += '\n## History - previous shipment\n\n' + historical + '\n'
                target.write_text(before)
            environment = dict(os.environ, ARCHIVE_TIMESTAMP='fixture-archive',
                               VALIDATION_FILE='literal $(touch executed) `touch executed`')
            if scenario == 'missing archive':
                environment.pop('ARCHIVE_TIMESTAMP')
            if scenario == 'missing validation':
                environment.pop('VALIDATION_FILE')
            executed_recipe = recipe
            if scenario.startswith('directory sync'):
                # Instrument only fsync; execute the otherwise unchanged recipe.
                instrumentation = '''
real_fsync = os.fsync
def checked_fsync(fd):
    is_directory = stat.S_ISDIR(os.fstat(fd).st_mode)
    with open('sync-events', 'a') as events:
        events.write('directory\\n' if is_directory else 'file\\n')
    if is_directory:
        assert '- **Event:** Project shipped' in open('.octo/STATE.md').read()
        if os.environ.get('FAIL_DIRECTORY_SYNC') == '1':
            raise OSError('injected directory sync failure')
    real_fsync(fd)
os.fsync = checked_fsync
'''
                executed_recipe = recipe.replace('archive, validation = sys.argv[1:]',
                                                 instrumentation + '\narchive, validation = sys.argv[1:]')
                environment['FAIL_DIRECTORY_SYNC'] = '1' if scenario.endswith('failure') else '0'
            def limit_write():
                signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
                limit = original.index('**Status:**') + 64
                resource.setrlimit(resource.RLIMIT_FSIZE, (limit, limit))

            try:
                result = subprocess.run(['bash', '-c', executed_recipe + '\nprintf done > completed'],
                                        cwd=project, env=environment, capture_output=True, text=True, timeout=2,
                                        preexec_fn=limit_write if scenario == 'partial write' else None)
            except subprocess.TimeoutExpired:
                failures.append(f'{tree}: {scenario}: recipe blocked on target')
                controls += 1
                continue
            accepted = scenario in ('regular', 'legacy status', 'historical status',
                                    'historical legacy status', 'directory sync')
            valid = ((result.returncode == 0) == accepted
                     and (project / 'completed').exists() == accepted
                     and victim.read_text() == original
                     and not (outside / 'missing').exists()
                     and not (project / 'executed').exists()
                     and not list(state.glob('.STATE.md.ship-*')))
            if accepted:
                content = target.read_text()
                if scenario in ('regular', 'historical status', 'historical legacy status'):
                    observed = subprocess.check_output(['bash', str(root / 'scripts/octo-state.sh'),
                                                        'read_state'], cwd=project, env=environment, text=True)
                    valid = (valid and 'status=shipped' in observed.splitlines()
                             and all('=' in line for line in observed.splitlines()))
                    phase = subprocess.run(['bash', str(root / 'scripts/octo-state.sh'),
                                            'get_phase_status', '4'], cwd=project, env=environment,
                                           capture_output=True, text=True)
                    valid = valid and phase.returncode == 0 and phase.stdout == 'shipped\n'
                expected = re.sub(r'^(\*\*Status:\*\*|status:)[^\r\n]*', r'\1 shipped', before, count=1, flags=re.M)
                valid = (valid and content.startswith(expected)
                         and content.count('- **Event:** Project shipped') == 1
                         and '- **Archive:** .octo/archive/fixture-archive/' in content
                         and environment['VALIDATION_FILE'] in content
                         and target.stat().st_mode & 0o777 == 0o600)
                if scenario == 'historical status':
                    tier = subprocess.check_output(['bash', str(root / 'scripts/octo-state.sh'),
                                                    'get_context_tier'], cwd=project, env=environment, text=True)
                    continued = subprocess.run(['bash', str(root / 'scripts/octo-state.sh'),
                                                'write_state', '--position', 'Post-shipment follow-up'],
                                               cwd=project, env=environment, capture_output=True, text=True)
                    valid = (valid and tier.splitlines()[0] == '=== Context Tier: planning ==='
                             and continued.returncode == 0)
            elif scenario in ('missing archive', 'missing validation', 'hard link', 'missing status',
                              'partial write', 'historical status only'):
                valid = valid and target.read_text() == before
            elif scenario == 'missing state':
                valid = valid and not target.exists()
            if scenario.startswith('directory sync'):
                valid = valid and (project / 'sync-events').read_text() == 'file\ndirectory\n'
            if not valid:
                failures.append(f'{tree}: {scenario}: exit={result.returncode}')
            controls += 1
print(f'{controls - len(failures)}/{controls} shipping state controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "shipping state boundary controls failed"; fi
test_summary
