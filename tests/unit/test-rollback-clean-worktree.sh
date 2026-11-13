#!/usr/bin/env bash
# Execute the rollback recipes against disposable repositories with user work.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Rollback worktree preservation"
test_case "dirty worktrees stop before preview, safety tag and restore"
if python3 - "$PROJECT_ROOT" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
source = (root / '.claude/skills/skill-rollback/SKILL.md').read_text().split('## Mode: ROLLBACK\n', 1)[1]

def recipe(step):
    section = source.split('### Step ' + str(step) + ':', 1)[1]
    return re.search(r'```bash\n(.*?)\n```', section, re.S)[1]

checks = 0
with tempfile.TemporaryDirectory() as temporary:
    repo = Path(temporary)
    env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
               GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
               GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
               CHECKPOINT_TAG='octo-checkpoint-fixture', LESSONS_PRESERVED='false')
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=repo, env=env, stderr=subprocess.DEVNULL)
    git('init', '-q')
    path = repo / 'file with spaces.txt'
    path.write_text('checkpoint\n')
    git('add', '.')
    git('commit', '-qm', 'checkpoint')
    git('tag', 'octo-checkpoint-fixture')
    path.write_text('current commit\n')
    git('commit', '-qam', 'current')
    head = git('rev-parse', 'HEAD')
    clean_tags = git('tag', '-l')
    for state in ('unstaged', 'staged', 'staged deletion', 'untracked'):
        git('reset', '--hard', '-q', 'HEAD')
        untracked = repo / 'new user file.txt'
        if untracked.exists():
            untracked.unlink()
        if state == 'staged deletion':
            git('rm', '-q', '--', path.name)
        elif state == 'untracked':
            untracked.write_text('untracked user work\n')
        else:
            path.write_text('user work\n')
            if state == 'staged':
                git('add', '--', path.name)
        status = git('status', '--porcelain=v1', '--untracked-files=all')
        index = git('diff', '--cached', '--binary')
        files = {p.name: p.read_bytes() for p in repo.iterdir() if p.is_file()}
        for step in (2, 4, 6):
            result = subprocess.run(['bash', '-c', recipe(step)], cwd=repo, env=env,
                                    capture_output=True, timeout=5)
            assert result.returncode != 0, (state, step, result.stdout, result.stderr)
            assert b'Rollback requires a clean working tree and index' in result.stderr, (state, step, result.stderr)
            assert git('status', '--porcelain=v1', '--untracked-files=all') == status, (state, step)
            assert git('diff', '--cached', '--binary') == index, (state, step)
            assert {p.name: p.read_bytes() for p in repo.iterdir() if p.is_file()} == files, (state, step)
            assert git('rev-parse', 'HEAD') == head and git('tag', '-l') == clean_tags, (state, step)
            checks += 1
    untracked.unlink()
    git('reset', '--hard', '-q', 'HEAD')
    # Missing recovery context must stop before checkout changes any bytes.
    for invalid in ({}, {'LESSONS_PRESERVED': 'true'},
                    {'LESSONS_PRESERVED': 'true', 'LESSONS_BACKUP_DIR': '/nonexistent/rollback-fixture'}):
        invalid_env = dict(env)
        invalid_env.pop('LESSONS_PRESERVED', None)
        invalid_env.update(invalid)
        before = git('status', '--porcelain=v1')
        result = subprocess.run(['bash', '-c', recipe(6)], cwd=repo, env=invalid_env,
                                capture_output=True, timeout=5)
        assert result.returncode != 0
        assert path.read_text() == 'current commit\n'
        assert git('status', '--porcelain=v1') == before
        checks += 1
    for step in (2, 4, 6):
        result = subprocess.run(['bash', '-c', (recipe(5) + '\n' if step == 6 else '') + recipe(step)], cwd=repo, env=env,
                                capture_output=True, timeout=5)
        assert result.returncode == 0, (step, result.stdout, result.stderr)
        checks += 1
    assert path.read_text() == 'checkpoint\n'
    assert git('rev-parse', 'HEAD') == head
    safety = git('tag', '-l', 'octo-checkpoint-pre-rollback-*').decode().strip()
    recovery_env = dict(env, CHECKPOINT_TAG=safety)
    # Restoration stages changes. Returning to the safety checkpoint requires
    # preserving that restored state in a commit before another rollback.
    result = subprocess.run(['bash', '-c', recipe(2)], cwd=repo, env=recovery_env,
                            capture_output=True, timeout=5)
    assert result.returncode != 0 and path.read_text() == 'checkpoint\n'
    checks += 1
    git('commit', '-qm', 'preserve restored state')
    for step in (2, 6):
        result = subprocess.run(['bash', '-c', (recipe(5) + '\n' if step == 6 else '') + recipe(step)], cwd=repo, env=recovery_env,
                                capture_output=True, timeout=5)
        assert result.returncode == 0, (step, result.stdout, result.stderr)
        checks += 1
    assert path.read_text() == 'current commit\n'
# Two simultaneous rollback preparations must retain different lesson bytes.
with tempfile.TemporaryDirectory() as temporary:
    paths = []
    for number in (1, 2):
        project = Path(temporary) / str(number)
        (project / '.octo').mkdir(parents=True)
        (project / '.octo/LESSONS.md').write_text(f'project {number} lessons')
        result = subprocess.run(['bash', '-eu', '-c', recipe(5) +
                                 '\nprintf "%s" "$LESSONS_BACKUP_DIR"'],
                                cwd=project, capture_output=True, text=True, check=True)
        paths.append(Path(result.stdout.splitlines()[-1]))
    assert paths[0] != paths[1]
    for number, backup in enumerate(paths, 1):
        assert (backup / 'LESSONS.md').read_text() == f'project {number} lessons'
        assert backup.stat().st_mode & 0o077 == 0
        (backup / 'LESSONS.md').unlink()
        backup.rmdir()
        checks += 1
print(f'{checks} dirty, clean and recovery rollback recipe cases passed')
PY
then test_pass; else test_fail "rollback modified user work or rejected a clean restore"; fi
test_summary
