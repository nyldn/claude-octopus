#!/usr/bin/env python3
"""Verify that every shipped host entry uses the same run-owned coordinator."""
import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(sys.argv.pop(1)).resolve()


class ParallelEntry(unittest.TestCase):
    def test_all_host_entries_bind_the_same_coordinator_and_seven_gates(self):
        for tree in (".claude/skills", "skills", "codex-skills"):
            text = (ROOT / tree / "flow-parallel/SKILL.md").read_text()
            self.assertEqual(len(re.findall(r"^### STEP [1-7]:", text, re.M)), 7)
            for command in ("prepare", "instructions", "run", "status"):
                self.assertRegex(text, r"parallel-workflow\.py\" " + command)
            for gate in ("wbs_generated", "instructions_written", "processes_launched", "all_work_packages_complete"):
                self.assertIn(gate, text)
            self.assertIn("octo_launch_advisors", text)
            self.assertIn('"wbs-" "$PROMPT" 1', text)
            self.assertNotIn(' spawn "$review_provider"', text)
            self.assertNotIn('cat > ".octo/parallel/wbs.json"', text)
            self.assertNotIn('<absolute-project-root-path>', text)
            self.assertNotIn("wbs=json.load(open('$WBS_FILE'))", text)
            self.assertIn('Dependency output is', text)
            self.assertIn('explicitly labeled untrusted', text)
            self.assertIn('Do not reset, stash, or commit unrelated user work', text)
            self.assertIn('Read every package', text)
            self.assertIn('the user has authorized', text)

    def test_command_loads_the_registered_native_entry_from_the_actual_root(self):
        command = (ROOT / "commands/parallel.md").read_text()
        self.assertIn('skills/flow-parallel/SKILL.md', command)
        self.assertIn('entry that was actually loaded', command)
        self.assertNotIn('${HOME}', command)
        self.assertNotIn('/.claude/skills/', command)
        manifest = json.loads((ROOT / '.claude-plugin/plugin.json').read_text())
        self.assertIn('./skills/flow-parallel', manifest['skills'])


if __name__ == '__main__':
    unittest.main()
