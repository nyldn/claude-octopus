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
import struct
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
        if tree != 'codex-skills':
            failures.append(f'{tree}: missing skill-ship entry')
            controls += 1
        continue
    section = entry.read_text().split('#### Step 1: Update STATE.md', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    reader_section = entry.read_text().split('#### Step 2: Read STATE.md Status', 1)[1]
    reader = re.search(r'```bash\n(.*?)\n```', reader_section, re.S)[1]
    for scenario in ('regular', 'other group', 'ownership failure', 'metadata failure', 'acl', 'inherited acl', 'permission race', 'partial write', 'legacy status', 'historical status', 'historical legacy status',
                     'historical status only', 'dual status legacy first', 'dual status canonical first',
                     'retry', 'directory sync', 'directory sync failure', 'directory sync retry',
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
            elif scenario.startswith('dual status'):
                statuses = ('status: complete\n**Status:** ready' if scenario.endswith('legacy first')
                            else '**Status:** ready\nstatus: complete')
                before = original.replace('**Status:** ready', statuses)
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
            if scenario == 'other group':
                groups = sorted(set(os.getgroups()) - {os.getegid()})
                if not groups:
                    print(f'{tree}: alternate-group control unavailable for this account')
                    continue
                os.chown(target, -1, groups[0])
                target.chmod(0o640)
            if scenario == 'permission race':
                target.chmod(0o640)
            access_metadata = None
            if scenario in ('acl', 'inherited acl'):
                if sys.platform.startswith('linux'):
                    acl = struct.pack('<I', 2) + b''.join(struct.pack('<HHI', tag, perm, who)
                        for tag, perm, who in ((1, 6, 0xffffffff), (2, 4, 65534),
                                              (4, 0, 0xffffffff), (16, 4, 0xffffffff), (32, 0, 0xffffffff)))
                    os.setxattr(target if scenario == 'acl' else state,
                                'system.posix_acl_access' if scenario == 'acl' else 'system.posix_acl_default', acl)
                    os.setxattr(target, 'user.octopus-fixture', b'preserve this attribute')
                    access_metadata = {name: os.getxattr(target, name) for name in os.listxattr(target)}
                elif sys.platform == 'darwin':
                    # Native macOS ACLs must survive both explicit and inherited grants.
                    subprocess.run(['chmod', '+a', f'user:{os.getuid()} allow read' +
                                    (',file_inherit' if scenario == 'inherited acl' else ''),
                                    str(state if scenario == 'inherited acl' else target)], check=True)
                    access_metadata = subprocess.check_output(['ls', '-le', str(target)], text=True).splitlines()[1:]
            expected_mode = target.stat().st_mode & 0o777 if target.is_file() else None
            owner = (target.stat().st_uid, target.stat().st_gid) if target.is_file() else None
            environment = dict(os.environ, ARCHIVE_TIMESTAMP='fixture-archive',
                               VALIDATION_FILE='literal $(touch executed) `touch executed`',
                               CLAUDE_PLUGIN_ROOT=str(root), CODEX_PLUGIN_ROOT=str(root))
            if scenario == 'missing archive':
                environment.pop('ARCHIVE_TIMESTAMP')
            if scenario == 'missing validation':
                environment.pop('VALIDATION_FILE')
            executed_recipe = recipe
            if scenario == 'metadata failure':
                instrumentation = '''
def denied_metadata(*args):
    raise PermissionError('injected access metadata preservation failure')
copy_access_metadata = denied_metadata
'''
                executed_recipe = recipe.replace('archive, validation = sys.argv[1:]',
                                                 instrumentation + '\narchive, validation = sys.argv[1:]')
            if scenario == 'permission race':
                instrumentation = '''
real_stat = os.stat
def revoking_stat(path, *args, **kwargs):
    if path == 'STATE.md' and 'dir_fd' in kwargs:
        os.chmod(path, 0o600, dir_fd=kwargs['dir_fd'])
    return real_stat(path, *args, **kwargs)
os.stat = revoking_stat
'''
                executed_recipe = recipe.replace('archive, validation = sys.argv[1:]',
                                                 instrumentation + '\narchive, validation = sys.argv[1:]')
            if scenario == 'ownership failure':
                instrumentation = '''
def denied_fchown(*args):
    raise PermissionError('injected ownership preservation failure')
os.fchown = denied_fchown
'''
                executed_recipe = recipe.replace('archive, validation = sys.argv[1:]',
                                                 instrumentation + '\narchive, validation = sys.argv[1:]')
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
                environment['FAIL_DIRECTORY_SYNC'] = '1' if scenario.endswith(('failure', 'retry')) else '0'
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
            accepted = scenario in ('regular', 'other group', 'acl', 'inherited acl', 'legacy status', 'historical status',
                                    'historical legacy status', 'directory sync', 'retry', 'directory sync retry',
                                    'dual status legacy first', 'dual status canonical first')
            retry_valid = True
            if scenario in ('retry', 'directory sync retry'):
                published = target.read_text()
                retry_valid = ((result.returncode == 0) == (scenario == 'retry')
                               and (project / 'completed').exists() == (scenario == 'retry')
                               and published.count('- **Event:** Project shipped') == 1)
                environment['FAIL_DIRECTORY_SYNC'] = '0'
                result = subprocess.run(['bash', '-c', executed_recipe + '\nprintf done > completed'],
                                        cwd=project, env=environment, capture_output=True, text=True, timeout=2)
                retry_valid = retry_valid and target.read_text() == published
            valid = ((result.returncode == 0) == accepted
                     and retry_valid
                     and (project / 'completed').exists() == accepted
                     and victim.read_text() == original
                     and not (outside / 'missing').exists()
                     and not (project / 'executed').exists()
                     and not list(state.glob('.STATE.md.ship-*')))
            if accepted:
                content = target.read_text()
                if scenario in ('regular', 'legacy status', 'historical status', 'historical legacy status',
                                'dual status legacy first', 'dual status canonical first'):
                    observed = subprocess.check_output(['bash', str(root / 'scripts/octo-state.sh'),
                                                        'read_state'], cwd=project, env=environment, text=True)
                    valid = (valid and 'status=shipped' in observed.splitlines()
                             and all('=' in line for line in observed.splitlines()))
                    skill_status = subprocess.run(['bash', '-c', reader], cwd=project,
                                                  env=environment, capture_output=True, text=True, timeout=2)
                    valid = (valid and skill_status.returncode == 0
                             and skill_status.stdout == 'Status: shipped\nCurrent Phase: 4\n')
                    phase = subprocess.run(['bash', str(root / 'scripts/octo-state.sh'),
                                            'get_phase_status', '4'], cwd=project, env=environment,
                                           capture_output=True, text=True)
                    valid = valid and phase.returncode == 0 and phase.stdout == 'shipped\n'
                if scenario.startswith('dual status'):
                    expected = before.replace('**Status:** ready', '**Status:** shipped', 1)
                else:
                    expected = re.sub(r'^(\*\*Status:\*\*|status:)[^\r\n]*', r'\1 shipped', before, count=1, flags=re.M)
                valid = (valid and content.startswith(expected)
                         and content.count('- **Event:** Project shipped') == 1
                         and '- **Archive:** .octo/archive/fixture-archive/' in content
                         and environment['VALIDATION_FILE'] in content
                         and target.stat().st_mode & 0o777 == expected_mode
                         and (target.stat().st_uid, target.stat().st_gid) == owner)
                if access_metadata is not None:
                    if sys.platform.startswith('linux'):
                        valid = valid and access_metadata == {name: os.getxattr(target, name) for name in os.listxattr(target)}
                    else:
                        valid = valid and access_metadata == subprocess.check_output(['ls', '-le', str(target)], text=True).splitlines()[1:]
                if scenario in ('historical status', 'legacy status'):
                    tier = subprocess.check_output(['bash', str(root / 'scripts/octo-state.sh'),
                                                    'get_context_tier'], cwd=project, env=environment, text=True)
                    continued = subprocess.run(['bash', str(root / 'scripts/octo-state.sh'),
                                                'write_state', '--position', 'Post-shipment follow-up'],
                                               cwd=project, env=environment, capture_output=True, text=True)
                    valid = (valid and tier.splitlines()[0] == '=== Context Tier: planning ==='
                             and continued.returncode == 0)
                    phase = subprocess.run(['bash', str(root / 'scripts/octo-state.sh'),
                                            'get_phase_status', '4'], cwd=project, env=environment,
                                           capture_output=True, text=True)
                    valid = valid and phase.returncode == 0 and phase.stdout == 'shipped\n'
            elif scenario in ('missing archive', 'missing validation', 'hard link', 'missing status',
                              'partial write', 'historical status only', 'ownership failure', 'metadata failure', 'permission race'):
                valid = valid and target.read_text() == before
                if scenario == 'ownership failure':
                    valid = valid and (target.stat().st_uid, target.stat().st_gid) == owner
                if scenario == 'permission race':
                    valid = valid and target.stat().st_mode & 0o777 == 0o600
            elif scenario == 'missing state':
                valid = valid and not target.exists()
            if scenario.startswith('directory sync'):
                expected_syncs = 'file\ndirectory\n' * (2 if scenario.endswith('retry') else 1)
                valid = valid and (project / 'sync-events').read_text() == expected_syncs
            if scenario in ('missing status', 'historical status only'):
                phase = subprocess.run(['bash', str(root / 'scripts/octo-state.sh'),
                                        'get_phase_status', '4'], cwd=project, env=environment,
                                       capture_output=True, text=True)
                valid = valid and phase.returncode == 0 and phase.stdout == 'unknown\n'
            if not valid:
                failures.append(f'{tree}: {scenario}: exit={result.returncode}')
            controls += 1
print(f'{controls - len(failures)}/{controls} shipping state controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "shipping state boundary controls failed"; fi

test_case "missing required shipping recipes cannot produce a vacuous pass"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_MISSING'
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
root = Path(sys.argv[1])
source = (root / 'tests/unit/test-ship-state-boundary.sh').read_text()
controls = source.split("<<'PY_CONTROLS'\n", 1)[1].split('\nPY_CONTROLS', 1)[0]
with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
    fixture = Path(temporary)
    templates = fixture / 'config/templates'
    templates.mkdir(parents=True)
    shutil.copyfile(root / 'config/templates/STATE.md.template', templates / 'STATE.md.template')
    result = subprocess.run([sys.executable, '-I', '-', str(fixture), str(fixture)],
                            input=controls, capture_output=True, text=True, timeout=5)
    assert result.returncode != 0, result.stdout
    for tree in ('.claude/skills', 'skills'):
        assert f'{tree}: missing skill-ship entry' in result.stderr, result.stderr
PY_MISSING
then test_pass; else test_fail "missing required recipes were accepted"; fi
test_summary
