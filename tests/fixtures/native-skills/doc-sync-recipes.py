#!/usr/bin/env python3
"""Exercise doc-sync's actual shell recipes without external writes."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv[1]).resolve()
TREES = tuple(sys.argv[2:]) or ('.claude/skills', 'skills', 'codex-skills')
sys.argv = sys.argv[:1]


def block(tree, heading, index=0):
    text = (ROOT / tree / 'skill-doc-sync/SKILL.md').read_text()
    section = text.split(heading, 1)[1].split('\n## ', 1)[0]
    return re.findall(r'```bash\n(.*?)\n```', section, re.S)[index]


class DocSyncRecipes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.number = 0
        self.env = dict({k: v for k, v in os.environ.items() if not k.startswith('GIT_')},
                        GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_TEMPLATE_DIR=str(self.base / 'empty-template'),
                        GIT_AUTHOR_NAME='Fixture', GIT_COMMITTER_NAME='Fixture',
                        GIT_AUTHOR_EMAIL='fixture@example.invalid', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                        HOME=str(self.base / 'home'))
        (self.base / 'empty-template').mkdir()
        Path(self.env['HOME']).mkdir()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, env=self.env, text=True).strip()

    def repository(self):
        self.number += 1
        self.repo = self.base / ('repo ' + str(self.number))
        self.repo.mkdir()
        self.git('init', '-q', '-b', 'trunk')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'core.hooksPath', str(self.base / 'empty-template'))
        (self.repo / 'README.md').write_text('Original docs\n')
        (self.repo / 'user.md').write_text('User docs\n')
        (self.repo / 'user.txt').write_text('User data\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        self.git('update-ref', 'refs/remotes/origin/trunk', 'HEAD')
        self.git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/trunk')
        self.git('checkout', '-qb', 'topic')
        (self.repo / 'code.py').write_text('pass\n')
        self.git('add', 'code.py')
        self.git('commit', '-qm', 'feature')
        self.head = self.git('rev-parse', 'HEAD')

    def run_block(self, tree, heading, paths=('README.md',), index=0, directory=None, **overrides):
        prefix = 'DOC_SYNC_PATHS=(' + ' '.join(shlex.quote(p) for p in paths) + ')\n'
        env = dict(self.env, DOC_SYNC_ROOT=str(self.repo), DOC_SYNC_BRANCH='topic', DOC_SYNC_HEAD=self.head)
        env.update(overrides)
        return subprocess.run(['bash', '-uo', 'pipefail', '-c', prefix + block(tree, heading, index)],
                              cwd=directory or self.repo, env=env, capture_output=True, text=True, timeout=15)

    def test_commit_only_owned_docs_preserves_user_index_and_worktree(self):
        for tree in TREES:
            with self.subTest(tree=tree):
                self.repository()
                (self.repo / 'user.txt').write_text('Pre-staged user data\n')
                self.git('add', 'user.txt')
                (self.repo / 'user.md').write_text('Unstaged user docs\n')
                staged = self.git('diff', '--cached', '--binary')
                paths = ('README.md', '[draft].md')
                result = self.run_block(tree, '## Step 3:', paths)
                self.assertEqual(result.returncode, 0, result.stderr)
                (self.repo / 'README.md').write_text('Reviewed sync\n')
                (self.repo / '[draft].md').write_text('New documentation\n')
                (self.repo / 'd.md').write_text('Unrelated glob match\n')
                result = self.run_block(tree, '## Step 9:', paths)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(set(self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').splitlines()), set(paths))
                self.assertEqual(self.git('diff', '--cached', '--binary'), staged)
                self.assertEqual((self.repo / 'user.md').read_text(), 'Unstaged user docs\n')
                self.assertEqual((self.repo / 'd.md').read_text(), 'Unrelated glob match\n')

    def test_preexisting_selected_edits_stop_before_work(self):
        for tree in TREES:
            for kind in ('unstaged', 'staged', 'untracked'):
                with self.subTest(tree=tree, kind=kind):
                    self.repository()
                    target = 'new.md' if kind == 'untracked' else 'README.md'
                    (self.repo / target).write_text('Existing user work\n')
                    if kind == 'staged':
                        self.git('add', target)
                    before = self.git('status', '--porcelain')
                    result = self.run_block(tree, '## Step 3:', (target,))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.git('status', '--porcelain'), before)
                    self.assertEqual((self.repo / target).read_text(), 'Existing user work\n')

    def test_no_owned_changes_do_not_commit_unrelated_staged_work(self):
        for tree in TREES:
            self.repository()
            (self.repo / 'user.txt').write_text('User staged data\n')
            self.git('add', 'user.txt')
            before = self.git('diff', '--cached', '--binary')
            result = self.run_block(tree, '## Step 9:')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.git('rev-parse', 'HEAD'), self.head)
            self.assertEqual(self.git('diff', '--cached', '--binary'), before)

    def test_actual_default_branch_and_missing_base(self):
        for tree in TREES:
            self.repository()
            result = self.run_block(tree, '## Step 2:')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('code.py', result.stdout)
            self.git('symbolic-ref', '--delete', 'refs/remotes/origin/HEAD')
            result = self.run_block(tree, '## Step 2:')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('DOC_SYNC_BASE_REF', result.stderr)
            result = self.run_block(tree, '## Step 2:', DOC_SYNC_BASE_REF='trunk')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.git('checkout', '-q', 'trunk')
            (self.repo / 'trunk-change.py').write_text('pass\n')
            self.git('add', 'trunk-change.py')
            self.git('commit', '-qm', 'trunk change')
            self.head = self.git('rev-parse', 'HEAD')
            result = self.run_block(tree, '## Step 2:', DOC_SYNC_BASE_REF='refs/heads/trunk')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('trunk-change.py', result.stdout)

    def test_step3_checks_owned_paths_from_repository_root(self):
        for tree in TREES:
            with self.subTest(tree=tree):
                self.repository()
                (self.repo / 'README.md').write_text('Existing user edit\n')
                before = self.git('status', '--porcelain')
                subdir = self.repo / 'nested'
                subdir.mkdir()
                result = self.run_block(tree, '## Step 3:', ('README.md',), directory=subdir)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.git('status', '--porcelain'), before)
                self.assertEqual((self.repo / 'README.md').read_text(), 'Existing user edit\n')

    def test_new_selected_markdown_is_committed_without_other_doc_edits(self):
        for tree in TREES:
            with self.subTest(tree=tree):
                self.repository()
                path = 'new-only.md'
                (self.repo / path).write_text('New documentation\n')
                result = self.run_block(tree, '## Step 9:', (path,))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.git('show', f'HEAD:{path}'), 'New documentation')
                self.assertEqual(self.git('diff', '--cached', '--binary'), '')

    def test_symlink_escape_is_rejected(self):
        for tree in TREES:
            self.repository()
            (self.repo / 'outside').symlink_to(self.base, target_is_directory=True)
            result = self.run_block(tree, '## Step 3:', ('outside/escape.md',))
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((self.base / 'escape.md').exists())

    def github_fixture(self):
        bindir = self.repo / 'fixture-bin'
        bindir.mkdir()
        cli = bindir / 'gh'
        cli.write_text('#!' + sys.executable + '\n' + """import json,os,sys
