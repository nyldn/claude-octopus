#!/usr/bin/env bash
# Run rollback recipes in fresh shells after the confirmed Git context changes.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Rollback preview binding"
test_case "changed repositories, revisions, branches and targets require a new preview"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
checks = 0
for tree in ('.claude/skills', 'skills'):
    text = (root / tree / 'skill-rollback/SKILL.md').read_text().split('## Mode: ROLLBACK\n', 1)[1]
    def recipe(step):
        section = text.split('### Step ' + str(step) + ':', 1)[1]
        return re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for step in (4, 6):
        for change in ('head', 'branch', 'target', 'repository', 'missing-head',
                       'missing-root', 'missing-ref', 'missing-target'):
            with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                repo = Path(temporary) / 'repo'
                repo.mkdir()
                env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                           GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                           GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                           CHECKPOINT_TAG='octo-checkpoint-fixture', LESSONS_PRESERVED='false')
                def git(*args):
                    return subprocess.check_output(['git', '-C', str(repo), *args], env=env,
                                                   stderr=subprocess.DEVNULL)
                git('init', '-q', '-b', 'main')
                file = repo / 'work.txt'
                file.write_text('checkpoint\n')
                git('add', '.')
                git('commit', '-qm', 'checkpoint')
                git('tag', env['CHECKPOINT_TAG'])
                file.write_text('current\n')
                git('commit', '-qam', 'current')
                preview = subprocess.run(['bash', '-c', recipe(2)], cwd=repo, env=env,
                                         capture_output=True, text=True, check=True)
                for line in preview.stdout.splitlines():
                    if line.startswith(('ROLLBACK_PREVIEW_', 'ROLLBACK_TARGET_COMMIT=')):
                        name, value = line.split('=', 1)
                        env[name] = value
                if change == 'head':
                    git('commit', '--allow-empty', '-qm', 'later commit')
                elif change == 'branch':
                    git('checkout', '-qb', 'other-branch')
                elif change == 'target':
                    git('tag', '-f', env['CHECKPOINT_TAG'], 'HEAD')
                elif change == 'repository':
                    other = Path(temporary) / 'other'
                    git('clone', '-q', '--shared', str(repo), str(other))
                    repo = other
                    file = repo / 'work.txt'
                else:
                    env.pop({'missing-head': 'ROLLBACK_PREVIEW_HEAD',
                             'missing-root': 'ROLLBACK_PREVIEW_ROOT',
                             'missing-ref': 'ROLLBACK_PREVIEW_REF',
                             'missing-target': 'ROLLBACK_TARGET_COMMIT'}[change], None)
                before = (git('rev-parse', 'HEAD'), git('write-tree'), git('show-ref'), file.read_bytes())
                result = subprocess.run(['bash', '-c', recipe(step)], cwd=repo, env=env,
                                        capture_output=True, text=True, timeout=5)
                assert result.returncode != 0, (tree, step, change, result.stdout)
                assert 'preview' in result.stderr.lower(), (tree, step, change, result.stderr)
                after = (git('rev-parse', 'HEAD'), git('write-tree'), git('show-ref'), file.read_bytes())
                assert after == before, (tree, step, change, 'rollback mutated a different context')
                checks += 1
print(f'{checks} changed-context cases stopped without mutations')
PY
then test_pass; else test_fail "rollback accepted a changed or missing preview"; fi
test_summary
