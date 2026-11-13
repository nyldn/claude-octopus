#!/usr/bin/env bash
# Claude must discover native skills while Codex keeps its adapted tree.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
test_suite "Native skill registration"
export TMPDIR="$TEST_TMP_DIR"
test_case "Claude registrations preserve native bodies, names, alias and starter pack"
if python3 - "$PROJECT_ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path
root = Path(sys.argv[1])
manifest = json.loads((root / '.claude-plugin/plugin.json').read_text())
registered = {path: (root / path / 'SKILL.md').read_text() for path in manifest['skills']}
for path, text in registered.items():
    assert 'Host: Codex CLI' not in text, f'Claude loads Codex instructions: {path}'
native = list((root / '.claude/skills').glob('*/SKILL.md'))
for source in native:
    name = re.search(r'^name: (.+)$', source.read_text(), re.M)[1]
    native_text = (root / 'skills' / name / 'SKILL.md').read_text()
    assert native_text.startswith(source.read_text()), f'native body changed: {source}'
    supplement = native_text[len(source.read_text()):]
    if supplement:
        assert re.search(r'^execution_mode: enforced$', source.read_text(), re.M), name
        assert 'Execution Contract (MANDATORY - CANNOT SKIP)' in supplement
        assert 'generated Claude Code skill' in supplement
        assert 'Do not claim provider output' in supplement
    if name in {'octopus-security-audit', 'skill-staged-review'}:
        assert supplement, f'missing native execution contract: {name}'
    assert not re.search(r'^agent: (Explore|Plan)$', source.read_text().split('---', 2)[1], re.M), f'read-only agent cannot execute native workflow: {source}'
assert set(registered) == {'./' + str(f.parent.relative_to(root)) for f in (root / 'skills').rglob('SKILL.md')}, 'automatic and explicit discovery differ'
assert len(registered) == 64, 'existing skill registration count changed'
assert any(re.search(r'^name: skill-verify$', text, re.M) for text in registered.values()), 'verification alias lost'
assert sum('/octopus-starter-pack/' in path for path in registered) == 4, 'starter pack lost'
assert json.loads((root / '.codex-plugin/plugin.json').read_text())['skills'] == './codex-skills/'
assert 'Host: Codex CLI' in (root / 'codex-skills/flow-develop/SKILL.md').read_text()
assert 'Bash tool' in (root / '.claude/skills/flow-develop/SKILL.md').read_text()
print(f'{len(native)} native sources and {len(registered)} registrations checked')
PY
then test_pass; else test_fail "host-specific skill registration contract failed"; fi

test_summary
