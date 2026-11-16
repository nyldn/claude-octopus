#!/usr/bin/env bash
# Hosts run a command's shell blocks in the user's login shell: Claude Code's
# Bash tool uses zsh on macOS. Libraries that need bash refuse any other shell,
# and every block that loads one, or calls one of its functions, runs itself
# under bash through one fixed wrapper. Under bash the wrapper evaluates the
# block in place, so state shared with neighbouring blocks is unchanged.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "host shell bash blocks"

GUARD_TEXT='must be sourced from bash'
BASH_ONLY_LIBS=()
while IFS= read -r lib; do
    BASH_ONLY_LIBS+=("$lib")
done < <(cd "$PROJECT_ROOT" && grep -rlF --include='*.sh' "$GUARD_TEXT" scripts | sort)

test_case "the bash-only libraries are found by their guard"
expected="scripts/context-manager.sh scripts/lib/consultative-advisors.sh scripts/lib/provider-allowlist.sh"
found="${BASH_ONLY_LIBS[*]:-}"
missing=""
for lib in $expected; do
    [[ " $found " == *" $lib "* ]] || missing+="$lib "
done
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "no bash guard in: $missing(found: ${found:-none})"
fi

test_case "a bash-only library sourced from zsh names the fix"
if command -v zsh >/dev/null 2>&1; then
    wrong=""
    for lib in ${BASH_ONLY_LIBS[@]+"${BASH_ONLY_LIBS[@]}"}; do
        rc=0
        err="$(cd "$TEST_TMP_DIR" && zsh -fc 'source "$1"' zsh "$PROJECT_ROOT/$lib" 2>&1 >/dev/null)" || rc=$?
        if [[ "$rc" -eq 0 || "$err" != *"$GUARD_TEXT"* ]]; then
            wrong+="$lib (rc=$rc: $(printf '%s' "$err" | head -2 | tr '\n' '|')) "
        fi
    done
    if [[ -z "$wrong" ]]; then
        test_pass
    else
        test_fail "$wrong"
    fi
else
    test_skip "zsh not installed"
fi

test_case "a bash-only library still sources from bash"
wrong=""
for lib in ${BASH_ONLY_LIBS[@]+"${BASH_ONLY_LIBS[@]}"}; do
    rc=0
    err="$(cd "$TEST_TMP_DIR" && HOME="$TEST_TMP_DIR" bash -c 'source "$1"' bash "$PROJECT_ROOT/$lib" 2>&1 >/dev/null)" || rc=$?
    if [[ "$rc" -ne 0 || "$err" == *"$GUARD_TEXT"* ]]; then
        wrong+="$lib (rc=$rc: $(printf '%s' "$err" | head -2 | tr '\n' '|')) "
    fi
done
if [[ -z "$wrong" ]]; then
    test_pass
else
    test_fail "$wrong"
fi

test_case "every block that loads a bash-only library runs under bash"
cat > "$TEST_TMP_DIR/scan-blocks.py" <<'CHECK'
import pathlib
import re
import sys
import textwrap

root = pathlib.Path(sys.argv[1])
libs = [root / lib for lib in sys.argv[2:]]
wrapper = 'if [ -n "${BASH_VERSION:-}" ]; then eval "$(cat)"; else bash -c "$(cat)"; fi <<\'OCTO_BASH\''

lib_names = {lib.name for lib in libs}
functions = {}
for lib in libs:
    for name in re.findall(r'(?m)^(octo_[A-Za-z0-9_]+)\s*\(\)\s*\{', lib.read_text()):
        functions[name] = lib.name
source_re = re.compile(r'(?m)^\s*(?:if\s+!?\s*)?(?:source|\.)\s+"?([^"\s]+)')
assign_re = re.compile(r'(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)="?[^"\n]*/([A-Za-z0-9_.-]+\.sh)"?\s*$')
call_re = re.compile(r'\b(' + '|'.join(sorted(functions)) + r')\b') if functions else None


