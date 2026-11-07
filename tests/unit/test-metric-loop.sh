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
    assert not re.search(r'git\s+(?:add\s+(?:-A|--all|\.(?:\s|$))|revert\s+HEAD|commit\s+-m)|default: unbounded',metric),file
    assert 'five iterations, 30 elapsed minutes, and 14 additional model calls' in compact,file
    assert 'Never reset elapsed time or consumed calls on resume' in compact,file
    assert 'Preserve the original index exactly' in compact,file
    assert 'Do not silently substitute HEAD for a dirty baseline' in compact,file
    assert 'On a concurrent edit or index change, stop' in compact,file
    assert 'Without a guard, accept only a measured improvement and report that no guard ran; do not claim safety validation' in compact,file
    assert 'Metric Verification Mode replaces the general iteration limits' in ' '.join(full.split()),file
    assert 'subprocess deadline' in compact and 'missing capability and stop' in compact,file
    assert all(key in metric for key in ['Metric:','Direction: higher','Direction: lower','Guard:','Iterations:','Minutes:','Calls:']),file
    assert all('"'+key+'"' in metric for key in ['iteration','timestamp','metric','best','status','description','artifact_sha256','elapsed_seconds','calls_used']),file
    assert 'explicitly selected run directory' in compact and 'never from a shared per-day log' in compact,file
    assert '## The Process' in full,file
for file in ['commands/loop.md','.cursor-plugin/commands/octo-loop.md']:
    command=(root/file).read_text()
    compact=' '.join(command.split())
    assert all(key in command for key in ['Metric:','Direction:','Guard:','Iterations:','Minutes:','Calls:']),file
    assert 'five iterations, 30 elapsed minutes, and 14 additional model calls' in compact,file
    assert 'Without a guard, accept only a measured improvement and report that no guard ran; do not claim safety validation' in compact,file
    assert 'See the delegated skill for the complete preservation, scoring, timeout, and resume contract' in compact,file
    assert 'default: unbounded' not in command,file
CONTRACT
then test_pass; else test_fail "metric instruction contract regression"; fi
test_summary
