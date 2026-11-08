---
description: "[advanced] Activate both careful mode and freeze mode together"
disable-model-invocation: true
---

# Guard Mode - Full Safety Activation

## Instructions

When the user invokes `/octo:guard <directory>`, activate both careful mode and freeze mode in a single command.

### Activation

Resolve the active installation and use its session-state helper. Replace
`<directory>` with the supplied directory as one quoted argument. For `guard-on`,
omit that argument when only careful mode was requested.

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
bash "$OCTO_ROOT/scripts/helpers/guard-state.sh" guard-on "<directory>"
```

A nonzero result means protection was not activated or changed. Do not announce
success. The helper requires a stable host session ID; a shell PID is not a
session identity. A missing directory fails before activation changes.

### What It Does

Guard mode combines both safety primitives:

- **Careful mode**: Warns before destructive Bash commands (rm -rf, DROP TABLE, git push --force, etc.)
- **Freeze mode**: Blocks Edit/Write operations outside the specified directory

This is the recommended safety configuration for focused work in sensitive codebases.

### Usage

```
/octo:guard src/auth
/octo:guard ./packages/core
/octo:guard /absolute/path/to/module
```

After activation, confirm to the user:

```
🛡️ Guard mode activated:
   ⚠️ Careful: Destructive commands require confirmation
   🔒 Freeze: Edits restricted to <resolved-path>
   Use /octo:unfreeze to remove edit restriction.
```

### Argument Required

If invoked without a directory argument, activate only careful mode and ask about freeze:

```
⚠️ Careful mode activated (destructive command warnings).
Which directory should I restrict edits to? Example: /octo:guard src/auth
```

## When to Use

- Starting work in a production-adjacent codebase
- Debugging with maximum safety
- When you want both protections without two separate commands

## See Also

- `/octo:careful` — Activate only destructive command warnings
- `/octo:freeze` — Activate only edit boundary enforcement
- `/octo:unfreeze` — Remove freeze restriction
