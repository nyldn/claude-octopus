---
command: octo:dev
description: "Switch to Dev Work mode - optimized for software development"
aliases:
  - dev-mode
---

# Dev Work Mode

Switch to **Dev Work Mode**, optimized for software development.

## Implementation Instructions

When this command is executed:

1. **Check current mode:**
   - Config file: `.claude/claude-octopus.local.md`
   - If file doesn't exist, user is already in Dev Work Mode (default)
   - Use bash `test -f` to check existence before reading

2. **Switch to Dev Work mode:**
   - Create/update `.claude/claude-octopus.local.md` with YAML frontmatter
   - Set `knowledge_mode: false`
   - Confirm the switch with current mode details

3. **Show confirmation:**
   - Display Dev Work Mode emoji (🔧)
   - List active personas
   - Suggest available commands (octo build, octo review, etc.)

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
