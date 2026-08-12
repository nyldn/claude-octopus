#!/usr/bin/env bash
# Regression coverage for the first-party PR review workflow (#888).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "PR review workflow uses the actual diff and fails closed"

WORKFLOW="$PROJECT_ROOT/.github/workflows/claude-octopus.yml"

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

test_case "PR review preserves provider diagnostics when orchestration fails"
if grep -q 'name: Upload PR Review Diagnostics' "$WORKFLOW" &&
   grep -A10 'name: Upload PR Review Diagnostics' "$WORKFLOW" | grep -q 'if: always()' &&
   grep -A10 'name: Upload PR Review Diagnostics' "$WORKFLOW" | grep -q '~/.claude-octopus/results/' &&
   grep -A10 'name: Upload PR Review Diagnostics' "$WORKFLOW" | grep -q '~/.claude-octopus/runs/'; then
    test_pass
else
    test_fail "failed PR reviews discard the provider result/error evidence needed for diagnosis"
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

test_summary
