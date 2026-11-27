#!/usr/bin/env bash
# Static coverage for research fanout and synthesis safeguards.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Research fanout safeguards"

test_case "research command supports breadth routing"
research_cmd="$(<"$PROJECT_ROOT/commands/research.md")"
if [[ "$research_cmd" == *"--breadth=light|standard|exhaustive"* && "$research_cmd" == *"[breadth=exhaustive]"* ]]; then
    test_pass
else
    test_fail "expected breadth parsing in research command"
fi

test_case "research command routes to dedicated research skill"
if [[ "$research_cmd" == *'.claude/skills/skill-deep-research/SKILL.md'* \
   && "$research_cmd" != *'Read `${HOME}/.claude-octopus/plugin/.claude/skills/flow-discover/'* ]]; then
    test_pass
else
    test_fail "expected /octo:research to load its dedicated source, not discover"
fi

test_case "research skill forwards the routed intensity as an orchestrate.sh flag"
research_skill="$(<"$(resolve_claude_skill_path "skill-deep-research")")"
if [[ "$research_skill" == *'[intensity=quick|standard|deep]` token from the skill args'* \
   && "$research_skill" == *'`light → quick`, `exhaustive → deep`; `quick`, `standard` and `deep` pass through unchanged'* \
   && "$research_skill" != *'--depth "${depth_choice}"'* \
   && "$research_skill" != *'--focus "${focus_choice}"'* \
   && "$research_skill" != *'--format "${format_choice}"'* ]] &&
   python3 - "$(resolve_claude_skill_path "skill-deep-research")" <<'PY'
from pathlib import Path
import shlex
import sys

for line in Path(sys.argv[1]).read_text().splitlines():
    if ' --intensity=' not in line:
        continue
    words = shlex.split(line.rstrip(' \\'))
    if words and words[0].startswith('OCTOPUS_WORKFLOW_INVOCATION_ID='):
        words = words[1:]
    if (words and words[0].endswith('/scripts/orchestrate.sh')
            and words[1:3] == ['--intensity=${research_intensity:?}', 'probe']):
        break
else:
    raise AssertionError('intensity must precede probe in the shell arguments')
PY
then
    test_pass
else
    test_fail "expected the research skill to pass --intensity= before probe and no unparsed flags"
fi

test_case "research availability displays one Antigravity row on every host"
if python3 - "$(resolve_claude_skill_path "skill-deep-research")" \
    "$PROJECT_ROOT/skills/octopus-research/SKILL.md" \
    "$PROJECT_ROOT/codex-skills/octopus-research/SKILL.md" <<'PY'
from pathlib import Path
import sys

failures = []
for name in sys.argv[1:]:
    banner = Path(name).read_text(encoding='utf-8').split('Provider Availability:\n', 1)[1]
    rows = [line for line in banner.split('\n\n', 1)[0].splitlines()
            if 'Antigravity CLI:' in line]
    if rows != ['🧭 Antigravity CLI: ${agy_status}']:
        failures.append(f'{name}: {rows!r}')
if failures:
    raise SystemExit('\n'.join(failures))
PY
then
    test_pass
else
    test_fail "expected a single Antigravity status row with the provider's compass marker"
fi

test_case "research tasks report the effective intensity on Claude and Codex"
if node - "$(resolve_claude_skill_path "skill-deep-research")" \
    "$PROJECT_ROOT/skills/octopus-research/SKILL.md" \
    "$PROJECT_ROOT/codex-skills/octopus-research/SKILL.md" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

for (const skill of process.argv.slice(2)) {
    const markdown = fs.readFileSync(skill, 'utf8');
    const taskSection = markdown.split('## Task Management Integration')[1];
    const recipe = taskSection.match(/```javascript\n([\s\S]*?)\n```/)[1];
    for (const intensity of ['quick', 'standard', 'deep']) {
        const tasks = [];
        vm.runInNewContext(recipe, {
            research_intensity: intensity,
            TaskCreate: task => tasks.push(task),
            TaskUpdate: () => {},
        });
        assert.equal(tasks.length, 1, skill);
        assert.equal(tasks[0].description, `Run orchestrate.sh probe at ${intensity} intensity`, skill);
        if (intensity !== 'deep') {
            const task = tasks[0];
            assert.doesNotMatch(`${task.subject} ${task.description} ${task.activeForm}`, /\bdeep\b/, skill);
        }
    }
}
JS
then
    test_pass
else
    test_fail "expected task progress to reflect quick, standard and deep dispatch"
fi

test_case "discover skill requires dynamic multi-provider fleet"
discover_skill="$(read_claude_skill_contract flow-discover)"
if [[ "$discover_skill" == *"build-fleet.sh"* && "$discover_skill" == *"codex, agy, copilot, qwen, opencode"* ]]; then
    test_pass
else
    test_fail "expected dynamic provider fleet instructions"
fi

test_case "discover skill surfaces agent summary before synthesis"
if [[ "$discover_skill" == *"orchestrate.sh\" agent-summary"* && "$discover_skill" == *"Failed provider output"* ]]; then
    test_pass
else
    test_fail "expected agent-summary gate before synthesis"
fi

test_case "probe progress display receives actual provider roster"
workflows_lib="$(<"$PROJECT_ROOT/scripts/lib/workflows.sh")"
session_lib="$(<"$PROJECT_ROOT/scripts/lib/session.sh")"
if [[ "$workflows_lib" == *"OCTO_PROGRESS_AGENT_TYPES"* && \
      "$session_lib" == *"OCTO_PROGRESS_AGENT_TYPES"* && \
      "$session_lib" == *"perplexity*)"* ]]; then
    test_pass
else
    test_fail "expected rich progress to use dynamic probe provider metadata"
fi

test_summary
