#!/usr/bin/env bash
# Execute the authored and generated state recipes without provider calls.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Debate state JSON"
test_case "debate state preserves user text and rejects invalid round counts"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY'
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
checks = 0

def render_inputs(recipe, environment):
    # The host fills the standalone block's explicit handoff assignments.
    for name in ('QUESTION', 'ROUNDS', 'STYLE', 'DEBATE_MODE', 'ADVISORS', 'USER_GOAL', 'USER_PRIORITY', 'USER_CONSTRAINTS'):
        recipe = re.sub(rf'(?m)^{name}=.*$',
                        lambda match: name + '=' + shlex.quote(environment[name]), recipe)
    return recipe

for tree in ('.claude/skills', 'skills', 'codex-skills'):
    text = (root / tree / 'skill-debate/SKILL.md').read_text()
    section = text.split('### Step 4: Setup Debate Folder', 1)[1]
    recipe = re.search(r'```bash\n(.*?)\n```', section, re.S)[1]
    # Run each recipe in a fresh shell with its ordinary setup, not a copy of
    # the serializer. Literal shell expressions must remain user data.
    for advisors, mode in (('codex, agy', 'blinded'), ('', 'cross-critique')):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as directory:
            home = Path(directory)
            shadow = home / 'python-path'
            shadow.mkdir()
            for target in (home / 'datetime.py', home / 'pathlib.py', home / 'json.py',
                           shadow / 'sitecustomize.py', shadow / 'usercustomize.py'):
                target.write_text("open('SHADOW_MODULE_EXECUTED', 'w').write('unexpected import')\n"
                                  "raise RuntimeError('untrusted Python module imported')\n")
            context = dict(goal='Keep "quotes" and \\paths\nnext line',
                           priority='Unicode café and 🐙',
                           constraints='Keep ${HOME} and $(touch SHOULD_NOT_RUN) literal')
            question = 'Should we use "Redis"?\nCompare \\paths and tabs\there.'
            env = dict(os.environ, HOME=directory, CLAUDE_CODE_SESSION='fixture',
                       PYTHONPATH=str(shadow),
                       QUESTION=question, ROUNDS='3', STYLE='thorough', DEBATE_MODE=mode, ADVISORS=advisors,
                       USER_GOAL=context['goal'], USER_PRIORITY=context['priority'],
                       USER_CONSTRAINTS=context['constraints'])
            result = subprocess.run(['/bin/bash', '-eu', '-c', render_inputs(recipe, env)], cwd=home,
                                    env=env, capture_output=True, text=True, timeout=5)
            assert not (home / 'SHADOW_MODULE_EXECUTED').exists(), (tree, result.stderr)
            assert result.returncode == 0, (tree, result.stderr)
            state_file = next(home.rglob('state.json'))
            state = json.loads(state_file.read_text(encoding='utf-8'))
            assert state['question'] == question and state['mode'] == mode, (tree, state)
            assert state['user_context'] == context, (tree, state)
            assert state['advisors'] == (['codex', 'agy'] if advisors else []), state
            assert state['rounds_total'] == 3 and type(state['rounds_total']) is int, state
            assert state['rounds_completed'] == 0 and state['status'] == 'active', state
            assert state['debate_id'] == state_file.parent.name, state
            assert re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', state['created_at']), state
            assert not (home / 'SHOULD_NOT_RUN').exists()
            checks += 1
    # Two invocations from the same session must not reuse state or evidence.
    for session in ('same-session', ''):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as directory:
            env = dict(os.environ, HOME=directory, CLAUDE_CODE_SESSION=session,
                       QUESTION='first question', ROUNDS='3', STYLE='thorough',
                       DEBATE_MODE='blinded', ADVISORS='codex', USER_GOAL='',
                       USER_PRIORITY='', USER_CONSTRAINTS='')

            def setup():
                result = subprocess.run(['/bin/bash', '-c', render_inputs(recipe, env)],
                                        cwd=directory, env=env, capture_output=True,
                                        text=True, timeout=5, check=True)
                label, separator, value = result.stdout.strip().partition('=')
                assert (label, separator) == ('DEBATE_DIR', '='), (tree, result.stdout)
                return Path(value)

            first = setup()
            first_state = (first / 'state.json').read_bytes()
            first_context = (first / 'context.md').read_bytes()
            first_note = first / 'rounds' / 'r001_claude.md'
            first_note.write_text('first moderator evidence', encoding='utf-8')

            env['QUESTION'] = 'second question'
            second = setup()
            assert first != second, (tree, session, first)
            assert first.parent == second.parent, (tree, first, second)
            assert (first / 'state.json').read_bytes() == first_state, tree
            assert (first / 'context.md').read_bytes() == first_context, tree
            assert first_note.read_text() == 'first moderator evidence', tree
            assert list((second / 'rounds').iterdir()) == [], tree
            second_state = json.loads((second / 'state.json').read_text())
            assert second_state['debate_id'] == second.name, tree
            assert second_state['question'] == 'second question', tree
            checks += 1
    invalid_settings = [(rounds, 'blinded') for rounds in ('0', '-1', 'invalid', '1.5', '11')]
    invalid_settings.append(('1', 'unknown'))
    for rounds, mode in invalid_settings:
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as directory:
            env = dict(os.environ, HOME=directory, CLAUDE_CODE_SESSION='fixture',
                       QUESTION='fixture', ROUNDS=rounds, STYLE='thorough', DEBATE_MODE=mode, ADVISORS='codex',
                       USER_GOAL='', USER_PRIORITY='', USER_CONSTRAINTS='')
            result = subprocess.run(['/bin/bash', '-c', render_inputs(recipe, env) + '\necho DEBATE_CONTINUED'],
                                    cwd=directory, env=env, capture_output=True, text=True, timeout=5)
            assert result.returncode != 0, (tree, rounds, result.stdout)
            assert 'DEBATE_CONTINUED' not in result.stdout, (tree, rounds)
            assert not list(Path(directory).rglob('state.json')), (tree, rounds)
            checks += 1
