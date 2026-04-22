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

## STEP 2a: v9.29 Migration Prompt (one-time, existing users only)

**Before showing the main menu, check if this is an existing user upgrading from ≤9.28.**

Run this bash check — skip migration if state is fresh (first-run) or already ≥9.29:

```bash
STATE_FILE="${HOME}/.claude-octopus/state.json"
if [[ -f "$STATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
  LAST_VERSION=$(jq -r '.last_version // "0.0.0"' "$STATE_FILE" 2>/dev/null)
  MODEL_DEFAULTS_V2=$(jq -r '.model_defaults_v2 // "unset"' "$STATE_FILE" 2>/dev/null)
  # Version compare: show migration only if last_version is between 1.x and 9.28
  if [[ "$LAST_VERSION" != "0.0.0" ]] && [[ "$MODEL_DEFAULTS_V2" == "unset" ]]; then
    printf "MIGRATION_PROMPT_NEEDED\nlast_version=%s\n" "$LAST_VERSION"
  fi
fi
```

**If `MIGRATION_PROMPT_NEEDED` appears**, show this AskUserQuestion BEFORE the main menu:

```javascript
AskUserQuestion({
  questions: [{
    question: "v9.29.0 refreshed model defaults based on April 2026 benchmarks. Planning + security reviews now use Claude Opus 4.7 (best on SWE-bench Pro + LMArena). Code review + implementation stay on GPT-5.4 (best on Terminal-Bench + edge cases). Opus is ~2x the cost of GPT-5.4 per MTok — this will increase planning-phase cost. How would you like to proceed?",
    header: "v9.29 Models",
    multiSelect: false,
    options: [
      {label: "Accept new defaults (Recommended)", description: "Use Opus 4.7 for planning/strategy/security, GPT-5.4 for review/implementation"},
      {label: "Keep v9.28 defaults (GPT-5.4 everywhere)", description: "Sets OCTOPUS_LEGACY_ROLES=1 in your shell profile"},
      {label: "Open /octo:model-config", description: "Customize per-role routing directly"},
      {label: "See the diff", description: "Show before/after routing table, then ask again"}
    ]
  }]
})
```

**Route based on selection:**

- **Accept new defaults** → Write `model_defaults_v2=accepted` and `last_version=9.29.0` to `~/.claude-octopus/state.json`. Continue to STEP 3.
- **Keep v9.28 defaults** → Append `export OCTOPUS_LEGACY_ROLES=1` to the user's shell profile (detect `~/.zshrc` vs `~/.bashrc` via `$SHELL`), notify them to reload the shell, then write `model_defaults_v2=legacy` + `last_version=9.29.0`. Continue to STEP 3.
- **Open /octo:model-config** → Invoke that command. Do NOT write state — defer to whatever the user picks there.
- **See the diff** → Print the routing table below, then re-ask the question.

**Diff table to show:**

```
Role                 v9.28 (old)                v9.29 (new)
architect            codex:gpt-5.4              claude-opus:claude-opus-4.7   (was GPT-5.4)
reviewer             codex-review:gpt-5.4       codex-review:gpt-5.4          (alias → code-reviewer)
code-reviewer        —                          codex-review:gpt-5.4          (NEW, same as reviewer)
security-reviewer    —                          claude-opus:claude-opus-4.7   (NEW, split from reviewer)
implementer          codex:gpt-5.4              codex:gpt-5.4                 (unchanged)
implementer-heavy    —                          claude-opus:claude-opus-4.7   (NEW, opt-in via role name)
synthesizer          claude:claude-sonnet-4.6   claude:claude-sonnet-4.6      (unchanged)
strategist           claude-opus:claude-opus-4.6 claude-opus:claude-opus-4.7  (already on 4.7 via resolver)
researcher           gemini:gemini-3.1-pro      gemini:gemini-3.1-pro         (unchanged)

Cost impact (per MTok): Opus 4.7 $5/$25 vs GPT-5.4 $2.50/$15 — roughly 2x for planning phases.
Graceful fallback: roles requiring Opus silently downshift to GPT-5.4 if no Anthropic auth.
Opt-out anytime: OCTOPUS_LEGACY_ROLES=1
```

**WHY:** Existing users should not silently inherit the new defaults without a chance to opt out. The one-time prompt gates the behavior change on explicit consent, surfaces cost impact, and writes state so the prompt doesn't recur. Skip entirely for fresh installs (they have no prior mental model to migrate).

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

## STEP 4b: Prompt Cache Optimization (Claude Code v2.1.108+)

Skip this step when `SUPPORTS_PROMPT_CACHE_1H=false`. Otherwise:

```javascript
AskUserQuestion({
  questions: [{
    question: "Enable 1-hour prompt cache TTL? (Saves tokens on long /octo:embrace and /octo:loop sessions — the default is 5 minutes.)",
    header: "Prompt Cache",
    multiSelect: false,
    options: [
      {label: "Yes, enable 1-hour cache", description: "Adds ENABLE_PROMPT_CACHING_1H=1 to your shell profile — applies to Claude API/Bedrock/Vertex/Foundry."},
      {label: "No, keep 5-minute default", description: "Simpler mental model; lower cost ceiling if you only run short sessions."}
    ]
  }]
})
```

If "Yes", append `export ENABLE_PROMPT_CACHING_1H=1` to `~/.bashrc` (or `~/.zshrc` per `$SHELL`), only if not already present. Note to the user: this only affects Claude-to-Claude round-trips inside Claude Code. External CLI subshells (Codex, Gemini, Perplexity) are unaffected — their providers manage caching independently.

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
