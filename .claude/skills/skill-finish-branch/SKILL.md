---
name: skill-finish-branch
description: "Wrap up a branch — run tests, create PR, merge or discard — use when implementation is done"
trigger: |
  AUTOMATICALLY ACTIVATE when user requests task completion with git operations:
  - "commit and push" or "git commit and push"
  - "complete all tasks and commit and push"
  - "proceed with all todos in sequence and push"
  - "save and commit" or "wrap this up and push"
  - "I'm done with this feature" or "ready to merge"
  - "create PR for this work"

  DO NOT activate for:
  - Individual file commits (use built-in git tools)
  - Work in progress without tests passing
  - Exploratory commits
  - Simple "git status" or "git diff" commands
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - output_artifact_exists
paths:
  - ".git/**"
---

# Finishing a Development Branch

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Branch Completion`

## Overview

Full ship pipeline: tests → multi-provider review → version bump → changelog → commit → push → PR.

**Core principle:** Verify tests → Review diff → Bump version → Update changelog → Present options → Execute choice → Clean up.

---

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

---

### Step 2: Multi-Provider Diff Review

**Run a quick multi-provider review of the changes before shipping.** This catches issues before they reach PR reviewers.

```bash
# Get the diff summary
DIFF_STAT=$(git diff --stat $(git merge-base HEAD main)..HEAD)
DIFF_FILES=$(git diff --name-only $(git merge-base HEAD main)..HEAD)
```

**Always run a quick review — this is automatic, not optional:**

```bash
# Quick review via orchestrate.sh (uses available providers)
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh spawn reviewer "Review this diff for bugs, security issues, and code quality problems. Be concise — only flag real issues, not style preferences.

$(git diff $(git merge-base HEAD main)..HEAD | head -500)"
```

**If critical issues found:** Present them and ask whether to fix or ship anyway.
**If clean:** Continue to Step 3. Show a brief `✓ Review clean — no issues found`.

---

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

---

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

---

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

---

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

---

#### Option 2: Create PR

```bash
# Get branch info
FEATURE_BRANCH=$(git branch --show-current)

# Push branch
git push -u origin $FEATURE_BRANCH

# Create PR with description
gh pr create \
  --title "feat: [description]" \
  --body "$(cat <<'EOF'
## Summary
- [What changed]
- [Why it changed]

## Test Plan
- [x] Unit tests pass
- [x] Manual verification done
- [ ] Code review needed
EOF
)"
```

**Report:**
```
✅ Branch pushed to origin/$FEATURE_BRANCH
✅ PR created: https://github.com/owner/repo/pull/123

Branch preserved for review process.
```

---

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

---

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

---

### Step 5: Cleanup (If Using Worktrees)

**For Options 1, 2, 4:** Check if in a worktree and clean up:

```bash
# Check if current directory is a worktree
if git worktree list | grep -q "$(pwd)"; then
  # Get worktree path
  WORKTREE_PATH=$(pwd)
  
  # Switch to main worktree
  cd $(git worktree list | head -1 | awk '{print $1}')
  
  # Remove the worktree
  git worktree remove "$WORKTREE_PATH"
  
  echo "✅ Worktree cleaned up"
fi
```

**For Option 3:** Keep worktree intact.

---

## Quick Reference

| Option | Merge | Push | Keep Branch | Cleanup |
|--------|-------|------|-------------|---------|
| 1. Merge locally | ✓ | - | Delete | ✓ |
| 2. Create PR | - | ✓ | Keep | - |
| 3. Keep as-is | - | - | Keep | - |
| 4. Discard | - | - | Delete | ✓ |

---

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
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh ink "Validate before merge"

# If validation passes, proceed with finishing-branch
```

---

## Red Flags - Never Do

| Action | Why It's Dangerous |
|--------|-------------------|
| Merge without testing | Ships broken code |
| Skip confirmation for discard | Loses work permanently |
| Force-push without asking | Destroys history |
| Delete remote branch silently | Affects collaborators |
| Proceed when tests fail | Corrupts main branch |

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Offering options before testing | Always verify tests FIRST |
| Auto-merging without asking | Present 4 options, let user choose |
| Deleting without confirmation | Require typed "discard" |
| Cleaning up worktree on "keep" | Only cleanup for options 1, 2, 4 |

---

## The Bottom Line

```
Finishing branch → Tests verified AND user chose option
Otherwise → Not complete
```

**Verify tests. Present options. Execute safely. Clean up appropriately.**
