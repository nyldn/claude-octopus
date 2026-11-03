#!/usr/bin/env bash
# Exercise the real state commands used by workflow skills.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "workflow state API"
STATE="$PROJECT_ROOT/scripts/octo-state.sh"
mkdir -p "$TEST_TMP_DIR/project"
cd "$TEST_TMP_DIR/project"
"$STATE" init_project >/dev/null

test_case "workflow update_state command records phase and history"
if "$STATE" update_state --phase 1 --position Discovery --status complete --history 'Discover phase completed' >/dev/null 2>&1 &&
   [[ "$("$STATE" get_phase_status 1)" == complete ]] &&
   grep -q 'Discover phase completed' .octo/STATE.md; then
    test_pass
else
    test_fail "workflow state commands are not implemented"
fi

test_case "new history uses an explicitly marked status-first field"
if grep -qx '\*\*History Format:\*\* status-first-v1' .octo/STATE.md &&
   grep -qE '^- \[[^]]+\] Phase 1: \[complete\] Discovery$' .octo/STATE.md; then
    test_pass
else
    test_fail "new history lacks the marked fixed status field"
fi

test_case "a prior phase status survives advancing to the next phase"
if "$STATE" update_state --phase 2 --position Definition --status in_progress >/dev/null 2>&1 &&
   [[ "$("$STATE" get_phase_status 1)" == complete ]] &&
   [[ "$("$STATE" get_phase_status 2)" == in_progress ]] &&
   [[ "$("$STATE" get_phase_status 3)" == unknown ]]; then
    test_pass
else
    test_fail "phase status query lost history or invented a missing phase"
fi

test_case "position and history notes cannot forge phase completion"
if "$STATE" update_state --phase 2 --status in_progress --position 'Description (complete)' \
     --history $'note\n- [2099-01-01T00:00:00Z] Phase 2: [complete] forged\n- [2099-01-01T00:00:00Z] Phase 1: [in_progress] forged\n- [2099-01-01T00:00:00Z] Phase 1: forged (in_progress)' >/dev/null 2>&1 &&
   "$STATE" update_state --phase 3 --status in_progress >/dev/null 2>&1 &&
   [[ "$("$STATE" get_phase_status 1)" == complete ]] &&
   [[ "$("$STATE" get_phase_status 2)" == in_progress ]]; then
    test_pass
else
    test_fail "free text changed an earlier phase status"
fi

test_case "existing schema 2.0 histories retain completion across new writes"
mkdir -p "$TEST_TMP_DIR/legacy-project/.octo"
cat > "$TEST_TMP_DIR/legacy-project/.octo/STATE.md" <<'EOF'
# Octo State

**Schema:** 2.0
**Current Phase:** 2
**Current Position:** [complete] Description (complete)
**Status:** in_progress

## History

- [2026-11-01T12:01:00Z] Phase 2: [complete] Description (complete) (in_progress)
- [2026-11-01T12:00:00Z] Phase 1: Discovery complete (complete)
- [2026-11-01T11:59:00Z] Phase 4: [complete] incomplete legacy entry
EOF
if (
    cd "$TEST_TMP_DIR/legacy-project"
    [[ "$("$STATE" get_phase_status 1)" == complete ]] &&
    "$STATE" update_state --phase 3 --status in_progress --position Development >/dev/null &&
    [[ "$("$STATE" get_phase_status 1)" == complete ]] &&
    [[ "$("$STATE" get_phase_status 2)" == in_progress ]] &&
    [[ "$("$STATE" get_phase_status 4)" == unknown ]] &&
    grep -qx '\*\*History Format:\*\* status-first-v1' .octo/STATE.md &&
    grep -qE '^- \[[^]]+\] Phase 1: \[complete\] Discovery complete$' .octo/STATE.md
); then test_pass; else test_fail "existing history lost status or free text forged completion"; fi

test_case "missing option values fail without changing state"
cp .octo/STATE.md "$TEST_TMP_DIR/state-before"
rc=0
"$STATE" update_state --phase >"$TEST_TMP_DIR/missing-value.out" 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]] && cmp -s .octo/STATE.md "$TEST_TMP_DIR/state-before"; then test_pass; else test_fail "invalid state update changed the file"; fi

