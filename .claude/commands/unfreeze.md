---
command: unfreeze
description: Remove freeze mode edit restriction
---

# Unfreeze - Remove Edit Boundary

## Instructions

When the user invokes `/octo:unfreeze`, remove the freeze mode restriction.

### Deactivation

Remove the freeze state file:

```bash
rm -f "/tmp/octopus-freeze-${CLAUDE_SESSION_ID:-$$}.txt"
```

### What It Does

Removes the edit boundary set by `/octo:freeze` or `/octo:guard`. After unfreezing, Edit and Write operations are unrestricted again.

**Note:** This does NOT deactivate careful mode. If careful mode was activated (via `/octo:careful` or `/octo:guard`), destructive command warnings remain active.

### Usage

```
/octo:unfreeze
```

After deactivation, confirm to the user:

```
🔓 Freeze mode deactivated. Edits are no longer restricted to a specific directory.
```

## When to Use

- Finished debugging a specific module
- Need to edit files outside the current freeze boundary
- Switching focus to a different part of the codebase

## See Also

- `/octo:freeze` — Activate edit boundary enforcement
- `/octo:guard` — Activate both careful + freeze together
- `/octo:careful` — Destructive command warnings (independent of freeze)
