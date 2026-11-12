"""Run shipped branch-finishing recipes against disposable Git repositories."""
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv[1]).resolve()
MODE = sys.argv[2]
BASH = os.environ.get('OCTOPUS_TEST_BASH', 'bash')
TREES = ('.claude/skills', 'skills', 'codex-skills')


def recipe(tree, option):
    text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
    section = text.split('#### Option %s:' % option, 1)[1]
    section = re.split(r'^#### Option |^### Step ', section, maxsplit=1, flags=re.M)[0]
    return re.search(r'```bash\n(.*?)\n```', section, re.S)[1]


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='finish branch ')
        self.root = Path(self.temporary.name).resolve()
        self.addCleanup(self.temporary.cleanup)
        self.base = self.root / 'base checkout'
        self.feature = self.root / 'feature checkout'
        self.remote = self.root / 'remote.git'
        hooks = self.root / 'empty hooks'
        hooks.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                        GIT_TEMPLATE_DIR=str(hooks), GIT_CONFIG_COUNT='1',
                        GIT_CONFIG_KEY_0='core.hooksPath', GIT_CONFIG_VALUE_0=str(hooks))
        self.git('init', '--bare', '--quiet', str(self.remote), cwd=self.root)
        self.git('init', '--quiet', '-b', 'trunk', str(self.base), cwd=self.root)
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        (self.base / 'file').write_text('original\n')
        (self.base / 'blocked').write_text('tracked on trunk\n')
        self.git('add', 'file', 'blocked')
        self.git('commit', '--quiet', '-m', 'initial')
        self.git('remote', 'add', 'origin', str(self.remote))
        self.git('push', '--quiet', '-u', 'origin', 'trunk')
        self.git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/trunk')
        self.git('worktree', 'add', '--quiet', '-b', 'topic', str(self.feature))
        (self.feature / 'file').write_text('feature change\n')
        self.git('rm', '--quiet', 'blocked', cwd=self.feature)
        self.git('add', 'file', cwd=self.feature)
        self.git('commit', '--quiet', '-m', 'feature', cwd=self.feature)
        self.head = self.git('rev-parse', 'HEAD', cwd=self.feature)
        self.env.update(FEATURE_ROOT=str(self.feature), FEATURE_BRANCH='topic',
                        BASE_BRANCH='trunk', BASE_WORKTREE=str(self.base), REVIEWED_HEAD=self.head)
        self.check = self.root / 'project check.py'
        self.marker = self.root / 'checked'
        self.check.write_text(
            'from pathlib import Path\nimport subprocess\n'
            "assert subprocess.check_output(['git', 'branch', '--show-current'], text=True).strip() == 'trunk'\n"
            "assert Path('file').read_text() == 'feature change\\n'\n"
            'Path(%r).write_text(str(Path.cwd()))\n' % str(self.marker))
        self.prefix = 'TEST_COMMAND=(%s %s)\n' % (shlex.quote(sys.executable), shlex.quote(str(self.check)))

    def git(self, *args, cwd=None, check=True):
        result = subprocess.run(['git', *args], cwd=cwd or self.base, env=self.env,
                                capture_output=True, text=True, check=check)
        return result.stdout.strip()

    def run_recipe(self, tree, option, prefix='', **env):
        return subprocess.run([BASH, '-uo', 'pipefail', '-c', self.prefix + prefix +
                               recipe(tree, option) + '\nprintf "RECIPE_FINISHED\\n"'],
                              cwd=self.feature, env=dict(self.env, **env), capture_output=True, text=True)

    def preserved(self):
        self.assertEqual(self.git('rev-parse', 'topic'), self.head)
        self.assertTrue(self.feature.is_dir())


