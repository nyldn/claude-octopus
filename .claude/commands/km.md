---
command: octo:km
description: "Toggle between Dev Work and Knowledge Work modes"
usage: "/octo:km [on|off|status]"
examples:
  - "/octo:km on    # Switch to Knowledge Work mode"
  - "/octo:km off   # Switch to Dev Work mode"
  - "/octo:km       # Show current mode"
---

# Knowledge Mode Toggle

Toggle between **Dev Work Mode** and **Knowledge Work Mode**.

## Usage

```bash
/octo:km on      # Switch to Knowledge Work mode
/octo:km off     # Switch to Dev Work mode (same as /octo:dev)
/octo:km         # Show current mode status
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

- `/octo:dev` - Switch to Dev Work mode
- `/octo:km on` - Switch to Knowledge Work mode

Your mode choice persists across sessions.
