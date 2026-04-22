---
command: model-config
description: Configure AI provider models for Claude Octopus workflows
version: 4.0.1
category: configuration
tags: [config, models, providers, codex, gemini, spark, routing, trace, interactive]
created: 2025-01-21
updated: 2026-04-21
---

# Model Configuration

**Your first output line MUST be:** `🐙 Octopus Model Config`

## STEP 0: Emit Banner (MANDATORY — run before AskUserQuestion or any other step)

```bash
echo "🐙 Octopus Model Config"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "provider | model | config | routing | cost"
```

Run this unconditionally — even when arguments are provided or when going to interactive wizard. The explicit bash block ensures the banner emits even when the command routes straight to `AskUserQuestion` (which historically skipped the inline-prose instruction and broke E2E pattern matching — see #301).

Interactive model configuration wizard. Detects installed providers, shows current settings, and guides users through configuration with AskUserQuestion.

## STEP 1: Detect & Display

Run a SINGLE comprehensive detection command:

```bash
echo "=== Provider Detection ==="
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo installed || echo missing)"
printf "gemini:%s\n" "$(command -v gemini >/dev/null 2>&1 && echo installed || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo configured || echo missing)"
printf "openrouter:%s\n" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo configured || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo installed || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo installed || echo missing)"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo running || command -v ollama >/dev/null 2>&1 && echo installed || echo missing)"
printf "opencode:%s\n" "$(command -v opencode >/dev/null 2>&1 && echo installed || echo missing)"
echo "=== Config ==="
if [[ -f ~/.claude-octopus/config/providers.json ]]; then
  cat ~/.claude-octopus/config/providers.json
else
  echo "NO_CONFIG"
fi
echo "=== Env ==="
env | grep -E '^OCTOPUS_|^CLAUDE_MODEL=' 2>/dev/null || echo "none"
```

Then display a compact dashboard:

```
🐙 Octopus Model Config
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Providers                          Status
  🔵 Claude (Sonnet/Opus)          Built-in ✓
  🔴 Codex (GPT-5.4)              [Installed ✓ / Missing ✗]  → current: <model>
  🟡 Gemini                        [Installed ✓ / Missing ✗]  → current: <model>
  🟣 Perplexity                    [Configured ✓ / Not set]
  🟠 OpenRouter                    [Configured ✓ / Not set]
  ...other installed providers...

Phase Routing
  discover → <model>    define  → <model>
  develop  → <model>    deliver → <model>
  review   → <model>    security → <model>
  debate   → <model>    research → <model>

Cost Mode: <standard/budget/premium>
```

Only show providers that are installed or configured. Don't show rows for providers the user doesn't have.

## STEP 2: Route by Arguments

**If arguments were provided** (e.g., `/octo:model-config codex gpt-5.4`), skip the interactive flow and execute the CLI-style command directly per the EXECUTION CONTRACT at the bottom.

**If no arguments**, proceed to the interactive wizard:

## STEP 3: Interactive Menu

```
AskUserQuestion({
  questions: [{
    question: "What would you like to configure?",
    header: "Model Config",
    multiSelect: false,
    options: [
      {label: "Provider defaults", description: "Set default models for Codex, Gemini, OpenRouter, etc."},
      {label: "Phase routing", description: "Choose which model handles each workflow phase (discover, develop, review, etc.)"},
      {label: "Debate & multi-LLM", description: "Configure which providers participate in debates, parallel execution, and reviews"},
      {label: "Cost mode", description: "Switch between budget, standard, and premium model tiers"},
      {label: "Reset to defaults", description: "Reset all or specific provider configuration"}
    ]
  }]
})
```

### Route: Provider Defaults

Build options dynamically from detected providers. Only show providers that are installed/configured:

```
AskUserQuestion({
  questions: [{
    question: "Which provider do you want to configure?",
    header: "Provider",
    multiSelect: false,
    options: [
      // Always show:
      {label: "🔵 Claude", description: "Current: claude-sonnet-4.6 / claude-opus-4.7 (legacy 4.6 available) — built-in, no config needed"},
      // Only if codex installed:
      {label: "🔴 Codex (OpenAI)", description: "Current: <current_model> — handles implementation, reasoning"},
      // Only if gemini installed:
      {label: "🟡 Gemini (Google)", description: "Current: <current_model> — handles research, creative tasks"},
      // Only if perplexity configured:
      {label: "🟣 Perplexity", description: "Current: <current_model> — handles web search, real-time data"},
      // Only if openrouter configured:
      {label: "🟠 OpenRouter", description: "Current: <current_model> — routes to GLM, Kimi, DeepSeek"},
      // Only if opencode installed:
      {label: "🟤 OpenCode", description: "Current: <current_model> — multi-provider router"}
    ]
  }]
})
```

After provider selection, show model choices appropriate for that provider:

**Codex example:**
```
AskUserQuestion({
  questions: [{
    question: "Which Codex model should be the default?",
    header: "Codex Model",
    multiSelect: false,
    options: [
      {label: "gpt-5.4", description: "Flagship — 400K context, $2.50/$15 MTok, best for complex tasks"},
      {label: "gpt-5.4 (fast/spark)", description: "1000+ tok/s — 128K context, Pro-only, best for reviews & iteration"},
      {label: "gpt-5.4-mini", description: "Budget — 400K context, $0.25/$2 MTok, great for simple tasks"},
      {label: "o3", description: "Reasoning — 200K context, $2/$8 MTok, deep analysis & trade-offs"},
      {label: "Custom", description: "Enter a custom model name"}
    ]
  }]
})
```

**Gemini example:**
```
AskUserQuestion({
  questions: [{
    question: "Which Gemini model should be the default?",
    header: "Gemini Model",
    multiSelect: false,
    options: [
      {label: "gemini-3.1-pro-preview", description: "Premium — $2.50/$10 MTok, best research quality"},
      {label: "gemini-3-flash-preview", description: "Fast — $0.25/$1 MTok, good for quick tasks"},
      {label: "Custom", description: "Enter a custom model name"}
    ]
  }]
})
```

**OpenRouter example:**
```
AskUserQuestion({
  questions: [{
    question: "Which OpenRouter models do you want available?",
    header: "OpenRouter Models",
    multiSelect: true,
    options: [
      {label: "z-ai/glm-5", description: "GLM-5 — 203K context, $0.80/$2.56 MTok, code review specialist"},
      {label: "moonshotai/kimi-k2.5", description: "Kimi K2.5 — 262K context, $0.45/$2.25 MTok, research & multimodal"},
      {label: "deepseek/deepseek-r1-0528", description: "DeepSeek R1 — 164K context, $0.70/$2.50 MTok, deep reasoning"},
      {label: "Custom", description: "Enter a custom model ID"}
    ]
  }]
})
```

After selection, apply the change:
```bash
/path/to/orchestrate.sh set-model <provider> <model>
```

Then confirm: `✓ Set <provider> default → <model>`

Offer to configure another provider or return to main menu.

### Route: Phase Routing

Show current routing as a visual table, then ask which phase to change:

```
AskUserQuestion({
  questions: [{
    question: "Which phase do you want to re-route?",
    header: "Phase Routing",
    multiSelect: false,
    options: [
      {label: "🔍 Discover", description: "Current: <model> — research & exploration"},
      {label: "🎯 Define", description: "Current: <model> — requirements & scope"},
      {label: "🛠️ Develop", description: "Current: <model> — implementation & building"},
      {label: "✅ Deliver", description: "Current: <model> — review & validation"},
      {label: "🔒 Security", description: "Current: <model> — security audits (default: o3 reasoning)"},
      {label: "💬 Debate", description: "Current: <model> — multi-AI deliberation"},
      {label: "📖 Review", description: "Current: <model> — code review"},
      {label: "🔬 Research", description: "Current: <model> — deep research (default: gemini)"},
      {label: "⚡ Quick", description: "Current: <model> — fast ad-hoc tasks"}
    ]
  }]
})
```

After phase selection, show model options from ALL available providers (not just one):

```
AskUserQuestion({
  questions: [{
    question: "Which model should handle the <phase> phase?",
    header: "<Phase> Model",
    multiSelect: false,
    options: [
      // Show cross-provider options
      {label: "codex:default (gpt-5.4)", description: "Deep reasoning, complex tasks"},
      {label: "codex:spark (gpt-5.4 fast)", description: "15x faster, good for iteration"},
      {label: "codex:reasoning (o3)", description: "Deep analysis with chain-of-thought"},
      {label: "gemini:default", description: "Broad research, creative approaches"},
      {label: "gemini:flash", description: "Fast, low-cost"},
      // Only if openrouter configured:
      {label: "openrouter:glm5 (z-ai/glm-5)", description: "Code review specialist"},
      {label: "openrouter:kimi (kimi-k2.5)", description: "Research & multimodal"},
      {label: "Custom", description: "Enter a custom model or cross-provider reference"}
    ]
  }]
})
```

Apply:
```bash
jq --arg phase "<phase>" --arg model "<model>" \
  '.routing.phases[$phase] = $model' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
```

Confirm and offer to route another phase.

### Route: Debate & Multi-LLM

This configures which providers participate in multi-LLM features:

```
AskUserQuestion({
  questions: [{
    question: "Which multi-LLM feature do you want to configure?",
    header: "Multi-LLM Config",
    multiSelect: false,
    options: [
      {label: "Debate participants", description: "Choose which 3-4 providers argue in /octo:debate"},
      {label: "Parallel execution providers", description: "Choose which providers run in /octo:parallel and /octo:multi"},
      {label: "Review providers", description: "Choose which providers contribute to /octo:review and /octo:staged-review"},
      {label: "Consensus threshold", description: "Set agreement % needed to ship (default: 75%)"}
    ]
  }]
})
```

**Debate participants:**
```
AskUserQuestion({
  questions: [{
    question: "Which providers should participate in debates? (Select 2-4)",
    header: "Debate Participants",
    multiSelect: true,
    options: [
      // Only show installed/configured providers
      {label: "🔵 Claude (Sonnet 4.6 / Opus 4.7)", description: "Moderator — instruction-following, synthesis"},
      {label: "🔴 Codex (GPT-5.4)", description: "Technical depth — architecture, implementation"},
      {label: "🟡 Gemini", description: "Ecosystem perspective — alternatives, trends"},
      {label: "🟠 OpenRouter: GLM-5", description: "Code review specialist — quality focus"},
      {label: "🟠 OpenRouter: Kimi K2.5", description: "Research perspective — broad knowledge"},
      {label: "🟤 OpenCode", description: "Multi-model router — varied perspectives"}
    ]
  }]
})
```

Save debate config to providers.json under `.routing.features.debate`:
```bash
jq --argjson providers '["claude","codex","gemini"]' \
  '.routing.features.debate = $providers' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
```

**Parallel execution:** Same pattern — select which providers to include in `/octo:parallel` and `/octo:multi` dispatches.

**Review providers:** Select which providers contribute analysis to `/octo:review`.

**Consensus threshold:**
```
AskUserQuestion({
  questions: [{
    question: "What agreement threshold should be required before shipping?",
    header: "Consensus Threshold",
    multiSelect: false,
    options: [
      {label: "50% — Majority", description: "At least half of providers must agree"},
      {label: "75% — Strong consensus (default)", description: "Three-quarters agreement required"},
      {label: "100% — Unanimous", description: "All providers must agree (strict)"},
      {label: "Custom", description: "Enter a custom percentage"}
    ]
  }]
})
```

### Route: Cost Mode

```
AskUserQuestion({
  questions: [{
    question: "Which cost mode do you want?",
    header: "Cost Mode",
    multiSelect: false,
    options: [
      {label: "💰 Budget", description: "Use cheapest models: gpt-5.4-mini, gemini-flash — best for prototyping"},
      {label: "⚖️ Standard (current default)", description: "Balanced: use your configured defaults"},
      {label: "🚀 Premium", description: "Use best available models for every task — higher cost, best quality"}
    ]
  }]
})
```

Apply by showing the user the export command:
```
To activate: export OCTOPUS_COST_MODE=<mode>
To make permanent: add to ~/.zshrc or ~/.bashrc
```

Or offer to set it in the config file.

### Route: Reset

```
AskUserQuestion({
  questions: [{
    question: "What do you want to reset?",
    header: "Reset",
    multiSelect: false,
    options: [
      {label: "Reset all", description: "Restore all providers and routing to defaults"},
      {label: "Reset Codex only", description: "Reset Codex to gpt-5.4 default"},
      {label: "Reset Gemini only", description: "Reset Gemini to gemini-3.1-pro-preview default"},
      {label: "Reset phase routing only", description: "Restore default phase-to-model mapping"},
      {label: "Cancel", description: "Go back without changing anything"}
    ]
  }]
})
```

## STEP 4: Loop or Exit

After each configuration change, offer:

```
AskUserQuestion({
  questions: [{
    question: "Configuration saved. What next?",
    header: "Next",
    multiSelect: false,
    options: [
      {label: "Configure something else", description: "Return to the main menu"},
      {label: "Show final config", description: "Display the complete updated configuration"},
      {label: "Done", description: "Exit model configuration"}
    ]
  }]
})
```

---

## CLI-STYLE EXECUTION CONTRACT (for direct arguments)

When invoked WITH arguments (e.g., `/octo:model-config codex gpt-5.4`), skip the interactive flow and execute directly:

1. **Parse arguments** to determine action:
   - `show phases` → Display formatted phase routing table
   - `<provider> <model>` → Set model (persistent)
   - `<provider>.<capability> <model>` → Set capability-specific model
   - `<provider> <model> --session` → Set model (session only)
   - `phase <phase> <model>` → Set phase-specific model routing
   - `reset <provider|all>` → Reset to defaults

2. **Set Model** (`<provider> <model>` or with `--session`):
   ```bash
   # Read and validate
   CONFIG_FILE="${HOME}/.claude-octopus/config/providers.json"
   # Use jq to set the model
   jq --arg p "<provider>" --arg m "<model>" '.providers[$p].default = $m' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
   ```

   **Dot syntax** (`<provider>.<capability> <model>`):
   ```bash
   jq --arg p "<provider>" --arg c "<capability>" --arg m "<model>" \
     '.providers[$p][$c] = $m' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
   ```

3. **Set Phase Routing** (`phase <phase> <model>`):
   Validate phase name against: `discover`, `define`, `develop`, `deliver`, `quick`, `debate`, `review`, `security`, `research`.
   ```bash
   jq --arg phase "<phase>" --arg model "<model>" '.routing.phases[$phase] = $model' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp.$$" && mv "${CONFIG_FILE}.tmp.$$" "$CONFIG_FILE"
   ```

4. **Reset**: Use default values from the ensure_config block in `scripts/helpers/octo-model-config.sh`.

5. Always show confirmation and the updated value after any change.

### Validation Gates

- Provider names validated against whitelist: `codex gemini claude perplexity openrouter opencode copilot ollama qwen`
- Phase names validated against known list
- Model names checked for injection safety (alphanumeric, hyphens, dots, slashes only)
- Config file operations use atomic write (tmp + mv)
- Always use `jq --arg` (never string interpolation)

### Prohibited Actions

- Assuming configuration without reading the file
- Skipping validation of provider/phase names
- Using string interpolation in jq expressions
- Showing providers that aren't installed (in interactive mode)
