#!/usr/bin/env bash
# Tests for skill-doc-sync: post-ship documentation synchronization
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "skill-doc-sync: post-ship documentation synchronization"

SKILL_FILE="$(resolve_claude_skill_path "skill-doc-sync")"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── File existence ───────────────────────────────────────────────────────────

if [[ -f "$SKILL_FILE" ]]; then
  pass "skill-doc-sync.md exists"
else
  fail "skill-doc-sync.md exists" "file not found at $SKILL_FILE"
  echo "Cannot continue without skill file."
  exit 1
fi

CONTENT=$(<"$SKILL_FILE")

# ── Frontmatter structure ────────────────────────────────────────────────────

FRONTMATTER=$(awk '/^---$/{if(++count==2) exit} count==1' "$SKILL_FILE")

# name field
if echo "$FRONTMATTER" | grep -q "^name: skill-doc-sync"; then
  pass "frontmatter: has name field (skill-doc-sync)"
else
  fail "frontmatter: has name field" "missing or wrong name"
fi

# aliases field
if echo "$FRONTMATTER" | grep -q "^aliases:"; then
  pass "frontmatter: has aliases field"
else
  fail "frontmatter: has aliases field" "missing aliases"
fi

# Check specific aliases
for alias in "doc-sync" "sync-docs" "document-release"; do
  if echo "$FRONTMATTER" | grep -q "$alias"; then
    pass "frontmatter: alias '$alias' present"
  else
    fail "frontmatter: alias '$alias' present" "missing alias: $alias"
  fi
done

# description field
if echo "$FRONTMATTER" | grep -q "^description:"; then
  pass "frontmatter: has description field"
else
  fail "frontmatter: has description field" "missing description"
fi

# trigger patterns in description (Use when: ...)
for trigger in "sync docs" "update doc" "document changes" "release notes"; do
  if echo "$FRONTMATTER" | grep -qi "$trigger"; then
    pass "frontmatter: trigger pattern '$trigger' present"
  else
    fail "frontmatter: trigger pattern '$trigger' present" "missing trigger: $trigger"
  fi
done

# ── Description constraints ──────────────────────────────────────────────────

DESC_LINE=$(echo "$FRONTMATTER" | grep "^description:" | sed 's/^description: *//')
DESC_LEN=${#DESC_LINE}

if [[ "$DESC_LEN" -le 120 ]]; then
  pass "description length <= 120 chars ($DESC_LEN chars)"
else
  fail "description length <= 120 chars" "got $DESC_LEN chars"
fi

# Banned words check
BANNED_WORDS=("independent" "compound" "team of teams" "claude instances")
for word in "${BANNED_WORDS[@]}"; do
  if echo "$DESC_LINE" | grep -qi "$word"; then
    fail "description: no banned word '$word'" "found banned word in description"
  else
    pass "description: no banned word '$word'"
  fi
done

# ── All 9 steps present ─────────────────────────────────────────────────────

STEP_LABELS=(
  "Step 1.*Discover"
  "Step 2.*Cross-[Rr]eference"
  "Step 3.*Auto-[Uu]pdate"
  "Step 4.*Risky"
  "Step 5.*CHANGELOG"
  "Step 6.*Cross-[Dd]oc"
  "Step 7.*Discoverability"
  "Step 8.*TODO"
  "Step 9.*Commit"
)

for i in "${!STEP_LABELS[@]}"; do
  step_num=$((i + 1))
  pattern="${STEP_LABELS[$i]}"
  if grep -qE "$pattern" <<< "$CONTENT"; then
    pass "step $step_num present (${pattern})"
  else
    fail "step $step_num present" "missing pattern: $pattern"
  fi
done

# ── Key patterns ─────────────────────────────────────────────────────────────

# git diff reference
if grep -q "git diff" <<< "$CONTENT"; then
  pass "references git diff"
else
  fail "references git diff" "no git diff found in content"
fi

# sell test
if grep -qi "sell test" <<< "$CONTENT"; then
  pass "references sell test"
else
  fail "references sell test" "no sell test reference found"
fi

# cross-doc consistency
if grep -qi "cross-doc consistency" <<< "$CONTENT"; then
  pass "references cross-doc consistency"
else
  fail "references cross-doc consistency" "not found"
fi

# discoverability check
if grep -qi "discoverability" <<< "$CONTENT"; then
  pass "references discoverability"
else
  fail "references discoverability" "not found"
fi

# CHANGELOG append-only
if grep -qi "append only" <<< "$CONTENT"; then
  pass "CHANGELOG append-only rule documented"
else
  fail "CHANGELOG append-only rule documented" "not found"
fi

# Never clobber CHANGELOG
if grep -Eqi "never.*clobber|never.*delete.*existing.*entries" <<< "$CONTENT"; then
  pass "never clobber CHANGELOG rule documented"
else
  fail "never clobber CHANGELOG rule documented" "not found"
fi

# ── Caps documented ──────────────────────────────────────────────────────────

# 30 file cap
if grep -q "30" <<< "$CONTENT"; then
  pass "30-file cap documented"
else
  fail "30-file cap documented" "no mention of 30-file limit"
fi

# User confirmation for risky changes
if grep -qi "user.*confirm\|ask.*user\|require.*confirmation\|user.*approval" <<< "$CONTENT"; then
  pass "user confirmation for risky changes documented"
else
  fail "user confirmation for risky changes documented" "not found"
fi

# ── No attribution / no source repo references ──────────────────────────────

if grep -qi "gstack" <<< "$CONTENT"; then
  fail "no gstack reference" "found 'gstack' in content"
else
  pass "no gstack reference"
fi

if grep -qi "source repo" <<< "$CONTENT"; then
  fail "no source repo reference" "found 'source repo' in content"
else
  pass "no source repo reference"
fi

# Check no Attribution section
if grep -qi "^## Attribution" <<< "$CONTENT"; then
  fail "no Attribution section" "found Attribution heading"
else
  pass "no Attribution section"
fi

# ── Integration notes ────────────────────────────────────────────────────────

if grep -qi "flow-deliver" <<< "$CONTENT"; then
  pass "references flow-deliver integration"
else
  fail "references flow-deliver integration" "not found"
fi

# ── flow-deliver actually wires doc-sync ───────────────────────────────────

DELIVER_SKILL="$PROJECT_ROOT/skills/flow-deliver/SKILL.md"
if [[ -f "$DELIVER_SKILL" ]]; then
  if grep -qi 'doc.sync\|doc-sync\|sync docs' "$DELIVER_SKILL" 2>/dev/null; then
    pass "flow-deliver references doc-sync step"
  else
    fail "flow-deliver references doc-sync step" "no doc-sync reference in flow-deliver"
  fi
else
  fail "flow-deliver references doc-sync step" "flow-deliver SKILL.md not found"
fi

test_case "shipped doc-sync commit recipes preserve unrelated work"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PYTHON'
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv[1])
trees = ('.claude/skills', 'skills', 'codex-skills')


