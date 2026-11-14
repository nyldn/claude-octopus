---
name: skill-rollback
description: "Roll back to a previous checkpoint via git — use when a change went wrong and you need to revert"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


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
# A tag records HEAD only; never overwrite work absent from that checkpoint.
ROLLBACK_STATUS=$(git status --porcelain=v1 --untracked-files=all) || exit 1
if [[ -n "$ROLLBACK_STATUS" ]]; then
  echo "Rollback requires a clean working tree and index. Preserve your changes before retrying." >&2
  exit 1
fi

# Bind confirmation to this repository, branch, revision and checkpoint commit.
ROLLBACK_PREVIEW_ROOT=$(git rev-parse --show-toplevel) || exit 1
ROLLBACK_PREVIEW_HEAD=$(git rev-parse --verify HEAD) || exit 1
ROLLBACK_PREVIEW_REF=$(git symbolic-ref --quiet HEAD || true)
ROLLBACK_TARGET_COMMIT=$(git rev-parse --verify "$CHECKPOINT_TAG^{commit}") || exit 1
printf 'ROLLBACK_PREVIEW_ROOT=%s\nROLLBACK_PREVIEW_HEAD=%s\nROLLBACK_PREVIEW_REF=%s\nROLLBACK_TARGET_COMMIT=%s\n' \
  "$ROLLBACK_PREVIEW_ROOT" "$ROLLBACK_PREVIEW_HEAD" "$ROLLBACK_PREVIEW_REF" "$ROLLBACK_TARGET_COMMIT"

# Get list of files that will be changed across the complete repository.
git -C "$ROLLBACK_PREVIEW_ROOT" diff --name-status "$ROLLBACK_PREVIEW_HEAD" "$ROLLBACK_TARGET_COMMIT"
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

The preview requires a clean index and working tree, including untracked files
reported by Git. Carry all four printed Step 2 values into later shells.
A safety tag records committed files only. Preserve changes
with a commit or another user-selected recovery method before retrying. Do not
stash, commit or discard unrelated work automatically. Recheck after confirmation
and immediately before restoration because the user may have edited files.

Before any rollback, create a pre-rollback checkpoint:

```bash
# A tag records HEAD only; never overwrite work absent from that checkpoint.
ROLLBACK_STATUS=$(git status --porcelain=v1 --untracked-files=all) || exit 1
if [[ -n "$ROLLBACK_STATUS" ]]; then
  echo "Rollback requires a clean working tree and index. Preserve your changes before retrying." >&2
  exit 1
fi

# Restore Step 2's exact printed values in a fresh shell. Never refresh them
# after confirmation; a changed context requires another preview and approval.
: "${ROLLBACK_PREVIEW_ROOT:?Restore the confirmed preview root}"
: "${ROLLBACK_PREVIEW_HEAD:?Restore the confirmed preview HEAD}"
: "${ROLLBACK_PREVIEW_REF?Restore the confirmed preview branch, empty for detached HEAD}"
: "${ROLLBACK_TARGET_COMMIT:?Restore the confirmed preview target commit}"
if [[ "$(git rev-parse --show-toplevel)" != "$ROLLBACK_PREVIEW_ROOT" ||
      "$(git rev-parse --verify HEAD)" != "$ROLLBACK_PREVIEW_HEAD" ||
      "$(git symbolic-ref --quiet HEAD || true)" != "$ROLLBACK_PREVIEW_REF" ||
      "$(git rev-parse --verify "$CHECKPOINT_TAG^{commit}")" != "$ROLLBACK_TARGET_COMMIT" ]]; then
  echo "Rollback context changed; show a new preview and obtain confirmation again." >&2
  exit 1
fi

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create safety checkpoint and retain the exact name for the history step.
SAFETY_CHECKPOINT_TAG="octo-checkpoint-pre-rollback-$TIMESTAMP"
git tag -a "$SAFETY_CHECKPOINT_TAG" "$ROLLBACK_PREVIEW_HEAD" -m "Safety checkpoint before rollback to $CHECKPOINT_TAG" || exit 1
printf 'Safety checkpoint: %s\n' "$SAFETY_CHECKPOINT_TAG"
```

