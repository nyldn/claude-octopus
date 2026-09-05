---
command: model-config
disable-model-invocation: true
description: Configure AI provider models for Claude Octopus workflows
version: 4.0.1
category: configuration
tags: [config, models, providers, codex, antigravity, kimi, spark, routing, trace, interactive]
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

**Preflight — Ensure plugin root is resolvable (run via Bash tool):**

```bash
OCTO_ROOT="${HOME}/.claude-octopus/plugin"
if [[ ! -x "$OCTO_ROOT/scripts/orchestrate.sh" ]]; then
  helper="$OCTO_ROOT/scripts/helpers/ensure-plugin-root.sh"
  if [[ ! -x "$helper" ]]; then
    helper="$(find "${HOME}/.claude/plugins/cache" "${HOME}/Library/Application Support/Claude" "${LOCALAPPDATA:-/dev/null}/Claude" "${XDG_DATA_HOME:-${HOME}/.local/share}/Claude" -maxdepth 8 -path "*/nyldn-plugins/octo/*/scripts/helpers/ensure-plugin-root.sh" -print -quit 2>/dev/null)"
  fi
  [[ -x "$helper" ]] && bash "$helper" >/dev/null 2>&1 || true
fi
test -x "$OCTO_ROOT/scripts/orchestrate.sh" && echo "plugin-root:ok" || echo "plugin-root:missing"
```

If the output is `plugin-root:missing`, stop and ask the user to run `/octo:setup`.

