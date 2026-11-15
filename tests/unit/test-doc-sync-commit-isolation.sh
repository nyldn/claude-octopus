#!/usr/bin/env bash
# Execute the documented commit recipe against disposable staged/unstaged work.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Documentation sync commit isolation"
test_case "doc-sync commits only selected paths and stops on Git failure"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv[1])
entries = [root / '.claude/skills/skill-doc-sync/SKILL.md',
           root / 'skills/skill-doc-sync/SKILL.md']
codex = root / 'codex-skills/skill-doc-sync/SKILL.md'
if codex.exists():
    entries.append(codex)


class DocSyncCommit(unittest.TestCase):
    def test_recipes(self):
        for entry in entries:
            section = entry.read_text().split('## Step 9: Commit Doc Changes', 1)[1]
            recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
            for filename in ('docs/task file.md', 'file[1].md', ':(glob)*.md'):
                for scenario in ('modified', 'new', 'deleted', 'rejected', 'unchanged', 'missing'):
                    with self.subTest(entry=str(entry), file=filename, scenario=scenario):
                        self.check_recipe(recipe, filename, scenario)

    def check_recipe(self, recipe, filename, scenario):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            repo = Path(temporary)
            env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
            env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                       GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                       GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')

            def git(*args):
                return subprocess.check_output(['git', *args], cwd=repo, env=env,
                                               stderr=subprocess.DEVNULL, text=True).strip()

            git('init', '-q', '-b', 'main')
            task = repo / filename
            task.parent.mkdir(parents=True, exist_ok=True)
            for name in ('README.md', 'unrelated.txt'):
                (repo / name).write_text('original\n')
            if scenario not in ('new', 'missing'):
                task.write_text('original\n')
            git('add', '.')
            git('commit', '-qm', 'base')
            before = git('rev-parse', 'HEAD')
            for name in ('README.md', 'unrelated.txt'):
                (repo / name).write_text('user staged bytes\n')
                git('add', '--', name)
                (repo / name).write_text('user unstaged bytes\n')
            original_staged = {name: git('show', ':' + name) for name in ('README.md', 'unrelated.txt')}
            if scenario == 'deleted':
                task.unlink()
            elif scenario not in ('unchanged', 'missing'):
                task.write_text('doc-sync bytes\n')
            if scenario == 'rejected':
                hook = repo / '.git/hooks/pre-commit'
                hook.write_text('#!/bin/sh\nexit 1\n')
                hook.chmod(0o755)
            recipe = recipe.replace('"path/to/doc.md"', shlex.quote(filename))
            result = subprocess.run(['bash', '-c', recipe + '\nprintf done > reached-state'],
                                    cwd=repo, env=env, capture_output=True, text=True, timeout=10)
            for name, staged in original_staged.items():
                self.assertEqual(git('show', ':' + name), staged, result.stdout + result.stderr)
                self.assertEqual((repo / name).read_text(), 'user unstaged bytes\n')
            if scenario in ('rejected', 'missing'):
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(git('rev-parse', 'HEAD'), before)
                self.assertFalse((repo / 'reached-state').exists())
            elif scenario == 'unchanged':
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(git('rev-parse', 'HEAD'), before)
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD'), filename)
                self.assertTrue((repo / 'reached-state').exists())


unittest.main(argv=['doc-sync-commit'], verbosity=1)
PY
then test_pass; else test_fail "doc-sync changed unrelated work or continued after failure"; fi
test_summary
