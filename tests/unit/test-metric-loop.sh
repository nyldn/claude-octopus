#!/usr/bin/env bash
# Validate the host-managed metric-loop instruction contract and its adapter.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "Bounded metric candidate workflow contract"
test_case "source and generated metric contracts preserve work and finite budgets"
if python3 - "$ROOT" <<'CONTRACT'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
for file in ['.claude/skills/skill-iterative-loop/SKILL.md','skills/skill-iterative-loop/SKILL.md']:
    full=(root/file).read_text()
    metric=full.split('## Metric Verification Mode',1)[1].split('## The Bottom Line',1)[0]
    compact=' '.join(metric.split())
    assert not re.search(r'git (?:add -A|revert HEAD|commit -m)|default: unbounded',metric),file
    assert 'five iterations, 30 elapsed minutes, and 14 additional model calls' in compact,file
    assert 'Never reset elapsed time or consumed calls on resume' in compact,file
    assert 'Preserve the original index exactly' in compact,file
    assert 'Do not silently substitute HEAD for a dirty baseline' in compact,file
    assert 'concurrent edit or index change' in compact and 'stop' in compact,file
    assert 'subprocess deadline' in compact and 'missing capability and stop' in compact,file
    assert all(key in metric for key in ['Metric:','Direction: higher','Direction: lower','Guard:','Iterations:','Minutes:','Calls:']),file
    assert all('"'+key+'"' in metric for key in ['iteration','timestamp','metric','best','status','description','artifact_sha256','elapsed_seconds','calls_used']),file
    assert 'explicitly selected run directory' in compact and 'never from a shared per-day log' in compact,file
    assert '## The Process' in full,file
command=(root/'commands/loop.md').read_text()
assert all(key in command for key in ['Metric:','Direction:','Guard:','Iterations:','Minutes:','Calls:'])
assert 'default: unbounded' not in command
CONTRACT
then test_pass; else test_fail "metric instruction contract regression"; fi
test_summary
