"""Execute review and planning guards against disposable local data."""
from decimal import Decimal
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv[1]).resolve()
TREES = ('.claude/skills', 'skills', 'codex-skills')


def blocks(tree, name):
    text = (ROOT / tree / name / 'SKILL.md').read_text()
    return re.findall(r'```bash\n(.*?)\n```', text, re.S)


class Guards(unittest.TestCase):
    def test_review_path_collection_preserves_names_and_rejects_invalid_range(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                       GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                       GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
            def git(*args):
                return subprocess.run(['git', *args], cwd=project, env=env, check=True,
                                      capture_output=True)
            git('init', '-q')
            git('-c', 'core.hooksPath=/dev/null', 'commit', '--allow-empty', '-qm', 'baseline')
            names = ['my component.tsx', 'line\nbreak.py', '-flag.ts']
            for name in names + ['notes.md']:
                (project / name).write_text('TODO: implement this function\n')
            git('add', '.')
            git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'candidate')
            for tree in TREES:
                block = next(b for b in blocks(tree, 'skill-code-review') if 'source_files=' in b)
                for rev in ('HEAD~1..HEAD', 'missing-revision'):
                    result = subprocess.run(['bash', '-u', '-c', block + '\nprintf "%s\\0" "${source_files[@]}"'],
                                            cwd=project, env=dict(env, COMMIT_RANGE=rev), capture_output=True)
                    if rev == 'missing-revision':
                        self.assertNotEqual(result.returncode, 0, tree)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(set(result.stdout.rstrip(b'\0').decode().split('\0')), set(names))

    def test_plan_directory_failure_stops_before_any_intent_write(self):
        with tempfile.TemporaryDirectory() as directory:
            plugin = Path(directory)
            helper = plugin / 'scripts/plan-storage.sh'
            helper.parent.mkdir()
            env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(plugin))
            for tree in TREES:
                block = next(b for b in blocks(tree, 'skill-intent-contract') if 'PLAN_STORAGE=' in b)
                guard = block.split('cat >', 1)[0] + '\nprintf reached-write'
                for answer in ('failure', 'empty', 'valid'):
                    helper.write_text('#!/bin/bash\n' + ('exit 1\n' if answer == 'failure' else
                        'printf "%s\\n" ' + repr(str(plugin) if answer == 'valid' else '') + '\n'))
                    helper.chmod(0o755)
                    result = subprocess.run(['bash', '-u', '-c', guard], env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, answer == 'valid', (tree, answer, result.stderr))
                    self.assertEqual('reached-write' in result.stdout, answer == 'valid')

    def test_quick_commit_failure_stops_and_summary_reads_literal_request(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            request = project / 'request.md'
            raw = 'Keep $HOME and $(touch SHOULD_NOT_RUN) as data, with "quotes".\n'
            request.write_text(raw)
            for tree in TREES:
                text = (ROOT / tree / 'octopus-quick/SKILL.md').read_text() if tree != '.claude/skills' else (ROOT / tree / 'skill-quick/SKILL.md').read_text()
                commit = re.search(r'```bash\n(.*?)\n```', text.split('### Step 3:', 1)[1], re.S)[1]
                result = subprocess.run(['bash', '-c',
                    'git() { if [[ "$1" == commit ]]; then return 37; fi; };\n' + commit + '\nprintf continued'],
                    cwd=project, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, tree)
                self.assertNotIn('continued', result.stdout)
                summary = re.search(r'```bash\n(.*?)\n```', text.split('### Step 5:', 1)[1], re.S)[1]
                result = subprocess.run(['bash', '-u', '-c', 'git() { printf fixture; };\n' + summary],
                    cwd=project, env=dict(os.environ, QUICK_REQUEST_FILE=str(request)), capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                files = list((project / '.claude-octopus/quick').glob('*-summary.md'))
                self.assertEqual(len(files), 1)
                self.assertIn(raw.rstrip(), files[0].read_text())
                self.assertFalse((project / 'SHOULD_NOT_RUN').exists())
                files[0].unlink()

    def test_prior_context_reaches_host_only_after_local_artifact_check(self):
        with tempfile.TemporaryDirectory() as directory:
            plugin = Path(directory)
            (plugin / 'scripts/helpers').mkdir(parents=True)
            (plugin / 'scripts/helpers/artifact-safety.py').write_bytes((ROOT / 'scripts/helpers/artifact-safety.py').read_bytes())
            manager = plugin / 'scripts/state-manager.sh'
            manager.write_text('#!/bin/bash\ncase "$1" in get_decisions) printf "[]";; read_state) printf "%s" "$SAVED_STATE";; esac\n')
            manager.chmod(0o755)
            for tree in ('skills', 'codex-skills'):
                text = (ROOT / tree / 'flow-discover/references/prepare.md').read_text()
                section = text.split('### STEP 3:', 1)[1].split('### STEP 3.5:', 1)[0]
                block = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
                for secret in (False, True):
                    state = '{"context":{"vision":"PRESERVE_CONTEXT_SENTINEL"}}' if not secret else '{"context":{"API_KEY":"private-value-not-for-capture"}}'
                    result = subprocess.run(['bash', '-u', '-c', block],
                        env=dict(os.environ, OCTO_ROOT=str(plugin), SAVED_STATE=state), capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, not secret, (tree, result.stderr))
                    self.assertEqual('PRESERVE_CONTEXT_SENTINEL' in result.stdout, not secret)
                    self.assertNotIn('private-value-not-for-capture', result.stdout + result.stderr)

    def test_projection_never_falls_below_spend(self):
        for tree in TREES:
            block = next(b for b in blocks(tree, 'skill-cost-projections') if 'remaining_steps=' in b)
            for completed, expected in ((2, Decimal('4')), (4, Decimal('4')), (5, Decimal('5'))):
                result = subprocess.run(['bash', '-u', '-c',
                    'total_steps=4; completed_count=$COMPLETED; avg_cost=1; total_spent=$COMPLETED\n' + block +
                    '\nprintf "%s" "$projected_total"'], env=dict(os.environ, COMPLETED=str(completed)),
                    capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(Decimal(result.stdout), expected, tree)


suite = unittest.defaultTestLoader.loadTestsFromTestCase(Guards)
raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
