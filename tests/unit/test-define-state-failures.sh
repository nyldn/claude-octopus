#!/usr/bin/env bash
# Run the production Define state recipe under failed writes and partial retries.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Define definition state failures"
test_case "failed state writes stop before later writes or completion"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
checked = 0
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'flow-define/SKILL.md'
    if not entry.exists():
        if tree == 'codex-skills':
            continue
        raise AssertionError(f'Missing maintained skill entry: {entry}')
    text = entry.read_text()
    section = text.split('### STEP 6:', 1)[1].split('### STEP 7:', 1)[0]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for strict in (False, True):
        for conditional in (False, True):
            for scenario in ('success', 'init_project', 'update_roadmap', 'update_state', 'complete_define', 'missing', 'empty', 'persistence off', 'headingless', 'whitespace'):
                with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                    temporary = Path(temporary)
                    plugin = temporary / 'plugin'
                    (plugin / 'scripts').mkdir(parents=True)
                    calls = temporary / 'calls'
                    synthesis = temporary / 'synthesis.md'
                    if scenario != 'missing':
                        synthesis.write_text('  \n\t' if scenario == 'whitespace' else 'plain requirements without a heading' if scenario == 'headingless' else
                                             '## Problem Definition\nselected the approach\n' if scenario != 'empty' else '')
                    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(plugin), CODEX_PLUGIN_ROOT=str(plugin),
                               SYNTHESIS_FILE=str(synthesis), STATE_CALLS=str(calls), FAIL_OPERATION=scenario,
                               OCTOPUS_WORKFLOW_STATE_DIR=str(temporary / 'state'),
                               REAL_STATE_MANAGER=str(root / 'scripts/state-manager.sh'),
                               OCTOPUS_PROJECT_PERSISTENCE='false' if scenario == 'persistence off' else 'true')
                    subprocess.run([env['REAL_STATE_MANAGER'], 'init_state'], env=env, cwd=temporary,
                                   capture_output=True, check=True)
                    for name in ('octo-state.sh', 'state-manager.sh'):
                        helper = plugin / 'scripts' / name
                        helper.write_text('#!/bin/sh\n'
                                          'printf "%s\\n" "$1" >> "$STATE_CALLS"\n'
                                          '[ "$1" != "$FAIL_OPERATION" ] || exit 23\n' +
                                          ('exec "$REAL_STATE_MANAGER" "$@"\n' if name == 'state-manager.sh' else 'exit 0\n'))
                        helper.chmod(0o755)
                    program = recipe + '\nprintf "completion reached\\n"'
                    if conditional:
                        program = '(\n' + program + '\n) && exit 0; exit $?'
                    succeeds = scenario in ('success', 'persistence off', 'headingless')
                    attempts = 2 if succeeds else 1
                    for attempt in range(attempts):
                        command = ['bash', '-euo', 'pipefail', '-c', program] if strict else ['bash', '-c', program]
                        result = subprocess.run(command,
                                                env=env, cwd=temporary, capture_output=True, text=True, timeout=10)
                        state = json.loads((temporary / 'state/state.json').read_text())
                        operations = (['complete_define'] if scenario == 'persistence off' else
                                      ['init_project', 'update_roadmap', 'complete_define', 'update_state'])
                        expected = (operations if succeeds else [] if scenario in ('missing', 'empty', 'whitespace')
                                    else operations[:operations.index(scenario) + 1])
                        observed = calls.read_text().splitlines() if calls.exists() else []
                        completed = succeeds or scenario == 'update_state'
                        valid = ((result.returncode == 0) == succeeds and
                                 observed == expected * (attempt + 1) and
                                 ('completion reached' in result.stdout) == succeeds and
                                 state['metrics']['phases_completed'] == int(completed) and
                                 len(state['decisions']) == int(completed and scenario != 'headingless') and
                                 (not completed or state['context']['define'].strip() ==
                                  ('plain requirements without a heading' if scenario == 'headingless' else '## Problem Definition selected the approach')))
                        if not valid:
                            failures.append(f'{tree}: {scenario}, strict={strict}, conditional={conditional}, '
                                            f'attempt={attempt}, exit={result.returncode}, calls={observed}, state={state}')
                        checked += 1
    # Completion effects must follow the executable persistence step in the contract.
    valid_order = (text.index('### STEP 6:') < text.index('complete_define') < text.index('### STEP 7:') and
                   'ONLY after synthesis validation and every Step 6 persistence operation succeeds' in text)
    if not valid_order:
        failures.append(f'{tree}: presentation or task completion precedes persistence')
    checked += 1
