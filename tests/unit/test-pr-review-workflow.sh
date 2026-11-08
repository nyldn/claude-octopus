#!/usr/bin/env bash
# Regression coverage for the first-party PR review workflow (#888).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "PR review workflow uses the actual diff and fails closed"

WORKFLOW="$PROJECT_ROOT/.github/workflows/claude-octopus.yml"
ACTIONLINT_CONFIG="$PROJECT_ROOT/.github/actionlint.yaml"

test_case "automatic advisory model review requires explicit repository opt-in"
if grep -Fq "vars.OCTOPUS_AUTOMATED_PR_REVIEW == 'true'" "$WORKFLOW" &&
   grep -Fq "github.event_name == 'workflow_dispatch'" "$WORKFLOW" &&
   grep -Fq '  comment-command:' "$WORKFLOW"; then
    test_pass
else
    test_fail "advisory review runs on every push or explicit review paths disappeared"
fi

test_case "first-party jobs install the provider that has a configured credential"
if grep -q 'npm install -g @anthropic-ai/claude-code' "$WORKFLOW" &&
   ! grep -q 'npm install -g @openai/codex' "$WORKFLOW"; then
    test_pass
else
    test_fail "workflow installs unauthenticated Codex instead of configured Claude Code"
fi

test_case "first-party jobs pass the Claude OAuth secret to orchestration"
oauth_bindings="$(grep -c 'CLAUDE_CODE_OAUTH_TOKEN:.*secrets.CLAUDE_CODE_OAUTH_TOKEN' "$WORKFLOW" || true)"
non_bare_bindings="$(grep -c 'OCTOPUS_DISABLE_BARE: 1' "$WORKFLOW" || true)"
if [[ "$oauth_bindings" -ge 3 && "$non_bare_bindings" -ge 3 ]]; then
    test_pass
else
    test_fail "expected Claude OAuth/non-bare binding in all three jobs; found oauth=$oauth_bindings non-bare=$non_bare_bindings"
fi

test_case "Claude Code jobs use the supported Node runtime"
if grep -q "node-version: '22'" "$WORKFLOW" &&
   ! grep -q "node-version: '20'" "$WORKFLOW"; then
    test_pass
else
    test_fail "Claude Code npm installation requires the workflow's Node 22 runtime"
fi

test_case "first-party jobs pin the tested Claude Code package"
install_count="$(grep -c 'npm install -g @anthropic-ai/claude-code@2.1.228' "$WORKFLOW" || true)"
if [[ "$install_count" -eq 3 ]] &&
   ! grep -Eq 'npm install -g @anthropic-ai/claude-code([[:space:]]|$)' "$WORKFLOW"; then
    test_pass
else
    test_fail "expected all three jobs to pin Claude Code 2.1.228, found ${install_count}"
fi

test_case "artifact uploads use known immutable v7 commits"
artifact_refs="$(grep 'actions/upload-artifact' "$WORKFLOW" || true)"
# Verified upstream v7.0.1 and v7.0.2 commits; extend only after verifying a new release.
artifact_v7_commits='043fb46d1a93c77aae656e7c1c64a875d1fc6a0a|cf430e030ddbb5b0abf93d22962f4752f3646cd9'
artifact_pin_pattern="^[[:space:]]*(-[[:space:]]+)?uses[[:space:]]*:[[:space:]]*actions/upload-artifact@(${artifact_v7_commits})[[:space:]]+# v7[[:space:]]*$"
artifact_count="$(grep -Ec "$artifact_pin_pattern" <<< "$artifact_refs" || true)"
if [[ "$artifact_count" -eq 2 ]] && ! grep -Evq "$artifact_pin_pattern" <<< "$artifact_refs"; then
    test_pass
else
    test_fail "expected exactly two known immutable v7 artifact upload references"
fi

test_case "PR review preserves provider diagnostics when orchestration fails"
if grep -q 'name: Upload PR Review Diagnostics' "$WORKFLOW" &&
   grep -A10 'name: Upload PR Review Diagnostics' "$WORKFLOW" | grep -q 'if: always()' &&
   grep -A10 'name: Upload PR Review Diagnostics' "$WORKFLOW" | grep -q '~/.claude-octopus/results/' &&
   grep -A12 'name: Upload PR Review Diagnostics' "$WORKFLOW" | grep -q '~/.claude-octopus/runs/' &&
   grep -A12 'name: Upload PR Review Diagnostics' "$WORKFLOW" | grep -q 'include-hidden-files: true'; then
    test_pass
else
    test_fail "failed PR reviews discard hidden provider result/error evidence needed for diagnosis"
fi

test_case "PR review grants the job-scoped token Copilot request access"
pr_permissions="$(awk '
    /pr-review:/ { job=1 }
    job && /permissions:/ { capture=1 }
    capture { print }
    capture && /steps:/ { exit }
