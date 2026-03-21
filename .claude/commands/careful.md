---
command: careful
description: Activate destructive command warnings for the session
---

# Careful Mode - Destructive Command Warnings

## Instructions

When the user invokes `/octo:careful`, activate careful mode for the current session.

### Activation

Write the activation state file:

```bash
echo "active" > "/tmp/octopus-careful-${CLAUDE_SESSION_ID:-$$}.txt"
```

### What It Does

Careful mode adds a PreToolUse safety net on Bash commands. Before any destructive command executes, you will be prompted to confirm. This catches accidental damage without blocking normal work.

**Detected patterns:**
- `rm -rf` (except safe targets: node_modules, dist, .next, __pycache__, build, coverage, .turbo)
- `DROP TABLE`, `DROP DATABASE`, `TRUNCATE`
- `git push --force`, `git push -f`
- `git reset --hard`
- `git checkout .`, `git restore .`
- `kubectl delete`
- `docker rm -f`, `docker system prune`

### Deactivation

Remove the state file to deactivate:

```bash
rm -f "/tmp/octopus-careful-${CLAUDE_SESSION_ID:-$$}.txt"
```

### Usage

```
/octo:careful
```

After activation, confirm to the user:

```
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
