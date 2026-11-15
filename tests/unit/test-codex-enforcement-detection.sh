#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/build-codex-skills.sh"

test_suite "Codex skill enforcement detection"

write_fixture() {
    local path="$1"
    local body="$2"

    {
        printf '%s\n' '---'
        printf '%s\n' 'name: enforcement-fixture'
        printf '%s\n' 'execution_mode: enforced'
        printf '%s\n' '---'
        printf '%s\n' "$body"
    } > "$path"
}

test_case "empty Execution Contract heading does not suppress generated enforcement"
empty_contract="$TEST_TMP_DIR/empty-contract.md"
write_fixture "$empty_contract" $'## Execution Contract\n\n## Workflow\n\nRun the workflow.'
empty_adapted="$(adapt_body_for_codex "$empty_contract")"
if body_has_enforcement "$empty_contract"; then
    test_fail "empty contract heading was treated as enforcement"
elif grep -q 'This generated Codex skill preserves an enforced workflow contract' <<< "$empty_adapted"; then
    test_pass
else
    test_fail "empty contract did not receive generated enforcement"
fi

test_case "Execution Contract heading inside a fenced example is ignored"
fenced_contract="$TEST_TMP_DIR/fenced-contract.md"
write_fixture "$fenced_contract" $'## Example\n\n```markdown\n## Execution Contract\n\nYou MUST run the command.\n```\n\n## Workflow\n\nRun the workflow.'
fenced_adapted="$(adapt_body_for_codex "$fenced_contract")"
if body_has_enforcement "$fenced_contract"; then
    test_fail "fenced example was treated as the real execution contract"
elif grep -q 'This generated Codex skill preserves an enforced workflow contract' <<< "$fenced_adapted"; then
    test_pass
else
    test_fail "fenced example did not receive generated enforcement"
fi

test_case "legacy marker outside an enforcement section does not suppress generated enforcement"
unrelated_marker="$TEST_TMP_DIR/unrelated-marker.md"
write_fixture "$unrelated_marker" $'## Notes\n\nThe release CANNOT SKIP the changelog.\n\n## Workflow\n\nRun the workflow.'
unrelated_adapted="$(adapt_body_for_codex "$unrelated_marker")"
if body_has_enforcement "$unrelated_marker"; then
    test_fail "unrelated legacy marker was treated as enforcement"
elif grep -q 'This generated Codex skill preserves an enforced workflow contract' <<< "$unrelated_adapted"; then
    test_pass
else
    test_fail "fixture with unrelated marker did not receive generated enforcement"
fi

test_case "real Execution Contract with mandatory content is detected"
real_contract="$TEST_TMP_DIR/real-contract.md"
write_fixture "$real_contract" $'## Execution Contract\n\nYou MUST run the command.\n\n**PROHIBITED:** Do not simulate it.\n\n## Workflow\n\nRun the workflow.'
real_adapted="$(adapt_body_for_codex "$real_contract")"
real_contract_count="$(grep -c '^## Execution Contract' <<< "$real_adapted" || true)"
if ! body_has_enforcement "$real_contract"; then
    test_fail "mandatory contract content was not detected"
elif grep -q 'This generated Codex skill preserves an enforced workflow contract' <<< "$real_adapted"; then
    test_fail "real contract received a duplicate generated enforcement block"
elif [[ "$real_contract_count" -eq 1 ]]; then
    test_pass
else
    test_fail "adapted output contained $real_contract_count execution-contract headings"
fi

test_case "generated primary and alias metadata preserve source text and bound UI descriptions"
fixture_root="$TEST_TMP_DIR/codex-generator"
SKILLS_DIR="$fixture_root/source"
OUTPUT_DIR="$fixture_root/output"
NATIVE_OUTPUT_DIR="$fixture_root/native"
mkdir -p "$NATIVE_OUTPUT_DIR"
mkdir -p "$SKILLS_DIR/skill-verification-gate"
cat > "$SKILLS_DIR/skill-verification-gate/SKILL.md" <<'EOF'
---
name: skill-verification-gate
description: "Use this deliberately long primary description to verify that SKILL metadata retains its full text while the separate Codex interface blurb is bounded correctly"
codex_alias_description: "Use this deliberately long alias description to verify that compatibility aliases also receive bounded Codex interface metadata without truncating SKILL metadata"
---

# Fixture
EOF
main >/dev/null

