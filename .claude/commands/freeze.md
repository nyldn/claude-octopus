---
command: freeze
description: Restrict file edits to a specific directory boundary
---

# Freeze Mode - Edit Boundary Enforcement

## Instructions

When the user invokes `/octo:freeze <directory>`, activate freeze mode to restrict Edit and Write operations to the specified directory.

### Activation

1. Resolve the directory argument to an absolute path
2. Ensure trailing `/` for safe prefix matching
3. Write the boundary to the state file:

```bash
# Resolve to absolute path
freeze_dir="$(cd "$1" 2>/dev/null && pwd)" || freeze_dir="$1"
# Write state
echo "${freeze_dir}" > "/tmp/octopus-freeze-${CLAUDE_SESSION_ID:-$$}.txt"
```

### What It Does

Freeze mode adds a PreToolUse safety net on Edit and Write tools. Any file operation targeting a path **outside** the frozen directory is blocked with a deny decision. This prevents accidental edits to unrelated code.

**Blocked:** Edit, Write to files outside the boundary
**Unaffected:** Read, Bash, Glob, Grep (investigation stays unrestricted)

### Usage

```
/octo:freeze src/auth
/octo:freeze ./packages/core
/octo:freeze /absolute/path/to/module
```

After activation, confirm to the user:

```
🔒 Freeze mode activated. Edits restricted to: <resolved-path>
   Read/search operations remain unrestricted.
   Use /octo:unfreeze to remove this restriction.
```

### Argument Required

If invoked without a directory argument, ask the user which directory to freeze:

```
Which directory should I restrict edits to? Example: /octo:freeze src/auth
```

## When to Use

- Debugging a specific module (auto-activated by skill-debug)
- Code review where you want to ensure no unrelated changes
- Focused refactoring within a single package
- Any time you want to guarantee edit boundaries

## See Also

- `/octo:careful` — Warn before destructive commands
- `/octo:guard` — Activate both careful + freeze together
- `/octo:unfreeze` — Remove freeze restriction
