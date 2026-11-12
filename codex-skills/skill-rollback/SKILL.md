---
name: skill-rollback
description: "Roll back to a previous checkpoint via git — use when a change went wrong and you need to revert"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
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

Usage: `$skill-rollback <tag-name>`
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
git rev-parse --verify --end-of-options "refs/tags/$CHECKPOINT_TAG^{commit}" >/dev/null || exit 1
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
git diff --name-status HEAD "$CHECKPOINT_TAG" --
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
files. Reject assume-unchanged and skip-worktree entries without changing their
flags. Stop if the checkpoint adds, removes or changes a submodule gitlink;
its worktree needs a separate, reviewed restoration. Reject a checkpoint that would replace the `.octo` directory containing
protected lessons with a file or symlink. Check ignored files against the selected checkpoint too, including file
and directory collisions. A Git tag records committed files only. If either
check fails, stop and let the user preserve their work before starting again.
Use the plugin installation that loaded this skill. If `CLAUDE_PLUGIN_ROOT` is
absent, replace the fallback below with that installation's absolute path.

```bash
# Run the remaining rollback steps from the repository root.
cd -- "$(git rev-parse --show-toplevel)" || exit 1

# Refuse work that the safety tag cannot recover. Fail closed on Git errors.
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
python3 "$OCTO_ROOT/scripts/helpers/rollback-preflight.py" "$CHECKPOINT_TAG" || exit 1

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create safety checkpoint
git tag -a "octo-checkpoint-pre-rollback-$TIMESTAMP" -m "Safety checkpoint before rollback to $CHECKPOINT_TAG" || exit 1

# Keep the loaded preflight outside tracked files. A local-development rollback
# can delete the plugin helper when restoring a checkpoint older than the helper.
PREFLIGHT_COPY=$(git rev-parse --git-path "octo-rollback-preflight-$TIMESTAMP.py") || exit 1
(umask 077; set -C; cat "$OCTO_ROOT/scripts/helpers/rollback-preflight.py" > "$PREFLIGHT_COPY") || exit 1
```

Report:
```
Created safety checkpoint: octo-checkpoint-pre-rollback-$TIMESTAMP

To return to this state, follow "Recover from the safety checkpoint" below.
First commit or stash the rollback and any subsequent edits.
Recovery preflight saved in Git metadata: $PREFLIGHT_COPY
```

### Step 5: Preserve LESSONS.md

Exclude `.octo/LESSONS.md` from the tracked restore. Its current bytes and index
entry stay in place, even when the checkpoint has older lessons or no lessons
file. No shared temporary backup is needed.

### Step 6: Execute Rollback

Retain the exact selected `CHECKPOINT_TAG` and reported `TIMESTAMP` in the run
record. If this step starts a new shell, initialize both from that record before
running it. Never infer the latest checkpoint or generate a new timestamp.

```bash
# Supply the saved checkpoint in this shell; an unset value stops restoration.
: "${CHECKPOINT_TAG:?Set the selected checkpoint from Step 4}"

# Resolve the root again if this step starts in a new shell or subdirectory.
cd -- "$(git rev-parse --show-toplevel)" || exit 1

# Recheck immediately before restoring in case work changed after confirmation.
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}"
python3 "$OCTO_ROOT/scripts/helpers/rollback-preflight.py" "$CHECKPOINT_TAG" || exit 1

# Restore the full tracked snapshot, including removal of post-checkpoint files.
# Keep current lessons and do not move HEAD or change branches.
git restore --no-recurse-submodules --source="$CHECKPOINT_TAG" --staged --worktree -- . ':(exclude).octo/LESSONS.md' || exit 1
```

This restores the checkpoint's tracked files across the whole repository and
deletes tracked paths added since it, even when invoked from a subdirectory.
The index records the rollback for review and a later commit. HEAD,
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

````markdown
Rollback Complete

**Restored to:** `$CHECKPOINT_TAG`
**Files restored:** N files
**LESSONS.md:** Preserved (not rolled back)

**Safety checkpoint created:** `octo-checkpoint-pre-rollback-$TIMESTAMP`

### Next Steps

1. Review the restored files
2. Commit the rollback if satisfied:
   ```bash
   git diff --cached
    # The restore already staged its changes. Review any STATE.md edit separately.
    git commit -m "chore: rollback to $CHECKPOINT_TAG"
   ```
3. To return to the previous state, follow the recovery instructions below.
````

### Recover from the safety checkpoint

The rollback leaves staged changes, and Step 7 can also leave an unstaged
STATE.md update. A second `$skill-rollback` refuses this non-clean tree. First
commit or stash the restored state and any subsequent edits, including
untracked files. Choose how to preserve that work with the user before recovery.
Keep the saved commit or stash until recovery has been reviewed.

Use the exact safety tag reported in Step 4. If starting a new shell, set
`TIMESTAMP` to that tag's timestamp before running this recipe. The preflight
still refuses dirty work, hidden index entries and ignored-file collisions.
Step 4 keeps a private copy of the loaded preflight in Git metadata, which
tracked restoration cannot remove. Keep that copy until recovery is reviewed.
If it is missing or unreadable, stop; do not skip the preflight.

```bash
cd -- "$(git rev-parse --show-toplevel)" || exit 1
SAFETY_TAG="octo-checkpoint-pre-rollback-$TIMESTAMP"
PREFLIGHT_COPY=$(git rev-parse --git-path "octo-rollback-preflight-$TIMESTAMP.py") || exit 1
python3 "$PREFLIGHT_COPY" "$SAFETY_TAG" || exit 1
git restore --no-recurse-submodules --source="$SAFETY_TAG" --staged --worktree -- . ':(exclude).octo/LESSONS.md' || exit 1
```

Review the restored files before committing. Recovery preserves the current
lessons file and its index entry, and leaves HEAD, branches and tags in place.


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
| `$skill-rollback` | List available checkpoints |
| `$skill-rollback list` | List available checkpoints |
| `$skill-rollback <tag>` | Rollback to specific checkpoint |


## The Bottom Line

```
Rollback → Confirmation received AND safety checkpoint created
Otherwise → Not executed
```

**Show preview. Require "ROLLBACK". Create safety tag. Preserve lessons. Execute safely.**
