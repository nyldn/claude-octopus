#!/usr/bin/env bash
# Execute task-resume selection with inert native task tools.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Task resume dependency admission"
test_case "resume starts only a currently unblocked pending task"
if python3 - "$PROJECT_ROOT" <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest

root = Path(sys.argv[1])
entries = [root / '.claude/skills/skill-task-management-v2/SKILL.md',
           root / 'skills/skill-task-management/SKILL.md']
codex = root / 'codex-skills/skill-task-management/SKILL.md'
if codex.exists():
    entries.append(codex)


class ResumeAdmission(unittest.TestCase):
    def test_selection(self):
        cases = [
            ('blocked first', [{'id': 'blocked', 'status': 'pending', 'blockedBy': ['dep']},
                               {'id': 'ready', 'status': 'pending', 'blockedBy': []}], 'ready', None),
            ('all blocked', [{'id': 'blocked', 'status': 'pending', 'blockedBy': ['dep']}], None, 'blocked'),
            ('no pending', [], None, 'pending'),
            ('other statuses', [{'id': 'done', 'status': 'completed'},
                                {'id': 'active', 'status': 'in_progress'},
                                {'id': 'ready', 'status': 'pending'}], 'ready', None),
            ('missing dependency field', [{'id': 'ready', 'status': 'pending'}], 'ready', None),
        ]
        for entry in entries:
            text = entry.read_text().split('#### Step 4: Execute Based on Choice', 1)[1]
            recipe = re.search(r'```javascript\n(.*?)\n\s*```', text, re.S)[1]
            for label, tasks, expected, message in cases:
                with self.subTest(entry=str(entry), scenario=label):
                    self.check(recipe, tasks, tasks, expected, message)
            with self.subTest(entry=str(entry), scenario='changed while choosing'):
                self.check(recipe, [{'id': 'formerly-ready', 'status': 'pending'}],
                           [{'id': 'formerly-ready', 'status': 'pending', 'blockedBy': ['dep']}],
                           None, 'blocked')

    def check(self, recipe, old_tasks, current_tasks, expected, message):
        harness = 'const pending = ' + json.dumps(old_tasks) + '.filter(t => t.status === "pending");\n'
        harness += 'const TaskList = () => ' + json.dumps(current_tasks) + ';\n'
        harness += '''const updates = [], messages = [];
const TaskUpdate = change => updates.push(change);
const console = {log: text => messages.push(text)};
'''
        harness += recipe
        harness += '\nprocess.stdout.write(JSON.stringify({updates, messages}));\n'
        result = subprocess.run(['node', '-e', harness], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data['updates'], [] if expected is None else
                         [{'taskId': expected, 'status': 'in_progress'}])
        if message:
            self.assertIn(message, ' '.join(data['messages']).lower())


unittest.main(argv=[sys.argv[0]], verbosity=2)
PY
then test_pass; else test_fail "resume ignored dependencies, stale state, or an empty queue"; fi
test_summary
