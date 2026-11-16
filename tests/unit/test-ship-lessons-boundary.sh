#!/usr/bin/env bash
# Execute shipped lesson recipes against ordinary and redirected paths.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Shipping lessons boundary"
test_case "lessons stay inside a real project state directory"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
controls = 0
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'skill-ship/SKILL.md'
    if not entry.exists():
        continue
    section = entry.read_text().split('#### Step 2: Append to LESSONS.md', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for scenario in ('existing', 'new', 'leaf link', 'dangling link', 'parent link',
                     'directory', 'fifo', 'hard link'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            directory = Path(temporary)
            project = directory / 'project'
            project.mkdir()
            state = project / '.octo'
            outside = directory / 'outside'
            outside.mkdir()
            victim = outside / 'LESSONS.md'
            victim.write_text('outside sentinel\n')
            state.mkdir()
            target = state / 'LESSONS.md'
            if scenario == 'existing':
                target.write_text('old lessons\n')
                target.chmod(0o600)
            elif scenario == 'hard link':
                os.link(victim, target)
            elif scenario == 'leaf link':
                target.symlink_to(victim)
            elif scenario == 'dangling link':
                target.symlink_to(outside / 'missing')
            elif scenario == 'parent link':
                state.rmdir()
                state.symlink_to(outside, target_is_directory=True)
            elif scenario == 'directory':
                target.mkdir()
            elif scenario == 'fifo':
                os.mkfifo(target)
            marker = project / 'executed'
            payload = 'literal $(touch executed) `touch executed`\nsecond line'
            environment = dict(os.environ, USER_WHAT_WENT_WELL=payload,
                               USER_WHAT_COULD_IMPROVE='improve', USER_KEY_LEARNINGS='learn')
            try:
                result = subprocess.run(['bash', '-c', recipe], cwd=project, env=environment,
                                        capture_output=True, text=True, timeout=5)
            except subprocess.TimeoutExpired:
                failures.append(f'{tree}: {scenario}: recipe blocked on the target')
                controls += 1
                continue
            safe = scenario in ('existing', 'new')
            valid = ((result.returncode == 0) == safe and
                     victim.read_text() == 'outside sentinel\n' and
                     not (outside / 'missing').exists() and not marker.exists())
            if safe:
                content = target.read_text()
                valid = (valid and payload in content and '### Key Learnings\n- learn' in content
                         and target.stat().st_mode & 0o777 == 0o600)
                if scenario == 'existing':
                    valid = valid and content.startswith('old lessons\n')
            if not valid:
                failures.append(f'{tree}: {scenario}: exit={result.returncode} {result.stderr}')
            controls += 1
print(f'{controls - len(failures)}/{controls} shipping lessons controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then
    test_pass
else
    test_fail "shipping lessons boundary controls failed"
fi
test_summary
