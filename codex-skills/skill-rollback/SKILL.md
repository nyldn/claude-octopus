---
name: skill-rollback
description: "Roll back to a previous checkpoint via git — use when a change went wrong and you need to revert"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.


# Checkpoint Rollback

Safely rollback to a previous checkpoint while preserving lessons learned.

**Core principle:** List checkpoints → Confirm explicitly → Create safety backup → Restore → Preserve lessons.


## Subcommand Detection

Parse the user's request to determine mode:

| User Request | Mode | Action |
|--------------|------|--------|
| `list`, `show checkpoints`, no argument | LIST | Show available checkpoints |
| `octo-checkpoint-*` tag name | ROLLBACK | Rollback to specific checkpoint |


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

Before any rollback, require a clean index and working tree, including untracked
files. Check ignored files against the selected checkpoint too, including file
and directory collisions. A Git tag records committed files only. If either
check fails, stop and let the user preserve their work before starting again.
Use the plugin installation that loaded this skill. If `CLAUDE_PLUGIN_ROOT` is
absent, replace the fallback below with that installation's absolute path.

```bash
# Refuse work that the safety tag cannot recover. Fail closed on Git errors.
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
python3 "$OCTO_ROOT/scripts/helpers/rollback-preflight.py" "$CHECKPOINT_TAG" || exit 1

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

Exclude `.octo/LESSONS.md` from the tracked restore. Its current bytes and index
entry stay in place, even when the checkpoint has older lessons or no lessons
file. No shared temporary backup is needed.

### Step 6: Execute Rollback

```bash
# Recheck immediately before restoring in case work changed after confirmation.
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
python3 "$OCTO_ROOT/scripts/helpers/rollback-preflight.py" "$CHECKPOINT_TAG" || exit 1

# Restore the full tracked snapshot, including removal of post-checkpoint files.
# Keep current lessons and do not move HEAD or change branches.
git restore --source="$CHECKPOINT_TAG" --staged --worktree -- . ':(exclude).octo/LESSONS.md' || exit 1
```

This restores the checkpoint's tracked files and deletes tracked paths added
since it. The index records the rollback for review and a later commit. HEAD,
commit history and `.octo/LESSONS.md` stay unchanged. Ignored local files remain
subject to the collision checks above.

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


## Safety Measures

| Measure | Implementation |
|---------|----------------|
| **Always create safety checkpoint** | Pre-rollback tag created BEFORE any file changes |
| **Preserve ignored local files** | Check checkpoint path collisions before tagging and immediately before restore |
| **Preserve LESSONS.md** | Exclude from index and worktree restoration |
| **Require explicit confirmation** | Must type "ROLLBACK" exactly |
| **Show affected files first** | Preview before confirmation |
| **No history modification** | Restores the tracked snapshot without moving HEAD |


## Red Flags - Never Do

| Action | Why It's Dangerous |
|--------|-------------------|
| Rollback without confirmation | Loses work unexpectedly |
| Skip safety checkpoint | No recovery path |
| Rollback LESSONS.md | Loses accumulated knowledge |
| Use `git reset --hard` | Destroys commit history |
| Force push after rollback | Affects collaborators |
| Delete checkpoint tags | Removes recovery points |


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


## Quick Reference

| Command | Action |
|---------|--------|
| `/octo:rollback` | List available checkpoints |
| `/octo:rollback list` | List available checkpoints |
| `/octo:rollback <tag>` | Rollback to specific checkpoint |


## The Bottom Line

```
Rollback → Confirmation received AND safety checkpoint created
Otherwise → Not executed
```

**Show preview. Require "ROLLBACK". Create safety tag. Preserve lessons. Execute safely.**
