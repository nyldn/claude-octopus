#!/usr/bin/env python3
"""Execute the shipped checkpoint recipe against disposable committed source."""
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve()
TREES = ('.claude/skills', 'skills', 'codex-skills')


class DevelopCheckpoint(unittest.TestCase):
    def test_planning_stage_does_not_record_phase_completion(self):
        for tree in TREES:
            with self.subTest(tree=tree), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                source = (ROOT / tree / 'flow-develop/SKILL.md').read_text()
                section = source.split('### STEP 6:', 1)[1].split('### STEP 7:', 1)[0]
                block = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
                helper = base / 'scripts/state-manager.sh'
                helper.parent.mkdir()
                marker = base / 'completion-recorded'
                helper.write_text('#!/bin/sh\nif [ "$1 $2" = "update_metrics phases_completed" ]; then\n'
                                  '  touch ' + shlex.quote(str(marker)) + '\nfi\n')
                helper.chmod(0o755)
                synthesis = base / 'proposal.md'
                synthesis.write_text('## Implementation\nusing a proposed approach\n')
                env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(base), CODEX_PLUGIN_ROOT=str(base),
                           SYNTHESIS_FILE=str(synthesis))
                result = subprocess.run(['/bin/bash', '-u', '-c', block], env=env,
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(marker.exists())

    def test_checkpoint_requires_the_clean_commit_that_passed_checks(self):
        for tree in TREES:
            source = (ROOT / tree / 'flow-develop/SKILL.md').read_text()
            section = source.split('## Post-Development: Checkpoint', 1)[1]
            block = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
            for mode in ('clean', 'staged', 'unstaged', 'untracked', 'failed-check', 'changed-commit',
                         'changed-worktree', 'tag-collision', 'missing-command'):
                with self.subTest(tree=tree, mode=mode), tempfile.TemporaryDirectory() as directory:
                    base = Path(directory)
                    project = base / 'project'
                    project.mkdir()
                    plugin = base / 'plugin'
                    (plugin / 'scripts').mkdir(parents=True)
                    marker = base / 'state-updated'
                    state = plugin / 'scripts/octo-state.sh'
                    state.write_text('#!/bin/sh\nprintf \'%s\\n\' "$*" >> ' + shlex.quote(str(marker)) + '\n')
                    state.chmod(0o755)
                    (plugin / 'scripts/state-manager.sh').write_bytes(state.read_bytes())
                    (plugin / 'scripts/state-manager.sh').chmod(0o755)
                    checked = base / 'checks-ran'
                    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
                    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                               GIT_TEMPLATE_DIR=str(base / 'empty-template'),
                               GIT_AUTHOR_NAME='Fixture', GIT_COMMITTER_NAME='Fixture',
                               GIT_AUTHOR_EMAIL='fixture@example.invalid', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                               CLAUDE_PLUGIN_ROOT=str(plugin), CODEX_PLUGIN_ROOT=str(plugin), CHECK_MODE=mode)
                    Path(env['GIT_TEMPLATE_DIR']).mkdir()
                    def git(*args):
                        return subprocess.check_output(['git', *args], cwd=project, env=env, stderr=subprocess.DEVNULL)
                    git('init', '-q')
                    git('config', 'commit.gpgsign', 'false')
                    git('config', 'tag.gpgsign', 'false')
                    code = project / 'code.py'
                    code.write_text('value = 1\n')
                    git('add', 'code.py')
                    git('commit', '-qm', 'baseline')
                    code.write_text('value = 2\n')
                    git('commit', '-qam', 'implementation')
                    head = git('rev-parse', 'HEAD').decode().strip()
                    if mode in ('staged', 'unstaged'):
                        code.write_text('value = 3\n')
                        if mode == 'staged':
                            git('add', 'code.py')
                    if mode == 'untracked':
                        (project / 'new.py').write_text('preserve this new implementation\n')
                    tag = 'octo-checkpoint-post-develop-fixture-time'
                    if mode == 'tag-collision':
                        git('tag', tag, 'HEAD^')
                    before = git('status', '--porcelain=v1', '--untracked-files=all')
                    check = base / 'project-check.py'
                    check.write_text('import os, subprocess\nfrom pathlib import Path\n'
                        'assert Path("code.py").read_text() == "value = 2\\n"\n'
                        'Path(' + repr(str(checked)) + ').touch()\n'
                        'mode = os.environ["CHECK_MODE"]\n'
                        'if mode == "failed-check": raise SystemExit(19)\n'
                        'if mode in ("changed-commit", "changed-worktree"):\n'
                        '    Path("code.py").write_text("value = 3\\n")\n'
                        '    if mode == "changed-commit": subprocess.run(["git", "commit", "-qam", "concurrent"], check=True)\n')
                    prefix = 'date() { printf "fixture-time\\n"; }\n'
                    if mode != 'missing-command':
                        prefix += 'DEVELOP_CHECK_COMMAND=(' + shlex.quote(sys.executable) + ' ' + shlex.quote(str(check)) + ')\n'
                    result = subprocess.run(['/bin/bash', '-u', '-c', prefix + block], cwd=project,
                                            env=env, capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode == 0, mode == 'clean', result.stdout + result.stderr)
                    if mode == 'clean':
                        self.assertEqual(git('rev-parse', tag + '^{commit}').decode().strip(), head)
                        self.assertEqual(git('show', tag + ':code.py'), b'value = 2\n')
                        self.assertTrue(checked.exists())
                        self.assertTrue(marker.exists())
                        self.assertEqual(marker.read_text().splitlines().count('update_metrics phases_completed 1'), 1)
                    else:
                        self.assertFalse(marker.exists(), result.stdout)
                        if mode == 'tag-collision':
                            self.assertEqual(git('rev-parse', tag + '^{commit}'), git('rev-parse', 'HEAD^'))
                        else:
                            self.assertEqual(git('tag', '--list', tag), b'')
                        if mode in ('staged', 'unstaged', 'untracked'):
                            self.assertEqual(git('status', '--porcelain=v1', '--untracked-files=all'), before)
                            self.assertFalse(checked.exists())
                            if mode != 'untracked':
                                self.assertEqual(code.read_text(), 'value = 3\n')


if __name__ == '__main__':
    unittest.main()
