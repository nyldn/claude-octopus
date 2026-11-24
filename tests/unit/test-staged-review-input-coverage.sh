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
import shutil
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
                     'relative config', 'shadow stdlib', 'unstaged excluded',
                     'forced text hidden NUL', 'forced text trailing NUL', 'unmerged', 'index race',
                     'unavailable output directory',
                     'staged stub', 'staged comments', 'staged deletion',
                     'staged block comments', 'staged block then code',
                     'staged exported declarations', 'staged reexports', 'staged private fields',
                     'staged multiline reexports', 'staged comment after code', 'staged nested Rust comment',
                     'staged comment delimiter in string', 'staged Python module docstring',
                     'staged Python nested docstrings', 'staged Python from imports',
                     'staged multiline JS imports'):
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
            source = project / ('source with spaces.ts' if scenario.startswith('staged ') else 'change.txt')
            if scenario == 'staged nested Rust comment':
                source = source.with_suffix('.rs')
            elif scenario.startswith('staged Python '):
                source = source.with_suffix('.py')
            source.write_text('original\n')
            if scenario in ('forced text hidden NUL', 'forced text trailing NUL'):
                lines = b''.join(f'line {i}\n'.encode() for i in range(200))
                data = b'binary\0header\n' + lines if scenario == 'forced text hidden NUL' else lines + b'binary\0footer\n'
                source.write_bytes(data)
                (project / '.gitattributes').write_text('change.txt diff\n')
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
            if scenario.startswith('forced text ') and scenario.endswith('NUL'):
                target = b'line 199' if scenario == 'forced text hidden NUL' else b'line 0'
                source.write_bytes(source.read_bytes().replace(target, b'STAGED_REVIEW_MARKER'))
            elif scenario != 'empty':
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
            elif scenario == 'staged stub':
                source.write_text('// TODO: implement\nconst value = 1;\n')
            elif scenario == 'staged comments':
                source.write_text('// A comment with no substantive lines\n')
            elif scenario == 'staged deletion':
                source.unlink()
            elif scenario in ('staged block comments', 'staged block then code'):
                closing = '*/ export const answer = 42;' if scenario.endswith('then code') else '*/'
                source.write_text('/*\n' + 'comment line\n' * 6 + closing + '\n')
            elif scenario == 'staged exported declarations':
                source.write_text(''.join(f'export const value{i} = {i};\n' for i in range(5)))
            elif scenario == 'staged reexports':
                source.write_text("export * from './values';\nexport { value };\nexport type { Model };\n")
            elif scenario == 'staged private fields':
                source.write_text('class Settings {\n' + ''.join(f'  #field{i} = {i};\n' for i in range(4)) + '}\n')
            elif scenario == 'staged multiline reexports':
                source.write_text('export type {\n' + ''.join(f'  Type{i},\n' for i in range(5)) + "} from './types';\n")
            elif scenario == 'staged comment after code':
                source.write_text('const value = 1; /*\n' + 'comment line\n' * 6 + '*/\n')
            elif scenario == 'staged nested Rust comment':
                source.write_text('/* outer\n/* nested */\n' + 'comment line\n' * 6 + '*/\n')
            elif scenario == 'staged comment delimiter in string':
                source.write_text('const delimiter = "/*";\n' + 'const value = 1;\n' * 4)
            elif scenario == 'staged Python module docstring':
                source.write_text('"""\n' + 'documentation line\n' * 5 + '"""\n')
            elif scenario == 'staged Python nested docstrings':
                source.write_text('class Placeholder:\n    """\n' + '    class documentation\n' * 4 +
                                  '    """\n    def run(self):\n        """\n' +
                                  '        function documentation\n' * 4 + '        """\n')
            elif scenario == 'staged Python from imports':
                source.write_text('from .helpers import (\n' + ''.join(f'    helper{i},\n' for i in range(5)) +
                                  ')\nfrom .extras import extra\n')
            elif scenario == 'staged multiline JS imports':
                source.write_text('import defaultThing, {\n' + ''.join(f'  helper{i},\n' for i in range(5)) +
                                  "} from './helpers';\n")
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
            if scenario.startswith('staged '):
                source.write_text('working_tree_only = True\n' * 5)
            cwd = project
            if scenario == 'relative config':
                git('config', 'diff.relative', 'true')
                cwd = project / 'subdir'
                cwd.mkdir()
            if scenario == 'unmerged':
                old = git('rev-parse', 'HEAD:change.txt')
                new = git('rev-parse', ':change.txt')
                git('update-index', '--force-remove', 'change.txt')
                records = f'100644 {old} 1\tchange.txt\n100644 {new} 2\tchange.txt\n100644 {old} 3\tchange.txt\n'
                subprocess.run(['git', 'update-index', '--index-info'], input=records, text=True,
                               cwd=project, env=environment, check=True)
            before = git('ls-files', '--stage', '-z')
            expected = subprocess.check_output(['git', 'diff', '--cached', '--no-ext-diff',
                '--no-textconv', '--no-renames', '--no-relative', '--ignore-submodules=none',
                '--no-color', '--binary', '--'], cwd=project, env=environment, text=True).rstrip('\n')
            fixture = project / '.git'
            plugin = fixture / 'plugin root'
            (plugin / 'scripts').mkdir(parents=True)
            launcher = plugin / 'scripts/orchestrate.sh'
            launcher.write_text(
                '#!/bin/bash\n'
                '[[ "$1" == spawn && $# == 3 ]] || exit 2\n'
                'printf "%s" "$3" > "$REVIEW_FIXTURE/$2-prompt"\n'
            )
            launcher.chmod(0o755)
            has_providers = scenario in ('long text', 'index race', 'empty',
                                         'unavailable output directory')
            temp_root = fixture
            if scenario == 'unavailable output directory':
                temp_root = fixture / 'not-a-directory'
                temp_root.touch()
            call_environment = dict(environment, CLAUDE_PLUGIN_ROOT=str(plugin), TMPDIR=str(temp_root),
                                    REVIEW_FIXTURE=str(fixture), REVIEW_PROVIDERS=str(int(has_providers)))
            expected_index = before
            if scenario == 'index race':
                binary_dir = project / '.git/bin'
                binary_dir.mkdir()
                wrapper = binary_dir / 'git'
                wrapper.write_text('#!' + sys.executable + '\nimport os, subprocess, sys\n'
                    'real = os.environ["REAL_GIT"]\n'
                    'result = subprocess.run([real, *sys.argv[1:]])\n'
                    'if sys.argv[1] == "diff" and "--raw" in sys.argv:\n'
                    '    subprocess.run([real, "update-index", "--add", "--cacheinfo", "160000," + os.environ["RACE_HEAD"] + ",nested"], check=True)\n'
                    'sys.exit(result.returncode)\n')
                wrapper.chmod(0o755)
                race_head = git('rev-parse', 'HEAD')
                call_environment.update(PATH=str(binary_dir) + ':' + environment['PATH'],
                                        REAL_GIT=shutil.which('git'), RACE_HEAD=race_head)
                expected_index += f'160000 {race_head} 0\tnested\0'
            # Give the recipe two inert providers only for the dispatch controls.
            provider_lookup = '''
command() {
    if [[ "$1" == -v && ( "$2" == codex || "$2" == agy ) ]]; then
        [[ "$REVIEW_PROVIDERS" == 1 ]]
    else
        builtin command "$@"
    fi
}
'''
            result = subprocess.run(['bash', '-c', provider_lookup + recipe + '\nwait'],
                                    cwd=cwd, env=call_environment,
                                    capture_output=True, text=True, timeout=5)
            blocked = scenario.startswith(('binary', 'gitlink')) or scenario in (
                'empty', 'forced text binary', 'oversized', 'transport marker',
                'forced text hidden NUL', 'forced text trailing NUL', 'unmerged',
                'unavailable output directory')
            valid = ((result.returncode != 0) == blocked and
                     not (project / 'executed').exists() and
                     git('ls-files', '--stage', '-z') == expected_index)
            output_dirs = list(fixture.glob('octopus-staged-review.*'))
            valid = valid and len(output_dirs) == (0 if blocked else 1)
            if blocked:
                valid = valid and result.stdout == ''
            elif output_dirs:
                staged_diff = output_dirs[0] / 'staged.diff'
                files = {'staged.diff'}
                if has_providers:
                    files.update(('codex.md', 'codex.log', 'agy.md', 'agy.log'))
                valid = (valid and result.stdout == f'Staged review input: {staged_diff}\n' and
                         {path.name for path in output_dirs[0].iterdir()} == files and
                         staged_diff.read_text() == expected + '\n')
            for provider in ('codex', 'agy'):
                prompt = fixture / f'{provider}-prompt'
                if has_providers and not blocked:
                    valid = valid and prompt.is_file()
                    if prompt.is_file():
                        valid = valid and prompt.read_text().partition('\nDIFF:\n')[2] == expected
                else:
                    valid = valid and not prompt.exists()
            if scenario == 'staged stub':
                valid = valid and '1 TODO/FIXME markers' in result.stderr
            elif scenario == 'staged comments':
                valid = valid and 'only 0 substantive lines' in result.stderr
                valid = valid and 'TODO/FIXME markers' not in result.stderr
            elif scenario == 'staged deletion':
                valid = valid and '0 source files scanned' in result.stderr
            elif scenario in ('staged block comments', 'staged reexports',
                              'staged multiline reexports', 'staged nested Rust comment',
                              'staged Python module docstring', 'staged Python from imports',
                              'staged multiline JS imports'):
                valid = valid and 'only 0 substantive lines' in result.stderr
            elif scenario == 'staged Python nested docstrings':
                valid = valid and 'only 2 substantive lines' in result.stderr
            elif scenario in ('staged block then code', 'staged comment after code'):
                valid = valid and 'only 1 substantive lines' in result.stderr
            elif scenario in ('staged exported declarations', 'staged private fields',
                              'staged comment delimiter in string'):
                valid = valid and '1 source files scanned, 0 issues found' in result.stderr
            if not valid:
                failures.append(f'{tree}: {scenario}: exit={result.returncode} {result.stderr}')
            controls += 1
