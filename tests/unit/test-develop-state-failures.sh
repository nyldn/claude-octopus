#!/usr/bin/env bash
# Run the production Develop state recipe under failed writes and partial retries.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Develop implementation state failures"
test_case "failed state writes stop before later writes or completion"
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
    entry = root / tree / 'flow-develop/SKILL.md'
    if not entry.exists():
        continue
    section = entry.read_text().split('### STEP 6: Update State', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for strict in (False, True):
        for with_decision in (False, True):
            operations = (['write_decision'] if with_decision else []) + ['update_context', 'update_metrics']
            for failing in ['none'] + operations:
                with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                    temporary = Path(temporary)
                    plugin = temporary / 'plugin'
                    (plugin / 'scripts').mkdir(parents=True)
                    calls = temporary / 'calls'
                    helper = plugin / 'scripts/state-manager.sh'
                    helper.write_text('#!/bin/sh\n'
                                      'printf "%s\\n" "$1" >> "$STATE_CALLS"\n'
                                      '[ "$1" != "$FAIL_OPERATION" ] || exit 23\n')
                    helper.chmod(0o755)
                    synthesis = temporary / 'synthesis.md'
                    synthesis.write_text('## Implementation\n' +
                                         ('implemented the request\n' if with_decision else 'plain design description\n'))
                    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(plugin), CODEX_PLUGIN_ROOT=str(plugin),
                               SYNTHESIS_FILE=str(synthesis), STATE_CALLS=str(calls), FAIL_OPERATION=failing)
                    # Tool hosts may evaluate a whole recipe as a conditional;
                    # that disables errexit even when the shell used -e.
                    for conditional in (False, True):
                        if calls.exists():
                            calls.unlink()
                        program = recipe + '\nprintf "completion reached\\n"'
                        if conditional:
                            program = '(\n' + program + '\n) && exit 0; exit $?'
                        result = subprocess.run(['bash', '-euc' if strict else '-c', program],
                                                env=env, cwd=temporary, capture_output=True, text=True, timeout=10)
                        observed = calls.read_text().splitlines() if calls.exists() else []
                        expected = operations if failing == 'none' else operations[:operations.index(failing) + 1]
                        valid = ((result.returncode == 0) == (failing == 'none') and observed == expected and
                                 ('completion reached' in result.stdout) == (failing == 'none'))
                        if not valid:
                            failures.append(f'{tree}: fail={failing}, decision={with_decision}, '
                                            f'strict={strict}, conditional={conditional}, '
                                            f'exit={result.returncode}, writes={observed}')
                        checked += 1
print(f'{checked - len(failures)}/{checked} actual state-write controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "Develop continued after failed implementation-state writes"; fi
test_summary
