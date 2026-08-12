#!/usr/bin/env bash
# Regression coverage for the first-party PR review workflow (#888).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "PR review workflow uses the actual diff and fails closed"

WORKFLOW="$PROJECT_ROOT/.github/workflows/claude-octopus.yml"
ACTIONLINT_CONFIG="$PROJECT_ROOT/.github/actionlint.yaml"

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

test_case "artifact uploads use the immutable v7 commit"
artifact_count="$(grep -c 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' "$WORKFLOW" || true)"
if [[ "$artifact_count" -eq 2 ]] && ! grep -q 'actions/upload-artifact@v7' "$WORKFLOW"; then
    test_pass
else
    test_fail "artifact upload references remain mutable"
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

test_summary
