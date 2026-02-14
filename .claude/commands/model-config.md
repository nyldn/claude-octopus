---
name: model-config
description: Configure AI provider models for Claude Octopus workflows
version: 2.0.0
category: configuration
tags: [config, models, providers, codex, gemini, spark, routing]
created: 2025-01-21
updated: 2026-02-13
---

# Model Configuration

Configure which AI models are used by Claude Octopus workflows. This allows you to:
- Use premium models (GPT-5.3-Codex, Claude Opus 4.6) for complex tasks
- Use fast models (GPT-5.3-Codex-Spark, Gemini Flash) for quick feedback
- Use large-context models (GPT-4.1, 1M tokens) for big codebases
- Use reasoning models (o3, o4-mini) for complex analysis
- Configure per-phase model routing (different models for different workflow phases)
- Control cost/performance tradeoffs per project

## Usage

```bash
# View current configuration (models + phase routing)
/octo:model-config

# Set codex model (persistent)
/octo:model-config codex gpt-5.3-codex

# Set to Spark for fast mode
/octo:model-config codex gpt-5.3-codex-spark

# Set gemini model (persistent)
/octo:model-config gemini gemini-3-pro-preview

# Set session-only override (doesn't modify config file)
/octo:model-config codex gpt-5.2 --session

# Configure phase routing (which model to use in which phase)
/octo:model-config phase deliver gpt-5.3-codex-spark
/octo:model-config phase develop gpt-5.3-codex

# Reset to defaults
/octo:model-config reset codex
/octo:model-config reset phases
/octo:model-config reset all
```

## Model Precedence

Models are selected using a 5-tier precedence system:

1. **Environment variables** (highest priority)
   - `OCTOPUS_CODEX_MODEL` - Override all codex model selection
   - `OCTOPUS_GEMINI_MODEL` - Override all gemini model selection

2. **Task hints** (contextual override from calling code)
   - `fast` / `spark` → GPT-5.3-Codex-Spark
   - `deep` / `security` → GPT-5.3-Codex
   - `large-codebase` → GPT-4.1
   - `reasoning` → o3
   - `budget` → GPT-5.1-Codex-Mini

3. **Phase routing config** (per-phase model selection)
   - Stored in `~/.claude-octopus/config/providers.json` → `phase_routing`

4. **Config file defaults / session overrides**
   - Stored in `~/.claude-octopus/config/providers.json` → `providers` / `overrides`

5. **Hard-coded defaults** (lowest priority)
   - Codex: `gpt-5.3-codex`
   - Spark: `gpt-5.3-codex-spark`
   - Reasoning: `o3`
   - Large context: `gpt-4.1`
   - Gemini: `gemini-3-pro-preview`

## Supported Models

### Codex Flagship Models

| Model | Context | Speed | Best For | Cost |
|-------|---------|-------|----------|------|
| `gpt-5.3-codex` | 400K | ~65 tok/s | Complex implementation, architecture | $1.75/$14.00 per MTok |
| `gpt-5.3-codex-spark` | 128K | **1000+ tok/s** | Fast reviews, iteration, prototyping | Pro-only |
| `gpt-5.2-codex` | 400K | ~65 tok/s | Standard code generation | $1.75/$14.00 per MTok |

### Codex Budget & Legacy

| Model | Context | Best For | Cost |
|-------|---------|----------|------|
| `gpt-5.1-codex-mini` | 400K | Budget tasks, ~1 credit/msg | ~$0.30/$1.25 per MTok |
| `gpt-5.1-codex-max` | 400K | Long-horizon agentic tasks | $1.25/$10.00 per MTok |
| `gpt-5-codex` | 400K | Legacy support | $1.25/$10.00 per MTok |

### Reasoning Models (via Codex CLI)

| Model | Context | Best For | Cost |
|-------|---------|----------|------|
| `o3` | 200K | Deep reasoning, trade-off analysis | $2.00/$8.00 per MTok |
| `o4-mini` | 200K | Cost-effective reasoning | $1.10/$4.40 per MTok |

### Large Context Models (via Codex CLI)

