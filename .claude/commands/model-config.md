---
command: model-config
description: Configure AI provider models for Claude Octopus workflows
version: 3.0.0
category: configuration
tags: [config, models, providers, codex, gemini, spark, routing, trace]
created: 2025-01-21
updated: 2026-03-09
---

# Model Configuration

Configure which AI models are used by Claude Octopus workflows. This allows you to:
- Use premium models (GPT-5.4, Claude Opus 4.6) for complex tasks
- Use fast models (GPT-5.3-Codex-Spark, Gemini Flash) for quick feedback
- Use large-context models (GPT-4.1, 1M tokens) for big codebases
- Use reasoning models (o3, o3) for complex analysis
- Configure per-phase model routing (different models for different workflow phases)
- Control cost/performance tradeoffs with cost modes (budget/standard/premium)
- Debug model selection with resolution tracing

## Usage

```bash
# View current configuration (models + phase routing + cost mode)
/octo:model-config

# Show current phase routing table
/octo:model-config show phases

# Set codex model (persistent)
/octo:model-config codex gpt-5.4

# Set to Spark for fast mode
/octo:model-config codex gpt-5.4

# Set gemini model (persistent)
/octo:model-config gemini gemini-3.1-pro-preview

# Set session-only override (doesn't modify config file)
/octo:model-config codex gpt-5.2-codex --session

# Configure phase routing (which model to use in which phase)
/octo:model-config phase deliver gpt-5.4
/octo:model-config phase develop gpt-5.4

# Reset to defaults
/octo:model-config reset codex
/octo:model-config reset all
```

## Model Precedence

Models are resolved using a 7-tier precedence system (use `OCTOPUS_TRACE_MODELS=1` to see which tier is selected):

1. **Environment variables** (highest priority)
   - `OCTOPUS_CODEX_MODEL` - Override all codex model selection
   - `OCTOPUS_GEMINI_MODEL` - Override all gemini model selection
   - `OCTOPUS_PERPLEXITY_MODEL` - Override perplexity model selection

2. **Native Claude Code settings** (Tier 0.5)
   - `CLAUDE_MODEL` env var - Only applies when provider is `claude`

3. **Session overrides** (config file `.overrides` section)
   - Set via `/octo:model-config <provider> <model> --session`

4. **Phase/role routing** (config file `.routing.phases` / `.routing.roles`)
   - Per-phase model selection: different models for discover/define/develop/deliver
   - Supports cross-provider references (e.g., `codex:spark`, `gemini:default`)

5. **Capability mapping** (config file `.providers.<provider>.<capability>`)
   - Maps agent types to specific model variants (spark, mini, reasoning, etc.)

6. **Cost mode tier mapping** (config file `.tiers`)
   - `OCTOPUS_COST_MODE=budget` → uses mini/flash models
   - `OCTOPUS_COST_MODE=premium` → uses full/pro models
   - Default: `standard`

7. **Config file defaults** (`.providers.<provider>.default`)
   - Persistent defaults set via `/octo:model-config <provider> <model>`

8. **Hard-coded fallbacks** (lowest priority)
   - Codex: `gpt-5.4`
   - Gemini: `gemini-3.1-pro-preview` (standard), `gemini-3-flash-preview` (fast)
   - Claude: `claude-sonnet-4.6` (standard), `claude-opus-4.6` (opus)
   - Perplexity: `sonar-pro` (standard), `sonar` (fast)

## Debugging Model Selection

When model selection produces unexpected results, enable resolution tracing:

```bash
export OCTOPUS_TRACE_MODELS=1
/octo:discover "test query"
# stderr will show:
# [model-trace] Resolving: provider=codex type=codex phase=discover role=<none>
# [model-trace] Tier 1 (env OCTOPUS_CODEX_MODEL): —
# [model-trace] Tier 2 (session override): —
# [model-trace] Tier 3 (phase/role routing): gpt-5.4 ← SELECTED (route: codex:spark)
# [model-trace] ► Result: gpt-5.4
```

## Cost Modes

Control cost/performance tradeoffs globally with `OCTOPUS_COST_MODE`:

```bash
# Budget mode — use cheapest models for all tasks
export OCTOPUS_COST_MODE=budget
/octo:embrace build a CRUD API

# Premium mode — use best models for all tasks
export OCTOPUS_COST_MODE=premium
/octo:embrace design payment architecture

# Standard mode (default) — balanced selection
export OCTOPUS_COST_MODE=standard
```

| Mode | Codex Model | Gemini Model | Best For |
|------|-------------|--------------|----------|
| `budget` | gpt-5-codex-mini | gemini-3-flash-preview | Prototyping, low-cost iteration |
| `standard` | (config default) | (config default) | Normal development |
| `premium` | (config default) | (config default) | Critical features, security audits |

## Supported Models

### Codex Flagship Models

