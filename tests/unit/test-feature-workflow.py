#!/usr/bin/env python3
"""Exercise actual host adapter and runtime phase boundaries offline."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
ADAPTER = REPO / 'scripts/helpers/feature-workflow.sh'
LIB = REPO / 'scripts/lib/feature-workflow.sh'


class Workflow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name).resolve()
        self.root = self.base / 'repo'
        self.root.mkdir()
        self.home = self.base / 'home'
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), OCTOPUS_PROJECT_DIR=str(self.root),
                        CLAUDE_OCTOPUS_WORKSPACE=str(self.base / 'runtime'))
        for key in tuple(self.env):
            if key.startswith(('FEATURE_', 'GIT_', 'OCTOPUS_FEATURE', 'OCTOPUS_WORKFLOW_STATE')):
                self.env.pop(key, None)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        (self.root / 'AGENTS.md').write_text('Keep the public API stable.\n')
        self.spec = self.base / 'draft.md'
        self.spec.write_text('''# Example
## Purpose
Test portable intent.
## Actors
- User: requests export.
## Behaviors
### FR-001: Export data
Postcondition: a saved export exists.
## Constraints
Keep the API stable.
## Dependencies
None.
## Acceptance Definition
Given saved data
When export starts
Then an artifact exists.
''')

    def tearDown(self):
        self.tmp.cleanup()

    def adapter(self, *args, success=True):
        p = subprocess.run(['/bin/bash', str(ADAPTER), *args], cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0 if success else 1, p.stderr)
        return [json.loads(line) for line in p.stdout.splitlines() if line.startswith('{')][-1]

    def test_prepare_without_runtime_context_returns_json(self):
        before = set(self.root.rglob('*'))
        stale = self.base / 'stale-selection.json'
        stale.write_text('{"feature":"specs/999-stale","spec_path":"specs/999-stale/spec.md"}\n')
        for unavailable in ['dry-run', 'stale-dry-run', 'python3', 'jq', 'project-root']:
            with self.subTest(unavailable=unavailable):
                env = dict(self.env)
                if unavailable in ['dry-run', 'stale-dry-run']:
                    env['DRY_RUN'] = 'true'
                    if unavailable == 'stale-dry-run':
                        env.update(FEATURE_SELECTION=str(stale), FEATURE_RUNTIME_DIR=str(self.base),
                                   FEATURE_SOURCE_ROOT=str(self.base), FEATURE_ACTIVE='true',
                                   FEATURE_SELECTED='specs/999-stale')
                elif unavailable == 'project-root':
                    env['OCTOPUS_PROJECT_DIR'] = str(self.base / 'missing')
                else:
                    binary_dir = self.base / ('without-' + unavailable)
                    binary_dir.mkdir()
                    for command in ['dirname', 'git', 'python3', 'jq']:
                        if command != unavailable:
                            (binary_dir / command).symlink_to(shutil.which(command))
                    env['PATH'] = str(binary_dir)
                result = subprocess.run(['/bin/bash', str(ADAPTER), 'prepare', 'spec', 'export'],
                                        cwd=self.root, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout),
                                 {'schema_version': 1, 'feature': None, 'feature_context': False})
                self.assertIn('feature context unavailable', result.stderr)
                self.assertNotIn('unbound variable', result.stderr)
                self.assertEqual(set(self.root.rglob('*')), before)
                self.assertFalse((self.base / 'runtime').exists())

    def test_blocked_boundary_emits_native_questions_before_failure(self):
        context = self.adapter('prepare', 'spec', 'export')
        self.spec.write_text(self.spec.read_text() + '\n```octopus-clarifications\n' + json.dumps([{
            'question': 'Which exports are in scope?', 'kind': 'user_decision', 'category': 'scope',
            'umbrella': True, 'phases': ['plan', 'develop'], 'blocking_phases': ['plan', 'develop'],
            'blocking_reason': 'The user must select the supported exports.'}]) + '\n```\n')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'boundary-run', context['feature'])
        plan = self.root / context['feature'] / 'plan.md'
        plan.write_text('Remove the public API.\n')
        policy = json.loads(Path(context['policy_snapshot']).read_text())
        findings = [{'source': 'AGENTS.md', 'digest': policy['digest'], 'line_start': 1, 'line_end': 1,
                     'quote': 'Keep the public API stable.', 'plan_digest': hashlib.sha256(plan.read_bytes()).hexdigest(),
                     'plan_line_start': 1, 'plan_line_end': 1, 'plan_action': 'Remove the public API.'}]
        Path(context['runtime_dir'], 'policy-findings.json').write_text(json.dumps(findings))
        result = self.adapter('boundary', 'develop', context['feature'], success=False)
        self.assertTrue(result['feature_context'])
        self.assertEqual(len(result['batch']), 1)
        self.assertEqual(result['batch'][0]['question'], 'Which exports are in scope?')
        self.assertTrue(result['markers'][0]['blocking_phases'])
        self.assertIn('score', result)
        self.assertIn('umbrella', result)

    def orchestrator_dispatch(self, *args):
        # Run the shipped startup and command parser. Stop only at the provider
        # or human-review entry point, before any external work or approval.
        interception = self.base / 'dispatch-interception.sh'
        interception.write_text('''trap 'case "$BASH_COMMAND" in
    "probe_discover "*|"probe_single_cli "*|"probe_single_agent "*|"grasp_define "*|"tangle_develop "*|"ink_deliver "*|"tangle_verify "*|"embrace_full "*|"review_run "*|"council_run "*|list_pending_reviews|"approve_review "*)
        printf "DISPATCH:%s|active=%s|ambiguous=%s|selected=%s|task=%s|root=%s|runtime=%s\\n" "$BASH_COMMAND" "${FEATURE_ACTIVE:-false}" "${FEATURE_AMBIGUOUS:-false}" "${FEATURE_SELECTED:-}" "${FEATURE_TASK_CONTRACT:-}" "${FEATURE_SOURCE_ROOT:-}" "${FEATURE_RUNTIME_DIR:-}"
        exit 0 ;;
esac' DEBUG
''')
        env = dict(self.env, BASH_ENV=str(interception), OCTOPUS_SKIP_PROVIDER_PROBES='true',
                   OCTOPUS_REMOTE_SESSION='true', OCTOPUS_HOST='claude', CLAUDE_CODE='1',
                   CLAUDE_OCTOPUS_WORKSPACE=str(self.home / 'runtime'),
                   CODEX_HOME=str(self.home / 'codex'), CLAUDE_CONFIG_DIR=str(self.home / 'claude'))
        for key in list(env):
            if key.endswith(('_API_KEY', '_TOKEN')):
                env.pop(key)
        return subprocess.run(['/bin/bash', str(REPO / 'scripts/orchestrate.sh'), *args],
                              cwd=self.root, env=env, capture_output=True, text=True, timeout=45)

    def test_ambiguous_features_only_stop_binding_commands(self):
        for ordinal, name in [(1, 'export'), (2, 'search')]:
            feature = self.root / 'specs' / f'{ordinal:03d}-{name}'
            feature.mkdir(parents=True)
            (feature / 'spec.md').write_text(self.spec.read_text())
        before = {str(path.relative_to(self.root)): path.read_bytes()
                  for path in self.root.rglob('*') if path.is_file()}
        unrelated = [('probe', 'Research unrelated caching'),
                     ('probe-single', 'claude', 'security', 'fixture-task', 'Research unrelated caching'),
                     ('research', 'Research unrelated caching'),
                     ('discover', 'Research unrelated caching'),
                     ('review', 'list'), ('review', 'approve', 'fixture-review'),
                     ('council', 'Review unrelated caching'), ('code-review', '{}'),
                     ('deliver', 'Validate unrelated change'), ('ink', 'Validate unrelated change'),
                     ('verify', 'Diagnose unrelated change'), ('verification-only', 'Diagnose unrelated change')]
        for args in unrelated:
            with self.subTest(args=args):
                result = self.orchestrator_dispatch(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('DISPATCH:', result.stdout)
                self.assertIn('|active=false|ambiguous=true|selected=|task=', result.stdout)
                self.assertIn('|root=' + str(self.root) + '|runtime=' + str(self.home / 'runtime'), result.stdout)
                self.assertIn('multiple features found', result.stderr)
                after = {str(path.relative_to(self.root)): path.read_bytes()
                         for path in self.root.rglob('*') if path.is_file()}
                self.assertEqual(after, before)
        for command in ['define', 'grasp', 'develop', 'tangle', 'embrace', 'agent-resume']:
            with self.subTest(command=command):
                args = [command] if command == 'agent-resume' else [command, 'Build export']
                result = self.orchestrator_dispatch(*args)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertNotIn('DISPATCH:', result.stdout)
                self.assertRegex(result.stderr, 'multiple features found|Several repository features exist')
        self.env['OCTOPUS_FEATURE'] = 'specs/002-search'
        selected = self.orchestrator_dispatch('develop', 'Build search')
        self.assertEqual(selected.returncode, 0, selected.stderr)
        self.assertIn('|active=true|ambiguous=false|selected=specs/002-search|', selected.stdout)
        self.assertFalse((self.root / 'specs/001-export/feature.json').exists())
        self.assertTrue((self.root / 'specs/002-search/feature.json').exists())

    def test_legacy_layout_and_configured_policy_environment(self):
        (self.root / 'PROJECT.md').write_text('Preserve exports.\n')
        self.env['OCTOPUS_FEATURE_LAYOUT'] = 'legacy'
        self.env['OCTOPUS_PROJECT_POLICY'] = 'PROJECT.md'
        context = self.adapter('prepare', 'spec', 'export')
        self.assertEqual(context['spec_path'], 'spec.md')
        policy = json.loads(Path(context['policy_snapshot']).read_text())
        self.assertEqual(policy['source'], 'PROJECT.md')
        self.assertFalse((self.root / 'specs').exists())

    def test_first_and_repeat_host_activation(self):
        context = self.adapter('prepare', 'spec', 'export')
        feature = context['feature']
        self.assertTrue(feature.startswith('specs/001-export'))
        policy = json.loads(Path(context['policy_snapshot']).read_text())
        self.assertEqual(policy['source'], 'AGENTS.md')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'run-1', feature)
        result = self.adapter('boundary', 'plan', feature)
        self.assertEqual(result['batch'], [])
        again = self.adapter('prepare', 'plan', 'export', feature)
        self.assertEqual(again['feature_id'], context['feature_id'])
        self.assertEqual(len(list((self.root / 'specs').glob('[0-9]*'))), 1)

    def test_challenge_markers_persist_and_native_answers_reopen(self):
        context = self.adapter('prepare', 'spec', 'export')
        challenge = self.base / 'challenge.md'
        challenge.write_text('[NEEDS CLARIFICATION: Which export formats are in scope?]\n')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'run-2', context['feature'], str(challenge))
        first = self.adapter('boundary', 'plan', context['feature'])
        self.assertEqual(len(first['batch']), 1)
        self.assertLess(first['score']['percentage'], 100)
        manifest = json.loads((self.root / context['feature'] / 'feature.json').read_text())
        marker_id = manifest['clarifications']['markers'][0]['id']
        answers = self.base / 'answers.json'
        answers.write_text(json.dumps({'answers': [{'question_id': marker_id, 'answer': 'CSV only.',
                        'provenance': {'kind': 'native_question_response', 'actor': 'user', 'response_id': 'native-round-1'}}]}))
        result = self.adapter('answer', str(answers), context['feature'])
        self.assertEqual(result['batch'], [])
        self.assertEqual(result['markers'][0]['status'], 'answered')

    def test_task_specific_marker_blocks_before_spawn(self):
        context = self.adapter('prepare', 'spec', 'export')
        self.spec.write_text(self.spec.read_text() + '\n```octopus-clarifications\n' + json.dumps([{
            'question': 'Which format?', 'kind': 'user_decision', 'category': 'acceptance', 'task_ids': ['T001'],
            'requirements': ['FR-001'], 'phases': ['develop'], 'blocking_phases': ['develop'],
            'blocking_reason': 'T001 cannot select the file format.'}]) + '\n```\n')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'run-3', context['feature'])
        script = '''source "$LIB"
feature_workflow_begin develop feature false
feature_workflow_refresh_clarifications
if feature_workflow_gate develop T001; then printf spawned > "$TRIPWIRE"; else printf deferred; fi
if feature_workflow_gate develop T002; then printf independent; fi
'''
        env = dict(self.env, LIB=str(LIB), OCTOPUS_FEATURE=context['feature'], TRIPWIRE=str(self.base / 'spawned'))
        p = subprocess.run(['/bin/bash', '-c', script], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertFalse((self.base / 'spawned').exists())
        self.assertIn('deferredindependent', p.stdout)

    def test_verified_policy_conflict_blocks_before_spawn(self):
        context = self.adapter('prepare', 'spec', 'export')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'run-4', context['feature'])
        plan = self.root / context['feature'] / 'plan.md'
        plan.write_text('Remove the public API.\n')
        policy = json.loads(Path(context['policy_snapshot']).read_text())
        findings = [{'source': 'AGENTS.md', 'digest': policy['digest'], 'line_start': 1, 'line_end': 1,
                     'quote': 'Keep the public API stable.', 'plan_digest': hashlib.sha256(plan.read_bytes()).hexdigest(),
                     'plan_line_start': 1, 'plan_line_end': 1, 'plan_action': 'Remove the public API.'}]
        runtime = Path(context['runtime_dir'])
        (runtime / 'policy-findings.json').write_text(json.dumps(findings))
        script = 'source "$LIB"; feature_workflow_begin develop feature false; if feature_workflow_gate develop; then echo spawned; else echo blocked; fi'
        env = dict(self.env, LIB=str(LIB), OCTOPUS_FEATURE=context['feature'])
        p = subprocess.run(['/bin/bash', '-c', script], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout.strip(), 'blocked')
        self.assertIn('Keep the public API stable.', p.stderr)
        self.assertIn('Remove the public API.', p.stderr)
        findings[0]['quote'] = 'Invented rule'
        (runtime / 'policy-findings.json').write_text(json.dumps(findings))
        p = subprocess.run(['/bin/bash', '-c', script], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(p.stdout.strip(), 'spawned')

    def test_invalid_findings_cannot_erase_a_blocking_policy_finding(self):
        context = self.adapter('prepare', 'spec', 'export')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'overflow-run', context['feature'])
        plan = self.root / context['feature'] / 'plan.md'
        plan.write_text('Remove the public API.\n')
        policy = json.loads(Path(context['policy_snapshot']).read_text())
        finding = {'source': 'AGENTS.md', 'digest': policy['digest'], 'line_start': 1, 'line_end': 1,
                   'quote': 'Keep the public API stable.', 'plan_digest': hashlib.sha256(plan.read_bytes()).hexdigest(),
                   'plan_line_start': 1, 'plan_line_end': 1, 'plan_action': 'Remove the public API.'}
        response = self.base / 'review.md'
        runtime_findings = Path(context['runtime_dir']) / 'policy-findings.json'
        env = dict(self.env, LIB=str(LIB), RESPONSE=str(response), OCTOPUS_FEATURE=context['feature'])
        for route in ('response', 'runtime', 'plan'):
            for number in ('1e999', '-1e999'):
                with self.subTest(route=route, number=number):
                    body = '[' + json.dumps(finding) + ', {"score": ' + number + '}]'
                    response.write_text('```octopus-policy-findings\n' + body + '\n```\n')
                    runtime_findings.unlink(missing_ok=True)
                    setup = ''
                    if route == 'response':
                        setup = 'feature_workflow_policy_response "$(cat "$RESPONSE")"; '
                    elif route == 'runtime':
                        runtime_findings.write_text(body)
                    else:
                        plan.write_text('Remove the public API.\n' + response.read_text())
                    script = 'source "$LIB"; feature_workflow_begin develop feature false; ' + setup
                    script += 'if feature_workflow_gate develop; then echo spawned; else echo blocked; fi'
                    result = subprocess.run(['/bin/bash', '-c', script], cwd=self.root, env=env,
                                            capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), 'blocked', result.stderr)
                    self.assertIn('policy verification unavailable', result.stderr)

    def test_policy_response_blocks_legacy_plan_without_spec(self):
        plan = self.root / 'plan.md'
        plan.write_text('Remove the public API.\n')
        findings = [{'source': 'AGENTS.md',
                     'digest': hashlib.sha256((self.root / 'AGENTS.md').read_bytes()).hexdigest(),
                     'line_start': 1, 'line_end': 1, 'quote': 'Keep the public API stable.',
                     'plan_digest': hashlib.sha256(plan.read_bytes()).hexdigest(),
                     'plan_line_start': 1, 'plan_line_end': 1, 'plan_action': 'Remove the public API.'}]
        response = self.base / 'review.md'
        script = '''source "$LIB"
feature_workflow_begin develop feature false
test "$FEATURE_ACTIVE" = false || exit 8
feature_workflow_policy_response "$(cat "$RESPONSE")"
if feature_workflow_preimplement; then echo preimplement-allowed; else echo preimplement-blocked; fi
if feature_workflow_gate develop; then echo design-allowed; else echo design-blocked; fi
'''
        env = dict(self.env, LIB=str(LIB), RESPONSE=str(response))
        for quote, expected in [('Keep the public API stable.', 'blocked'), ('Invented rule', 'allowed')]:
            findings[0]['quote'] = quote
            response.write_text('```octopus-policy-findings\n' + json.dumps(findings) + '\n```\n')
            result = subprocess.run(['/bin/bash', '-c', script], cwd=self.root, env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['preimplement-' + expected, 'design-' + expected])
            if expected == 'blocked':
                self.assertIn('AGENTS.md:1', result.stderr)
                self.assertIn('Keep the public API stable.', result.stderr)
        self.assertFalse((self.root / '.octopus-feature.json').exists())

    def test_actual_tangle_binds_alternate_plan_before_decomposition(self):
        plan = self.root / 'alternate-plan.md'
        plan.write_text('Remove the public API.\n')
        for args in [('config', 'user.name', 'Fixture'), ('config', 'user.email', 'fixture@example.invalid'),
                     ('add', '.'), ('commit', '-qm', 'fixture')]:
            subprocess.run(['git', '-C', str(self.root), *args], check=True)
        finding = {'source': 'AGENTS.md',
                   'digest': hashlib.sha256((self.root / 'AGENTS.md').read_bytes()).hexdigest(),
                   'line_start': 1, 'line_end': 1, 'quote': 'Keep the public API stable.',
                   'plan_digest': hashlib.sha256(plan.read_bytes()).hexdigest(),
                   'plan_line_start': 1, 'plan_line_end': 1, 'plan_action': 'Remove the public API.'}
        response = self.base / 'design-response.md'
        tripwire = self.base / 'decomposition-started'
        script = '''source "$PLUGIN/scripts/lib/workflows.sh"
source "$LIB"
DRY_RUN=false; TMUX_MODE=false; SUPPORTS_PARALLEL_FILE_SAFETY=false; MAGENTA=; CYAN=; NC=
log(){ :; }; octopus_phase_banner(){ :; }
review_kill_process_tree_frozen(){ :; }; review_kill_descendants_frozen(){ :; }
tangle_clean_baseline_guard_enabled(){ return 1; }
display_workflow_cost_estimate(){ return 0; }; reset_provider_lockouts(){ :; }
tangle_file_digest(){ shasum -a256 "$1" | cut -d ' ' -f1; }
design_review_ceremony(){
    [[ "$1" == *'Remove the public API.'* ]] || return 90
    printf -v "$3" '%s' "$(cat "$RESPONSE")"
}
tangle_run_decomposition_fallbacks(){ printf started > "$TRIPWIRE"; return 77; }
tangle_decomposition_json_contract_guidance(){ :; }
tangle_decompose_agent=fixture; tangle_decompose_fallback_agent=fixture
feature_workflow_begin develop feature false
_tangle_develop_in_workspace alternate-plan.md '' fixture-run ''
echo TANGLE_RC=$?
'''
        env = dict(self.env, LIB=str(LIB), PLUGIN=str(REPO), PROJECT_ROOT=str(self.root),
                   RESPONSE=str(response), TRIPWIRE=str(tripwire), RESULTS_DIR=str(self.base / 'results'))
        for quote, blocked in [('Keep the public API stable.', True), ('Invented rule', False)]:
            finding['quote'] = quote
            response.write_text('```octopus-policy-findings\n' + json.dumps([finding]) + '\n```\n')
            result = subprocess.run(['/bin/bash', '-c', script], cwd=self.root, env=env,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(tripwire.exists(), not blocked, result.stderr)
            if blocked:
                self.assertIn('TANGLE_RC=1', result.stdout)
                self.assertIn('AGENTS.md:1', result.stderr)
        self.assertFalse((self.root / 'plan.md').exists())

    def test_absolute_plan_snapshot_stays_confined(self):
        plan = self.root / 'alternate-plan.md'
        plan.write_text('Accepted plan.\n')
        outside = self.base / 'outside.md'
        outside.write_text('Outside sentinel.\n')
        (self.root / 'linked.md').symlink_to(outside)
        for path, accepted in [(plan, True), (outside, False), (self.root / 'linked.md', False),
                               (self.root / '../outside.md', False),
                               (str(self.root) + '/nested/../alternate-plan.md', False)]:
            result = subprocess.run(['python3', str(REPO / 'scripts/helpers/feature-workflow.py'),
                                     'snapshot', '--root', str(self.root), '--path', str(path)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0 if accepted else 2, result.stderr)
            self.assertNotIn('Outside sentinel.', result.stdout + result.stderr)
            if accepted:
                self.assertEqual(result.stdout, plan.read_text())

    def test_legacy_import_persists_identity_before_parsing_tasks(self):
        (self.root / 'spec.md').write_text(self.spec.read_text())
        (self.root / 'tasks.md').write_text('- [ ] T001 [P] [FR-001] Implement `src/export.py`\n')
        script = '''source "$LIB"
for round in 1 2; do
    feature_workflow_begin develop feature false
    jq -c --arg feature "$FEATURE_ID" '{feature:$feature,contract:.feature_id,identity:.tasks[0].identity}' "$FEATURE_TASK_CONTRACT"
done
'''
        for policy_present in [True, False]:
            if not policy_present:
                (self.root / 'AGENTS.md').unlink()
                (self.root / '.octopus-feature.json').unlink()
            result = subprocess.run(['/bin/bash', '-c', script], cwd=self.root,
                                    env=dict(self.env, LIB=str(LIB)), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            first, second = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(first, second)
            self.assertEqual(first['feature'], first['contract'])
            self.assertTrue(first['identity'])
            manifest = json.loads((self.root / '.octopus-feature.json').read_text())
            self.assertEqual(manifest['feature_id'], first['feature'])

    def test_custom_filename_resumes_and_runtime_drafts_stay_private(self):
        context = self.adapter('prepare', 'spec', 'export', 'design.md')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'run-5', 'design.md')
        self.assertTrue((self.root / 'design.md').exists())
        self.assertFalse((self.root / 'spec.md').exists())
        command = ['python3', str(REPO / 'scripts/helpers/feature-contract.py'), 'resume', '--root', str(self.root), '--explicit', 'design.md']
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)['artifacts']['spec']['path'], 'design.md')
        self.assertFalse((self.root / 'specs').exists())
        self.assertNotIn(str(self.home), (self.root / '.octopus-feature.json').read_text())

    def test_accepted_plan_emits_and_reconciles_portable_tasks(self):
        context = self.adapter('prepare', 'spec', 'export')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'run-6', context['feature'])
        task = {'id': 'T001', 'kind': 'coding', 'title': 'Export data', 'requirements': ['FR-001'],
                'files': [], 'reads': [], 'creates': ['src/export.py'], 'dependencies': [],
                'parallel_hint': True, 'status': 'pending'}
        contract = {'schema_version': 1, 'feature_id': context['feature_id'], 'tasks': [task]}
        plan = self.base / 'plan.md'
        plan.write_text('# Plan\nImplement FR-001.\n```octopus-tasks\n' + json.dumps(contract) + '\n```\n')
        self.adapter('save', 'plan', str(plan), 'claude', 'sonnet-5.5', 'run-6-plan', context['feature'])
        feature = self.root / context['feature']
        manifest = json.loads((feature / 'feature.json').read_text())
        saved = manifest['task_history']['tasks'][0]
        self.assertEqual(saved['id'], 'T001')
        self.assertIn('```octopus-tasks', (feature / 'tasks.md').read_text())
        saved['title'] = 'Export the requested data'
        contract['tasks'] = [saved]
        plan.write_text('# Replan\n```octopus-tasks\n' + json.dumps(contract) + '\n```\n')
        self.adapter('save', 'plan', str(plan), 'claude', 'sonnet-5.5', 'run-6-replan', context['feature'])
        current = json.loads((feature / 'feature.json').read_text())['task_history']['tasks'][0]
        self.assertEqual(current['identity'], saved['identity'])
        self.assertEqual(current['id'], 'T001')


    def test_host_preimplementation_persists_only_portable_analysis(self):
        context = self.adapter('prepare', 'spec', 'export')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'run-analysis', context['feature'])
        self.adapter('boundary', 'develop', context['feature'])
        manifest_path = self.root / context['feature'] / 'feature.json'
        first = json.loads(manifest_path.read_text())['analysis']
        self.assertEqual(first['attempts'], 0)
        self.assertIn(first['status'], ('clean', 'skipped'))
        self.assertNotIn(str(self.base), manifest_path.read_text())
        self.assertNotIn('raw_path', manifest_path.read_text())
        self.adapter('boundary', 'develop', context['feature'])
        second = json.loads(manifest_path.read_text())['analysis']
        self.assertEqual(first['analysis_digest'], second['analysis_digest'])
        self.assertEqual(first['status'], second['status'])

    def test_completion_publication_preserves_contract_and_excludes_runtime_authority(self):
        context = self.adapter('prepare', 'spec', 'export')
        self.adapter('save', 'spec', str(self.spec), 'claude', 'unknown', 'run-7', context['feature'])
        task = {'id': 'T001', 'kind': 'coding', 'title': 'Export data', 'requirements': ['FR-001'],
                'files': [], 'reads': [], 'creates': ['src/export.py'], 'dependencies': [], 'parallel_hint': True}
        plan = self.base / 'plan.md'
        plan.write_text('```octopus-tasks\n' + json.dumps({'schema_version': 1, 'feature_id': context['feature_id'], 'tasks': [task]}) + '\n```\n')
        self.adapter('save', 'plan', str(plan), 'claude', 'unknown', 'run-7-plan', context['feature'])
        subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'baseline'], check=True)
        manifest = json.loads((self.root / context['feature'] / 'feature.json').read_text())
        contract = manifest['task_history']
        task = contract['tasks'][0]
        raw = {'schema_version': 1, 'contract_digest': contract['contract_digest'], 'tasks': [{
            'id': task['id'], 'identity': task['identity'], 'status': 'completed', 'contract_digest': contract['contract_digest'],
            'parent_verified': True, 'evidence': 'run:wave-1', 'write_evidence': {
                'execution_root_digest': 'private-runtime-authority', 'launch_snapshot': 'private-snapshot',
                'paths': {'src/export.py': {'type': 'file', 'mode': 420, 'digest': 'sha256:' + 'a' * 64}}}}]}
        completed = self.base / 'completion.json'
        completed.write_text(json.dumps(raw))
        script = 'source "$LIB"; feature_workflow_begin develop feature false; feature_workflow_tasks_completed "$COMPLETION"'
        env = dict(self.env, LIB=str(LIB), OCTOPUS_FEATURE=context['feature'], COMPLETION=str(completed))
        result = subprocess.run(['/bin/bash', '-c', script], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        portable = (self.root / context['feature'] / 'feature.json').read_text()
        self.assertNotIn('parent_verified', portable)
        self.assertNotIn('private-runtime-authority', portable)
        history = json.loads(portable)['task_completion']
        self.assertEqual(json.loads(portable)['phase'], 'verify')
        self.assertEqual(history['tasks'][0]['evidence']['files'][0]['relativepath'], 'src/export.py')
        self.assertEqual(history['tasks'][0]['evidence']['run_id'], 'wave-1')
        document = (self.root / context['feature'] / 'tasks.md').read_text()
        self.assertIn('- [x] T001', document)
        parsed = subprocess.run(['python3', str(REPO / 'scripts/helpers/feature-tasks.py'), 'parse', '--tasks', str(self.root / context['feature'] / 'tasks.md'), '--feature-id', context['feature_id']], capture_output=True, text=True)
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        self.assertEqual(json.loads(parsed.stdout)['contract_digest'], contract['contract_digest'])


if __name__ == '__main__':
    unittest.main()
