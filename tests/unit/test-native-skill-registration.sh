#!/usr/bin/env bash
# Claude must discover native skills while Codex keeps its adapted tree.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
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
assert len(registered) == 64, 'existing skill registration count changed'
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
    for state in ('ignored-file', 'ignored-directory', 'ignored-parent', 'unrelated-ignored',
                  'ignored-nested-directory', 'ignored-nested-file'):
        for step in (4, 6):
            with tempfile.TemporaryDirectory() as temporary:
                repo = Path(temporary)
                def git(*args):
                    return subprocess.check_output(['git', *args], cwd=repo, env=env)
                git('init', '-q')
                target = 'archive' if state in ('ignored-directory', 'ignored-nested-file') else 'archive/data.txt'
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
                saved = repo / ('archive/local.txt' if state in ('ignored-directory', 'ignored-nested-file') else
                                'archive' if state == 'ignored-parent' else
                                'cache/data.txt' if state == 'unrelated-ignored' else target)
                saved.parent.mkdir(parents=True, exist_ok=True)
                saved.write_text('private local bytes\n')
                nested_head = None
                if state.startswith('ignored-nested-'):
                    git('-C', 'archive', 'init', '-q')
                    git('-C', 'archive', 'add', '.')
                    git('-C', 'archive', 'commit', '-qm', 'private nested work')
                    nested_head = git('-C', 'archive', 'rev-parse', 'HEAD')
                    assert b'archive/\0' in git('ls-files', '-z', '--others', '--ignored', '--exclude-standard')
                before = git('status', '--porcelain=v1', '--untracked-files=all')
                assert before == b'', (state, before)
                result = subprocess.run(['bash', '-eu', '-c', commands[step]], cwd=repo,
                    env=dict(env, CHECKPOINT_TAG='target', LESSONS_PRESERVED='false'), capture_output=True)
                allowed = state == 'unrelated-ignored'
                assert (result.returncode == 0) == allowed, (tree, state, step, result.stderr)
                assert saved.read_text() == 'private local bytes\n', (tree, state, step)
                if nested_head is not None:
                    assert git('-C', 'archive', 'rev-parse', 'HEAD') == nested_head
                if not allowed:
                    assert git('status', '--porcelain=v1', '--untracked-files=all') == before
                    assert not git('tag', '--list', 'octo-checkpoint-pre-rollback-*')
                elif step == 6:
                    assert (repo / target).read_text() == 'checkpoint bytes\n'
print('36 ignored-file rollback scenarios passed across all three skill trees')
PY_IGNORED
then test_pass; else test_fail "rollback can overwrite ignored local work"; fi

test_case "finish-branch choices preserve the selected action, base and test evidence"
if python3 "$PROJECT_ROOT/tests/fixtures/native-skills/finish-branch-recipes.py" "$PROJECT_ROOT" choices; then
    test_pass
else
    test_fail "finish-branch execution contradicts the selected action or evidence"
fi

test_case "failed branch operations preserve recovery work without shell error-exit mode"
if python3 "$PROJECT_ROOT/tests/fixtures/native-skills/finish-branch-recipes.py" "$PROJECT_ROOT" failures; then
    test_pass
else
    test_fail "failed finish-branch operation lost recovery work or continued"
fi