| Model | Context | Best For | Cost |
|-------|---------|----------|------|
| `gpt-4.1` | **1M** | Large codebase analysis, dependency mapping | $2.00/$8.00 per MTok |
| `gpt-4.1-mini` | **1M** | Budget large-context tasks | $0.40/$1.60 per MTok |

### Gemini (Google)

| Model | Best For | Cost |
|-------|----------|------|
| `gemini-3-pro-preview` | Premium quality research | $2.50/$10.00 per MTok |
| `gemini-3-flash-preview` | Fast, low-cost tasks | $0.25/$1.00 per MTok |

## Phase Routing

v8.9.0 introduces **contextual phase routing** - automatically selecting the best model for each workflow phase:

| Phase | Default Model | Rationale |
|-------|--------------|-----------|
| `discover` | gpt-5.3-codex | Deep research needs max reasoning |
| `define` | gpt-5.3-codex | Requirements analysis needs precision |
| `develop` | gpt-5.3-codex | Complex implementation |
| `deliver` | gpt-5.3-codex-spark | Fast review feedback (15x faster) |
| `quick` | gpt-5.3-codex-spark | Speed over depth |
| `debate` | gpt-5.3-codex | Deep reasoning for arguments |
| `review` | gpt-5.3-codex-spark | Rapid PR review feedback |
| `security` | gpt-5.3-codex | Thorough security analysis |
| `research` | gpt-5.3-codex | Deep multi-source research |

### Customizing Phase Routing

```bash
# Use Spark for develop phase (faster iteration)
/octo:model-config phase develop gpt-5.3-codex-spark

# Use full codex for all review phases (deeper analysis)
/octo:model-config phase deliver gpt-5.3-codex
/octo:model-config phase review gpt-5.3-codex

# Use budget model for discover phase (save costs on research)
/octo:model-config phase discover gpt-5.1-codex-mini

# Reset phase routing to defaults
/octo:model-config reset phases
```

## Examples

### Fast Prototyping Mode
```bash
# Switch everything to Spark for rapid iteration
export OCTOPUS_CODEX_MODEL="gpt-5.3-codex-spark"
/octo:develop user profile component
# NOTE: Spark has 128K context (vs 400K for full Codex)
```

### Large Codebase Analysis
```bash
# Use 1M context model for analyzing large repos
/octo:model-config codex gpt-4.1 --session
/octo:discover "analyze the entire authentication subsystem"
```

### Cost-Optimized Workflow
```bash
# Use budget models across the board
/octo:model-config codex gpt-5.1-codex-mini
/octo:model-config gemini gemini-3-flash-preview
/octo:embrace build a simple CRUD API
```

### Deep Security Audit
```bash
# Use premium models + reasoning for security
/octo:model-config phase security o3
/octo:security audit the payment processing module
```

### Mixed: Spark for Reviews, Full for Implementation
```bash
# Default phase routing already does this, but to customize:
/octo:model-config phase develop gpt-5.3-codex
/octo:model-config phase deliver gpt-5.3-codex-spark
/octo:model-config phase review gpt-5.3-codex-spark
```

## Configuration File

Location: `~/.claude-octopus/config/providers.json`

```json
{
  "version": "2.0",
  "providers": {
    "codex": {
      "model": "gpt-5.3-codex",
      "fallback": "gpt-5.2-codex",
      "spark_model": "gpt-5.3-codex-spark",
      "mini_model": "gpt-5.1-codex-mini",
      "reasoning_model": "o3",
      "large_context_model": "gpt-4.1"
    },
    "gemini": {
      "model": "gemini-3-pro-preview",
      "fallback": "gemini-3-flash-preview"
    }
  },
  "phase_routing": {
    "discover": "gpt-5.3-codex",
    "define":   "gpt-5.3-codex",
    "develop":  "gpt-5.3-codex",
    "deliver":  "gpt-5.3-codex-spark",
    "quick":    "gpt-5.3-codex-spark",
    "debate":   "gpt-5.3-codex",
    "review":   "gpt-5.3-codex-spark",
    "security": "gpt-5.3-codex",
    "research": "gpt-5.3-codex"
  },
  "overrides": {}
}
```

