---
name: skill-opencli-research
version: 1.0.0
description: Real-time web research via OpenCLI — search Twitter/Reddit/HN/GitHub, fetch trending topics, and explore URLs. Use when: AUTOMATICALLY ACTIVATE when user needs live data:. "what's trending" or "search Twitter for" or "latest on Reddit". "fetch HN frontpage" or "explore this URL" or "real-time data"
---

# OpenCLI Real-Time Research

Real-time social/web data retrieval via OpenCLI to complement Codex/Gemini research.

## Prerequisites

- `npm install -g @jackwener/opencli && opencli setup`
- Chrome Browser Bridge extension (from GitHub Releases)

## MCP Tools

| Tool | Purpose | Example |
|------|---------|---------|
| `opencli_search` | Search a platform | `search(platform: "twitter", query: "AI agents")` |
| `opencli_trending` | Get trending topics | `trending(platform: "hackernews")` |
| `opencli_fetch` | Extract URL content | `fetch(url: "https://example.com")` |
| `opencli_explore` | Interactive browser explore | `explore(url: "https://spa-app.com")` |
| `opencli_status` | Check OpenCLI health | `status()` |

## Supported Platforms

`twitter`, `reddit`, `hackernews`, `github`, `stackoverflow`

## Multi-Platform Search

```bash
# Search across multiple platforms simultaneously
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh multi-search "query" twitter,reddit,hackernews
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh multi-trending twitter,hackernews
```

## Integration with Discover Phase

Use alongside `flow-discover` to add live social signals:

1. Run `orchestrate.sh probe` for Codex/Gemini research
2. Add `opencli_search` for live Twitter/Reddit sentiment
3. Use `opencli_trending` to identify current buzz
4. Synthesize all into recommendation

## Cost

**Free** — no API keys required. Rate limits apply per-platform.

## Error Recovery

| Error | Fix |
|-------|-----|
| `opencli: command not found` | `npm install -g @jackwener/opencli` |
| `Daemon not running` | `opencli daemon start` |
| `Browser Bridge unavailable` | Install Chrome extension from Releases |
| `Timeout` | Increase `OPENCLI_TIMEOUT` env var |
