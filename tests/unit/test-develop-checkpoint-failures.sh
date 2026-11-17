#!/usr/bin/env bash
# Execute authored/generated checkpoint recipes through success and write failures.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Develop checkpoint failures"
test_case "checkpoint and state failures stop development completion"
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
    section = entry.read_text().split('## Post-Development: Checkpoint', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for strict in (False, True):
        for nested in (False, True):
            for scenario in ('success', 'unborn', 'tag collision', 'state failure', 'history failure'):
                with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
                    temporary = Path(temporary)
                    project = temporary / 'project'
                    project.mkdir()
                    plugin = temporary / 'plugin'
                    (plugin / 'scripts').mkdir(parents=True)
                    state_calls = temporary / 'state-calls'
                    state = plugin / 'scripts/octo-state.sh'
                    state.write_text('#!/usr/bin/env bash\n'
                                     'printf "%s\\n" "$*" >> "$STATE_CALLS"\n'
                                     'if [[ "$FAIL_STATE" == yes && "$*" == *--status* ]]; then exit 23; fi\n'
                                     'if [[ "$FAIL_HISTORY" == yes && "$*" == *"Files modified:"* ]]; then exit 24; fi\n')
                    state.chmod(0o755)
                    binaries = temporary / 'bin'
                    binaries.mkdir()
                    date = binaries / 'date'
                    date.write_text('#!/bin/sh\nprintf "20261117-071700\\n"\n')
                    date.chmod(0o755)
                    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
                    env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                               GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                               GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
                               CLAUDE_PLUGIN_ROOT=str(plugin), CODEX_PLUGIN_ROOT=str(plugin),
                               STATE_CALLS=str(state_calls), FAIL_STATE='yes' if scenario == 'state failure' else 'no',
                               FAIL_HISTORY='yes' if scenario == 'history failure' else 'no',
                               PATH=str(binaries) + os.pathsep + env['PATH'])

                    def git(*args):
                        return subprocess.check_output(['git', *args], cwd=project, env=env,
                                                       stderr=subprocess.DEVNULL, text=True).strip()

                    git('init', '-q', '-b', 'main')
                    tag = 'octo-checkpoint-post-develop-20261117-071700'
                    if scenario != 'unborn':
                        (project / 'source.txt').write_text('committed source\n')
                        git('add', 'source.txt')
                        git('commit', '-qm', 'source')
                    if scenario == 'tag collision':
                        git('tag', '-a', tag, '-m', 'preserve existing checkpoint')
                    before_tags = git('show-ref', '--tags') if scenario == 'tag collision' else ''
                    cwd = project / 'nested' if nested else project
                    cwd.mkdir(exist_ok=True)
                    result = subprocess.run(['bash', '-eu' if strict else '-c'] +
                                            (['-c'] if strict else []) +
                                            [recipe + '\nprintf "recipe completed\\n"'],
                                            cwd=cwd, env=env, capture_output=True, text=True, timeout=10)
                    calls = state_calls.read_text().splitlines() if state_calls.exists() else []
                    expected_calls = (0 if scenario in ('unborn', 'tag collision') else
                                      1 if scenario == 'state failure' else 2)
                    valid = ((result.returncode == 0) == (scenario == 'success')
                             and ('recipe completed' in result.stdout) == (scenario == 'success')
                             and len(calls) == expected_calls)
                    if scenario in ('unborn', 'tag collision'):
                        valid = valid and 'Created checkpoint:' not in result.stdout
                        valid = valid and (git('show-ref', '--tags') == before_tags if before_tags else git('tag') == '')
                    else:
                        valid = valid and git('rev-parse', tag + '^{}') == git('rev-parse', 'HEAD')
                    if not valid:
                        failures.append(f'{tree}: {scenario}, nested={nested}, strict={strict}, '
                                        f'exit={result.returncode}, state writes={len(calls)}')
                    checked += 1
print(f'{checked - len(failures)}/{checked} actual checkpoint controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "development continued after checkpoint or state failure"; fi
test_summary
