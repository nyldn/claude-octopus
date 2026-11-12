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
        home = self.root / 'home'
        home.mkdir()
        self.plugin = self.root / 'plugin'
        self.helper = self.plugin / 'scripts/safe-gh-comment.sh'
        self.helper.parent.mkdir(parents=True)
        self.helper.write_text('#!/bin/bash\nprintf "%s\\0" "$@" > "$ARGS_FILE"\ncat > "$BODY_FILE"\n')
        self.helper.chmod(0o755)
        self.env.update(HOME=str(home), CLAUDE_PLUGIN_ROOT=str(self.plugin), CODEX_PLUGIN_ROOT='',
                        ARGS_FILE=str(self.root / 'args'), BODY_FILE=str(self.root / 'body'),
                        PR_TITLE='Fix fixture', CHANGE_SUMMARY='Keep the feature.',
                        CHANGE_REASON='Verify the recipe.', VALIDATION_SUMMARY='Project checks passed.')
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
        for path in (self.marker, self.root / 'args', self.root / 'body'):
            path.unlink(missing_ok=True)
        remote_fixture = """git() {
  if [[ "${3:-}" == remote && "${4:-}" == get-url ]]; then
    printf '%s\\n' 'https://github.com/fixture/repository.git'
  else
    command git "$@"
  fi
}
""" if str(option) == '1' and 'git()' not in prefix else ''
        return subprocess.run([BASH, '-uo', 'pipefail', '-c', self.prefix + remote_fixture + prefix +
                               recipe(tree, option) + '\nprintf "FEATURE_SWITCHED_TO_BASE=%s\\n" "${FEATURE_SWITCHED_TO_BASE:-false}"\nprintf "RECIPE_FINISHED\\n"'],
                              cwd=self.feature, env=dict(self.env, **env), capture_output=True, text=True)

    def preserved(self):
        self.assertEqual(self.git('rev-parse', 'topic'), self.head)
        self.assertTrue(self.feature.is_dir())