from pathlib import Path
args=sys.argv[1:]
assert Path.cwd() == Path(os.environ['GH_EXPECTED_ROOT']).resolve()
if args[:2] == ['pr','list']:
    if os.environ.get('FAIL_READ') == '1': raise SystemExit(9)
    print(Path(os.environ['PR_LIST']).read_text())
elif args[:2] == ['pr','edit']:
    Path(os.environ['POSTED']).write_bytes(Path(args[args.index('--body-file')+1]).read_bytes())
else: raise SystemExit(8)
""")
        cli.chmod(0o755)
        self.prs = self.base / 'prs.json'
        self.posted = self.base / 'posted.md'
        self.summary = self.base / 'summary.md'
        self.summary.write_text('Updated README. Local checks passed; push and hosted CI pending.\n')
        return dict(PATH=str(bindir) + os.pathsep + self.env['PATH'], CLAUDE_PLUGIN_ROOT=str(ROOT),
                    DOC_SYNC_REPO='fixture/repository', DOC_SYNC_SUMMARY_FILE=str(self.summary),
                    PR_LIST=str(self.prs), POSTED=str(self.posted), GH_EXPECTED_ROOT=str(self.repo))

    def test_pr_update_preserves_body_and_replaces_only_managed_section(self):
        for tree in TREES:
            self.repository()
            env = self.github_fixture()
            original = 'Keep the user body: café, `literal` and $HOME.\n'
            self.prs.write_text(json.dumps([{'number': 7, 'body': original}]))
            result = self.run_block(tree, '## Step 9:', index=1, directory=self.base, **env)
            self.assertEqual(result.returncode, 0, result.stderr)
            first = self.posted.read_text()
            self.assertTrue(first.startswith(original))
            self.assertIn(self.summary.read_text().strip(), first)
            self.prs.write_text(json.dumps([{'number': 7, 'body': first}]))
            self.summary.write_text('Second verified doc-sync summary.\n')
            result = self.run_block(tree, '## Step 9:', index=1, directory=self.base, **env)
            self.assertEqual(result.returncode, 0, result.stderr)
            second = self.posted.read_text()
            self.assertTrue(second.startswith(original))
            self.assertEqual(second.count('<!-- octopus-doc-sync:start -->'), 1)
            self.assertNotIn('Updated README.', second)
            self.posted.unlink()

    def test_failed_or_ambiguous_pr_reads_do_not_post(self):
        for tree in TREES:
            self.repository()
            env = self.github_fixture()
            for prs, fail_read in [([], '1'), ([{'number': 7, 'body': ''}, {'number': 8, 'body': ''}], '0'),
                                   ([{'number': 7, 'body': '<!-- octopus-doc-sync:start -->'}], '0')]:
                self.prs.write_text(json.dumps(prs))
                result = self.run_block(tree, '## Step 9:', index=1, FAIL_READ=fail_read, **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.posted.exists())
            self.prs.write_text('[]')
            result = self.run_block(tree, '## Step 9:', index=1, directory=self.base, **env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(self.posted.exists())


if __name__ == '__main__':
    unittest.main()
