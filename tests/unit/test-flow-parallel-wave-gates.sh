#!/usr/bin/env bash
# Execute the shipped wave monitor with inert workers, never live providers.
set -euo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Parallel wave success gates"
test_case "invalid plans stop launch and unsuccessful prerequisites stop dependent waves"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
checks = 0
bad_plans = ('missing WBS', 'malformed WBS', 'empty WBS', 'invalid wave',
             'duplicate package', 'same-wave dependency', 'invalid dependency list')
successful_plans = ('success', 'late success', 'legacy wave default', 'plan replaced after admission')
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    text = (root / tree / 'flow-parallel/SKILL.md').read_text()
    section = text.split('**Wave-based launch sequence:**', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for scenario in ('success', 'failed', 'missing status', 'invalid status',
                     'timeout', 'missing dependency', 'failed dependency',
                     'final failed', 'final missing status', 'final invalid status',
                     *successful_plans[1:], *bad_plans):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            project = Path(temporary)
            parallel = project / '.octo/parallel'
            binary = project / 'bin'
            binary.mkdir()
            # Preserve the real timeout recipe while advancing only its clock.
            date = binary / 'date'
            date.write_text('''#!/bin/bash
if [[ "${WAVE_SCENARIO:-}" == "plan replaced after admission" && "$1" == +%H:%M:%S ]]; then
  printf '{' > .octo/parallel/wbs.json
fi
if [[ "${WAVE_SCENARIO:-}" == timeout || "${WAVE_SCENARIO:-}" == "late success" ]] && [[ "$1" == +%s ]]; then
  tick=$(cat "$WAVE_CLOCK" 2>/dev/null || echo 0)
  if [[ "$WAVE_SCENARIO" == "late success" ]]; then
    # The monitor calls date before scanning markers for each new wave.
    for pid_file in .octo/parallel/WP-*/pid; do
      [[ -f "$pid_file" ]] || continue
      for attempt in {1..100}; do
        [[ -f "${pid_file%/pid}/.done" ]] && break
        /bin/sleep 0.01
      done
      [[ -f "${pid_file%/pid}/.done" ]] || exit 1
    done
  fi
  echo "$tick"
  echo "$((tick + 1000))" > "$WAVE_CLOCK"
else
  exec /bin/date "$@"
fi
''')
            date.chmod(0o755)
            sleep = binary / 'sleep'
            sleep.write_text('#!/bin/bash\nexec /bin/sleep 0.01\n')
            sleep.chmod(0o755)
            dependency = 'WP-0' if scenario in ('missing dependency', 'failed dependency') else 'WP-1'
            packages = [dict(id='WP-1', wave=1, dependencies=[]),
                        dict(id='WP-2', wave=2, dependencies=[dependency])]
            for number in (1, 2):
                directory = parallel / f'WP-{number}'
                directory.mkdir(parents=True)
                (directory / 'instructions.md').write_text('original instructions\n')
                status_case = scenario.removeprefix('final ')
                affected = number == (2 if scenario.startswith('final ') else 1)
                code = '7' if status_case == 'failed' else 'invalid' if status_case == 'invalid status' else '0'
                script = 'cd "$(dirname "$0")" || exit 1\nprintf "launched\\n" > launched\n'
                if scenario == 'late success':
                    script += '/bin/sleep 0.05\n'
                script += 'printf "retained worker evidence\\n" > output.md\n'
                if number == 2 or scenario != 'timeout':
                    if not affected or status_case != 'missing status':
                        script += f'printf "%s\\n" "{code if affected else "0"}" > exit-code\n'
                    script += 'touch .done\n'
                (directory / 'launch.sh').write_text(script)
            wbs = parallel / 'wbs.json'
            if scenario == 'legacy wave default':
                for package in packages:
                    package.pop('wave')
                    package.pop('dependencies')
            elif scenario == 'invalid wave':
                packages[1]['wave'] = 0
            elif scenario == 'duplicate package':
                packages[1]['id'] = packages[0]['id']
            elif scenario == 'same-wave dependency':
                packages[1]['wave'] = packages[0]['wave']
            elif scenario == 'invalid dependency list':
                packages[1]['dependencies'] = 'WP-1'

            if scenario == 'malformed WBS':
                wbs.write_text('{')
            elif scenario == 'empty WBS':
                wbs.write_text(json.dumps(dict(work_packages=[])))
            elif scenario != 'missing WBS':
                wbs.write_text(json.dumps(dict(work_packages=packages)))
            if scenario == 'failed dependency':
                extra = parallel / 'WP-0'
                extra.mkdir()
                (extra / '.done').touch()
                (extra / 'exit-code').write_text('9\n')
                (extra / 'output.md').write_text('failed prerequisite output\n')
            env = dict(os.environ, PATH=str(binary) + ':' + os.environ['PATH'],
                       WAVE_SCENARIO=scenario, WAVE_CLOCK=str(project / 'clock'),
                       CLAUDE_PLUGIN_ROOT=str(project / 'inert-plugin'),
                       CODEX_PLUGIN_ROOT=str(project / 'inert-plugin'))
            result = subprocess.run(['bash', '-c', recipe], cwd=project, env=env,
                                    capture_output=True, text=True, timeout=10)
            second = parallel / 'WP-2'
            valid = result.returncode == 0 and (second / 'launched').exists()
            if scenario.startswith('final '):
                valid = (result.returncode != 0 and (second / 'launched').exists()
                         and 'All waves executed.' not in result.stdout)
            elif scenario not in successful_plans:
                valid = (result.returncode != 0 and not (second / 'launched').exists()
                         and (second / 'instructions.md').read_text() == 'original instructions\n'
                         and 'All waves executed.' not in result.stdout)
            if scenario in bad_plans:
                valid = (valid and not (parallel / 'WP-1/launched').exists()
                         and not (parallel / 'WP-1/pid').exists())
            if scenario == 'same-wave dependency':
                valid = valid and 'WP-2 needs all dependencies in earlier waves' in result.stderr
            if not valid:
                failures.append(f'{tree}: {scenario}: rc={result.returncode}, '
                                f'dependent launched={(second / "launched").exists()}\n'
                                + result.stdout + result.stderr)
            checks += 1
if failures:
    raise SystemExit('\n'.join(failures))
print(f'{checks} production wave controls passed')
PY
then test_pass; else test_fail "wave monitor accepted an invalid plan or advanced without successful prerequisites"; fi
test_summary