class Choices(Fixture):
    def test_authorized_staged_deletion_commits_without_unrelated_index_work(self):
        for tree in TREES:
            with self.subTest(tree=tree):
                text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
                section = text.split('### Prepare an explicitly authorized commit', 1)[1].split('### Step 1:', 1)[0]
                block = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
                selected = self.feature / '[delete me].txt'
                selected.write_text('authorized deletion\n')
                self.git('--literal-pathspecs', 'add', '--', selected.name, cwd=self.feature)
                self.git('commit', '-qm', 'before deletion', cwd=self.feature)
                self.git('--literal-pathspecs', 'rm', '--', selected.name, cwd=self.feature)
                unrelated = self.feature / 'unrelated.txt'
                unrelated.write_text('preserve staged work\n')
                self.git('add', unrelated.name, cwd=self.feature)
                result = subprocess.run([BASH, '-u', '-c',
                    'COMMIT_PATHS=("[delete me].txt"); COMMIT_MESSAGE="Authorized deletion"\n' + block],
                    cwd=self.feature, env=self.env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.git('diff-tree', '--no-commit-id', '--name-status', '-r', 'HEAD', cwd=self.feature),
                                 'D\t[delete me].txt')
                self.assertEqual(self.git('diff', '--cached', '--name-only', cwd=self.feature), unrelated.name)
                self.git('reset', '--hard', self.head, cwd=self.feature)
                unrelated.unlink(missing_ok=True)

    def test_authorized_commit_excludes_unrelated_staged_paths(self):
        for tree in TREES:
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            section = text.split('### Prepare an explicitly authorized commit', 1)[1].split('### Step 1:', 1)[0]
            block = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
            (self.feature / 'selected file.txt').write_text('authorized change')
            (self.feature / 'unrelated.txt').write_text('preserve staged work')
            self.git('add', 'unrelated.txt', cwd=self.feature)
            result = subprocess.run([BASH, '-u', '-c',
                                     'COMMIT_PATHS=("selected file.txt"); COMMIT_MESSAGE="Scoped change"\n' + block],
                                    cwd=self.feature, env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD', cwd=self.feature),
                             'selected file.txt')
            self.assertEqual(self.git('diff', '--cached', '--name-only', cwd=self.feature), 'unrelated.txt')
            self.git('reset', '--hard', self.head, cwd=self.feature)
            (self.feature / 'unrelated.txt').unlink(missing_ok=True)

    def test_pr_target_comes_from_single_github_push_url(self):
        for tree in TREES:
            block = recipe(tree, '1')
            block = 'if ! PUSH_URLS=' + block.split('if ! PUSH_URLS=', 1)[1].split('PR_TITLE=', 1)[0]
            for url, expected in [('https://github.com/owner/repo.git', 'owner/repo'),
                                  ('git@github.com:owner/repo.git', 'owner/repo'),
                                  ('ssh://git@github.com/owner/repo.git', 'owner/repo'),
                                  ('https://github.com/owner/repo', 'owner/repo'),
                                  ('https://elsewhere.invalid/owner/repo', None),
                                  ('https://github.com/owner/repo.git\nhttps://github.com/other/repo.git', None)]:
                result = subprocess.run([BASH, '-u', '-c',
                    'git() { printf "%s\\n" "$PUSH_URL_TEST"; }; gh() { exit 99; };\n' + block +
                    '\nprintf "%s" "$REPO_SLUG"'], env=dict(self.env, PUSH_URL_TEST=url),
                    text=True, capture_output=True)
                if expected is None:
                    self.assertNotEqual(result.returncode, 0, (tree, url))
                else:
                    self.assertEqual(result.returncode, 0, (tree, url, result.stderr))
                    self.assertEqual(result.stdout, expected)

    def test_menu_and_cleanup_agree(self):
        for tree in TREES:
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            menu = dict(re.findall(r'^(\d+)\. \*\*([^*]+)\*\*', text, re.M))
            self.assertEqual(menu, {'1': 'Create PR', '2': 'Merge locally', '3': 'Keep as-is', '4': 'Discard', '5': 'Push only'})
            rows = dict(re.findall(r'^\| (\d+)\. ([^|]+)\|', text, re.M))
            self.assertEqual({k: v.strip() for k, v in rows.items()}, menu)
            self.assertEqual(re.findall(r'^### Step (\d+):', text, re.M), list('1234567'))
            cleanup = text.split('### Step 7: Cleanup', 1)[1].split('## Quick Reference', 1)[0]
            self.assertIn('For Options 2, 4:', cleanup)
            self.assertIn('For Options 1, 3, 5:', cleanup)
            self.assertIn('FEATURE_SWITCHED_TO_BASE', cleanup)
            self.assertIn('primary checkout must remain', cleanup)
            self.assertIn('no useful ignored files', cleanup)

    def test_non_main_base_resolved_before_review(self):
        for tree in TREES:
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            setup_section = text.split('### Step 1:', 1)[1].split('### Step 2:', 1)[0]
            setup = re.search(r'```bash\n(.*?)\n```', setup_section, re.S)[1]
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
        for tree in TREES:
            args = self.root / 'args'
            body = self.root / 'body'
            result = self.run_recipe(tree, '1',
                                     prefix='gh() { printf "fixture/repository\\n"; }\n',
                                     CLAUDE_PLUGIN_ROOT=str(self.plugin), ARGS_FILE=str(args), BODY_FILE=str(body),
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

    def test_push_only_needs_no_pr_helper_and_creates_no_pr(self):
        for tree in TREES:
            self.git('update-ref', '-d', 'refs/heads/topic', cwd=self.remote)
            result = self.run_recipe(tree, '5', prefix='gh() { echo UNEXPECTED_GITHUB_CALL; return 99; }\n',
                                     CLAUDE_PLUGIN_ROOT=str(self.root / 'missing plugin'))
            self.assertEqual(result.returncode, 0, (tree, result.stderr))
            self.assertNotIn('UNEXPECTED_GITHUB_CALL', result.stdout)
            self.assertFalse((self.root / 'args').exists())
            self.assertEqual(self.git('rev-parse', 'refs/heads/topic', cwd=self.remote), self.head)
            self.preserved()

    def test_codex_root_resolves_the_pr_helper_before_push(self):
        for tree in TREES:
            result = self.run_recipe(tree, '1', prefix='gh() { echo fixture/repository; }\n',
                                     CLAUDE_PLUGIN_ROOT='', CODEX_PLUGIN_ROOT=str(self.plugin))
            self.assertEqual(result.returncode, 0, (tree, result.stderr))
            self.assertTrue((self.root / 'args').is_file())

    def test_local_merge_without_origin_or_remote_base(self):
        before = self.git('rev-parse', 'HEAD')
        self.git('update-ref', '-d', 'refs/heads/trunk', cwd=self.remote)
        for origin in (True, False):
            if not origin:
                self.git('remote', 'remove', 'origin')
            for tree in TREES:
                self.git('reset', '--hard', before)
                result = self.run_recipe(tree, '2')
                self.assertEqual(result.returncode, 0, (origin, tree, result.stderr))
                self.assertEqual(self.git('rev-parse', 'HEAD'), self.head)
                self.assertTrue(self.marker.exists())
                self.preserved()

    def test_switching_the_feature_checkout_records_its_new_base_role(self):
        before = self.git('rev-parse', 'HEAD')
        self.git('checkout', '--quiet', '--detach')
        for tree in TREES:
            self.git('checkout', '--quiet', 'topic', cwd=self.feature)
            self.git('branch', '-f', 'trunk', before)
            result = self.run_recipe(tree, '2', BASE_WORKTREE=str(self.feature))
            self.assertEqual(result.returncode, 0, (tree, result.stderr))
            self.assertIn('FEATURE_SWITCHED_TO_BASE=true', result.stdout)
            self.assertEqual(self.git('branch', '--show-current', cwd=self.feature), 'trunk')
            self.assertEqual(Path(self.marker.read_text()), self.feature)
            self.preserved()


class Failures(Fixture):
    def test_missing_default_base_stops(self):
        self.git('symbolic-ref', '--delete', 'refs/remotes/origin/HEAD')
        for tree in TREES:
            text = (ROOT / tree / 'skill-finish-branch/SKILL.md').read_text()
            setup_section = text.split('### Step 1:', 1)[1].split('### Step 2:', 1)[0]
            setup = re.search(r'```bash\n(.*?)\n```', setup_section, re.S)[1]
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

    def test_conflicted_merge_preserves_branch_and_restores_the_base(self):
        (self.base / 'file').write_text('base conflict\n')
        self.git('commit', '--quiet', '-am', 'base conflict')
        self.git('push', '--quiet', 'origin', 'trunk')
        base_head = self.git('rev-parse', 'HEAD')
        for tree in TREES:
            self.git('reset', '--hard', base_head)
            result = self.run_recipe(tree, '2')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('RECIPE_FINISHED', result.stdout)
            self.assertEqual(self.git('status', '--porcelain'), '')
            self.assertEqual(self.git('rev-parse', 'HEAD'), base_head)
            self.assertEqual(self.git('rev-parse', '--verify', '--quiet', 'MERGE_HEAD', check=False), '')
            self.preserved()

    def test_missing_pr_helper_stops_before_push(self):
        self.helper.chmod(0o644)
        for plugin in (self.root / 'missing plugin', self.plugin):
            for tree in TREES:
                result = self.run_recipe(tree, '1', prefix='gh() { echo UNEXPECTED_GITHUB_CALL; }\n',
                                         CLAUDE_PLUGIN_ROOT=str(plugin))
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('UNEXPECTED_GITHUB_CALL', result.stdout)
                self.assertEqual(self.git('show-ref', '--verify', 'refs/heads/topic', cwd=self.remote, check=False), '')
                self.preserved()

    def test_missing_pr_metadata_stops_before_push(self):
        for tree in TREES:
            result = self.run_recipe(tree, '1', prefix='gh() { echo fixture/repository; }\n', PR_TITLE='')
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((self.root / 'args').exists())
            self.assertEqual(self.git('show-ref', '--verify', 'refs/heads/topic', cwd=self.remote, check=False), '')
            self.preserved()

    def test_existing_merge_state_is_preserved(self):
        before = self.git('rev-parse', 'HEAD')
        self.git('merge', '--no-ff', '--no-commit', self.head)
        self.git('read-tree', '--reset', '-u', 'HEAD')
        self.assertEqual(self.git('status', '--porcelain'), '')
        pending = self.git('rev-parse', 'MERGE_HEAD')
        for tree in TREES:
            result = self.run_recipe(tree, '2')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.git('rev-parse', 'MERGE_HEAD'), pending)
            self.assertEqual(self.git('rev-parse', 'HEAD'), before)
            self.preserved()

    def test_feature_merge_preserves_ignored_collisions(self):
        before = self.git('rev-parse', 'HEAD')
        exclude = self.base / self.git('rev-parse', '--git-path', 'info/exclude')
        exclude.parent.mkdir(parents=True, exist_ok=True)
        exclude.write_text('ignored-result\n')
        (self.feature / 'ignored-result').write_text('reviewed feature\n')
        self.git('add', '-f', 'ignored-result', cwd=self.feature)
        self.git('commit', '--quiet', '-m', 'tracked feature result', cwd=self.feature)
        self.head = self.git('rev-parse', 'HEAD', cwd=self.feature)
        self.env['REVIEWED_HEAD'] = self.head
        (self.base / 'ignored-result').write_text('useful local file\n')
        for tree in TREES:
            result = self.run_recipe(tree, '2')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.git('rev-parse', 'HEAD'), before)
            self.assertEqual((self.base / 'ignored-result').read_text(), 'useful local file\n')
            self.preserved()

    def test_remote_fast_forward_preserves_ignored_collisions(self):
        before = self.git('rev-parse', 'HEAD')
        writer = self.root / 'remote writer'
        self.git('worktree', 'add', '--quiet', '-b', 'remote-update', str(writer))
        (writer / 'remote-result').write_text('remote work\n')
        self.git('add', 'remote-result', cwd=writer)
        self.git('commit', '--quiet', '-m', 'remote addition', cwd=writer)
        self.git('push', '--quiet', 'origin', 'HEAD:trunk', cwd=writer)
        exclude = self.base / self.git('rev-parse', '--git-path', 'info/exclude')
        exclude.parent.mkdir(parents=True, exist_ok=True)
        exclude.write_text('remote-result\n')
        (self.base / 'remote-result').write_text('useful local file\n')
        for tree in TREES:
            result = self.run_recipe(tree, '2')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.git('rev-parse', 'HEAD'), before)
            self.assertEqual((self.base / 'remote-result').read_text(), 'useful local file\n')
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
            trace = self.root / 'push-attempt'
            trace.unlink(missing_ok=True)
            result = self.run_recipe(tree, '1', prefix=r"""
git() {
  if [[ "${3:-}" == remote && "${4:-}" == get-url ]]; then printf '%s\n' 'https://github.com/fixture/repository.git'; return; fi
  if [[ "${3:-}" == push ]]; then printf called > "$PUSH_TRACE"; return 23; fi
  command git "$@"
}
gh() { echo fixture/repository; }
""", PUSH_TRACE=str(trace))
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(trace.exists())
            self.assertFalse((self.root / 'args').exists())
            self.assertNotIn('RECIPE_FINISHED', result.stdout)
            self.preserved()

    def test_changed_feature_stops_before_push(self):
        (self.feature / 'file').write_text('unreviewed edit\n')
        for tree in TREES:
            for option in ('1', '5'):
                result = self.run_recipe(tree, option, prefix='gh() { echo UNEXPECTED_GITHUB_CALL; }\n')
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('UNEXPECTED_GITHUB_CALL', result.stdout)
                self.assertNotIn('RECIPE_FINISHED', result.stdout)
                if option == '5':
                    self.assertIn('uncommitted changes', result.stderr)
                    self.assertIn('Commit the intended changes', result.stderr)
                self.assertEqual(self.git('rev-parse', 'HEAD', cwd=self.feature), self.head)
                self.preserved()


suite = unittest.defaultTestLoader.loadTestsFromTestCase({'choices': Choices, 'failures': Failures}[MODE])
raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
