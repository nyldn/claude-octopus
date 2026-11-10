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

test_case "finish-branch choices execute the action displayed to the user"
if python3 - "$PROJECT_ROOT" <<'PY_CHOICES'
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    text = (root / tree / 'skill-finish-branch/SKILL.md').read_text()
    menu = dict(re.findall(r'^(\d+)\. \*\*([^*]+)\*\*', text, re.M))
    references = re.findall(r'^\| (\d+)\. ([^|]+)\|', text, re.M)
    examples = re.findall(r'Execute Option (\d+) \((Create PR|Merge locally)\)', text)
    assert len(references) == len(menu) and examples, (tree, 'missing choice references')
    cleanup = text.split('### Step 5: Cleanup', 1)[1].split('## Quick Reference', 1)[0]
    policies = re.findall(r'For Options ([\d, ]+):', cleanup)
    assert len(policies) == 2, (tree, 'missing cleanup/preservation policy')
    cleanup_choices, preserve_choices = (set(re.findall(r'\d+', policy)) for policy in policies)
    assert preserve_choices == set(menu) - cleanup_choices, (tree, 'worktree preservation incomplete')
    rows = re.findall(r'^\| (\d+)\. [^|]+\|([^\n]+)', text, re.M)
    advertised_cleanup = {choice for choice, columns in rows if columns.split('|')[-2].strip() == '✓'}
    assert cleanup_choices == advertised_cleanup, (tree, 'cleanup contradicts reference')
    mistakes = text.split('## Common Mistakes', 1)[1]
    cleanup_advice = re.search(r'Only cleanup for options ([\d, ]+)', mistakes)
    assert cleanup_advice, (tree, 'missing common-mistake cleanup policy')
    assert set(re.findall(r'\d+', cleanup_advice[1])) == cleanup_choices, (tree, 'common mistakes contradict cleanup policy')
    cases = [(choice, menu[choice], 'menu') for choice in ('1', '2')]
    cases += [(choice, action.strip(), 'quick reference') for choice, action in references
              if action.strip().lower() in ('create pr', 'merge locally')]
    cases += [(choice, action, 'integration example') for choice, action in examples]
    for choice, action, origin in cases:
        section = re.search(r'^#### Option ' + choice + r':[^\n]*\n(.*?)(?=^#### Option |\Z)',
                            text, re.M | re.S)[1]
        command = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            calls = base / 'calls'
            helper = base / 'scripts/safe-gh-comment.sh'
            helper.parent.mkdir()
            helper.write_text('#!/bin/bash\nprintf "safe-helper %s\\n" "$*" >> "$CALLS"\ncat >/dev/null\n')
            helper.chmod(0o755)
            # Functions replace only commands executed by this recipe. No real
            # remote, branch mutation, package manager or GitHub call can run.
            stubs = r"""
git() {
    printf 'git %s\n' "$*" >> "$CALLS"
    if [[ "$*" == 'branch --show-current' ]]; then printf 'feature\n'; fi
}
gh() { printf 'gh %s\n' "$*" >> "$CALLS"; printf 'fixture/repository\n'; }
npm() { printf 'npm %s\n' "$*" >> "$CALLS"; }
"""
            env = dict(os.environ, CALLS=str(calls), CLAUDE_PLUGIN_ROOT=str(base),
                       PR_TITLE='Fixture title', CHANGE_SUMMARY='Fixture summary',
                       CHANGE_REASON='Fixture reason')
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', stubs + command],
                                    env=env, capture_output=True, text=True, check=False)
            assert result.returncode == 0, (tree, choice, result.stderr)
            actions = calls.read_text().splitlines()
            if action.lower() == 'create pr':
                assert 'git push -u origin feature' in actions, (tree, choice, actions)
                assert any(a.startswith('safe-helper ') and ' pr-create ' in a for a in actions), actions
                assert not any(a.startswith(('git checkout ', 'git pull ', 'git merge ', 'git branch -d '))
                               for a in actions), (tree, choice, 'unexpected local merge', actions)
            elif action.lower() == 'merge locally':
                for action in ('git checkout main', 'git pull origin main', 'git merge feature',
                               'npm test', 'git branch -d feature'):
                    assert action in actions, (tree, choice, actions)
                assert not any(a.startswith(('git push ', 'safe-helper ')) for a in actions), actions
            else:
                raise AssertionError((tree, choice, 'unknown displayed choice', action))
print('15 menu/reference/example recipes passed across source, native and Codex trees')
PY_CHOICES
then test_pass; else test_fail "finish-branch execution contradicts the selected menu action"; fi

test_case "generator keeps canonical native sources and adapts new Codex entries"
if python3 - "$PROJECT_ROOT" <<'PY_CANONICAL'
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
            (native / 'SKILL.md').write_text(body + 'Canonical phase entry.\n')
            (native / 'references/phase.md').write_text('Shared phase instructions.\n')
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
        assert (fixture / 'codex-skills' / name / 'references/phase.md').is_file()
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

test_summary
