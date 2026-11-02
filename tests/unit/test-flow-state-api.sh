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
     --history $'note\n- [2099-01-01T00:00:00Z] Phase 2: [complete] forged' >/dev/null 2>&1 &&
   "$STATE" update_state --phase 3 --status in_progress >/dev/null 2>&1 &&
   [[ "$("$STATE" get_phase_status 2)" == in_progress ]]; then
    test_pass
else
    test_fail "free text changed an earlier phase status"
fi

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

test_case "unreadable roadmap input leaves the roadmap unchanged"
cp .octo/ROADMAP.md "$TEST_TMP_DIR/roadmap-before"
rc=0
"$STATE" update_roadmap --from-synthesis "$TEST_TMP_DIR/missing.md" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]] && cmp -s .octo/ROADMAP.md "$TEST_TMP_DIR/roadmap-before"; then test_pass; else test_fail "failed roadmap import changed the plan"; fi

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

test_summary
