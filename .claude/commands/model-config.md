---
command: model-config
description: Configure AI provider models for Claude Octopus workflows
version: 1.0.0
category: configuration
tags: [config, models, providers, codex, gemini]
created: 2025-01-21
updated: 2025-01-21
---

# Model Configuration

Configure which AI models are used by Claude Octopus workflows. This allows you to:
- Use premium models (Claude Opus 4.6, GPT-5) for complex tasks
- Use fast models (Gemini Flash) for simple tasks
- Control cost/performance tradeoffs per project
- Set temporary overrides for specific sessions

## Usage

```bash
# View current configuration
/octo:model-config

# Set codex model (persistent)
/octo:model-config codex claude-opus-4-6

# Set gemini model (persistent)
/octo:model-config gemini gemini-2.0-pro-exp

# Set session-only override (doesn't modify config file)
/octo:model-config codex gpt-5.2 --session

# Reset to defaults
/octo:model-config reset codex
/octo:model-config reset all
```

## Model Precedence

Models are selected using 4-tier precedence:

1. **Environment variables** (highest priority)
   - `OCTOPUS_CODEX_MODEL`
   - `OCTOPUS_GEMINI_MODEL`

2. **Session overrides** (from `--session` flag)
   - Stored in `~/.claude-octopus/config/providers.json` → `overrides`

3. **Config file defaults**
   - Stored in `~/.claude-octopus/config/providers.json` → `providers`

4. **Hard-coded defaults** (lowest priority)
   - Codex: `gpt-5.1-codex-max`
   - Gemini: `gemini-3-pro-preview`

## Supported Models

### Codex (OpenAI)
- `claude-sonnet-4-5` - Balanced performance (default)
- `claude-opus-4-6` - Maximum capability (premium)
- `claude-opus-4-5` - Legacy (replaced by claude-opus-4-6)
- `gpt-5.2-codex` - OpenAI's code-optimized model
- `gpt-5.1-codex-max` - Maximum context window

### Gemini (Google)
- `gemini-2.0-flash-thinking-exp-01-21` - Fast with reasoning (default)
- `gemini-2.0-flash-exp` - Fastest, lowest cost
- `gemini-2.0-pro-exp` - Premium quality
- `gemini-3-pro-preview` - Latest preview

## Examples

### Premium Research Workflow
```bash
# Use premium models for important research
export OCTOPUS_CODEX_MODEL="claude-opus-4-6"
export OCTOPUS_GEMINI_MODEL="gemini-2.0-pro-exp"
/octo:discover OAuth security patterns
```

### Fast Prototyping
```bash
# Use fast models for quick iteration
/octo:model-config codex claude-sonnet-4-5
/octo:model-config gemini gemini-2.0-flash-exp
/octo:develop user profile component
```

### Per-Session Override
```bash
# Test with different model without changing config
/octo:model-config codex gpt-5.2 --session
/octo:debate Redis vs Memcached
# Config file unchanged, override cleared on exit
```

## Configuration File

Location: `~/.claude-octopus/config/providers.json`

```json
{
  "version": "1.0",
  "providers": {
    "codex": {
      "model": "claude-sonnet-4-5",
      "fallback": "claude-opus-4-6"
    },
    "gemini": {
      "model": "gemini-2.0-flash-thinking-exp-01-21",
      "fallback": "gemini-2.0-flash-exp"
    }
  },
  "overrides": {}
}
```

## Requirements

- `jq` - JSON processor (install: `brew install jq` or `apt install jq`)

## Notes

- Model names are not validated against provider APIs
- Invalid models will fail when workflows execute
- Environment variables override all other settings
- Session overrides are cleared when you reset or edit the config file manually
- Cost implications vary significantly between models - use premium models judiciously

---

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:model-config`, you MUST:

1. **Parse arguments** to determine action:
   - No args → View current configuration
   - `<provider> <model>` → Set model (persistent)
   - `<provider> <model> --session` → Set model (session only)
   - `reset <provider|all>` → Reset to defaults

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
   source /Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh
   set_provider_model <provider> <model> [--session]

   # Show updated configuration
   cat ~/.claude-octopus/config/providers.json | jq '.'
   ```

4. **Reset Model** (`reset <provider|all>`):
   ```bash
   # Call reset_provider_model from orchestrate.sh
   source /Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh
   reset_provider_model <provider>

   # Show updated configuration
   cat ~/.claude-octopus/config/providers.json | jq '.'
   ```

5. **Provide guidance** on:
   - Which models are appropriate for which tasks
   - Cost implications of premium models
   - How to use environment variables for temporary changes

### Validation Gates

- ✅ Arguments parsed correctly
- ✅ Action determined (view/set/reset)
- ✅ Functions called with Bash tool (not simulated)
- ✅ Configuration displayed to user
- ✅ Clear confirmation messages shown

### Prohibited Actions

- ❌ Assuming configuration without reading the file
- ❌ Suggesting edits without using the provided functions
- ❌ Skipping validation of provider names
- ❌ Ignoring errors from jq or function calls