test_case "generator keeps canonical native sources and adapts new Codex entries"
if python3 - "$PROJECT_ROOT" <<'PY_CANONICAL'
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as directory:
    fixture = Path(directory)
    (fixture / 'scripts').mkdir()
    for script in ('build-codex-skills.sh', 'build-factory-skills.sh'):
        shutil.copy2(root / 'scripts' / script, fixture / 'scripts' / script)
    canonical = {}
    for name in ('skill-refine', 'flow-discover', 'demo'):
        source = fixture / '.claude/skills' / name / 'SKILL.md'
        source.parent.mkdir(parents=True)
        body = ('---\nname: ' + name + '\ndescription: Fixture skill\n'
                'disable-model-invocation: true\n---\nUse the Bash tool and '
                '`skills/blocks/method.md`.\n')
        source.write_text(body)
        if name != 'demo':
            native = fixture / 'skills' / name
            (native / 'references').mkdir(parents=True)
            (native / 'SKILL.md').write_text(body + 'Read `skills/' + name + '/references/phase.md`.\n')
            (native / 'references/phase.md').write_text(
                'Use the Bash tool and Agent tool. You (Claude) synthesize.\n'
                'Claude Code example: Agent(run_in_background: true).\n'
                '```bash\n'
                'if [[ -n "${PLAN_MODE_ACTIVE}" ]] || claude-code plan status 2>/dev/null | grep -q "active"; then\n'
                '  echo plan-active\n'
                'fi\n```\n')
            canonical[name] = (native / 'SKILL.md').read_bytes()
    blocks = fixture / 'skills/blocks'
    blocks.mkdir()
    (blocks / 'method.md').write_text('See `skills/blocks/other.md`.\n')
    generator = ['bash', str(fixture / 'scripts/build-codex-skills.sh')]
    def run(*arguments):
        return subprocess.run([*generator, *arguments], capture_output=True, text=True, timeout=30)
    result = run()
    assert result.returncode == 0, result.stderr
    for name, body in canonical.items():
        assert (fixture / '.claude/skills' / name / 'SKILL.md').read_bytes() == body
        assert (fixture / 'skills' / name / 'SKILL.md').read_bytes() == body
        adapted = (fixture / 'codex-skills' / name / 'SKILL.md').read_text()
        assert 'Host: Codex CLI' in adapted and 'native shell command tool' in adapted
        assert '`codex-skills/blocks/method.md`' in adapted
        assert '`codex-skills/' + name + '/references/phase.md`' in adapted, 'Codex entry loads native phase resources'
        resource = (fixture / 'codex-skills' / name / 'references/phase.md').read_text()
        native_resource = (fixture / 'skills' / name / 'references/phase.md').read_text()
        assert 'native shell command tool' in resource and 'host subagent tool' in resource
        assert 'You (the host model) synthesize.' in resource
        assert 'Agent(run_in_background: true)' in resource, 'labelled native call was corrupted'
        assert 'claude-code plan status' not in resource
        assert 'You (Claude)' in native_resource and 'Bash tool' in native_resource
        assert 'claude-code plan status' in native_resource, 'native resource was adapted'
        command = resource.split('```bash\n', 1)[1].split('\n```', 1)[0]
        for active, expected in ((None, ''), ('', ''), ('1', 'plan-active\n')):
            env = dict(os.environ)
            env.pop('PLAN_MODE_ACTIVE', None)
            if active is not None:
                env['PLAN_MODE_ACTIVE'] = active
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c',
                'claude-code() { echo unexpected-probe >&2; return 99; }; ' + command],
                env=env,
                capture_output=True, text=True, timeout=5)
            assert result.returncode == 0 and result.stdout == expected and not result.stderr, result
    assert 'codex-skills/blocks/other.md' in (fixture / 'codex-skills/blocks/method.md').read_text()
    assert 'codex-skills' not in (fixture / 'skills/blocks/method.md').read_text()
    def snapshot():
        return {str(p.relative_to(fixture)): p.read_bytes() for p in fixture.rglob('*') if p.is_file()}
    before = snapshot()
    result = run('--check')
    assert result.returncode == 0, result.stderr
    assert snapshot() == before, 'check mode mutated source or output'
    clean = subprocess.run(['bash', str(fixture / 'scripts/build-factory-skills.sh'), '--clean'],
                           capture_output=True, text=True, timeout=30)
    assert clean.returncode == 0, clean.stderr
    result = run()
    assert result.returncode == 0, result.stderr
    assert (fixture / 'skills/demo/SKILL.md').read_bytes() == (fixture / '.claude/skills/demo/SKILL.md').read_bytes()
    (fixture / 'skills/skill-refine/SKILL.md').unlink()
    before = snapshot()
    result = run()
    assert result.returncode != 0, 'missing canonical native input was accepted'
    assert snapshot() == before, 'failed generation removed output or changed sources'