Report:
```
Created safety checkpoint: $SAFETY_CHECKPOINT_TAG

After restoration, review and commit the restored changes before using this
command to return to the safety checkpoint. It requires a clean index and
working tree. Preserve any unrelated changes separately.
  /octo:rollback $SAFETY_CHECKPOINT_TAG
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
# A tag records HEAD only; never overwrite work absent from that checkpoint.
ROLLBACK_STATUS=$(git status --porcelain=v1 --untracked-files=all) || exit 1
if [[ -n "$ROLLBACK_STATUS" ]]; then
  echo "Rollback requires a clean working tree and index. Preserve your changes before retrying." >&2
  exit 1
fi

# Restore Step 2's exact printed values in a fresh shell. Never refresh them
# after confirmation; a changed context requires another preview and approval.
: "${ROLLBACK_PREVIEW_ROOT:?Restore the confirmed preview root}"
: "${ROLLBACK_PREVIEW_HEAD:?Restore the confirmed preview HEAD}"
: "${ROLLBACK_PREVIEW_REF?Restore the confirmed preview branch, empty for detached HEAD}"
: "${ROLLBACK_TARGET_COMMIT:?Restore the confirmed preview target commit}"
if [[ "$(git rev-parse --show-toplevel)" != "$ROLLBACK_PREVIEW_ROOT" ||
      "$(git rev-parse --verify HEAD)" != "$ROLLBACK_PREVIEW_HEAD" ||
      "$(git symbolic-ref --quiet HEAD || true)" != "$ROLLBACK_PREVIEW_REF" ||
      "$(git rev-parse --verify "$CHECKPOINT_TAG^{commit}")" != "$ROLLBACK_TARGET_COMMIT" ]]; then
  echo "Rollback context changed; show a new preview and obtain confirmation again." >&2
  exit 1
fi

# Restore files from checkpoint (does NOT move HEAD)
# No-overlay also removes tracked files added after the checkpoint. Keep lessons
# out of both index and worktree restoration so accumulated knowledge survives.
# Run checkout from the repository root even when this shell is in a subdirectory.
ROLLBACK_ROOT=$(git rev-parse --show-toplevel) || exit 1
# Ordinary status omits ignored local files. Refuse collisions before any write,
# including file/directory replacements; NUL-delimited paths retain newlines.
python3 -I - "$ROLLBACK_ROOT" "$ROLLBACK_TARGET_COMMIT" <<'PY_IGNORED' || exit 1
from bisect import bisect_left
import os
import subprocess
import sys

root, checkpoint = sys.argv[1:]
lessons_tracked = bool(subprocess.check_output([
    'git', '-C', root, 'ls-files', '-z', '--', '.octo/LESSONS.md',
]))
# Embedded repositories may be returned as a single directory entry ending in /.
ignored = {path.rstrip(b'/') for path in subprocess.check_output([
    'git', '-C', root, 'ls-files', '--others', '--ignored', '--exclude-standard', '-z',
]).split(b'\0') if path}
ordered = sorted(ignored)
targets = subprocess.check_output([
    'git', '-C', root, 'ls-tree', '-r', '--name-only', '-z', checkpoint, '--',
]).split(b'\0')
for target in targets:
    if target == b'.octo' and (lessons_tracked or os.path.lexists(os.path.join(root, '.octo', 'LESSONS.md'))):
        sys.exit('Rollback would replace the protected lessons directory. Preserve lessons before retrying.')
    if not target or target == b'.octo/LESSONS.md' or target.startswith(b'.octo/LESSONS.md/'):
        continue
    parts = target.split(b'/')
    prefixes = (b'/'.join(parts[:length]) for length in range(1, len(parts) + 1))
    descendant = bisect_left(ordered, target + b'/')
    if any(path in ignored for path in prefixes) or (
        descendant < len(ordered) and ordered[descendant].startswith(target + b'/')
    ):
        sys.exit('Rollback would overwrite ignored local files. Preserve them before retrying.')
PY_IGNORED
git -C "$ROLLBACK_ROOT" checkout --no-overlay "$ROLLBACK_TARGET_COMMIT" -- . ':(exclude).octo/LESSONS.md' || exit 1

# Restore preserved LESSONS.md
if [ "$LESSONS_PRESERVED" = "true" ]; then
  cp /tmp/LESSONS_PRESERVED.md .octo/LESSONS.md
fi
```

