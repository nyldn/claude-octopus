#!/usr/bin/env bash
# Execute the rollback recipes against disposable repositories with user work.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Rollback worktree preservation"
test_case "dirty worktrees stop before preview, safety tag and restore"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
source = (root / '.claude/skills/skill-rollback/SKILL.md').read_text().split('## Mode: ROLLBACK\n', 1)[1]

def recipe(step, prepare=True):
    section = source.split('### Step ' + str(step) + ':', 1)[1]
    script = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    return recipe(5) + '\n' + script if step == 6 and prepare else script

checks = 0
with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
    repo = Path(temporary) / 'repo'
    repo.mkdir()
    backups = Path(temporary) / 'backups'
    backups.mkdir()
    env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
               GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
               GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
               CHECKPOINT_TAG='octo-checkpoint-fixture', LESSONS_PRESERVED='false', TMPDIR=str(backups))
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=repo, env=env, stderr=subprocess.DEVNULL)
    git('init', '-q')
    path = repo / 'file with spaces.txt'
    path.write_text('checkpoint\n')
    removed = repo / 'removed since checkpoint.txt'
    removed.write_text('restore this file\n')
    newline = repo / 'ignored\nlocal.txt'
    newline.write_text('checkpoint newline path\n')
    historical = repo / 'historical'
    historical.mkdir()
    (historical / 'config.env').write_text('checkpoint config\n')
    lessons = repo / '.octo/LESSONS.md'
    lessons.parent.mkdir()
    lessons.write_text('checkpoint lessons\n')
    nested = repo / 'nested'
    nested.mkdir()
    (nested / 'inside.txt').write_text('nested checkpoint\n')
    git('add', '.')
    git('commit', '-qm', 'checkpoint')
    git('tag', 'octo-checkpoint-fixture')
    path.write_text('current commit\n')
    removed.unlink()
    newline.unlink()
    (historical / 'config.env').unlink()
    historical.rmdir()
    added = repo / 'added since checkpoint.txt'
    added.write_text('remove this file on rollback\n')
    lessons.write_text('current lessons must survive\n')
    (nested / 'inside.txt').write_text('nested current\n')
    git('add', '-A')
    git('commit', '-qm', 'current')
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
        result = subprocess.run(['bash', '-c', recipe(6, prepare=False)], cwd=repo, env=invalid_env,
                                capture_output=True, timeout=5)
        assert result.returncode != 0
        assert path.read_text() == 'current commit\n'
        assert git('status', '--porcelain=v1') == before
        checks += 1
    # Ignored local files do not appear in the ordinary clean-tree guard.
    (repo / '.git/info/exclude').write_text('*\n')
    cache = repo / 'unrelated.cache'
    cache.write_text('keep ignored cache\n')
    # Git reports an ignored embedded repository as one trailing-slash entry.
    git('init', '-q', str(historical))
    embedded_file = historical / 'config.env'
    embedded_file.write_text('uncommitted embedded repository data\n')
    before_tree = git('write-tree')
    result = subprocess.run(['bash', '-c', recipe(6)], cwd=nested, env=env,
                            capture_output=True, timeout=5)
    assert result.returncode != 0, 'rollback overwrote an ignored embedded repository'
    assert b'ignored local files' in result.stderr, result.stderr
    assert embedded_file.read_text() == 'uncommitted embedded repository data\n'
    assert (historical / '.git/HEAD').is_file()
    assert git('write-tree') == before_tree
    assert git('rev-parse', 'HEAD') == head and git('tag', '-l') == clean_tags
    checks += 1
    shutil.rmtree(historical)
    for collision in (removed, newline, historical, removed / 'local.env'):
        collision.parent.mkdir(exist_ok=True)
        collision.write_text('ignored local data\n')
        assert not git('status', '--porcelain=v1', '--untracked-files=all')
        before_index = git('diff', '--cached', '--binary')
        result = subprocess.run(['bash', '-c', recipe(6)], cwd=nested, env=env,
                                capture_output=True, timeout=5)
        assert result.returncode != 0, ('rollback overwrote ignored local files', collision)
        assert b'ignored local files' in result.stderr, result.stderr
        assert collision.read_text() == 'ignored local data\n'
        assert git('diff', '--cached', '--binary') == before_index
        assert path.read_text() == 'current commit\n'
        assert git('rev-parse', 'HEAD') == head and git('tag', '-l') == clean_tags
        checks += 1
        collision.unlink()
        if collision.parent == removed:
            removed.rmdir()
    for step in (2, 4, 6):
        result = subprocess.run(['bash', '-c', recipe(step)], cwd=nested if step == 6 else repo, env=env,
                                capture_output=True, timeout=5)
        assert result.returncode == 0, (step, result.stdout, result.stderr)
        checks += 1
    assert path.read_text() == 'checkpoint\n'
    assert (nested / 'inside.txt').read_text() == 'nested checkpoint\n'
    assert not added.exists(), 'rollback retained a tracked file absent from the checkpoint'
    assert removed.read_text() == 'restore this file\n'
    assert lessons.read_text() == 'current lessons must survive\n'
    assert cache.read_text() == 'keep ignored cache\n'
    assert git('show', ':.octo/LESSONS.md') == b'current lessons must survive\n'
    assert not git('diff', '--cached', 'octo-checkpoint-fixture', '--', '.', ':(exclude).octo/LESSONS.md')
    checks += 1
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
        result = subprocess.run(['bash', '-c', recipe(step)], cwd=nested if step == 6 else repo, env=recovery_env,
                                capture_output=True, timeout=5)
        assert result.returncode == 0, (step, result.stdout, result.stderr)
        checks += 1
    assert path.read_text() == 'current commit\n'
    assert (nested / 'inside.txt').read_text() == 'nested current\n'
    assert added.read_text() == 'remove this file on rollback\n'
    assert not removed.exists(), 'safety recovery retained a file absent from its checkpoint'
    assert lessons.read_text() == 'current lessons must survive\n'
    checks += 1
    git('commit', '-qm', 'preserve recovered state')
    protected_head = git('rev-parse', 'HEAD').decode().strip()
    for kind in ('file', 'symlink'):
        lessons.unlink()
        lessons.parent.rmdir()
        if kind == 'file':
            lessons.parent.write_text('checkpoint replaces lessons directory\n')
        else:
            lessons.parent.symlink_to('historical')
        git('add', '-f', '--', '.octo')
        git('add', '-A')
        git('commit', '-qm', 'checkpoint with lessons ancestor ' + kind)
        tag = 'octo-checkpoint-ancestor-' + kind
        git('tag', tag)
        git('reset', '--hard', '-q', protected_head)
        before_tree = git('write-tree')
        before_status = git('status', '--porcelain=v1', '--untracked-files=all')
        result = subprocess.run(['bash', '-c', recipe(6)], cwd=nested,
                                env=dict(env, CHECKPOINT_TAG=tag),
                                capture_output=True, timeout=5)
        assert result.returncode != 0, ('rollback replaced protected lessons directory', kind)
        assert b'protected lessons' in result.stderr, result.stderr
        assert lessons.read_text() == 'current lessons must survive\n'
        assert git('show', ':.octo/LESSONS.md') == b'current lessons must survive\n'
        assert git('write-tree') == before_tree
        assert git('status', '--porcelain=v1', '--untracked-files=all') == before_status
        assert git('rev-parse', 'HEAD').decode().strip() == protected_head
        checks += 1
    git('update-index', '--skip-worktree', '--', '.octo/LESSONS.md')
    lessons.unlink()
    for kind in ('file', 'symlink'):
        before_tree = git('write-tree')
        before_flags = git('ls-files', '-v', '--', '.octo/LESSONS.md')
        result = subprocess.run(['bash', '-c', recipe(6)], cwd=nested,
                                env=dict(env, CHECKPOINT_TAG='octo-checkpoint-ancestor-' + kind),
                                capture_output=True, timeout=5)
        assert result.returncode != 0, ('rollback removed index-only lessons', kind)
        assert b'protected lessons' in result.stderr, result.stderr
        assert not lessons.exists()
        assert git('show', ':.octo/LESSONS.md') == b'current lessons must survive\n'
        assert git('write-tree') == before_tree
        assert git('ls-files', '-v', '--', '.octo/LESSONS.md') == before_flags
        assert git('rev-parse', 'HEAD').decode().strip() == protected_head
        checks += 1
    # History runs in a fresh shell after restoration, often from a subdirectory.
    state = repo / '.octo/STATE.md'
    state.write_text('fixture state\n')
    for target, safety_tag in (('', ''), ('octo-checkpoint-fixture', ''),
                               ('missing-target', safety), ('octo-checkpoint-fixture', 'missing-safety')):
        before = state.read_bytes()
        result = subprocess.run(['bash', '-c', recipe(7)], cwd=repo,
                                env=dict(env, CHECKPOINT_TAG=target, SAFETY_CHECKPOINT_TAG=safety_tag),
                                capture_output=True, timeout=5)
        assert result.returncode != 0, ('history accepted missing recovery context', target, safety_tag)
        assert state.read_bytes() == before, 'invalid context changed rollback history'
        checks += 1
    result = subprocess.run(['bash', '-c', recipe(7)], cwd=nested,
                            env=dict(env, SAFETY_CHECKPOINT_TAG=safety),
                            capture_output=True, timeout=5)
    assert result.returncode == 0, result.stderr
    history = state.read_text()
    assert '- **Target:** octo-checkpoint-fixture\n' in history, history
    assert '- **Safety checkpoint:** ' + safety + '\n' in history, history
    assert not (nested / '.octo/STATE.md').exists()
    checks += 1
    # Checkpoints can track symlinks, including a state path outside the repo.
    evil_tag = 'octo-checkpoint-$(id)'
    git('tag', evil_tag)
    with tempfile.TemporaryDirectory(dir=sys.argv[2]) as outside:
        victim = Path(outside) / 'STATE.md'
        victim.write_text('outside shell file must remain unchanged\n')
        before = victim.read_bytes()
        state.unlink()
        state.symlink_to(victim)
        result = subprocess.run(['bash', '-c', recipe(7)], cwd=nested,
                                env=dict(env, CHECKPOINT_TAG=evil_tag, SAFETY_CHECKPOINT_TAG=safety),
                                capture_output=True, timeout=5)
        assert result.returncode != 0, 'history followed a symlinked state file'
        assert victim.read_bytes() == before, 'history corrupted an external file'
        state.unlink()
        checks += 1
        saved = repo / 'saved-octo'
        state.parent.rename(saved)
        state.parent.symlink_to(outside)
        result = subprocess.run(['bash', '-c', recipe(7)], cwd=nested,
                                env=dict(env, SAFETY_CHECKPOINT_TAG=safety),
                                capture_output=True, timeout=5)
        assert result.returncode != 0, 'history followed a symlinked .octo directory'
        assert victim.read_bytes() == before
        state.parent.unlink()
        saved.rename(state.parent)
        checks += 1
    os.mkfifo(state)
    result = subprocess.run(['bash', '-c', recipe(7)], cwd=nested,
                            env=dict(env, SAFETY_CHECKPOINT_TAG=safety),
                            capture_output=True, timeout=5)
    assert result.returncode != 0, 'history accepted a non-regular state file'
    state.unlink()
    checks += 1
# Two simultaneous rollback preparations must retain different lesson bytes.
with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
    paths = []
    for number in (1, 2):
        project = Path(temporary) / str(number)
        (project / '.octo').mkdir(parents=True)
        subprocess.run(['git', 'init', '-q', str(project)], check=True)
        (project / '.octo/LESSONS.md').write_text(f'project {number} lessons')
        result = subprocess.run(['bash', '-eu', '-c', recipe(5) +
                                 '\nprintf "%s" "$LESSONS_BACKUP_DIR"'],
                                cwd=project, env=dict(os.environ, TMPDIR=temporary),
                                capture_output=True, text=True, check=True)
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