print('Canonical preservation, new-entry adaptation, block paths, read-only check, clean/rebuild and missing-input checks passed')
PY_CANONICAL
then test_pass; else test_fail "generator damaged canonical ownership or host-specific references"; fi

test_case "rollback restores the complete tracked snapshot and preserves lessons"
if python3 - "$PROJECT_ROOT" <<'PY_SNAPSHOT'
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
root = Path(sys.argv[1])
env = dict(os.environ, GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.invalid',
           GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.invalid',
           CLAUDE_PLUGIN_ROOT=str(root), LESSONS_PRESERVED='false')
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    text = (root / tree / 'skill-rollback/SKILL.md').read_text()
    section = text.split('### Step 6:', 1)[1].split('### Step 7:', 1)[0]
    command = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for shape, invocation_dir in ((shape, directory) for shape in ('file', 'directory', 'symlink')
                                  for directory in ('.octo', '.', 'nested')):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=repo, env=env)
            git('init', '-q')
            (repo / '.octo').mkdir()
            (repo / 'nested').mkdir()
            (repo / 'nested/keep.txt').write_text('nested tracked file\n')
            (repo / '.octo/LESSONS.md').write_text('old lessons\n')
            (repo / 'work.txt').write_text('checkpoint content\n')
            (repo / 'restored.txt').write_text('restore this deleted file\n')
            git('add', '.')
            git('commit', '-qm', 'checkpoint')
            git('tag', 'target')
            git('rm', '-q', 'restored.txt')
            (repo / '.octo/LESSONS.md').write_text('keep current lessons\n')
            (repo / 'work.txt').write_text('new implementation\n')
            added = repo / 'post-checkpoint'
            if shape == 'directory':
                added.mkdir()
                (added / 'implementation.txt').write_text('later code\n')
            elif shape == 'symlink':
                added.symlink_to('work.txt')
            else:
                added.write_text('later code\n')
            git('add', '.')
            git('commit', '-qm', 'later implementation')
            before = git('rev-parse', 'HEAD')
            lessons_index = git('show', ':.octo/LESSONS.md')
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', command], cwd=repo / invocation_dir,
                                    env=dict(env, CHECKPOINT_TAG='target'), capture_output=True)
            assert result.returncode == 0, (tree, shape, result.stderr)
            assert (repo / '.octo/LESSONS.md').read_text() == 'keep current lessons\n', (tree, shape, invocation_dir, 'protected lessons overwritten')
            assert not added.exists() and not added.is_symlink(), (tree, shape, 'post-checkpoint path survived')
            assert (repo / 'work.txt').read_text() == 'checkpoint content\n'
            assert (repo / 'restored.txt').read_text() == 'restore this deleted file\n'
            assert (repo / '.octo/LESSONS.md').read_text() == 'keep current lessons\n'
            assert git('rev-parse', 'HEAD') == before, 'rollback moved HEAD'
            assert git('show', ':.octo/LESSONS.md') == lessons_index, 'protected lessons index changed'
            assert git('diff', '--cached', 'target', '--', '.', ':(exclude).octo/LESSONS.md') == b''
print('27 complete-snapshot rollbacks from root, nested and lessons directories passed across all three skill trees')
PY_SNAPSHOT
then test_pass; else test_fail "rollback left post-checkpoint code or lost protected lessons"; fi