' "$WORKFLOW")"
if grep -q 'contents: read' <<< "$pr_permissions" &&
   grep -q 'pull-requests: write' <<< "$pr_permissions" &&
   grep -q 'copilot-requests: write' <<< "$pr_permissions" &&
   ! grep -q 'models: read' <<< "$pr_permissions"; then
    test_pass
else
    test_fail "PR review does not use the supported Copilot job-token permission set"
fi

test_case "actionlint suppresses only its stale Copilot permission diagnostic"
if [[ -f "$ACTIONLINT_CONFIG" ]] &&
   grep -Fq '.github/workflows/claude-octopus.yml:' "$ACTIONLINT_CONFIG" &&
   grep -Fq 'unknown permission scope "copilot-requests"' "$ACTIONLINT_CONFIG"; then
    test_pass
else
    test_fail "actionlint is not scoped to ignore its stale copilot-requests diagnostic"
fi

test_case "Claude quota failure triggers a GitHub Copilot fallback"
fallback_block="$(awk '
    /- name: Install GitHub Copilot CLI Fallback/ { capture=1 }
    capture { print }
    capture && /- name: Finalize Review Outcome/ { exit }
' "$WORKFLOW")"
if grep -q "steps.review.outcome == 'failure'" <<< "$fallback_block" &&
   grep -q 'npm install -g @github/copilot@1.0.79' <<< "$fallback_block" &&
   grep -q 'OCTOPUS_REVIEW_SINGLE_PROVIDER: copilot' <<< "$fallback_block" &&
   grep -q 'OCTOPUS_COPILOT_TOOL_POLICY: none' <<< "$fallback_block" &&
   grep -q 'GITHUB_TOKEN:.*github.token' <<< "$fallback_block" &&
   ! grep -q 'models.github.ai' <<< "$fallback_block" &&
   ! grep -q 'CLAUDE_CODE_OAUTH_TOKEN' <<< "$fallback_block"; then
    test_pass
else
    test_fail "PR review does not isolate or correctly configure the GitHub Copilot fallback"
fi

test_case "PR review fails closed when primary and fallback both fail"
finalize_block="$(awk '
    /- name: Finalize Review Outcome/ { capture=1 }
    capture { print }
    capture && /- name: Upload PR Review Diagnostics/ { exit }
' "$WORKFLOW")"
if grep -q 'PRIMARY_OUTCOME:.*steps.review.outcome' <<< "$finalize_block" &&
   grep -q 'FALLBACK_OUTCOME:.*steps.review_fallback.outcome' <<< "$finalize_block" &&
   grep -Eq 'PRIMARY_OUTCOME.*success.*\|\|.*FALLBACK_OUTCOME.*success' <<< "$finalize_block" &&
   grep -Eq 'exit[[:space:]]+1' <<< "$finalize_block"; then
    test_pass
else
    test_fail "PR review can pass after both provider paths fail"
fi

test_case "PR review materializes the base-to-head diff for review"
if grep -q 'git diff .*origin/.*\.\.\.HEAD.*> pr-review\.diff' "$WORKFLOW" &&
   grep -q '"target":"pr-review\.diff"' "$WORKFLOW"; then
    test_pass
else
    test_fail "pr-review does not feed the base-to-head diff artifact to code-review"
fi

test_case "PR review never asks code-review for the empty staged index"
if grep -q 'code-review.*"target":"staged"' "$WORKFLOW"; then
    test_fail "clean Actions checkouts have no staged diff"
else
    test_pass
fi

test_case "tee cannot mask a failed or empty review"
run_block="$(awk '
    /- name: Run Code Review/ { capture=1 }
    capture { print }
    capture && /- name: Post Review Comment/ { exit }
' "$WORKFLOW")"
if grep -q 'set -o pipefail' <<< "$run_block"; then
    test_pass
else
    test_fail "review pipeline does not preserve orchestrate.sh failure through tee"
fi

test_case "review diagnostics are posted even when the review fails"
post_header="$(awk '
    /- name: Post Review Comment/ { capture=1 }
    capture { print }
    capture && /uses: actions\/github-script/ { exit }
' "$WORKFLOW")"
if grep -q 'if:.*always()' <<< "$post_header"; then
    test_pass
else
    test_fail "failed review output is hidden because the comment step is success-only"
fi

test_case "issue-comment commands preserve orchestration failures through tee"
comment_run_block="$(awk '
    /- name: Run Claude Octopus/ { seen++; if (seen == 2) capture=1 }
    capture { print }
    capture && /- name: Reply to Comment/ { exit }
' "$WORKFLOW")"
if grep -q 'set -o pipefail' <<< "$comment_run_block"; then
    test_pass
