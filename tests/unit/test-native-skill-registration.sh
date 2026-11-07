#!/usr/bin/env bash
# Claude must discover native skills while Codex keeps its adapted tree.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Native skill registration"
test_case "Claude registrations preserve native bodies, names, alias and starter pack"
if python3 - "$PROJECT_ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path
root = Path(sys.argv[1])
manifest = json.loads((root / '.claude-plugin/plugin.json').read_text())
registered = {path: (root / path / 'SKILL.md').read_text() for path in manifest['skills']}
for path, text in registered.items():
    assert 'Host: Codex CLI' not in text, f'Claude loads Codex instructions: {path}'
native = list((root / '.claude/skills').glob('*/SKILL.md'))
for source in native:
    name = re.search(r'^name: (.+)$', source.read_text(), re.M)[1]
    assert (root / 'skills' / name / 'SKILL.md').read_text() == source.read_text(), f'native body changed: {source}'
    assert not re.search(r'^agent: (Explore|Plan)$', source.read_text().split('---', 2)[1], re.M), f'read-only agent cannot execute native workflow: {source}'
assert set(registered) == {'./' + str(f.parent.relative_to(root)) for f in (root / 'skills').rglob('SKILL.md')}, 'automatic and explicit discovery differ'
assert len(registered) == 63, 'existing skill registration count changed'
assert any(re.search(r'^name: skill-verify$', text, re.M) for text in registered.values()), 'verification alias lost'
assert sum('/octopus-starter-pack/' in path for path in registered) == 4, 'starter pack lost'
assert json.loads((root / '.codex-plugin/plugin.json').read_text())['skills'] == './codex-skills/'
assert 'Host: Codex CLI' in (root / 'codex-skills/flow-develop/SKILL.md').read_text()
assert 'Bash tool' in (root / '.claude/skills/flow-develop/SKILL.md').read_text()
print(f'{len(native)} native sources and {len(registered)} registrations checked')
PY
then test_pass; else test_fail "host-specific skill registration contract failed"; fi

test_case "rollback safety checkpoint refuses staged, unstaged and untracked work"
if python3 - "$PROJECT_ROOT" <<'PY'
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
env = dict(os.environ, GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.invalid',
           GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.invalid',
           CLAUDE_PLUGIN_ROOT=str(root))
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    text = (root / tree / 'skill-rollback/SKILL.md').read_text()
    step = text.split('### Step 4:', 1)[1].split('### Step 5:', 1)[0]
    command = re.search(r'```bash\n(.*?)\n```', step, re.S)[1]
    for state in ('clean', 'staged', 'unstaged', 'untracked'):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=repo, env=env)
            git('init', '-q')
            (repo / 'work.txt').write_text('committed\n')
            git('add', 'work.txt')
            git('commit', '-qm', 'baseline')
            git('tag', 'target')
            if state in ('staged', 'unstaged'):
                (repo / 'work.txt').write_text('keep my edits\n')
            if state == 'staged':
                git('add', 'work.txt')
            if state == 'untracked':
                (repo / 'new.txt').write_text('keep new work\n')
            before = git('status', '--porcelain=v1', '--untracked-files=all')
            work = (repo / 'work.txt').read_bytes()
            result = subprocess.run(['bash', '-eu', '-c', command], cwd=repo,
                                    env=dict(env, CHECKPOINT_TAG='target'), capture_output=True)
            tags = git('tag', '--list', 'octo-checkpoint-pre-rollback-*')
            assert (result.returncode == 0) == (state == 'clean'), (tree, state, result.stderr)
            assert bool(tags) == (state == 'clean'), (tree, state, 'unsafe safety tag')
            assert git('status', '--porcelain=v1', '--untracked-files=all') == before
            assert (repo / 'work.txt').read_bytes() == work
            if state == 'untracked':
                assert (repo / 'new.txt').read_text() == 'keep new work\n'
print('12 rollback checkpoint scenarios passed across all three skill trees')
PY
then test_pass; else test_fail "rollback can misrepresent uncommitted work as recoverable"; fi

test_case "rollback preserves ignored files that collide with checkpoint paths"
if python3 - "$PROJECT_ROOT" <<'PY_IGNORED'
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
env = dict(os.environ, GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.invalid',
           GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.invalid',
           CLAUDE_PLUGIN_ROOT=str(root))
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    text = (root / tree / 'skill-rollback/SKILL.md').read_text()
    commands = {}
    for step in (4, 6):
        section = text.split(f'### Step {step}:', 1)[1].split(f'### Step {step + 1}:', 1)[0]
        commands[step] = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for state in ('ignored-file', 'ignored-directory', 'ignored-parent', 'unrelated-ignored'):
        for step in (4, 6):
            with tempfile.TemporaryDirectory() as temporary:
                repo = Path(temporary)
                def git(*args):
                    return subprocess.check_output(['git', *args], cwd=repo, env=env)
                git('init', '-q')
                target = 'archive' if state == 'ignored-directory' else 'archive/data.txt'
                path = repo / target
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('checkpoint bytes\n')
                git('add', '.')
                git('commit', '-qm', 'checkpoint')
                git('tag', 'target')
                git('rm', '-qr', 'archive')
                (repo / '.gitignore').write_text('archive\ncache\n')
                git('add', '.gitignore')
                git('commit', '-qm', 'ignore local archive')
                saved = repo / ('archive/local.txt' if state == 'ignored-directory' else
                                'archive' if state == 'ignored-parent' else
                                'cache/data.txt' if state == 'unrelated-ignored' else target)
                saved.parent.mkdir(parents=True, exist_ok=True)
                saved.write_text('private local bytes\n')
                before = git('status', '--porcelain=v1', '--untracked-files=all')
                assert before == b'', (state, before)
                result = subprocess.run(['bash', '-eu', '-c', commands[step]], cwd=repo,
                    env=dict(env, CHECKPOINT_TAG='target', LESSONS_PRESERVED='false'), capture_output=True)
                allowed = state == 'unrelated-ignored'
                assert (result.returncode == 0) == allowed, (tree, state, step, result.stderr)
                assert saved.read_text() == 'private local bytes\n', (tree, state, step)
                if not allowed:
                    assert git('status', '--porcelain=v1', '--untracked-files=all') == before
                    assert not git('tag', '--list', 'octo-checkpoint-pre-rollback-*')
                elif step == 6:
                    assert (repo / target).read_text() == 'checkpoint bytes\n'
print('24 ignored-file rollback scenarios passed across all three skill trees')
PY_IGNORED
then test_pass; else test_fail "rollback can overwrite ignored local work"; fi

test_summary
