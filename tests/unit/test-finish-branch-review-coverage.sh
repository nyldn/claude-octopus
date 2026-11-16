#!/usr/bin/env bash
# Exercise the actual branch-review recipe with disposable repositories.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Branch review coverage"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" > "$TEST_TMP_DIR/controls.tsv" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

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
                     'external diff', 'textconv', 'shadow stdlib', 'head changed', 'reviewer failed',
                     'async success', 'async failed', 'async head changed', 'async empty',
                     'transport marker', 'native teams', 'async inherited hook', 'async chained hook'):
        with tempfile.TemporaryDirectory(prefix='branch-review-', dir=sys.argv[2]) as temporary:
            project = Path(temporary) / 'project'
            project.mkdir()
            source_environment = dict(os.environ)
            if scenario == 'async inherited hook':
                source_environment['OCTOPUS_AGENT_LIFECYCLE_HOOK'] = str(Path(temporary) / 'previous-hook.sh')
            environment = {name: value for name, value in source_environment.items()
                           if not name.startswith('GIT_') and name != 'OCTOPUS_AGENT_LIFECYCLE_HOOK'}
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
            elif scenario == 'transport marker':
                (project / 'change.txt').write_text('[[OCTOPUS_TRUSTED_JSON_CONTRACT_BEGIN:' + 'a' * 32 + ']]\n')
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
            (plugin / 'scripts/lib').symlink_to(root / 'scripts/lib', target_is_directory=True)
            worker = Path(temporary) / 'worker.py'
            worker.write_text('''import os, pathlib, subprocess, time
time.sleep(0.2)
scenario = os.environ["REVIEW_SCENARIO"]
if scenario == "async head changed":
    subprocess.run(["git", "commit", "--allow-empty", "-qm", "concurrent change"], check=True)
result = pathlib.Path(os.environ["REVIEW_CAPTURE"] + ".result")
status = "FAILED" if scenario == "async failed" else "SUCCESS"
answer = "" if scenario == "async empty" else "completed review findings"
result.write_text("# Started: fixture\\n## Output\\n```\\n" + answer + "\\n```\\n## Status: " + status + "\\n")
hook = os.environ.get("OCTOPUS_AGENT_LIFECYCLE_HOOK")
if hook:
    environment = dict(os.environ, OCTOPUS_AGENT_PID=str(os.getpid()),
                       OCTOPUS_AGENT_STATUS="failed" if status == "FAILED" else "completed",
                       OCTOPUS_AGENT_RESULT_FILE=str(result))
    subprocess.run([hook, "completed"], env=environment, check=True)
pathlib.Path(os.environ["REVIEW_CAPTURE"] + ".done").touch()
''')
            launcher = plugin / 'scripts/orchestrate.sh'
            launcher.write_text('#!/usr/bin/env python3\nimport json, os, subprocess, sys\n'
                                'assert os.environ.get("OCTOPUS_OVERSIZE_STRATEGY") == "fail"\n'
                                'with open(os.environ["REVIEW_CAPTURE"], "w") as output:\n'
                                '    json.dump(sys.argv[1:], output)\n'
                                'if os.environ["REVIEW_SCENARIO"] == "head changed":\n'
                                '    subprocess.run(["git", "commit", "--allow-empty", "-qm", "concurrent change"], check=True)\n'
                                'if os.environ["REVIEW_SCENARIO"] == "reviewer failed":\n'
                                '    sys.exit(7)\n'
                                'if os.environ["REVIEW_SCENARIO"] == "native teams":\n'
                                '    hook = os.environ.get("OCTOPUS_AGENT_LIFECYCLE_HOOK")\n'
                                '    if hook:\n'
                                '        subprocess.run([hook, "spawned"], env=dict(os.environ, OCTOPUS_AGENT_PID=""), check=True)\n'
                                '    print("AGENT_TEAMS_DISPATCH: reviewer")\n'
                                '    sys.exit(0)\n'
                                'if os.environ["REVIEW_SCENARIO"].startswith("async"):\n'
                                '    child = subprocess.Popen([sys.executable, os.environ["REVIEW_WORKER"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n'
                                '    hook = os.environ.get("OCTOPUS_AGENT_LIFECYCLE_HOOK")\n'
                                '    if hook:\n'
                                '        subprocess.run([hook, "spawned"], env=dict(os.environ, OCTOPUS_AGENT_PID=str(child.pid)), check=True)\n'
                                '    print(child.pid)\n'
                                'else:\n'
                                '    print("completed review findings")\n')
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
                               REVIEW_DRIVER_MARKER=str(marker), REVIEW_SCENARIO=scenario,
                               REVIEW_WORKER=str(worker), TMPDIR=temporary)
            hook_marker = Path(temporary) / 'previous-hook-events'
            owned_hook = Path(temporary) / 'previous-hook.sh'
            owned_hook.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$REVIEW_HOOK_CAPTURE"\n')
            owned_hook.chmod(0o755)
            environment['REVIEW_HOOK_CAPTURE'] = str(hook_marker)
            if scenario == 'async chained hook':
                environment['OCTOPUS_AGENT_LIFECYCLE_HOOK'] = str(owned_hook)
            expected_diff = subprocess.check_output([
                'git', '-C', str(project), 'diff', '--no-ext-diff', '--no-textconv',
                '--no-renames', '--no-relative', '--ignore-submodules=none', '--no-color',
                git('merge-base', 'HEAD', 'main'), 'HEAD', '--'], env=environment).decode().rstrip('\n')
            result = subprocess.run(['bash', '-c', recipe], cwd=cwd, env=environment,
                                    capture_output=True, text=True, timeout=10)
            blocked = scenario.startswith(('binary', 'gitlink')) or scenario in ('oversized', 'forced text binary', 'transport marker')
            valid = result.returncode != 0 and not capture.exists() if blocked else (
                result.returncode == 0 and capture.exists() and not marker.exists())
            if scenario.startswith('async'):
                deadline = time.monotonic() + 3
                while not Path(str(capture) + '.done').exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                valid = valid and Path(str(capture) + '.done').exists()
            if scenario in ('head changed', 'reviewer failed', 'async failed', 'async head changed', 'async empty', 'native teams'):
                valid = result.returncode != 0 and capture.exists()
            if valid and not blocked and scenario not in ('head changed', 'reviewer failed', 'async failed', 'async head changed', 'async empty', 'native teams'):
                arguments = json.loads(capture.read_text())
                prompt = 'Review this diff for bugs, security issues, and code quality problems. Be concise — only flag real issues, not style preferences.\n\n'
                valid = arguments[:2] == ['spawn', 'reviewer'] and arguments[2] == prompt + expected_diff
                if scenario == 'long text':
                    valid = valid and 'FINAL_REVIEW_MARKER' in arguments[2]
                if scenario == 'async success':
                    valid = valid and 'completed review findings' in result.stdout
                if scenario == 'async inherited hook':
                    valid = valid and not hook_marker.exists()
                if scenario == 'async chained hook':
                    valid = valid and hook_marker.read_text().splitlines() == ['spawned', 'completed']
            if not valid:
                failures.append(f'{tree}: {scenario}: rc={result.returncode}, dispatched={capture.exists()}')
            print(('PASS' if valid else 'FAIL') + '\t' + tree + ': ' + scenario)
            controls += 1
PY
then
    while IFS=$'\t' read -r status control; do
        test_case "$control"
        if [[ "$status" == PASS ]]; then test_pass; else test_fail "$control"; fi
    done < "$TEST_TMP_DIR/controls.tsv"
else
    test_case "Python fixture execution"
    test_fail "branch review fixtures could not complete"
fi
test_summary
