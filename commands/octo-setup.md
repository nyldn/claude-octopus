---
description: "Interactive setup wizard — install providers, configure auth, RTK, token optimization"
---

# Claude Octopus Setup

**Your first output line MUST be:** `🐙 Octopus Setup`

**CRITICAL: This command MUST always run its interactive flow when invoked.** Never silently dismiss the user. Never say "you're already set up" without showing the dashboard and asking what they want to do. Even if everything is configured, the user invoked this command for a reason — show them their status and offer choices.

## STEP 1: Detect Current State

Run a SINGLE comprehensive check:

```bash
echo "=== Provider Detection ==="
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo installed || echo missing)"
printf "codex_auth:%s\n" "$(codex --version >/dev/null 2>&1 && echo ok || echo none)"
printf "gemini:%s\n" "$(command -v gemini >/dev/null 2>&1 && echo installed || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo configured || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo installed || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo installed || echo missing)"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo running || command -v ollama >/dev/null 2>&1 && echo installed || echo missing)"
printf "opencode:%s\n" "$(command -v opencode >/dev/null 2>&1 && echo installed || echo missing)"
echo "=== Token Optimization ==="
printf "rtk:%s\n" "$(command -v rtk >/dev/null 2>&1 && echo "installed $(rtk --version 2>&1 | head -1)" || echo missing)"
printf "rtk_hook:%s\n" "$(grep -q 'rtk' "${HOME}/.claude/settings.json" 2>/dev/null && echo active || echo missing)"
echo "=== System ==="
printf "node:%s\n" "$(node --version 2>/dev/null || echo missing)"
printf "jq:%s\n" "$(command -v jq >/dev/null 2>&1 && echo installed || echo missing)"
printf "os:%s\n" "$(uname -s)"
```

## STEP 2: Display Status Dashboard

Always show this dashboard — never skip it:

```
🐙 Octopus Setup
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Providers:
  🔵 Claude:        Available ✓
  🔴 Codex CLI:     [Installed ✓ / Missing ✗]
  🟡 Gemini CLI:    [Installed ✓ / Missing ✗]
  🟣 Perplexity:    [Configured ✓ / Not set ✗]
  🟢 Copilot CLI:   [Installed ✓ / Not installed]
  🟠 Qwen CLI:      [Installed ✓ / Not installed]
  🟤 OpenCode:      [Installed ✓ / Not installed]
  ⚫ Ollama:        [Running ✓ / Installed / Not installed]

Token Optimization:
  RTK:              [Installed + Hook active ✓ / Installed ✓ / Missing ✗]
```

## STEP 3: Interactive Menu (ALWAYS show this)

**Always present this menu, whether it's a first run or a returning user:**

```
AskUserQuestion({
  questions: [{
    question: "What would you like to do?",
    header: "Setup",
    multiSelect: false,
    options: [
      {label: "Add or configure a provider", description: "Install Codex, Gemini, Perplexity, Copilot, Qwen, or OpenCode"},
      {label: "Configure models", description: "Set which models are used for each workflow phase → launches /octo:model-config"},
      {label: "Set up token optimization (RTK)", description: "Install RTK for 60-90% token savings on bash output"},
      {label: "Change work mode", description: "Switch between Dev mode and Knowledge Work mode"},
      {label: "Fine-tune preferences", description: "Banner verbosity, telemetry, cost mode"},
      {label: "Troubleshoot an issue", description: "Diagnose a problem → launches /octo:doctor"}
    ]
  }]
})
```

Then route to the appropriate section below.

**If providers are NOT yet configured or this is a first run**, also proceed with the full setup flow below after showing the menu.

---

## Dependency Check

First, check all software dependencies (CLIs, statusline, recommended plugins):

```bash
bash ${HOME}/.claude-octopus/plugin/scripts/install-deps.sh check
```

If dependencies are missing, install them:

```bash
bash ${HOME}/.claude-octopus/plugin/scripts/install-deps.sh install
```