print(f'{checks} executable debate state scenarios passed')
PY
then test_pass; else test_fail "debate state recipe did not preserve valid JSON"; fi
test_case "debate quality scoring handles absent and present signals on every host"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_QUALITY'
from pathlib import Path
import re
import subprocess
import sys

root, tmp = map(Path, sys.argv[1:])
response = tmp / "quality-response.md"
plain = "reason " * 50
scenarios = {
    "empty": ("", 0),
    "no markers": (plain, 25),
    "citation only": (plain + "[ref]", 50),
    "code only": (plain + "```", 50),
    "advisor only": (plain + "Codex", 50),
    "all markers": (plain + "[ref] ``` Claude", 100),
}
errors = []
for tree in ("skills", ".claude/skills", "codex-skills"):
    text = (root / tree / "skill-debate/SKILL.md").read_text()
    scorer = re.search(r"(?ms)^evaluate_response_quality\(\) \{\n.*?^\}", text)[0]
    command = scorer + '\nevaluate_response_quality "$1"'
    for name, (body, expected) in scenarios.items():
        response.write_text(body, encoding="utf-8")
        result = subprocess.run(["/bin/bash", "-euo", "pipefail", "-c", command,
                                 "_", str(response)], capture_output=True, text=True, timeout=5)
        if (result.returncode, result.stdout, result.stderr) != (0, f"{expected}\n", ""):
            errors.append(f"{tree}, {name}: rc={result.returncode}, "
                          f"score={result.stdout.strip()!r}, stderr={result.stderr.strip()!r}")
    result = subprocess.run(["/bin/bash", "-euo", "pipefail", "-c", command,
                             "_", str(tmp / "missing-response.md")],
                            capture_output=True, text=True, timeout=5)
    if result.returncode == 0 or result.stdout:
        errors.append(f"{tree}: treated a missing response as a scored response")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("21 executable debate quality scenarios passed")
PY_QUALITY
then test_pass; else test_fail "debate quality scoring failed"; fi
test_case "blinded Debate keeps advisor answers unread until all moderator notes are saved"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_BLIND'
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

