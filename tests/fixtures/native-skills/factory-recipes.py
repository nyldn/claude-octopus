#!/usr/bin/env python3
"""Exercise factory recipes with inert transports and real shell functions."""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "scripts/helpers/factory-run.py"


class FactoryRecipes(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name) / "project 'quoted' $literal"
        self.project.mkdir()
        self.plugin = Path(self.temporary.name) / "loaded plugin"
        (self.plugin / "scripts").mkdir(parents=True)
        self.transport = self.plugin / "scripts/orchestrate.sh"
        self.transport.write_text("""#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
root=Path.cwd()/'.octo/factory'
run=root/os.environ['OCTOPUS_FACTORY_RUN_ID'];run.mkdir()
spec=Path(sys.argv[sys.argv.index('--spec')+1])
(run/'spec.md').write_bytes(spec.read_bytes())
target=float(os.environ.get('OCTOPUS_FACTORY_SATISFACTION_TARGET','0.85'))
(run/'session.json').write_text(json.dumps({'run_id':run.name,'satisfaction_target':target}))
scores=dict(behavior_coverage=.9,constraint_adherence=.9,quality=.9,holdout_pass_rate=.9,composite=.9,satisfaction_target=target,verdict='PASS')
(run/'satisfaction-scores.json').write_text(json.dumps(scores))
if os.environ.get('OMIT_COVERAGE')!='1':(run/'coverage-review.json').write_text(json.dumps({'status':'reviewed','verdict':'SUFFICIENT','gaps':[]}))
if os.environ.get('OMIT_REPORT')!='1':(run/'factory-report.md').write_text('This run report')
(root/'factory-zzzz-decoy').mkdir(exist_ok=True)
(root/'factory-zzzz-decoy/factory-report.md').write_text('Wrong concurrent run')
(run/'argv.json').write_text(json.dumps(sys.argv[1:]))
""")
        self.transport.chmod(0o755)

    def invoke(self, *args, approval="approve", env=None):
        command = [sys.executable, "-I", str(HELPER), "run", "--project", str(self.project),
                   "--plugin-root", str(self.plugin), "--approval", approval, *args]
        return subprocess.run(command, input="Inline specification with 'quotes' and $dollars.\n",
                              text=True, capture_output=True, env=dict(os.environ, **(env or {})))

    def test_decline_creates_no_state_and_never_dispatches(self):
        result = self.invoke("--inline", approval="decline")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "declined")
        self.assertFalse((self.project / ".octo").exists())

    def test_banner_retains_every_shared_provider_status(self):
        text = (ROOT / ".claude/skills/skill-factory/SKILL.md").read_text()
        step = text.split("### STEP 2:", 1)[1].split("### STEP 3:", 1)[0]
        fence = chr(96) * 3
        block = re.search(fence + r"bash\n(.*?)\n" + fence, step, re.S)[1]
        helper = self.plugin / "scripts/helpers/check-providers.sh"
        helper.parent.mkdir()
        rows = "PROVIDER_CHECK_START\ncodex:available\nagy:missing\nperplexity:missing\ncustom-seat:degraded\nPROVIDER_CHECK_END\n"
        helper.write_text("#!/bin/bash\nprintf '%s' " + shlex.quote(rows) + "\n")
        result = subprocess.run(["/bin/bash", "-c", block], text=True, capture_output=True,
                                env=dict(os.environ, OCTO_ROOT=str(self.plugin)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CLAUDE OCTOPUS ACTIVATED - Factory", result.stdout)
        self.assertIn(rows, result.stdout)

    def test_inline_target_and_exact_run_artifacts(self):
        result = self.invoke("--inline", "--target", "0.88", approval="ci")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["scores"]["satisfaction_target"], .88)
        self.assertEqual(Path(data["report"]).read_text(), "This run report")
        run = Path(data["run_dir"])
        self.assertIn("--ci", json.loads((run / "argv.json").read_text()))
        self.assertIn("$dollars", (run / "spec.md").read_text())
        self.assertEqual(Path(data["request_dir"]).stat().st_mode & 0o777, 0o700)

    def test_runs_are_isolated_and_ambient_target_cannot_override_default(self):
        first = self.invoke("--inline", env={"OCTOPUS_FACTORY_SATISFACTION_TARGET": ".99"})
        second = self.invoke("--inline")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        a, b = json.loads(first.stdout), json.loads(second.stdout)
        self.assertNotEqual(a["run_dir"], b["run_dir"])
        self.assertEqual(a["scores"]["satisfaction_target"], .85)

    def test_missing_current_report_cannot_reuse_decoy(self):
        result = self.invoke("--inline", env={"OMIT_REPORT": "1"})
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "failed")
        self.assertNotIn("report", data)

    def test_invalid_targets_fail_before_dispatch(self):
        for value in ("nan", "inf", "1.1", ".79"):
            with self.subTest(value=value):
                result = self.invoke("--inline", "--target", value)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.project / ".octo").exists())

    def test_missing_coverage_evidence_cannot_complete_a_run(self):
        result = self.invoke("--inline", env={"OMIT_COVERAGE": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["status"], "failed")

    def score(self, response, holdout="Score: 0.90", exit_code="0"):
        run = self.project / "evaluation";run.mkdir(exist_ok=True)
        (run / "spec.md").write_text("Original specification")
        (run / "holdout-results.md").write_text(holdout)
        (run / "satisfaction-scores.json").write_text('{"verdict":"PASS","composite":1}')
        script = """
source "$1/scripts/lib/factory-spec.sh"
log() { :; }
run_agent_sync() { printf '%s' "$EVALUATION"; return "$EVALUATION_RC"; }
score_satisfaction "$2" 0.85
"""
        result = subprocess.run(["/bin/bash", "-c", script, "fixture", str(ROOT), str(run)],
                                text=True, capture_output=True,
                                env=dict(os.environ, EVALUATION=response, EVALUATION_RC=exit_code))
        return result, run

    def test_scores_require_all_measured_dimensions(self):
        for response in ("", "behavior_coverage: 0.99",
                         "behavior_coverage: 0.9\nconstraint_adherence: 0.9\nquality: nan",
                         "behavior_coverage: 0.9\nconstraint_adherence: 0.9\nquality: 1.5",
                         "behavior_coverage: 0.9\nconstraint_adherence: 0.9\nquality: 0.8\nquality: 0.9"):
            with self.subTest(response=response):
                result, run = self.score(response)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse((run / "satisfaction-scores.json").exists())

    def test_failed_provider_output_is_not_a_score(self):
        result, run = self.score("behavior_coverage: 0.9\nconstraint_adherence: 0.9\nquality: 0.9", exit_code="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((run / "satisfaction-scores.json").exists())

    def test_missing_holdout_is_not_a_measured_score(self):
        result, run = self.score("behavior_coverage: 0.9\nconstraint_adherence: 0.9\nquality: 0.9", holdout="No score available")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((run / "satisfaction-scores.json").exists())

    def test_holdout_can_measure_actual_scenario_verdicts(self):
        result, run = self.score("behavior_coverage: 0.9\nconstraint_adherence: 0.9\nquality: 0.9",
                                 holdout="**Verdict:** PASS\n**Verdict:** PARTIAL")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((run / "satisfaction-scores.json").read_text())["holdout_pass_rate"], .75)

    def test_real_scores_are_written(self):
        result, run = self.score("behavior_coverage: 0.9\nconstraint_adherence: 0.8\nquality: 0.9")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads((run / "satisfaction-scores.json").read_text())
        self.assertEqual(data["composite"], .88)
        self.assertEqual(data["weights"], {"behavior_coverage": .4, "constraint_adherence": .2, "holdout_pass_rate": .25, "quality": .15})
        self.assertEqual(data["verdict"], "PASS")

    def test_actual_factory_pipeline_binds_metadata_and_results(self):
        self.transport.write_text("#!/bin/bash\nset -euo pipefail\n" +
            "source " + shlex.quote(str(ROOT / "scripts/lib/factory-spec.sh")) + "\n" +
            "source " + shlex.quote(str(ROOT / "scripts/lib/factory.sh")) + "\n" + """
log() { :; }
NC= RED= GREEN= YELLOW= CYAN= MAGENTA= _BOX_TOP= _BOX_MID= _BOX_BOT=
assess_spec_maturity() { printf 'Draft|4|{}'; }
score_nlspec_quality() { printf '95|PASS'; }
generate_factory_scenarios() {
  printf '### Scenario 1: One\\nGiven input\\nThen output\\n### Scenario 2: Two\\nGiven input\\nThen output\\n### Scenario 3: Three\\nGiven input\\nThen output\\n' > "$2/scenarios-all.md"
  printf generated
}
factory_review_scenario_coverage() { printf '{"status":"reviewed","verdict":"SUFFICIENT","gaps":[]}' > "$2/coverage-review.json"; }
embrace_full_workflow() { :; }
run_agent_sync() {
  if [[ "$2" == *"Scoring Dimensions"* ]]; then
    printf 'behavior_coverage: 0.9\\nconstraint_adherence: 0.9\\nquality: 0.9\\n'
  else
    printf '### Scenario 1\\n**Verdict:** PASS\\n## Summary\\n- Score: 0.90\\n'
  fi
}
while (( $# )); do
  case "$1" in --spec) spec="$2";shift 2;; *) shift;; esac
done
factory_run "$spec" 0.20 0 true
""")
        result = self.invoke("--inline", "--target", ".88", approval="ci")
        detail = result.stderr + result.stdout
        if result.returncode and result.stdout.strip().startswith("{"):
            failure = json.loads(result.stdout)
            detail += (Path(failure["request_dir"]) / "factory.log").read_text()
        self.assertEqual(result.returncode, 0, detail)
        data = json.loads(result.stdout)
        run = Path(data["run_dir"])
        metadata = json.loads((run / "session.json").read_text())
        self.assertEqual(metadata["run_id"], data["run_id"])
        self.assertEqual(metadata["satisfaction_target"], .88)
        self.assertEqual(metadata["behavior_count"], 0)
        self.assertIn("'quoted'", metadata["spec_path"])
        self.assertEqual(data["scores"]["composite"], .9)

    def coverage(self, verdict):
        run = self.project / ("coverage-" + verdict);run.mkdir()
        (run / "scenarios-all.md").write_text("SCENARIO_SENTINEL")
        spec = run / "spec.md";spec.write_text("SPEC_SENTINEL")
        binary = self.project / "bin";binary.mkdir(exist_ok=True)
        for provider in ("codex", "agy"):
            path=binary/provider;path.write_text("#!/bin/sh\nexit 99\n");path.chmod(0o755)
        script = """
source "$1/scripts/lib/factory.sh"
source "$1/scripts/lib/consultative-advisors.sh"
log() { :; }
octo_launch_advisors() {
  printf '%s' "$2" > "$3/selected"
  printf '%s' "$5" > "$3/prompt"
  printf '{"verdict":"%s","gaps":[]}' "$COVERAGE_VERDICT" > "$3/$4$2.md"
  printf '1'
}
factory_review_scenario_coverage "$2" "$3"
"""
        result = subprocess.run(["/bin/bash", "-c", script, "fixture", str(ROOT), str(spec), str(run)],
                                text=True, capture_output=True,
                                env=dict(os.environ, PATH=str(binary)+os.pathsep+os.environ["PATH"],
                                         OCTO_ALLOWED_PROVIDERS="agy", COVERAGE_VERDICT=verdict))
        return result, run

    def test_coverage_reviews_generated_content_with_allowed_provider(self):
        result, run = self.coverage("SUFFICIENT")
        self.assertEqual(result.returncode, 0, result.stderr)
        review = run / "coverage-review"
        self.assertEqual((review / "selected").read_text(), "agy")
        prompt = (review / "prompt").read_text()
        self.assertIn("SPEC_SENTINEL", prompt)
        self.assertIn("SCENARIO_SENTINEL", prompt)

    def test_critical_coverage_gaps_stop_the_pipeline(self):
        result, run = self.coverage("CRITICAL-GAPS")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads((run / "coverage-review.json").read_text())["verdict"], "CRITICAL-GAPS")

    def test_coverage_gate_runs_after_generation_before_implementation(self):
        spec=self.project/"spec.md";spec.write_text("Spec")
        marker=self.project/"implementation"
        script="""
source "$1/scripts/lib/factory.sh"
log() { :; }
assess_spec_maturity() { printf 'Draft|4|{}'; }
parse_factory_spec() { printf '0.85'; }
score_nlspec_quality() { printf '95|PASS'; }
generate_factory_scenarios() { printf 'SCENARIO_SENTINEL' > "$2/scenarios-all.md"; printf ok; }
factory_review_scenario_coverage() { test -s "$2/scenarios-all.md" || return 90; return 91; }
split_holdout_scenarios() { :; }
embrace_full_workflow() { touch "$MARKER"; }
run_holdout_tests() { printf 0.9; }
score_satisfaction() { printf '0.9|PASS'; }
generate_factory_report() { :; }
factory_run "$2" .2 0 true
"""
        result=subprocess.run(["/bin/bash","-c",script,"fixture",str(ROOT),str(spec)],cwd=self.project,
                              env=dict(os.environ,MARKER=str(marker)),capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
