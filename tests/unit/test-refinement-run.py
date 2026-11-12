#!/usr/bin/env python3
"""Exercise persisted refinement admission with inert paired judges."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]

class RunControlTest(unittest.TestCase):
    def setUp(self):
        """Build an isolated installation with credential-free judge adapters."""
        self.assertTrue((ROOT/'scripts/refinement-run.py').is_file(), 'persisted refinement controller is missing')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.scripts = self.base/'scripts'; self.scripts.mkdir()
        for name in ('refinement-run.py','refinement-pair.py','refinement-judge.sh','refinement-score.py'):
            shutil.copy2(ROOT/'scripts'/name, self.scripts/name)
        backend = self.scripts/'orchestrate.sh'
        backend.write_text('#!/bin/sh\ncase "$*" in *codex:codex-fixed*) [ "${FAIL_CODEX:-0}" != 1 ] || exit 1;; esac\nprintf "inert judge result\\n"\n')
        backend.chmod(0o755)
        self.run = self.base/'run'; self.run.mkdir()
        self.original = self.base/'original'; self.original.write_text('original')
        self.candidate = self.base/'candidate'; self.candidate.write_text('candidate')
        self.rubric = self.base/'rubric.json'
        self.rubric.write_text(json.dumps({'schema_version':1,'target':95,'criteria':[{'id':'correctness','description':'Works','weight':100,'minimum':3,'anchors':{str(i):str(i) for i in range(5)}}], 'guards':[{'id':'tests','description':'Tests pass'}]}))
        self.guards = self.base/'guards.json'; self.guards.write_text(json.dumps([{'id':'tests','status':'pass','evidence':'inert checks passed'}]))
        self.prompt = self.base/'prompt'; self.prompt.write_text('blind fixture request')
        self.deadline = time.time()+90
        self.cli('init', self.run, self.original, self.rubric, '--deadline',self.deadline,'--max-calls',14,'--max-rounds',5,'--claude','claude:claude-fixed','--codex','codex:codex-fixed')

    def cli(self, *args, ok=True):
        """Check the exit status and decode successful journal-backed output."""
        p = subprocess.run([sys.executable,str(self.scripts/'refinement-run.py'),*map(str,args)],text=True,capture_output=True)
        if ok: self.assertEqual(p.returncode,0,p.stderr)
        else: self.assertNotEqual(p.returncode,0,p.stdout)
        return json.loads(p.stdout) if p.returncode == 0 else p

    def controller(self):
        """Import the controller from this test's isolated installation."""
        spec = importlib.util.spec_from_file_location('refinement_run_control', self.scripts/'refinement-run.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        return module

    def pair(self, name, candidate, correction=None, **env):
        """Dispatch inert judges with fixed identities and optional correction metadata."""
        return subprocess.run([sys.executable,str(self.scripts/'refinement-pair.py'),str(self.run),name,str(self.prompt),str(candidate),str(self.rubric),str(self.deadline),'14','claude:claude-fixed','high','codex:codex-fixed','high'] + (['--rubric-correction',correction,'repair an omitted criterion'] if correction else []),env=dict(os.environ,**env),capture_output=True,text=True)

    def score(self, name, value=3.2, blockers=None, artifact=None, correction=None, late=False, interrupted=False):
        """Exercise ordinary, expired or interrupted recording of one inert pair."""
        artifact = artifact or (self.original if name == 'baseline' else self.candidate)
        self.cli('begin',self.run,name)
        self.cli('prepare',self.run,artifact,self.guards)
        result = self.pair(name,artifact,correction=correction)
        self.assertEqual(result.returncode,0,result.stderr)
        manifest = json.loads((self.run/name/'manifest.json').read_text())
        assessment = {'artifact_sha256':manifest['hashes']['candidate'],'guards':json.loads(self.guards.read_text()),'judges':[]}
        for provider in ('claude','codex'):
            assessment['judges'].append({'provider':provider,'model':provider+'-fixed','effort':'high','rubric_sha256':manifest['hashes']['rubric'],'artifact_sha256':manifest['hashes']['candidate'],'criteria':[{'id':'correctness','score':value,'evidence':'inert behavior evidence'}],'blockers':blockers or []})
        path = self.base/(name+'-assessment.json');path.write_text(json.dumps(assessment))
        if late or interrupted:
            spec = importlib.util.spec_from_file_location('late_refinement_run',self.scripts/'refinement-run.py')
            module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            if late:
                with patch.object(module.time,'time',return_value=self.deadline+1):
                    module.record(self.run,module.load(self.run),path)
                return self.cli('status',self.run)
            with patch.object(module,'persist',side_effect=OSError('interrupted checkpoint')):
                with self.assertRaises(OSError): module.record(self.run,module.load(self.run),path)

        return self.cli('record',self.run,path)

    def test_guard_failure_and_rejection_stop_before_third_attempt(self):
        self.score('baseline')
        self.cli('begin',self.run,'round-1')
        self.guards.write_text(json.dumps([{'id':'tests','status':'fail','evidence':'regression reproduced'}]))
        self.cli('prepare',self.run,self.candidate,self.guards)
        self.guards.write_text(json.dumps([{'id':'tests','status':'pass','evidence':'inert checks passed'}]))
        self.candidate.write_text('repair after the guard failure')
        result = self.score('round-2',3.6,['unresolved defect'])
        self.assertEqual(result['stop_reason'],'two-round stall')
        self.cli('begin',self.run,'round-3',ok=False)
        self.assertEqual(len((self.run/'calls.jsonl').read_text().splitlines()),2)

    def test_pending_round_and_unmanaged_dispatch_fail_closed(self):
        self.cli('begin',self.run,'baseline')
        self.cli('begin',self.run,'other',ok=False)
        self.assertNotEqual(self.pair('baseline',self.original).returncode,0)
        other = self.base/'unmanaged';other.mkdir()
        self.run = other
        self.assertNotEqual(self.pair('unmanaged',self.original).returncode,0)
        self.assertFalse((other/'calls.jsonl').exists())

    def test_best_candidate_and_trajectory_survive_restart(self):
        """Reload a lost trajectory without promoting a later rejected edit."""
        self.score('baseline',3.0)
        self.candidate.write_text('improved')
        self.score('round-1',3.5)
        best = self.cli('status',self.run)['best']
        self.candidate.write_text('rejected next version')
        self.score('round-2',3.1)
        (self.run/'trajectory.json').unlink()
        status = self.cli('status',self.run)
        self.assertEqual(status['best'],best)
        self.assertEqual(Path(best['artifact']).read_text(),'improved')
        trajectory = json.loads((self.run/'trajectory.json').read_text())
        self.assertEqual([r['decision'] for r in trajectory],['baseline retained','accepted','rejected'])

    def test_initialization_hashes_the_bytes_it_snapshots(self):
        """Edit the live original after capture to expose a second-read hash race."""
        module = self.controller()
        run = self.base/'racy-init'; run.mkdir()
        original_bytes = self.original.read_bytes()
        real_read = Path.read_bytes
        reads = []
        def read_once(path):
            """Change only the source file after returning its initial bytes."""
            data = real_read(path)
            if path == self.original:
                reads.append(path)
                path.write_text('changed after the read')
            return data
        with patch.object(Path, 'read_bytes', read_once):
            module.initialize(run, self.original, self.rubric, self.deadline, 14, 5,
                              module.load(self.run)['seats'])
        state = module.load(run)
        self.assertEqual(len(reads), 1)
        self.assertEqual((run/'original.snapshot').read_bytes(), original_bytes)
        self.assertEqual(state['original_sha256'], hashlib.sha256(original_bytes).hexdigest())

    def test_preparation_validates_and_freezes_one_read_of_each_input(self):
        """Mutate each live input after capture and compare the retained evidence."""
        module = self.controller()
        self.cli('begin', self.run, 'baseline')
        inputs = {p:p.read_bytes() for p in [self.original, self.guards, self.rubric]}
        counts = {p:0 for p in inputs}
        real_read = Path.read_bytes
        def read_once(path):
            """Count live reads while simulating edits immediately after capture."""
            data = real_read(path)
            if path in inputs:
                counts[path] += 1
                path.write_text('changed after validation')
            return data
        with patch.object(Path, 'read_bytes', read_once):
            state = module.prepare(self.run, module.load(self.run), self.original, self.guards)
        self.assertEqual(list(counts.values()), [1,1,1])
        directory = self.run/'candidates/baseline'
        for name, path in [('candidate',self.original),('guards',self.guards),('rubric',self.rubric)]:
            self.assertEqual((directory/name).read_bytes(), inputs[path])
        self.assertEqual(state['pending']['candidate_hash'], hashlib.sha256(inputs[self.original]).hexdigest())

    def test_round_limit_and_no_reinitialization(self):
        """Spend every improvement round before attempting a sixth and a reset."""
        self.score('baseline')
        self.candidate.write_text('better one'); self.score('one',3.3)
        for i in range(2,6):
            self.candidate.write_text('better '+str(i)); self.score('r'+str(i),3.3+i*.05)
        self.cli('begin',self.run,'six',ok=False)
        self.cli('init',self.run,self.original,self.rubric,'--deadline',self.deadline+60,ok=False)

    def test_pair_cannot_change_deadline_or_skip_recording(self):
        self.cli('begin',self.run,'baseline'); self.cli('prepare',self.run,self.original,self.guards)
        self.deadline += 60
        result = self.pair('baseline',self.original)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('dispatch differs from frozen run limits or panel',result.stderr)
        self.assertFalse((self.run/'calls.jsonl').exists())

    def test_prepared_admission_enforces_frozen_budget_and_deadline(self):
        """Start from admissible prepared state so missing preparation cannot mask a limit bypass."""
        self.cli('begin',self.run,'baseline')
        self.cli('prepare',self.run,self.original,self.guards)
        module = self.controller()
        state = module.load(self.run)
        frozen = {'candidate':state['pending']['candidate_hash'], 'rubric':state['pending']['rubric_hash']}
        before = (self.run/'iterations.jsonl').read_bytes()
        with module.locked(self.run):
            admitted = module.admit(self.run,'baseline',frozen,self.deadline,14,state['seats'])
            self.assertEqual(admitted['pending']['phase'],'prepared')
            for deadline, budget in [(self.deadline,13),(self.deadline,16),(self.deadline+60,14)]:
                with self.subTest(deadline=deadline,budget=budget):
                    with self.assertRaisesRegex(ValueError,'dispatch differs from frozen run limits or panel'):
                        module.admit(self.run,'baseline',frozen,deadline,budget,state['seats'])
        self.assertEqual((self.run/'iterations.jsonl').read_bytes(),before)
        self.assertFalse((self.run/'calls.jsonl').exists())

    def test_rubric_correction_can_rescore_an_original_with_failed_guards(self):
        self.guards.write_text(json.dumps([{'id':'tests','status':'fail','evidence':'known original defect'}]))
        self.score('baseline',3.0)
        previous = hashlib.sha256(self.rubric.read_bytes()).hexdigest()
        data = json.loads(self.rubric.read_text()); data['criteria'][0]['description'] = 'Corrected requirement'
        self.rubric.write_text(json.dumps(data))
        status = self.score('corrected-original',3.1,artifact=self.original,correction=previous)
        self.assertIsNone(status['correction'])
        self.assertEqual(status['stalls'],0)
        self.assertEqual(status['rounds'][-1]['decision'],'baseline retained')

    def test_correction_completes_both_rescores_before_target_success(self):
        self.score('baseline',3.0)
        self.candidate.write_text('best existing candidate'); self.score('better',3.5)
        previous = hashlib.sha256(self.rubric.read_bytes()).hexdigest()
        data = json.loads(self.rubric.read_text()); data['criteria'][0]['description'] = 'Corrected requirement'
        self.rubric.write_text(json.dumps(data))
        original = self.score('corrected-original',4,artifact=self.original,correction=previous)
        self.assertIsNone(original['stop_reason'])
        final = self.score('corrected-best',3.9)
        self.assertEqual(final['stop_reason'],'target reached')
        self.assertIsNone(final['correction'])
        self.assertEqual(len((self.run/'calls.jsonl').read_text().splitlines()),4)

    def correction_with_retained_best(self, original_score=3.0, stall=False):
        """Stage recalibration after an accepted candidate and an optional stalled edit."""
        self.score('baseline',3.0)
        self.candidate.write_text('retained best'); self.score('better',3.5)
        best = self.cli('status',self.run)['best']
        if stall:
            self.candidate.write_text('rejected candidate'); self.score('rejected',3.1)
            self.candidate.write_text('retained best')
        previous = hashlib.sha256(self.rubric.read_bytes()).hexdigest()
        data = json.loads(self.rubric.read_text()); data['criteria'][0]['description'] = 'Corrected requirement'
        self.rubric.write_text(json.dumps(data))
        self.score('corrected-original',original_score,artifact=self.original,correction=previous)
        return best

    def test_accepted_correction_best_preserves_stall_count(self):
        self.correction_with_retained_best(stall=True)
        status = self.score('corrected-best',3.5)
        self.assertTrue(status['rounds'][-1]['accepted'])
        self.assertEqual(status['stalls'],1)
        self.assertIsNone(status['stop_reason'])

    def test_rejected_correction_best_preserves_stall_count(self):
        self.correction_with_retained_best(original_score=3.6,stall=True)
        status = self.score('corrected-best',3.5)
        self.assertFalse(status['rounds'][-1]['accepted'])
        self.assertEqual(status['stalls'],1)
        self.assertIsNone(status['stop_reason'])

    def test_stopped_correction_retains_the_previous_best_and_rubric(self):
        best = self.correction_with_retained_best()
        status = self.cli('stop',self.run,'host stopped')
        self.assertEqual(status['best'],best)
        self.assertTrue(status['correction']['incomplete'])
        self.assertFalse(status['best']['target_met'])

    def test_expired_correction_status_persists_the_previous_best(self):
        """Expire unfinished recalibration, then reload it after restoring the clock."""
        import contextlib, io
        best = self.correction_with_retained_best()
        module = self.controller()
        with patch.object(module.time,'time',return_value=self.deadline+1), contextlib.redirect_stdout(io.StringIO()):
            module.main(['status',str(self.run)])
        status = self.cli('status',self.run)
        self.assertEqual(status['stop_reason'],'elapsed time limit')
        self.assertEqual(status['best'],best)
        self.assertTrue(status['correction']['incomplete'])

    def test_delivery_stop_keeps_the_first_terminal_reason(self):
        self.score('baseline',4)
        status = self.cli('stop',self.run,'delivery complete')
        self.assertEqual(status['stop_reason'],'target reached')

    def test_late_correction_best_does_not_promote_provisional_success(self):
        self.score('baseline',3.0)
        self.candidate.write_text('retained best');self.score('better',3.5)
        previous = hashlib.sha256(self.rubric.read_bytes()).hexdigest()
        data = json.loads(self.rubric.read_text());data['criteria'][0]['description'] = 'Corrected requirement'
        self.rubric.write_text(json.dumps(data))
        self.score('corrected-original',4,artifact=self.original,correction=previous)
        status = self.score('corrected-best',3.9,late=True)
        self.assertEqual(status['stop_reason'],'elapsed time limit')
        self.assertFalse(status['best']['target_met'])
        self.assertEqual(status['best']['score'],87.5)
        self.assertEqual(status['best']['rubric_sha256'],previous)
        self.assertTrue(status['correction']['incomplete'])

    def test_resume_after_retaining_assessment_before_journal_commit(self):
        """Recover retained assessment bytes without reserving another judge pair."""
        status = self.score('baseline',interrupted=True)
        self.assertEqual(len(status['rounds']),1)
        self.assertEqual(len((self.run/'calls.jsonl').read_text().splitlines()),1)

    def test_resume_after_freezing_inputs_before_journal_commit(self):
        """Reuse matching frozen inputs after an interrupted preparation checkpoint."""
        self.cli('begin',self.run,'baseline')
        spec = importlib.util.spec_from_file_location('interrupted_prepare',self.scripts/'refinement-run.py')
        module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with patch.object(module,'persist',side_effect=OSError('interrupted checkpoint')):
            with self.assertRaises(OSError):
                module.prepare(self.run,module.load(self.run),self.original,self.guards)
        status = self.cli('prepare',self.run,self.original,self.guards)
        self.assertEqual(status['pending']['phase'],'prepared')
        self.assertFalse((self.run/'calls.jsonl').exists())

    def test_invalid_rubric_cannot_consume_judge_calls(self):
        self.cli('begin',self.run,'baseline')
        rubric = json.loads(self.rubric.read_text()); rubric['criteria'][0]['weight'] = 99
        self.rubric.write_text(json.dumps(rubric))
        self.cli('prepare',self.run,self.original,self.guards,ok=False)
        self.assertFalse((self.run/'calls.jsonl').exists())
        data = self.rubric.read_text().replace('"target": 95', '"target": 95, "target": 96')
        data = data.replace('"weight": 99', '"weight": 100')
        self.rubric.write_text(data)
        self.cli('prepare',self.run,self.original,self.guards,ok=False)
        self.assertFalse((self.run/'calls.jsonl').exists())

    def test_external_calls_leave_scoring_capacity_and_ids_cannot_collide(self):
        self.cli('reserve',self.run,'research',12)
        before = (self.run/'calls.jsonl').read_bytes()
        self.cli('reserve',self.run,'overspend',1,ok=False)
        self.cli('begin',self.run,'research',ok=False)
        self.assertEqual((self.run/'calls.jsonl').read_bytes(),before)

    def test_expired_assessment_cannot_claim_target_success(self):
        """Record completed judge results after expiry without reporting target success."""
        self.run = self.base/'short-run'; self.run.mkdir()
        self.deadline = time.time()+2.5
        self.cli('init',self.run,self.original,self.rubric,'--deadline',self.deadline,'--claude','claude:claude-fixed','--codex','codex:codex-fixed')
        self.cli('begin',self.run,'baseline'); self.cli('prepare',self.run,self.original,self.guards)
        self.assertEqual(self.pair('baseline',self.original).returncode,0)
        manifest = json.loads((self.run/'baseline/manifest.json').read_text())
        assessment = {'artifact_sha256':manifest['hashes']['candidate'],'guards':json.loads(self.guards.read_text()),'judges':[
            {'provider':provider,'model':provider+'-fixed','effort':'high','rubric_sha256':manifest['hashes']['rubric'],'artifact_sha256':manifest['hashes']['candidate'],'criteria':[{'id':'correctness','score':4,'evidence':'inert checks'}],'blockers':[]} for provider in ('claude','codex')]}
        path = self.base/'late-assessment.json';path.write_text(json.dumps(assessment))
        time.sleep(max(0,self.deadline-time.time())+.05)
        status = self.cli('record',self.run,path)
        self.assertEqual(status['stop_reason'],'elapsed time limit')
        self.assertFalse(status['rounds'][-1]['target_met'])

    def test_failed_pair_stops_run_without_accepting_single_success(self):
        self.cli('begin',self.run,'baseline'); self.cli('prepare',self.run,self.original,self.guards)
        result = self.pair('baseline',self.original,FAIL_CODEX='1')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('provider',self.cli('status',self.run)['stop_reason'])
        self.cli('begin',self.run,'retry',ok=False)

if __name__ == '__main__': unittest.main()
