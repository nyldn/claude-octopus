---
command: km
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
   - No argument or "on" → target mode = Knowledge Work (`knowledge_mode: true`)
   - "off" → target mode = Dev Work (`knowledge_mode: false`)

2. **Check current mode** via `.claude/claude-octopus.local.md`:
   - Target is Dev Work AND file does NOT exist → user is already in Dev Work Mode (default). **Do not create the file.** Show confirmation only, then exit.
   - File exists AND current `knowledge_mode` already equals the target → **Do not rewrite the file.** Show confirmation only, then exit.
   - Otherwise → proceed to step 3 (real transition needed).

3. **Switch modes** (only when a real transition is required):
   - Before writing, state one sentence: "Switching to Knowledge Work — creating `.claude/claude-octopus.local.md` (`knowledge_mode: true`)." (or the equivalent for Dev Work).
   - If the file does not exist, create it with minimal frontmatter containing only the fields being set.
   - If the file exists, update only the `knowledge_mode` field; preserve any other keys.
   - Confirm with the target mode's emoji (🎓 / 🔧) and active personas.

**Rule (v9.30+):** Never create or rewrite `.claude/claude-octopus.local.md` when the user is already in the target mode. The v9.29 behavior over-executed — it wrote config for a state the user was already in, without explanation. Skip the Write tool entirely when there's nothing to change. See `agents/principles/write-intent.md` for the general principle.

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