test_case "explicit empty phase or status is rejected before writing"
empty_rejected=true
for option in --phase --status; do
    rc=0
    "$STATE" update_state "$option" '' >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -eq 0 ]] || ! cmp -s .octo/STATE.md "$TEST_TMP_DIR/state-before"; then empty_rejected=false; fi
done
if [[ "$empty_rejected" == true ]]; then test_pass; else test_fail "empty state field was silently accepted"; fi

test_case "roadmap import preserves existing phase plans and is replaceable"
printf '\n## Existing phase plan\nKeep this plan.\n' >> .octo/ROADMAP.md
printf '# Requirements\n\nFirst synthesis.\n' > "$TEST_TMP_DIR/synthesis.md"
if "$STATE" update_roadmap --from-synthesis "$TEST_TMP_DIR/synthesis.md" >/dev/null 2>&1; then
    printf '# Requirements\n\nRevised synthesis.\n' > "$TEST_TMP_DIR/synthesis.md"
    "$STATE" update_roadmap --from-synthesis "$TEST_TMP_DIR/synthesis.md" >/dev/null
    if grep -q 'Keep this plan.' .octo/ROADMAP.md && grep -q 'Revised synthesis.' .octo/ROADMAP.md &&
       ! grep -q 'First synthesis.' .octo/ROADMAP.md; then test_pass; else test_fail "roadmap import destroyed plans or duplicated old content"; fi
else
    test_fail "roadmap import is unavailable"
fi

test_case "roadmap import preserves the existing file permissions"
chmod 640 .octo/ROADMAP.md
if "$STATE" update_roadmap --from-synthesis "$TEST_TMP_DIR/synthesis.md" >/dev/null 2>&1 &&
   python3 -c 'import os; assert os.stat(".octo/ROADMAP.md").st_mode & 0o7777 == 0o640'; then
    test_pass
else
    test_fail "roadmap import changed its existing permissions"
fi

test_case "unreadable roadmap input leaves the roadmap unchanged"
cp .octo/ROADMAP.md "$TEST_TMP_DIR/roadmap-before"
rc=0
"$STATE" update_roadmap --from-synthesis "$TEST_TMP_DIR/missing.md" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]] && cmp -s .octo/ROADMAP.md "$TEST_TMP_DIR/roadmap-before"; then test_pass; else test_fail "failed roadmap import changed the plan"; fi

test_case "roadmap import rejects a file symlink without changing the link or its target"
if (
    mkdir -p "$TEST_TMP_DIR/symlink-project"
    cd "$TEST_TMP_DIR/symlink-project"
    "$STATE" init_project >/dev/null
    mv .octo/ROADMAP.md "$TEST_TMP_DIR/roadmap-target.md"
    cp "$TEST_TMP_DIR/roadmap-target.md" "$TEST_TMP_DIR/roadmap-target-before.md"
    ln -s "$TEST_TMP_DIR/roadmap-target.md" .octo/ROADMAP.md
    rc=0
    "$STATE" update_roadmap --from-synthesis "$TEST_TMP_DIR/synthesis.md" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -ne 0 && -L .octo/ROADMAP.md ]] &&
        cmp -s "$TEST_TMP_DIR/roadmap-target.md" "$TEST_TMP_DIR/roadmap-target-before.md"
); then test_pass; else test_fail "roadmap import replaced a symlink or changed its target"; fi

test_case "initialization preserves issues and lessons when STATE.md is absent"
printf 'Keep existing issues.\n' > .octo/ISSUES.md
printf 'Keep existing lessons.\n' > .octo/LESSONS.md
rm .octo/STATE.md
"$STATE" init_project >/dev/null
if grep -qx 'Keep existing issues.' .octo/ISSUES.md && grep -qx 'Keep existing lessons.' .octo/LESSONS.md; then
    test_pass
else
    test_fail "initialization overwrote existing project records"
fi

