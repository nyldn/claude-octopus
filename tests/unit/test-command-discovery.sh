#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Installed command discovery"

test_case "guide lists only commands declared by the installed manifest"
output="$(HOME="$TEST_TMP_DIR" "$PROJECT_ROOT/bin/octopus" guide --json 2>/dev/null || true)"
if jq -e --slurpfile manifest "$PROJECT_ROOT/.claude-plugin/plugin.json" '
    .commands | length == ($manifest[0].commands | length)' <<<"$output" >/dev/null 2>&1 &&
    [[ ! -d "$TEST_TMP_DIR/.claude-octopus" ]]; then test_pass; else test_fail "guide missing, incomplete, or initialized state"; fi

test_case "automatic help uses the same provider-free catalog"
auto_output="$(HOME="$TEST_TMP_DIR" "$PROJECT_ROOT/scripts/orchestrate.sh" auto help 2>/dev/null || true)"
if [[ "$auto_output" == *"/octo:setup"* && "$auto_output" == *"/octo:auto"* && ! -d "$TEST_TMP_DIR/.claude-octopus" ]]; then
    test_pass
else test_fail "auto help did not return the installed catalog without workflow state"; fi

test_case "public explain command reaches its runtime parser"
output="$(HOME="$TEST_TMP_DIR" "$PROJECT_ROOT/bin/octopus" explain --help 2>&1 || true)"
if [[ "$output" != *"Unknown octopus command"* && "$output" == *"explain"* ]]; then test_pass; else test_fail "explain is not dispatched"; fi

test_case "legacy setup alias reaches setup"
output="$(HOME="$TEST_TMP_DIR" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$PROJECT_ROOT/hooks/user-prompt-submit.sh" <<< '{"prompt":"/octo:sys-setup"}' 2>/dev/null || true)"
if [[ "$output" == *"Alias resolved: /octo:sys-setup -> /octo:setup"* ]]; then test_pass; else test_fail "sys-setup does not resolve to setup"; fi
test_case "guide preserves readable entries when one command is damaged"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import json
from pathlib import Path
import shutil
import subprocess
import sys
root = Path(sys.argv[2]) / "guide-fixture"
(root / "scripts").mkdir(parents=True)
(root / ".claude-plugin").mkdir()
(root / "commands").mkdir()
shutil.copyfile(Path(sys.argv[1]) / "scripts/guide.py", root / "scripts/guide.py")
(root / ".claude-plugin/plugin.json").write_text(json.dumps({"version": "test", "commands": ["commands/good.md", "commands/bad.md"]}))
(root / "commands/good.md").write_text('---\ndescription: "Valid entry"\n---\n')
(root / "commands/bad.md").write_text("Missing frontmatter\n")
result = subprocess.run([sys.executable, str(root / "scripts/guide.py"), "--json"], capture_output=True, text=True)
assert result.returncode == 0, result.stderr
assert json.loads(result.stdout)["commands"] == [{"command": "/octo:good", "description": "Valid entry"}]
assert "bad.md" in result.stderr, result.stderr
PY
then test_pass; else test_fail "one damaged entry disabled the guide"; fi

test_case "guide, doctor and refine preserve explicit host root precedence"
if python3 - "$PROJECT_ROOT" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
root = Path(sys.argv[1])
for relative in ("commands/guide.md", "skills/skill-doctor/SKILL.md", "skills/skill-refine/SKILL.md"):
    match = re.search(r'^OCTO_(?:PLUGIN_)?ROOT=(.+)$', (root / relative).read_text(), re.MULTILINE)
    assert match, relative
    clean = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_PLUGIN_ROOT", "CODEX_PLUGIN_ROOT", "OCTO_ROOT", "OCTO_SKILL_FILE")}
    cases = [({"CLAUDE_PLUGIN_ROOT": "/claude", "CODEX_PLUGIN_ROOT": "/codex"}, "/claude"),
             ({"CODEX_PLUGIN_ROOT": "/codex"}, "/codex")]
    if relative == "skills/skill-refine/SKILL.md":
        cases.extend([({"OCTO_ROOT": "/explicit"}, "/explicit"), ({}, "")])
    for pins, expected in cases:
        result = subprocess.run(["bash", "-c", 'selected=' + match.group(1) + '; printf "%s" "$selected"'], env={**clean, **pins}, capture_output=True, text=True, check=True)
        assert result.stdout == expected, (relative, pins, result.stdout)
    if relative == "skills/skill-refine/SKILL.md":
        block = re.search(r'```bash\n(.*?)\n```', (root / relative).read_text(), re.S)
        assert block, f"{relative}: no root-resolution block"
        with tempfile.TemporaryDirectory() as home:
            unresolved = subprocess.run(["bash", "-eu", "-c", block.group(1)],
                env={**clean, "HOME": home}, capture_output=True, text=True)
            assert unresolved.returncode != 0, "unresolved refinement used another installation"
            assert "Cannot resolve this installed Octopus skill" in unresolved.stderr, unresolved.stderr
PY
then test_pass; else test_fail "host root precedence or unresolved-root handling differs"; fi

