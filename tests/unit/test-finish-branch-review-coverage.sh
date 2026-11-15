#!/usr/bin/env bash
# Exercise the actual branch-review recipe with disposable repositories.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$PROJECT_ROOT" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
failures = []
controls = 0
for tree in ('.claude/skills', 'skills'):
    text = (root / tree / 'skill-finish-branch/SKILL.md').read_text()
    section = text.split('**Always run a quick review', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for scenario in ('text', 'long text', 'binary added', 'binary removed',
                     'binary attribute', 'forced text binary', 'gitlink added', 'gitlink removed',
                     'gitlink updated', 'oversized', 'relative config',
                     'external diff', 'textconv', 'shadow stdlib', 'head changed', 'reviewer failed'):
        with tempfile.TemporaryDirectory(prefix='branch-review-') as temporary:
            project = Path(temporary) / 'project'
            project.mkdir()
            environment = {name: value for name, value in os.environ.items()
                           if not name.startswith('GIT_')}
            environment.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                               GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                               GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
            def git(*args):
                return subprocess.check_output(['git', '-C', str(project), *args],
                                               env=environment, stderr=subprocess.DEVNULL, text=True).strip()
            git('init', '-q', '-b', 'main')
            git('config', 'core.hooksPath', os.devnull)
            (project / 'seed.txt').write_text('seed\n')
            if scenario == 'binary removed':
                (project / 'asset.bin').write_bytes(b'original\0binary')
            git('add', '.')
            git('commit', '-qm', 'baseline')
            base = git('rev-parse', 'HEAD')
            if scenario in ('gitlink removed', 'gitlink updated'):
                git('update-index', '--add', '--cacheinfo', '160000,' + base + ',nested')
                git('commit', '-qm', 'submodule baseline')
            git('switch', '-qc', 'feature')
            (project / 'change.txt').write_text('reviewed content\n')
            if scenario == 'long text':
                (project / 'change.txt').write_text(''.join(f'line {i}\n' for i in range(600)) + 'FINAL_REVIEW_MARKER\n')
            elif scenario == 'oversized':
                (project / 'change.txt').write_text('x' * 65000 + '\n')
            elif scenario == 'binary added':
                (project / 'asset.bin').write_bytes(b'new\0binary')
            elif scenario == 'binary removed':
                (project / 'asset.bin').unlink()
            elif scenario == 'forced text binary':
                (project / '.gitattributes').write_text('asset.bin diff\n')
                (project / 'asset.bin').write_bytes(b'forced\0binary')
            elif scenario == 'binary attribute':
                (project / '.gitattributes').write_text('change.txt -diff\n')
            elif scenario == 'shadow stdlib':
                (project / 'subprocess.py').write_text('raise RuntimeError("project stdlib shadow executed")\n')
            elif scenario in ('external diff', 'textconv'):
                (project / '.gitattributes').write_text('change.txt diff=fixture\n')
            git('add', '.')
            if scenario == 'gitlink added':
                git('update-index', '--add', '--cacheinfo', '160000,' + base + ',nested')
            elif scenario == 'gitlink removed':
                git('update-index', '--force-remove', 'nested')
            elif scenario == 'gitlink updated':
                git('update-index', '--add', '--cacheinfo', '160000,' + git('rev-parse', 'HEAD') + ',nested')
            git('commit', '-qm', 'feature')
            plugin = Path(temporary) / 'plugin'
            (plugin / 'scripts').mkdir(parents=True)
            launcher = plugin / 'scripts/orchestrate.sh'
            launcher.write_text('#!/usr/bin/env python3\nimport json, os, subprocess, sys\n'
                                'assert os.environ.get("OCTOPUS_OVERSIZE_STRATEGY") == "fail"\n'
                                'with open(os.environ["REVIEW_CAPTURE"], "w") as output:\n'
                                '    json.dump(sys.argv[1:], output)\n'
                                'if os.environ["REVIEW_SCENARIO"] == "head changed":\n'
                                '    subprocess.run(["git", "commit", "--allow-empty", "-qm", "concurrent change"], check=True)\n'
                                'if os.environ["REVIEW_SCENARIO"] == "reviewer failed":\n'
                                '    sys.exit(7)\n')
            launcher.chmod(0o755)
            capture = Path(temporary) / 'review.json'
            marker = Path(temporary) / 'diff-driver-executed'
            driver = Path(temporary) / 'driver.sh'
            driver.write_text('#!/bin/sh\ntouch "$REVIEW_DRIVER_MARKER"\nprintf "hidden\\n"\n')
            driver.chmod(0o755)
            if scenario == 'external diff':
                environment['GIT_EXTERNAL_DIFF'] = str(driver)
            elif scenario == 'textconv':
                git('config', 'diff.fixture.textconv', str(driver))
            elif scenario.startswith('gitlink'):
                git('config', 'diff.ignoreSubmodules', 'all')
            git('config', 'color.ui', 'always')
            cwd = project
            if scenario == 'relative config':
                git('config', 'diff.relative', 'true')
                cwd = project / 'subdirectory'
                cwd.mkdir()
            environment.update(CLAUDE_PLUGIN_ROOT=str(plugin), REVIEW_CAPTURE=str(capture),
                               REVIEW_DRIVER_MARKER=str(marker), REVIEW_SCENARIO=scenario)
            result = subprocess.run(['bash', '-c', recipe], cwd=cwd, env=environment,
                                    capture_output=True, text=True, timeout=10)
            blocked = scenario.startswith(('binary', 'gitlink')) or scenario in ('oversized', 'forced text binary')
            valid = result.returncode != 0 and not capture.exists() if blocked else (
                result.returncode == 0 and capture.exists() and not marker.exists())
            if scenario in ('head changed', 'reviewer failed'):
                valid = result.returncode != 0 and capture.exists()
            if valid and not blocked and scenario not in ('head changed', 'reviewer failed'):
                arguments = json.loads(capture.read_text())
                valid = (arguments[:2] == ['spawn', 'reviewer'] and '+reviewed content' in arguments[2]
                         if scenario != 'long text' else 'FINAL_REVIEW_MARKER' in arguments[2])
            if not valid:
                failures.append(f'{tree}: {scenario}: rc={result.returncode}, dispatched={capture.exists()}')
            controls += 1
if failures:
    raise SystemExit('\n'.join(failures))
print(f'{controls} production branch-review coverage controls passed')
PY
