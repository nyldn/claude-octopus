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

test_case "guide and doctor choose the same root when both hosts are set"
if python3 - "$PROJECT_ROOT" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys
root = Path(sys.argv[1])
resolved = []
for relative in ("commands/guide.md", "skills/skill-doctor/SKILL.md"):
    match = re.search(r'^OCTO_(?:PLUGIN_)?ROOT=(.+)$', (root / relative).read_text(), re.MULTILINE)
    assert match, relative
    result = subprocess.run(["bash", "-c", 'selected=' + match.group(1) + '; printf "%s" "$selected"'], env={**os.environ, "CLAUDE_PLUGIN_ROOT": "/claude", "CODEX_PLUGIN_ROOT": "/codex"}, capture_output=True, text=True, check=True)
    resolved.append(result.stdout)
assert resolved == ["/claude", "/claude"], resolved
PY
then test_pass; else test_fail "host root precedence differs"; fi

test_case "unknown CLI commands return a usage error"
rc=0
output="$(HOME="$TEST_TMP_DIR" "$PROJECT_ROOT/bin/octopus" not-a-command 2>&1)" || rc=$?
if [[ "$rc" == 2 && "$output" == *"Unknown octopus command"* ]]; then test_pass; else test_fail "unknown command did not return exit 2"; fi
test_summary