class DocSyncCommit(unittest.TestCase):
    def test_recipes(self):
        for tree in trees:
            text = (root / tree / 'skill-doc-sync/SKILL.md').read_text()
            step = text.split('## Step 9: Commit Doc Changes', 1)[1]
            recipe = re.search(r'```bash\n(.*?)\n```', step, re.S)[1]
            for scenario in ('updated', 'new', 'no edits', 'rejected'):
                with self.subTest(tree=tree, scenario=scenario):
                    self.check_recipe(recipe, scenario)

    def check_recipe(self, recipe, scenario):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as directory:
            repo = Path(directory)
            env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                       GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                       GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')

            def git(*args):
                return subprocess.check_output(['git', *args], cwd=repo, env=env, text=True).strip()

            git('init', '-q', '-b', 'main')
            filename = 'docs/guide [1].md'
            draft = repo / 'docs/guide 1.md'
            staged = repo / 'work.txt'
            target = repo / filename
            draft.parent.mkdir()
            for path in (draft, staged):
                path.write_text('baseline\n')
            if scenario != 'new':
                target.write_text('baseline\n')
            git('add', '.')
            git('commit', '-qm', 'base')
            before = git('rev-parse', 'HEAD')
            staged.write_text('user staged change\n')
            git('add', '--', staged.name)
            staged.write_text('user unstaged change\n')
            draft.write_text('unrelated doc changes\n')
            if scenario != 'no edits':
                target.write_text('doc-sync change\n')
                recipe = recipe.replace('set --\n', f'set -- {shlex.quote(filename)}\n', 1)
            if scenario == 'rejected':
                hook = repo / '.git/hooks/pre-commit'
                hook.write_text('#!/bin/sh\nexit 1\n')
                hook.chmod(0o755)

            result = subprocess.run(
                ['bash', '-uc', recipe + '\nprintf continued > reached-state'],
                cwd=repo, env=env, capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(git('show', ':work.txt'), 'user staged change')
            self.assertEqual(staged.read_text(), 'user unstaged change\n')
            self.assertEqual(draft.read_text(), 'unrelated doc changes\n')
            if scenario == 'rejected':
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(git('rev-parse', 'HEAD'), before)
                self.assertFalse((repo / 'reached-state').exists())
                self.assertEqual(target.read_text(), 'doc-sync change\n')
            elif scenario == 'no edits':
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(git('rev-parse', 'HEAD'), before)
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD'), filename)
                self.assertEqual(git('show', f'HEAD:{filename}'), 'doc-sync change')
                self.assertEqual(git('diff', '--cached', '--name-only'), 'work.txt')


unittest.main(argv=['doc-sync-commit'])
PYTHON
then
  test_pass
else
  test_fail "doc-sync included unrelated changes or mishandled its commit outcome"
fi

test_case "shipped doc-sync recipes update the PR body without replacing unrelated text"
if python3 - "$PROJECT_ROOT" "$TEST_TMP_DIR" <<'PYTHON'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv[1])
trees = ('.claude/skills', 'skills', 'codex-skills')
start = '<!-- octopus-doc-sync:start -->'
end = '<!-- octopus-doc-sync:end -->'


