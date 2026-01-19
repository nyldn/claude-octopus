---
name: skill-finish-branch
description: |
  Post-implementation workflow: verify tests, present 4 options (merge/PR/keep/discard), execute choice.
  Use when implementation is complete and you need to decide how to integrate the work.
  
  Use PROACTIVELY when user requests task completion with git operations:
  - "commit and push", "git commit and push"
  - "complete all tasks and commit and push", "proceed with all todos in sequence and push"
  - "save and commit", "wrap this up and push"
  - "I'm done with this feature", "ready to merge", "create PR for this work"
  
  DO NOT use for: individual file commits, work in progress without tests passing,
  or simple git status/diff commands.
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
---

# Finishing a Development Branch

## Overview

Guide completion of development work with clear options and safe execution.

**Core principle:** Verify tests → Present options → Execute choice → Clean up.

---

## The Process

### Step 1: Verify Tests Pass

**Before presenting options, verify tests pass:**

```bash
# Run project's test suite
npm test        # JavaScript/TypeScript
pytest          # Python
cargo test      # Rust
go test ./...   # Go
```

**If tests fail:**
```
❌ Tests failing (N failures). Must fix before completing:

[Show failures]

Cannot proceed with merge/PR until tests pass.
```

**STOP. Do not proceed to Step 2.**

**If tests pass:** Continue to Step 2.

---

### Step 2: Determine Base Branch

```bash
# Identify the base branch
git merge-base HEAD main 2>/dev/null || \
git merge-base HEAD master 2>/dev/null || \
git merge-base HEAD develop 2>/dev/null
```

If unclear, ask: "This branch split from `main` - is that correct?"

---

### Step 3: Present Options

Present exactly these 4 options:

```markdown
✅ Implementation complete. Tests passing. What would you like to do?

1. **Merge locally** - Merge back to <base-branch> on this machine
2. **Create PR** - Push and create a Pull Request for review
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
./scripts/orchestrate.sh ink "Validate before merge"

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
