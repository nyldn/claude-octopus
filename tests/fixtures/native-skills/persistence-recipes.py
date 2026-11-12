#!/usr/bin/env python3
"""Run authored persistence recipes in private directories without providers."""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve()
TREES = tuple(sys.argv[1:]) or ('.claude/skills', 'skills', 'codex-skills')
sys.argv = sys.argv[:1]


def block(tree, skill, fragment):
    text = (ROOT / tree / skill / 'SKILL.md').read_text()
    return next(b for b in re.findall(r'```bash\n(.*?)\n```', text, re.S) if fragment in b)


class PersistenceRecipes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / 'project & "quoted"'
        self.project.mkdir()
        self.env = dict(os.environ, HOME=str(self.base / 'home'), USER='fixture',
                        CLAUDE_PLUGIN_ROOT=str(ROOT), CODEX_PLUGIN_ROOT=str(ROOT),
                        GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
        self.env.pop('GIT_DIR', None)
        self.env.pop('GIT_WORK_TREE', None)
        Path(self.env['HOME']).mkdir()

    def run_block(self, source, extra=None):
        return subprocess.run(['bash', '-eu', '-o', 'pipefail', '-c', source],
                              cwd=self.project, env=dict(self.env, **(extra or {})),
                              capture_output=True, text=True, timeout=15)

    def test_debate_runs_preserve_prior_evidence_and_json_text(self):
        question = 'Should "cache" use \\paths?\nKeep $(touch SHOULD_NOT_RUN) literal.'
        context = {'goal': 'quotes " and \\ and\nnewlines', 'priority': 'Speed & safety',
                   'constraints': 'Unicode café and literal ${HOME}'}
        values = dict(QUESTION=question, ROUNDS='3', STYLE='thorough', ADVISORS='codex,agy',
                      USER_GOAL=context['goal'], USER_PRIORITY=context['priority'],
                      USER_CONSTRAINTS=context['constraints'])
        for tree in TREES:
            with self.subTest(tree=tree):
                source = block(tree, 'skill-debate', 'DEBATE_BASE_DIR=')
                paths = []
                for _ in range(2):
                    result = self.run_block(source + '\nprintf "%s" "$DEBATE_DIR"', values)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    path = Path(result.stdout)
                    state = json.loads((path / 'state.json').read_text())
                    self.assertEqual(state['question'], question)
                    self.assertEqual(state['user_context'], context)
                    self.assertEqual(state['advisors'], ['codex', 'agy'])
                    self.assertEqual(state['rounds_total'], 3)
                    self.assertEqual(state['debate_id'], path.name)
                    self.assertTrue(path.name.startswith('should-cache-use-paths-'))
                    (path / 'rounds/evidence.md').write_text('preserve previous run')
                    paths.append(path)
                self.assertNotEqual(*paths)
                self.assertEqual((paths[0] / 'rounds/evidence.md').read_text(), 'preserve previous run')
                self.assertFalse((self.project / 'SHOULD_NOT_RUN').exists())

    def test_repeated_debate_topic_never_reuses_a_directory(self):
        values = dict(QUESTION='Repeat this topic', ROUNDS='3', STYLE='thorough', ADVISORS='codex,agy',
                      USER_GOAL='goal', USER_PRIORITY='priority', USER_CONSTRAINTS='constraints')
        for tree in TREES:
            with self.subTest(tree=tree):
                source = block(tree, 'skill-debate', 'DEBATE_BASE_DIR=')
                paths = []
                for _ in range(2):
                    result = self.run_block(source + '\nprintf "%s" "$DEBATE_DIR"', values)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    paths.append(result.stdout)
                self.assertNotEqual(*paths)

    def test_designs_reserve_unique_markdown_paths_at_the_same_timestamp(self):
        for tree in TREES:
            with self.subTest(tree=tree):
                source = block(tree, 'skill-design-lineage', 'cat > "$FILEPATH"')
                prefix = 'date() { printf "20261112-180000\\n"; }\n'
                paths = []
                for _ in range(2):
                    result = self.run_block(prefix + source + '\nprintf "%s" "$FILEPATH"')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    path = Path(result.stdout)
                    self.assertEqual(path.suffix, '.md')
                    paths.append(path)
                self.assertNotEqual(*paths)
                self.assertTrue(paths[0].exists())

    def intent_environment(self):
        plugin = self.base / 'plugin'
        helper = plugin / 'scripts/plan-storage.sh'
        helper.parent.mkdir(parents=True, exist_ok=True)
        plan = self.base / 'plan'
        plan.mkdir(exist_ok=True)
        helper.write_text('#!/bin/sh\nprintf "%s\\n" ' + shlex.quote(str(plan)) + '\n')
        helper.chmod(0o755)
        values = dict(CLAUDE_PLUGIN_ROOT=str(plugin), CODEX_PLUGIN_ROOT=str(plugin),
                      WORKFLOW_NAME='fixture', USER_GOAL='saved goal', MIN_SUCCESS_CRITERIA='minimum',
                      EXCEPTIONAL_CRITERIA='exceptional', BOUNDARIES='scope', STAKEHOLDERS='user',
                      TIMELINE='bounded', THREE_QUESTION_ANSWERS='saved answers',
                      ALLOCATION_RISK='intermediate', ALLOCATION_INITIATIVE='human',
                      ALLOCATION_CONTROL='human', ALLOCATION_DECISION_RIGHTS='human',
                      ALLOCATION_AI_ROLE='none', ALLOCATION_DISPOSITION='pending-user-decision',
                      ALLOCATION_ESCALATION='pending', ALLOCATION_MODE='pending-user-decision')
        return plan, values

    def test_intent_persists_every_allocation_field(self):
        plan, values = self.intent_environment()
        for tree in TREES:
            for disposition, mode, role in [('pending-user-decision', 'pending-user-decision', 'none'),
                                             ('human-only', 'not-applicable', 'none'),
                                             ('AI-assisted', 'supervised', 'executor')]:
                with self.subTest(tree=tree, disposition=disposition):
                    values.update(ALLOCATION_DISPOSITION=disposition, ALLOCATION_MODE=mode,
                                  ALLOCATION_AI_ROLE=role)
                    source = block(tree, 'skill-intent-contract', 'PLAN_STORAGE=')
                    result = self.run_block(source, values)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    saved = (plan / 'session-intent.md').read_text()
                    for field, value in [('Risk', values['ALLOCATION_RISK']),
                                         ('Initiative', values['ALLOCATION_INITIATIVE']),
                                         ('Control', values['ALLOCATION_CONTROL']),
                                         ('Decision rights', values['ALLOCATION_DECISION_RIGHTS']),
                                         ('AI role', role), ('Execution disposition', disposition),
                                         ('Escalation decision', values['ALLOCATION_ESCALATION']),
                                         ('Resolved AUTONOMY_MODE', mode)]:
                        self.assertIn('**' + field + '**: ' + value, saved)

    def test_missing_allocation_preserves_existing_intent(self):
        plan, values = self.intent_environment()
        values['ALLOCATION_DECISION_RIGHTS'] = ''
        path = plan / 'session-intent.md'
        path.write_text('preserve existing intent')
        for tree in TREES:
            source = block(tree, 'skill-intent-contract', 'PLAN_STORAGE=')
            result = self.run_block(source, values)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Missing Task Allocation field', result.stderr)
            self.assertEqual(path.read_text(), 'preserve existing intent')

    def test_issue_template_is_portable_literal_and_preserves_existing_file(self):
        template = (ROOT / 'config/templates/ISSUES.md.template').read_text()
        for tree in TREES:
            with self.subTest(tree=tree):
                path = self.project / '.octo/ISSUES.md'
                path.unlink(missing_ok=True)
                source = block(tree, 'skill-issues', 'mkdir -p .octo')
                result = self.run_block(source)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = template.replace('{{PROJECT_NAME}}', self.project.name)
                self.assertEqual(path.read_text(), expected)
                saved = expected + '\nExisting issue: preserve this decision.\n'
                path.write_text(saved)
                result = self.run_block(source)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(path.read_text(), saved)
                result = self.run_block(source, {'CLAUDE_PLUGIN_ROOT': str(self.base / 'missing plugin')})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(path.read_text(), saved)

    def test_issue_initialization_rejects_nonregular_existing_paths(self):
        for tree in TREES:
            with self.subTest(tree=tree):
                path = self.project / '.octo/ISSUES.md'
                path.parent.mkdir(exist_ok=True)
                source = block(tree, 'skill-issues', 'mkdir -p .octo')
                path.mkdir()
                result = self.run_block(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(path.is_dir())
                path.rmdir()
                outside = self.base / 'preserved issues.md'
                outside.write_text('preserve outside data')
                path.symlink_to(outside)
                result = self.run_block(source)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(outside.read_text(), 'preserve outside data')
                path.unlink()


if __name__ == '__main__':
    unittest.main()
