#!/usr/bin/env bash
# Test that live public references resolve to installed commands, skills, or files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "public reference integrity"

VALID_NAMES="$TEST_TMP_DIR/valid-octo-names"
REFERENCES="$TEST_TMP_DIR/public-octo-references"

jq -r '.commands[] | split("/")[-1] | sub("[.]md$"; "")' \
  "$PROJECT_ROOT/.claude-plugin/plugin.json" > "$VALID_NAMES"

# Claude Code exposes registered plugin skills by their installed skill name.
# Older lifecycle skills also document the name without the skill- prefix.
jq -r '.skills[] | split("/")[-1]' \
  "$PROJECT_ROOT/.claude-plugin/plugin.json" >> "$VALID_NAMES"
jq -r '.skills[] | split("/")[-1] | sub("^skill-"; "")' \
  "$PROJECT_ROOT/.claude-plugin/plugin.json" >> "$VALID_NAMES"

# Frontmatter aliases are explicit compatibility entries. The retired shell
# workflow name "ink" is intentionally excluded from slash-command validity.
for command_file in "$PROJECT_ROOT"/commands/*.md; do
  awk '
    NR == 1 && $0 == "---" { frontmatter = 1; next }
    frontmatter && $0 == "---" { exit }
    frontmatter && /^aliases:/ { aliases = 1; next }
    frontmatter && aliases && /^[[:space:]]+-[[:space:]]+/ {
      sub(/^[[:space:]]+-[[:space:]]+/, "")
      print
      next
    }
    frontmatter && aliases && !/^[[:space:]]/ { aliases = 0 }
  ' "$command_file"
done | grep -vx 'ink' >> "$VALID_NAMES"

# Hook-level aliases are compatibility entries only when their destination is
# still a registered command. Parse the authoritative case table rather than
# maintaining another hand-written alias list.
ALIAS_TABLE="$TEST_TMP_DIR/compatibility-aliases"
awk '
  /octo_alias_for[(][)]/ { in_aliases = 1; next }
  in_aliases && /^[[:space:]]*esac/ { exit }
  in_aliases && /[)] echo "/ {
    line = $0
    sub(/^[[:space:]]*/, "", line)
    split(line, parts, ") echo \"")
    aliases = parts[1]
    target = parts[2]
    sub(/\".*/, "", target)
    print aliases "|" target
  }
' "$PROJECT_ROOT/hooks/user-prompt-submit.sh" > "$ALIAS_TABLE"
while IFS= read -r alias_entry; do
  aliases="${alias_entry%|*}"
  target="${alias_entry##*|}"
  if grep -Fxq "$target" "$VALID_NAMES"; then
    printf '%s\n' "$aliases" | tr '|' '\n'
  fi
done < "$ALIAS_TABLE" >> "$VALID_NAMES"

sort -u "$VALID_NAMES" -o "$VALID_NAMES"

PUBLIC_SURFACES=(
  "$PROJECT_ROOT"/commands/*.md
  "$PROJECT_ROOT/docs/COMMAND-REFERENCE.md"
)

for surface in "${PUBLIC_SURFACES[@]}"; do
  grep -Eo '/octo:[A-Za-z0-9_-]+' "$surface" || true
done | sed 's#^/octo:##' | sort -u > "$REFERENCES"

test_case "Every live /octo reference resolves"
unresolved="$(comm -23 "$REFERENCES" "$VALID_NAMES" | grep -vx 'doctor' || true)"
if [[ -z "$unresolved" ]]; then
  test_pass
else
  test_fail "unresolved slash commands: $(printf '%s' "$unresolved" | tr '\n' ' ')"
fi

test_case "Retired /octo:doctor appears only in its documented explanation"
doctor_lines="$(grep -RFn '/octo:doctor' "${PUBLIC_SURFACES[@]}" || true)"
if [[ "$(printf '%s\n' "$doctor_lines" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ]] &&
   printf '%s\n' "$doctor_lines" | grep -Fq 'intentionally leaves `/octo:doctor` unregistered'; then
  test_pass
else
  test_fail "retired /octo:doctor must appear once in docs/COMMAND-REFERENCE.md"
fi

test_case "Shell workflow aliases are not presented as slash commands"
if grep -RFn '/octo:ink' "${PUBLIC_SURFACES[@]}" >/dev/null; then
  test_fail "ink is a shell workflow alias; present the registered /octo:deliver command instead"
else
  test_pass
fi

test_case "Plugin command, skill, and hook paths resolve"
missing_paths=0
while IFS= read -r relative_path; do
  relative_path="${relative_path#./}"
  if [[ ! -e "$PROJECT_ROOT/$relative_path" ]]; then
    printf 'missing manifest path: %s\n' "$relative_path"
    missing_paths=$((missing_paths + 1))
  fi
done < <(
  jq -r '.commands[], .skills[]' "$PROJECT_ROOT/.claude-plugin/plugin.json"
  printf '%s\n' './hooks/hooks.json'
)
if [[ "$missing_paths" -eq 0 ]]; then
  test_pass
else
  test_fail "$missing_paths plugin manifest path(s) do not resolve"
fi

test_case "Installed-root script and skill references resolve"
REFERENCE_PATHS="$TEST_TMP_DIR/installed-root-paths"
for surface in "${PUBLIC_SURFACES[@]}"; do
  grep -Eho '(claude-octopus/plugin|CLAUDE_PLUGIN_ROOT}|OCTO_ROOT})/[.A-Za-z0-9_/-]+' "$surface" || true
done |
  sed -E 's#^(claude-octopus/plugin|CLAUDE_PLUGIN_ROOT}|OCTO_ROOT})/##' |
  sort -u > "$REFERENCE_PATHS"

missing_references=0
while IFS= read -r relative_path; do
  [[ -n "$relative_path" ]] || continue
  if [[ ! -e "$PROJECT_ROOT/$relative_path" ]]; then
    printf 'missing installed-root reference: %s\n' "$relative_path"
    missing_references=$((missing_references + 1))
  fi
done < "$REFERENCE_PATHS"

if [[ "$missing_references" -eq 0 ]]; then
  test_pass
else
  test_fail "$missing_references installed-root reference(s) do not resolve"
fi

test_case "Generated Cursor command sources resolve"
missing_generated=0
while IFS= read -r command_name; do
  generated_name="octo-${command_name}.md"
  [[ "$command_name" == "octo" ]] && generated_name="octo.md"
  if [[ ! -f "$PROJECT_ROOT/.cursor-plugin/commands/$generated_name" ]]; then
    printf 'missing generated Cursor command: %s\n' "$generated_name"
    missing_generated=$((missing_generated + 1))
  fi
done < <(jq -r '.commands[] | split("/")[-1] | sub("[.]md$"; "")' "$PROJECT_ROOT/.claude-plugin/plugin.json")

# Cursor deliberately has a Doctor adapter generated from skill-doctor. It is
# not evidence that Claude Code registers the retired /octo:doctor command.
if [[ ! -f "$PROJECT_ROOT/.cursor-plugin/commands/octo-doctor.md" ]]; then
  printf 'missing generated Cursor Doctor adapter\n'
  missing_generated=$((missing_generated + 1))
fi

if [[ "$missing_generated" -eq 0 ]]; then
  test_pass
else
  test_fail "$missing_generated generated command source(s) do not resolve"
fi

test_summary