class Choices(Fixture):
    def test_menu_and_cleanup_agree(self):
        for tree in TREES:
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            menu = dict(re.findall(r'^(\d+)\. \*\*([^*]+)\*\*', text, re.M))
            self.assertEqual(menu, {'1': 'Create PR', '2': 'Merge locally', '3': 'Keep as-is', '4': 'Discard'})
            rows = dict(re.findall(r'^\| (\d+)\. ([^|]+)\|', text, re.M))
            self.assertEqual({k: v.strip() for k, v in rows.items()}, menu)
            self.assertEqual(re.findall(r'^### Step (\d+):', text, re.M), list('1234567'))
            cleanup = text.split('### Step 7: Cleanup', 1)[1].split('## Quick Reference', 1)[0]
            self.assertIn('For Options 2, 4:', cleanup)
            self.assertIn('For Options 1, 3:', cleanup)
            self.assertIn('primary checkout must remain', cleanup)
            self.assertIn('no useful ignored files', cleanup)

    def test_non_main_base_resolved_before_review(self):
        for tree in TREES:
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            setup = re.search(r'```bash\n(.*?)\n```', text, re.S)[1]
            env = dict(self.env)
            env.pop('BASE_BRANCH')
            result = subprocess.run([BASH, '-uo', 'pipefail', '-c', setup +
                                     '\nprintf "BASE=%s\\n" "$BASE_BRANCH"'], cwd=self.feature,
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('BASE=trunk', result.stdout)
            self.assertNotIn('merge-base HEAD main', text)

    def test_python_checks_run_in_existing_base_worktree(self):
        for tree in TREES:
            # Reset only this disposable base so each shipped recipe does a real merge.
            self.git('reset', '--hard', 'origin/trunk')
            result = self.run_recipe(tree, '2')
            self.assertEqual(result.returncode, 0, (tree, result.stderr))
            self.assertEqual(Path(self.marker.read_text()), self.base)
            self.assertEqual(self.git('branch', '--show-current', cwd=self.feature), 'topic')
            self.assertEqual(self.git('rev-parse', 'HEAD'), self.head)
            self.preserved()

    def test_pr_forwards_base_and_actual_evidence(self):
        plugin = self.root / 'plugin'
        helper = plugin / 'scripts/safe-gh-comment.sh'
        helper.parent.mkdir(parents=True)
        helper.write_text('#!/bin/bash\nprintf "%s\\0" "$@" > "$ARGS_FILE"\ncat > "$BODY_FILE"\n')
        helper.chmod(0o755)
        for tree in TREES:
            args = self.root / 'args'
            body = self.root / 'body'
            result = self.run_recipe(tree, '1',
                                     prefix='gh() { printf "fixture/repository\\n"; }\n',
                                     CLAUDE_PLUGIN_ROOT=str(plugin), ARGS_FILE=str(args), BODY_FILE=str(body),
                                     PR_TITLE='Fix fixture', CHANGE_SUMMARY='Keep the feature.',
                                     CHANGE_REASON='Verify the recipe.',
                                     VALIDATION_SUMMARY='Python project checks passed on the reviewed commit.')
            self.assertEqual(result.returncode, 0, (tree, result.stderr))
            self.assertEqual(args.read_bytes().split(b'\0')[:-1],
                             [b'--repo', b'fixture/repository', b'pr-create', b'Fix fixture', b'topic', b'-', b'trunk'])
            self.assertIn('Python project checks passed', body.read_text())
            self.assertNotIn('Manual verification done', body.read_text())
            self.assertEqual(self.git('rev-parse', 'refs/heads/topic', cwd=self.remote), self.head)
            self.preserved()


class Failures(Fixture):
    def test_missing_default_base_stops(self):
        self.git('symbolic-ref', '--delete', 'refs/remotes/origin/HEAD')
        for tree in TREES:
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            setup = re.search(r'```bash\n(.*?)\n```', text, re.S)[1]
            env = dict(self.env)
            env.pop('BASE_BRANCH')
            result = subprocess.run([BASH, '-uo', 'pipefail', '-c', setup + '\necho CONTINUED'],
                                    cwd=self.feature, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('CONTINUED', result.stdout)

    def test_no_test_command_stops_before_merge(self):
        before = self.git('rev-parse', 'HEAD')
        for tree in TREES:
            result = self.run_recipe(tree, '2', prefix='TEST_COMMAND=()\n')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('RECIPE_FINISHED', result.stdout)
            self.assertEqual(self.git('rev-parse', 'HEAD'), before)
            self.preserved()

    def test_failed_merged_checks_preserve_recovery_branch(self):
        for tree in TREES:
            self.git('reset', '--hard', 'origin/trunk')
            result = self.run_recipe(tree, '2', prefix='TEST_COMMAND=(false)\n')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('RECIPE_FINISHED', result.stdout)
            self.assertEqual(self.git('rev-parse', 'HEAD'), self.head)
            self.preserved()

    def test_dirty_base_stops_before_merge(self):
        before = self.git('rev-parse', 'HEAD')
        (self.base / 'unrelated').write_text('keep this\n')
        for tree in TREES:
            result = self.run_recipe(tree, '2')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.git('rev-parse', 'HEAD'), before)
            self.assertEqual((self.base / 'unrelated').read_text(), 'keep this\n')
            self.preserved()

    def test_failed_pull_stops_before_merge(self):
        before = self.git('rev-parse', 'HEAD')
        self.git('remote', 'set-url', 'origin', str(self.root / 'missing remote'))
        for tree in TREES:
            result = self.run_recipe(tree, '2')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('RECIPE_FINISHED', result.stdout)
            self.assertEqual(self.git('rev-parse', 'HEAD'), before)
            self.preserved()

    def test_conflicted_merge_preserves_branch_and_conflict(self):
        (self.base / 'file').write_text('base conflict\n')
        self.git('commit', '--quiet', '-am', 'base conflict')
        self.git('push', '--quiet', 'origin', 'trunk')
        base_head = self.git('rev-parse', 'HEAD')
        for tree in TREES:
            self.git('reset', '--hard', base_head)
            result = self.run_recipe(tree, '2')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('RECIPE_FINISHED', result.stdout)
            self.assertIn('UU file', self.git('status', '--porcelain'))
            self.preserved()

    def test_checkout_preserves_ignored_collision(self):
        self.git('checkout', '--quiet', '--detach')
        exclude = Path(self.git('rev-parse', '--git-path', 'info/exclude', cwd=self.feature))
        exclude.parent.mkdir(parents=True, exist_ok=True)
        exclude.write_text('blocked\n')
        (self.feature / 'blocked').write_text('local ignored work\n')
        for tree in TREES:
            result = self.run_recipe(tree, '2', BASE_WORKTREE=str(self.feature))
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('RECIPE_FINISHED', result.stdout)
            self.assertEqual((self.feature / 'blocked').read_text(), 'local ignored work\n')
            self.assertEqual(self.git('branch', '--show-current', cwd=self.feature), 'topic')
            self.preserved()

    def test_failed_push_stops_before_github_write(self):
        for tree in TREES:
            result = self.run_recipe(tree, '1', prefix=r"""
git() {
  if [[ "${3:-}" == push ]]; then return 23; fi
  command git "$@"
}
gh() { echo UNEXPECTED_GITHUB_CALL; return 99; }
""")
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('UNEXPECTED_GITHUB_CALL', result.stdout)
            self.assertNotIn('RECIPE_FINISHED', result.stdout)
            self.preserved()

    def test_changed_feature_stops_before_push(self):
        (self.feature / 'file').write_text('unreviewed edit\n')
        for tree in TREES:
            result = self.run_recipe(tree, '1', prefix='gh() { echo UNEXPECTED_GITHUB_CALL; }\n')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('UNEXPECTED_GITHUB_CALL', result.stdout)
            self.assertNotIn('RECIPE_FINISHED', result.stdout)
            self.preserved()


suite = unittest.defaultTestLoader.loadTestsFromTestCase({'choices': Choices, 'failures': Failures}[MODE])
raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
