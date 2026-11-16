#!/usr/bin/env bash
# Execute the local-merge recipe with real conflicts and inert test commands.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Branch completion merge boundary"
test_case "failed integration steps preserve the feature branch and stop cleanup"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_CONTROLS'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
environment = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                   GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                   GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
for variable in subprocess.check_output(['git', 'rev-parse', '--local-env-vars'], text=True).splitlines():
    environment.pop(variable, None)
failures = []
count = 0
for tree in ('.claude/skills', 'skills', 'codex-skills'):
    entry = root / tree / 'skill-finish-branch/SKILL.md'
    if not entry.exists():
        continue
    section = entry.read_text().split(': Merge Locally', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for scenario in ('checkout failure', 'pull failure', 'merge conflict', 'test failure', 'success'):
        count += 1
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as temporary:
            directory = Path(temporary)
            project = directory / 'project'
            project.mkdir()
            def git(*arguments, check=True):
                return subprocess.run(['git', '-C', str(project), *arguments], env=environment,
                                      capture_output=True, text=True, check=check)
            git('init', '-q', '-b', 'main')
            source = project / 'source.txt'
            source.write_text('base\n')
            git('add', '.')
            git('commit', '-qm', 'base')
            remote = directory / 'remote.git'
            git('init', '--bare', '-q', str(remote))
            git('remote', 'add', 'origin', str(remote))
            git('push', '-q', 'origin', 'main')
            git('checkout', '-qb', 'feature')
            source.write_text('feature\n')
            git('commit', '-qam', 'feature')
            if scenario == 'merge conflict':
                git('checkout', '-q', 'main')
                source.write_text('main\n')
                git('commit', '-qam', 'main diverged')
                git('push', '-q', 'origin', 'main')
                git('checkout', '-q', 'feature')
            if scenario == 'checkout failure':
                source.write_text('uncommitted feature edit\n')
            if scenario == 'pull failure':
                git('remote', 'remove', 'origin')
            binary = directory / 'bin'
            binary.mkdir()
            npm = binary / 'npm'
            npm.write_text('#!/bin/sh\nprintf "test\\n" >> "$TEST_CALLS"\nexit "$TEST_EXIT"\n')
            npm.chmod(0o755)
            calls = directory / 'calls'
            env = dict(environment, BASE_BRANCH='main', TEST_CALLS=str(calls),
                       TEST_EXIT='42' if scenario == 'test failure' else '0',
                       PATH=str(binary) + ':' + os.environ['PATH'])
            # No implicit errexit: the published recipe must handle failures itself.
            result = subprocess.run(['bash', '-c', recipe], cwd=project, env=env,
                                    capture_output=True, text=True, timeout=15)
            retained = git('show-ref', '--verify', '--quiet', 'refs/heads/feature', check=False).returncode == 0
            expected_tests = scenario in ('test failure', 'success')
            ok = ((result.returncode == 0) == (scenario == 'success') and
                  retained == (scenario != 'success') and calls.exists() == expected_tests)
            if scenario == 'checkout failure':
                ok = ok and source.read_text() == 'uncommitted feature edit\n'
            if not ok:
                failures.append(f'{tree}: {scenario}: rc={result.returncode}, retained={retained}, tests={calls.exists()}')
print(f'{count - len(failures)}/{count} actual merge controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then
    test_pass
else
    test_fail "local integration continued after a failed step"
fi
test_summary