test_case "unknown CLI commands return a usage error"
rc=0
output="$(HOME="$TEST_TMP_DIR" "$PROJECT_ROOT/bin/octopus" not-a-command 2>&1)" || rc=$?
if [[ "$rc" == 2 && "$output" == *"Unknown octopus command"* ]]; then test_pass; else test_fail "unknown command did not return exit 2"; fi

test_case "every installed command path honors both host pins ahead of the shared alias"
if python3 - "$PROJECT_ROOT" <<'ROOTS'
from pathlib import Path
import os, subprocess, sys, tempfile
root = Path(sys.argv[1])
expression = '${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}'
prd_expression = '${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${OCTO_ROOT:-${HOME}/.claude-octopus/plugin}}}'
checked = 0
for path in (root/'commands').glob('*.md'):
    text = path.read_text()
    if '${HOME}/.claude-octopus/plugin' not in text:
        continue
    allowed = prd_expression if path.name == 'prd.md' else expression
    assert '${HOME}/.claude-octopus/plugin' not in text.replace(allowed, ''), path
    for pins, expected in [({'CLAUDE_PLUGIN_ROOT':'/selected-claude','CODEX_PLUGIN_ROOT':'/other-codex'}, '/selected-claude'), ({'CODEX_PLUGIN_ROOT':'/selected-codex'}, '/selected-codex'), ({}, '/fixture-home/.claude-octopus/plugin')]:
        env = dict(os.environ, HOME='/fixture-home')
        env.pop('CLAUDE_PLUGIN_ROOT',None);env.pop('CODEX_PLUGIN_ROOT',None);env.update(pins)
        result = subprocess.run(['bash','-c','printf "%s" "'+expression+'"'], env=env, capture_output=True,text=True,check=True)
        assert result.stdout == expected, (path, result.stdout)
    checked += 1
assert checked >= 24, checked
ROOTS
then test_pass; else test_fail "a command can use another installation"; fi

test_case "PRD dispatch preserves the resolved installation below explicit host roots"
if python3 - "$PROJECT_ROOT" <<'PRD_ROOTS'
from pathlib import Path
import os
import re
import subprocess
import sys

root = Path(sys.argv[1])
clean = {key: value for key, value in os.environ.items()
         if key not in ('CLAUDE_PLUGIN_ROOT', 'CODEX_PLUGIN_ROOT', 'OCTO_ROOT')}
clean['HOME'] = '/fixture home'
cases = [({'CLAUDE_PLUGIN_ROOT': '/claude root', 'CODEX_PLUGIN_ROOT': '/codex root',
           'OCTO_ROOT': '/resolved root'}, '/claude root'),
         ({'CODEX_PLUGIN_ROOT': '/codex root', 'OCTO_ROOT': '/resolved root'}, '/codex root'),
         ({'OCTO_ROOT': '/resolved root'}, '/resolved root'),
         ({'CLAUDE_PLUGIN_ROOT': '', 'CODEX_PLUGIN_ROOT': '', 'OCTO_ROOT': '/resolved root'}, '/resolved root'),
         ({'OCTO_ROOT': ''}, '/fixture home/.claude-octopus/plugin'),
         ({}, '/fixture home/.claude-octopus/plugin')]
for relative in ('commands/prd.md', '.cursor-plugin/commands/octo-prd.md'):
    assignments = re.findall(r'^OCTO_ROOT=.+$', (root / relative).read_text(), re.M)
    assert len(assignments) == 2, (relative, assignments)
    for assignment in assignments:
        for pins, expected in cases:
            result = subprocess.run(['bash', '-eu', '-c', assignment + '; printf "%s" "$OCTO_ROOT"'],
                env=dict(clean, **pins), capture_output=True, text=True, check=True)
            assert result.stdout == expected, (relative, assignment, pins, expected, result.stdout)
PRD_ROOTS
then test_pass; else test_fail "PRD replaced the resolved installation"; fi

test_case "workflow source templates preserve host-root precedence"
if python3 - "$PROJECT_ROOT" <<'TEMPLATE_ROOTS'
from pathlib import Path
import os
import re
import subprocess
import sys

root = Path(sys.argv[1])
old = '${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}'
clean = {key: value for key, value in os.environ.items()
         if key not in ('CLAUDE_PLUGIN_ROOT', 'CODEX_PLUGIN_ROOT')}
clean['HOME'] = '/fixture home'
for template in (root / '.claude/skills').glob('*/*.tmpl'):
    text = template.read_text()
    assert old not in text, template
    assignments = re.findall(r'^OCTO_(?:RESEARCH_)?ROOT=(.+)$', text, re.M)
    assert assignments, template
    for expression in assignments:
        for pins, expected in [({'CLAUDE_PLUGIN_ROOT': '/claude root', 'CODEX_PLUGIN_ROOT': '/codex root'}, '/claude root'),
                               ({'CODEX_PLUGIN_ROOT': '/codex root'}, '/codex root'),
                               ({}, '/fixture home/.claude-octopus/plugin')]:
            result = subprocess.run(['bash', '-c', 'selected=' + expression + '; printf "%s" "$selected"'],
                env=dict(clean, **pins), capture_output=True, text=True, check=True)
            assert result.stdout == expected, (template, expression, expected, result.stdout)
TEMPLATE_ROOTS
then test_pass; else test_fail "source template lost the selected host root"; fi

test_summary
