---
command: setup
description: Interactive setup wizard — install providers, configure auth, RTK, token optimization
aliases:
  - sys-setup
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Claude Octopus Setup

**Your first output line MUST be:** `🐙 Octopus Setup`

Interactive setup wizard. Detects what's installed, offers to install what's missing, configures auth, and optimizes token usage.

**This command auto-runs on first install** (via SessionStart hook). It also runs when users invoke `/octo:setup` manually.

**CRITICAL: This command MUST always run its interactive flow when invoked.** Never silently dismiss the user. Never say "you're already set up" without showing the dashboard and offering choices via AskUserQuestion. Even if everything is configured, the user invoked this command for a reason — show them their status and ask what they want to do.

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
printf "octo_compress:%s\n" "$(command -v octo-compress >/dev/null 2>&1 && echo available || echo missing)"
echo "=== System ==="
printf "node:%s\n" "$(node --version 2>/dev/null || echo missing)"
printf "jq:%s\n" "$(command -v jq >/dev/null 2>&1 && echo installed || echo missing)"
printf "os:%s\n" "$(uname -s)"
```

## STEP 2: Display Status Summary

Show a compact table:

```
🐙 Octopus Setup
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Providers:
  🔴 Codex CLI:     [Installed ✓ / Missing ✗]
  🟡 Gemini CLI:    [Installed ✓ / Missing ✗]
  🟣 Perplexity:    [Configured ✓ / Not set ✗]
  🟢 Copilot CLI:   [Installed ✓ / Not installed]
  🟠 Qwen CLI:      [Installed ✓ / Not installed]
  🟤 OpenCode:      [Installed ✓ / Not installed]
  ��� Ollama:        [Running ✓ / Installed / Not installed]
  🔵 Claude:        Available ✓

Token Optimization:
  RTK:              [Installed + Hook active ✓ / Installed ✓ / Missing ✗]
  octo-compress:    [Available ✓ / Not in PATH]
```

## STEP 3: Interactive Menu (ALWAYS show — even for returning users)

**Always present this menu after the dashboard, regardless of current setup state:**

```javascript
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
      {label: "Troubleshoot an issue", description: "Diagnose a problem → launches /octo:doctor"},
      {label: "Done — everything looks good", description: "Exit setup"}
    ]
  }]
})
```

Route based on selection:
- **Add or configure a provider** → Continue to the provider install flow below
- **Configure models** → Invoke `/octo:model-config` (the interactive model config wizard)
- **Set up RTK** → Jump to the RTK section below
- **Change work mode** → Jump to the Work Mode section (STEP 4)
- **Fine-tune preferences** → Jump to the Fine-tune section (STEP 5)
- **Troubleshoot** → Suggest `/octo:doctor`
- **Done** → Show "Run /octo:setup anytime to change these settings" and exit

## STEP 3a: Provider Install (if selected above, or if core providers are missing on first run)

**If core providers are missing (Codex/Gemini):**

```javascript
AskUserQuestion({
  questions: [{
    question: "Which providers do you want to install?",
    header: "Providers",
    multiSelect: true,
    options: [
      {label: "Codex CLI (Recommended)", description: "npm install -g @openai/codex — OpenAI's coding agent"},
      {label: "Gemini CLI", description: "brew install gemini-cli — Google's research agent"},
      {label: "Skip", description: "Continue with what's already installed"}
    ]
  }]
})
```

Execute installs for each selected option. After install, offer auth:

```javascript
AskUserQuestion({
  questions: [{
    question: "How do you want to authenticate Codex?",
    header: "Codex Auth",
    multiSelect: false,
    options: [
      {label: "OAuth login (Recommended)", description: "codex login — opens browser, no API key needed"},
      {label: "API key", description: "I'll set OPENAI_API_KEY manually"},
      {label: "Skip", description: "I'll configure auth later"}
    ]
  }]
})
```

If user chooses OAuth, tell them to run `! codex login` (the `!` prefix runs it in this session).

**If RTK is missing:**

```javascript
AskUserQuestion({
  questions: [{
    question: "RTK saves 60-90% on bash output tokens. Install it?",
    header: "RTK",
    multiSelect: false,
    options: [
      {label: "Install via brew (Recommended)", description: "brew install rtk — fast, macOS"},
      {label: "Install via cargo", description: "cargo install --git https://github.com/rtk-ai/rtk"},
      {label: "Skip", description: "Continue without RTK"}
    ]
  }]
})
```

After install, auto-configure the hook: `rtk init -g`, then add the PreToolUse hook to settings.json.

**If RTK is installed but hook not active:**

Offer `rtk init -g` directly.

## STEP 4: Work Mode Selection

```javascript
AskUserQuestion({
  questions: [{
    question: "What kind of work will you primarily do?",
    header: "Work Mode",
    multiSelect: false,
    options: [
      {label: "Dev Work (Default)", description: "Software development — building, debugging, reviewing code"},
      {label: "Knowledge Work", description: "Research, analysis, writing, strategy — recommends document-skills plugin"},
      {label: "Both", description: "I'll switch between them"}
    ]
  }]
})
```

If Knowledge Work selected, offer to install document-skills plugin.

## STEP 5: Verify & Summarize

Re-run provider detection to confirm everything works:

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh detect-providers
```

Show final summary:

```
✅ Setup Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Providers: X active (Codex, Gemini, ...)
RTK: [Active / Not installed]
Mode: [Dev / Knowledge / Both]

Quick start:
  Just describe what you need — "research X", "build Y", "review Z"
  Or use /octo:auto for the smart router
  Run /octo:doctor anytime for diagnostics
```

## IMPORTANT: This Replaces Passive Setup

The old setup just printed instructions. This new setup:
- Uses AskUserQuestion for every decision
- Executes installs directly (with user consent via option selection)
- Configures auth interactively
- Sets up RTK + token optimization
- Remembers preferences via auto-memory

Everything `/octo:doctor` can fix, `/octo:setup` should also offer to configure on first run.
