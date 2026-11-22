#!/usr/bin/env bash
# Exercise the production Define recipe, including a real argument-size failure.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Define state failure boundaries"
test_case "failed writes stop later operations and presentation in each host recipe"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
checked = 0
operations = ['write_decision', 'update_context', 'update_metrics']
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'flow-define/SKILL.md'
    if not entry.exists() and tree == 'codex-skills':
        continue
    section = entry.read_text().split('### STEP 6:', 1)[1].split('### STEP 7:', 1)[0]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for strict in (False, True):
        for conditional in (False, True):
            for failing in ['none'] + operations:
                with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                    directory = Path(temporary)
                    plugin = directory / 'plugin'
                    (plugin / 'scripts').mkdir(parents=True)
                    helper = plugin / 'scripts/state-manager.sh'
                    helper.write_text('#!/bin/sh\n'
                                      'printf "%s\\n" "$1" >> "$STATE_CALLS"\n'
                                      '[ "$1" != "$FAIL_OPERATION" ] || exit 23\n'
                                      'printf "%s\\n" "$1" >> "$STATE_SAVED"\n')
                    helper.chmod(0o755)
                    synthesis = directory / 'synthesis.md'
                    synthesis.write_text('## Problem Definition\nusing PostgreSQL\nPersist requirements.\n')
                    calls, saved = directory / 'calls', directory / 'saved'
                    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(plugin), CODEX_PLUGIN_ROOT=str(plugin),
                               SYNTHESIS_FILE=str(synthesis), STATE_CALLS=str(calls),
                               STATE_SAVED=str(saved), FAIL_OPERATION=failing)
                    program = recipe + '\nprintf "presentation reached\\n"'
                    if conditional:
                        program = '(\n' + program + '\n) && exit 0; exit $?'
                    result = subprocess.run(['bash', '-euc' if strict else '-c', program], env=env,
                                            cwd=directory, capture_output=True, text=True, timeout=10)
                    expected = operations if failing == 'none' else operations[:operations.index(failing) + 1]
                    assert calls.read_text().splitlines() == expected, (tree, failing, result.stderr)
                    persisted = saved.read_text().splitlines() if saved.exists() else []
                    assert persisted == (operations if failing == 'none' else expected[:-1])
                    assert (result.returncode == 0) == (failing == 'none'), (tree, failing, strict, conditional)
                    assert ('presentation reached' in result.stdout) == (failing == 'none')
                    checked += 1
print(f'{checked}/{checked} production recipe controls passed')
PY_CONTROLS
then test_pass; else test_fail "Define continued after a failed state operation"; fi
test_case "real oversized context does not increment completion; ordinary context persists"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_REAL'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
section = (root / '.claude/skills/flow-define/SKILL.md').read_text().split('### STEP 6:', 1)[1]
recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
    directory = Path(temporary)
    synthesis = directory / 'synthesis.md'
    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(root), CODEX_PLUGIN_ROOT=str(root),
               SYNTHESIS_FILE=str(synthesis), OCTOPUS_WORKFLOW_STATE_DIR=str(directory / 'state'))
    subprocess.run([str(root / 'scripts/state-manager.sh'), 'init_state'], env=env,
                   cwd=directory, capture_output=True, check=True)
    state_file = directory / 'state/state.json'
    initial = state_file.read_bytes()
    synthesis.write_text('## Problem Definition\n' + 'A' * 4194304 + '\nPersist requirements.\n')
    failed = subprocess.run(['bash', '-c', recipe], env=env, cwd=directory,
                            capture_output=True, text=True, timeout=30)
    assert failed.returncode != 0, failed.stdout
    assert state_file.read_bytes() == initial, 'Failed context changed state or completion'
    synthesis.write_text('## Problem Definition\nusing PostgreSQL\nPersist requirements.\n')
    succeeded = subprocess.run(['bash', '-c', recipe], env=env, cwd=directory,
                               capture_output=True, text=True, timeout=10)
    assert succeeded.returncode == 0, succeeded.stderr
    state = json.loads(state_file.read_text())
    assert 'using PostgreSQL' in state['context']['define']
    assert state['metrics']['phases_completed'] == 1
    assert len(state['decisions']) == 1 and state['decisions'][0]['phase'] == 'define'
print('Real failure leaves completion unchanged; successful retry persists context and decision once.')
PY_REAL
then test_pass; else test_fail "Define hid a real context failure or broke successful persistence"; fi
test_summary
