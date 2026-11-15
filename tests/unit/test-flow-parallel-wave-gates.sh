#!/usr/bin/env bash
# Execute the shipped wave monitor with inert workers, never live providers.
set -euo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Parallel wave success gates"
test_case "failed, missing and timed-out prerequisites stop dependent launches"
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
for tree in ('.claude/skills', 'skills'):
    text = (root / tree / 'flow-parallel/SKILL.md').read_text()
    section = text.split('**Wave-based launch sequence:**', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for scenario in ('success', 'failed', 'missing status', 'invalid status',
                     'timeout', 'missing dependency', 'failed dependency'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            project = Path(temporary)
            parallel = project / '.octo/parallel'
            binary = project / 'bin'
            binary.mkdir()
            # Preserve the real timeout recipe while advancing only its clock.
            date = binary / 'date'
            date.write_text('''#!/bin/bash
if [[ "${WAVE_SCENARIO:-}" == timeout && "$1" == +%s ]]; then
  tick=$(cat "$WAVE_CLOCK" 2>/dev/null || echo 0)
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
            dependency = 'WP-0' if 'dependency' in scenario else 'WP-1'
            packages = [dict(id='WP-1', wave=1, dependencies=[]),
                        dict(id='WP-2', wave=2, dependencies=[dependency])]
            for number in (1, 2):
                directory = parallel / f'WP-{number}'
                directory.mkdir(parents=True)
                (directory / 'instructions.md').write_text('original instructions\n')
                code = '7' if scenario == 'failed' else 'invalid' if scenario == 'invalid status' else '0'
                script = 'cd "$(dirname "$0")" || exit 1\nprintf "launched\\n" > launched\n'
                script += 'printf "retained worker evidence\\n" > output.md\n'
                if number == 2 or scenario != 'timeout':
                    if number == 2 or scenario != 'missing status':
                        script += f'printf "%s\\n" "{code if number == 1 else "0"}" > exit-code\n'
                    script += 'touch .done\n'
                (directory / 'launch.sh').write_text(script)
            (parallel / 'wbs.json').write_text(json.dumps(dict(work_packages=packages)))
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
            if scenario != 'success':
                valid = (result.returncode != 0 and not (second / 'launched').exists()
                         and (second / 'instructions.md').read_text() == 'original instructions\n'
                         and 'All waves executed.' not in result.stdout)
            if not valid:
                failures.append(f'{tree}: {scenario}: rc={result.returncode}, '
                                f'dependent launched={(second / "launched").exists()}\n'
                                + result.stdout + result.stderr)
            checks += 1
if failures:
    raise SystemExit('\n'.join(failures))
print(f'{checks} production wave controls passed')
PY
then test_pass; else test_fail "wave monitor advanced without successful prerequisites"; fi
test_summary