print(f'{controls - len(failures)}/{controls} staged review controls passed')
for failure in failures:
    print(failure, file=sys.stderr)
sys.exit(bool(failures))
PY_CONTROLS
then test_pass; else test_fail "staged review admitted incomplete input or omitted source"; fi

test_case "production spawn preserves fitting input and refuses oversized staged reviews before dispatch"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_SPAWN'
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time

root = Path(sys.argv[1])
skill = (root / '.claude/skills/skill-staged-review/SKILL.md').read_text()
section = skill.split('### Step 2: Multi-LLM Quality Review', 1)[1]
recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
for oversized in (False, True):
    with tempfile.TemporaryDirectory(dir=sys.argv[2]) as location:
        project = Path(location)
        for directory in ('bin', 'home', 'tmp'):
            (project / directory).mkdir()
        for provider, capture_prompt in {
            'codex': '[[ "$1" == exec ]] || exit 0\ncat > "$capture.tmp"\n',
            'agy': '''while [[ $# -gt 1 && "$1" != --print ]]; do shift; done
[[ "$1" == --print ]] || exit 0
printf '%s' "$2" > "$capture.tmp"
''',
        }.items():
            stub = project / 'bin' / provider
            capture = shlex.quote(str(project / f'{provider}.prompt'))
            stub.write_text(
                '#!/bin/bash\n'
                'case "$1" in --version|-v|version) echo "0.160.0"; exit 0;; esac\n'
                f'capture={capture}\n' + capture_prompt +
                'mv "$capture.tmp" "$capture"\n'
                'echo "Fixture reviewer inspected the supplied text."\n'
            )
            stub.chmod(0o755)
        environment = dict(
            PATH=str(project / 'bin') + ':' + os.environ['PATH'],
            HOME=str(project / 'home'), TMPDIR=str(project / 'tmp'),
            CLAUDE_PLUGIN_ROOT=str(root), GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
            OPENAI_API_KEY='fixture-unusable', OCTO_ALLOWED_PROVIDERS='codex,agy',
            OCTOPUS_CONTEXT_BUDGET='4000', OCTOPUS_OVERSIZE_STRATEGY='truncate',
            OCTOPUS_HEURISTIC_LEARNING='off', OCTOPUS_PERSONA_PACKS='off',
        )
        for args in (('init', '-q'), ('config', 'core.hooksPath', os.devnull)):
            subprocess.run(['git', *args], cwd=project, env=environment, check=True)
        (project / 'change.txt').write_text(
            'START_STAGED_EVIDENCE\n' + 'x' * (50000 if oversized else 10) + '\nEND_STAGED_EVIDENCE\n'
        )
        subprocess.run(['git', 'add', 'change.txt'], cwd=project, env=environment, check=True)
        expected = subprocess.check_output(['git', 'diff', '--cached', '--binary'], cwd=project,
                                           env=environment, text=True).rstrip('\n')
        result = subprocess.run(['bash', '-c', recipe], cwd=project, env=environment,
                                capture_output=True, text=True, timeout=45)
        snapshot, = (project / 'tmp').glob('octopus-staged-review.*/staged.diff')
        assert snapshot.read_text() == expected + '\n'
        assert result.returncode == int(oversized), (oversized, result.stderr)
        for provider in ('codex', 'agy'):
            capture = project / f'{provider}.prompt'
            diagnostic = (snapshot.parent / f'{provider}.log').read_text()
            if oversized:
                assert not capture.exists(), (provider, 'oversized dispatch')
                assert 'Context budget: prompt for ' + provider in diagnostic, diagnostic
                assert f'External review incomplete for {provider}.' in result.stderr, result.stderr
            else:
                # The Codex CLI launch returns its worker PID before it completes.
                for _ in range(100):
                    if capture.exists():
                        break
                    time.sleep(0.1)
                assert capture.exists(), (provider, diagnostic)
                assert '\nDIFF:\n' + expected in capture.read_text(), (provider, 'incomplete prompt')
print('2/2 staged review production spawn controls passed')
PY_SPAWN
then test_pass; else test_fail "production spawn changed or omitted staged-review input"; fi
test_summary
