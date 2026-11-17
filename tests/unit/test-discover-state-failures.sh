#!/usr/bin/env bash
# Execute Discover's shared production recipe with inert persistence failures.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Discover synthesis and state failures"
test_case "invalid synthesis and failed writes stop presentation and later writes"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
entry = root / 'skills/flow-discover/references/synthesize.md'
section = entry.read_text().split('### STEP 7:', 1)[1]
blocks = re.findall(r'```bash\n(.*?)\n```', section, re.S)
assert len(blocks) == 2, 'Expected the actual validation and state-write recipes'
recipe = '\n'.join(blocks)
operations = ['update_context:discover', 'update_metrics:provider:agy',
              'update_metrics:provider:codex', 'update_metrics:phases_completed']
failures = []
checked = 0
for strict in (False, True):
    for conditional in (False, True):
        for synthesis_kind, failing in [('valid', value) for value in ['none'] + operations] + [
                ('missing', 'none'), ('empty', 'none'), ('directory', 'none')]:
            with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                temporary = Path(temporary)
                plugin = temporary / 'plugin'
                (plugin / 'scripts').mkdir(parents=True)
                calls = temporary / 'calls'
                saved = temporary / 'saved'
                helper = plugin / 'scripts/state-manager.sh'
                helper.write_text('#!/bin/sh\n'
                                  'operation="$1:$2"\n'
                                  '[ "$operation" != update_metrics:provider ] || operation="$operation:$3"\n'
                                  'printf "%s\\n" "$operation" >> "$STATE_CALLS"\n'
                                  '[ "$operation" != "$FAIL_OPERATION" ] || exit 23\n'
                                  'printf "%s\\n" "$operation" >> "$STATE_SAVED"\n')
                helper.chmod(0o755)
                synthesis = temporary / 'synthesis.md'
                if synthesis_kind == 'valid':
                    synthesis.write_text('## Key Findings\nverified findings\n')
                elif synthesis_kind == 'empty':
                    synthesis.touch()
                elif synthesis_kind == 'directory':
                    synthesis.mkdir()
                env = dict(os.environ, OCTO_ROOT=str(plugin), SYNTHESIS_FILE=str(synthesis),
                           STATE_CALLS=str(calls), STATE_SAVED=str(saved), FAIL_OPERATION=failing,
                           FLEET_OUTPUT='codex|coding\nagy|research\ncodex|duplicate')
                program = recipe + '\nprintf "presentation reached\\n"'
                if conditional:
                    program = '(\n' + program + '\n) && exit 0; exit $?'
                result = subprocess.run(['bash', '-euc' if strict else '-c', program],
                                        env=env, cwd=temporary, capture_output=True, text=True, timeout=10)
                observed = calls.read_text().splitlines() if calls.exists() else []
                persisted = saved.read_text().splitlines() if saved.exists() else []
                success = synthesis_kind == 'valid' and failing == 'none'
                if synthesis_kind != 'valid':
                    expected = []
                    expected_saved = []
                elif failing == 'none':
                    expected = operations
                    expected_saved = operations
                else:
                    index = operations.index(failing)
                    expected = operations[:index + 1]
                    expected_saved = operations[:index]
                if not ((result.returncode == 0) == success and observed == expected and
                        persisted == expected_saved and ('presentation reached' in result.stdout) == success):
                    failures.append(f'{synthesis_kind=} {failing=} {strict=} {conditional=} '
                                    f'exit={result.returncode} writes={observed} saved={persisted}')
                checked += 1
print(f'{checked - len(failures)}/{checked} actual Discover recipe controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "Discover continued after invalid synthesis or failed state writes"; fi
test_summary