| Model | Context | Speed | Best For | Cost |
|-------|---------|-------|----------|------|
| `gpt-5.4` | 400K | ~65 tok/s | Complex implementation, architecture | $2.50/$15.00 per MTok |
| `gpt-5.4` | 128K | **1000+ tok/s** | Fast reviews, iteration, prototyping | Pro-only |
| `gpt-5.2-codex` | 400K | ~65 tok/s | Legacy support | $1.75/$14.00 per MTok |

### Codex Budget & Specialized

| Model | Context | Best For | Cost |
|-------|---------|----------|------|
| `gpt-5-codex-mini` | 400K | Budget tasks, ~1 credit/msg | ~$0.25/$2.00 per MTok |
| `gpt-5.1-codex-max` | 400K | Long-horizon agentic tasks | $1.25/$10.00 per MTok |

### Reasoning Models (via Codex CLI)

| Model | Context | Best For | Cost |
|-------|---------|----------|------|
| `o3` | 200K | Deep reasoning, trade-off analysis | $2.00/$8.00 per MTok |
| `o3` | 200K | Cost-effective reasoning | $1.10/$4.40 per MTok |

### Large Context Models (via Codex CLI)

| Model | Context | Best For | Cost |
|-------|---------|----------|------|
| `gpt-5.4` | **1M** | Large codebase analysis, dependency mapping | $2.00/$8.00 per MTok |
| `gpt-5.4` | **1M** | Budget large-context tasks | $0.40/$1.60 per MTok |

### OpenRouter Models (v8.11.0)

| Agent Type | Model | Context | Best For | Cost |
|------------|-------|---------|----------|------|
| `openrouter-glm5` | `z-ai/glm-5` | 203K | Code review specialist | $0.80/$2.56 per MTok |
| `openrouter-kimi` | `moonshotai/kimi-k2.5` | **262K** | Research, multimodal | $0.45/$2.25 per MTok |
| `openrouter-deepseek` | `deepseek/deepseek-r1` | 164K | Deep reasoning | $0.70/$2.50 per MTok |

Requires `OPENROUTER_API_KEY` to be set.

### Gemini (Google)

| Model | Best For | Cost |
|-------|----------|------|
| `gemini-3.1-pro-preview` | Premium quality research | $2.50/$10.00 per MTok |
| `gemini-3-flash-preview` | Fast, low-cost tasks | $0.25/$1.00 per MTok |

## Phase Routing

Contextual phase routing selects the best model for each workflow phase:

| Phase | Default Routing | Rationale |
|-------|----------------|-----------|
| `discover` | codex default | Deep research needs max reasoning |
| `define` | codex default | Requirements analysis needs precision |
| `develop` | codex default | Complex implementation |
| `deliver` | `codex:spark` | Fast review feedback (15x faster) |
| `review` | `codex:spark` | Rapid PR review feedback |
| `security` | `codex:reasoning` | Thorough security analysis via o3 |
| `research` | `gemini:default` | Gemini excels at broad research |
| `quick` | `codex:spark` | Speed over depth |
| `debate` | codex default | Deep reasoning for arguments |

### Customizing Phase Routing

```bash
# Use Spark for develop phase (faster iteration)
/octo:model-config phase develop codex:spark

# Use reasoning model for security (deeper analysis)
/octo:model-config phase security o3

# Use Gemini for discover phase
/octo:model-config phase discover gemini:default

# View current phase routing
/octo:model-config show phases
```

Phase routing supports both direct model names (`gpt-5.4`) and cross-provider references (`codex:spark`, `gemini:default`).

## Configuration File

Location: `~/.claude-octopus/config/providers.json`

```json
{
  "version": "3.0",
  "providers": {
    "codex": {
      "default": "gpt-5.4",
      "fallback": "gpt-5.2-codex",
      "spark": "gpt-5.4",
      "mini": "gpt-5-codex-mini",
      "reasoning": "o3",
      "large_context": "gpt-4.1"
    },
    "gemini": {
      "default": "gemini-3.1-pro-preview",
      "fallback": "gemini-3-flash-preview",
      "flash": "gemini-3-flash-preview",
      "image": "gemini-3-pro-image-preview"
    }
  },
  "routing": {
    "phases": {
      "deliver": "codex:spark",
      "review": "codex:spark",
      "security": "codex:reasoning",
      "research": "gemini:default"
    },
    "roles": {
      "researcher": "perplexity"
    }
  },
  "tiers": {
    "budget": { "codex": "mini", "gemini": "flash" },
    "standard": { "codex": "default", "gemini": "default" },
    "premium": { "codex": "default", "gemini": "default" }
  },
  "overrides": {}
}
```

### Auto-Migration

If your config file uses an older format (v1.0 or v2.0), it will be automatically migrated to v3.0 on first use. Stale model names (e.g., `gpt-4o`, `gemini-1.5-pro`) are also auto-upgraded.

## Environment Variables Reference

