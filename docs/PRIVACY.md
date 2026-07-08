# Privacy Policy

**Claude Octopus** is an open-source Claude Code plugin. This policy describes how the plugin handles data.

## What the plugin collects

**Nothing.** Claude Octopus does not collect, transmit, or store any personal data, telemetry, analytics, or usage metrics. There is no phone-home, no tracking, and no remote data collection of any kind.

## What stays on your machine

All plugin data is stored locally:

- **Session state**: `~/.claude-octopus/` — workflow progress, provider cache, HUD config
- **Results**: `~/.claude-octopus/results/` — research synthesis, quality gate outputs
- **Logs**: `~/.claude-octopus/logs/` — diagnostic logs (never transmitted)

## Third-party API calls

The plugin dispatches prompts to AI providers **you configure**. These calls go directly from your machine to the provider's API — the plugin is not an intermediary:

| Provider | Who receives your prompts | Your relationship |
|----------|--------------------------|-------------------|
| Codex (OpenAI) | OpenAI | Your API key or OAuth |
| Antigravity CLI (`agy`) | Google Antigravity (agent harness, Google seat) | OAuth via `agy login` + keyring session (stores credentials) — optional headless override `ANTIGRAVITY_API_KEY` for non-interactive use |
| Copilot (GitHub) | GitHub | Your Copilot subscription |
| Qwen (Alibaba) | Alibaba Cloud | Your Qwen API key or Coding-Plan credentials |
| Ollama | Your local machine | No external calls |
| Perplexity | Perplexity AI | Your API key |
| OpenRouter | OpenRouter | Your API key |
| Claude (Anthropic) | Anthropic | Your Claude Code subscription |

The plugin does not add headers, modify payloads, or route traffic through any intermediary server.

## Rate limit API

The HUD statusline optionally calls the Anthropic OAuth usage API (`api.anthropic.com/api/oauth/usage`) to display your rate limit status. This uses your existing Claude Code credentials and returns only your usage percentages — no prompt content is involved.

## Open source

The complete source code is available at [github.com/nyldn/claude-octopus](https://github.com/nyldn/claude-octopus) under the MIT license. You can audit every line.

## Contact

For privacy questions, open an issue at [github.com/nyldn/claude-octopus/issues](https://github.com/nyldn/claude-octopus/issues).

*Last updated: March 2026*