root, tmp = map(Path, sys.argv[1:])
scenarios = (
    ("blinded", (), False),
    ("blinded", ("moderator round one",), False),
    ("blinded", ("moderator round one", ""), False),
    ("blinded", ("moderator round one", "moderator round two"), True),
    ("cross-critique", (), True),
    (None, (), False),
)
errors = []
for tree in (".claude/skills", "skills", "codex-skills"):
    text = (root / tree / "skill-debate/SKILL.md").read_text()
    section = text.split("#### 5.3:", 1)[1]
    reader = re.search(r"```bash\n(.*?)\n```", section, re.S)[1]
    for mode, notes, allowed in scenarios:
        with tempfile.TemporaryDirectory(dir=tmp) as directory:
            debate = Path(directory)
            rounds = debate / "rounds"
            rounds.mkdir()
            (rounds / "r001_codex.md").write_text("ADVISOR ANSWER\n", encoding="utf-8")
            for number, analysis in enumerate(notes, 1):
                (rounds / f"r{number:03d}_claude.md").write_text(analysis, encoding="utf-8")
            state = {"rounds_total": 2}
            if mode is not None:
                state["mode"] = mode
            (debate / "state.json").write_text(json.dumps(state), encoding="utf-8")
            recipe = re.sub(r"^DEBATE_DIR=.*$", lambda _: "DEBATE_DIR=" + shlex.quote(directory),
                            reader, flags=re.M)
            result = subprocess.run(["/bin/bash", "-euo", "pipefail", "-c", recipe],
                                    capture_output=True, text=True, timeout=5)
            if ((result.returncode == 0) != allowed or
                    ("ADVISOR ANSWER" in result.stdout) != allowed or
                    "moderator round" in result.stdout):
                errors.append(f"{tree}, {mode}, {len(notes)} notes: "
                              f"rc={result.returncode}, stdout={result.stdout!r}")
            for number, analysis in enumerate(notes, 1):
                if (rounds / f"r{number:03d}_claude.md").read_text(encoding="utf-8") != analysis:
                    errors.append(f"{tree}, {mode}: rewrote the moderator note for round {number}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("18 executable Debate response-order scenarios passed")
PY_BLIND
then test_pass; else test_fail "Debate response reading did not preserve independent analysis"; fi
test_case "Debate reports actionable quality findings for the selected round"
if python3 -I - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PY_ROUND_QUALITY'
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

root, tmp = map(Path, sys.argv[1:])
errors = []
for tree in (".claude/skills", "skills", "codex-skills"):
    text = (root / tree / "skill-debate/SKILL.md").read_text()
    section = text.split("#### 5.4:", 1)[1]
    scorer = re.search(r"```bash\n(.*?)\n```", section, re.S)[1]
    with tempfile.TemporaryDirectory(dir=tmp) as directory:
        rounds = Path(directory) / "rounds"
        rounds.mkdir()
        plain = "reason " * 50
        for prefix, seat in (("r001", "codex"), ("r002", "agy"), ("r003", "sonnet")):
            (rounds / f"{prefix}_{seat}.md").write_text("short answer", encoding="utf-8")
            (rounds / f"{prefix}_adequate.md").write_text(plain + "[ref]", encoding="utf-8")
            (rounds / f"{prefix}_strong.md").write_text(plain + "[ref] ```", encoding="utf-8")
            (rounds / f"{prefix}_claude.md").write_text("moderator analysis", encoding="utf-8")
        scorer = re.sub(r"^DEBATE_DIR=.*$", lambda _: "DEBATE_DIR=" + shlex.quote(directory),
                        scorer, flags=re.M)
        def score_round(prefix, expected):
            recipe = re.sub(r"^ROUND_PREFIX=.*$", "ROUND_PREFIX=" + prefix, scorer, flags=re.M)
            result = subprocess.run(["/bin/bash", "-euo", "pipefail", "-c", recipe],
                                    capture_output=True, text=True, timeout=5)
            lines = result.stdout.splitlines()
            if result.returncode or result.stderr or len(lines) != len(expected) or set(lines) != expected:
                errors.append(f"{tree}, {prefix}: rc={result.returncode}, "
                              f"stdout={result.stdout!r}, stderr={result.stderr!r}")

        for prefix, seat in (("r001", "codex"), ("r002", "agy"), ("r003", "sonnet")):
            caution = f"{prefix} adequate: score 50/100. Flag limitations in synthesis."
            score_round(prefix, {caution, f"{prefix} {seat}: score 0/100. Needs elaboration."})
            retry = Path(directory) / "retries" / f"{prefix}_{seat}"
            retry.mkdir(parents=True)
            score_round(prefix, {caution, f"{prefix} {seat}: no completed elaboration. Quality gate failed."})
            reply = retry / "response.md"
            reply.write_text("", encoding="utf-8")
            score_round(prefix, {caution, f"{prefix} {seat}: no completed elaboration. Quality gate failed."})
            reply.write_text("another short answer", encoding="utf-8")
            score_round(prefix, {caution, f"{prefix} {seat}: retry scored 0/100. Quality gate failed."})
            reply.write_text(plain + "[ref]", encoding="utf-8")
            score_round(prefix, {caution, f"{prefix} {seat}: retry scored 50/100. Use the elaboration."})
            assert (rounds / f"{prefix}_{seat}.md").read_text(encoding="utf-8") == "short answer"
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("45 executable Debate round-scoring and retry scenarios passed")
PY_ROUND_QUALITY
then test_pass; else test_fail "Debate reported an incorrect quality or retry outcome"; fi
test_case "blinded Debate prepares every moderator note before native advisor completions"
if python3 -I - "$PROJECT_ROOT" <<'PY_NATIVE'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for tree in (".claude/skills", "skills", "codex-skills"):
    text = (root / tree / "skill-debate/SKILL.md").read_text()
    preparation, launch = text.split("#### 5.1:", 1)[1].split("#### 5.2:", 1)
    preparation = preparation.partition("```bash")[0]
    assert "for every round before launching any advisors" in preparation, tree
    native_prompt = launch.split("prompt:", 1)[1].split("After all allowed advisors finish", 1)[0]
    assert "write your analysis" in native_prompt.lower(), tree
    assert "final reply must contain only a completion status" in native_prompt, tree
    assert "Do not include any analysis, verdict, or summary in the final reply" in native_prompt, tree
PY_NATIVE
then test_pass; else test_fail "a native completion can expose analysis before the moderator finishes"; fi
test_summary