**Note:** Plugin installs (claude-mem, document-skills) can't be auto-installed via script. The install command above will print `/plugin install` commands — copy and paste them to install.

## Provider Detection

Running provider detection...

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh detect-providers
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

## Optional: Add Perplexity for Web Search

Perplexity adds live web search to research workflows. When configured, discover/probe phases automatically include a web-grounded research agent with source citations.

```bash
export PERPLEXITY_API_KEY="pplx-..."
# Get key from: https://www.perplexity.ai/settings/api
```

To make the API key permanent, add it to your shell profile:
```bash
# For zsh (macOS default)
echo 'export PERPLEXITY_API_KEY="pplx-..."' >> ~/.zshrc
source ~/.zshrc

# For bash
echo 'export PERPLEXITY_API_KEY="pplx-..."' >> ~/.bashrc
source ~/.bashrc
```

**Note:** Perplexity is fully optional. All workflows work without it. It simply adds an extra web search perspective (~$0.01-0.05/query).

## Optional: Add GitHub Copilot CLI for Zero-Cost Research

If you have a GitHub Copilot subscription (Pro, Pro+, Business, or Enterprise), the Copilot CLI adds another research perspective at zero additional API cost — prompts count against your existing subscription quota.

**Install:**
```bash
brew install copilot-cli
# Or: npm install -g @github/copilot
```

**Authenticate:**
```bash
# Option 1: Interactive login (recommended)
copilot login

# Option 2: Fine-grained PAT for automation
# Create at: https://github.com/settings/personal-access-tokens/new
# Enable "Copilot Requests" permission
export COPILOT_GITHUB_TOKEN="github_pat_..."
```

**Note:** Copilot CLI also reuses `gh` CLI authentication automatically. If you already use `gh auth login`, Copilot may work with no additional setup.

**Note:** Copilot is fully optional. Classic PATs (`ghp_*`) are NOT supported — use fine-grained PATs (`github_pat_*`) or OAuth login.

## Optional: Add Qwen CLI for Free-Tier Research

Qwen CLI (fork of Gemini CLI) offers 1,000-2,000 free requests per day via Qwen OAuth. Excellent for research and code review at zero cost.

**Install:**
```bash
npm install -g @qwen-code/qwen-code
```

**Authenticate:**
```bash
# Interactive OAuth (recommended — free tier, no API key needed)
qwen
# Follow the browser-based OAuth flow
```

**Note:** Qwen is fully optional. It uses the same dispatch pattern as Gemini CLI.

## New Provider Detection

After running provider detection, if you detect new providers (Copilot, Qwen, Ollama) that are installed but NOT yet used in workflows, **proactively inform the user**:

```
💡 New providers detected! You have extra tentacles available:
  🟢 Copilot CLI — zero-cost research (using your GitHub subscription)
  🟤 Qwen CLI — free-tier research (1,000-2,000 requests/day)
  ⚫ Ollama — local LLM (fully offline, zero cost)

These will automatically join your workflows. No configuration needed —
Claude Octopus detects and uses them when running /octo:research,
/octo:review, /octo:debate, and other multi-provider commands.
```

