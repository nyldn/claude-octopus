---
name: km
description: "Shortcut for /co:skill-knowledge-mode - Quick toggle between dev and research modes"
redirect: skill-knowledge-mode
usage: "/co:km [on|off|status]"
---

# km - Knowledge Mode Quick Toggle (Shortcut)

This is a shortcut alias for `/co:skill-knowledge-mode`.

**Instant** mode switching optimized for Claude Code.

## Current Status

Checking your current mode...

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh knowledge-mode
```

## Usage

```
/co:km on      # Enable knowledge work mode
/co:km off     # Enable development mode
/co:km         # Show current status
```

## What It Does

Instantly switches between:
- **Development Mode** 🔧: Optimized for coding, code review, technical implementation
- **Knowledge Work Mode** 🎓: Optimized for research, UX, strategy, analysis

For full documentation, see `/co:skill-knowledge-mode`.
