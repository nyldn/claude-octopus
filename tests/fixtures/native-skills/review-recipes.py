"""Check review snapshot bytes and shipped posting recipes with inert GitHub writes."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv[1]).resolve()
BASH = os.environ.get('OCTOPUS_TEST_BASH', 'bash')
HELPER = ROOT / 'scripts/helpers/review-snapshot.py'
TREES = ('.claude/skills', 'skills', 'codex-skills')


class ReviewFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='review fixture ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / 'repo with spaces '
        self.repo.mkdir()
        self.scratch = self.root / 'private snapshots'
        self.scratch.mkdir()
        hooks = self.root / 'empty hooks'
        hooks.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        self.env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_TEMPLATE_DIR=str(hooks), GIT_CONFIG_COUNT='1',
                        GIT_CONFIG_KEY_0='core.hooksPath', GIT_CONFIG_VALUE_0=str(hooks),
                        TMPDIR=str(self.scratch))
        self.git('init', '-q', '-b', 'trunk')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, env=self.env, stderr=subprocess.DEVNULL).decode().strip()

    def save(self, name, content, commit=True):
        (self.repo / name).write_bytes(content)
        self.git('add', '--', name)
        if commit:
            self.git('commit', '-qm', 'fixture change')

    def capture(self, *args):
        result = subprocess.run([sys.executable, str(HELPER), '--repo', str(self.repo), *args],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest_path = Path(result.stdout.strip())
        manifest = json.loads(manifest_path.read_text())
        files = {row['path']: row for row in json.loads(Path(manifest['stub_report']).read_text())}
        patch = Path(manifest['input_file']).read_text()
        self.assertEqual(manifest_path.parent.stat().st_mode & 0o777, 0o700)
        for file in manifest_path.parent.iterdir():
            self.assertEqual(file.stat().st_mode & 0o777, 0o600)
        return manifest, files, patch

    def test_staged_bytes_ignore_later_working_copy_edits(self):
        self.save('space name.js', b'const value = 1;\n')
        self.save('space name.js', b'// TODO staged\nconst value = 2;\n', commit=False)
        (self.repo / 'space name.js').write_text('const value = 99;\n')
        before = self.git('status', '--porcelain')
        manifest, files, patch = self.capture()
        self.assertEqual(manifest['scope'], 'staged')
        self.assertEqual(files['space name.js']['todo_count'], 1)
        self.assertIn('TODO staged', patch)
        self.assertNotIn('value = 99', patch)
        self.assertEqual(self.git('status', '--porcelain'), before)

    def test_working_copy_and_zero_counts(self):
        self.save('app.py', b'old = 1\n')
        (self.repo / 'app.py').write_text('# comment only\n')
        manifest, files, patch = self.capture()
        self.assertEqual(manifest['scope'], 'working')
        self.assertEqual(files['app.py']['todo_count'], 0)
        self.assertEqual(files['app.py']['empty_function_count'], 0)
        self.assertEqual(files['app.py']['substantive_lines'], 0)
        self.assertIn('comment only', patch)

    def test_latest_committed_diff_when_index_is_empty(self):
        self.save('app.py', b'old = 1\n')
        self.save('app.py', b'new = 2\n')
        manifest, files, patch = self.capture()
        self.assertEqual(manifest['scope'], 'committed')
        self.assertEqual(manifest['head'], self.git('rev-parse', 'HEAD'))
        self.assertIn('new = 2', patch)
        self.assertEqual(files['app.py']['scan_status'], 'scanned')

    def test_initial_commit_is_reviewable(self):
        self.save('first.py', b'first = True\n')
        manifest, files, patch = self.capture()
        self.assertEqual(manifest['file_count'], 1)
        self.assertIn('first.py', files)
        self.assertIn('+first = True', patch)

    def test_empty_unborn_repository_does_not_fabricate_a_diff(self):
        manifest, files, patch = self.capture()
        self.assertEqual(manifest['scope'], 'empty')
        self.assertEqual(manifest['file_count'], 0)
        self.assertEqual(files, {})
        self.assertEqual(patch, '')

    def test_deleted_and_newline_paths_remain_separate(self):
        self.save('deleted.py', b'old = 1\n')
        self.git('rm', 'deleted.py')
        self.save('new\nname.py', b'new = 2\n', commit=False)
        manifest, files, patch = self.capture()
        self.assertEqual(set(files), {'deleted.py', 'new\nname.py'})
        self.assertEqual(files['deleted.py']['scan_status'], 'deleted')
        self.assertEqual(files['new\nname.py']['scan_status'], 'scanned')

    def test_symlinks_and_binary_sources_are_not_read_as_code(self):
        outside = self.root / 'outside'
        outside.write_text('PRIVATE_UNRELATED_FILE_BYTES')
        (self.repo / 'link.py').symlink_to(outside)
        self.save('binary.py', b'zero\0byte', commit=False)
        self.git('add', 'link.py')
        manifest, files, patch = self.capture()
        self.assertEqual(files['link.py']['scan_status'], 'non-regular')
        self.assertEqual(files['binary.py']['scan_status'], 'binary')
        self.assertNotIn('PRIVATE_UNRELATED_FILE_BYTES', json.dumps(files) + patch)

    def test_explicit_range_uses_the_requested_commit(self):
        self.save('app.py', b'base = 1\n')
        base = self.git('rev-parse', 'HEAD')
        self.save('app.py', b'reviewed = 2\n')
        head = self.git('rev-parse', 'HEAD')
        self.save('app.py', b'// TODO later\n', commit=False)
        manifest, files, patch = self.capture('--base', base, '--head', head)
        self.assertEqual(manifest['base'], base)
        self.assertEqual(manifest['head'], head)
        self.assertNotIn('TODO later', patch)
        self.assertEqual(files['app.py']['todo_count'], 0)

    def test_explicit_working_scope_includes_staged_and_unstaged_changes(self):
        self.save('staged.py', b'old = 1\n')
        self.save('working.py', b'old = 1\n')
        self.save('staged.py', b'staged = 2\n', commit=False)
        (self.repo / 'working.py').write_text('working = 3\n')
        (self.repo / 'untracked.py').write_text('new_file = 4\n')
        manifest, files, patch = self.capture('--scope=working')
        self.assertEqual(manifest['scope'], 'working')
        self.assertEqual(set(files), {'staged.py', 'working.py', 'untracked.py'})
        self.assertIn('new_file = 4', patch)
        self.assertIn('staged = 2', patch)
        self.assertIn('working = 3', patch)

    def test_explicit_empty_staged_scope_does_not_review_last_commit(self):
        self.save('app.py', b'value = 1\n')
        manifest, files, patch = self.capture('--scope=staged')
        self.assertEqual(manifest['scope'], 'staged')
        self.assertEqual(files, {})
        self.assertEqual(patch, '')

    def test_specific_files_capture_current_contents_without_a_diff(self):
        self.save('requested.py', b'requested = 1\n')
        self.save('unrelated.py', b'unrelated = 2\n')
        manifest, files, patch = self.capture('--scope=files', '--path', 'requested.py')
        self.assertEqual(manifest['scope'], 'files')
        self.assertEqual(set(files), {'requested.py'})
        self.assertIn('requested = 1', patch)
        self.assertNotIn('unrelated = 2', patch)

    def test_specific_directory_includes_untracked_files_and_respects_ignores(self):
        (self.repo / 'scope').mkdir()
        self.save('scope/one.py', b'one = 1\n')
        self.save('.gitignore', b'cache/\n')
        (self.repo / 'scope/two.py').write_text('two = 2\n')
        (self.repo / 'scope/cache').mkdir()
        (self.repo / 'scope/cache/ignored.py').write_text('ignored = 3\n')
        self.save('other.py', b'other = 4\n')
        manifest, files, patch = self.capture('--scope=files', '--path', 'scope')
        self.assertEqual(set(files), {'scope/one.py', 'scope/two.py'})
        self.assertIn('two = 2', patch)
        self.assertNotIn('ignored = 3', patch)
        self.assertNotIn('other = 4', patch)

    def test_shipped_skill_passes_the_selected_scope_to_snapshot_capture(self):
        self.save('staged.py', b'old = 1\n')
        self.save('working.py', b'old = 1\n')
        self.save('staged.py', b'staged = 2\n', commit=False)
        (self.repo / 'working.py').write_text('working = 3\n')
        for tree in TREES:
            text = (ROOT / tree / 'skill-staged-review/SKILL.md').read_text()
            section = text.split('### Step 1: Record the diff', 1)[1]
            command = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
            result = subprocess.run([BASH, '-uo', 'pipefail', '-c', command], cwd=self.repo,
                                    env=dict(self.env, OCTO_ROOT=str(ROOT), REVIEW_SCOPE='working'),
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, (tree, result.stderr))
            manifest, _ = json.JSONDecoder().raw_decode(result.stdout)
            self.assertEqual(manifest['scope'], 'working')
            self.assertEqual(manifest['file_count'], 2)

    def test_external_diff_programs_cannot_run(self):
        self.save('app.py', b'old = 1\n')
        self.save('app.py', b'new = 2\n', commit=False)
        marker = self.root / 'external diff ran'
        program = self.root / 'external-diff'
        program.write_text('#!/bin/sh\ntouch "$EXTERNAL_DIFF_MARKER"\nexit 0\n')
        program.chmod(0o755)
        self.env['EXTERNAL_DIFF_MARKER'] = str(marker)
        self.git('config', 'diff.external', str(program))
        manifest, files, patch = self.capture()
        self.assertFalse(marker.exists())
        self.assertIn('new = 2', patch)

    def test_invalid_range_stops_without_snapshot_artifacts(self):
        self.save('app.py', b'value = 1\n')
        result = subprocess.run([sys.executable, str(HELPER), '--repo', str(self.repo), '--base=--not-a-ref'],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_posting_requires_authorization_and_a_completed_report(self):
        plugin = self.root / 'plugin'
        helper = plugin / 'scripts/safe-gh-comment.sh'
        helper.parent.mkdir(parents=True)
        helper.write_text('#!/bin/bash\nprintf "%s\\0" "$@" > "$ARGS_FILE"\ncat > "$BODY_FILE"\n')
        helper.chmod(0o755)
        review = self.root / 'recorded review'
        review.mkdir()
        args_file, body_file = self.root / 'args', self.root / 'body'
        for tree in TREES:
            text = (ROOT / tree / 'skill-staged-review/SKILL.md').read_text()
            section = text.split('## Post results to a PR', 1)[1]
            command = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
            for decision, report, success in [('0', 'completed report', True), ('1', None, False),
                                               ('1', ' \n\t', False), ('1', 'Actual findings for snapshot abc', True)]:
                report_file = review / 'combined-report.md'
                if report_file.exists():
                    report_file.unlink()
                if report is not None:
                    report_file.write_text(report)
                if args_file.exists():
                    args_file.unlink()
                env = dict(self.env, OCTO_ROOT=str(plugin), REVIEW_DIR=str(review),
                           POST_TO_PR=decision, REPO_SLUG='fixture/repository', PR_NUM='42',
                           ARGS_FILE=str(args_file), BODY_FILE=str(body_file), COMBINED_REPORT='STALE_AMBIENT_REPORT')
                result = subprocess.run([BASH, '-uo', 'pipefail', '-c', command], cwd=self.repo,
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, success, (tree, decision, report, result.stderr))
                if decision == '1' and success:
                    self.assertEqual(args_file.read_bytes().split(b'\0')[:-1],
                                     [b'--repo', b'fixture/repository', b'pr-comment', b'42', b'-'])
                    self.assertIn(report, body_file.read_text())
                    self.assertNotIn('STALE_AMBIENT_REPORT', body_file.read_text())
                else:
                    self.assertFalse(args_file.exists(), (tree, decision, report))


raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(
    unittest.defaultTestLoader.loadTestsFromTestCase(ReviewFixture)).wasSuccessful())
