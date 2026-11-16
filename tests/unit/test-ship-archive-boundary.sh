#!/usr/bin/env bash
# Execute the shipped archive recipe against redirected and nonregular paths.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Shipping archive boundary"
test_case "archive copies remain private and inside the project state directory"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
from pathlib import Path
import re
import resource
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
controls = 0
names = ('STATE.md', 'PROJECT.md', 'ROADMAP.md', 'ISSUES.md')
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'skill-ship/SKILL.md'
    if not entry.exists():
        continue
    section = entry.read_text().split('### Phase 4: Archive Project State', 1)[1].split('### Phase 5:', 1)[0]
    recipe = '\n'.join(re.findall(r'```bash\n(.*?)\n```', section, re.S))
    scenarios = ('ordinary', 'repeat', 'parent link', 'archive link', 'fifo', 'directory',
                 'missing state', 'copy failure',
                 'missing optional', *('link ' + name for name in names), 'hard link')
    for scenario in scenarios:
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            directory = Path(temporary)
            project = directory / 'project'
            state = project / '.octo'
            state.mkdir(parents=True)
            outside = directory / 'outside'
            outside.mkdir()
            victim = outside / 'private'
            victim.write_text('outside private sentinel\n')
            for name in names:
                (state / name).write_text(name + '\n')
                (state / name).chmod(0o600)
            (state / 'LESSONS.md').write_text('lessons stay in place\n')
            if scenario.startswith('link '):
                target = state / scenario[5:]
                target.unlink()
                target.symlink_to(victim)
            elif scenario == 'hard link':
                (state / 'PROJECT.md').unlink()
                os.link(victim, state / 'PROJECT.md')
            elif scenario in ('fifo', 'directory'):
                (state / 'PROJECT.md').unlink()
                if scenario == 'fifo':
                    os.mkfifo(state / 'PROJECT.md')
                else:
                    (state / 'PROJECT.md').mkdir()
            elif scenario == 'parent link':
                state.rename(outside / 'state')
                state.symlink_to(outside / 'state', target_is_directory=True)
            elif scenario == 'archive link':
                (state / 'archive').symlink_to(outside, target_is_directory=True)
            elif scenario == 'missing optional':
                (state / 'ROADMAP.md').unlink()
            elif scenario == 'missing state':
                (state / 'STATE.md').unlink()
            elif scenario == 'copy failure':
                (state / 'PROJECT.md').write_text('large state\n' * 2048)
            expected = scenario in ('ordinary', 'repeat', 'missing optional')
            valid = True
            for attempt in range(2 if scenario == 'repeat' else 1):
                try:
                    result = subprocess.run(['bash', '-c', recipe], cwd=project,
                                            capture_output=True, text=True, timeout=5,
                                            preexec_fn=(lambda: resource.setrlimit(resource.RLIMIT_FSIZE, (1024, 1024)))
                                            if scenario == 'copy failure' else None)
                except subprocess.TimeoutExpired:
                    valid = False
                    break
                valid = valid and ((result.returncode == 0) == expected)
            if expected:
                archives = list((state / 'archive').iterdir())
                valid = valid and len(archives) == (2 if scenario == 'repeat' else 1)
                for archive in archives:
                    valid = valid and archive.is_dir() and archive.stat().st_mode & 0o077 == 0
                    for name in names:
                        target = archive / name
                        if scenario == 'missing optional' and name == 'ROADMAP.md':
                            valid = valid and not target.exists()
                        else:
                            valid = valid and target.read_text() == name + '\n' and target.stat().st_mode & 0o077 == 0
                    valid = valid and not (archive / 'LESSONS.md').exists()
            # No linked private bytes may appear anywhere in the project archive.
            if not state.is_symlink() and not (state / 'archive').is_symlink():
                valid = valid and all(b'outside private sentinel' not in p.read_bytes()
                                      for p in (state / 'archive').rglob('*') if p.is_file() and not p.is_symlink())
            valid = valid and victim.read_text() == 'outside private sentinel\n'
            valid = valid and sorted(p.name for p in outside.iterdir()) == (['private', 'state'] if scenario == 'parent link' else ['private'])
            if not valid:
                failures.append(f'{tree}: {scenario}: archive boundary failed')
            controls += 1
print(f'{controls - len(failures)}/{controls} shipping archive controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then
    test_pass
else
    test_fail "shipping archive boundary controls failed"
fi
test_summary