# Exercise the production transaction with optional decisions, distinct runs,
# changed synthesis content and a rejected atomic publication.
with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
    directory = Path(temporary)
    helper = root / 'scripts/state-manager.sh'
    env = dict(os.environ, OCTOPUS_WORKFLOW_STATE_DIR=str(directory / 'state'))
    subprocess.run([str(helper), 'init_state'], env=env, capture_output=True, check=True)
    synthesis = directory / 'synthesis.md'
    synthesis.write_text('plain requirements')
    for path, content, expected in ((synthesis, 'plain requirements', 1),
                                    (synthesis, 'plain requirements', 1),
                                    (directory / 'second.md', 'plain requirements', 2),
                                    (synthesis, 'revised requirements', 3),
                                    (synthesis, 'plain requirements', 3)):
        path.write_text(content)
        result = subprocess.run([str(helper), 'complete_define', str(path), content, ''],
                                env=env, capture_output=True, text=True)
        state = json.loads((directory / 'state/state.json').read_text())
        if result.returncode != 0 or state['metrics']['phases_completed'] != expected or state['decisions'] or state['context']['define'] != content:
            failures.append(f'optional decision or synthesis identity: {expected}, {result.returncode}, {state}')
        checked += 1
    state_file = directory / 'state/state.json'
    before = state_file.read_bytes()
    synthesis.write_text('unpublished requirements')
    for operation in ('python3', 'jq', 'atomic_write', 'cp', 'mv', 'printf'):
        for conditional in (False, True):
            state_file.write_bytes(before)
            call = 'complete_define "$2" "unpublished context" "new decision"'
            if conditional:
                call = 'if ' + call + '; then exit 0; else exit $?; fi'
            marker = directory / 'injected-operation'
            if marker.exists():
                marker.unlink()
            injected_env = dict(env, FAILURE_MARKER=str(marker))
            if operation == 'python3':
                injection = 'python3() { if [[ "${1:-}" == -I ]]; then command touch "$FAILURE_MARKER"; return 23; fi; command python3 "$@"; }; '
            elif operation == 'printf':
                injection = r'printf() { if [[ "${2:-}" == \{* ]]; then command touch "$FAILURE_MARKER"; return 23; fi; builtin printf "$@"; }; '
            else:
                injection = operation + '() { command touch "$FAILURE_MARKER"; return 23; }; '
            result = subprocess.run(['bash', '-c', 'source "$1"; ' + injection + call,
                                     'test', str(helper), str(synthesis)], env=injected_env, capture_output=True, text=True)
            if not marker.exists():
                failures.append(f'{operation} injection never reached its intended operation, conditional={conditional}')
            if result.returncode == 0 or state_file.read_bytes() != before or 'Recorded Define completion' in result.stdout:
                failures.append(f'{operation} failure accepted, conditional={conditional}')
            if operation in ('cp', 'mv', 'printf') and list(state_file.parent.glob('state.json.tmp.*')):
                failures.append(f'{operation} failure left unpublished temporary state')
            checked += 1
# Execute both production helpers from a fresh project, with persistence unset,
# disabled and enabled, including replay after a failed project status write.
for persistence in (None, 'false', 'true'):
    with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
        directory = Path(temporary)
        synthesis = directory / 'synthesis.md'
        synthesis.write_text('## Problem Definition\nselected the approach\n')
        env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(root), CODEX_PLUGIN_ROOT=str(root),
                   SYNTHESIS_FILE=str(synthesis), OCTOPUS_WORKFLOW_STATE_DIR=str(directory / 'state'))
        env.pop('OCTOPUS_PROJECT_PERSISTENCE', None)
        if persistence is not None:
            env['OCTOPUS_PROJECT_PERSISTENCE'] = persistence
        subprocess.run([str(helper), 'init_state'], env=env, cwd=directory, capture_output=True, check=True)
        for attempt in range(2):
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', recipe], env=env, cwd=directory, capture_output=True, text=True)
            state = json.loads((directory / 'state/state.json').read_text())
            project_state = directory / '.octo/STATE.md'
            phase_status = subprocess.run([str(root / 'scripts/octo-state.sh'), 'get_phase_status', '2'],
                                          env=env, cwd=directory, capture_output=True, text=True)
            valid_project = (project_state.exists() and '**Status:** complete' in project_state.read_text()
                             and '**Current Phase:** 2' in project_state.read_text()
                             and '**Current Position:** Definition' in project_state.read_text()
                             and phase_status.returncode == 0 and phase_status.stdout.strip() == 'complete'
                             if persistence == 'true' else not (directory / '.octo').exists())
            if result.returncode or not valid_project or state['metrics']['phases_completed'] != 1 or len(state['decisions']) != 1:
                failures.append(f'actual helpers: persistence={persistence}, attempt={attempt}, exit={result.returncode}')
            checked += 1
