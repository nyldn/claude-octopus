---
name: skill-finish-branch
description: "Wrap up a branch — run tests, create PR, merge or discard — use when implementation is done"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.


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


### Step 2: Determine the base branch and review the diff

Resolve the base before computing any diff. Carry the verified `BASE_REF` and local `BASE_BRANCH`
into each later shell invocation, along with the verified `MERGE_BASE`.

```bash
BASE_REF=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
if [[ -z "$BASE_REF" ]] || ! git rev-parse --verify "$BASE_REF^{commit}" >/dev/null 2>&1; then
  BASE_REF=""
  for candidate in main master; do
    if git rev-parse --verify "$candidate^{commit}" >/dev/null 2>&1; then
      BASE_REF="$candidate"
      break
    fi
  done
fi
[[ -n "$BASE_REF" ]] && git rev-parse --verify "$BASE_REF^{commit}" >/dev/null 2>&1 || {
  echo "Cannot determine the base branch; ask the user before reviewing or merging." >&2
  exit 1
}
BASE_BRANCH="${BASE_REF#origin/}"
MERGE_BASE=$(git merge-base HEAD "$BASE_REF") || {
  echo "Cannot determine a common ancestor; fetch the missing history or confirm the base before reviewing." >&2
  exit 1
}
[[ -n "$MERGE_BASE" ]] || exit 1
```

**Run a quick multi-provider review of the changes before shipping.** This catches issues before they reach PR reviewers.

```bash
# Get the diff summary
DIFF_STAT=$(git diff --stat "${MERGE_BASE:?Restore the verified merge base}..HEAD") || exit 1
DIFF_FILES=$(git diff --name-only "${MERGE_BASE:?Restore the verified merge base}..HEAD") || exit 1
```

**Always run a quick review — this is automatic, not optional:**

```bash
# Quick review via orchestrate.sh (uses available providers)
"${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/orchestrate.sh" spawn reviewer "Review this diff for bugs, security issues, and code quality problems. Be concise — only flag real issues, not style preferences.

$(git diff "${MERGE_BASE:?Restore the verified merge base}..HEAD" | head -500)"
```

**If critical issues found:** Present them and ask whether to fix or ship anyway.
**If clean:** Continue to Step 3. Show a brief `✓ Review clean — no issues found`.


### Step 3: Determine the version

```bash
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
COMMITS=$(git log --oneline "${MERGE_BASE:?Restore the verified merge base}..HEAD") || exit 1
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


### Step 6: Execute choice

#### Option 2: Merge Locally

```bash
# Get current branch name
FEATURE_BRANCH=$(git branch --show-current)
: "${BASE_BRANCH:?Restore the verified base branch}"

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


#### Option 1: Create PR

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


### Step 7: Cleanup (If Using Worktrees)

**After Merge locally or confirmed Discard only:** Check if in a worktree and clean up.
Keep the checkout after Create PR so review changes can be made.

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

**After Create PR or Keep as-is:** Keep the worktree intact.


## Quick Reference

| Option | Merge | Push | Keep Branch | Cleanup |
|--------|-------|------|-------------|---------|
| 2. Merge locally | ✓ | - | Delete | ✓ |
| 1. Create PR | - | ✓ | Keep | - |
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
# → Execute Option 1 (Create PR)
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
