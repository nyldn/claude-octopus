#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "local issue resolution"

for entry in .claude/skills/skill-issues skills/skill-issues codex-skills/skill-issues; do
    test_case "$entry resolves only an exact ID in the Open Issues table"
    if python3 - "$PROJECT_ROOT/$entry/SKILL.md" "$PROJECT_ROOT/config/templates/ISSUES.md.template" <<'PY'
from pathlib import Path
import subprocess
import sys
import tempfile

skill, template = (Path(path).read_text() for path in sys.argv[1:])
resolve_steps = skill.split("### 3. Resolve Issue\n", 1)[1]
check_issue = resolve_steps.split("```bash\n", 1)[1].split("\n```", 1)[0]
issue_id = "ISS-20260203-001"
cases = [
    ("open", f"| {issue_id} | high | integration | Login fails | 2026-02-03 | Develop |", "", True),
    ("resolved only", "", f"| {issue_id} | high | integration | Login fails | 2026-02-03 | 2026-02-04 | Fixed |", False),
    ("similarly named open ID", f"| {issue_id}0 | high | integration | Login fails | 2026-02-03 | Develop |", "", False),
    ("ID in another issue's description", f"| ISS-20260203-002 | high | integration | Follow up {issue_id} | 2026-02-03 | Develop |", "", False),
    ("ID in notes", "", f"\n## Notes\n\n| {issue_id} | Historical reference |", False),
]

failed = False
with tempfile.TemporaryDirectory() as workdir:
    state = Path(workdir) / ".octo"
    state.mkdir()
    for name, open_rows, resolved_rows, should_succeed in cases:
        ledger = template.replace("| <!-- Issues will be appended here --> |", open_rows)
        ledger = ledger.replace("| <!-- Resolved issues moved here --> |", resolved_rows)
        (state / "ISSUES.md").write_text(ledger)
        result = subprocess.run(
            ["bash", "-c", check_issue], cwd=workdir,
            env={"ISSUE_ID": issue_id}, capture_output=True, text=True,
        )
        if (result.returncode == 0) != should_succeed:
            print(f"{name}: unexpected status {result.returncode}", file=sys.stderr)
            failed = True
sys.exit(failed)
PY
    then
        test_pass
    else
        test_fail "the Resolve issue recipe accepted an invalid match or rejected an open issue"
    fi
done

test_summary
