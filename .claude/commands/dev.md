---
command: dev
description: "Switch to Dev Work mode - optimized for software development"
aliases:
  - dev-mode
---

# Dev Work Mode

Switch to **Dev Work Mode**, optimized for software development.

## Implementation Instructions

When this command is executed:

1. **Check current mode** via `.claude/claude-octopus.local.md`:
   - If file does NOT exist → user is already in Dev Work Mode (default). **Do not create the file.** Show confirmation only, then exit.
   - If file exists and `knowledge_mode: false` → user is already in Dev Work Mode. **Do not rewrite the file.** Show confirmation only, then exit.
   - If file exists and `knowledge_mode: true` → proceed to step 2.

2. **Switch to Dev Work mode** (only if a real transition is needed):
   - Before writing, state one sentence: "Switching Knowledge Work → Dev Work — updating `.claude/claude-octopus.local.md` (`knowledge_mode: true` → `false`)."
   - Update the existing file's `knowledge_mode` field to `false` (preserve any other keys in frontmatter).
   - Confirm the switch.

3. **Show confirmation:**
   - Display Dev Work Mode emoji (🔧)
   - List active personas
   - Suggest available commands (`/octo:develop`, `/octo:review`, `/octo:tdd`, etc.)

**Rule (v9.30+):** Never create or rewrite `.claude/claude-octopus.local.md` when the user is already in the target mode. The v9.29 behavior over-executed — it wrote config for a state the user was already in, without explanation. Skip the Write tool entirely when there's nothing to change. See `agents/principles/write-intent.md` for the general principle.

## Usage

```bash
/octo:dev        # Switch to Dev Work mode
```

## What is Dev Work Mode?

**Dev Work Mode** 🔧 is optimized for:
- Building features and implementing APIs
- Debugging code and fixing bugs
- Technical architecture and code review
- Test-driven development

**Personas**: backend-architect, code-reviewer, debugger, test-automator, performance-engineer

## Two Work Modes

Claude Octopus has two work modes:

1. **Dev Work Mode** 🔧 (this mode)
   - For: Software development, code, technical tasks

2. **Knowledge Work Mode** 🎓
   - For: User research, strategy analysis, literature reviews
   - Switch: `/octo:km on`

Both modes use the same AI providers (Codex + Gemini), just optimized with different personas.

## Learn More

Run `/octo:setup` to configure your preferences and choose your default mode.
