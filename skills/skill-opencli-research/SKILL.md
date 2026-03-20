---
name: skill-opencli-research
version: 1.0.0
description: Real-time web research via OpenCLI — search Twitter/Reddit/HN/GitHub, fetch trending topics, and explore URLs. Use when: AUTOMATICALLY ACTIVATE when user needs live data:. "what's trending" or "search Twitter for" or "latest on Reddit". "fetch HN frontpage" or "explore this URL" or "real-time data"
---

# OpenCLI Real-Time Research

## The Iron Law

```
VERIFY OPENCLI IS INSTALLED. CHECK PLATFORM AVAILABILITY. ALWAYS ATTRIBUTE SOURCES.
```

Never assume OpenCLI is available. Always verify connectivity before executing. Always include source attribution in results.

---

## When to Use

**Use this skill for:**
- Real-time social media search (Twitter/X, Reddit, Hacker News)
- Trending topic aggregation across platforms
- Live URL content extraction and analysis
- Multi-platform research combining several sources
- Desktop application interaction via Browser Bridge

**Do NOT use for:**
- Static documentation lookup (use web search or context7)
- Codebase-specific research (use `flow-discover`)
- Historical data analysis (OpenCLI provides live/recent data only)

---

## Prerequisites

1. **OpenCLI installed**: `npm install -g @jackwener/opencli`
2. **OpenCLI setup complete**: `opencli setup` (creates config, tests connectivity)
3. **Browser Bridge extension** installed in Chrome (for `desktop` and `explore` actions)
4. **Chrome running** (required for Browser Bridge features)

### Quick Verification

```bash
# Check OpenCLI is installed
command -v opencli &>/dev/null && echo "✅ OpenCLI installed" || echo "❌ OpenCLI not found"

# Check version
opencli --version

# Check daemon status
opencli status
```

---

## Available Actions

### 1. Search — Query a Platform

Search a specific platform for recent content matching a query.

```bash
# Via MCP tool
opencli_search(platform: "twitter", query: "AI agent frameworks 2026")

# Via bridge script
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh search twitter "AI agent frameworks 2026"
```

**Supported platforms:** `twitter`, `reddit`, `hackernews`, `github`, `stackoverflow`

### 2. Trending — Get Trending Topics

Get currently trending topics on a platform.

```bash
# Via MCP tool
opencli_trending(platform: "hackernews")

# Via bridge script
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh trending hackernews
```

### 3. Fetch — Extract URL Content

Fetch and extract readable content from any URL.

```bash
# Via MCP tool
opencli_fetch(url: "https://example.com/article")

# Via bridge script
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh fetch "https://example.com/article"
```

### 4. Explore — Interactive URL Exploration

Explore a URL using the Browser Bridge for JavaScript-rendered content.

```bash
# Via MCP tool (requires Chrome + Browser Bridge)
opencli_explore(url: "https://example.com/spa-app")

# Via bridge script
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh explore "https://example.com/spa-app"
```

### 5. Desktop — Control Desktop Apps

Interact with desktop applications through Browser Bridge.

```bash
# Via MCP tool
opencli_desktop(app: "chrome", action: "screenshot")

# Via bridge script
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh desktop chrome screenshot
```

### 6. Status — Check OpenCLI Health

```bash
# Via MCP tool
opencli_status()

# Via bridge script
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh status
```

---

## Multi-Platform Research Pattern

For comprehensive research, aggregate across multiple platforms:

```bash
# Search Twitter + Reddit + HN simultaneously
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh multi-search "AI agents" twitter,reddit,hackernews

# Get trending across platforms
${CLAUDE_PLUGIN_ROOT}/scripts/opencli-bridge.sh multi-trending twitter,hackernews
```

---

## Integration with Octopus Workflows

### With Discover Phase (flow-discover)

OpenCLI complements the Discover phase by providing **live data** alongside Codex/Gemini analysis:

```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research mode
🔍 Discover Phase + OpenCLI Real-Time Data

Providers:
🔴 Codex CLI - Technical analysis
🟡 Gemini CLI - Ecosystem research
🟢 OpenCLI - Real-time social/web data
🔵 Claude - Strategic synthesis
```

**Workflow:**
1. Run `orchestrate.sh probe` for structured research
2. Supplement with `opencli_search` for live social signals
3. Use `opencli_trending` to identify current buzz
4. Synthesize all sources into recommendation

### With Debate Phase (skill-debate)

Use OpenCLI to inject real-time evidence into debates:

```bash
# Panelist can cite live data
opencli_search(platform: "reddit", query: "React vs Vue 2026 experience reports")
```

---

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| `opencli: command not found` | Not installed | `npm install -g @jackwener/opencli` |
| `Daemon not running` | OpenCLI daemon stopped | `opencli daemon start` |
| `Browser Bridge unavailable` | Chrome extension missing | Install Browser Bridge from GitHub Releases |
| `Timeout` | Platform slow/unreachable | Increase `OPENCLI_TIMEOUT` or try different platform |
| `Rate limited` | Too many requests | Wait 60s, reduce request frequency |

---

## Cost Awareness

- **OpenCLI is free** — no API keys required for basic search/trending
- **Browser Bridge** requires Chrome running (resource overhead)
- **Rate limits** apply per-platform (Twitter stricter than HN)
- **No per-query cost** unlike Codex/Gemini providers

---

## Security Considerations

- URL validation: only HTTPS URLs accepted for `explore`
- Fetched content treated as **untrusted external content**
- API key sanitization in error messages
- No credentials stored or transmitted by the bridge script

---

## Example Usage

### Example 1: Research a Technology Trend

```
User: What are people saying about Claude MCP on Twitter and HN?

Claude:
🟢 OpenCLI Real-Time Search

[Executes: opencli_search(platform: "twitter", query: "Claude MCP")]
[Executes: opencli_search(platform: "hackernews", query: "Claude MCP")]

# Real-Time Findings: Claude MCP

## Twitter Buzz (last 24h)
- 142 mentions, mostly positive
- Key themes: tool integration, custom servers, plugin ecosystem

## Hacker News Discussion
- 3 active threads on front page
- Top comment highlights security concerns with arbitrary tool execution

## Synthesis
The community reception is enthusiastic but security-conscious...
```

### Example 2: URL Deep Dive

```
User: Explore this article and summarize it: https://example.com/deep-article

Claude:
🟢 OpenCLI Content Extraction

[Executes: opencli_fetch(url: "https://example.com/deep-article")]

# Article Summary
[Formatted summary with key points and source attribution]
```
