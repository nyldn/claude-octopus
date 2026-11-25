#!/usr/bin/env bash
# Exercise the quick-task commit and summary recipes in disposable repositories.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Quick-task commit isolation and summary"
test_case "quick commits preserve unrelated work and summaries identify the task commit"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv[1])
entries = [root / '.claude/skills/skill-quick/SKILL.md',
           root / 'skills/octopus-quick/SKILL.md']
codex = root / 'codex-skills/octopus-quick/SKILL.md'
if codex.exists():
    entries.append(codex)


class QuickCommit(unittest.TestCase):
    def test_recipes(self):
        for entry in entries:
            text = entry.read_text()
            primary = text.split('### Step 3: Create Atomic Commit', 1)[1]
            primary = re.search(r'```bash\n(.*?)\n```', primary, re.S)[1]
            example = text.split('## Complete Example', 1)[1]
            example = next(block for block in re.findall(r'```bash\n(.*?)\n\s*```', example, re.S)
                           if re.search(r'git(?: --literal-pathspecs)? commit', block))
            for label, recipe, filename in [('primary', primary, 'task file.txt'),
                                             ('brackets', primary, 'file[1].txt'),
                                             ('pathspec magic', primary, ':(glob)*.txt'),
                                             ('example', example, 'README.md')]:
                for scenario in ('modified', 'new', 'deleted', 'rejected'):
                    with self.subTest(entry=str(entry), recipe=label, scenario=scenario):
                        self.check_recipe(recipe, filename, scenario)

    def check_recipe(self, recipe, filename, scenario):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            repo = Path(temporary)
            env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                       GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                       GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')

            def git(*args):
                return subprocess.check_output(['git', *args], cwd=repo, env=env,
                                               stderr=subprocess.DEVNULL, text=True).strip()

            git('init', '-q', '-b', 'main')
            task = repo / filename
            other = repo / 'file1.txt'
            other.write_text('original\n')
            if scenario != 'new':
                task.write_text('original\n')
            git('add', '.')
            git('commit', '-qm', 'base')
            before = git('rev-parse', 'HEAD')
            other.write_text('user staged bytes\n')
            git('add', '--', 'file1.txt')
            staged = git('show', ':file1.txt')
            other.write_text('user unstaged bytes\n')
            if scenario == 'deleted':
                task.unlink()
            else:
                task.write_text('quick task\n')
            if scenario == 'rejected':
                hook = repo / '.git/hooks/pre-commit'
                hook.write_text('#!/bin/sh\nexit 1\n')
                hook.chmod(0o755)
            recipe = recipe.replace('"path/to/task-file"', shlex.quote(filename))
            result = subprocess.run(['bash', '-c', recipe + '\nprintf done > reached-state'],
                                    cwd=repo, env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(git('show', ':file1.txt'), staged)
            self.assertEqual(other.read_text(), 'user unstaged bytes\n')
            if scenario == 'rejected':
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(git('rev-parse', 'HEAD'), before)
                self.assertFalse((repo / 'reached-state').exists())
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD'), filename)
                self.assertTrue((repo / 'reached-state').exists())
                if 'git rev-parse --verify HEAD' in recipe:
                    self.assertEqual(result.stdout.splitlines()[-1], git('rev-parse', 'HEAD'))

    def test_summary(self):
        request = "Update `read me` without expanding $(false) or $HOME."
        for entry in entries:
            section = entry.read_text().split('### Step 5: Generate Summary', 1)[1]
            recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
            for scenario in ('root commit', 'head advanced', 'missing commit'):
                with self.subTest(entry=str(entry), scenario=scenario):
                    self.check_summary(recipe, request, scenario)

    def check_summary(self, recipe, request, scenario):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            repo = Path(temporary)
            env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                       GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                       GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
            env.pop('TASK_DESCRIPTION', None)

            def git(*args):
                return subprocess.check_output(['git', *args], cwd=repo, env=env,
                                               text=True).strip()

            git('init', '-q', '-b', 'main')
            (repo / 'quick file.txt').write_text('Quick change\n')
            git('add', 'quick file.txt')
            git('commit', '-qm', 'quick: add task file')
            commit = git('rev-parse', 'HEAD')
            if scenario == 'head advanced':
                (repo / 'unrelated.txt').write_text('Later change\n')
                git('add', 'unrelated.txt')
                git('commit', '-qm', 'later change')
            if scenario == 'missing commit':
                commit = '0' * 40
            recipe = recipe.replace('"<quick-commit-sha>"', shlex.quote(commit))
            recipe = recipe.replace('"user task description"', shlex.quote(request))
            result = subprocess.run(['bash', '-c', recipe], cwd=repo, env=env,
                                    capture_output=True, text=True, timeout=10)
            summaries = list(repo.glob('.claude-octopus/quick/*-summary.md'))
            if scenario == 'missing commit':
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(summaries)
                self.assertNotIn('Summary saved', result.stdout)
                return
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(summaries), 1)
            summary = summaries[0].read_text()
            self.assertIn('# Quick Task: quick: add task file', summary)
            self.assertIn(f'## Task Description\n{request}\n', summary)
            self.assertIn('quick file.txt | 1 +', summary)
            self.assertIn('## Files Modified\nquick file.txt\n', summary)
            self.assertIn(f'## Commit\n{commit}\n', summary)
            self.assertNotIn('unrelated.txt', summary)
            self.assertEqual(result.stderr, '')


unittest.main(argv=['quick-commit'], verbosity=1)
PY
then test_pass; else test_fail "quick-task commit or summary evidence did not match the task"; fi
test_summary
