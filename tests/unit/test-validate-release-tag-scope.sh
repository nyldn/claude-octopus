#!/usr/bin/env bash
# Feature branches may validate release contents without impersonating a release commit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_RELEASE="$PROJECT_ROOT/scripts/validate-release.sh"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "validate-release tag mismatch scope"

# Load only the tag-scope function so fixtures cannot run the whole validator.
load_tag_scope_helper() {
    local helper
    helper=$(awk '
        /^tag_mismatch_is_fatal\(\)/ { capture = 1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$VALIDATE_RELEASE")
    [[ -n "$helper" ]] || return 1
    eval "$helper"
}

test_case "tag scope helper is available"
if load_tag_scope_helper; then
    test_pass
else
    test_fail "tag_mismatch_is_fatal helper not found"
fi

test_case "tag mismatch remains fatal on main"
CURRENT_BRANCH=main
if tag_mismatch_is_fatal; then
    test_pass
else
    test_fail "main could ignore a mismatched release tag"
fi

test_case "tag mismatch remains fatal on a release branch"
CURRENT_BRANCH=release/v10.1.0
if tag_mismatch_is_fatal; then
    test_pass
else
    test_fail "release branch could ignore a mismatched release tag"
fi

test_case "tag mismatch remains fatal on detached HEAD"
CURRENT_BRANCH=
if tag_mismatch_is_fatal; then
    test_pass
else
    test_fail "detached HEAD could ignore a mismatched release tag"
fi

test_case "ordinary feature branch treats an existing release tag as validation-only"
CURRENT_BRANCH=feat/simplify-install-setup-use
if ! tag_mismatch_is_fatal; then
    test_pass
else
    test_fail "feature branch incorrectly requires the existing release tag at HEAD"
fi

test_case "mismatched-tag branch is guarded by the tag scope helper"
tag_block=$(sed -n '/if git tag -l/,/^    fi$/p' "$VALIDATE_RELEASE")
if grep -q 'tag_mismatch_is_fatal' <<< "$tag_block"; then
    test_pass
else
    test_fail "tag mismatch handling does not consult tag scope"
fi

test_case "release validation never writes tags or GitHub releases, including on clean main"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'READ_ONLY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]) / 'scripts/validate-release.sh'
with tempfile.TemporaryDirectory(prefix='release-readonly-', dir=sys.argv[2]) as temporary:
    root = Path(temporary) / 'plugin'
    root.mkdir()
    (root / 'scripts/helpers').mkdir(parents=True)
    shutil.copyfile(source, root / 'scripts/validate-release.sh')
    audit = root / 'scripts/helpers/audit-provider-contracts.sh'
    audit.write_text('#!/usr/bin/env bash\nprintf "SUMMARY fixture audit passed\\n"\n')
    audit.chmod(0o755)
    for directory in ['.claude-plugin', '.codex-plugin', '.cursor-plugin', '.factory-plugin', 'commands', 'skills/flow-fixture']:
        (root / directory).mkdir(parents=True)
    version = '99.1.0'
    plugin = {'name': 'octo', 'version': version, 'commands': ['./commands/fixture.md'],
              'skills': ['./skills/flow-fixture']}
    (root / '.claude-plugin/plugin.json').write_text(json.dumps(plugin, indent=2))
    (root / '.claude-plugin/marketplace.json').write_text(json.dumps({'plugins': [
        {'name': 'octo', 'version': version, 'description': 'v' + version}]}, indent=2))
    for directory in ['.codex-plugin', '.cursor-plugin', '.factory-plugin']:
        (root / directory / 'plugin.json').write_text(json.dumps({'name': 'claude-octopus', 'version': version}, indent=2))
    (root / '.factory-plugin/marketplace.json').write_text(json.dumps({'plugins': [
        {'name': 'claude-octopus', 'version': version}]}, indent=2))
    (root / 'package.json').write_text(json.dumps({'version': version, 'files': [
        '.claude-plugin/', '.codex-plugin/', '.cursor-plugin/', '.factory-plugin/',
        '.opencode/', '.mcp.json', 'bin/', 'managed-settings.d/', 'skills/', 'docs/']}, indent=2))
    (root / 'README.md').write_text('Version-' + version + '\n')
    (root / 'CHANGELOG.md').write_text('## [' + version + '] - 2026-01-01\n\nFixture release.\n')
    (root / 'commands/fixture.md').write_text('---\ncommand: fixture\n---\n')
    (root / 'skills/flow-fixture/SKILL.md').write_text('---\nname: flow-fixture\n---\n')
    binaries = Path(temporary) / 'bin'
    binaries.mkdir()
    cli = r'''
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
with Path(os.environ['FIXTURE_COMMAND_LOG']).open('a') as log:
    log.write(json.dumps([name, args]) + '\n')
if name == 'claude':
    if args == ['--help']:
        print('--plugin-url --plugin-dir .zip')
    raise SystemExit(0)
if name == 'git':
    if args[:1] == ['-C']:
        args = args[2:]
    if args == ['rev-parse', '--is-inside-work-tree']:
        print('true')
    elif args == ['rev-parse', 'HEAD'] or args[:1] == ['rev-list']:
        print('b' * 40 if os.environ['FIXTURE_TAG'] == 'mismatch' and args[:1] == ['rev-list'] else 'a' * 40)
    elif args == ['branch', '--show-current']:
        print('main')
    elif args == ['status', '--porcelain']:
        pass
    elif args[:1] == ['show-ref']:
        raise SystemExit(0 if os.environ['FIXTURE_TAG'] != 'missing' else 1)
    elif args[:2] == ['tag', '-l']:
        if os.environ['FIXTURE_TAG'] != 'missing':
            print('v99.1.0')
    elif args[:1] == ['ls-remote']:
        print('a' * 40 + '\trefs/tags/v99.1.0')
    else:
        print('Forbidden git operation: ' + repr(args), file=sys.stderr)
        raise SystemExit(88)
    raise SystemExit(0)
if name == 'gh':
    if args == ['auth', 'status']:
        raise SystemExit(0)
    if args[:2] == ['release', 'view']:
        raise SystemExit(0 if os.environ['FIXTURE_RELEASE'] == 'present' else 1)
    print('Forbidden gh operation: ' + repr(args), file=sys.stderr)
    raise SystemExit(88)
raise SystemExit(89)
'''
    for name in ['git', 'gh', 'claude']:
        path = binaries / name
        path.write_text('#!' + sys.executable + '\n' + cli)
        path.chmod(0o755)
    for tag, release, expected in [('missing', 'missing', 0), ('present', 'missing', 0),
                                   ('present', 'present', 0), ('mismatch', 'missing', 1)]:
        log = Path(temporary) / (tag + '-' + release + '.jsonl')
        env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ['PATH'],
                   HOME=str(Path(temporary) / 'home'), FIXTURE_COMMAND_LOG=str(log),
                   FIXTURE_TAG=tag, FIXTURE_RELEASE=release, OCTOPUS_RELEASE_RUNTIME_SMOKE='0')
        result = subprocess.run(['bash', str(root / 'scripts/validate-release.sh')],
                                cwd=root, env=env, capture_output=True, text=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        calls = [(name, args[2:] if name == 'git' and args[:1] == ['-C'] else args)
                 for name, args in calls]
        assert all(name != 'git' or args in [
            ['rev-parse', '--is-inside-work-tree'], ['rev-parse', 'HEAD'],
            ['branch', '--show-current'], ['status', '--porcelain'],
            ['tag', '-l', 'v99.1.0'], ['rev-list', '-n', '1', 'v99.1.0'],
            ['show-ref', '--verify', '--quiet', 'refs/tags/v99.1.0'],
            ['show-ref', '--verify', '--quiet', 'refs/tags/99.1.0'],
            ['ls-remote', 'origin', 'refs/tags/v99.1.0'],
            ['ls-remote', 'origin', 'refs/tags/v99.1.0^{}']]
            for name, args in calls), calls
        assert not any(name == 'gh' and args[:2] != ['release', 'view'] and
                       args != ['auth', 'status'] for name, args in calls), calls
        assert result.returncode == expected, (tag, release, result.returncode, result.stdout, result.stderr)
        if tag == 'missing' or release == 'missing':
            assert 'scripts/release.sh' in result.stdout, result.stdout
        if tag == 'mismatch':
            assert "doesn't point to HEAD" in result.stdout, result.stdout
READ_ONLY
then test_pass; else test_fail "validator mutated release state or lost validation behavior"; fi

test_summary