test_case "rollback refuses hidden edits and protected lessons ancestor conflicts"
if python3 - "$PROJECT_ROOT" <<'PY_HIDDEN'
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
    for state in ('assume-unchanged', 'skip-worktree', 'ancestor-file', 'ancestor-symlink'):
        for step in (4, 6):
            with tempfile.TemporaryDirectory() as temporary:
                repo = Path(temporary)
                def git(*args):
                    return subprocess.check_output(['git', *args], cwd=repo, env=env)
                git('init', '-q')
                (repo / 'work.txt').write_text('checkpoint content\n')
                if state == 'ancestor-file':
                    (repo / '.octo').write_text('old file\n')
                elif state == 'ancestor-symlink':
                    (repo / '.octo').symlink_to('work.txt')
                git('add', '.')
                git('commit', '-qm', 'checkpoint')
                git('tag', 'target')
                if state.startswith('ancestor-'):
                    git('rm', '-q', '.octo')
                (repo / '.octo').mkdir()
                (repo / '.octo/LESSONS.md').write_text('keep current lessons\n')
                git('add', '.')
                git('commit', '-qm', 'current lessons')
                if state in ('assume-unchanged', 'skip-worktree'):
                    git('update-index', '--' + state, 'work.txt')
                    (repo / 'work.txt').write_text('hidden private edits\n')
                assert git('status', '--porcelain=v1', '--untracked-files=all') == b''
                before_index = (repo / '.git/index').read_bytes()
                before_flags = git('ls-files', '-v', '-z')
                before_tree = {str(p.relative_to(repo)): p.read_bytes() for p in repo.rglob('*')
                               if p.is_file() and '.git' not in p.relative_to(repo).parts}
                result = subprocess.run(['bash', '-euo', 'pipefail', '-c', commands[step]], cwd=repo,
                                        env=dict(env, CHECKPOINT_TAG='target'), capture_output=True)
                assert result.returncode != 0, (tree, state, step, 'unsafe restore allowed')
                after_tree = {str(p.relative_to(repo)): p.read_bytes() for p in repo.rglob('*')
                              if p.is_file() and '.git' not in p.relative_to(repo).parts}
                assert after_tree == before_tree, (tree, state, step, 'worktree changed')
                assert (repo / '.git/index').read_bytes() == before_index, 'index changed'
                assert git('ls-files', '-v', '-z') == before_flags, 'index flags changed'
                assert not git('tag', '--list', 'octo-checkpoint-pre-rollback-*'), 'unsafe safety tag created'
print('24 hidden-edit/ancestor-conflict refusals passed across all three skill trees')
PY_HIDDEN
then test_pass; else test_fail "rollback can erase hidden edits or protected lessons"; fi

