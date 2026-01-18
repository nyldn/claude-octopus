---
name: knowledge-mode
description: "Toggle between development mode (code-focused) and knowledge work mode (research, UX, strategy)"
usage: "/claude-octopus:knowledge-mode [on|off|status]"
examples:
  - "/claude-octopus:knowledge-mode on"
  - "/claude-octopus:knowledge-mode off"
  - "/claude-octopus:knowledge-mode"
aliases:
  - km
---

# Knowledge Mode - Quick Toggle

Instantly switch between **Development Mode** 🔧 (code-focused) and **Knowledge Work Mode** 🎓 (research, strategy, UX).

## Usage in Claude Code

Just run the command in your conversation:

```
/claude-octopus:knowledge-mode on
/claude-octopus:knowledge-mode off
/claude-octopus:knowledge-mode
```

Or even simpler - **just tell me!**
- "Switch to knowledge mode"
- "Enable research mode"
- "Back to development mode"
- "What mode am I in?"

I'll automatically detect and switch for you! ✨

## Quick Toggle

Run this command to toggle modes:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh knowledge-toggle
```

Or specify explicitly:

**Enable Knowledge Mode:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh knowledge-mode on
```

**Disable Knowledge Mode:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh knowledge-mode off
```

**Check Current Status:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh knowledge-mode status
```

## What Changes When You Toggle?

### Development Mode (Default) 🔧
When **OFF**, claude-octopus optimizes for software engineering:
- "Review this" → Code review
- "Analyze this" → Technical analysis
- "Research X" → Technical research
- Primary agents: `codex`, `gemini`, `code-reviewer`
- Workflows: `embrace`, `probe`, `tangle`, `optimize`

### Knowledge Work Mode 🎓
When **ON**, claude-octopus optimizes for research and strategy:
- "Review this" → Document/strategy review
- "Analyze this" → Market/user analysis
- "Research X" → Academic/market research
- Primary agents: `ux-researcher`, `strategy-analyst`, `research-synthesizer`
- Workflows: `empathize`, `advise`, `synthesize`

## Current Status

After toggling, you'll see:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Knowledge Work Mode Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Current Mode: 🎓 KNOWLEDGE WORK MODE ENABLED

Auto-routing behavior:
  ✓ "Review document" → UX/strategic review
  ✓ "Analyze market" → Strategy analysis
  ✓ "Research topic" → Literature synthesis
  ✓ Available workflows: empathize, advise, synthesize

Toggle back to development mode:
  /claude-octopus:knowledge-mode off
```

## Usage Examples

### Enable for Research Session
```
/claude-octopus:knowledge-mode on
```
Then work naturally:
- "Synthesize these 10 research papers on AI safety"
- "Analyze our market positioning vs competitors"
- "Review user interview transcripts and create personas"

### Quick Status Check
```
/claude-octopus:knowledge-mode
```
(No argument = shows current status)

### Return to Development
```
/claude-octopus:knowledge-mode off
```
Then resume coding:
- "Build an authentication system"
- "Review this PR for security issues"
- "Optimize database queries"

## Keyboard Shortcut

You can also use the shorter command:
```
/claude-octopus:km on
/claude-octopus:km off
/claude-octopus:km
```

## Persistent Across Sessions

The mode setting is saved to `~/.claude-octopus/.user-config` and persists across terminal sessions. You only need to toggle once, and it stays that way until you change it.

## Pro Tips

1. **Task-specific toggle**: Turn on knowledge mode for research sprint, then turn off for implementation sprint
2. **Check before big tasks**: Run `/claude-octopus:knowledge-mode` to confirm you're in the right mode
3. **Use with auto command**: The mode only affects `auto` routing - direct commands (`empathize`, `embrace`) work regardless of mode

## Related Commands

- `/claude-octopus:setup` - Initial configuration
- `/claude-octopus:check-updates` - Check compatibility
- See available workflows: `${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh help --full`

## Troubleshooting

**Mode not persisting?**
Check that `~/.claude-octopus/.user-config` is writable:
```bash
ls -la ~/.claude-octopus/.user-config
```

**Want to see what mode does?**
Run with dry-run to see routing differences:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh auto "review this document" --dry-run
```
