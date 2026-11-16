---
name: skill-finish-branch
description: "Wrap up a branch — run tests, create PR, merge or discard — use when implementation is done"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


## Execution Contract (MANDATORY - CANNOT SKIP)

This generated Codex skill preserves an enforced workflow contract from the source skill.

**PROHIBITED:**
- Do not summarize, simulate, or skip the referenced workflow command when this skill requires execution.
- Do not claim provider output or validation artifacts exist without checking the actual files or command output.
- Do not continue silently when a required provider, command, or host capability is unavailable; report the unavailable dependency and use a supported fallback.


# Finishing a Development Branch

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Branch Completion`

## Overview

Full ship pipeline: tests → multi-provider review → version bump → changelog → commit → push → PR.

**Core principle:** Verify tests → Review diff → Bump version → Update changelog → Present options → Execute choice → Clean up.


## The Process

### Step 1: Verify Tests Pass

**Before anything else, verify tests pass:**

```bash
# Detect and run project's test suite
if [[ -f "package.json" ]]; then npm test
elif [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then pytest
elif [[ -f "Cargo.toml" ]]; then cargo test
elif [[ -f "go.mod" ]]; then go test ./...
elif [[ -f "Makefile" ]] && grep -q '^test:' Makefile; then make test
fi
```

**If tests fail:** STOP. Show failures. Do not proceed.

**If tests pass:** Continue to Step 2.


### Step 2: Multi-Provider Diff Review

**Run a quick multi-provider review of the changes before shipping.** This catches issues before they reach PR reviewers.

```bash
# Get the diff summary
DIFF_STAT=$(git diff --stat $(git merge-base HEAD main)..HEAD)
DIFF_FILES=$(git diff --name-only $(git merge-base HEAD main)..HEAD)
```

**Always run a quick review — this is automatic, not optional:**

```bash
# Review the complete committed range. A text diff cannot review binary content
# or nested submodule source, and a partial prompt cannot establish coverage.
REVIEW_HEAD=$(git rev-parse --verify 'HEAD^{commit}') || exit 1
REVIEW_BASE=$(git merge-base "$REVIEW_HEAD" main) || exit 1
REVIEW_NUMSTAT=$(git diff --no-ext-diff --no-textconv --no-renames --no-relative \
  --ignore-submodules=none --no-color --numstat "$REVIEW_BASE" "$REVIEW_HEAD" --) || exit 1
if awk -F '\t' '$(1) == "-" || $(2) == "-" {found=1} END {exit !found}' <<< "$REVIEW_NUMSTAT"; then
  echo "Review incomplete: changed binary content needs a separate complete review." >&2
  exit 1
fi
REVIEW_RAW=$(git diff --no-ext-diff --no-textconv --no-renames --no-relative \
  --ignore-submodules=none --no-color --raw "$REVIEW_BASE" "$REVIEW_HEAD" --) || exit 1
if awk '$(1) == ":160000" || $(2) == "160000" {found=1} END {exit !found}' <<< "$REVIEW_RAW"; then
  echo "Review incomplete: changed submodules need a separate complete source review." >&2
  exit 1
fi
# Inspect bytes before Bash command substitution, which discards NUL bytes.
REVIEW_DIFF=$(python3 -I - "$REVIEW_BASE" "$REVIEW_HEAD" <<'PY_REVIEW_DIFF'
import subprocess
import sys
import re

diff = subprocess.check_output([
    'git', 'diff', '--no-ext-diff', '--no-textconv', '--no-renames',
    '--no-relative', '--ignore-submodules=none', '--no-color',
    sys.argv[1], sys.argv[2], '--',
])
if b'\0' in diff:
    sys.exit('Review incomplete: NUL-containing content needs a separate complete review.')
if re.search(rb'\[\[OCTOPUS_TRUSTED_JSON_CONTRACT_(?:BEGIN|END):[0-9a-fA-F]{32}\]\]', diff):
    sys.exit('Review incomplete: transport markers need a separate lossless review.')
if len(diff) > 60000:
    sys.exit('Review incomplete: the full diff exceeds the 60000-byte quick-review limit. Split it into fully reviewed ranges before continuing.')
sys.stdout.buffer.write(diff)
PY_REVIEW_DIFF
) || exit 1
# Collect the completed answer, rather than accepting a launch PID as a review.
REVIEW_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
source "$REVIEW_ROOT/scripts/lib/consultative-advisors.sh" || exit 1
REVIEW_OUTPUT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/octopus-review-results.XXXXXX") || exit 1
printf 'REVIEW_OUTPUT_DIR=%s\n' "$REVIEW_OUTPUT_DIR"
REVIEW_EVENT_LOG="$REVIEW_OUTPUT_DIR/events"
: > "$REVIEW_EVENT_LOG" || exit 1
cat > "$REVIEW_OUTPUT_DIR/lifecycle.sh" <<'REVIEW_HOOK'
#!/usr/bin/env bash
printf '%s\t%s\t%s\t%s\n' "${1:-}" "${OCTOPUS_AGENT_PID:-}" \
  "${OCTOPUS_AGENT_STATUS:-}" "${OCTOPUS_AGENT_RESULT_FILE:-}" >> "$OCTO_BRANCH_REVIEW_EVENTS" || exit 1
if [[ -n "${OCTO_BRANCH_REVIEW_PREV_HOOK:-}" && -x "$OCTO_BRANCH_REVIEW_PREV_HOOK" ]]; then
  exec "$OCTO_BRANCH_REVIEW_PREV_HOOK" "$@"
fi
REVIEW_HOOK
chmod +x "$REVIEW_OUTPUT_DIR/lifecycle.sh" || exit 1
REVIEW_PREV_HOOK="${OCTOPUS_AGENT_LIFECYCLE_HOOK:-}"
OCTOPUS_AGENT_LIFECYCLE_HOOK="$REVIEW_OUTPUT_DIR/lifecycle.sh" \
OCTO_BRANCH_REVIEW_EVENTS="$REVIEW_EVENT_LOG" \
OCTO_BRANCH_REVIEW_PREV_HOOK="$REVIEW_PREV_HOOK" \
OCTOPUS_OVERSIZE_STRATEGY=fail \
"$REVIEW_ROOT/scripts/orchestrate.sh" spawn reviewer "Review this diff for bugs, security issues, and code quality problems. Be concise — only flag real issues, not style preferences.

$REVIEW_DIFF" > "$REVIEW_OUTPUT_DIR/spawn.txt" || exit 1
# Native Agent Teams emits a dispatch receipt without a collectable answer.
if grep -q '^AGENT_TEAMS_DISPATCH:' "$REVIEW_OUTPUT_DIR/spawn.txt"; then
  echo "Review incomplete: native dispatch produced no answer. Use a supervised subprocess review." >&2
  exit 1
fi
if ! _octo_advisor_collect "$REVIEW_EVENT_LOG" "$REVIEW_OUTPUT_DIR/spawn.txt" \
    "$REVIEW_OUTPUT_DIR/answer.md" "$(( $(date +%s) + 600 ))"; then
  echo "Review incomplete; inspect $REVIEW_OUTPUT_DIR before retrying." >&2
  exit 1
fi
cat "$REVIEW_OUTPUT_DIR/answer.md" || exit 1
if [[ "$(git rev-parse --verify 'HEAD^{commit}')" != "$REVIEW_HEAD" ]]; then
  echo "Review incomplete: HEAD changed during review. Review the current committed range again." >&2
  exit 1
fi
```

Binary, submodule and oversized ranges leave the review incomplete. Obtain and
record a complete review of those changes before proceeding to Step 3.

**If critical issues found:** Present them and ask whether to fix or ship anyway.
**If clean:** Continue to Step 3. Show a brief `✓ Review clean — no issues found`.


### Step 3: Determine Base Branch & Version

```bash
# Identify the base branch
BASE_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
[[ -z "$BASE_BRANCH" ]] && BASE_BRANCH="main"

# Check for VERSION file
VERSION_FILE=""
for f in VERSION version.txt package.json; do
  [[ -f "$f" ]] && VERSION_FILE="$f" && break
done
```


### Step 4: Version Bump & Changelog (Optional)

**If a VERSION file or package.json exists**, offer to bump:

```javascript
AskUserQuestion({
  questions: [{
    question: "Version bump?",
    header: "Version",
    multiSelect: false,
    options: [
      {label: "Patch (Recommended)", description: "Bug fixes, minor changes (1.2.3 → 1.2.4)"},
      {label: "Minor", description: "New features, backward compatible (1.2.3 → 1.3.0)"},
      {label: "Major", description: "Breaking changes (1.2.3 → 2.0.0)"},
      {label: "Skip", description: "Don't bump version"}
    ]
  }]
})
```

**If bumping:** Update the version file and prepend a changelog entry summarizing the diff:

```bash
# Generate changelog entry from commits
COMMITS=$(git log --oneline $(git merge-base HEAD $BASE_BRANCH)..HEAD)
# Prepend to CHANGELOG.md if it exists
```


### Step 5: Present Options

Present exactly these 4 options:

```markdown
✅ Ship ready. Tests passing. Review clean. What would you like to do?

1. **Create PR** (Recommended) - Push and create a Pull Request for review
2. **Merge locally** - Merge back to <base-branch> on this machine
3. **Keep as-is** - Leave the branch, I'll handle it later
4. **Discard** - Delete this work permanently

Which option? (1-4)
```

**Keep options concise.** Don't add explanations unless asked.


### Step 4: Execute Choice

#### Option 1: Merge Locally

```bash
# Get current branch name
FEATURE_BRANCH=$(git branch --show-current)
BASE_BRANCH="main"  # or detected base

# Switch to base branch
git checkout $BASE_BRANCH

# Pull latest
git pull origin $BASE_BRANCH

# Merge feature branch
git merge $FEATURE_BRANCH

# Verify tests on merged result
npm test  # or appropriate test command

# If tests pass, delete feature branch
git branch -d $FEATURE_BRANCH
```

**Report:**
```
✅ Merged $FEATURE_BRANCH into $BASE_BRANCH
✅ Tests pass on merged result
✅ Feature branch deleted

Ready to push when you want: git push origin $BASE_BRANCH
```


#### Option 2: Create PR

```bash
# Get branch info
FEATURE_BRANCH=$(git branch --show-current)

# Push branch
git push -u origin $FEATURE_BRANCH

# Create PR with a validated description file
REPO_SLUG=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
PR_TITLE=${PR_TITLE:?Complete PR_TITLE before creating the pull request}
CHANGE_SUMMARY=${CHANGE_SUMMARY:?Complete CHANGE_SUMMARY before creating the pull request}
CHANGE_REASON=${CHANGE_REASON:?Complete CHANGE_REASON before creating the pull request}
PR_BODY=$(cat <<EOF
## Summary
- ${CHANGE_SUMMARY}
- ${CHANGE_REASON}

## Test Plan
- [x] Unit tests pass
- [x] Manual verification done
- [ ] Code review needed
EOF
)
if ! "${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/safe-gh-comment.sh" \
    --repo "$REPO_SLUG" pr-create "$PR_TITLE" "$FEATURE_BRANCH" - <<< "$PR_BODY"; then
  echo "GitHub write state is unknown; check for an existing pull request before retrying:" >&2
  gh pr list --repo "$REPO_SLUG" --head "$FEATURE_BRANCH" --state all --json number,state,url || true
  return 1 2>/dev/null || exit 1
fi
```

**Report:**
```
✅ Branch pushed to origin/$FEATURE_BRANCH
✅ PR created: https://github.com/owner/repo/pull/123

Branch preserved for review process.
```


#### Option 3: Keep As-Is

```
✅ Keeping branch $FEATURE_BRANCH as-is.

Current state:
- Branch: $FEATURE_BRANCH
- Commits ahead of $BASE_BRANCH: N
- Tests: Passing

When ready, you can:
- Merge: git checkout main && git merge $FEATURE_BRANCH
- PR: git push -u origin $FEATURE_BRANCH && gh pr create
- Discard: git branch -D $FEATURE_BRANCH
```

**Do NOT clean up anything.**


#### Option 4: Discard

**Confirm first (REQUIRED):**

```
⚠️ This will PERMANENTLY delete:
- Branch: $FEATURE_BRANCH
- All commits:
  - abc1234 feat: add user validation
  - def5678 fix: handle edge case
  - ghi9012 test: add integration tests

Type 'discard' to confirm, or anything else to cancel.
```

**Wait for exact confirmation: `discard`**

If confirmed:
```bash
# Switch to base branch first
git checkout $BASE_BRANCH

# Force delete the feature branch
git branch -D $FEATURE_BRANCH

# If remote exists, delete it too (with confirmation)
git push origin --delete $FEATURE_BRANCH 2>/dev/null || true
```

**Report:**
```
✅ Branch $FEATURE_BRANCH deleted locally
✅ Remote branch deleted (if existed)

Work has been permanently discarded.
```


### Step 5: Cleanup (If Using Worktrees)

**For Options 1, 2, 4:** Check if in a worktree and clean up:

```bash
# Check if current directory is a worktree
if git worktree list | grep -q "$(pwd)"; then
  # Get worktree path
  WORKTREE_PATH=$(pwd)
  
  # Switch to main worktree
  cd $(git worktree list | head -1 | awk '{print $(1)}')
  
  # Remove the worktree
  git worktree remove "$WORKTREE_PATH"
  
  echo "✅ Worktree cleaned up"
fi
```

**For Option 3:** Keep worktree intact.


## Quick Reference

| Option | Merge | Push | Keep Branch | Cleanup |
|--------|-------|------|-------------|---------|
| 1. Merge locally | ✓ | - | Delete | ✓ |
| 2. Create PR | - | ✓ | Keep | - |
| 3. Keep as-is | - | - | Keep | - |
| 4. Discard | - | - | Delete | ✓ |


## Integration with Claude Octopus

After completing octopus workflows, use this skill:

```bash
# After tangle (develop) phase completes successfully
# After ink (deliver) phase validates the work

# User says: "I'm done, create a PR"
# → Invoke finishing-branch skill
# → Verify tests
# → Present options
# → Execute Option 2 (Create PR)
```

### With Octopus Validation

```bash
# Run octopus validation before finishing
"${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/orchestrate.sh" ink "Validate before merge"

# If validation passes, proceed with finishing-branch
```


## Red Flags - Never Do

| Action | Why It's Dangerous |
|--------|-------------------|
| Merge without testing | Ships broken code |
| Skip confirmation for discard | Loses work permanently |
| Force-push without asking | Destroys history |
| Delete remote branch silently | Affects collaborators |
| Proceed when tests fail | Corrupts main branch |


## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Offering options before testing | Always verify tests FIRST |
| Auto-merging without asking | Present 4 options, let user choose |
| Deleting without confirmation | Require typed "discard" |
| Cleaning up worktree on "keep" | Only cleanup for options 1, 2, 4 |


## The Bottom Line

```
Finishing branch → Tests verified AND user chose option
Otherwise → Not complete
```

**Verify tests. Present options. Execute safely. Clean up appropriately.**