test_case "documented safety recovery preserves rollback work and current lessons"
if python3 - "$PROJECT_ROOT" <<'PY_RECOVERY'
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
env = dict(os.environ, GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.invalid',
           GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.invalid',
           CLAUDE_PLUGIN_ROOT=str(root), TIMESTAMP='20261110-111700')
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    text = (root / tree / 'skill-rollback/SKILL.md').read_text()
    safety_section = text.split('### Step 4:', 1)[1].split('### Step 5:', 1)[0]
    safety_command = re.search(r'```bash\n(.*?)\n```', safety_section, re.S)[1]
    restore_section = text.split('### Step 6:', 1)[1].split('### Step 7:', 1)[0]
    restore = re.search(r'```bash\n(.*?)\n```', restore_section, re.S)[1]
    recovery_section = text.split('### Recover from the safety checkpoint', 1)[1]
    recovery = re.search(r'```bash\n(.*?)\n```', recovery_section, re.S)[1]
    for preservation, installation in ((p, i) for p in ('commit', 'stash')
                                       for i in ('installed', 'local-checkout')):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=repo, env=env)
            git('init', '-q')
            (repo / '.octo').mkdir()
            (repo / '.octo/LESSONS.md').write_text('old lessons\n')
            (repo / '.octo/STATE.md').write_text('old state\n')
            (repo / 'work.txt').write_text('checkpoint\n')
            (repo / 'old-only.txt').write_text('checkpoint-only file\n')
            git('add', '.')
            git('commit', '-qm', 'checkpoint')
            git('tag', 'target')
            if installation == 'local-checkout':
                helper = repo / 'scripts/helpers/rollback-preflight.py'
                helper.parent.mkdir(parents=True)
                helper.write_bytes((root / 'scripts/helpers/rollback-preflight.py').read_bytes())
            git('rm', '-q', 'old-only.txt')
            (repo / 'work.txt').write_text('current implementation\n')
            (repo / 'new-only.txt').write_text('current-only file\n')
            (repo / '.octo/LESSONS.md').write_text('keep current lessons\n')
            git('add', '.')
            git('commit', '-qm', 'current')
            run_env = dict(env, CLAUDE_PLUGIN_ROOT=str(repo if installation == 'local-checkout' else root),
                           CHECKPOINT_TAG='target')
            result = subprocess.run(['bash', '-eu', '-c', safety_command], cwd=repo,
                                    env=run_env, capture_output=True)
            assert result.returncode == 0, result.stderr
            safety = git('tag', '--list', 'octo-checkpoint-pre-rollback-*').decode().strip()
            run_env['TIMESTAMP'] = safety.removeprefix('octo-checkpoint-pre-rollback-')
            before = git('rev-parse', 'HEAD')
            result = subprocess.run(['bash', '-eu', '-c', restore], cwd=repo,
                                    env=run_env, capture_output=True)
            assert result.returncode == 0, result.stderr
            if installation == 'local-checkout':
                assert not helper.exists(), 'old checkpoint must remove the plugin helper'
            (repo / '.octo/STATE.md').write_text('rollback history update\n')
            (repo / 'local.txt').write_text('keep subsequent local work\n')
            dirty_index = git('diff', '--cached', '--binary')
            result = subprocess.run(['bash', '-eu', '-c', recovery], cwd=repo / '.octo',
                                    env=run_env, capture_output=True)
            assert result.returncode != 0, 'dirty recovery must refuse before preservation'
            assert git('diff', '--cached', '--binary') == dirty_index
            assert (repo / 'local.txt').read_text() == 'keep subsequent local work\n'
            if preservation == 'commit':
                git('add', '.')
                git('commit', '-qm', 'preserved rollback')
                saved = git('rev-parse', 'HEAD').decode().strip()
            else:
                git('stash', 'push', '--include-untracked', '-qm', 'preserved rollback')
                saved = git('rev-parse', 'stash@{0}').decode().strip()
                assert git('rev-parse', 'HEAD') == before
                assert git('show', saved + '^3:local.txt') == b'keep subsequent local work\n'
            assert git('show', saved + ':work.txt') == b'checkpoint\n'
            assert git('show', saved + ':.octo/STATE.md') == b'rollback history update\n'
            head = git('rev-parse', 'HEAD')
            lessons_index = git('show', ':.octo/LESSONS.md')
            checker = repo / os.fsdecode(git('rev-parse', '--git-path',
                'octo-rollback-preflight-' + run_env['TIMESTAMP'] + '.py')).strip()
            assert checker.stat().st_mode & 0o777 == 0o600, 'preflight copy must be private'
            saved_checker = checker.with_suffix('.saved')
            checker.rename(saved_checker)
            clean_index = git('diff', '--cached', '--binary')
            result = subprocess.run(['bash', '-eu', '-c', recovery], cwd=repo / '.octo',
                                    env=run_env, capture_output=True)
            assert result.returncode != 0, 'missing recovery preflight must fail closed'
            assert git('diff', '--cached', '--binary') == clean_index
            assert git('status', '--porcelain=v1', '--untracked-files=all') == b''
            saved_checker.rename(checker)
            result = subprocess.run(['bash', '-eu', '-c', recovery], cwd=repo / '.octo',
                                    env=run_env, capture_output=True)
            assert result.returncode == 0, (tree, preservation, installation, result.stderr)
            assert git('rev-parse', 'HEAD') == head
            assert git('rev-parse', safety + '^{commit}') == before
            assert (repo / 'work.txt').read_text() == 'current implementation\n'
            assert (repo / 'new-only.txt').read_text() == 'current-only file\n'
            assert not (repo / 'old-only.txt').exists()
            assert (repo / '.octo/LESSONS.md').read_text() == 'keep current lessons\n'
            assert git('show', ':.octo/LESSONS.md') == lessons_index
            assert git('diff', '--cached', safety, '--', '.', ':(exclude).octo/LESSONS.md') == b''
            assert git('cat-file', '-t', saved).strip() == b'commit'
