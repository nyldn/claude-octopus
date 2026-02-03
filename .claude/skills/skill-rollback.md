---
name: skill-rollback
description: Rollback to a previous checkpoint using git tags
trigger: |
  AUTOMATICALLY ACTIVATE when user mentions:
  - "rollback" or "revert" or "undo"
  - "go back to" or "restore checkpoint"
argument-hint: "[list|<checkpoint-tag>]"
---

# Checkpoint Rollback

Safely rollback to a previous checkpoint while preserving lessons learned.

**Core principle:** List checkpoints → Confirm explicitly → Create safety backup → Restore → Preserve lessons.

---

## Subcommand Detection

Parse the user's request to determine mode:

| User Request | Mode | Action |
|--------------|------|--------|
| `list`, `show checkpoints`, no argument | LIST | Show available checkpoints |
| `octo-checkpoint-*` tag name | ROLLBACK | Rollback to specific checkpoint |

---

## Mode: LIST (Default)

### Step 1: Fetch Available Checkpoints

```bash
# List all octo checkpoints with dates
git tag -l "octo-checkpoint-*" --sort=-creatordate --format='%(refname:short)|%(creatordate:short)|%(contents:subject)'
```

### Step 2: Present Checkpoint Table

```markdown
## Available Checkpoints

| Tag | Created | Description |
|-----|---------|-------------|
| octo-checkpoint-post-discover-20260203-143022 | 2026-02-03 | After Discover phase |
| octo-checkpoint-post-define-20260203-150145 | 2026-02-03 | After Define phase |

Usage: `/octo:rollback <tag-name>`
```

**If no checkpoints found:**
```
No checkpoints found. Checkpoints are created automatically after each Octopus phase.

To create a manual checkpoint:
  git tag -a octo-checkpoint-manual-$(date +%Y%m%d-%H%M%S) -m "Manual checkpoint"
```

---

## Mode: ROLLBACK

### Step 1: Validate Checkpoint Exists

```bash
# Check if tag exists
git tag -l "$CHECKPOINT_TAG" | grep -q . || echo "TAG_NOT_FOUND"
```

**If tag not found:**
```
Checkpoint '$CHECKPOINT_TAG' not found.

Available checkpoints:
[show list output]
```

**STOP. Do not proceed.**

### Step 2: Show What Will Be Affected

```bash
# Get list of files that will be changed
git diff --name-status HEAD $CHECKPOINT_TAG
```

Present clearly:
```markdown
## Rollback Preview

**Rolling back to:** `octo-checkpoint-post-discover-20260203-143022`
**Created:** 2026-02-03 14:30:22
**Description:** After Discover phase

### Files That Will Be Changed

| Status | File |
|--------|------|
| M | src/auth/login.ts |
| D | src/auth/oauth.ts |
| A | src/legacy/old-auth.ts |

Legend: M=Modified, D=Deleted, A=Added (relative to current state)

### Protected Files (Will NOT be changed)
- `.octo/LESSONS.md` - Lessons are always preserved
```

### Step 3: Require Explicit Confirmation (MANDATORY)

```
To confirm this rollback, type ROLLBACK exactly.

Any other input will cancel.
```

**Wait for exact confirmation: `ROLLBACK`**

**CRITICAL:** Do NOT proceed without explicit "ROLLBACK" confirmation.

### Step 4: Create Safety Checkpoint

Before any rollback, create a pre-rollback checkpoint:

```bash
# Generate timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create safety checkpoint
git tag -a "octo-checkpoint-pre-rollback-$TIMESTAMP" -m "Safety checkpoint before rollback to $CHECKPOINT_TAG"
```

Report:
```
Created safety checkpoint: octo-checkpoint-pre-rollback-$TIMESTAMP

You can return to current state with:
  /octo:rollback octo-checkpoint-pre-rollback-$TIMESTAMP
```

### Step 5: Preserve LESSONS.md