class DocSyncPullRequest(unittest.TestCase):
    def test_recipes(self):
        for tree in trees:
            text = (root / tree / 'skill-doc-sync/SKILL.md').read_text()
            step = text.split('## Step 9: Commit Doc Changes', 1)[1].split('## Integration', 1)[0]
            recipe = re.findall(r'```bash\n(.*?)\n```', step, re.S)[1]
            for scenario in ('append', 'replace', 'unchanged', 'invalid markers',
                             'closed', 'changed body', 'edit failed'):
                with self.subTest(tree=tree, scenario=scenario):
                    self.check_recipe(recipe, scenario)

    def check_recipe(self, recipe, scenario):
        with tempfile.TemporaryDirectory(dir=sys.argv[2]) as directory:
            fixture = Path(directory)
            fake_gh = fixture / 'gh'
            fake_gh.write_text("""#!/usr/bin/env python3
import os
from pathlib import Path
import sys

root = Path(os.environ['TEST_DOC_SYNC_FIXTURE'])
if sys.argv[1:3] == ['pr', 'view']:
    current = root / 'current.json'
    response = current if len(sys.argv) > 3 and sys.argv[3].startswith('https://') and current.exists() else root / 'pr.json'
    print(response.read_text())
elif sys.argv[1:4] == ['pr', 'edit', 'https://github.com/example/project/pull/2']:
    assert sys.argv[4] == '--body-file' and len(sys.argv) == 6
    if (root / 'reject-edit').exists():
        sys.exit(1)
    (root / 'edited').write_bytes(Path(sys.argv[5]).read_bytes())
else:
    sys.exit(3)
""")
            fake_gh.chmod(0o755)
            prefix = '## Context\n\nExisting PR text.  \n'
            suffix = '\n\n## Testing\n\nStill here.\n'
            summary = '- Updated docs/guide.md\n'
            section = f'{start}\n## Documentation sync\n\n{summary}{end}'
            body = prefix
            if scenario in ('replace', 'unchanged'):
                previous = section if scenario == 'unchanged' else f'{start}\nPrevious summary\n{end}'
                body = f'{prefix}\n{previous}{suffix}'
            if scenario == 'invalid markers':
                body = f'{prefix}\n{start}\n'
            if scenario == 'edit failed':
                (fixture / 'reject-edit').touch()
            (fixture / 'summary.md').write_text(summary)
            pr = {
                'number': 2, 'url': 'https://github.com/example/project/pull/2',
                'state': 'CLOSED' if scenario == 'closed' else 'OPEN', 'body': body,
            }
            (fixture / 'pr.json').write_text(json.dumps(pr))
            if scenario == 'changed body':
                (fixture / 'current.json').write_text(json.dumps(dict(pr, body=f'{body}New edit.')))
            env = dict(os.environ, PATH=f'{fixture}:{os.environ["PATH"]}',
                       TEST_DOC_SYNC_FIXTURE=directory,
                       DOC_SYNC_SUMMARY_FILE=str(fixture / 'summary.md'))
            result = subprocess.run(['bash', '-c', recipe], env=env, capture_output=True, text=True)
            edited = fixture / 'edited'
            if scenario in ('append', 'replace'):
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = f'{prefix}\n{section}{suffix if scenario == "replace" else chr(10)}'
                self.assertEqual(edited.read_text(), expected)
            else:
                self.assertFalse(edited.exists())
                self.assertNotIn('Updated PR', result.stdout)
                if scenario in ('invalid markers', 'changed body', 'edit failed'):
                    self.assertNotEqual(result.returncode, 0)


unittest.main(argv=['doc-sync-pull-request'])
PYTHON
then
  test_pass
else
  test_fail "doc-sync lost existing PR text or mishandled its update outcome"
fi

test_summary
