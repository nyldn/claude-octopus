#!/usr/bin/env bash
# Execute the authored and generated state recipes without provider calls.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Debate state JSON"
test_case "debate state preserves user text and rejects invalid round counts"
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
    text = (root / tree / 'skill-debate/SKILL.md').read_text()
    section = text.split('### Step 4: Setup Debate Folder', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    # Run each recipe in a fresh shell with its ordinary setup, not a copy of
    # the serializer. Literal shell expressions must remain user data.
    for advisors in ('codex, agy', ''):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as directory:
            home = Path(directory)
            shadow = home / 'python-path'
            shadow.mkdir()
            for target in (home / 'datetime.py', home / 'pathlib.py', home / 'json.py',
                           shadow / 'sitecustomize.py', shadow / 'usercustomize.py'):
                target.write_text("open('SHADOW_MODULE_EXECUTED', 'w').write('unexpected import')\n"
                                  "raise RuntimeError('untrusted Python module imported')\n")
            context = dict(goal='Keep "quotes" and \\paths\nnext line',
                           priority='Unicode café and 🐙',
                           constraints='Keep ${HOME} and $(touch SHOULD_NOT_RUN) literal')
            question = 'Should we use "Redis"?\nCompare \\paths and tabs\there.'
            env = dict(os.environ, HOME=directory, CLAUDE_CODE_SESSION='fixture',
                       PYTHONPATH=str(shadow),
                       QUESTION=question, ROUNDS='3', STYLE='thorough', ADVISORS=advisors,
                       USER_GOAL=context['goal'], USER_PRIORITY=context['priority'],
                       USER_CONSTRAINTS=context['constraints'])
            result = subprocess.run(['/bin/bash', '-eu', '-c', recipe], cwd=home,
                                    env=env, capture_output=True, text=True, timeout=5)
            assert not (home / 'SHADOW_MODULE_EXECUTED').exists(), (tree, result.stderr)
            assert result.returncode == 0, (tree, result.stderr)
            state_file = next(home.rglob('state.json'))
            state = json.loads(state_file.read_text(encoding='utf-8'))
            assert state['question'] == question, (tree, state)
            assert state['user_context'] == context, (tree, state)
            assert state['advisors'] == (['codex', 'agy'] if advisors else []), state
            assert state['rounds_total'] == 3 and type(state['rounds_total']) is int, state
            assert state['rounds_completed'] == 0 and state['status'] == 'active', state
            assert state['debate_id'] == state_file.parent.name, state
            assert re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', state['created_at']), state
            assert not (home / 'SHOULD_NOT_RUN').exists()
            checks += 1
    for rounds in ('0', '-1', 'invalid', '1.5'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as directory:
            env = dict(os.environ, HOME=directory, CLAUDE_CODE_SESSION='fixture',
                       QUESTION='fixture', ROUNDS=rounds, STYLE='thorough', ADVISORS='codex',
                       USER_GOAL='', USER_PRIORITY='', USER_CONSTRAINTS='')
            result = subprocess.run(['/bin/bash', '-c', recipe + '\necho DEBATE_CONTINUED'],
                                    cwd=directory, env=env, capture_output=True, text=True, timeout=5)
            assert result.returncode != 0, (tree, rounds, result.stdout)
            assert 'DEBATE_CONTINUED' not in result.stdout, (tree, rounds)
            assert not list(Path(directory).rglob('state.json')), (tree, rounds)
            checks += 1
print(f'{checks} executable debate state scenarios passed')
PY
then test_pass; else test_fail "debate state recipe did not preserve valid JSON"; fi
test_summary
