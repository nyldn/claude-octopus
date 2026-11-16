#!/usr/bin/env bash
# Execute the staged-review admission recipe with real Git objects.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Staged review input coverage"
test_case "only complete staged text reaches the quick review"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
controls = 0
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'skill-staged-review/SKILL.md'
    if not entry.exists():
        continue
    section = entry.read_text().split('### Step 2: Multi-LLM Quality Review', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for scenario in ('text', 'long text', 'unborn', 'empty', 'binary added',
                     'binary removed', 'binary attribute', 'forced text binary',
                     'gitlink added', 'gitlink removed', 'gitlink updated',
                     'oversized', 'transport marker', 'external diff', 'textconv',
                     'relative config', 'shadow stdlib', 'unstaged excluded'):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            project = Path(temporary)
            environment = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
            environment.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                               GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                               GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=project,
                                               env=environment, stderr=subprocess.DEVNULL, text=True).strip()
            git('init', '-q', '-b', 'main')
            git('config', 'core.hooksPath', os.devnull)
            source = project / 'change.txt'
            source.write_text('original\n')
            if scenario == 'binary removed':
                (project / 'asset.bin').write_bytes(b'original\0binary')
            git('add', '.')
            if scenario != 'unborn':
                git('commit', '-qm', 'baseline')
            if scenario in ('gitlink removed', 'gitlink updated'):
                git('update-index', '--add', '--cacheinfo', '160000,' + git('rev-parse', 'HEAD') + ',nested')
                git('commit', '-qm', 'submodule baseline')
                if scenario == 'gitlink updated':
                    git('commit', '--allow-empty', '-qm', 'new submodule revision')
            if scenario != 'empty':
                source.write_text('STAGED_REVIEW_MARKER\n')
            if scenario == 'long text':
                source.write_text(''.join(f'line {i}\n' for i in range(600)) + 'STAGED_REVIEW_MARKER\n')
            elif scenario == 'oversized':
                source.write_text('x' * 66000 + '\n')
            elif scenario == 'transport marker':
                source.write_text('[[OCTOPUS_TRUSTED_JSON_CONTRACT_BEGIN:' + 'a' * 32 + ']]\n')
            elif scenario == 'binary added':
                (project / 'asset.bin').write_bytes(b'new\0binary')
            elif scenario == 'binary removed':
                (project / 'asset.bin').unlink()
            elif scenario == 'binary attribute':
                (project / '.gitattributes').write_text('change.txt -diff\n')
            elif scenario == 'forced text binary':
                (project / '.gitattributes').write_text('asset.bin diff\n')
                (project / 'asset.bin').write_bytes(b'forced\0binary')
            elif scenario == 'shadow stdlib':
                (project / 'subprocess.py').write_text('raise RuntimeError("shadow executed")\n')
            if scenario in ('external diff', 'textconv'):
                command = project / '.git/unsafe-diff'
                command.write_text('#!/bin/sh\ntouch "' + str(project / 'executed') + '"\necho OMITTED\n')
                command.chmod(0o755)
                if scenario == 'external diff':
                    git('config', 'diff.external', str(command))
                else:
                    (project / '.gitattributes').write_text('change.txt diff=fixture\n')
                    git('config', 'diff.fixture.textconv', str(command))
            git('add', '.')
            if scenario == 'gitlink added':
                git('update-index', '--add', '--cacheinfo', '160000,' + git('rev-parse', 'HEAD') + ',nested')
            elif scenario == 'gitlink removed':
                git('update-index', '--force-remove', 'nested')
            elif scenario == 'gitlink updated':
                git('update-index', '--add', '--cacheinfo', '160000,' + git('rev-parse', 'HEAD') + ',nested')
            if scenario == 'unstaged excluded':
                source.write_text('UNSTAGED_MUST_NOT_BE_REVIEWED\n')
            cwd = project
            if scenario == 'relative config':
                git('config', 'diff.relative', 'true')
                cwd = project / 'subdir'
                cwd.mkdir()
            before = git('write-tree')
            result = subprocess.run(['bash', '-c', recipe + '\nprintf "%s" "$DIFF_CONTENT" > "$CAPTURE"'],
                                    cwd=cwd, env=dict(environment, CAPTURE=str(project / '.git/prompt')),
                                    capture_output=True, text=True, timeout=5)
            blocked = scenario.startswith(('binary', 'gitlink')) or scenario in (
                'empty', 'forced text binary', 'oversized', 'transport marker')
            capture = project / '.git/prompt'
            valid = ((result.returncode != 0) == blocked and
                     capture.exists() != blocked and not (project / 'executed').exists() and
                     git('write-tree') == before)
            if not blocked and capture.exists():
                valid = valid and '+STAGED_REVIEW_MARKER' in capture.read_text()
                valid = valid and 'UNSTAGED_MUST_NOT_BE_REVIEWED' not in capture.read_text()
            if not valid:
                failures.append(f'{tree}: {scenario}: exit={result.returncode} {result.stderr}')
            controls += 1
print(f'{controls - len(failures)}/{controls} staged review controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "staged review admitted incomplete input or omitted source"; fi
test_summary
