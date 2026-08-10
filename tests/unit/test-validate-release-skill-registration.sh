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

test_summary