else
    test_fail "comment-command can report success when orchestrate.sh failed"
fi

test_case "issue-comment diagnostics are posted even when orchestration fails"
reply_header="$(awk '
    /- name: Reply to Comment/ { capture=1 }
    capture { print }
    capture && /uses: actions\/github-script/ { exit }
' "$WORKFLOW")"
if grep -q 'if:.*always()' <<< "$reply_header"; then
    test_pass
else
    test_fail "failed issue-comment output is hidden because the reply step is success-only"
fi

test_case "manual review dispatch fetches a PR diff and invokes code-review"
if python3 - "$WORKFLOW" "$TEST_TMP_DIR" <<'PY'
from pathlib import Path
import json
import os
import subprocess
import sys

workflow = Path(sys.argv[1]).read_text().split('  pr-review:', 1)[0]
block = workflow.split('      - name: Run Claude Octopus\n', 1)[1].split('        run: |\n', 1)[1]
lines = []
for line in block.splitlines():
    if line and not line.startswith('          '):
        break
    lines.append(line[10:])
script = '\n'.join(lines)
fixture = Path(sys.argv[2]) / 'manual dispatch with spaces'
(fixture / 'scripts').mkdir(parents=True)
(fixture / 'bin').mkdir()
calls = fixture / 'calls.jsonl'
orchestrate = fixture / 'scripts/orchestrate.sh'
orchestrate.write_text('''#!'''+sys.executable+'''
import json, os, sys
from pathlib import Path
with open(os.environ['FIXTURE_CALLS'], 'a') as f:
    f.write(json.dumps(['orchestrate', *sys.argv[1:]])+'\\n')
if 'code-review' in sys.argv:
    profile = json.loads(sys.argv[-1])
    assert profile['target'] == 'pr-review.diff' and profile['publish'] == 'never'
    assert profile['contextText'] == os.environ['OCTOPUS_PROMPT']
    assert Path(profile['target']).read_text() == 'fixture diff\\n'
''')
orchestrate.chmod(0o700)
gh = fixture / 'bin/gh'
gh.write_text('''#!'''+sys.executable+'''
import json, os, sys
with open(os.environ['FIXTURE_CALLS'], 'a') as f:
    f.write(json.dumps(['gh', *sys.argv[1:]])+'\\n')
if os.environ.get('FIXTURE_DIFF_FAIL'): sys.exit(42)
if not os.environ.get('FIXTURE_DIFF_EMPTY'): print('fixture diff')
''')
gh.chmod(0o700)
base = dict(os.environ, PATH=str(fixture/'bin')+os.pathsep+os.environ['PATH'],
            FIXTURE_CALLS=str(calls), GITHUB_REPOSITORY='owner/repo',
            OCTOPUS_PR_NUMBER='1275', OCTOPUS_PROMPT='focus with spaces', OCTOPUS_TIER='standard')

def run(command, **updates):
    """Execute the workflow's real dispatch block with inert command targets."""
    calls.write_text('')
    result = subprocess.run(['bash', '-eo', 'pipefail', '-c', script], cwd=fixture,
                            env=dict(base, OCTOPUS_COMMAND=command, **updates),
                            capture_output=True, text=True)
    return result.returncode, [json.loads(line) for line in calls.read_text().splitlines()]

rc, invoked = run('review', OCTOPUS_TIER='premium')
assert rc == 0, (rc, invoked)
assert invoked[0] == ['gh', 'pr', 'diff', '1275', '--repo', 'owner/repo'], invoked
assert invoked[1][:-1] == ['orchestrate', '--ci', '-P', 'code-review'], invoked
rc, invoked = run('review')
assert rc == 0 and invoked[1][:-1] == ['orchestrate', '--ci', 'code-review'], invoked
for command in ('auto', 'embrace', 'research', 'develop', 'deliver'):
    rc, invoked = run(command, OCTOPUS_TIER='quick')
    assert rc == 0 and invoked == [['orchestrate', '--ci', '-Q', command, base['OCTOPUS_PROMPT']]], invoked
for number in ('', 'abc', '-1', '1275;touch marker'):
    rc, invoked = run('review', OCTOPUS_PR_NUMBER=number)
    assert rc != 0 and not invoked, (number, rc, invoked)
for update in ({'FIXTURE_DIFF_FAIL':'1'}, {'FIXTURE_DIFF_EMPTY':'1'}):
    rc, invoked = run('review', **update)
    assert rc != 0 and len(invoked) == 1 and invoked[0][0] == 'gh', invoked
rc, invoked = run('not-a-command')
assert rc != 0 and not invoked
PY
then test_pass; else test_fail "manual review dispatch did not reach code-review safely"; fi

test_summary
