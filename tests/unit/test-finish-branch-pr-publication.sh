#!/usr/bin/env bash
# Execute the PR recipe against disposable local remotes and inert GitHub tools.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Branch completion PR publication"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" > "$TEST_TMP_DIR/controls.tsv" <<'PY'
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
real_git = shutil.which('git')
failures = []
controls = 0
for tree in ('.claude/skills', 'skills'):
    text = (root / tree / 'skill-finish-branch/SKILL.md').read_text()
    section = text.split('#### Option 2: Create PR', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    for scenario in ('success', 'push failed', 'detached', 'branch lookup failed',
                     'repository lookup failed', 'empty repository',
                     'empty title', 'empty summary', 'empty reason', 'PR write failed'):
        with tempfile.TemporaryDirectory(prefix='branch-publication-', dir=sys.argv[2]) as tmp:
            temporary = Path(tmp)
            project = temporary / 'project'
            project.mkdir()
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith('GIT_')}
            environment.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                               GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                               GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
            def git(*args, cwd=project, check=True):
                return subprocess.run([real_git, '-C', str(cwd), *args], env=environment,
                                      text=True, capture_output=True, check=check)
            remote = temporary / 'remote.git'
            git('init', '-q', '--bare', str(remote))
            git('init', '-q', '-b', 'feature')
            git('config', 'core.hooksPath', os.devnull)
            (project / 'source.txt').write_text('committed work\n')
            git('add', 'source.txt')
            git('commit', '-qm', 'reviewed work')
            head = git('rev-parse', 'HEAD').stdout.strip()
            git('remote', 'add', 'origin', str(temporary / 'missing' if scenario == 'push failed' else remote))
            if scenario == 'detached':
                git('checkout', '-q', '--detach')

            plugin = temporary / 'plugin'
            (plugin / 'scripts').mkdir(parents=True)
            helper = plugin / 'scripts/safe-gh-comment.sh'
            helper.write_text('''#!/usr/bin/env bash
printf 'pr-write\n' >> "$PUBLICATION_LOG"
[[ "$PUBLICATION_SCENARIO" != 'PR write failed' ]]
''')
            helper.chmod(0o755)
            binary = temporary / 'bin'
            binary.mkdir()
            gh = binary / 'gh'
            gh.write_text('''#!/usr/bin/env bash
if [[ "$1 $2" == 'repo view' ]]; then
  [[ "$PUBLICATION_SCENARIO" != 'repository lookup failed' ]] || exit 17
  [[ "$PUBLICATION_SCENARIO" == 'empty repository' ]] || printf 'fixture/repository\n'
elif [[ "$1 $2" == 'pr list' ]]; then
  printf 'recovery-read\n' >> "$PUBLICATION_LOG"
  printf '[]\n'
else
  exit 64
fi
''')
            gh.chmod(0o755)
            log = temporary / 'publication.log'
            environment.update(PATH=str(binary) + os.pathsep + environment['PATH'],
                               CLAUDE_PLUGIN_ROOT=str(plugin), CODEX_PLUGIN_ROOT='',
                               PUBLICATION_LOG=str(log), PUBLICATION_SCENARIO=scenario,
                               PR_TITLE='' if scenario == 'empty title' else 'Reviewed change',
                               CHANGE_SUMMARY='' if scenario == 'empty summary' else 'Fix bounded behavior',
                               CHANGE_REASON='' if scenario == 'empty reason' else 'Preserve completion evidence')
            prefix = ''
            if scenario == 'branch lookup failed':
                prefix = '''git() {
  if [[ "$1 $2" == 'branch --show-current' ]]; then return 19; fi
  command git "$@"
}
'''
            # Do not enable errexit: each documented recipe must stop explicitly.
            result = subprocess.run(['bash', '-c', prefix + recipe + '\nprintf "completed\\n"'],
                                    cwd=project, env=environment, text=True,
                                    capture_output=True, timeout=15)
            events = log.read_text().splitlines() if log.exists() else []
            published = git('show-ref', '--verify', 'refs/heads/feature', cwd=remote, check=False).returncode == 0
            if scenario == 'success':
                valid = result.returncode == 0 and published and events == ['pr-write'] and 'completed' in result.stdout
            elif scenario == 'PR write failed':
                valid = result.returncode != 0 and published and events == ['pr-write', 'recovery-read'] and 'completed' not in result.stdout
            else:
                valid = result.returncode != 0 and not published and not events and 'completed' not in result.stdout
            valid = valid and git('rev-parse', 'HEAD').stdout.strip() == head
            valid = valid and git('show-ref', '--verify', 'refs/heads/feature', check=False).returncode == 0
            controls += 1
            label = f'{tree}: {scenario}'
            print(('PASS' if valid else 'FAIL') + '\t' + label)
            if not valid:
                failures.append(f'{label}: rc={result.returncode}, published={published}, events={events}')
if failures:
    print('\n'.join(failures), file=sys.stderr)
    sys.exit(1)
print(f'PASS\t{controls} production publication controls')
PY
then
    while IFS=$'\t' read -r status label; do
        test_case "$label"
        if [[ "$status" == PASS ]]; then
            test_pass
        else
            test_fail "publication contract violated"
        fi
    done < "$TEST_TMP_DIR/controls.tsv"
else
    cat "$TEST_TMP_DIR/controls.tsv"
    test_case "production publication controls"
    test_fail "recipe continued after failed admission or publication"
fi
test_summary
