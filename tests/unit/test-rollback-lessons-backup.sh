#!/usr/bin/env bash
# Exercise the authored backup and restore recipes across separate shells.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Private rollback lessons backup"
test_case "private backup survives fresh shells and preserves unrelated files"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
checks = 0
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    source = (root / tree / 'skill-rollback/SKILL.md').read_text().split('## Mode: ROLLBACK\n', 1)[1]
    def recipe(step):
        section = source.split('### Step ' + str(step) + ':', 1)[1]
        return re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for mode in ('present', 'absent', 'dirty', 'missing-backup', 'linked-backup', 'linked-source'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2], prefix='lessons space ') as temporary:
            base = Path(temporary)
            repo = base / 'repo'
            repo.mkdir()
            env = dict(os.environ, TMPDIR=temporary, GIT_CONFIG_GLOBAL='/dev/null',
                       GIT_CONFIG_NOSYSTEM='1', GIT_AUTHOR_NAME='Fixture',
                       GIT_AUTHOR_EMAIL='fixture@example.invalid', GIT_COMMITTER_NAME='Fixture',
                       GIT_COMMITTER_EMAIL='fixture@example.invalid', CHECKPOINT_TAG='octo-checkpoint-fixture')
            for key in subprocess.check_output(['git', 'rev-parse', '--local-env-vars'], text=True).splitlines():
                env.pop(key, None)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(repo), *args], env=env,
                                               stderr=subprocess.DEVNULL)
            def run(step):
                # Relocate only the vulnerable legacy destination into this owned
                # fixture. Never touch a real shared backup or user lessons file.
                code = recipe(step).replace('/tmp/LESSONS_PRESERVED.md', shlex.quote(str(legacy)))
                return subprocess.run(['bash', '-c', code], cwd=repo, env=env,
                                      capture_output=True, text=True, timeout=10)
            def capture(result):
                assert result.returncode == 0, (tree, mode, result.stderr)
                for line in result.stdout.splitlines():
                    if line.startswith(('ROLLBACK_PREVIEW_', 'ROLLBACK_TARGET_COMMIT=',
                                        'LESSONS_BACKUP_DIR=', 'LESSONS_PRESERVED=')):
                        name, value = line.split('=', 1)
                        if name == 'LESSONS_BACKUP_DIR':
                            value = shlex.split(line)[0].split('=', 1)[1]
                        env[name] = value
            git('init', '-q', '-b', 'main')
            (repo / 'work.txt').write_text('checkpoint\n')
            (repo / '.octo').mkdir()
            lessons = repo / '.octo/LESSONS.md'
            if mode != 'absent':
                lessons.write_text('checkpoint lessons\n')
            git('add', '.')
            git('commit', '-qm', 'checkpoint')
            git('tag', env['CHECKPOINT_TAG'])
            (repo / 'work.txt').write_text('current\n')
            if mode != 'absent':
                lessons.write_text('current lessons\n')
            sentinel = base / 'unrelated'
            sentinel.write_text('untouched\n')
            legacy = base / 'LESSONS_PRESERVED.md'
            legacy.symlink_to(sentinel)
            if mode == 'linked-source':
                lessons.unlink()
                lessons.symlink_to(sentinel)
            git('add', '.')
            git('commit', '-qm', 'current')
            capture(run(2))
            preserved = run(5)
            assert sentinel.read_text() == 'untouched\n', (tree, mode, 'backup followed the occupied destination')
            if mode == 'linked-source':
                assert preserved.returncode != 0, (tree, mode, 'linked source admitted')
                checks += 1
                continue
            capture(preserved)
            assert env['LESSONS_PRESERVED'] == ('false' if mode == 'absent' else 'true')
            backup_dir = Path(env['LESSONS_BACKUP_DIR']) if env['LESSONS_BACKUP_DIR'] else None
            if backup_dir:
                backup = backup_dir / 'LESSONS.md'
                assert backup_dir.stat().st_mode & 0o777 == 0o700
                assert backup.stat().st_mode & 0o777 == 0o600
                assert backup.read_text() == 'current lessons\n'
            if mode == 'dirty':
                (repo / 'work.txt').write_text('unsaved work\n')
            elif mode == 'missing-backup':
                backup.unlink()
            elif mode == 'linked-backup':
                backup.unlink()
                backup.symlink_to(sentinel)
            before = git('write-tree')
            result = run(6)
            if mode in ('present', 'absent'):
                assert result.returncode == 0, (tree, mode, result.stderr)
                assert (repo / 'work.txt').read_text() == 'checkpoint\n'
                assert lessons.read_text() == 'current lessons\n' if mode == 'present' else not lessons.exists()
                assert backup_dir is None or not backup_dir.exists()
            else:
                assert result.returncode != 0, (tree, mode, result.stderr)
                assert git('write-tree') == before
                assert (repo / 'work.txt').read_text() == ('unsaved work\n' if mode == 'dirty' else 'current\n')
                assert backup_dir.exists(), 'failed restoration discarded recovery state'
            assert legacy.is_symlink() and sentinel.read_text() == 'untouched\n'
            checks += 1
print(f'{checks} production backup/restore cases passed')
PY
then test_pass; else test_fail "rollback backup or recovery boundary failed"; fi
test_summary
