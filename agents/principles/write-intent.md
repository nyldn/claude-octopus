---
name: write-intent-principle
domain: general
description: Announce intent before writing files — one sentence stating what, where, and why, with an idempotence check that skips the Write entirely when state is already correct.
---

# Write-Intent Principle

Before creating, overwriting, or rewriting any file as part of a command, skill, or agent workflow, you MUST:

## 1. Check for idempotence first

If the desired state already matches the current state, **do not call Write at all.** Confirm the state to the user and exit. The most common bug this prevents is writing config for a mode / setting / flag the user is already in — that's noise, not value.

Examples of state to check before writing:
- Target mode matches current mode → skip
- Target frontmatter field matches current field → skip
- Generated file is byte-identical to what you'd write → skip

## 2. Announce intent in one sentence

When a Write **is** needed, say what you're about to do **before** calling the tool. Format:

> Writing `<path>` (create | update | overwrite) — `<field/change>` — because `<why>`.

Example:

> Updating `.claude/claude-octopus.local.md` — setting `knowledge_mode: false` (was `true`) — because the user requested `/octo:dev`.

## 3. Never write "empty" config

Do not create a config file populated with defaults just to "mark" a state. Absent config is a legitimate state — it means "use defaults". Creating a file to restate defaults adds noise, makes diffs confusing, and implies the user opted into something they didn't.

## 4. Respect scope

Before writing to `.claude/`, `~/.claude-octopus/`, `~/.claude/`, or any user-owned directory from a command/skill, consider whether the file should live in:
- The plugin (committed, shipped to all users)
- The user's home (`~/.claude/`) — persists across projects
- The project workspace (`.claude/`) — per-project
- `~/.claude/scratchpad/<session-id>/` — ephemeral working files

A user-facing command that writes to an unexpected scope (e.g. a "mode switch" that writes to project `.claude/`) needs to say *which* scope in its intent sentence.

## Anti-Patterns (reject in review)

- ❌ `/octo:dev` writes `.claude/claude-octopus.local.md` when the file didn't exist and the user was already in default Dev Work Mode.
- ❌ A "setup" wizard silently creates configuration for every possible option even when not selected.
- ❌ An idempotent-looking operation overwrites a file with identical content, bumping its mtime and confusing build systems.
- ❌ A skill announces "I'll update your config" and then writes without showing the diff or field being changed.

## Correct Patterns

- ✅ Check current state → already matches target → confirm to user → exit without Write.
- ✅ "Switching Knowledge Work → Dev Work — updating `.claude/claude-octopus.local.md` (`knowledge_mode: true` → `false`)." followed by the Write.
- ✅ "No `.claude/claude-octopus.local.md` exists — you're in default Dev Work Mode. Nothing to change." followed by no Write.

## Scope

This principle applies to **all** Write operations initiated by skills, commands, and agents in this plugin. Tests in `tests/unit/test-write-intent.sh` enforce that user-facing mode-switch commands carry the idempotence check in their implementation instructions.
