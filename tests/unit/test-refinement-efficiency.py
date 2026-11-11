#!/usr/bin/env python3
"""Offline panel, receipt, paired reservation, and phase packaging regressions."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class Efficiency(unittest.TestCase):
    def setUp(self):
        """Give each case an isolated directory with automatic cleanup."""
        self.tmp = tempfile.TemporaryDirectory(prefix="octo-efficiency-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

    def test_nul_fields_bash32(self):
        """Keep empty fields and embedded whitespace intact on Bash 3.2."""
        script = r'''source "$1/scripts/lib/preflight.sh"
{ IFS= read -r -d '' a; IFS= read -r -d '' b; IFS= read -r -d '' c; IFS= read -r -d '' d; } < <(_octo_readiness_json_fields '{"a":"","b":null,"c":"x\n\t\n","d":"last"}' a b c d)
[[ "$a" == "" && "$b" == "" && "$c" == $'x\n\t\n' && "$d" == last ]]
'''
        subprocess.run(["/bin/bash", "-eu", "-c", script, "test", str(ROOT)], check=True)

    def fixture_panel(self):
        """Build an inert provider panel behind the real preflight helper."""
        helpers = self.base / "scripts/helpers"
        lib = self.base / "scripts/lib"
        helpers.mkdir(parents=True)
        lib.mkdir()
        for name in ("preflight.sh", "readiness-receipt.py"):
            shutil.copy(ROOT / "scripts/helpers" / name, helpers / name)
        (lib / "preflight.sh").write_text(f'source "{ROOT}/scripts/lib/preflight.sh"\n' + r'''
octo_provider_ids() { printf '%s\n' claude codex agy; }
octo_provider_readiness_result() {
    jq -cn --arg p "$1" --arg k "$2" --arg s "${TEST_STATUS:-available}" '{provider:$p,status:$s,reason_code:"fixture",check_kind:$k,checked_at:"fixture",duration_ms:0,remediation:""}'
}
''')
        return helpers / "preflight.sh"

    def test_scope_receipt_parity_pins_and_fail_closed(self):
        """Require fresh panel evidence and reject changed receipt identity."""
        helper = self.fixture_panel()
        workspace = self.base / "workspace"; workspace.mkdir()
        env = dict(os.environ, OCTOPUS_PREFLIGHT_PROVIDERS="", OCTOPUS_COUNCIL_DEFAULT_PROVIDERS="", WORKSPACE_DIR=str(workspace))
        def run(*args, changes=None):
            """Invoke fixture readiness checks with only the requested environment changes."""
            return subprocess.run(["bash", str(helper), "--json", *args], env=dict(env, **(changes or {})), capture_output=True, text=True)
        full = json.loads(run().stdout)
        selected = json.loads(run("--providers", "claude,codex").stdout)
        self.assertEqual(selected["results"], full["results"][:2])
        pinned = json.loads(run(changes={"OCTOPUS_COUNCIL_DEFAULT_PROVIDERS":"claude,codex"}).stdout)
        self.assertEqual(selected["results"], pinned["results"])
        override = json.loads(run("--providers", "claude,codex", changes={"OCTOPUS_COUNCIL_DEFAULT_PROVIDERS":"agy"}).stdout)
        self.assertEqual(override["roster"], ["claude", "codex"])
        for scope in ("unknown", "openai-tools", "claude,,codex", ",", "claude:"):
            self.assertNotEqual(run("--providers", scope).returncode, 0, scope)
        receipt = self.base / "receipt.json"
        self.assertEqual(run("--providers", "claude,codex", "--run-id", "one", "--report-out", str(receipt)).returncode, 0)
        args = ("--providers", "claude,codex", "--run-id", "one", "--report-in", str(receipt))
        self.assertEqual(run(*args).returncode, 0)
        fresh = self.base / 'fresh-codex-check'
        transport = f'''source "{ROOT}/scripts/lib/preflight.sh"
_preflight_registry_dir="{helper.parent.parent / 'lib'}"
WORKSPACE_DIR="{workspace}"
check_codex_auth_freshness() {{ touch "{fresh}"; }}
log() {{ :; }}
preflight_check true
'''
        transport_env = dict(env, OCTOPUS_PREFLIGHT_PROVIDERS='claude,codex',
                             OCTOPUS_PREFLIGHT_REPORT=str(receipt), OCTOPUS_PREFLIGHT_RUN_ID='one')
        prepared = subprocess.run(['bash', '-eu', '-c', transport], env=transport_env, capture_output=True, text=True)
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        self.assertTrue(fresh.is_file())
        prepared = subprocess.run(['bash', '-eu', '-c', transport],
            env=dict(transport_env, OCTOPUS_PREFLIGHT_RUN_ID='wrong-run'), capture_output=True, text=True)
        self.assertNotEqual(prepared.returncode, 0)
        self.assertNotEqual(run(*args, changes={"TEST_STATUS":"degraded"}).returncode, 0)
        self.assertNotEqual(run(*args, changes={"OCTOPUS_CODEX_MODEL":"changed"}).returncode, 0)
        self.assertNotEqual(run(*args, changes={"OCTO_ALLOWED_PROVIDERS":"agy"}).returncode, 0)
        # Transport into preparation uses the panel environment without altering receipt identity.
        self.assertEqual(run(*args, changes={"OCTOPUS_PREFLIGHT_PROVIDERS":"claude,codex"}).returncode, 0)
        config = self.base/'scripts/lib/config-fixture.sh'
        config.write_text('changed')
        self.assertNotEqual(run(*args).returncode, 0)
        config.unlink()
        binary_dir = self.base/'bin'; binary_dir.mkdir()
        binary = binary_dir/'codex'; binary.write_text('#!/bin/sh\nexit 0\n'); binary.chmod(0o755)
        binary_receipt = self.base/'binary-receipt.json'
        scoped_env = {'PATH':str(binary_dir)+':'+os.environ['PATH'], 'WORKSPACE_DIR':str(self.base/'workspace')}
        self.assertEqual(run('--providers','claude,codex','--run-id','one','--report-out',str(binary_receipt),changes=scoped_env).returncode,0)
        binary_args = ('--providers','claude,codex','--run-id','one','--report-in',str(binary_receipt))
        self.assertEqual(run(*binary_args,changes=scoped_env).returncode,0)
        binary.write_text('#!/bin/sh\nexit 1\n')
        self.assertNotEqual(run(*binary_args,changes=scoped_env).returncode,0)
        binary_receipt.unlink()
        self.assertEqual(run('--providers','claude,codex','--run-id','one','--report-out',str(binary_receipt),changes=scoped_env).returncode,0)
        self.assertEqual(run(*binary_args,changes=scoped_env).returncode,0)
        quota = self.base/'workspace/state/.provider-quota-dead'; quota.parent.mkdir(parents=True)
        quota.write_text('codex')
        self.assertNotEqual(run(*binary_args,changes=scoped_env).returncode,0)
        blank = run('--providers', 'claude,codex', '--run-id', 'blank', '--report-out', str(self.base / 'blank.json'), changes={'OCTOPUS_CODEX_BIN': '   '})
        self.assertEqual(blank.returncode, 0, blank.stderr)
        malformed = run('--providers', 'claude,codex', '--run-id', 'bad', '--report-out', str(self.base / 'bad.json'), changes={'OCTOPUS_CODEX_BIN': "'"})
        self.assertEqual(malformed.returncode, 2)
        self.assertNotIn('Traceback', malformed.stderr)
        original = receipt.read_text()
        for key, value in (("created_at", 0), ("version", 99), ("scope", ["agy"]), ("run_id", "two"), ("state", "bad")):
            data = json.loads(original); data[key] = value; receipt.write_text(json.dumps(data))
            self.assertNotEqual(run(*args).returncode, 0, key)
        receipt.write_text("{bad")
        self.assertNotEqual(run(*args).returncode, 0)

    def test_optional_diagnostics_scope(self):
        """Run version diagnostics only for the selected provider panel."""
        binaries = self.base/'bin'; binaries.mkdir()
        log = self.base/'versions'
        for name in ('codex','agy','qwen','gh','opencode'):
            cli = binaries/name
            cli.write_text('#!/bin/sh\necho '+name+' >> "'+str(log)+'"\necho 1.0.0\n')
            cli.chmod(0o755)
        subprocess.run(['bash',str(ROOT/'scripts/helpers/check-versions.sh'),'--json'],
            env=dict(os.environ, PATH=str(binaries)+':'+os.environ['PATH'], OCTO_ROOT=str(ROOT),
                     OCTOPUS_PREFLIGHT_DIAGNOSTIC_PROVIDERS='codex'), check=True,capture_output=True)
        self.assertEqual(log.read_text().splitlines(), ['codex'])
        log.unlink()
        result = subprocess.run(['bash', str(ROOT / 'scripts/helpers/check-versions.sh'), '--json'],
            env=dict(os.environ, PATH=str(binaries)+':'+os.environ['PATH'], OCTO_ROOT=str(ROOT),
                     OCTOPUS_PREFLIGHT_DIAGNOSTIC_PROVIDERS='copilot', OCTO_GH_MIN_VERSION='2.0.0'), check=True, capture_output=True, text=True)
        self.assertEqual(log.read_text().splitlines(), ['gh'])
        self.assertTrue(json.loads(result.stdout)['any_below_floor'])

    def pair_fixture(self, deadline=None, budget=4):
        """Put inert provider execution behind the mandatory judge adapter."""
        scripts = self.base / "scripts"
        scripts.mkdir()
        for name in ("refinement-pair.py", "refinement-judge.sh", "refinement-run.py", "refinement-score.py"):
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        # Inert orchestrator behind the real mandatory adapter. No credentials/model CLI.
        runner = scripts / "orchestrate.sh"
        runner.write_text('''#!/usr/bin/env python3
import json,os,sys,time,hashlib
from pathlib import Path
args=sys.argv
provider=args[4]
prompt=Path(args[args.index('--perspective-file')+1])
out=Path(args[args.index('--output-dir')+1])
(out/'started').write_text(str(time.time()))
(out/'record.json').write_text(json.dumps(dict(provider=provider, request=hashlib.sha256(prompt.read_bytes()).hexdigest(), retry=os.environ['OCTOPUS_AUTH_RETRIES'], effort=os.environ['OCTOPUS_REASONING_LEVEL'], sandbox=os.environ['OCTOPUS_CODEX_SANDBOX'], tools=os.environ['OCTOPUS_CLAUDE_BIN'])))
time.sleep(float(os.environ.get('TEST_DELAY','0.4')))
(out/'ended').write_text(str(time.time()))
if os.environ.get('TEST_FAIL') == provider: sys.exit(1)
print('raw unvalidated output')
''')
        runner.chmod(0o755)
        run = self.base / "run"; run.mkdir()
        prompt = self.base / "prompt"; prompt.write_text("blind same candidate and rubric")
        self.deadline = str(deadline or time.time() + 20)
        rubric = self.base / 'rubric.json'; rubric.write_text(self.rubric_text('initial rubric'))
        self.pair_args = [str(scripts / "refinement-pair.py"), str(run), "round-0", str(prompt), str(prompt), str(rubric), self.deadline, str(budget), "claude-opus:claude-fixed", "high", "codex:codex-fixed", "high"]
        self.prepare_pair()
        return run

    @staticmethod
    def rubric_text(description):
        return json.dumps({'schema_version':1,'target':95,'criteria':[{'id':'correctness','description':description,'weight':100,'minimum':3,'anchors':{str(i):str(i) for i in range(5)}}], 'guards':[]})

    def run_control(self, *args):
        command = [sys.executable, str(self.base/'scripts/refinement-run.py'), *map(str,args)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def prepare_pair(self):
        args = self.pair_args
        run = Path(args[1])
        if not (run/'iterations.jsonl').exists():
            self.run_control('init', run, args[4], args[5], '--deadline',args[6], '--max-calls',args[7], '--claude',args[8], '--claude-effort',args[9], '--codex',args[10], '--codex-effort',args[11])
        self.run_control('begin',run,args[2])
        guards = self.base/'guard-results.json'; guards.write_text('[]')
        self.run_control('prepare',run,args[4],guards,'--rubric',args[5])

    def finish_pair(self, value=3.2):
        args = self.pair_args; pair = Path(args[1])/args[2]
        manifest = json.loads((pair/'manifest.json').read_text())
        criteria = json.loads((pair/'rubric').read_text())['criteria']
        assessment = {'artifact_sha256':manifest['hashes']['candidate'],'guards':[],'judges':[]}
        for provider, seat in zip(('claude','codex'),manifest['seats']):
            assessment['judges'].append({'provider':provider,'model':seat['provider'].split(':',1)[1],'effort':seat['effort'],'rubric_sha256':manifest['hashes']['rubric'],'artifact_sha256':manifest['hashes']['candidate'],'criteria':[{'id':c['id'],'score':value,'evidence':'inert fixture checks'} for c in criteria],'blockers':[]})
        path = self.base/'assessment.json'; path.write_text(json.dumps(assessment))
        return self.run_control('record',args[1],path)

    def test_pair_overlap_identity_reservation_and_failure(self):
        """Overlap two pinned judges and retain failed calls in the budget ledger."""
        run = self.pair_fixture()
        result = subprocess.run(self.pair_args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        seats = [run / "round-0" / str(i) for i in range(2)]
        self.assertLess(max(float((s/'started').read_text()) for s in seats), min(float((s/'ended').read_text()) for s in seats))
        records = [json.loads((s/'record.json').read_text()) for s in seats]
        self.assertEqual(records[0]['request'], records[1]['request'])
        for record in records:
            self.assertEqual(record['retry'], '0'); self.assertEqual(record['effort'], 'high')
            self.assertEqual(record['sandbox'], 'read-only'); self.assertIn('--strict-mcp-config', record['tools'])
        manifest = json.loads((run/'round-0/manifest.json').read_text())
        self.assertFalse(manifest['score_validated'])
        self.finish_pair()
        self.assertNotEqual(subprocess.run(self.pair_args, capture_output=True).returncode, 0)
        self.pair_args[2] = 'round-1'
        Path(self.pair_args[4]).write_text('edited candidate')
        self.prepare_pair()
        failed = subprocess.run(self.pair_args, env=dict(os.environ, TEST_FAIL='codex:codex-fixed'), capture_output=True)
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(len((run/'calls.jsonl').read_text().splitlines()), 2)
        self.pair_args[2] = 'round-2'
        self.assertNotEqual(subprocess.run(self.pair_args, capture_output=True).returncode, 0)

    def test_deadline_and_cancellation(self):
        """Stop owned judges at the shared deadline or on interruption."""
        run = self.pair_fixture(deadline=time.time() + 2)
        result = subprocess.run(self.pair_args, env=dict(os.environ, TEST_DELAY='5'), capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads((run/'round-0/manifest.json').read_text())['state'], 'failed')
        # Both normal termination and a lost terminal cancel every owned seat.
        for signum in (signal.SIGTERM, signal.SIGHUP):
            other = self.base / f'cancel-{signum}'; other.mkdir()
            self.pair_args[1] = str(other)
            self.pair_args[6] = str(time.time() + 20)
            self.prepare_pair()
            child = subprocess.Popen(self.pair_args, env=dict(os.environ, TEST_DELAY='5'), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            limit = time.time() + 4
            while not (other / 'round-0/1/started').exists() and time.time() < limit:
                time.sleep(.02)
            self.assertTrue((other / 'round-0/1/started').exists())
            child.send_signal(signum)
            child.communicate(timeout=3)
            self.assertNotEqual(child.returncode, 0)
            time.sleep(.1)
            self.assertFalse((other / 'round-0/0/ended').exists())
            self.assertFalse((other / 'round-0/1/ended').exists())

    def test_explicit_rubric_correction_retains_run_limits(self):
        """Version a corrected rubric without resetting calls, time or model pins."""
        run = self.pair_fixture(budget=6)
        rubric = Path(self.pair_args[5])
        baseline = subprocess.run(self.pair_args, capture_output=True, text=True)
        self.assertEqual(baseline.returncode, 0, baseline.stderr)
        self.finish_pair()
        ledger = run / 'calls.jsonl'
        prior_ledger = ledger.read_bytes()
        original = json.loads(prior_ledger.splitlines()[0])
        previous = original['hashes']['rubric']
        rubric.write_text(self.rubric_text('corrected rubric with the missing criterion'))
        self.pair_args[2] = 'rubric-v2-original'
        self.prepare_pair()
        silent = subprocess.run(self.pair_args, capture_output=True, text=True)
        self.assertNotEqual(silent.returncode, 0)
        transition = ['--rubric-correction', previous, 'Add the omitted user requirement']
        stale = subprocess.run(self.pair_args + ['--rubric-correction', '0' * 64, transition[-1]], capture_output=True, text=True)
        self.assertNotEqual(stale.returncode, 0)
        self.assertIn('current hash', stale.stderr)
        best = self.base / 'best'; best.write_text('improved candidate')
        original_candidate = self.pair_args[4]
        self.pair_args[4] = str(best)
        wrong_candidate = subprocess.run(self.pair_args + transition, capture_output=True, text=True)
        self.assertNotEqual(wrong_candidate.returncode, 0)
        self.assertIn('candidate', wrong_candidate.stderr)
        self.pair_args[4] = original_candidate
        self.pair_args[8] = 'claude-opus:changed'
        changed_panel = subprocess.run(self.pair_args + transition, capture_output=True, text=True)
        self.assertNotEqual(changed_panel.returncode, 0)
        self.assertIn('panel', changed_panel.stderr)
        self.pair_args[8] = 'claude-opus:claude-fixed'
        self.assertEqual(ledger.read_bytes(), prior_ledger)
        corrected = subprocess.run(self.pair_args + transition, capture_output=True, text=True)
        self.assertEqual(corrected.returncode, 0, corrected.stderr)
        self.finish_pair()
        self.assertTrue(ledger.read_bytes().startswith(prior_ledger))
        revised = json.loads(ledger.read_text().splitlines()[1])
        self.assertEqual(revised['rubric_version'], 2)
        self.assertEqual(revised['rubric_correction']['previous_sha256'], previous)
        self.assertEqual(revised['rubric_correction']['reason'], transition[-1])
        self.assertEqual(revised['deadline'], original['deadline'])
        self.assertEqual(revised['max_calls'], 6)
        self.pair_args[2] = 'rubric-v2-best'
        repeated = subprocess.run(self.pair_args + transition, capture_output=True, text=True)
        self.assertNotEqual(repeated.returncode, 0)
        self.pair_args[4] = str(best)
        self.prepare_pair()
        rescored = subprocess.run(self.pair_args, capture_output=True, text=True)
        self.assertEqual(rescored.returncode, 0, rescored.stderr)
        self.finish_pair(3.5)
        entries = [json.loads(line) for line in ledger.read_text().splitlines()]
        self.assertEqual(sum(entry['calls'] for entry in entries), 6)
        self.assertEqual(entries[-1]['rubric_version'], 2)
        full_ledger = ledger.read_bytes()
        exhausted = subprocess.run([sys.executable, str(self.base/'scripts/refinement-run.py'),
                                    'begin', str(run), 'over-budget'], capture_output=True, text=True)
        self.assertNotEqual(exhausted.returncode, 0)
        self.assertIn('reserve two scoring calls', exhausted.stderr)
        self.assertEqual(ledger.read_bytes(), full_ledger)

    def test_reusing_historical_rubric_bytes_requires_a_new_version(self):
        """Preserve version history when an explicit correction restores prior bytes."""
        spec = importlib.util.spec_from_file_location('refinement_pair', ROOT / 'scripts/refinement-pair.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        entries = [{'hashes': {'rubric': 'old', 'candidate': 'original'}},
                   {'hashes': {'rubric': 'current', 'candidate': 'original'}, 'rubric_version': 2}]
        frozen = {'rubric': 'old', 'candidate': 'original'}
        with self.assertRaisesRegex(ValueError, '--rubric-correction'):
            module.rubric_transition(entries, frozen, None)
        revision = module.rubric_transition(entries, frozen, ['current', 'Undo an incorrect criterion'])
        self.assertEqual(revision['rubric_version'], 3)
        self.assertEqual(revision['rubric_correction']['previous_sha256'], 'current')
        self.assertEqual(revision['rubric_correction']['new_sha256'], 'old')

    def test_rubric_correction_needs_budget_for_both_rescores(self):
        """Keep the ledger unchanged when only one scoring pair remains."""
        run = self.pair_fixture()
        rubric = Path(self.pair_args[5])
        baseline = subprocess.run(self.pair_args, capture_output=True, text=True)
        self.assertEqual(baseline.returncode, 0, baseline.stderr)
        self.finish_pair()
        ledger = run / 'calls.jsonl'; before = ledger.read_bytes()
        previous = json.loads(before)['hashes']['rubric']
        rubric.write_text(self.rubric_text('corrected rubric'))
        self.pair_args[2] = 'correction'
        self.run_control('begin',run,'correction')
        result = subprocess.run([sys.executable,str(self.base/'scripts/refinement-run.py'),'prepare',str(run),self.pair_args[4],str(self.base/'guard-results.json'),'--rubric',str(rubric)],capture_output=True,text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('both rescores', result.stderr)
        self.assertEqual(ledger.read_bytes(), before)

    def test_group_signals_precede_reaping(self):
        """Keep process-group ownership until every cancellation signal is sent."""
        spec = importlib.util.spec_from_file_location('refinement_pair', ROOT / 'scripts/refinement-pair.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        events = []
        class Child:
            def __init__(self, pid): self.pid = pid
            def wait(self, timeout): events.append(('wait', self.pid))
        with patch.object(module.os, 'killpg', side_effect=lambda pid, sig: events.append(('signal', pid, sig))), patch.object(module.time, 'sleep'):
            module.terminate_owned_children([Child(101), Child(102)])
        self.assertEqual([event[0] for event in events], ['signal'] * 4 + ['wait'] * 2)
        self.assertEqual([event[2] for event in events[:4]], [signal.SIGTERM] * 2 + [signal.SIGKILL] * 2)

    def test_resources_and_packaging(self):
        """Retain explicit invocation, installed-root lookup and phase resources."""
        for skill in ('skill-refine','flow-discover'):
            text=(ROOT/'skills'/skill/'SKILL.md').read_text()
            self.assertIn('disable-model-invocation: true', text)
            if skill == 'flow-discover':
                frontmatter = text.split('---', 2)[1]
                self.assertNotRegex(frontmatter, r'(?m)^(agent|context):')
                self.assertIn('main\nconversation', text)
            for link in re.findall(r'skills/[^`\s]+\.md',text):
                self.assertTrue((ROOT/link).is_file(),link)
        for skill in ('skill-refine', 'flow-discover'):
            text = (ROOT / 'skills' / skill / 'SKILL.md').read_text()
            match = re.search(r'```bash\n(.*?)\n```', text, re.S)
            self.assertIsNotNone(match, f'{skill}: no fenced bash block')
            block = match.group(1)
            for entry in (ROOT / 'skills' / skill / 'SKILL.md', ROOT / '.claude/skills' / skill / 'SKILL.md'):
                isolated = {k: v for k, v in os.environ.items() if k not in ('CLAUDE_PLUGIN_ROOT', 'CODEX_PLUGIN_ROOT', 'OCTO_ROOT')}
                isolated.update(HOME=str(self.base), OCTO_SKILL_FILE=str(entry))
                result = subprocess.run(['bash', '-eu', '-c', block + '\nprintf "%s" "$OCTO_ROOT"'],
                    env=isolated, cwd=self.base, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(Path(result.stdout), ROOT)
        fixture=self.base/'plugin'; (fixture/'scripts').mkdir(parents=True)
        (fixture/'.claude/skills').mkdir(parents=True)
        shutil.copy2(ROOT/'scripts/build-codex-skills.sh',fixture/'scripts')
        shutil.copytree(ROOT/'skills',fixture/'skills')
        for skill in ('skill-refine','flow-discover'):
            shutil.copytree(ROOT/'.claude/skills'/skill,fixture/'.claude/skills'/skill)
        subprocess.run(['bash',str(fixture/'scripts/build-codex-skills.sh')],check=True,capture_output=True)
        for skill in ('skill-refine','flow-discover'):
            self.assertEqual((fixture/'skills'/skill/'SKILL.md').read_bytes(),(fixture/'.claude/skills'/skill/'SKILL.md').read_bytes())
            self.assertEqual(sorted(p.name for p in (ROOT/'skills'/skill/'references').iterdir()), sorted(p.name for p in (fixture/'skills'/skill/'references').iterdir()))
        subprocess.run(['bash',str(fixture/'scripts/build-codex-skills.sh'),'--check'],check=True,capture_output=True)

if __name__ == '__main__':
    unittest.main()
