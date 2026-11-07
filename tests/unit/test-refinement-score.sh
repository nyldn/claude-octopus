#!/usr/bin/env bash
# Exercise score validation against malformed, stale, and blocking assessments.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "Refinement score validation"
test_case "exact scoring and invalid assessment rejection"
if python3 - "$ROOT" <<'PY'
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop())


class RefinementScoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.rubric = {
            "schema_version": 1, "target": 95,
            "criteria": [{"id": key, "weight": weight, "minimum": 3,
                          "description": key, "anchors": {str(i): f"level {i}" for i in range(5)}}
                         for key, weight in [("correctness", 80), ("clarity", 20)]],
            "guards": [{"id": "tests", "description": "Required tests"}],
        }
        self.artifact = b"candidate version one\n"
        self.assessment = {
            "judges": [{"provider": provider, "model": model, "effort": "high",
                        "criteria": [{"id": key, "score": 3.8, "evidence": "Section 1: verified"}
                                     for key in ["correctness", "clarity"]], "blockers": []}
                       for provider, model in [("claude", "claude-model"), ("codex", "codex-model")]],
            "guards": [{"id": "tests", "status": "pass", "evidence": "tests.log: exit 0"}],
        }

    def run_score(self, mutation=None, artifact=None):
        rb = json.dumps(self.rubric).encode()
        rh = hashlib.sha256(rb).hexdigest()
        ah = hashlib.sha256(self.artifact).hexdigest()
        data = copy.deepcopy(self.assessment)
        data["artifact_sha256"] = ah
        for judge in data["judges"]:
            judge.update(rubric_sha256=rh, artifact_sha256=ah)
        if mutation:
            mutation(data)
        (self.root / "rubric").write_bytes(rb)
        (self.root / "artifact").write_bytes(self.artifact if artifact is None else artifact)
        (self.root / "assessment").write_text(json.dumps(data))
        proc = subprocess.run([sys.executable, str(ROOT / "scripts/refinement-score.py"),
                               str(self.root / "rubric"), str(self.root / "artifact"),
                               str(self.root / "assessment")], text=True, capture_output=True)
        return proc.returncode, json.loads(proc.stdout)

    def test_exact_threshold_passes(self):
        rc, result = self.run_score()
        self.assertEqual(rc, 0)
        self.assertTrue(result["target_met"])
        self.assertEqual(result["score"], 95)

    def test_lower_judge_controls_score(self):
        rc, result = self.run_score(lambda a: a["judges"][1]["criteria"][0].update(score=3.6))
        self.assertEqual(rc, 0)
        self.assertEqual(result["score"], 91)
        self.assertFalse(result["target_met"])

    def test_exact_decimal_threshold_with_uneven_weights(self):
        for criterion in self.rubric["criteria"]:
            criterion["weight"] = {"correctness": 1, "clarity": 2}[criterion["id"]]
        extra = copy.deepcopy(self.rubric["criteria"][0])
        extra.update(id="completeness", weight=97)
        self.rubric["criteria"].append(extra)
        for judge in self.assessment["judges"]:
            judge["criteria"].append({"id": "completeness", "score": 3.8,
                                      "evidence": "Section 2: verified"})
        rc, result = self.run_score()
        self.assertEqual(rc, 0)
        self.assertEqual(result["score"], 95)
        self.assertTrue(result["target_met"])

    def test_rounding_never_creates_a_pass(self):
        _, result = self.run_score(lambda a: a["judges"][1]["criteria"][0].update(score=3.799999999))
        self.assertFalse(result["target_met"])

    def test_criterion_floor_cannot_be_averaged_away(self):
        self.rubric["target"] = 90
        self.rubric["criteria"][0]["weight"] = 99
        self.rubric["criteria"][1]["weight"] = 1
        def change(a):
            for judge in a["judges"]:
                judge["criteria"][0]["score"] = 4
                judge["criteria"][1]["score"] = 2
        _, result = self.run_score(change)
        self.assertEqual(result["score"], 99.5)
        self.assertFalse(result["target_met"])
        self.assertEqual(len(result["criterion_failures"]), 2)

    def test_blockers_and_unverified_guards_prevent_success(self):
        for mutate in [lambda a: a["judges"][0]["blockers"].append("Requirement R2 is absent"),
                       lambda a: a["guards"][0].update(status="unverified"),
                       lambda a: a["guards"][0].update(status="fail")]:
            with self.subTest(mutate=mutate):
                self.assertFalse(self.run_score(mutate)[1]["target_met"])

    def test_disagreement_prevents_success(self):
        self.rubric["target"] = 80
        def change(a):
            for criterion in a["judges"][0]["criteria"]:
                criterion["score"] = 4
            for criterion in a["judges"][1]["criteria"]:
                criterion["score"] = 3.5
        _, result = self.run_score(change)
        self.assertEqual(result["disagreement"], 12.5)
        self.assertFalse(result["target_met"])

    def test_invalid_assessments_fail_closed(self):
        changes = [
            lambda a: a.update(artifact_sha256="stale"),
            lambda a: a["judges"][0].update(rubric_sha256="stale"),
            lambda a: a["judges"][0].update(artifact_sha256="stale"),
            lambda a: a["judges"].pop(),
            lambda a: a["judges"][1].update(provider="claude"),
            lambda a: a["judges"][1].update(model="claude-model"),
            lambda a: a["judges"][0]["criteria"].pop(),
            lambda a: a["judges"][0]["criteria"].append(a["judges"][0]["criteria"][0]),
            lambda a: a["judges"][0]["criteria"][0].update(score=True),
            lambda a: a["judges"][0]["criteria"][0].update(score=float("nan")),
            lambda a: a["judges"][0]["criteria"][0].update(score=float("inf")),
            lambda a: a["judges"][0]["criteria"][0].update(score=5),
            lambda a: a["judges"][0]["criteria"][0].update(evidence=" "),
            lambda a: a.update(guards=[]),
            lambda a: a["guards"][0].update(status="skipped"),
            lambda a: a["judges"][0].update(blockers="none"),
        ]
        for change in changes:
            with self.subTest(change=change):
                rc, result = self.run_score(change)
                self.assertEqual(rc, 2)
                self.assertFalse(result["valid"])
                self.assertFalse(result["target_met"])

    def test_changed_artifact_invalidates_scores(self):
        rc, result = self.run_score(artifact=b"new candidate\n")
        self.assertEqual(rc, 2)
        self.assertFalse(result["target_met"])

    def test_requires_canonical_claude_and_codex_provider_ids(self):
        for label in ["claude-opus", "claude-sonnet", "codex-standard", "Claude", " codex ", "other"]:
            with self.subTest(label=label):
                def alias(a):
                    a["judges"][1].update(provider=label, model="different-model")
                rc, result = self.run_score(alias)
                self.assertEqual(rc, 2)
                self.assertFalse(result["target_met"])
                self.assertIn("canonical", result["error"])

    def test_invalid_rubrics_are_rejected(self):
        original = copy.deepcopy(self.rubric)
        for mutate in [lambda r: r.update(target=True),
                       lambda r: r.update(target=101),
                       lambda r: r["criteria"][0].update(weight=70),
                       lambda r: r["criteria"][0].update(minimum=-1),
                       lambda r: r["criteria"][0]["anchors"].pop("4"),
                       lambda r: r["criteria"][0].update(weight=0)]:
            self.rubric = copy.deepcopy(original)
            mutate(self.rubric)
            self.assertEqual(self.run_score()[0], 2)

    def test_duplicate_json_keys_rejected(self):
        self.run_score()
        (self.root / "assessment").write_text('{"judges": [], "judges": []}')
        proc = subprocess.run([sys.executable, str(ROOT / "scripts/refinement-score.py"),
                               str(self.root / "rubric"), str(self.root / "artifact"),
                               str(self.root / "assessment")], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("duplicate JSON key", json.loads(proc.stdout)["error"])


unittest.main()
PY
then
    test_pass
else
    test_fail "refinement score validation regression"
fi
test_summary