**Important:** This runs `git checkout --no-overlay <tag> -- . ':(exclude).octo/LESSONS.md'` from the repository root, which:
- Restores tracked files to checkpoint state, including additions and deletions
- Preserves current `.octo/LESSONS.md` in both the index and working tree
- Does NOT move HEAD or change branch
- Preserves current commit history
- Allows immediate commit of the restored state

### Step 7: Update STATE.md (If Exists)

Restore `CHECKPOINT_TAG` to the exact target used by the successful Step 6
restoration and `SAFETY_CHECKPOINT_TAG` to the exact name printed by Step 4.
Carry these literal values into this shell call even when earlier shell
variables no longer exist. Do not reconstruct the safety tag from a new clock
value or select a different tag by age. If either value is unavailable, report
that history was not updated rather than writing an incomplete recovery entry.
Symlinked state paths and non-regular files are refused before any append.

```bash
ROLLBACK_ROOT=$(git rev-parse --show-toplevel) || exit 1
python3 -I - "$ROLLBACK_ROOT" "${CHECKPOINT_TAG:-}" "${SAFETY_CHECKPOINT_TAG:-}" <<'PY_HISTORY' || exit 1
from contextlib import ExitStack
from datetime import datetime
import os
import stat
import subprocess
import sys

root, target, safety = sys.argv[1:]
try:
    with ExitStack() as opened:
        descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        opened.callback(os.close, descriptor)
        # Pin each repository-owned component. Never follow a restored symlink,
        # including one swapped in between directory lookup and the append.
        for name, flags in (
            (".octo", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW),
            ("STATE.md", os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK),
        ):
            try:
                descriptor = os.open(name, flags, dir_fd=descriptor)
            except FileNotFoundError:
                sys.exit(0)  # History remains optional when its state path is absent.
            opened.callback(os.close, descriptor)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError("rollback state must be a regular file")
        if not target or not safety:
            raise ValueError("restore the exact target from Step 6 and safety tag from Step 4")
        for tag in (target, safety):
            ref = "refs/tags/" + tag
            subprocess.run(["git", "-C", root, "check-ref-format", ref], check=True)
            subprocess.run(["git", "-C", root, "rev-parse", "--verify", ref + "^{commit}"],
                           check=True, stdout=subprocess.DEVNULL)
        entry = (f"\n## Rollback - {datetime.now():%Y-%m-%d %H:%M}\n\n"
                 f"- **Target:** {target}\n- **Safety checkpoint:** {safety}\n"
                 "- **Reason:** User requested rollback\n")
        with os.fdopen(os.dup(descriptor), "a", encoding="utf-8") as history:
            history.write(entry)
except (OSError, ValueError, subprocess.CalledProcessError) as error:
    sys.exit("Rollback history was not updated: " + str(error))
PY_HISTORY
```

### Step 8: Report Success

```markdown
Rollback Complete

**Restored to:** `$CHECKPOINT_TAG`
**Files restored:** N files
**LESSONS.md:** Preserved (not rolled back)

**Safety checkpoint created:** `$SAFETY_CHECKPOINT_TAG`

### Next Steps

1. Review the restored files
2. Commit the rollback if satisfied:
   ```bash
   git add -A && git commit -m "chore: rollback to $CHECKPOINT_TAG"
   ```
3. To return to the safety checkpoint, first review and commit the restored
   changes. The recovery command requires a clean index and working tree.
   Preserve unrelated changes separately; do not bypass the clean-tree gate.
   ```bash
   /octo:rollback $SAFETY_CHECKPOINT_TAG
   ```
```


## Safety Measures

| Measure | Implementation |
|---------|----------------|
| **Reject uncommitted work** | Check Git status before preview, tagging and restoration |
| **Always create safety checkpoint** | Pre-rollback tag created BEFORE any file changes |
| **Preserve LESSONS.md** | Copy before rollback, restore after |
| **Require explicit confirmation** | Must type "ROLLBACK" exactly |
| **Show affected files first** | Preview before confirmation |
| **No history modification** | Uses checkout, not reset |


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
