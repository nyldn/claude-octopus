#!/usr/bin/env bash
# Rollback must not claim to restore a submodule by changing its gitlink alone.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Rollback submodule boundary"
test_case "changed submodules stop before index or worktree restoration"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
           GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
           GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
           CHECKPOINT_TAG='octo-checkpoint-fixture', LESSONS_PRESERVED='false')
checks = 0
for tree in ('.claude/skills', 'skills'):
    source = (root / tree / 'skill-rollback/SKILL.md').read_text().split('## Mode: ROLLBACK\n', 1)[1]
    def recipe(step):
        section = source.split('### Step ' + str(step) + ':', 1)[1]
        return re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for change in ('update', 'addition', 'removal', 'replacement', 'move', 'unchanged'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            base = Path(temporary)
            repo, origin = base / 'project', base / 'submodule-origin'
            repo.mkdir()
            origin.mkdir()
            def git(directory, *args):
                return subprocess.check_output(['git', '-C', str(directory), *args], env=env,
                                               stderr=subprocess.DEVNULL).decode().strip()
            for directory in (repo, origin):
                git(directory, 'init', '-q', '-b', 'main')
            (origin / 'content').write_text('first submodule revision\n')
            git(origin, 'add', '.')
            git(origin, 'commit', '-qm', 'first')
            first = git(origin, 'rev-parse', 'HEAD')
            (origin / 'content').write_text('second submodule revision\n')
            git(origin, 'commit', '-qam', 'second')
            second = git(origin, 'rev-parse', 'HEAD')
            module = repo / 'module with spaces'
            git(repo, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', str(origin), module.name)
            git(module, 'checkout', '-q', first)
            git(repo, 'add', module.name)
            regular = repo / 'regular.txt'
            regular.write_text('checkpoint ordinary file\n')
            if change == 'addition':
                git(repo, 'rm', '--cached', '-q', '--', module.name)
            git(repo, 'add', 'regular.txt')
            # Stage the first gitlink revision unless it is absent at checkpoint.
            if change != 'addition':
                git(repo, 'add', module.name)
            git(repo, 'commit', '-qm', 'checkpoint')
            git(repo, 'tag', env['CHECKPOINT_TAG'])
            if change == 'update':
                git(module, 'checkout', '-q', second)
            elif change == 'move':
                git(repo, 'mv', module.name, 'renamed\nmodule')
                module = repo / 'renamed\nmodule'
            elif change in ('removal', 'replacement'):
                git(repo, 'rm', '--cached', '-q', '--', module.name)
                module.rename(base / 'retained-module')
                if change == 'replacement':
                    module.write_text('ordinary replacement\n')
            regular.write_text('current ordinary file\n')
            git(repo, 'add', '-A')
            git(repo, 'commit', '-qm', 'current')
            assert not git(repo, 'status', '--porcelain'), change
            call_env = dict(env, TMPDIR=temporary)
            preview = subprocess.run(['bash', '-c', recipe(2)], cwd=repo, env=call_env,
                                     capture_output=True, text=True, check=True)
            for line in preview.stdout.splitlines():
                if line.startswith(('ROLLBACK_PREVIEW_', 'ROLLBACK_TARGET_COMMIT=')):
                    key, value = line.split('=', 1)
                    call_env[key] = value
            before = (git(repo, 'rev-parse', 'HEAD'), git(repo, 'write-tree'),
                      git(repo, 'show-ref'), regular.read_bytes())
            result = subprocess.run(['bash', '-c', recipe(5) + '\n' + recipe(6)],
                                    cwd=repo, env=call_env, capture_output=True, text=True, timeout=10)
            if change == 'unchanged':
                assert result.returncode == 0, (tree, change, result.stderr)
                assert regular.read_text() == 'checkpoint ordinary file\n'
                assert git(module, 'rev-parse', 'HEAD') == first
            else:
                assert result.returncode != 0, (tree, change, 'rollback reported success', result.stdout)
                assert 'submodule' in result.stderr.lower(), (tree, change, result.stderr)
                after = (git(repo, 'rev-parse', 'HEAD'), git(repo, 'write-tree'),
                         git(repo, 'show-ref'), regular.read_bytes())
                assert after == before, (tree, change, 'partial rollback changed the project')
                if change in ('update', 'addition'):
                    assert git(module, 'rev-parse', 'HEAD') == (second if change == 'update' else first)
            checks += 1
print(f'{checks} submodule rollback scenarios passed')
PY
then test_pass; else test_fail "rollback changed a gitlink without restoring its submodule"; fi
test_summary
