#!/usr/bin/env bash
# Regression test for issue #829.
#
# validate-release.sh's skill registration check only searched
# skills/<name>/SKILL.md (depth 2 below skills/), so skills nested one level
# deeper at skills/<pack>/<name>/SKILL.md (skills/octopus-starter-pack/*) were
# reported as "does not exist" even though they were registered in
# plugin.json and present on disk.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "validate-release.sh skill registration (issue #829)"

VALIDATE_RELEASE="$PROJECT_ROOT/scripts/validate-release.sh"

test_case "validate-release.sh exists"
if [[ -f "$VALIDATE_RELEASE" ]]; then
    test_pass
else
    test_fail "missing $VALIDATE_RELEASE"
    test_summary
    exit 1
fi

test_case "find_skill_md_files locates ordinary and one-level-nested SKILL.md, ignoring other files"
FIXTURE_DIR="$TEST_TMP_DIR/skill-fixture-$$"
rm -rf "$FIXTURE_DIR"
mkdir -p "$FIXTURE_DIR/skills/plain-skill"
mkdir -p "$FIXTURE_DIR/skills/starter-pack/nested-skill"
printf -- '---\nname: plain-skill\n---\n' > "$FIXTURE_DIR/skills/plain-skill/SKILL.md"
printf -- '---\nname: nested-skill\n---\n' > "$FIXTURE_DIR/skills/starter-pack/nested-skill/SKILL.md"
printf 'not a skill file\n' > "$FIXTURE_DIR/skills/plain-skill/README.md"

FUNC_SRC=$(sed -n '/^find_skill_md_files()/,/^}/p' "$VALIDATE_RELEASE")
if [[ -z "$FUNC_SRC" ]]; then
    test_fail "find_skill_md_files() helper not found in validate-release.sh"
else
    eval "$FUNC_SRC"
    found=$(find_skill_md_files "$FIXTURE_DIR/skills" | sed "s|^$FIXTURE_DIR/skills/||;s|/SKILL.md\$||" | sort)
    expected=$'plain-skill\nstarter-pack/nested-skill'
    if [[ "$found" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected:\n$expected\ngot:\n$found"
    fi
fi
rm -rf "$FIXTURE_DIR"

test_case "real octopus-starter-pack nested skills are reported registered, not missing"
CURRENT_VERSION=$(jq -r '.version' "$PROJECT_ROOT/.claude-plugin/plugin.json")
OUTPUT=$(cd "$PROJECT_ROOT" && bash "$VALIDATE_RELEASE" "$CURRENT_VERSION" 2>&1 || true)

if grep -cF -- "Registered skill 'octopus-starter-pack" <<< "$OUTPUT" >/dev/null; then
    test_fail "validate-release.sh still reports registered nested skills as missing:\n$(grep -F -- "octopus-starter-pack" <<< "$OUTPUT")"
elif grep -cE -- "All [0-9]+ skills properly registered" <<< "$OUTPUT" >/dev/null; then
    test_pass
else
    test_fail "could not confirm skill registration passed; output:\n$OUTPUT"
fi

test_case "release registration accepts the same leaf, scalar and container forms as assembly"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_REGISTRATION_FORMS'
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
root = Path(sys.argv[1])
temp_root = sys.argv[2]
source = (root / 'scripts/validate-release.sh').read_text()
section = source[source.index('find_skill_md_files()'):source.index('# 7. SKILL FRONTMATTER FORMAT CHECK')]
with tempfile.TemporaryDirectory(dir=temp_root) as temporary:
    fixture = Path(temporary)
    (fixture / '.claude-plugin').mkdir()
    (fixture / 'scripts').mkdir()
    shutil.copyfile(root / 'scripts/validate-plugin-assembly.py', fixture / 'scripts/validate-plugin-assembly.py')
    for name in ('one', 'pack/two'):
        path = fixture / 'skills' / name
        path.mkdir(parents=True)
        (path / 'SKILL.md').write_text('---\nname: ' + name.split('/')[-1] +
            '\ndescription: Fixture\ndisable-model-invocation: true\n---\nNative skill\n')
    shutil.copytree(fixture / 'skills', fixture / '.claude/skills')
    manifest = fixture / '.claude-plugin/plugin.json'
    valid = [['./skills/one/', './skills/pack/two/'], './skills/', ['./skills/'],
             ['./skills/one', './skills/pack/'], ['./skills/', './skills/one/']]
    invalid = [['./skills/missing/'], ['../escape'], [7], {'path': './skills/'}]
    for registrations in valid + invalid:
        manifest.write_text(json.dumps(dict(name='octo', version='1.0.0', description='Fixture', skills=registrations)))
        command = 'set -euo pipefail\nROOT_DIR="$1"\nerrors=0\nGREEN=\nNC=\nlog() { printf "%s\\n" "$*" >&2; }\n' + section + '\nexit "$errors"\n'
        result = subprocess.run(['bash', '-c', command, 'registration-check', str(fixture)], capture_output=True, text=True)
        assert (result.returncode == 0) == (registrations in valid), (registrations, result.stdout, result.stderr)
        if registrations in valid:
            assert 'All 2 skills properly registered' in result.stdout, (registrations, result.stdout)
print('5 supported and 4 invalid registration forms checked through the release section')
PY_REGISTRATION_FORMS
then test_pass; else test_fail "release and assembly disagree on supported registration forms"; fi

test_summary
