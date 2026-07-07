# OpenCode CLI Provider Configuration

This file contains OpenCode-specific instructions for Claude Octopus workflows.

## Provider Information

- **Provider**: OpenCode CLI (multi-provider router)
- **Emoji**: 🟤
- **API Key**: Varies by backend — OAuth for Google, API keys for OpenAI/Z.AI/MiniMax
- **CLI Command**: `opencode run`
- **Agent Types**: `opencode`, `opencode-fast`, `opencode-research`
- **Cost**: Variable — free for Google OAuth, pay-per-use for OpenAI API, depends on backend model

## Detection

- CLI: `command -v opencode`
- Auth file: `~/.local/share/opencode/auth.json`
- Validation: `timeout 3 opencode auth list` (non-blocking check)

Workflows silently skip OpenCode if the CLI is not installed or not authenticated. Diagnostic tools (`/octo:doctor`) will still report the provider status.

## Authentication Setup

### Option 1: Interactive Login (recommended)

```bash
opencode auth login
```

Authenticates via credential flow for supported backends (Google, OpenAI).

### Option 2: Environment Variables (per backend)

```bash
export GITHUB_TOKEN="ghp_..."           # GitHub Copilot + GitHub Models
export OPENROUTER_API_KEY="sk-or-..."   # OpenRouter (100+ models)
export Z_AI_API_KEY="..."               # Z.AI direct (GLM models)
export MINIMAX_API_KEY="..."            # MiniMax models
```

### Option 3: Combined (maximum backend coverage)

Run `opencode auth login` for OAuth backends, then set env vars for API-key backends.

## Multi-Provider Architecture

OpenCode routes to multiple backends via a single CLI using `-m provider/model` format.

| Prefix | Backend | Example Models |
|--------|---------|----------------|
| `google/` | Google AI | Google-branded model labels (e.g. flash, pro variants) |
| `openai/` | OpenAI | `gpt-5.4`, `gpt-5.4-mini` |
| `z-ai/` | Z.AI | `glm-5`, `glm-5.1` |
| `openrouter/` | OpenRouter | `deepseek/deepseek-r1`, `z-ai/glm-5` |
| `github-copilot/` | GitHub Copilot | `claude-opus-4.6`, `gpt-5.4` |
| `github-models/` | GitHub Models | `meta/llama-3.1-70b-instruct` |
| `minimax/` | MiniMax | (MiniMax catalog) |
| `opencode/` | OpenCode built-in | `gpt-5-nano` (free) |

The same model can be routed through different backends (e.g., `z-ai/glm-5` direct vs `openrouter/z-ai/glm-5` proxied) for cost, latency, or availability reasons.

Run `opencode models` for the full model catalog.

## Model Configuration

```bash
# Set default model for all OpenCode agent types
/octo:model-config opencode google/default

# Set capability-specific models (dot syntax)
/octo:model-config opencode.fast google/default
/octo:model-config opencode.research z-ai/glm-5.1
```

## Dispatch Pattern

```bash
opencode run -m provider/model "<prompt>"
```

## Role Assignment

OpenCode serves as an independent multi-provider router:
- **Default** (`opencode`) — general-purpose tasks via configured default model
- **Fast iteration** (`opencode-fast`) — quick feedback via fast/budget model
- **Research** (`opencode-research`) — deep analysis via research-grade model

OpenCode is a standalone provider, not a replacement for Codex or Antigravity.

## Limitations

- Cost depends entirely on the backend model selected (free to premium)
- No direct model selection from orchestrate.sh — uses model-resolver pipeline
- Output is plain text (ANSI stripped by caller)
- Some backends require separate API keys beyond OAuth

## Timeout Configuration

Default timeout: 90 seconds. Configurable via `OCTOPUS_OPENCODE_TIMEOUT` env var.

## Error Handling

Common errors:
- `unauthorized`: Not authenticated — run `opencode auth login`
- `model not found`: Invalid provider/model — check `opencode models`
- `Timeout`: Response took too long — increase timeout or use a faster model
- `command not found`: CLI not installed — `npm install -g opencode-ai`

## Integration with Workflows

OpenCode is used in:
- **Discover Phase**: Research via `opencode-research` agent type
- **Develop Phase**: Code generation via default or fast agent types
- **Deliver Phase**: Fast review feedback via `opencode-fast` agent type
