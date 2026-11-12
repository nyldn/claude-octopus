#!/usr/bin/env python3
"""Run the shipped aggregation recipe against inert package evidence."""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(sys.argv.pop(1))
TREES = (".claude/skills", "skills", "codex-skills")


def aggregate(tree, case):
    text = (ROOT / tree / "flow-parallel/SKILL.md").read_text()
    section = text.split("### STEP 7:", 1)[1]
    command = re.search(r"```bash\n(.*?)\n```", section, re.S)[1]
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        run = root / ".octo/parallel"
        run.mkdir(parents=True)
        ids = ["WP-2", "WP-7"]
        if case == "unsafe":
            ids[1] = "../../outside"
        if case == "duplicate":
            ids[1] = "WP-2"
        (run / "wbs.json").write_text(json.dumps({"work_packages": [{"id": n} for n in ids]}))
        for number in (2, 7):
            package = run / ("WP-" + str(number))
            package.mkdir()
            (package / "exit-code").write_text("42" if case == "failed" and number == 7 else "0")
            if case != "unfinished" or number != 7:
                (package / ".done").touch()
            if case != "incomplete" or number != 7:
                (package / "branch").write_text("octo/wp-" + str(number))
                (package / "commit-sha").write_text(str(number) * 40)
        env = dict(os.environ)
        env.pop("WP_COUNT", None)
        if case == "stale-count":
            env["WP_COUNT"] = "999"
        return subprocess.run(["/bin/bash", "-eu", "-c", command], cwd=root,
                              env=env, text=True, capture_output=True)


class ParallelAggregation(unittest.TestCase):
    def test_noncontiguous_ids_work_in_fresh_shells_and_ignore_stale_count(self):
        for tree in TREES:
            for case in ("success", "stale-count"):
                result = aggregate(tree, case)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Total: 2 | Succeeded: 2 | Failed: 0", result.stdout)
                for number in (2, 7):
                    self.assertIn("WP-" + str(number) + ": SUCCESS", result.stdout)
                    self.assertIn("Branch: octo/wp-" + str(number), result.stdout)
                    self.assertIn("Commit: " + str(number) * 40, result.stdout)

    def test_missing_commit_evidence_and_failed_workers_are_not_successful(self):
        for tree in TREES:
            for case in ("incomplete", "failed", "unfinished"):
                result = aggregate(tree, case)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Total: 2 | Succeeded: 1 | Failed: 1", result.stdout)
                self.assertIn("WP-7: FAILED", result.stdout)

    def test_instruction_gate_checks_the_same_inventory_and_missing_metadata(self):
        for tree in TREES:
            text = (ROOT / tree / "flow-parallel/SKILL.md").read_text()
            section = text.split("**Validation gate: `instructions_written`**", 1)[1]
            command = re.search(r"```bash\n(.*?)\n```", section, re.S)[1]
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                run = root / ".octo/parallel"
                run.mkdir(parents=True)
                (run / "wbs.json").write_text(json.dumps({"work_packages": [{"id": "WP-2"}, {"id": "WP-7"}]}))
                for name in ("WP-2", "WP-7"):
                    package = run / name
                    package.mkdir()
                    for artifact in ("instructions.md", "launch.sh", "plugin-root"):
                        (package / artifact).write_text("fixture bytes")
                result = subprocess.run(["/bin/bash", "-eu", "-c", command], cwd=root, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("PASSED (2 work packages)", result.stdout)
                (run / "WP-7/plugin-root").unlink()
                result = subprocess.run(["/bin/bash", "-eu", "-c", command], cwd=root, text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("MISSING: .octo/parallel/WP-7/plugin-root", result.stdout)

    def test_invalid_or_duplicate_ids_stop_before_reading_results(self):
        for tree in TREES:
            for case in ("unsafe", "duplicate"):
                result = aggregate(tree, case)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("WORK PACKAGE RESULTS", result.stdout)


if __name__ == "__main__":
    unittest.main()