print('12 installed/local-checkout dirty-refusal and commit/stash recovery scenarios passed across all three trees')
PY_RECOVERY
then test_pass; else test_fail "documented recovery cannot safely restore the safety checkpoint"; fi


test_case "rollback recipes preserve host roots, recovery guards, history and ignored lessons"
if python3 "$PROJECT_ROOT/tests/fixtures/native-skills/rollback-recipes.py" "$PROJECT_ROOT"; then
    test_pass
else
    test_fail "rollback recipe violated its restoration or recovery contract"
fi

test_case "rollback refuses checkpoint submodule changes before mutation"
if python3 - "$PROJECT_ROOT" <<'PY_SUBMODULE'
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
root = Path(sys.argv[1])
env = dict(os.environ, GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.invalid',
           GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.invalid', CLAUDE_PLUGIN_ROOT=str(root))
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    text = (root / tree / 'skill-rollback/SKILL.md').read_text()
    command = re.search(r'```bash\n(.*?)\n```', text.split('### Step 4:', 1)[1].split('### Step 5:', 1)[0], re.S)[1]
    for transition in ('changed', 'added', 'removed'):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            repo = base / 'parent'
            donor = base / 'donor'
            repo.mkdir()
            donor.mkdir()
            def git(*args, directory=repo):
                return subprocess.check_output(['git', *args], cwd=directory, env=env, stderr=subprocess.DEVNULL)
            git('init', '-q', directory=donor)
            (donor / 'file').write_text('first\n')
            git('add', '.', directory=donor)
            git('commit', '-qm', 'first', directory=donor)
            first = git('rev-parse', 'HEAD', directory=donor).decode().strip()
            (donor / 'file').write_text('second\n')
            git('commit', '-qam', 'second', directory=donor)
            git('init', '-q')
            (repo / 'work.txt').write_text('parent\n')
            git('add', '.')
            git('commit', '-qm', 'parent')
            if transition != 'added':
                git('-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', str(donor), 'module')
                git('checkout', '-q', first, directory=repo / 'module')
                git('add', '.')
            git('commit', '--allow-empty', '-qm', 'checkpoint')
            git('tag', 'target')
            if transition == 'removed':
                git('rm', '-qf', 'module')
            elif transition == 'added':
                git('-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', str(donor), 'module')
            else:
                git('checkout', '-q', git('rev-parse', 'HEAD', directory=donor).decode().strip(), directory=repo / 'module')
            git('add', '.')
            git('commit', '-qm', 'current')
            assert git('status', '--porcelain=v1', '--untracked-files=all') == b''
            before = git('diff', '--cached', '--binary')
            result = subprocess.run(['bash', '-eu', '-c', command], cwd=repo,
                                    env=dict(env, CHECKPOINT_TAG='target'), capture_output=True)
            assert result.returncode != 0, (tree, transition, 'unsafe checkpoint accepted')
            assert b'submodule' in result.stderr.lower(), result.stderr
            assert not git('tag', '--list', 'octo-checkpoint-pre-rollback-*')
            assert git('diff', '--cached', '--binary') == before
print('9 submodule transitions refused before checkpoint creation')
PY_SUBMODULE
then test_pass; else test_fail "rollback can report a complete snapshot with stale submodule worktrees"; fi

test_summary
