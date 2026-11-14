#!/usr/bin/env bash
# Run aggregation in a fresh shell, independent of the launch shell's locals.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Parallel result summary"
test_case "aggregation restores its package count and reports every worker"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
checks = 0
for tree in ('.claude/skills', 'skills'):
    text = (root / tree / 'flow-parallel/SKILL.md').read_text()
    section = text.split('### STEP 7: Aggregate & Present', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for mode in ('fresh', 'stale', 'missing-exit', 'invalid-json', 'wrong-type', 'missing-wbs'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            project = Path(temporary)
            output = project / '.octo/parallel'
            output.mkdir(parents=True)
            wbs = output / 'wbs.json'
            wbs.write_text(json.dumps({'work_packages': [{'id': 'WP-1'}, {'id': 'WP-2'}]}))
            for number, code in ((1, '0'), (2, '7')):
                worker = output / f'WP-{number}'
                worker.mkdir()
                (worker / 'output.md').write_text(f'worker {number} evidence\n')
                (worker / 'exit-code').write_text(code)
            if mode == 'missing-exit':
                (output / 'WP-2/exit-code').unlink()
            elif mode == 'invalid-json':
                wbs.write_text('{')
            elif mode == 'wrong-type':
                wbs.write_text('{"work_packages": {"WP-1": {}}}')
            elif mode == 'missing-wbs':
                wbs.unlink()
            env = dict(os.environ)
            env.pop('WP_COUNT', None)
            if mode == 'stale':
                env['WP_COUNT'] = '99'
            before = {str(p): p.read_bytes() for p in output.rglob('*') if p.is_file()}
            result = subprocess.run(['/bin/bash', '-eu', '-c', recipe], cwd=project,
                                    env=env, capture_output=True, text=True, timeout=5)
            if mode in ('fresh', 'stale', 'missing-exit'):
                assert result.returncode == 0, (tree, mode, result.stderr)
                assert 'WP-1: SUCCESS' in result.stdout, (tree, mode, result.stdout)
                assert 'WP-2: FAILED' in result.stdout, (tree, mode, result.stdout)
                assert 'Total: 2 | Succeeded: 1 | Failed: 1' in result.stdout, result.stdout
                assert 'WP-3:' not in result.stdout, result.stdout
            else:
                assert result.returncode != 0, (tree, mode, result.stdout)
                assert '=== SUMMARY ===' not in result.stdout, (tree, mode, result.stdout)
            assert before == {str(p): p.read_bytes() for p in output.rglob('*') if p.is_file()}
            checks += 1
print(f'{checks} executable parallel aggregation scenarios passed')
PY
then test_pass; else test_fail "parallel aggregation lost worker results or accepted an invalid WBS"; fi
test_summary
