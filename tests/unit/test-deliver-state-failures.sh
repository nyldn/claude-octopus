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
        if tree == 'codex-skills':
            continue
        raise AssertionError(f'Missing maintained skill entry: {entry}')
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
test_case "fresh shells require the validated report before state writes or PR comments"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_REPORT'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
checked = 0
with tempfile.TemporaryDirectory(dir=sys.argv[2], prefix='deliver report ') as temporary:
    directory = Path(temporary)
    scripts = directory / 'scripts'
    scripts.mkdir()
    side_effect = directory / 'side effect'
    for helper, script in (
        ('state-manager.sh', 'printf "%s\\n" "$1" >> "$SIDE_EFFECT"'),
        ('safe-gh-comment.sh', 'cat >> "$SIDE_EFFECT"'),
    ):
        path = scripts / helper
        path.write_text(f'#!/bin/bash\n{script}\n')
        path.chmod(0o755)
    valid = directory / 'validated report.md'
    valid.write_text('## Status: COMPLETE\n## Summary\nPass\nValidated review\n')
    no_summary = directory / 'validated report without summary.md'
    no_summary.write_text('## Status: COMPLETE\nValidated review\n')
    empty = directory / 'empty.md'
    empty.touch()
    (directory / 'delivery-newer.md').write_text('## Summary\nPass\nUnrelated review\n')
    git_and_gh = """
git() { echo feature; }
gh() {
    case "$1 $2" in
        'pr list') echo 123 ;;
        'repo view') echo test/example ;;
        *) return 1 ;;
    esac
}
"""
    for tree in ('.claude/skills', 'skills', 'codex-skills'):
        text = (root / tree / 'flow-deliver/SKILL.md').read_text()
        for section in ('### STEP 6: Update State', '#### Post to PR'):
            recipe = re.search(r'```bash\n(.*?)\n```', text.split(section, 1)[1], re.S)[1]
            for shell in ('-c', '-euo'):
                for report in (None, '', directory / 'missing.md', directory, empty, valid, no_summary):
                    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(directory), CODEX_PLUGIN_ROOT=str(directory),
                               SIDE_EFFECT=str(side_effect))
                    env.pop('VALIDATION_FILE', None)
                    if report is not None:
                        env['VALIDATION_FILE'] = str(report)
                    flags = ['-euo', 'pipefail', '-c'] if shell == '-euo' else ['-c']
                    program = git_and_gh + '(\n' + recipe + '\nprintf "completion reached\\n"\n) && exit 0; exit $?'
                    result = subprocess.run(['bash', *flags, program], env=env, cwd=directory,
                                            capture_output=True, text=True, timeout=10)
                    effect = side_effect.read_text() if side_effect.exists() else ''
                    side_effect.unlink(missing_ok=True)
                    admitted = report in (valid, no_summary)
                    expected_effect = ('Validated review' in effect and 'Unrelated review' not in effect
                                       if section == '#### Post to PR'
                                       else effect.splitlines() == ['update_context', 'update_metrics', 'show_summary'])
                    if admitted:
                        passed = result.returncode == 0 and 'completion reached' in result.stdout and expected_effect
                    else:
                        passed = (result.returncode != 0 and 'completion reached' not in result.stdout
                                  and not effect and 'validated report' in result.stderr.lower())
                    if not passed:
                        failures.append(f'{tree}: {section}, {shell}, report={report!r}, exit={result.returncode}, '
                                        f'evidence={effect!r}, stderr={result.stderr.strip()!r}')
                    checked += 1
print(f'{checked - len(failures)}/{checked} Deliver report handoff controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_REPORT
then test_pass; else test_fail "Deliver accepted a missing or unreadable validated report"; fi
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
    corruptions = ('', ' \n\t', 'invalid JSON', original + original,
                      json.dumps(dict(json.loads(original), blockers={})),
                      json.dumps(dict(json.loads(original), blockers='active')),
                      json.dumps(dict(json.loads(original), blockers=None)),
                      json.dumps({key: value for key, value in json.loads(original).items() if key != 'blockers'}))
    for corrupted in corruptions:
        state_file.write_text(corrupted)
        result = subprocess.run([str(helper), 'show_summary'], env=env, capture_output=True, text=True)
        assert result.returncode != 0 and not result.stdout, (result.returncode, result.stdout)
    state_file.write_text(original)
    restored = subprocess.run([str(helper), 'show_summary'], env=env, capture_output=True, text=True)
    assert restored.returncode == 0 and restored.stdout == good.stdout
print(f'{len(corruptions) + 2}/{len(corruptions) + 2} production summary controls passed')
PY_SUMMARY
then test_pass; else test_fail "summary read failure was hidden"; fi
test_case "resume a failed summary without repeating successful metrics writes"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_RETRY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
helper = root / 'scripts/state-manager.sh'
for tree in ('.claude/skills', 'skills'):
    text = (root / tree / 'flow-deliver/SKILL.md').read_text()
    section = text.split('### STEP 6:', 1)[1].split('### STEP 7:', 1)[0]
    assert 'resume at the failed operation' in section
    assert 'Do not repeat successful context or' in section
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    resume = recipe.split('# Display final state summary', 1)[1]
    with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
        directory = Path(temporary)
        validation = directory / 'validation.md'
        validation.write_text('## Summary\nPass\nreview accepted\n')
        env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(root), CODEX_PLUGIN_ROOT=str(root),
                   VALIDATION_FILE=str(validation), OCTOPUS_WORKFLOW_STATE_DIR=str(directory / 'state'))
        subprocess.run([str(helper), 'init_state'], env=env, capture_output=True, check=True)
        state_file = directory / 'state/state.json'
        state = json.loads(state_file.read_text())
        state['blockers'] = None
        state_file.write_text(json.dumps(state))
        failed = subprocess.run(['bash', '-euc', recipe], env=env, capture_output=True, text=True)
        state = json.loads(state_file.read_text())
        assert failed.returncode != 0 and state['metrics']['phases_completed'] == 1
        assert state['context']['deliver'].strip() == 'Pass review accepted'
        state['blockers'] = []
        state_file.write_text(json.dumps(state))
        before = state_file.read_bytes()
        retried = subprocess.run(['bash', '-euc', resume], env=env, capture_output=True, text=True)
        assert retried.returncode == 0 and 'Active Blockers: 0' in retried.stdout
        assert state_file.read_bytes() == before, 'summary retry repeated a successful write'
print('2/2 production failed-summary resume controls passed')
PY_RETRY
then test_pass; else test_fail "summary retry repeated successful writes"; fi
test_summary