## Spark vs Full Codex: When to Use Which

| Factor | GPT-5.3-Codex | GPT-5.3-Codex-Spark |
|--------|---------------|---------------------|
| **Speed** | ~65 tok/s | **1000+ tok/s** (15x) |
| **Context** | 400K tokens | 128K tokens |
| **Terminal-Bench** | 77.3% | 58.4% |
| **Image input** | Yes | No (text only) |
| **Availability** | All plans | Pro ($200/mo) only |
| **Best for** | Complex tasks, security, architecture | Reviews, iteration, quick tasks |

**Rule of thumb:** Use Spark when speed matters more than depth. Use full Codex when accuracy and context window matter.

## Requirements

- `jq` - JSON processor (install: `brew install jq` or `apt install jq`)

## Notes

- Model names are validated against known models but unknown models are still accepted
- Invalid models will fail when workflows execute
- Environment variables override all other settings including phase routing
- GPT-5.3-Codex-Spark requires OpenAI Pro subscription ($200/mo)
- Phase routing only affects Codex model selection (Gemini has its own model defaults)
- Cost implications vary significantly between models - see pricing table above
- **Gemini sandbox modes** (`OCTOPUS_GEMINI_SANDBOX`):
  - `headless` (default, v8.10.0) - Stdin-based prompt delivery with `-p ""`, `-o text`, `--approval-mode yolo`
  - `interactive` - Launch Gemini in interactive mode (for manual use)
  - `auto-accept` - Legacy alias for `headless`
  - `prompt-mode` - Legacy alias for `interactive`

---

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:model-config`, you MUST:

1. **Parse arguments** to determine action:
   - No args → View current configuration including phase routing
   - `<provider> <model>` → Set model (persistent)
   - `<provider> <model> --session` → Set model (session only)
   - `phase <phase> <model>` → Set phase-specific model routing
   - `reset <provider|phases|all>` → Reset to defaults

2. **View Configuration** (no args):
   ```bash
   # Check environment variables
   env | grep OCTOPUS_

   # Show config file contents
   if [[ -f ~/.claude-octopus/config/providers.json ]]; then
     cat ~/.claude-octopus/config/providers.json | jq '.'
   else
     echo "No configuration file found (using defaults)"
   fi
   ```

3. **Set Model** (`<provider> <model>` or with `--session`):
   ```bash
   # Call set_provider_model from orchestrate.sh
   source "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh"
   set_provider_model <provider> <model> [--session]

   # Show updated configuration
   cat ~/.claude-octopus/config/providers.json | jq '.'
   ```

4. **Set Phase Routing** (`phase <phase> <model>`):
   ```bash
   # Update phase_routing in config file
   local config_file="${HOME}/.claude-octopus/config/providers.json"
   jq ".phase_routing.${phase} = \"${model}\"" "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
   echo "✓ Set phase routing: $phase → $model"
   cat ~/.claude-octopus/config/providers.json | jq '.phase_routing'
   ```

5. **Reset Model** (`reset <provider|phases|all>`):
   ```bash
   # Call reset_provider_model from orchestrate.sh
   source "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh"
   reset_provider_model <provider>

   # For phases: reset phase_routing to defaults
   # For all: reset both providers and phase routing

   # Show updated configuration
   cat ~/.claude-octopus/config/providers.json | jq '.'
   ```

6. **Provide guidance** on:
   - Which models are appropriate for which tasks/phases
   - Cost implications of premium models vs Spark vs budget
   - How to use environment variables for temporary changes
   - Spark availability requirements (Pro subscription)

### Validation Gates

- Parsed arguments correctly
- Action determined (view/set/set-phase/reset)
- Functions called with Bash tool (not simulated)
- Configuration displayed to user
- Clear confirmation messages shown

### Prohibited Actions

- Assuming configuration without reading the file
- Suggesting edits without using the provided functions
- Skipping validation of provider names
- Ignoring errors from jq or function calls