# A failed first roadmap publication must recover through the same recipe.
for tree in ('.claude/skills', 'skills'):
    entry = root / tree / 'flow-define/SKILL.md'
    section = entry.read_text().split('### STEP 6:', 1)[1].split('### STEP 7:', 1)[0]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
        directory = Path(temporary)
        synthesis = directory / 'synthesis.md'
        synthesis.write_text('## Problem Definition\nselected the recovery approach\n')
        env = dict(os.environ, CLAUDE_PLUGIN_ROOT=str(root), CODEX_PLUGIN_ROOT=str(root),
                   SYNTHESIS_FILE=str(synthesis), OCTOPUS_PROJECT_PERSISTENCE='true',
                   OCTOPUS_WORKFLOW_STATE_DIR=str(directory / 'state'))
        subprocess.run([str(helper), 'init_state'], env=env, cwd=directory, capture_output=True, check=True)
        shim = directory / 'bin'
        shim.mkdir()
        mover = shim / 'python3'
        mover.write_text('#!/bin/sh\n[ "${3:-}" != ".octo/ROADMAP.md" ] || exit 23\n'
                         'exec "' + shutil.which('python3') + '" "$@"\n')
        mover.chmod(0o755)
        failed_env = dict(env, PATH=str(shim) + os.pathsep + env['PATH'])
        program = recipe + '\nprintf "completion reached\\n"'
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', program], env=failed_env,
                                cwd=directory, capture_output=True, text=True, timeout=10)
        state_file = directory / '.octo/STATE.md'
        project_file = directory / '.octo/PROJECT.md'
        if result.returncode == 0 or not state_file.is_file() or (directory / '.octo/ROADMAP.md').exists():
            failures.append(f'{tree}: initial roadmap publication did not fail partially')
        checked += 1
        # Keep user edits in both already-published files during initialization.
        state_file.write_text(state_file.read_text() + '\nRetained state note\n')
        project_file.write_text('Retained project vision\n')
        state_before = state_file.read_bytes()
        project_before = project_file.read_bytes()
        initialized = subprocess.run([str(root / 'scripts/octo-state.sh'), 'init_project'], env=env,
                                     cwd=directory, capture_output=True, text=True, timeout=10)
        if (initialized.returncode or not (directory / '.octo/ROADMAP.md').is_file() or
                state_file.read_bytes() != state_before or project_file.read_bytes() != project_before):
            failures.append(f'{tree}: init retry did not restore missing files while preserving existing files')
        checked += 1
        for attempt in range(2):
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', program], env=env,
                                    cwd=directory, capture_output=True, text=True, timeout=10)
            state = json.loads((directory / 'state/state.json').read_text())
            if (result.returncode or 'completion reached' not in result.stdout or
                    state['metrics']['phases_completed'] != 1 or len(state['decisions']) != 1 or
                    'Retained state note' not in state_file.read_text() or
                    project_file.read_bytes() != project_before):
                failures.append(f'{tree}: partial-init recipe retry {attempt} failed or duplicated completion')
            checked += 1
# Shell echo options must not change JSON string escapes during publication.
with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
    directory = Path(temporary)
    env = dict(os.environ, OCTOPUS_WORKFLOW_STATE_DIR=str(directory / 'state'))
    subprocess.run([str(helper), 'init_state'], env=env, capture_output=True, check=True)
    synthesis = directory / 'synthesis.md'
    synthesis.write_text('literal backslash context')
    context = r'keep C:\new\temp and literal \t unchanged'
    result = subprocess.run(['bash', '-c', 'source "$1"; shopt -s xpg_echo; complete_define "$2" "$3" ""',
                             'test', str(helper), str(synthesis), context], env=env, capture_output=True, text=True)
    state = json.loads((directory / 'state/state.json').read_text())
    if result.returncode or state['context']['define'] != context:
        failures.append('shell echo options changed literal JSON content')
    checked += 1
print(f'{checked - len(failures)}/{checked} actual Define persistence/retry controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "Define continued after failed definition-state writes"; fi
test_summary
