---
command: unfreeze
disable-model-invocation: true
description: "[advanced] Remove freeze mode edit restriction"
---

# Unfreeze - Remove Edit Boundary

## Instructions

When the user invokes `/octo:unfreeze`, remove the freeze mode restriction.

### Deactivation

Resolve the active installation and use its session-state helper.
`freeze-off` takes no directory argument.

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
bash "$OCTO_ROOT/scripts/helpers/guard-state.sh" freeze-off
```

A nonzero result means the freeze was not removed. Do not announce success.
The helper requires a stable host session ID; a shell PID is not a session
identity.

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