**Only show this if the user previously had ONLY Codex/Gemini and new providers are now detected.** Don't show it if they've already seen it.

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
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh detect-providers
```

You should see at least one provider with status:
- ✓ Codex: Installed and authenticated (oauth or api-key)
- ✓ Gemini: Installed and authenticated (oauth or api-key)
- ✓ Perplexity: Configured (api-key) — optional, adds web search
- ✓ Copilot: Installed and authenticated — optional, zero-cost research

### Quick Auth Check (Claude Code v2.1.41+)

If you have Claude Code v2.1.41+, you can also verify Claude's own auth status:
```bash
claude auth status
```

This confirms your Claude session is active and authenticated. Octopus uses this for reliable provider detection when available.

## Fine-tune Your Experience (Optional)

**After confirming at least one provider is set up**, offer the user a chance to configure plugin preferences. This section uses interactive questions for settings the plugin can write directly — skip this section for users who declined or are in a hurry.

Ask only if the user appears to be in a setup flow (not troubleshooting):

```
AskUserQuestion({
  questions: [{
    question: "Want to fine-tune your Claude Octopus experience? (takes ~30 seconds)",
    header: "Fine-tune",
    multiSelect: false,
    options: [
      {label: "Yes, let's configure it", description: "Set work mode, verbosity, and telemetry preferences"},
      {label: "Skip for now", description: "Use defaults — you can run /octo:setup anytime to change these"}
    ]
  }]
})
```

**If yes**, run this preferences questionnaire:

```
AskUserQuestion({
  questions: [
    {
      question: "What's your primary use case?",
      header: "Work Mode",
      multiSelect: false,
      options: [
        {label: "Software development", description: "Dev mode — optimized for building features, debugging, code review"},
        {label: "Research & analysis", description: "Knowledge Work mode — optimized for research, reports, strategy work"}
      ]
    },
    {
      question: "How much detail do you want in workflow banners?",
      header: "Verbosity",
      multiSelect: false,
      options: [
        {label: "Full banners (default)", description: "Show which providers are running and their roles — good for new users"},
        {label: "Compact banners", description: "Single-line indicators — better for experienced users who know the system"}
      ]
    },
    {
      question: "Telemetry — help improve Claude Octopus?",
      header: "Telemetry",
      multiSelect: false,
      options: [
        {label: "Yes, share anonymous usage data", description: "Helps prioritize features and catch bugs (default)"},
        {label: "No, opt out", description: "Set OCTOPUS_TELEMETRY_OPT_OUT=1 — no data sent"}
      ]
    }
  ]
})
```

**After receiving answers, apply settings:**

- Work mode "Software development" → run `/octo:dev` or note that Dev mode is the default
- Work mode "Research & analysis" → run `/octo:km on`
- Compact banners selected → write `OCTOPUS_COMPACT_BANNERS=true` to shell profile and inform user to restart terminal (or add to `~/.zshrc`)
- Telemetry opt-out selected → write `OCTOPUS_TELEMETRY_OPT_OUT=1` to shell profile and inform user

**Note:** For shell profile writes, show the exact command for the user to run — do not run it automatically:
```bash
# Example: add to ~/.zshrc
echo 'export OCTOPUS_COMPACT_BANNERS=true' >> ~/.zshrc
```

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
- **Perplexity (optional):** Adds live web search with citations to research workflows
- **Copilot (optional):** Zero-cost research via GitHub subscription — uses Claude/GPT/Gemini models
- **Qwen (optional):** Free-tier research — 1,000-2,000 requests/day via Qwen OAuth
- **Ollama (optional):** Zero-cost local LLM — fully offline, privacy-sensitive workflows

Having both providers enables multi-AI workflows where different models review each other's work, but a single provider works great for most tasks. Perplexity is a bonus — it grounds research in live web data.

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

The plugin update UI is currently broken — "Failed to update: Plugin 'octo' not found" is a known issue. Manual cleanup is required:

**Step 1:** Edit `~/.claude/settings.json` → remove `"octo@nyldn-plugins"` from the `enabledPlugins` array.

**Step 2:** Remove plugin files:
```bash
rm -rf ~/.claude/plugins/octo@nyldn-plugins
rm -rf ~/.claude/installed-plugins/octo@nyldn-plugins
```

**Step 3:** Reinstall:
```
/plugin marketplace add https://github.com/nyldn/claude-octopus.git
/plugin install octo@nyldn-plugins
```

## Getting Help

If you encounter issues:
1. Run `${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh preflight` for a detailed system check
2. Check the logs in `~/.claude-octopus/logs/`
3. Report issues at: https://github.com/nyldn/claude-octopus/issues
