---
command: freeze
disable-model-invocation: true
description: "[advanced] Restrict file edits to a specific directory boundary"
---

# Freeze Mode - Edit Boundary Enforcement

## Instructions

When the user invokes `/octo:freeze <directory>`, activate freeze mode to restrict Edit and Write operations to the specified directory.

### Activation

Resolve the active installation and use its session-state helper. Replace
`<directory>` with the supplied directory as one quoted argument. For `guard-on`,
omit that argument when only careful mode was requested.

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
bash "$OCTO_ROOT/scripts/helpers/guard-state.sh" freeze-on "<directory>"
```

A nonzero result means protection was not activated or changed. Do not announce
success. The helper requires a stable host session ID; a shell PID is not a
session identity. A missing directory fails before activation changes.

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
