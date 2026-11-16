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
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'skill-ship/SKILL.md'
    if not entry.exists():
        continue
    section = entry.read_text().split('#### Step 1: Update STATE.md', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for scenario in ('regular', 'partial write', 'legacy status', 'missing status', 'missing state', 'missing archive', 'missing validation',
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
            environment = dict(os.environ, ARCHIVE_TIMESTAMP='fixture-archive',
                               VALIDATION_FILE='literal $(touch executed) `touch executed`')
            if scenario == 'missing archive':
                environment.pop('ARCHIVE_TIMESTAMP')
            if scenario == 'missing validation':
                environment.pop('VALIDATION_FILE')
            def limit_write():
                signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
                limit = original.index('**Status:**') + 64
                resource.setrlimit(resource.RLIMIT_FSIZE, (limit, limit))

            try:
                result = subprocess.run(['bash', '-c', recipe + '\nprintf done > completed'],
                                        cwd=project, env=environment, capture_output=True, text=True, timeout=2,
                                        preexec_fn=limit_write if scenario == 'partial write' else None)
            except subprocess.TimeoutExpired:
                failures.append(f'{tree}: {scenario}: recipe blocked on target')
                controls += 1
                continue
            accepted = scenario in ('regular', 'legacy status')
            valid = ((result.returncode == 0) == accepted
                     and (project / 'completed').exists() == accepted
                     and victim.read_text() == original
                     and not (outside / 'missing').exists()
                     and not (project / 'executed').exists()
                     and not list(state.glob('.STATE.md.ship-*')))
            if accepted:
                content = target.read_text()
                if scenario == 'regular':
                    observed = subprocess.check_output(['bash', str(root / 'scripts/octo-state.sh'),
                                                        'read_state'], cwd=project, env=environment, text=True)
                    valid = valid and 'status=shipped' in observed.splitlines()
                valid = (valid and content.startswith(before.replace('**Status:** ready', '**Status:** shipped').replace('status: complete', 'status: shipped'))
                         and content.count('- **Event:** Project shipped') == 1
                         and ('**Status:** shipped' in content if scenario == 'regular' else 'status: shipped' in content)
                         and '**Status:** ready' not in content
                         and '- **Archive:** .octo/archive/fixture-archive/' in content
                         and environment['VALIDATION_FILE'] in content
                         and target.stat().st_mode & 0o777 == 0o600)
            elif scenario in ('missing archive', 'missing validation', 'hard link', 'missing status', 'partial write'):
                valid = valid and target.read_text() == before
            elif scenario == 'missing state':
                valid = valid and not target.exists()
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
