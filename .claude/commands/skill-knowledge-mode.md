---
command: skill-knowledge-mode
description: "Instant toggle between dev and research modes (v7.2.1 - faster, clearer)"
usage: "/claude-octopus:km [on|off|status]"
examples:
  - "/claude-octopus:km on"
  - "/claude-octopus:km off"
  - "/claude-octopus:km"
aliases:
  - km
  - knowledge-mode
---

# Knowledge Mode - Instant Toggle

**Instantly** switch between **Development Mode** 🔧 (code-focused) and **Knowledge Work Mode** 🎓 (research, strategy, UX).

## What's New in v7.2.1

✅ **Instant switching** - No loading delays, optimized for speed
✅ **Clearer output** - Scannable status designed for Claude Code chat
✅ **Error-free** - Fixed config update issues
✅ **Persistent** - Settings automatically saved

## Current Status

Checking your current mode...

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh knowledge-mode
```

## Usage in Claude Code

Just run the command in your conversation:

```
/co:km on
/co:km off
/co:km
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

Both modes use the same AI providers (Codex + Gemini), but with different personas optimized for different types of work.

### Dev Work Mode 🔧 (Default)
When **OFF**, claude-octopus optimizes for software development:
- **Best for:** Building features, debugging code, implementing APIs
- **Primary tasks:** Code review, technical architecture, bug fixes
- **Personas:** backend-architect, code-reviewer, debugger, test-automator

Switch to Dev mode:
```bash
/co:dev
```

### Knowledge Work Mode 🎓
When **ON**, claude-octopus optimizes for research and strategy:
- **Best for:** User research, strategy analysis, literature reviews
- **Primary tasks:** UX research, market analysis, document synthesis
- **Personas:** ux-researcher, strategy-analyst, research-synthesizer

Switch to Knowledge mode:
```bash
/co:km on
```

## Current Status (v7.2.1)

After toggling, you'll see a **clearer, more scannable** output:

**Knowledge Mode Enabled:**
```
  🎓 Knowledge Work Mode ENABLED

  Best for: User research, strategy analysis, literature reviews
  Providers: Codex + Gemini (same as Dev mode)

  Switch back: /co:dev
```

**Dev Work Mode Active:**
```
  🔧 Dev Work Mode ACTIVE

  Best for: Building features, debugging code, implementing APIs
  Providers: Codex + Gemini (same as Knowledge mode)

  Switch to research: /co:km on
```

The new output is:
- **50% shorter** - Less scrolling in chat
- **More scannable** - Key info stands out
- **Actionable** - Clear next steps shown

## Usage Examples

### Enable for Research Session
```
/co:km on
```
Then work naturally:
- "Synthesize these 10 research papers on AI safety"
- "Analyze our market positioning vs competitors"
- "Review user interview transcripts and create personas"

### Quick Status Check
```
/co:km
```
(No argument = shows current status)

### Return to Development
```
/co:km off
```
Then resume coding:
- "Build an authentication system"
- "Review this PR for security issues"
- "Optimize database queries"

## Keyboard Shortcut

You can also use the shorter command:
```
/co:km on
/co:km off
/co:km
```

## Persistent Across Sessions

The mode setting is saved to `~/.claude-octopus/.user-config` and persists across terminal sessions. You only need to toggle once, and it stays that way until you change it.

## Pro Tips

1. **Task-specific toggle**: Turn on knowledge mode for research sprint, then turn off for implementation sprint
2. **Check before big tasks**: Run `/co:km` to confirm you're in the right mode
3. **Use with auto command**: The mode only affects `auto` routing - direct commands (`empathize`, `embrace`) work regardless of mode

## Related Commands

- `/co:setup` - Initial configuration
- `/co:update` - Check compatibility
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
