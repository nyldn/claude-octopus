---
description: Run the Claude Octopus setup wizard to install dependencies and configure API keys
---

# Claude Octopus Setup

The setup wizard is **interactive** and must be run in your **actual terminal** (not through Claude Code bash commands).

## What This Does

The setup wizard will:
1. **Check/Install Codex CLI** - OpenAI's coding agent (tentacles 1-4)
2. **Check/Install Gemini CLI** - Google's reasoning agent (tentacles 5-8)
3. **Configure API Keys** - Detects OAuth or prompts for API keys
4. **Configure subscription tiers** - Auto-detects from installed CLIs
5. **Set cost optimization strategy** - Balanced, cost-first, or quality-first

## Run the Wizard

**Please copy and run this command in your terminal:**

```bash
cd ~/.claude/plugins/claude-octopus && ./scripts/orchestrate.sh octopus-configure
```

The wizard is interactive and will guide you through each step with prompts and menus.

## After Setup

Verify everything is working:

```bash
cd ~/.claude/plugins/claude-octopus && ./scripts/orchestrate.sh status
```

Then test with a simple probe:

```bash
cd ~/.claude/plugins/claude-octopus && ./scripts/orchestrate.sh probe "Hello Octopus!"
```

## Quick Status Check

To check if you're already configured, run:

```bash
cd ~/.claude/plugins/claude-octopus && ./scripts/orchestrate.sh status
```

If you see authentication methods (oauth or api-key) for Codex and Gemini, you're all set!
