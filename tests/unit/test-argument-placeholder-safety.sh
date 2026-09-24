#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Command and skill bodies survive Claude Code argument substitution"

find_substituted_positionals() {
    python3 - "$@" <<'PY'
import re
import sys

placeholder = re.compile(r"\$(\d+)(?!\w)")

def body_lines(text):
    lines = text.split("\n")
    start = 0
    if lines and lines[0].strip() == "---":
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                start = index + 1
                break
    return enumerate(lines[start:], start + 1)

def escaped(line, dollar):
    return dollar >= 1 and line[dollar - 1] == "\\" and not (dollar >= 2 and line[dollar - 2] == "\\")

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    for number, line in body_lines(text):
        for match in placeholder.finditer(line):
            if not escaped(line, match.start()):
                print(f"{path}:{number}: {match.group(0)} in: {line.strip()}")
PY
}

surface_files() {
    local surface="$1"
    case "$surface" in
        commands)
            find "$PROJECT_ROOT/commands" -maxdepth 1 -type f -name '*.md' ;;
        cursor-commands)
            find "$PROJECT_ROOT/.cursor-plugin/commands" -maxdepth 1 -type f -name '*.md' ;;
        skill-sources)
            find "$PROJECT_ROOT/.claude/skills" -maxdepth 2 -type f \( -name 'SKILL.md' -o -name '*.tmpl' \)
            find "$PROJECT_ROOT/.claude/skills" -maxdepth 1 -type f -name '*.md' ;;
        shipped-skills)
            find "$PROJECT_ROOT/skills" -mindepth 2 -maxdepth 3 -type f -name 'SKILL.md' ;;
    esac | LC_ALL=C sort
}

test_case "scanner flags exactly the positional forms Claude Code substitutes"
fixture="$TEST_TMP_DIR/placeholder-fixture.md"
cat > "$fixture" <<'EOF'
---
description: frontmatter is not substituted $1
---
status_cli() { command -v "$1" >/dev/null 2>&1; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Estimated Cost: $0.01-0.05
awk '{print $10}'
doubled backslash still expands \\$2
braced ${1} and ${0}
awk field expression $(1)
escaped \$3.00
word suffix $1abc
all arguments $ARGUMENTS and $ARGUMENTS[0]
EOF
expected="$fixture:4: \$1 in: status_cli() { command -v \"\$1\" >/dev/null 2>&1; }
$fixture:5: \$0 in: SCRIPT_DIR=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)\"
$fixture:6: \$0 in: Estimated Cost: \$0.01-0.05
$fixture:7: \$10 in: awk '{print \$10}'
$fixture:8: \$2 in: doubled backslash still expands \\\\\$2"
actual="$(find_substituted_positionals "$fixture")"
if [[ "$actual" == "$expected" ]]; then
    test_pass
else
    test_fail "scanner output differs from the substitution rule; got:
$actual"
fi

for surface in commands cursor-commands skill-sources shipped-skills; do
    test_case "$surface contain no positional placeholder Claude Code would substitute"
    files=()
    while IFS= read -r file; do
        files+=("$file")
    done < <(surface_files "$surface")
    if [[ ${#files[@]} -eq 0 ]]; then
        test_fail "no $surface files found under $PROJECT_ROOT"
        continue
    fi
    hits="$(find_substituted_positionals "${files[@]}")"
    if [[ -z "$hits" ]]; then
        test_pass
    else
        test_fail "use \${N} in shell, \$(N) in awk, or \\\$ before a literal amount:
${hits//$PROJECT_ROOT\//}"
    fi
done

test_summary
