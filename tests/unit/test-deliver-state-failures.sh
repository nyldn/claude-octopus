#!/usr/bin/env bash
# Execute the delivered skill recipes with failing persistence helpers.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Deliver state failure boundaries"
test_case "failed state operations stop completion and shipping guidance"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
checked = 0
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'flow-deliver/SKILL.md'
    if not entry.exists():
        continue
    text = entry.read_text()
    for section, operations in (
        ('### STEP 6: Update State', ['update_context', 'update_metrics', 'show_summary']),
        ('## Post-Delivery: Route to Ship', ['update_state']),
    ):
        recipe = re.search(r'```bash\n(.*?)\n```', text.split(section, 1)[1], re.S)[1]
        for strict in (False, True):
            for conditional in (False, True):
                for failing in ['none'] + operations:
                    with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                        temporary = Path(temporary)
                        plugin = temporary / 'plugin'
                        (plugin / 'scripts').mkdir(parents=True)
                        calls = temporary / 'calls'
                        # Record only successful writes as durable state. A failure
                        # must retain those writes and prevent subsequent operations.
                        saved = temporary / 'saved'
                        helper_text = ('#!/bin/sh\n'
                                       'printf "%s\\n" "$1" >> "$STATE_CALLS"\n'
                                       '[ "$1" != "$FAIL_OPERATION" ] || exit 23\n'
                                       'printf "%s\\n" "$1" >> "$SAVED_STATE"\n')
                        for name in ('state-manager.sh', 'octo-state.sh'):
                            helper = plugin / 'scripts' / name
                            helper.write_text(helper_text)
                            helper.chmod(0o755)
                        validation = temporary / 'validation.md'
                        validation.write_text('## Summary\nPass\nreview accepted\n')
                        env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(plugin), CODEX_PLUGIN_ROOT=str(plugin),
                                   VALIDATION_FILE=str(validation), STATE_CALLS=str(calls),
                                   SAVED_STATE=str(saved), FAIL_OPERATION=failing)
                        program = recipe + '\nprintf "completion reached\\n"'
                        if conditional:
                            program = '(\n' + program + '\n) && exit 0; exit $?'
                        result = subprocess.run(['bash', '-euc' if strict else '-c', program],
                                                env=env, cwd=temporary, capture_output=True, text=True, timeout=10)
                        observed = calls.read_text().splitlines() if calls.exists() else []
                        persisted = saved.read_text().splitlines() if saved.exists() else []
                        expected = operations if failing == 'none' else operations[:operations.index(failing) + 1]
                        expected_saved = operations if failing == 'none' else expected[:-1]
                        completion = any(marker in result.stdout for marker in
                                         ('completion reached', 'Session Complete', 'WORKFLOW COMPLETE', 'Project ready!'))
                        valid = ((result.returncode == 0) == (failing == 'none') and
                                 observed == expected and persisted == expected_saved and
                                 completion == (failing == 'none'))
                        if not valid:
                            failures.append(f'{tree}: {section}, fail={failing}, strict={strict}, '
                                            f'conditional={conditional}, exit={result.returncode}, '
                                            f'calls={observed}, saved={persisted}, completion={completion}')
                        checked += 1
print(f'{checked - len(failures)}/{checked} actual Deliver state controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "Deliver continued after a failed state operation"; fi
test_case "actual summary reads fail without printing success-shaped output"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_SUMMARY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
root = Path(sys.argv[1])
helper = root / 'scripts/state-manager.sh'
with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
    directory = Path(temporary)
    env = dict(os.environ, OCTOPUS_WORKFLOW_STATE_DIR=str(directory))
    subprocess.run([str(helper), 'init_state'], env=env, capture_output=True, check=True)
    state_file = directory / 'state.json'
    original = state_file.read_text()
    good = subprocess.run([str(helper), 'show_summary'], env=env, capture_output=True, text=True)
    assert good.returncode == 0 and 'Active Blockers: 0' in good.stdout
    for corrupted in ('', ' \n\t', 'invalid JSON', json.dumps(dict(json.loads(original), blockers=None)),
                      json.dumps({key: value for key, value in json.loads(original).items() if key != 'blockers'})):
        state_file.write_text(corrupted)
        result = subprocess.run([str(helper), 'show_summary'], env=env, capture_output=True, text=True)
        assert result.returncode != 0 and not result.stdout, (result.returncode, result.stdout)
    state_file.write_text(original)
    restored = subprocess.run([str(helper), 'show_summary'], env=env, capture_output=True, text=True)
    assert restored.returncode == 0 and restored.stdout == good.stdout
print('7/7 production summary controls passed')
PY_SUMMARY
then test_pass; else test_fail "summary read failure was hidden"; fi
test_summary