def sourced_libs(block):
    paths = dict(assign_re.findall(block))
    names = set()
    for target in source_re.findall(block):
        variable = re.fullmatch(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?', target)
        name = paths.get(variable.group(1), '') if variable else target.rsplit('/', 1)[-1]
        if name in lib_names:
            names.add(name)
    return names

documents = []
for pattern in ('commands/*.md', 'skills/*/SKILL.md', '.claude/skills/*/SKILL.md',
                '.cursor-plugin/commands/*.md'):
    documents.extend(sorted(root.glob(pattern)))

nested_heredoc_re = re.compile(r"<<-?'([A-Za-z_][A-Za-z0-9_]*)'\n.*?\n\1\n", re.S)
reference_re = re.compile(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)')
assigned_re = re.compile(r'(?:^|[\s;!(])([A-Za-z_][A-Za-z0-9_]*)=')
loop_re = re.compile(r'\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b')
read_re = re.compile(r'\bread((?:\s+[^\s;|<>]+)+)')
environment = {'HOME', 'TMPDIR', 'PATH'}
environment_prefixes = ('CLAUDE_', 'CODEX_', 'OCTOPUS_', 'OCTO_')


def unset_inputs(block):
    body = block.split(wrapper, 1)[1].rsplit('OCTO_BASH', 1)[0]
    body = nested_heredoc_re.sub('\n', body)
    assigned = set(assigned_re.findall(body)) | set(loop_re.findall(body))
    for names in read_re.findall(body):
        assigned |= {name for name in names.split()
                     if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name)}
    return sorted(name for name in set(reference_re.findall(body)) - assigned
                  if name not in environment and not name.startswith(environment_prefixes))


problems = []
checked = 0
for document in documents:
    lines = document.read_text().split('\n')
    i = 0
    prose_start = 0
    while i < len(lines):
        if not re.match(r'^\s*```bash\s*$', lines[i]):
            if re.match(r'^\s*```', lines[i]):
                prose_start = i + 1
            i += 1
            continue
        start = i
        j = i + 1
        while j < len(lines) and not re.match(r'^\s*```\s*$', lines[j]):
            j += 1
        block = textwrap.dedent('\n'.join(lines[start + 1:j]))
        prose = '\n'.join(lines[prose_start:start])
        i = j + 1
        prose_start = i
        where = f'{document.relative_to(root)}:{start + 1}'
        code = [line for line in block.split('\n')
                if line.strip() and not line.lstrip().startswith('#')]
        wrapped = bool(code) and code[0] == wrapper and code[-1] == 'OCTO_BASH'
        if wrapped:
            missing = [name for name in unset_inputs(block)
                       if 'Export' not in prose or f'`{name}`' not in prose]
            if missing:
                problems.append(f'input: {where}: uses {", ".join(missing)} without setting it '
                                'inside the heredoc or naming it for export before the block')
        sourced = sourced_libs(block)
        called = set(call_re.findall(block)) if call_re else set()
        if not sourced and not called:
            continue
        checked += 1
        if not wrapped:
            problems.append(f'wrap: {where}: not wrapped to run under bash')
        unsourced = sorted({functions[name] for name in called} - sourced)
        if unsourced:
            problems.append(f'wrap: {where}: calls functions from {", ".join(unsourced)} without sourcing it')

if checked < 9:
    problems.append(f'wrap: only {checked} blocks load a bash-only library; the scan is not finding them')
print('\n'.join(problems))
CHECK
rc=0
report="$(python3 "$TEST_TMP_DIR/scan-blocks.py" "$PROJECT_ROOT" ${BASH_ONLY_LIBS[@]+"${BASH_ONLY_LIBS[@]}"})" || rc=$?
wrap_report="$(grep '^wrap: ' <<< "$report" || true)"
if [[ "$rc" -eq 0 && -z "$wrap_report" ]]; then
    test_pass
else
    test_fail "rc=$rc $(printf '%s' "$wrap_report" | tr '\n' '|')"
fi

# Under zsh a wrapped block is a separate bash process, which sees only exported
# variables, and no host shell keeps variables between tool calls. A value set
# outside the heredoc, or by an earlier block, is empty inside it.
test_case "every wrapped block sets its inputs inside the heredoc or names them for export"
input_report="$(grep '^input: ' <<< "$report" || true)"
if [[ "$rc" -eq 0 && -z "$input_report" ]]; then
    test_pass
else
    test_fail "rc=$rc $(printf '%s' "$input_report" | tr '\n' '|')"
fi

# A heredoc inside $( ... ) is re-parsed by bash 3.2 (macOS /bin/bash), which
# joins backslash-continued lines and misreads quotes, so the wrapper reads its
# block with a plain $(cat). The block below carries both.
IFS= read -r -d '' WRAPPED_BLOCK <<'BLOCK' || true
if [ -n "${BASH_VERSION:-}" ]; then eval "$(cat)"; else bash -c "$(cat)"; fi <<'OCTO_BASH'
BLOCK_VALUE="${OUTER_VALUE:-unset}"
joined=$(printf '%s|' one \
    two)
