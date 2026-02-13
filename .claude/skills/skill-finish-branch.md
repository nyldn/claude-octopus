---
name: skill-finish-branch
description: "Post-implementation: verify tests, merge/PR/keep/discard"
trigger: |
  AUTOMATICALLY ACTIVATE when user requests task completion with git operations:
  - "commit and push" or "git commit and push"
  - "complete all tasks and commit and push"
  - "I'm done with this feature" or "ready to merge"
  - "create PR for this work"

  DO NOT activate for:
  - Individual file commits
  - Exploratory commits
  - Simple "git status" or "git diff"
execution_mode: enforced
---

# STOP. READ THIS FIRST.

**Before finishing a branch, you MUST run multi-AI validation via orchestrate.sh.**

---

## Step 1: Run validation (USE BASH TOOL NOW)

```bash
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" deliver "Validate before branch completion: <branch description>"
```

**WAIT for completion.**

## Step 2: Review validation results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -name "delivery-*.md" | sort -r | head -n1)
if [[ -n "$RESULT_FILE" ]]; then
  cat "$RESULT_FILE"
fi
```

## Step 3: Present options to user

Based on validation results, offer:
1. **Merge** - if validation passes
2. **Fix issues** - if validation found problems
3. **Create PR** - for team review
4. **Discard** - if the approach is wrong

Do NOT auto-merge without user confirmation.

---

## What NOT to do

- Do NOT skip the validation step
- Do NOT use `Task(octo:personas:*)` for validation
- If orchestrate.sh fails, tell the user - do NOT work around it
