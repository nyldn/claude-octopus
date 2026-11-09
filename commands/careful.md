---
command: careful
disable-model-invocation: true
description: "[advanced] Activate destructive command warnings for the session"
---

# Careful Mode - Destructive Command Warnings

## Instructions

When the user invokes `/octo:careful`, activate careful mode for the current session.

### Activation

Resolve the active installation and use its session-state helper.

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
bash "$OCTO_ROOT/scripts/helpers/guard-state.sh" careful-on
```

A nonzero result means protection was not activated or changed. Do not announce
success. The helper requires a stable host session ID; a shell PID is not a
session identity. A missing directory fails before activation changes.

To deactivate, call the same helper with `careful-off`.

### What It Does

Careful mode adds a PreToolUse safety net on Bash commands. Before any destructive command executes, you will be prompted to confirm. This catches accidental damage without blocking normal work.

**Detected patterns:**
- `rm -rf` (except targets resolved below the working directory inside node_modules, dist, .next, __pycache__, build, coverage, or .turbo)
- Executables selected by variables or shell patterns, opaque dynamic wrappers, and command input
  piped into an interpreter require review even when the executable name is
  hidden. Ordinary argument text is not an executable.
- `DROP TABLE`, `DROP DATABASE`, `TRUNCATE`
- `git push --force`, `git push -f`
- `git reset --hard`
- `git checkout .`, `git restore .`
- `kubectl delete`
- `docker rm -f`, `docker system prune`

### Deactivation

Use the same host-aware helper in a new shell:

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
bash "$OCTO_ROOT/scripts/helpers/guard-state.sh" careful-off
```

If the helper cannot identify the session, report that warnings were not
deactivated; do not remove another process's state file.

### Usage

```text
/octo:careful
```

After activation, confirm to the user:

```text
⚠️ Careful mode activated. Destructive commands will now require confirmation before executing.
```

## When to Use

- Working in production environments
- Unfamiliar codebases where accidental deletion is risky
- Pair programming sessions where extra safety is desired
- Any time you want a safety net against destructive commands

## See Also

- `/octo:freeze` — Restrict edits to a specific directory
- `/octo:guard` — Activate both careful + freeze together
- `/octo:unfreeze` — Remove freeze restriction
