---
command: guard
description: Activate both careful mode and freeze mode together
---

# Guard Mode - Full Safety Activation

## Instructions

When the user invokes `/octo:guard <directory>`, activate both careful mode and freeze mode in a single command.

### Activation

1. Activate careful mode (destructive command warnings):

```bash
echo "active" > "/tmp/octopus-careful-${CLAUDE_SESSION_ID:-$$}.txt"
```

2. Activate freeze mode (edit boundary enforcement):

```bash
freeze_dir="$(cd "$1" 2>/dev/null && pwd)" || freeze_dir="$1"
echo "${freeze_dir}" > "/tmp/octopus-freeze-${CLAUDE_SESSION_ID:-$$}.txt"
```

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