case "$joined" in
    'one|two|') shape=kept ;;
    *) shape="changed:$joined" ;;
esac
note="it's (unbalanced"
printf 'bash=%s value=%s shape=%s note=%s\n' "${BASH_VERSION:+yes}" "$BLOCK_VALUE" "$shape" "$note"
OCTO_BASH
BLOCK
EXPECTED_LINE="bash=yes value=VALUE shape=kept note=it's (unbalanced"

test_case "the wrapper runs a block under bash from zsh, byte-exact"
if command -v zsh >/dev/null 2>&1; then
    rc=0
    out="$(cd "$TEST_TMP_DIR" && OUTER_VALUE=VALUE zsh -fc "$WRAPPED_BLOCK" 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 && "$out" == "$EXPECTED_LINE" ]]; then
        test_pass
    else
        test_fail "rc=$rc output: $out"
    fi
else
    test_skip "zsh not installed"
fi

test_case "under bash the wrapper evaluates the block in the calling shell"
rc=0
out="$(cd "$TEST_TMP_DIR" && bash -c "OUTER_VALUE=VALUE
$WRAPPED_BLOCK
printf 'after=%s\n' \"\$BLOCK_VALUE\"" 2>&1)" || rc=$?
if [[ "$rc" -eq 0 && "$out" == "$EXPECTED_LINE"$'\n'"after=VALUE" ]]; then
    test_pass
else
    test_fail "rc=$rc output: $(printf '%s' "$out" | tr '\n' '|')"
fi

test_case "the wrapper passes a failing block's exit status to the host shell"
failing="$(printf '%s\n' "${WRAPPED_BLOCK%%$'\n'*}" 'exit 7' 'OCTO_BASH')"
expected="bash=7 "
command -v zsh >/dev/null 2>&1 && expected+="zsh=7 "
statuses=""
for shell in bash zsh; do
    command -v "$shell" >/dev/null 2>&1 || continue
    rc=0
    (cd "$TEST_TMP_DIR" && "$shell" -c "$failing") >/dev/null 2>&1 || rc=$?
    statuses+="$shell=$rc "
done
if [[ "$statuses" == "$expected" ]]; then
    test_pass
else
    test_fail "statuses: $statuses (expected $expected)"
fi

test_case "user values in wrapped recipes remain literal shell data"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_LITERAL'
import pathlib
import re
import shlex
import subprocess
import sys

root, scratch = map(pathlib.Path, sys.argv[1:])
marker = scratch / 'unexpected-expansion'
payload = f'''a 'single' and "double" quote; $HOME $(touch {marker}) `touch {marker}`
second line \\ final'''
targets = {
    '.claude/skills/flow-define/SKILL.md': ['USER_REQUEST', 'user_flow', 'approach', 'out_of_scope'],
    '.claude/skills/skill-debate/SKILL.md': ['QUESTION', 'CONTEXT', 'MAX_WORDS', 'DEBATE_DIR', 'ADVISORS', 'REQUIRED_EXTERNAL_ADVISORS', 'SUCCESSFUL_EXTERNAL_ADVISORS', 'HOST_ADVISOR_SUCCESS'],
    'commands/brainstorm.md': ['TOPIC', 'SUCCESSFUL_EXTERNAL_ADVISORS', 'HOST_ADVISOR_SUCCESS'],
}
for source, names in list(targets.items()):
    if source.startswith('.claude/'):
        targets[source.removeprefix('.claude/')] = names
targets['.cursor-plugin/commands/octo-brainstorm.md'] = targets['commands/brainstorm.md']
for source, names in targets.items():
    text = (root / source).read_text()
    for name in names:
        assignments = re.findall(rf'(?m)^{name}=(.*)$', text)
        literals = [value for value in assignments if value.startswith(('"[', "'[")) or 'Should we use Redis' in value]
        assert literals, (source, name, 'missing input assignment')
        for literal in literals:
            # Insert exactly the quote-escaped contents of the value into the
            # recipe's existing quote delimiters. The old double quotes execute
            # command substitutions; single quotes preserve every byte.
            quoted = shlex.quote(payload)
            assignment = name + '=' + literal[0] + quoted[1:-1] + literal[-1]
            result = subprocess.run(['bash', '-c', assignment + '\nprintf %s "$' + name + '"'], capture_output=True, text=True)
            assert result.returncode == 0 and result.stdout == payload, (source, name, result.stderr, result.stdout)
            assert not marker.exists(), (source, name, 'executed input')
PY_LITERAL
then
    test_pass
else
    test_fail "a recipe expanded or altered user input"
fi

test_summary
