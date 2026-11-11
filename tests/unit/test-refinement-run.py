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
        self.assertTrue((ROOT/'scripts/refinement-run.py').is_file(), 'persisted refinement controller is missing')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
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
        p = subprocess.run([sys.executable,str(self.scripts/'refinement-run.py'),*map(str,args)],text=True,capture_output=True)
        if ok: self.assertEqual(p.returncode,0,p.stderr)
        else: self.assertNotEqual(p.returncode,0,p.stdout)
        return json.loads(p.stdout) if p.returncode == 0 else p

    def pair(self, name, candidate, correction=None, **env):
        return subprocess.run([sys.executable,str(self.scripts/'refinement-pair.py'),str(self.run),name,str(self.prompt),str(candidate),str(self.rubric),str(self.deadline),'14','claude:claude-fixed','high','codex:codex-fixed','high'] + (['--rubric-correction',correction,'repair an omitted criterion'] if correction else []),env=dict(os.environ,**env),capture_output=True,text=True)

    def score(self, name, value=3.2, blockers=None, artifact=None, correction=None, late=False, interrupted=False):
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

    def test_round_limit_and_no_reinitialization(self):
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

    def test_resume_after_retaining_assessment_before_journal_commit(self):
        status = self.score('baseline',interrupted=True)
        self.assertEqual(len(status['rounds']),1)
        self.assertEqual(len((self.run/'calls.jsonl').read_text().splitlines()),1)

    def test_resume_after_freezing_inputs_before_journal_commit(self):
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
