---
command: sys-setup
description: Check Claude Octopus setup status and get configuration instructions
aliases:
  - setup
---

# Claude Octopus Setup

This command checks your current setup and provides instructions for any missing dependencies.

## Auto-Detection

Running setup detection...

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh detect-providers
```

Based on the results above, here's what you need:

## If You See: CODEX_STATUS=missing

Install Codex CLI:
```bash
npm install -g @openai/codex
```

Then configure authentication:
```bash
# Option 1: OAuth (recommended)
codex login

# Option 2: API Key
export OPENAI_API_KEY="sk-..."
# Get key from: https://platform.openai.com/api-keys
```

To make the API key permanent, add it to your shell profile:
```bash
# For zsh (macOS default)
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrc
source ~/.zshrc

# For bash
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.bashrc
source ~/.bashrc
```

## If You See: GEMINI_STATUS=missing

Install Gemini CLI:
```bash
npm install -g @google/gemini-cli
```

Then configure authentication:
```bash
# Option 1: OAuth (recommended)
gemini  # Opens browser for OAuth

# Option 2: API Key
export GEMINI_API_KEY="AIza..."
# Get key from: https://aistudio.google.com/app/apikey
```

To make the API key permanent, add it to your shell profile:
```bash
# For zsh (macOS default)
echo 'export GEMINI_API_KEY="AIza..."' >> ~/.zshrc
source ~/.zshrc

# For bash
echo 'export GEMINI_API_KEY="AIza..."' >> ~/.bashrc
source ~/.bashrc
```

## If You See: CODEX_AUTH=none or GEMINI_AUTH=none

The CLI is installed but not authenticated. Configure authentication:

**For Codex:**
```bash
# Option 1: OAuth
codex login

# Option 2: API Key
export OPENAI_API_KEY="sk-..."
```

**For Gemini:**
```bash
# Option 1: OAuth
gemini

# Option 2: API Key
export GEMINI_API_KEY="AIza..."
```

## Verify Setup

After installing and configuring, verify with:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh detect-providers
```

You should see at least one provider with status:
- ✓ Codex: Installed and authenticated (oauth or api-key)
- ✓ Gemini: Installed and authenticated (oauth or api-key)

### Quick Auth Check (Claude Code v2.1.41+)

If you have Claude Code v2.1.41+, you can also verify Claude's own auth status:
```bash
claude auth status
```

This confirms your Claude session is active and authenticated. Octopus uses this for reliable provider detection when available.

## Ready to Use

Once at least ONE provider is configured, you're ready! Claude Octopus automatically activates when you need multi-AI collaboration.

### Just Talk Naturally

You don't need to run commands - just describe what you want in plain English:

**Research & Exploration:**
> "Research OAuth authentication patterns and summarize the best approaches"
> "Explore different database architectures for a multi-tenant SaaS application"
> "Investigate the trade-offs between REST and GraphQL for our API"

**Implementation & Development:**
> "Build a user authentication system with JWT tokens"
> "Implement a rate limiting middleware for Express"
> "Create a responsive navigation component in React"

**Code Review & Quality:**
> "Review this authentication code for security vulnerabilities"
> "Check this API implementation for performance issues"
> "Validate that this component follows accessibility best practices"

**Adversarial Testing:**
> "Use adversarial review to critique my password reset implementation"
> "Have two models debate the best approach for session management"
> "Red team this login form to find security weaknesses"

**Full Workflows:**
> "Research, design, and implement a complete user dashboard feature"
> "Build a notification system from research to delivery"

Claude coordinates multiple AI models behind the scenes and provides comprehensive, validated results.

## Choosing Your Work Mode

Claude Octopus has two work modes optimized for different tasks. Both use the same AI providers (Codex + Gemini) but with different personas:

### Dev Work Mode 🔧 (Default)
**Best for:** Building features, debugging code, implementing APIs

Switch to Dev mode:
```
/octo:dev
```

### Knowledge Work Mode 🎓
**Best for:** User research, strategy analysis, literature reviews

Switch to Knowledge mode:
```
/octo:km on
```

**For Knowledge Work, we recommend installing document-skills:**
```
/plugin install document-skills@anthropic-agent-skills
```

This adds support for PDF analysis, DOCX/PPTX/XLSX generation, and professional document export.

**Note:** The mode you choose during setup will be remembered across sessions. You can switch modes anytime using `/octo:dev` or `/octo:km on`

---

## Do I Need Both Providers?

No! You only need ONE provider (Codex or Gemini) to use Claude Octopus. Both providers give you access to powerful workflows:

- **Codex (OpenAI):** Best for code generation, refactoring, complex logic
- **Gemini (Google):** Best for analysis, long-context understanding, multi-modal tasks

Having both providers enables multi-AI workflows where different models review each other's work, but a single provider works great for most tasks.

## Troubleshooting

### "npm: command not found"

You need Node.js and npm installed. Install from https://nodejs.org/

### "Permission denied" when installing CLIs

Use `sudo npm install -g` or configure npm to use a user directory:
```bash
mkdir ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.zshrc
source ~/.zshrc
```

### "codex/gemini: command not found" after installation

The CLI may not be in your PATH. Try:
```bash
# Reload your shell profile
source ~/.zshrc  # or source ~/.bashrc

# Or restart your terminal
```

### API key not persisting after terminal restart

Add the export statement to your shell profile (~/.zshrc or ~/.bashrc) so it loads automatically.

### Can't update or uninstall the plugin

If you see "not installed in user scope", the plugin was installed at project scope. Try:

```
/plugin uninstall claude-octopus@nyldn-plugins --scope project
```

Then reinstall:
```
/plugin marketplace add https://github.com/nyldn/claude-octopus.git
/plugin install claude-octopus@nyldn-plugins
```

To check your install scope, run `/octo:status` or ask Claude to run `orchestrate.sh doctor`.

## Getting Help

If you encounter issues:
1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh preflight` for a detailed system check
2. Check the logs in `~/.claude-octopus/logs/`
3. Report issues at: https://github.com/nyldn/claude-octopus/issues
