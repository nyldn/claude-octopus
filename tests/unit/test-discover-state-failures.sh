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
reports = {
    'valid': ('## Key Findings\nverified findings\n', 'verified findings'),
    'late_findings': ('## Executive Summary\nsummary\n' + 'intro\n' * 52
                      + '## Key Findings\n\nfirst\nsecond\nthird\nfourth\n'
                      + '## Themes & Patterns\nother section\n', 'first second third'),
    'legacy_summary': ('## Summary\nlegacy result\n## Sources\nsource\n', 'legacy result'),
    'executive_summary': ('## Executive Summary\nexecutive result\n', 'executive result'),
    'subsections': ('## Key Findings\n### Latency\nrequests got faster\n'
                    '### Cost\nless compute\n## Sources\nsource only\n',
                    'requests got faster less compute'),
    'heading_only': ('## Key Findings\n### Latency fell by 30% [inference]\n'
                     '### Cost fell by 20% [inference]\n',
                     'Latency fell by 30% [inference] Cost fell by 20% [inference]'),
    'mixed_subsections': ('## Key Findings\n### Latency fell by 30% [inference]\n'
                          '### Cost\nless compute\n## Sources\nsource only\n',
                          'Latency fell by 30% [inference] less compute'),
    'no_context': ('## Sources\nsource only\n', None),
    'blank_context': ('## Key Findings\n  \n## Sources\nsource only\n', None),
}
scenarios = [('valid', value) for value in ['none'] + operations] + [
    (kind, 'none') for kind in reports if kind != 'valid'
] + [('missing', 'none'), ('empty', 'none'), ('directory', 'none')]
failures = []
checked = 0
for strict in (False, True):
    for conditional in (False, True):
        for synthesis_kind, failing in scenarios:
            with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                temporary = Path(temporary)
                plugin = temporary / 'plugin'
                (plugin / 'scripts').mkdir(parents=True)
                calls = temporary / 'calls'
                saved = temporary / 'saved'
                context = temporary / 'context'
                helper = plugin / 'scripts/state-manager.sh'
                helper.write_text('#!/bin/sh\n'
                                  'operation="$1:$2"\n'
                                  '[ "$operation" != update_metrics:provider ] || operation="$operation:$3"\n'
                                  'printf "%s\\n" "$operation" >> "$STATE_CALLS"\n'
                                  '[ "$operation" != "$FAIL_OPERATION" ] || exit 23\n'
                                  'if [ "$operation" = update_context:discover ]; then printf "%s" "$3" > "$STATE_CONTEXT"; fi\n'
                                  'printf "%s\\n" "$operation" >> "$STATE_SAVED"\n')
                helper.chmod(0o755)
                synthesis = temporary / 'synthesis.md'
                report, expected_context = reports.get(synthesis_kind, (None, None))
                if report is not None:
                    synthesis.write_text(report)
                elif synthesis_kind == 'empty':
                    synthesis.touch()
                elif synthesis_kind == 'directory':
                    synthesis.mkdir()
                env = dict(os.environ, OCTO_ROOT=str(plugin), SYNTHESIS_FILE=str(synthesis),
                           STATE_CALLS=str(calls), STATE_SAVED=str(saved), STATE_CONTEXT=str(context),
                           FAIL_OPERATION=failing,
                           FLEET_OUTPUT='codex|coding\nagy|research\ncodex|duplicate')
                program = recipe + '\nprintf "presentation reached\\n"'
                if conditional:
                    program = '(\n' + program + '\n) && exit 0; exit $?'
                result = subprocess.run(['bash', '-euo', 'pipefail', '-c', program] if strict else ['bash', '-c', program],
                                        env=env, cwd=temporary, capture_output=True, text=True, timeout=10)
                observed = calls.read_text().splitlines() if calls.exists() else []
                persisted = saved.read_text().splitlines() if saved.exists() else []
                success = expected_context is not None and failing == 'none'
                if expected_context is None:
                    expected = []
                    expected_saved = []
                elif failing == 'none':
                    expected = operations
                    expected_saved = operations
                else:
                    index = operations.index(failing)
                    expected = operations[:index + 1]
                    expected_saved = operations[:index]
                actual_context = context.read_text() if context.exists() else None
                if failing == 'update_context:discover':
                    expected_context = None
                if not ((result.returncode == 0) == success and observed == expected and
                        persisted == expected_saved and actual_context == expected_context and
                        ('presentation reached' in result.stdout) == success):
                    failures.append(f'{synthesis_kind=} {failing=} {strict=} {conditional=} '
                                    f'exit={result.returncode} writes={observed} saved={persisted} context={actual_context!r}')
                checked += 1
print(f'{checked - len(failures)}/{checked} actual Discover recipe controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "Discover continued after invalid synthesis or failed state writes"; fi

test_case "Discover guidance uses the synthesis path from the current run"
guidance_failures=()
for skill_tree in skills codex-skills; do
    guidance_path="$PROJECT_ROOT/$skill_tree/flow-discover/references/guidance.md"
    guidance="$(<"$guidance_path")"
    if [[ "$guidance" != *'Read `$SYNTHESIS_FILE`'* \
       || "$guidance" != *'Full research saved to: $SYNTHESIS_FILE'* ]] \
       || grep -E '(discover|probe)-synthesis-[^[:space:]]*\.md' "$guidance_path"; then
        guidance_failures+=("$skill_tree")
    fi
done
if [[ ${#guidance_failures[@]} -eq 0 ]]; then
    test_pass
else
    test_fail "Discover guidance does not consistently use SYNTHESIS_FILE in: ${guidance_failures[*]}"
fi
test_summary
