#!/usr/bin/env bash
# Exercise the actual restore recipe where Git can leave a partial tree.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Rollback complete tree boundary"
test_case "partial checkouts and linked lessons stop before any restoration"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
env_base = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                CHECKPOINT_TAG='octo-checkpoint-fixture', LESSONS_PRESERVED='false')
for key in subprocess.check_output(['git', 'rev-parse', '--local-env-vars'], text=True).splitlines():
    env_base.pop(key, None)
failures = []
checks = 0
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    source = (root / tree / 'skill-rollback/SKILL.md').read_text().split('## Mode: ROLLBACK\n', 1)[1]
    def recipe(step):
        section = source.split('### Step ' + str(step) + ':', 1)[1]
        return re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for mode in ('complete', 'protected-skip', 'protected-assume', 'sparse-cone',
                 'sparse-noncone', 'skip-worktree', 'skip-assume', 'assume-clean',
                 'assume-edited', 'assume-deleted', 'linked-lessons', 'linked-file'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            base = Path(temporary)
            repo = base / 'repo'
            repo.mkdir()
            env = dict(env_base, TMPDIR=temporary)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(repo), *args], env=env,
                                               stderr=subprocess.DEVNULL)
            def run(step):
                return subprocess.run(['bash', '-c', recipe(step)], cwd=repo, env=env,
                                      capture_output=True, text=True, timeout=10)
            git('init', '-q', '-b', 'main')
            for path in ('visible/file.txt', 'hidden/file.txt', '.octo/LESSONS.md'):
                file = repo / path
                file.parent.mkdir(exist_ok=True)
                file.write_text('checkpoint\n')
            if mode == 'linked-file':
                (repo / '.octo/LESSONS.md').unlink()
                (repo / '.octo/LESSONS.md').symlink_to('knowledge.md')
                (repo / '.octo/knowledge.md').write_text('checkpoint\n')
            git('add', '.')
            git('commit', '-qm', 'checkpoint')
            git('tag', env['CHECKPOINT_TAG'])
            for path in ('visible/file.txt', 'hidden/file.txt', '.octo/LESSONS.md'):
                (repo / path).write_text('current\n')
            if mode == 'linked-lessons':
                (repo / '.octo/LESSONS.md').unlink()
                (repo / '.octo').rmdir()
                external = base / 'external'
                external.mkdir()
                (external / 'LESSONS.md').write_text('external lessons must survive\n')
                (repo / '.octo').symlink_to(external, target_is_directory=True)
            git('add', '-A')
            git('commit', '-qm', 'current')
            if mode.startswith('sparse-'):
                git('sparse-checkout', 'init', '--cone' if mode == 'sparse-cone' else '--no-cone')
                git('sparse-checkout', 'set', 'visible' if mode == 'sparse-cone' else '/visible/')
            elif mode in ('skip-worktree', 'skip-assume'):
                git('update-index', '--skip-worktree', 'hidden/file.txt')
                if mode == 'skip-assume':
                    git('update-index', '--assume-unchanged', 'hidden/file.txt')
            elif mode.startswith('assume-'):
                git('update-index', '--assume-unchanged', 'hidden/file.txt')
                if mode == 'assume-edited':
                    (repo / 'hidden/file.txt').write_text('uncommitted user work\n')
                elif mode == 'assume-deleted':
                    (repo / 'hidden/file.txt').unlink()
                assert not git('status', '--porcelain=v1'), 'fixture did not hide local work'
            elif mode == 'protected-skip':
                git('update-index', '--skip-worktree', '.octo/LESSONS.md')
            elif mode == 'protected-assume':
                git('update-index', '--assume-unchanged', '.octo/LESSONS.md')
                (repo / '.octo/LESSONS.md').write_text('uncommitted lessons must survive\n')
            # Supply private recovery state for variants that require it. The
            # legacy backup recipe uses a shared /tmp filename, so do not run it.
            backup = base / 'backup'
            backup.mkdir()
            env['LESSONS_BACKUP_DIR'] = str(backup)
            for step in (2,):
                result = run(step)
                assert result.returncode == 0, (tree, mode, step, result.stderr)
                for line in result.stdout.splitlines():
                    if line.startswith(('ROLLBACK_PREVIEW_', 'ROLLBACK_TARGET_COMMIT=',
                                        'LESSONS_BACKUP_DIR=', 'LESSONS_PRESERVED=')):
                        name, value = line.split('=', 1)
                        env[name] = value
            before_tree = git('write-tree')
            before_flags = git('ls-files', '-v', '-z')
            hidden = repo / 'hidden/file.txt'
            before_hidden = hidden.read_bytes() if hidden.exists() else None
            before_head = git('rev-parse', 'HEAD')
            before_tags = git('tag', '-l')
            result = run(6)
            if mode in ('complete', 'protected-skip', 'protected-assume'):
                assert result.returncode == 0, (tree, mode, result.stderr)
                assert (repo / 'visible/file.txt').read_text() == 'checkpoint\n'
                assert (repo / 'hidden/file.txt').read_text() == 'checkpoint\n'
                expected_lessons = 'uncommitted lessons must survive\n' if mode == 'protected-assume' else 'current\n'
                assert (repo / '.octo/LESSONS.md').read_text() == expected_lessons
            else:
                diagnostic = 'protected lessons' if mode in ('linked-lessons', 'linked-file') else 'complete working tree'
                if result.returncode == 0 or diagnostic not in result.stderr:
                    if mode == 'linked-file' and result.returncode == 0:
                        assert (repo / '.octo/knowledge.md').read_text() == 'checkpoint\n', 'control did not restore the backing file'
                    failures.append((tree, mode, result.returncode, result.stderr))
                    continue
                assert git('write-tree') == before_tree, (tree, mode, 'index changed')
                assert git('ls-files', '-v', '-z') == before_flags, (tree, mode, 'index flags changed')
                assert (hidden.read_bytes() if hidden.exists() else None) == before_hidden, (tree, mode, 'hidden local work changed')
                assert (repo / 'visible/file.txt').read_text() == 'current\n'
                if mode == 'linked-lessons':
                    assert (repo / '.octo').is_symlink()
                    assert (external / 'LESSONS.md').read_text() == 'external lessons must survive\n'
                if mode == 'linked-file':
                    assert (repo / '.octo/LESSONS.md').is_symlink()
                    assert (repo / '.octo/knowledge.md').read_text() == 'current\n'
                if mode == 'skip-worktree':
                    assert (repo / 'hidden/file.txt').read_text() == 'current\n'
            assert git('rev-parse', 'HEAD') == before_head
            assert git('tag', '-l') == before_tags
            checks += 1
assert not failures, failures
print(f'{checks} production restore cases passed')
PY
then test_pass; else test_fail "rollback accepted a partial or linked protected tree"; fi
test_summary
