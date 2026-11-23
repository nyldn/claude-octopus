#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "local issue initialization"

for entry in .claude/skills/skill-issues skills/skill-issues codex-skills/skill-issues; do
    test_case "$entry creates a complete ledger and preserves an existing one"
    if python3 - "$PROJECT_ROOT" "$entry" "$TEST_TMP_DIR" <<'PY'
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

root, entry, temp_root = sys.argv[1:]
skill = (Path(root) / entry / "SKILL.md").read_text(encoding="utf-8")
initializer = skill.split("### Initialize ISSUES.md\n", 1)[1].split("```bash\n", 1)[1].split("\n```", 1)[0]
template_path = Path("config/templates/ISSUES.md.template")
template = (Path(root) / template_path).read_text(encoding="utf-8")

with tempfile.TemporaryDirectory(dir=temp_root) as directory:
    work = Path(directory)
    plugins = [work / "plugin", work / "installed plugin"]
    for plugin in plugins:
        packed_template = plugin / template_path
        packed_template.parent.mkdir(parents=True)
        shutil.copyfile(Path(root) / template_path, packed_template)
    for project_name, plugin in [
        ("ordinary-project", plugins[0]),
        ("Design & QA\\tools", plugins[1]),
        ("Design\nQA", plugins[1]),
    ]:
        project = work / project_name
        project.mkdir()
        env = {"HOME": str(work), "PATH": os.environ["PATH"]}
        root_var = "CODEX_PLUGIN_ROOT" if entry.startswith("codex-skills") else "CLAUDE_PLUGIN_ROOT"
        env[root_var] = str(plugin)
        ledger = project / ".octo/ISSUES.md"
        result = subprocess.run(["bash", "-ec", initializer], cwd=project, env=env, capture_output=True, text=True)
        expected = template.replace("{{PROJECT_NAME}}", project_name.replace("\n", " "))
        if result.returncode or not ledger.exists() or ledger.read_text(encoding="utf-8") != expected:
            print(f"{project_name!r}: did not render the complete ledger: {result.stderr}", file=sys.stderr)
            sys.exit(1)
        ledger.write_text("Existing issues\n", encoding="utf-8")
        subprocess.run(["bash", "-ec", initializer], cwd=project, env=env, check=True)
        if ledger.read_text(encoding="utf-8") != "Existing issues\n":
            sys.exit("repeat initialization overwrote existing issues")

    missing = work / "missing-template"
    missing.mkdir()
    packed_template.unlink()
    result = subprocess.run(["bash", "-ec", initializer], cwd=missing, env=env, capture_output=True, text=True)
    if result.returncode == 0 or (missing / ".octo/ISSUES.md").exists():
        sys.exit("missing template did not fail cleanly")
PY
    then
        test_pass
    else
        test_fail "the issue initializer did not preserve the ledger contract"
    fi
done

test_summary
