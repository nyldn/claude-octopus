#!/usr/bin/env python3
"""Execute shipping recipes in disposable projects, without provider calls."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve()
TREE = sys.argv.pop(1) if len(sys.argv) > 1 else '.claude/skills'
SOURCE = (ROOT / TREE / 'skill-ship/SKILL.md').read_text()


def block_after(heading):
    return re.search(r'```bash\n(.*?)\n```', SOURCE.split(heading, 1)[1], re.S)[1]


def block_containing(fragment):
    return next(m[1] for m in re.finditer(r'```bash\n(.*?)\n```', SOURCE, re.S) if fragment in m[1])


class ShipRecipes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / 'project'
        self.project.mkdir()
        self.plugin = self.base / 'plugin'
        (self.plugin / 'scripts').mkdir(parents=True)
        (self.plugin / 'scripts/octo-state.sh').symlink_to(ROOT / 'scripts/octo-state.sh')
        (self.plugin / 'scripts/orchestrate.sh').symlink_to(ROOT / 'scripts/orchestrate.sh')
        (self.plugin / 'scripts/helpers').symlink_to(ROOT / 'scripts/helpers', target_is_directory=True)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('GIT_', 'CLAUDE_', 'CODEX_', 'DROID_')) and k != 'OCTO_ROOT'}
        self.env.update(CLAUDE_PLUGIN_ROOT=str(self.plugin), STATE_TOOL=str(self.plugin / 'scripts/octo-state.sh'),
                        GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                        GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                        GIT_TEMPLATE_DIR=str(self.base / 'empty-template'), HOME=str(self.base / 'home'))
        Path(self.env['HOME']).mkdir()
        Path(self.env['GIT_TEMPLATE_DIR']).mkdir()
        self.state = self.plugin / 'scripts/octo-state.sh'
        self.state_call('init_project')

    def state_call(self, *args):
        return subprocess.check_output([self.state, *args], cwd=self.project, env=self.env, text=True)

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.project, env=self.env, text=True).strip()

    def run_shell(self, source, extra_env=None):
        return subprocess.run(['bash', '-uo', 'pipefail', '-c', source], cwd=self.project,
                              env=dict(self.env, **(extra_env or {})), text=True, capture_output=True, timeout=15)

    def archive(self):
        result = self.run_shell(block_after('## 4. Record shipped status and archive project state'),
                                {'VALIDATION_FILE': 'verified-audit.md'})
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = next(line.split(': ', 1)[1] for line in result.stdout.splitlines() if line.startswith('Archive: '))
        return {'ARCHIVE': archive, 'ARCHIVE_TIMESTAMP': Path(archive).name}

    def commit(self, ignored=False):
        self.git('init', '-q')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'tag.gpgsign', 'false')
        self.git('config', 'core.hooksPath', self.env['GIT_TEMPLATE_DIR'])
        if ignored:
            (self.project / '.gitignore').write_text('.octo/\n')
        (self.project / 'source.txt').write_text('delivered source\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'reviewed delivery')
        return self.git('rev-parse', 'HEAD')

    def test_readiness_requires_completed_delivery_and_labels_override(self):
        recipe = block_after('## 1. Check project state')
        for status in ('in_progress', 'blocked'):
            self.state_call('write_state', '--phase', '4', '--status', status)
            result = self.run_shell(recipe)
            self.assertNotEqual(result.returncode, 0)
            inherited = self.run_shell(recipe, {'SHIP_ANYWAY': '1'})
            self.assertNotEqual(inherited.returncode, 0)
            self.assertNotIn('user requested ship anyway', inherited.stdout)
            override_recipe = recipe.replace('ship_check_readiness || exit 1',
                                             'ship_check_readiness --user-approved-override || exit 1')
            override = self.run_shell(override_recipe)
            self.assertEqual(override.returncode, 0, override.stderr)
            self.assertIn('delivery completion is not established', override.stdout)
            self.assertNotIn('Delivery completion evidence: phase 4 is complete', override.stdout)

    def test_canonical_markdown_and_all_supported_root_selections(self):
        self.state_call('write_state', '--phase', '4', '--status', 'complete')
        original = dict(self.env)
        for key in ('CLAUDE_PLUGIN_ROOT', 'CODEX_PLUGIN_ROOT', 'DROID_PLUGIN_ROOT', 'OCTO_ROOT', 'stable'):
            self.env = {k: v for k, v in original.items() if k not in ('CLAUDE_PLUGIN_ROOT', 'CODEX_PLUGIN_ROOT', 'DROID_PLUGIN_ROOT', 'OCTO_ROOT')}
            if key == 'stable':
                stable = Path(self.env['HOME']) / '.claude-octopus/plugin'
                stable.parent.mkdir(exist_ok=True)
                stable.symlink_to(self.plugin, target_is_directory=True)
            else:
                self.env[key] = str(self.plugin)
            result = self.run_shell(block_after('## 1. Check project state'))
            self.assertEqual(result.returncode, 0, (key, result.stderr))
            self.assertIn('Status: complete', result.stdout)
            self.assertIn('Delivery completion evidence: phase 4 is complete', result.stdout)
        self.env = original

    def audit(self, change_during=False):
        orchestrator = self.plugin / 'scripts/orchestrate.sh'
        orchestrator.unlink(missing_ok=True)
        orchestrator.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == ink ]]
printf '%s\n' "$1" >> "$SHIP_TEST_TRACE"
source "$SHIP_TEST_ROOT/scripts/state-manager.sh"
source "$SHIP_TEST_ROOT/scripts/lib/host-runtime.sh"
workspace=$(resolve_octopus_workspace)
if [[ "$(octo_detect_host_runtime "$SHIP_TEST_ROOT")" == codex ]]; then
  session="${CODEX_SESSION_ID:-${CODEX_TASK_ID:-}}"
else
  session="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
fi
results="$workspace/results"
[[ -z "$session" ]] || results="$results/$session"
mkdir -p "$results"
if [[ "${SHIP_TEST_CHANGE:-0}" == 1 ]]; then printf changed >> source.txt; fi
python3 - "$results" "$OCTOPUS_WORKFLOW_INVOCATION_ID" <<'REPORT'
from pathlib import Path
import os, sys, time
path = Path(sys.argv[1]) / ('delivery-' + sys.argv[2] + '.md')
data = ('# DELIVERY DOCUMENT\n<!-- octopus-workflow-invocation: ' + sys.argv[2] + ' -->\n'
        '<!-- octopus-task-bytes: 4 -->\n## Task: test\n## Generated: fixture\n'
        '## Status: COMPLETE\n\n---\n\n## Quality Certification\n'
        '- Pre-delivery checks: PASSED\n- Results synthesized: fixture\n'
        '- Context policy: fixture\n- Generated by: Claude Octopus Double Diamond\n'
        '- Timestamp: fixture\n')
path.write_text(data)
stamp = time.time_ns() + 2000000
os.utime(path, ns=(stamp, stamp))
REPORT
''')
        orchestrator.chmod(0o755)
        recipe = block_after('## 2. Run the delivery audit')
        result = self.run_shell(recipe + '\nprintf "audit=%s\\n" "$SHIP_AUDITED_HEAD"\n',
            {'SHIP_TEST_ROOT': str(ROOT), 'SHIP_TEST_TRACE': str(self.base / 'audit-calls'),
             'CLAUDE_OCTOPUS_WORKSPACE': str(self.base / 'workspace'),
             'SHIP_TEST_CHANGE': '1' if change_during else '0'})
        return result

    def test_audit_records_clean_commit_through_real_report_adapter(self):
        head = self.commit(ignored=True)
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'audit={head}', result.stdout)
        self.assertEqual((self.base / 'audit-calls').read_text().splitlines(), ['ink'])

    def test_source_modified_during_audit_cannot_produce_a_complete_receipt(self):
        self.commit(ignored=True)
        result = self.audit(change_during=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('AUDIT COMPLETE:', result.stdout)
        self.assertIn('Source changed during audit', result.stderr)

    def test_zero_counts_print_once(self):
        for name in ('LESSONS.md', 'ISSUES.md'):
            (self.project / '.octo' / name).write_text('')
        result = self.run_shell(block_containing('ISSUES_RESOLVED='))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'Issues resolved: 0\nLessons captured: 0\n')

    def test_archive_is_exclusive_complete_and_preserves_completed_history(self):
        self.state_call('write_state', '--phase', '4', '--status', 'complete')
        (self.project / '.octo/LESSONS.md').write_text('## Preserve this lesson\n')
        first = self.archive()
        state = (self.project / '.octo/STATE.md').read_bytes()
        self.assertIn(b'**Status:** shipped', state)
        self.assertIn(b'Project initialized', state)
        self.assertIn(b'Project shipped; archive:', state)
        self.assertIn(b'**Current Phase:** 4', state)
        self.assertIn(b'Phase 4: [complete]', state)
        archive = self.project / first['ARCHIVE']
        self.assertEqual((archive / 'STATE.md').read_bytes(), state)
        self.assertFalse((archive / 'LESSONS.md').exists())
        second = self.archive()
        self.assertNotEqual(first['ARCHIVE'], second['ARCHIVE'])
        self.assertEqual((archive / 'STATE.md').read_bytes(), state)
        self.assertEqual((self.project / '.octo/LESSONS.md').read_text(), '## Preserve this lesson\n')

    def test_dirty_or_changed_reviewed_commit_stops_before_tag(self):
        values = self.archive()
        head = self.commit()
        recipe = block_containing('CHECKPOINT_TAG="octo-checkpoint-shipped-')
        (self.project / 'user.txt').write_text('preserve user work\n')
        result = self.run_shell(recipe, dict(values, SHIP_REVIEWED_HEAD=head, SHIP_AUDITED_HEAD=head))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.project / 'user.txt').read_text(), 'preserve user work\n')
        (self.project / 'user.txt').unlink()
        result = self.run_shell(recipe, dict(values, SHIP_REVIEWED_HEAD='0' * 40, SHIP_AUDITED_HEAD=head))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git('tag', '--list'), '')

    def test_changed_audit_head_stops_before_tag(self):
        audited_head = self.commit(ignored=True)
        audit = self.audit()
        self.assertEqual(audit.returncode, 0, audit.stderr)
        values = self.archive()
        (self.project / 'source.txt').write_text('new unaudited source\n')
        self.git('add', 'source.txt')
        self.git('commit', '-qm', 'source changed after audit')
        reviewed_head = self.git('rev-parse', 'HEAD')
        self.assertNotEqual(reviewed_head, audited_head)
        result = self.run_shell(block_containing('CHECKPOINT_TAG="octo-checkpoint-shipped-'),
            dict(values, SHIP_REVIEWED_HEAD=reviewed_head, SHIP_AUDITED_HEAD=audited_head))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('reviewed source differs from audited source', result.stderr)
        self.assertEqual(self.git('tag', '--list'), '')

    def test_each_ignored_auxiliary_copy_is_disclosed_when_state_is_tracked(self):
        original = self.project
        try:
            for name in ('PROJECT.md', 'ROADMAP.md', 'ISSUES.md'):
                for ignored in ('source', 'archive', 'both'):
                    with self.subTest(name=name, ignored=ignored):
                        self.project = self.base / (name + '-' + ignored)
                        self.project.mkdir()
                        self.state_call('init_project')
                        (self.project / '.octo' / name).write_text('local state\n')
                        patterns = []
                        if ignored in ('source', 'both'): patterns.append('.octo/' + name)
                        if ignored in ('archive', 'both'): patterns.append('.octo/archive/**/' + name)
                        (self.project / '.gitignore').write_text('\n'.join(patterns) + '\n')
                        values = self.archive()
                        head = self.commit()
                        result = self.run_shell(block_containing('CHECKPOINT_TAG="octo-checkpoint-shipped-'),
                            dict(values, SHIP_REVIEWED_HEAD=head, SHIP_AUDITED_HEAD=head))
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn('local-only state excluded:', result.stdout)
                        self.assertIn(name, result.stdout)
                        self.assertTrue(self.git('ls-files', '--', '.octo/STATE.md'))
                        self.assertTrue(self.git('ls-files', '--', values['ARCHIVE'] + '/STATE.md'))
        finally:
            self.project = original

    def test_failed_tag_is_exercised_and_never_reports_success(self):
        values = self.archive()
        head = self.commit()
        marker = self.base / 'tag-called'
        prefix = 'git() { if [[ $1 == tag ]]; then echo called > "$TAG_MARKER"; return 9; fi; command git "$@"; }\n'
        result = self.run_shell(prefix + block_containing('CHECKPOINT_TAG="octo-checkpoint-shipped-'),
                                dict(values, SHIP_REVIEWED_HEAD=head, SHIP_AUDITED_HEAD=head, TAG_MARKER=str(marker)))
        self.assertTrue(marker.exists(), result.stderr)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Checkpoint created:', result.stdout)
        self.assertEqual(self.git('tag', '--list'), '')

    def test_successful_checkpoint_targets_exact_reviewed_commit(self):
        values = self.archive()
        head = self.commit()
        result = self.run_shell(block_containing('CHECKPOINT_TAG="octo-checkpoint-shipped-'),
                                dict(values, SHIP_REVIEWED_HEAD=head, SHIP_AUDITED_HEAD=head))
        self.assertEqual(result.returncode, 0, result.stderr)
        tag = 'octo-checkpoint-shipped-' + values['ARCHIVE_TIMESTAMP']
        self.assertEqual(self.git('rev-parse', tag + '^{commit}'), head)
        self.assertIn('Checkpoint created:', result.stdout)

    def test_ignored_state_stays_local_and_checkpoint_coverage_is_explicit(self):
        for name in ('PROJECT.md', 'ROADMAP.md', 'ISSUES.md'):
            (self.project / '.octo' / name).write_text(f'{name} local state\n')
        values = self.archive()
        head = self.commit(ignored=True)
        result = self.run_shell(block_containing('CHECKPOINT_TAG="octo-checkpoint-shipped-'),
                                dict(values, SHIP_REVIEWED_HEAD=head, SHIP_AUDITED_HEAD=head))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('local-only state excluded:', result.stdout)
        for name in ('STATE.md', 'PROJECT.md', 'ROADMAP.md', 'ISSUES.md'):
            self.assertIn('.octo/' + name, result.stdout)
            self.assertIn(values['ARCHIVE'] + '/' + name, result.stdout)
        self.assertEqual(self.git('ls-files', '--', '.octo'), '')
        self.assertTrue((self.project / values['ARCHIVE'] / 'STATE.md').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