Run this unconditionally — even when arguments are provided or when going to interactive wizard. The explicit bash block ensures the banner emits even when the command routes straight to `AskUserQuestion` (which historically skipped the inline-prose instruction and broke E2E pattern matching — see #301).

Interactive model configuration wizard. Detects installed providers, shows current settings, and guides users through configuration with AskUserQuestion.

## STEP 1: Detect & Display

Run a SINGLE comprehensive detection command:

```bash
echo "=== Provider Detection ==="
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo installed || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo configured || echo missing)"
printf "openrouter:%s\n" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo configured || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo installed || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo installed || echo missing)"
printf "kimi:%s\n" "$(command -v kimi >/dev/null 2>&1 && echo installed || echo missing)"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf --connect-timeout 1 --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1 && echo running || command -v ollama >/dev/null 2>&1 && echo installed || echo missing)"
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
  🔴 Codex (GPT-5.6 Sol)          [Installed ✓ / Missing ✗]  → current: <model>
  🧭 Antigravity (`agy`)           [Installed ✓ / Missing ✗]  → current: <model>
  🌙 Kimi Code                     [Installed ✓ / Missing ✗]  → current: <model alias>
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

**If arguments were provided** (e.g., `/octo:model-config codex gpt-5.6-sol`), skip the interactive flow and execute the CLI-style command directly per the EXECUTION CONTRACT at the bottom.

**If no arguments**, proceed to the interactive wizard:

## STEP 3: Interactive Menu

```
AskUserQuestion({
  questions: [{
    question: "What would you like to configure?",
    header: "Model Config",
    multiSelect: false,
    options: [
      {label: "Provider defaults", description: "Set default models for Codex, Antigravity, OpenRouter, etc."},
      {label: "Phase routing", description: "Choose which model handles each workflow phase (discover, develop, review, etc.)"},
      {label: "Role routing overrides", description: "Route specific roles/personas such as researcher, logic-reviewer, or qa-reviewer"},
      {label: "Debate & multi-LLM", description: "Configure which providers participate in debates, parallel execution, and reviews"},
      {label: "Session provider availability", description: "Temporarily enable or disable providers for this Claude Code session"},
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
      {label: "🔵 Claude", description: "Current: claude-sonnet-5 / claude-opus-5 (legacy fallbacks available) — built-in, no config needed"},
      // Only if codex installed:
      {label: "🔴 Codex (OpenAI)", description: "Current: <current_model> — handles implementation, reasoning"},
      // Only if agy installed:
      {label: "🧭 Antigravity (agy)", description: "Current: <current_model> — handles research and external-model review"},
      // Only if perplexity configured:
      {label: "🟣 Perplexity", description: "Current: <current_model> — handles web search, real-time data"},
      // Only if openrouter configured:
      {label: "🟠 OpenRouter", description: "Current: <current_model> — routes to GLM, Kimi, DeepSeek"},
      // Only if opencode installed:
      {label: "🟤 OpenCode", description: "Current: <current_model> — multi-provider router"},
      // Only if kimi installed:
      {label: "🌙 Kimi Code", description: "Current: <current_model> — aliases are declared in KIMI_CODE_HOME/config.toml"}
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
      {label: "gpt-5.6-sol", description: "Frontier default — 1M context, $4/$20 MTok, best for implementation and independent review"},
      {label: "gpt-5.6-terra", description: "Balanced — 1M context, $2/$12 MTok, strong general-purpose Codex seat"},
      {label: "gpt-5.6-luna", description: "Budget — 1M context, $0.20/$1.20 MTok, best for quick checks and prototypes"},
      {label: "o3", description: "Reasoning — 200K context, $2/$8 MTok, deep analysis & trade-offs"},
      {label: "Custom", description: "Enter a custom model name"}
    ]
  }]
})
```

`gpt-6-astra` is intentionally absent from persistent defaults and cost tiers.
For a bounded evaluation after Sol fails a hard acceptance test, use
`OCTOPUS_CODEX_MODEL=gpt-6-astra` for one command or an exact
`codex:gpt-6-astra` seat. Model overrides written by `--session` share the
global provider configuration, so explicit-only frontier models are rejected
there until overrides are truly session-scoped.

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
      {label: "deepseek/deepseek-v4-pro", description: "DeepSeek V4 Pro — 1M context, $0.435/$0.87 MTok, reasoning"},
      {label: "Custom", description: "Enter a custom model ID"}
    ]
  }]
})
```

**Kimi Code example:** enter the exact alias already declared under
`[models.<alias>]` in `$KIMI_CODE_HOME/config.toml` (default
`~/.kimi-code/config.toml`). Run `kimi` and enter `/login` first if the selected
provider has no configured API key or OAuth credential. A legacy keyring-only
session is not usable here; run `kimi` with the same `KIMI_CODE_HOME` and enter
`/login` again to create the current file-backed session.

After selection, apply the change:

```bash
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh set <provider> <model>
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
      {label: "🔬 Research", description: "Current: <model> — deep research (default: agy)"},
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
      {label: "codex:default (gpt-5.6-sol)", description: "Frontier implementation and independent review"},
      {label: "codex:spark (gpt-5.6-luna)", description: "Budget-friendly quick checks and iteration"},
      {label: "codex:reasoning (o3)", description: "Deep analysis with chain-of-thought"},
      {label: "agy:default", description: "Broad research, creative approaches"},
      {label: "agy:flash", description: "Fast Antigravity model tier"},
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
      {label: "🔵 Claude (Sonnet 5 / Opus 5)", description: "Moderator — instruction-following, synthesis"},
      {label: "🔴 Codex (GPT-5.6 Sol)", description: "Independent implementation and edge-case review"},
      {label: "🧭 Antigravity (agy)", description: "Alternate model perspective via Antigravity CLI"},
      {label: "🟠 OpenRouter: GLM-5", description: "Code review specialist — quality focus"},
      {label: "🟠 OpenRouter: Kimi K2.5", description: "Research perspective — broad knowledge"},
      {label: "🟤 OpenCode", description: "Multi-model router — varied perspectives"}
    ]
  }]
})
```

Save debate config to providers.json under `.routing.features.debate`:
```bash
jq --argjson providers '["claude","codex","agy"]' \
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
      {label: "💰 Budget", description: "Use cheapest configured models, including gpt-5.6-luna — best for prototyping"},
      {label: "⚖️ Standard (current default)", description: "Balanced: use your configured defaults"},
      {label: "🚀 Premium", description: "Use best available models for every task — higher cost, best quality"}
    ]
  }]
})
```

Apply the selection with the shared helper:

```bash
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh cost-mode <mode>
```

The helper persists the selection in `providers.json`. Do not edit the user's
shell profile. Mention the matching quick command: `/octo:budget-mode`,
`/octo:standard-mode`, or `/octo:premium-mode`.

To configure which model or capability a provider uses in a tier:

```bash
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh tier <budget|standard|premium> <provider> <model-or-capability>
```


### Route: Role Routing Overrides

Use role routing when a specific persona or workflow role should use a different provider/model than the phase or provider default. Examples: route `researcher` to `agy:default`, route `logic-reviewer` to `codex:logic_review`, or route QA roles to a review model while implementation remains on the provider default.

Show current role overrides:

```bash
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh show roles
```

Set or remove an override:

```bash
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh route-role <role> <provider:capability-or-model>
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh unroute-role <role>
```

Role overrides are intentionally sparse. Do not restate defaults; add a role only when it needs deterministic routing different from the provider/persona default.

### Route: Session Provider Availability

Use this when the user wants to turn a provider off for the current session, for example when Codex quota is exhausted and they want Claude + Antigravity only.

First show the current allowlist:

```bash
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh providers
```

Then ask which providers should be available:

```
AskUserQuestion({
  questions: [{
    question: "Which providers should Octopus use for this session?",
    header: "Providers",
    multiSelect: true,
    options: [
      {label: "Claude", description: "Built-in Claude providers"},
      {label: "Codex", description: "OpenAI Codex CLI"},
      {label: "Antigravity", description: "Google Antigravity CLI"},
      {label: "Copilot", description: "GitHub Copilot CLI"},
      {label: "Qwen", description: "Qwen Code CLI"},
      {label: "OpenCode", description: "OpenCode multi-provider router"},
      {label: "Perplexity", description: "Live web research via API key"},
      {label: "OpenRouter", description: "OpenRouter API models"}
    ]
  }]
})
```

Apply the selection as a session allowlist:

```bash
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh allow <providers...> --session
```

Useful direct commands:

```bash
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh disable codex --session
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh allow claude agy --session
${HOME}/.claude-octopus/plugin/scripts/helpers/octo-model-config.sh clear-allowlist --session
```

Explain that `OCTO_ALLOWED_PROVIDERS` still wins when it is set in the shell environment.

### Route: Reset

```
AskUserQuestion({
  questions: [{
    question: "What do you want to reset?",
    header: "Reset",
    multiSelect: false,
    options: [
      {label: "Reset all", description: "Restore all providers and routing to defaults"},
      {label: "Reset Codex only", description: "Reset Codex to gpt-5.6-sol default"},
      {label: "Reset Antigravity only", description: "Reset Antigravity to its service-selected default"},
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

When invoked WITH arguments (e.g., `/octo:model-config codex gpt-5.6-sol`), skip the interactive flow and execute directly:

1. **Parse arguments** to determine action:
   - `show phases` → Display formatted phase routing table
   - `show roles` → Display explicit role routing overrides
   - `<provider> <model>` → Set model (persistent)
   - `<provider>.<capability> <model>` → Set capability-specific model
   - `<provider> <model> --session` → Set model (session only)
   - `phase <phase> <model>` → Set phase-specific model routing
   - `cost-mode <budget|standard|premium|status>` → Persist or inspect the active cost mode
   - `tier <budget|standard|premium> <provider> <model-or-capability>` → Configure a tier mapping
   - `route-role <role> <target>` → Set role/persona routing override
   - `unroute-role <role>` → Remove role/persona routing override
   - `providers` → Show current provider allowlist source and value
   - `allow <providers...> --session` → Use only these providers for the current session
   - `disable <providers...> --session` → Remove providers from the current session
   - `enable <providers...> --session` → Add providers to the current session allowlist
   - `clear-allowlist --session` → Restore default provider availability for the current session
   - `reset <provider|all>` → Reset to defaults

2. **Set Model** (`<provider> <model>` or with `--session`):
   ```bash
   scripts/helpers/octo-model-config.sh set "<provider>" "<model>" [--session]
   ```

   **Dot syntax** (`<provider>.<capability> <model>`):
   ```bash
   scripts/helpers/octo-model-config.sh set "<provider>.<capability>" "<model>"
   ```

3. **Set Phase Routing** (`phase <phase> <model>`):
   Validate phase name against: `discover`, `define`, `develop`, `deliver`, `quick`, `debate`, `review`, `security`, `research`.
   ```bash
   scripts/helpers/octo-model-config.sh route "<phase>" "<model>"
   ```

4. **Reset**: Use default values from the ensure_config block in `scripts/helpers/octo-model-config.sh`.

5. **Provider Availability**: Use `scripts/helpers/octo-model-config.sh providers|allow|enable|disable|clear-allowlist`. These commands write to `~/.claude-octopus/config/provider-allowlist.<session>` by default. Global files are supported with `--global`, but prefer session scope unless the user explicitly asks for a persistent change.

6. **Cost Mode**: Use `scripts/helpers/octo-model-config.sh cost-mode <mode>`
   for the active selection and `scripts/helpers/octo-model-config.sh tier
   <mode> <provider> <target>` for per-provider tier mappings. The
   `OCTOPUS_COST_MODE` environment variable remains the highest-priority
   override.

7. Always show confirmation and the updated value after any change.

### Validation Gates

- Provider names are validated against the canonical registry: `codex commandcode claude claude-sdk agy perplexity opencode openrouter orcarouter atlascloud openai-compatible openai-tools openai-compatible-agent cursor-agent grok qwen ollama copilot vibe kimi`. Aliases are canonicalized first; for example, `antigravity` becomes `agy`.
- Phase names validated against known list
- Model values reject empty strings, whitespace, shell metacharacters, and leading slashes. Provider-qualified targets such as `codex:default` are allowed.
- In dot syntax, the suffix is stored as a capability key without separate capability-name validation.
- Route and model writes use `jq --arg`, a temporary file, and `mv` for atomic replacement.

### Prohibited Actions

- Assuming configuration without reading the file
- Skipping validation of provider/phase names
- Using string interpolation in jq expressions
- Showing providers that aren't installed (in interactive mode)
