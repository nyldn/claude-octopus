---
command: octo:km
description: "Switch to Knowledge Work mode (or toggle with off)"
usage: "/octo:km [on|off]"
examples:
  - "/octo:km       # Switch to Knowledge Work mode"
  - "/octo:km on    # Switch to Knowledge Work mode (explicit)"
  - "/octo:km off   # Switch to Dev Work mode"
---

# Knowledge Mode Toggle

Toggle between **Dev Work Mode** and **Knowledge Work Mode**.

## Implementation Instructions

When this command is executed:

1. **Parse the argument:**
   - No argument or "on": Switch to Knowledge Work mode (set `knowledge_mode: true`)
   - "off": Switch to Dev Work mode (set `knowledge_mode: false`)

2. **Check for config file:**
   - Config file: `.claude/claude-octopus.local.md`
   - If file doesn't exist when switching, create it
   - Use bash `test -f` to check existence before reading

3. **Switch to Knowledge Work mode (no argument or "on"):**
   - Create/update `.claude/claude-octopus.local.md` with YAML frontmatter
   - Set `knowledge_mode: true`
   - Confirm with emoji 🎓 and active personas

4. **Switch to Dev Work mode ("off"):**
   - Create/update `.claude/claude-octopus.local.md` with YAML frontmatter
   - Set `knowledge_mode: false`
   - Confirm with emoji 🔧 and active personas

## Usage

```bash
/octo:km         # Switch to Knowledge Work mode (default action)
/octo:km on      # Switch to Knowledge Work mode (explicit)
/octo:km off     # Switch to Dev Work mode (same as /octo:dev)
```

## Two Work Modes

**Dev Work Mode** 🔧 (default)
- Best for: Building features, debugging code, implementing APIs
- Personas: backend-architect, code-reviewer, debugger, test-automator

**Knowledge Work Mode** 🎓
- Best for: User research, strategy analysis, literature reviews
- Personas: ux-researcher, strategy-analyst, research-synthesizer

Both modes use the same AI providers (Codex + Gemini), just optimized with different personas.

## Quick Switch

- `/octo:dev` - Switch to Dev Work mode 🔧
- `/octo:km` - Switch to Knowledge Work mode 🎓

Your mode choice persists across sessions.
