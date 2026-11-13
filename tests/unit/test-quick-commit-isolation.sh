#!/usr/bin/env bash
# Execute both quick-task commit recipes with an unrelated staged change.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Quick-task commit isolation"
test_case "quick commits preserve unrelated work and stop on commit failure"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import os
from pathlib import Path
import re
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
                           if 'git commit' in block)
            for label, recipe, filename in [('primary', primary, 'task file.txt'),
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
            other = repo / 'unrelated.txt'
            other.write_text('original\n')
            if scenario != 'new':
                task.write_text('original\n')
            git('add', '.')
            git('commit', '-qm', 'base')
            before = git('rev-parse', 'HEAD')
            other.write_text('user staged bytes\n')
            git('add', '--', 'unrelated.txt')
            staged = git('show', ':unrelated.txt')
            other.write_text('user unstaged bytes\n')
            if scenario == 'deleted':
                task.unlink()
            else:
                task.write_text('quick task\n')
            if scenario == 'rejected':
                hook = repo / '.git/hooks/pre-commit'
                hook.write_text('#!/bin/sh\nexit 1\n')
                hook.chmod(0o755)
            recipe = recipe.replace('git add [changed-files]', 'git add -- "task file.txt"')
            recipe = recipe.replace('"path/to/task-file"', '"task file.txt"')
            result = subprocess.run(['bash', '-c', recipe + '\nprintf done > reached-state'],
                                    cwd=repo, env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(git('show', ':unrelated.txt'), staged)
            self.assertEqual(other.read_text(), 'user unstaged bytes\n')
            if scenario == 'rejected':
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(git('rev-parse', 'HEAD'), before)
                self.assertFalse((repo / 'reached-state').exists())
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD'), filename)
                self.assertTrue((repo / 'reached-state').exists())


unittest.main(argv=['quick-commit'], verbosity=1)
PY
then test_pass; else test_fail "quick-task commit included unrelated work or continued after failure"; fi
test_summary