expected_primary="Use this deliberately long primary description to verify that SKILL metadata retains its full text while the separate Codex interface blurb is bounded correctly"
expected_alias="Use this deliberately long alias description to verify that compatibility aliases also receive bounded Codex interface metadata without truncating SKILL metadata"
metadata_ok=true
for generated in skill-verification-gate skill-verify; do
    skill_desc=$(sed -n 's/^description: "\(.*\)"$/\1/p' "$OUTPUT_DIR/$generated/SKILL.md")
    ui_desc=$(sed -n 's/^  short_description: "\(.*\)"$/\1/p' "$OUTPUT_DIR/$generated/agents/openai.yaml")
    if [[ "$generated" == "skill-verification-gate" ]]; then
        expected_skill_desc="$expected_primary"
        expected_ui_desc="Use this deliberately long primary description to verify that..."
    else
        expected_skill_desc="$expected_alias"
        expected_ui_desc="Use this deliberately long alias description to verify that..."
    fi
    if [[ "$skill_desc" != "$expected_skill_desc" ]] ||
       (( ${#ui_desc} < 25 || ${#ui_desc} > 64 )) ||
       [[ "$ui_desc" != "$expected_ui_desc" ]]; then
        metadata_ok=false
    fi
done
if [[ "$metadata_ok" == true ]]; then
    test_pass
else
    test_fail "primary or alias metadata lost exact SKILL text or produced invalid UI text"
fi

test_case "UI short descriptions honor 24, 25, 64, and 65 character boundaries"
input_24="123456789012345678901234"
input_25="${input_24}5"
sixty_zeros=$(printf '%060d' 0)
input_64="${sixty_zeros} cat"
word_prefix=""
for ((word_index = 0; word_index < 30; word_index++)); do
    word_prefix="${word_prefix}a "
done
input_65="${word_prefix}words"
if [[ "$(ui_short_description "$input_24" Fixture)" == "Help with Fixture tasks and workflows" ]] &&
   [[ "$(ui_short_description "$input_25" Fixture)" == "$input_25" ]] &&
   [[ "$(ui_short_description "$input_64" Fixture)" == "$input_64" ]] &&
   [[ "$(ui_short_description "$input_65" Fixture)" == "${word_prefix% }..." ]]; then
    test_pass
else
    test_fail "ui_short_description did not preserve exact boundaries or trim at a complete word"
fi


test_case "native output cleanup initializes an absent output directory"
NATIVE_OUTPUT_DIR="$fixture_root/absent-native"
if prepare_target_dir "$NATIVE_OUTPUT_DIR" && [[ -d "$NATIVE_OUTPUT_DIR" ]]; then
    test_pass
else
    test_fail "missing native output directory cannot be rebuilt"
fi

test_case "native generation inserts a missing source name without changing its body"
mkdir -p "$SKILLS_DIR/fallback-name"
cat > "$SKILLS_DIR/fallback-name/SKILL.md" <<'EOF'
---
description: Fixture with a filename-derived name
disable-model-invocation: true
---

# Missing name fixture

Keep this body unchanged.
name: this-body-line-is-not-frontmatter
EOF
main >/dev/null
if python3 - "$NATIVE_OUTPUT_DIR/fallback-name/SKILL.md" "$SKILLS_DIR/fallback-name/SKILL.md" <<'PY'
import sys
from pathlib import Path
generated, source = (Path(p).read_text() for p in sys.argv[1:])
assert generated == source.replace('\n---\n', '\nname: fallback-name\n---\n', 1), generated
PY
then
    test_pass
else
    test_fail "native entry did not receive the filename-derived frontmatter name"
fi

test_case "native name insertion respects CRLF and spaced frontmatter delimiters"
if python3 - "$PROJECT_ROOT/scripts/build-codex-skills.sh" "$TEST_TMP_DIR" <<'PY'
import subprocess
import sys
from pathlib import Path
generator, directory = sys.argv[1:]
root = Path(directory)
for index, (ending, delimiter) in enumerate(((b'\r\n', b'---'), (b'\n', b'---  '))):
    for named in (False, True):
        name = b'name: original' + ending if named else b''
        header = b'---' + ending + name + b'description: Fixture' + ending
        body = ending + b'name: this body must remain unchanged' + ending
        source = root / f'native-{index}-{named}.md'
        source.write_bytes(header + delimiter + ending + body)
        output = root / f'native-{index}-{named}'
        subprocess.run(['bash', '-c', 'source "$1"; write_native_skill "$2" "$3" fallback-name',
                        'fixture', generator, str(source), str(output)], check=True)
        expected_header = header.replace(name, b'name: fallback-name' + ending, 1) if named else header + b'name: fallback-name' + ending
        assert (output / 'SKILL.md').read_bytes() == expected_header + delimiter + ending + body
PY
then test_pass; else test_fail "native name writer changed body bytes or missed the closing delimiter"; fi

test_summary
