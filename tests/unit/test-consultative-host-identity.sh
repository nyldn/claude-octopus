#!/usr/bin/env bash
# No model launches: exercise host admission and the shipped debate gate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Consultative host identity"
test_case "only a native allowed Sonnet route with a completed artifact counts"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys

root, temporary = map(Path, sys.argv[1:])
base_env = {'PATH': os.environ['PATH'], 'OCTOPUS_CONFIG_DIR': str(temporary / 'config')}
response = temporary / 'rounds/r001_sonnet.md'
response.parent.mkdir()
response.write_text('completed native Sonnet answer\n')
library = root / 'scripts/lib/consultative-advisors.sh'
checks = 0

def run(code, markers):
    return subprocess.run(['bash', '-c', 'source "$1" || exit 1\n' + code,
                           'fixture', str(library)], env=dict(base_env, **markers),
                          capture_output=True, text=True, timeout=10)

codex = {'CODEX_THREAD_ID': 'fixture', 'CLAUDE_PLUGIN_ROOT': str(root)}
claude = {'CLAUDECODE': '1', 'CLAUDE_PLUGIN_ROOT': str(root)}
for markers, required in ((codex, '2'), (claude, '1'), ({}, '2'),
                          (dict(claude, OCTO_ALLOWED_PROVIDERS='codex'), '2')):
    result = run('octo_consultative_required_external_count', markers)
    assert result.returncode == 0 and result.stdout.strip() == required, (markers, result.stdout)
    result = run('octo_consultative_provider_count_is_sufficient 1 1 "$RESULT"',
                 dict(markers, RESULT=str(response)))
    assert (result.returncode == 0) == (required == '1'), (markers, result.stderr)
    assert run('octo_consultative_provider_count_is_sufficient 2 0', markers).returncode == 0
    checks += 3

for value in ('2', '01', '-1', 'bogus'):
    assert run('octo_consultative_provider_count_is_sufficient 1 "$COUNT" "$RESULT"',
               dict(claude, COUNT=value, RESULT=str(response))).returncode != 0
    checks += 1

empty = temporary / 'empty'
empty.touch()
linked = temporary / 'linked'
linked.symlink_to(response)
for artifact in (temporary / 'missing', empty, linked):
    assert run('octo_consultative_provider_count_is_sufficient 1 1 "$RESULT"',
               dict(claude, RESULT=str(artifact))).returncode != 0, artifact
    checks += 1

# Execute the final minimum check from every shipped debate recipe. The host
# flag alone must never let a Codex task claim the Sonnet identity.
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    text = (root / tree / 'skill-debate/SKILL.md').read_text()
    blocks = re.findall(r'```bash\n(.*?)\n```', text, re.S)
    gate = next(block for block in blocks if 'if ! octo_consultative_provider_count_is_sufficient' in block)
    gate = '\n'.join(line for line in gate.splitlines() if not line.startswith('export '))
    for markers, external, host, expected in ((codex, '1', '1', False),
                                             (codex, '2', '0', True),
                                             (claude, '1', '1', True)):
        result = run(gate, dict(markers, DEBATE_DIR=str(temporary),
                               SUCCESSFUL_EXTERNAL_ADVISORS=external, HOST_ADVISOR_SUCCESS=host))
        assert (result.returncode == 0) == expected, (tree, markers, result.stderr)
        checks += 1
    response.unlink()
    assert run(gate, dict(claude, DEBATE_DIR=str(temporary),
                         SUCCESSFUL_EXTERNAL_ADVISORS='1', HOST_ADVISOR_SUCCESS='1')).returncode != 0
    response.write_text('completed native Sonnet answer\n')
    checks += 1
print(f'{checks} host admission, artifact and production gate checks passed')
PY
then test_pass; else test_fail "unverified host identity or result admitted"; fi
test_summary
