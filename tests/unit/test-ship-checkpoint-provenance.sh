#!/usr/bin/env bash
# Execute the actual shipped-checkpoint recipe after source changes or Git failure.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Shipping checkpoint provenance"
test_case "only the audited clean revision receives a shipped checkpoint"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
import itertools
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
checked = 0
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'skill-ship/SKILL.md'
    if not entry.exists():
        continue
    section = entry.read_text().split('#### Step 2: Create Shipped Checkpoint', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for strict in (False, True):
        for scenario, nested in itertools.product(('clean', 'missing head', 'missing root', 'advanced head',
                         'unstaged', 'staged', 'untracked', 'wrong root', 'tag exists',
                         'assume modified', 'assume deleted', 'skip modified',
                         'skip deleted', 'sparse config', 'submodule clean', 'submodule hidden',
                         'submodule nested hidden', 'submodule skip', 'submodule dirty',
                         'concurrent commit'), (False, True)):
            with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                physical = Path(temporary) / 'physical'
                physical.mkdir()
                alias = Path(temporary) / 'aliased-temp'
                alias.symlink_to(physical, target_is_directory=True)
                project = alias / 'project'
                project.mkdir()
                env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
                env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                           GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                           GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                           ARCHIVE_TIMESTAMP='fixture')

                def git(*args):
                    return subprocess.check_output(['git', *args], cwd=project, env=env,
                                                   stderr=subprocess.DEVNULL, text=True).strip()

                git('init', '-q', '-b', 'main')
                (project / '.gitignore').write_text('.octo/\ncompleted\n')
                (project / 'source.txt').write_text('audited source\n')
                git('add', '.')
                git('commit', '-qm', 'audited revision')
                if scenario.startswith('submodule '):
                    child = Path(temporary) / 'child'
                    child.mkdir()
                    subprocess.run(['git', 'init', '-q', str(child)], env=env, check=True)
                    (child / 'child.txt').write_text('audited child\n')
                    subprocess.run(['git', '-C', str(child), 'add', '.'], env=env, check=True)
                    subprocess.run(['git', '-C', str(child), 'commit', '-qm', 'child'], env=env, check=True)
                    git('-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', str(child), 'sub')
                    if scenario == 'submodule nested hidden':
                        git('-C', 'sub', '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', str(child), 'nested')
                        git('-C', 'sub', 'commit', '-qam', 'nested child')
                    git('add', '.')
                    git('commit', '-qm', 'audited submodules')
                audited = git('rev-parse', 'HEAD')
                env.update(AUDIT_HEAD=audited, AUDIT_REPO=git('rev-parse', '--show-toplevel'))
                (project / '.octo').mkdir()
                (project / '.octo/STATE.md').write_text('status: delivery_pending\n')
                if scenario == 'missing head':
                    env.pop('AUDIT_HEAD')
                elif scenario == 'missing root':
                    env.pop('AUDIT_REPO')
                elif scenario in ('advanced head', 'unstaged', 'staged'):
                    (project / 'source.txt').write_text('unreviewed source\n')
                    if scenario != 'unstaged':
                        git('add', 'source.txt')
                    if scenario == 'advanced head':
                        git('commit', '-qm', 'unaudited revision')
                elif scenario == 'untracked':
                    (project / 'new-source.txt').write_text('unreviewed new source\n')
                elif scenario == 'wrong root':
                    env['AUDIT_REPO'] = str(Path(temporary) / 'different-checkout')
                elif scenario == 'tag exists':
                    git('tag', '-a', 'octo-checkpoint-shipped-fixture', '-m', 'existing checkpoint')
                elif scenario.startswith(('assume ', 'skip ')):
                    flag = '--assume-unchanged' if scenario.startswith('assume ') else '--skip-worktree'
                    git('update-index', flag, 'source.txt')
                    if scenario.endswith('deleted'):
                        (project / 'source.txt').unlink()
                    else:
                        (project / 'source.txt').write_text('hidden unreviewed source\n')
                    assert git('status', '--porcelain=v1') == ''
                elif scenario == 'sparse config':
                    git('config', 'core.sparseCheckout', 'true')
                if scenario.startswith('submodule ') and scenario != 'submodule clean':
                    sub = 'sub/nested' if scenario == 'submodule nested hidden' else 'sub'
                    if scenario != 'submodule dirty':
                        flag = '--skip-worktree' if scenario == 'submodule skip' else '--assume-unchanged'
                        git('-C', sub, 'update-index', flag, 'child.txt')
                    (project / sub / 'child.txt').write_text('unaudited child\n')
                    if scenario != 'submodule dirty':
                        assert git('status', '--porcelain=v1', '--ignore-submodules=none') == ''
                before_head = git('rev-parse', 'HEAD')
                before_index = git('write-tree')
                before_flags = git('ls-files', '-v')
                before_status = git('status', '--porcelain=v1')
                before_tags = git('show-ref', '--tags') if scenario == 'tag exists' else ''
                invocation_directory = project / 'nested' if nested else project
                invocation_directory.mkdir(exist_ok=True)
                command = ['bash', '-eu' if strict else '-c']
                if strict:
                    command.append('-c')
                if scenario == 'concurrent commit':
                    real_git = subprocess.check_output(['which', 'git'], text=True).strip()
                    wrapper_dir = Path(temporary) / 'bin'
                    wrapper_dir.mkdir()
                    wrapper = wrapper_dir / 'git'
                    wrapper.write_text('#!/usr/bin/env bash\n'
                                       'if [[ "$*" == *"status --porcelain=v1"* && ! -e "$RACE_MARKER" ]]; then\n'
                                       '  touch "$RACE_MARKER"\n'
                                       '  "$CHECKPOINT_TEST_GIT" -C "$AUDIT_REPO" commit --allow-empty -qm concurrent || exit 1\n'
                                       'fi\nexec "$CHECKPOINT_TEST_GIT" "$@"\n')
                    wrapper.chmod(0o755)
                    env.update(CHECKPOINT_TEST_GIT=real_git, RACE_MARKER=str(Path(temporary) / 'raced'),
                               PATH=str(wrapper_dir) + os.pathsep + env['PATH'])
                result = subprocess.run(command + [recipe + '\nprintf done > completed'],
                                        cwd=invocation_directory, env=env, capture_output=True, text=True, timeout=10)
                accepted = scenario in ('clean', 'submodule clean')
                valid = ((result.returncode == 0) == accepted
                         and (invocation_directory / 'completed').exists() == accepted
                         and (git('rev-parse', 'HEAD') != before_head if scenario == 'concurrent commit'
                              else git('rev-parse', 'HEAD') == before_head)
                         and git('write-tree') == before_index
                         and git('ls-files', '-v') == before_flags
                         and git('status', '--porcelain=v1') == before_status)
                if accepted:
                    valid = valid and git('rev-parse', 'octo-checkpoint-shipped-fixture^{}') == audited
                elif scenario == 'tag exists':
                    valid = valid and git('show-ref', '--tags') == before_tags
                else:
                    valid = valid and git('tag') == ''
                if not valid:
                    failures.append(f'{tree}: {scenario}, nested={nested}, strict={strict}, exit={result.returncode}')
                checked += 1
print(f'{checked - len(failures)}/{checked} actual checkpoint controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "checkpoint accepted unaudited source or continued after failure"; fi
test_summary