| Variable | Purpose | Example |
|----------|---------|---------|
| `OCTOPUS_CODEX_MODEL` | Override all Codex model selection | `gpt-5.4` |
| `OCTOPUS_GEMINI_MODEL` | Override all Gemini model selection | `gemini-3.1-pro-preview` |
| `OCTOPUS_PERPLEXITY_MODEL` | Override Perplexity model | `sonar-pro` |
| `OCTOPUS_COST_MODE` | Set cost tier: `budget`, `standard`, `premium` | `budget` |
| `OCTOPUS_TRACE_MODELS` | Enable model resolution tracing | `1` |
| `OCTOPUS_CODEX_ALLOWED_MODELS` | Allowlist for Codex models | `gpt-5.4,gpt-5.2-codex` |
| `OCTOPUS_GEMINI_ALLOWED_MODELS` | Allowlist for Gemini models | `gemini-3-flash-preview` |
| `OCTOPUS_GEMINI_SANDBOX` | Gemini execution mode | `headless` (default) |

## Spark vs Full Codex: When to Use Which

| Factor | GPT-5.4 | GPT-5.3-Codex-Spark |
|--------|---------|---------------------|
| **Speed** | ~65 tok/s | **1000+ tok/s** (15x) |
| **Context** | 400K tokens | 128K tokens |
| **Image input** | Yes | No (text only) |
| **Availability** | All plans | Pro ($200/mo) only |
| **Best for** | Complex tasks, security, architecture | Reviews, iteration, quick tasks |

**Rule of thumb:** Use Spark when speed matters more than depth. Use full Codex when accuracy and context window matter.

## Valid Providers

The following providers can be configured: `codex`, `gemini`, `claude`, `perplexity`, `openrouter`.

Custom/local providers (e.g., Ollama proxies) can be set using the `--force` flag:
```bash
/octo:model-config custom-local llama-3.2 --force
```

## Requirements

- `jq` - JSON processor (install: `brew install jq` or `apt install jq`)

---

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:model-config`, you MUST:

1. **Parse arguments** to determine action:
   - No args → View current configuration including phase routing and cost mode
   - `show phases` → Display formatted phase routing table
   - `<provider> <model>` → Set model (persistent)
   - `<provider> <model> --session` → Set model (session only)
   - `phase <phase> <model>` → Set phase-specific model routing
   - `reset <provider|all>` → Reset to defaults

2. **View Configuration** (no args):
   ```bash
   # Check environment variables
   env | grep OCTOPUS_ 2>/dev/null || echo "No OCTOPUS_ environment variables set"

   # Show config file contents
   if [[ -f ~/.claude-octopus/config/providers.json ]]; then
     cat ~/.claude-octopus/config/providers.json | jq '.'
   else
     echo "No configuration file found (using defaults)"
   fi
   ```
   Then display a formatted summary table showing:
   - Provider models (codex, gemini) with fallbacks
   - Phase routing (if configured)
   - Active cost mode
   - Active environment overrides
   - Available subcommands

3. **Show Phases** (`show phases`):
   ```bash
   if [[ -f ~/.claude-octopus/config/providers.json ]]; then
     echo "Phase Routing Configuration:"
     jq -r '.routing.phases // {} | to_entries[] | "  \(.key)\t→ \(.value)"' ~/.claude-octopus/config/providers.json 2>/dev/null
   fi
   ```
   Display as a formatted table with phase name, routed model, and rationale.
   Show phases NOT in config that use hardcoded defaults.

4. **Set Model** (`<provider> <model>` or with `--session`):
   Execute via orchestrate.sh's `set_provider_model()`:
   ```bash
   /path/to/orchestrate.sh set-model <provider> <model> [--session]
   ```
   The function validates provider (whitelist), model name (injection safety), and uses atomic file operations.
   Show the updated config after setting.

5. **Set Phase Routing** (`phase <phase> <model>`):
   Validate phase name against known phases: `discover`, `define`, `develop`, `deliver`, `quick`, `debate`, `review`, `security`, `research`.
   ```bash
   # Update routing.phases in config file
   local config_file="${HOME}/.claude-octopus/config/providers.json"
   jq --arg phase "<phase>" --arg model "<model>" '.routing.phases[$phase] = $model' "$config_file" > "${config_file}.tmp.$$" && mv "${config_file}.tmp.$$" "$config_file"
   echo "✓ Set phase routing: $phase → $model"
   ```

6. **Reset Model** (`reset <provider|all>`):
   Execute via orchestrate.sh's `reset_provider_model()`.
   Show the updated config after reset.

7. **Provide guidance** on:
   - Which models are appropriate for which tasks/phases
   - Cost implications of premium models vs Spark vs budget
   - How to use environment variables for temporary changes
   - How to use `OCTOPUS_TRACE_MODELS=1` for debugging
   - How to use `OCTOPUS_COST_MODE` for cost control

### Validation Gates

- Parsed arguments correctly
- Action determined (view/show-phases/set/set-phase/reset)
- Functions called with Bash tool (not simulated)
- Configuration displayed to user
- Clear confirmation messages shown
- Phase names validated against known list

### Prohibited Actions

- Assuming configuration without reading the file
- Suggesting edits without using the provided functions
- Skipping validation of provider names
- Ignoring errors from jq or function calls
- Using string interpolation in jq expressions (use `--arg` instead)
