---
description: Run the Claude Octopus setup wizard to install dependencies and configure API keys
---

# Claude Octopus Setup

Run the interactive setup wizard to configure Claude Octopus.

## What This Does

The setup wizard will:
1. **Check/Install Codex CLI** - OpenAI's coding agent (tentacles 1-4)
2. **Check/Install Gemini CLI** - Google's reasoning agent (tentacles 5-8)
3. **Configure OpenAI API Key** - Opens platform.openai.com if needed
4. **Configure Gemini API Key** - Opens aistudio.google.com if needed
5. **Persist keys** - Optionally adds to your shell profile

## Run the Wizard

Execute this command in your terminal:

```bash
./scripts/orchestrate.sh setup
```

The wizard is interactive and will guide you through each step.

## After Setup

Verify everything is working:

```bash
./scripts/orchestrate.sh preflight
```

Then try your first command:

```bash
./scripts/orchestrate.sh embrace "Hello, Octopus!"
```