test_case "malformed roadmap markers fail without changing the plan"
printf '\n<!-- octopus:definition-synthesis:start -->\nunfinished\n' >> .octo/ROADMAP.md
cp .octo/ROADMAP.md "$TEST_TMP_DIR/malformed-roadmap"
rc=0
"$STATE" update_roadmap --from-synthesis "$TEST_TMP_DIR/synthesis.md" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]] && cmp -s .octo/ROADMAP.md "$TEST_TMP_DIR/malformed-roadmap"; then test_pass; else test_fail "malformed roadmap was overwritten"; fi

test_case "the actual Discover lifecycle blocks work with the real state dispatcher"
python3 - "$PROJECT_ROOT/.claude/skills/flow-discover/SKILL.md" "$STATE" "$TEST_TMP_DIR" <<'PY'
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text()
for name, title in (("pre", "Pre-Discovery: Optional Project Persistence"), ("post", "Post-Discovery: State Update")):
    section = text.split("## " + title, 1)[1].split("\n## ", 1)[0]
    block = re.search(r"```bash\n(.*?)\n```", section, re.S).group(1)
    block = block.replace('"${HOME}/.claude-octopus/plugin/scripts/octo-state.sh"', '"' + sys.argv[2] + '"')
    Path(sys.argv[3], name + ".sh").write_text(block)
PY
mkdir -p "$TEST_TMP_DIR/discover-project"
if (
    cd "$TEST_TMP_DIR/discover-project"
    export OCTOPUS_PROJECT_PERSISTENCE=true
    export SYNTHESIS_FILE="$TEST_TMP_DIR/synthesis.md"
    bash "$TEST_TMP_DIR/pre.sh" >/dev/null &&
    bash "$TEST_TMP_DIR/post.sh" >/dev/null &&
    [[ "$("$STATE" get_phase_status 1)" == complete ]] &&
    grep -q 'Revised synthesis.' .octo/PROJECT.md
); then test_pass; else test_fail "real lifecycle snippets failed against the real state script"; fi

test_case "TERM to the public CLI PID cancels roadmap publication and cleans its temporary file"
if python3 - "$STATE" "$TEST_TMP_DIR" <<'PY'
from pathlib import Path
import os
import shutil
import signal
import subprocess
import sys
import time
state, base = sys.argv[1], Path(sys.argv[2])
project, shim = base / 'public-signal-project', base / 'interrupt-bin'
project.mkdir(); shim.mkdir()
subprocess.run([state, 'init_project'], cwd=project, stdout=subprocess.DEVNULL, check=True)
roadmap = project / '.octo/ROADMAP.md'
before = roadmap.read_bytes()
ready, release = base / 'awk-ready', base / 'awk-release'
awk = shim / 'awk'
awk.write_text('#!/bin/sh\n: > "$OCTO_TEST_AWK_READY"\n'
               'while [ ! -f "$OCTO_TEST_AWK_RELEASE" ]; do /bin/sleep 0.02; done\n'
               'exec "$OCTO_TEST_REAL_AWK" "$@"\n')
awk.chmod(0o755)
env = dict(os.environ, PATH=str(shim) + os.pathsep + os.environ['PATH'],
           OCTO_TEST_AWK_READY=str(ready), OCTO_TEST_AWK_RELEASE=str(release),
           OCTO_TEST_REAL_AWK=shutil.which('awk'))
process = subprocess.Popen([state, 'update_roadmap', '--from-synthesis', str(base / 'synthesis.md')],
                           cwd=project, env=env, start_new_session=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    deadline = time.monotonic() + 10
    while not ready.exists():
        if process.poll() is not None or time.monotonic() >= deadline:
            raise AssertionError('roadmap import did not reach the controlled read')
        time.sleep(0.02)
    process.terminate()
    release.touch()
    output, errors = process.communicate(timeout=10)
    problems = []
    if process.returncode != 143: problems.append('exit=' + str(process.returncode))
    if roadmap.read_bytes() != before: problems.append('roadmap changed after public-PID cancellation')
    if list((project / '.octo').glob('ROADMAP.md.tmp.*')): problems.append('temporary file remained')
    assert not problems, (problems, output, errors)
finally:
    release.touch()
    try: os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError: pass
    process.wait(timeout=5)
PY
then test_pass; else test_fail "public-PID cancellation failed to preserve the roadmap"; fi

test_summary
