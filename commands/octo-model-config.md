---
description: Configure AI provider models for Claude Octopus workflows (v3.0)
---

# Model Configuration (v3.0)

Configure which AI models are used by Claude Octopus workflows. v3.0 introduces a unified model resolver with enhanced phase/role routing and session-level caching.

## Usage

```bash
# View current configuration (models + routing + overrides)
/octo:model-config

# Set default model for a provider (persistent)
/octo:model-config set codex gpt-5.4
/octo:model-config set gemini gemini-3-pro-preview
/octo:model-config set claude claude-opus-4.6

# Set session-only override (doesn't modify defaults)
/octo:model-config set codex gpt-5.2-codex --session

# Configure phase routing (route phase to a model or capability)
/octo:model-config route deliver codex:spark
/octo:model-config route security codex:reasoning
/octo:model-config route research gemini:default

# Reset to defaults
/octo:model-config reset codex
/octo:model-config reset all
```

## Model Precedence (v3.0)

Models are selected using a refined top-down precedence system:

1. **Force Overrides (Highest)**
   - Environment variables (e.g., `OCTOPUS_CODEX_MODEL`)
   - Native Claude Code settings (for `claude` provider)

2. **Session Context**
   - Session-only config overrides (`.overrides` in config)

3. **Phase & Role Routing**
   - Phase routing (e.g., `deliver` → `codex:spark`)
   - Role routing (e.g., `researcher` → `perplexity`)

4. **Capability Mapping**
   - Mapped via agent type suffix (e.g., `codex-spark` → `providers.codex.spark`)

5. **Tier Mapping**
   - Configured via `OCTOPUS_COST_MODE` (budget/standard/premium)

6. **Global Defaults (Lowest)**
   - Config file defaults (`.providers.provider.default`)
   - Hard-coded fallback values

## Supported Providers & Models

### Codex (OpenAI via Codex CLI)

| Model | Type | Best For |
|-------|------|----------|
| `gpt-5.4` | Flagship | Complex implementation, architecture |
| `gpt-5.3-codex-spark` | Spark | Fast reviews, iteration (1000+ tok/s) |
| `o3` | Reasoning | Deep logic, trade-off analysis |
| `gpt-4.1` | Large Context | 1M token window for big codebases |

### Claude (Anthropic via Claude CLI)

| Model | Best For |
|-------|----------|
| `claude-sonnet-4.6` | Default flagship, high quality |
| `claude-opus-4.6` | Premium reasoning and reliability |

### Gemini (Google via Gemini CLI)

| Model | Best For |
|-------|----------|
| `gemini-3-pro-preview` | Premium quality research |
| `gemini-3-flash-preview` | Fast, low-cost tasks |

### Perplexity (Web Search)

| Model | Best For |
|-------|----------|
| `sonar-pro` | Web-grounded research, news, docs |
| `sonar` | Fast web search and synthesis |

## Phase Routing

Automatically select the best model for each workflow phase:

| Phase | Default Target | Rationale |
|-------|----------------|-----------|
| `discover` | `codex:default` | Deep research needs reasoning |
| `develop` | `codex:default` | Implementation capability |
| `deliver` | `codex:spark` | Fast review feedback (15x faster) |
| `security` | `codex:reasoning` | Thorough vulnerability analysis |
| `research` | `gemini:default` | Multi-source research synthesis |

## Configuration File

Location: `~/.claude-octopus/config/providers.json`

```json
{
  "version": "3.0",
  "providers": {
    "codex": { 
      "default": "gpt-5.4", 
      "spark": "gpt-5.3-codex-spark",
      "reasoning": "o3"
    },
    "gemini": { "default": "gemini-3-pro-preview" }
  },
  "routing": { 
    "phases": { "deliver": "codex:spark" },
    "roles": { "researcher": "perplexity" }
  },
  "overrides": {}
}
```

---

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:model-config`, you MUST use the helper script:

1. **Invoke Helper:**
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/helpers/octo-model-config.sh" "$@"
   ```

2. **Handle Actions:**
   - **List:** Just run the helper with no args or `list`.
   - **Set Model:** `set <provider> <model> [--session]`
   - **Route Phase:** `route <phase> <target>`
   - **Reset:** `reset <provider|all>`

3. **Validation:**
   - Confirm the change was applied by reviewing the output of the helper.
   - If a provider is not recognized, warn the user but still attempt to set it (v3.0 is extensible).

4. **Security:**
   - Never expose API keys in configuration output.
   - Validate model names for suspicious characters.