```bash
# Save current LESSONS.md if it exists
if [ -f ".octo/LESSONS.md" ]; then
  cp .octo/LESSONS.md /tmp/LESSONS_PRESERVED.md
  LESSONS_PRESERVED=true
fi
```

### Step 6: Execute Rollback

```bash
# Restore files from checkpoint (does NOT move HEAD)
git checkout $CHECKPOINT_TAG -- .

# Restore preserved LESSONS.md
if [ "$LESSONS_PRESERVED" = "true" ]; then
  cp /tmp/LESSONS_PRESERVED.md .octo/LESSONS.md
fi
```

**Important:** This uses `git checkout <tag> -- .` which:
- Restores all files to checkpoint state
- Does NOT move HEAD or change branch
- Preserves current commit history
- Allows immediate commit of the restored state

### Step 7: Update STATE.md (If Exists)

```bash
if [ -f ".octo/STATE.md" ]; then
  # Append rollback entry to history
  echo "" >> .octo/STATE.md
  echo "## Rollback - $(date '+%Y-%m-%d %H:%M')" >> .octo/STATE.md
  echo "" >> .octo/STATE.md
  echo "- **Target:** $CHECKPOINT_TAG" >> .octo/STATE.md
  echo "- **Safety checkpoint:** octo-checkpoint-pre-rollback-$TIMESTAMP" >> .octo/STATE.md
  echo "- **Reason:** User requested rollback" >> .octo/STATE.md
fi
```

### Step 8: Report Success

```markdown
Rollback Complete

**Restored to:** `$CHECKPOINT_TAG`
**Files restored:** N files
**LESSONS.md:** Preserved (not rolled back)

**Safety checkpoint created:** `octo-checkpoint-pre-rollback-$TIMESTAMP`

### Next Steps

1. Review the restored files
2. Commit the rollback if satisfied:
   ```bash
   git add -A && git commit -m "chore: rollback to $CHECKPOINT_TAG"
   ```
3. Or return to previous state:
   ```bash
   /octo:rollback octo-checkpoint-pre-rollback-$TIMESTAMP
   ```
```

---

## Safety Measures

| Measure | Implementation |
|---------|----------------|
| **Always create safety checkpoint** | Pre-rollback tag created BEFORE any file changes |
| **Preserve LESSONS.md** | Copy before rollback, restore after |
| **Require explicit confirmation** | Must type "ROLLBACK" exactly |
| **Show affected files first** | Preview before confirmation |
| **No history modification** | Uses checkout, not reset |

---

## Red Flags - Never Do

| Action | Why It's Dangerous |
|--------|-------------------|
| Rollback without confirmation | Loses work unexpectedly |
| Skip safety checkpoint | No recovery path |
| Rollback LESSONS.md | Loses accumulated knowledge |
| Use `git reset --hard` | Destroys commit history |
| Force push after rollback | Affects collaborators |
| Delete checkpoint tags | Removes recovery points |

---

## Checkpoint Tag Format

All Octopus checkpoints follow this format:

```
octo-checkpoint-{type}-{timestamp}

Where:
- type: post-discover, post-define, post-develop, post-deliver, pre-rollback, manual
- timestamp: YYYYMMDD-HHMMSS
```

Examples:
- `octo-checkpoint-post-discover-20260203-143022`
- `octo-checkpoint-post-define-20260203-150145`
- `octo-checkpoint-pre-rollback-20260203-161530`
- `octo-checkpoint-manual-20260203-170000`

---

## Quick Reference

| Command | Action |
|---------|--------|
| `/octo:rollback` | List available checkpoints |
| `/octo:rollback list` | List available checkpoints |
| `/octo:rollback <tag>` | Rollback to specific checkpoint |

---

## The Bottom Line

```
Rollback → Confirmation received AND safety checkpoint created
Otherwise → Not executed
```

**Show preview. Require "ROLLBACK". Create safety tag. Preserve lessons. Execute safely.**
