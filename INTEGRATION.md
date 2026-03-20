# 🐙🌐 Claude Octopus + OpenCLI Integration

> **Three AI brains + the entire web as your CLI.** This fork integrates [Claude Octopus](https://github.com/nyldn/claude-octopus) with [OpenCLI](https://github.com/jackwener/opencli), connecting Octopus's multi-AI orchestration to real-time web data and desktop app control.

## What Is This?

| Component | Role |
|-----------|------|
| **Claude Octopus** | Multi-AI orchestrator — coordinates Claude, Codex, and Gemini with structured workflows, quality gates, and 32 specialized personas |
| **OpenCLI** | Universal CLI Hub — turns any website (Twitter, Reddit, HN, YouTube) or desktop app (Cursor, ChatGPT, Notion) into a command-line interface |
| **Integration** | OpenCLI becomes Octopus's 6th provider, giving AI workflows access to live web data and desktop app control |

## Why This Matters

Before: Octopus's `/octo:research` could only use AI models to generate answers from training data.

After: `/octo:research` can pull **live trending posts from Twitter**, **real Reddit threads**, **latest HN discussions** — and feed them into the multi-AI consensus pipeline.

```
🐙 Octopus Workflow (Discover → Define → Develop → Deliver)
    ├── Claude    (synthesis + judgment)
    ├── Codex     (deep implementation)
    ├── Gemini    (ecosystem breadth)
    └── 🌐 OpenCLI (live web data + desktop control)  ← NEW
```

## Quick Start

### 1. Install Claude Octopus
```bash
claude plugin marketplace add https://github.com/nyldn/claude-octopus.git
claude plugin install octo@nyldn-plugins
```

### 2. Install OpenCLI
```bash
npm install -g opencli
opencli setup  # Installs Browser Bridge extension
```

### 3. Verify Integration
```bash
/octo:setup  # Inside Claude Code — should detect OpenCLI as a provider
```

## New MCP Tools

The integration adds 6 new tools to the Octopus MCP Server:

| MCP Tool | Description | Example |
|----------|-------------|---------|
| `opencli_search` | Search any web platform | Search Twitter for "AI agents" |
| `opencli_trending` | Get trending content | HN frontpage, Reddit hot posts |
| `opencli_fetch` | Run any OpenCLI command | Get user profile, read thread |
| `opencli_explore` | Discover website APIs | Reverse-engineer any site's API |
| `opencli_desktop` | Control desktop apps | Screenshot Cursor, extract ChatGPT code |
| `opencli_status` | Check OpenCLI health | Verify Browser Bridge is running |

## New Workflows

### Research with Live Data
```bash
/octo:research "AI agent frameworks 2026"
# Octopus now pulls:
# - Twitter trending discussions via OpenCLI
# - Reddit r/MachineLearning posts via OpenCLI  
# - HN frontpage via OpenCLI
# - Plus Claude, Codex, Gemini analysis
```

### Debate with Real Evidence
```bash
/octo:debate "React vs htmx for 2026 projects"
# Each AI model gets live community sentiment from
# Twitter, Reddit, and HN to ground their arguments
```

### Desktop App Orchestration
```bash
/octo:auto "extract and review all code from my ChatGPT conversation"
# Uses opencli_desktop to control ChatGPT app
# Then feeds extracted code through Octopus review pipeline
```

## Architecture

```
Claude Code Session
├── Octopus Plugin (.claude-plugin/)
│   ├── commands/          — 39 slash commands (/octo:*)
│   ├── scripts/
│   │   ├── orchestrate.sh — Core 943KB orchestration engine
│   │   ├── opencli-bridge.sh — NEW: Bridge to OpenCLI
│   │   └── provider-router.sh — Latency-based routing
│   ├── config/providers/
│   │   ├── claude/
│   │   ├── codex/
│   │   ├── gemini/
│   │   └── opencli/       — NEW: OpenCLI provider config
│   └── mcp-server/
│       └── src/index.ts   — MCP tools (+ 6 new opencli_* tools)
│
└── OpenCLI (npm global)
    ├── Browser Bridge Extension (Chrome)
    ├── src/clis/           — Platform adapters (Twitter, Reddit, etc.)
    └── Desktop adapters    — Electron app control
```

## Files Changed

| File | Change |
|------|--------|
| `config/providers/opencli/CLAUDE.md` | **NEW** — OpenCLI provider configuration |
| `scripts/opencli-bridge.sh` | **NEW** — Bridge script connecting Octopus ↔ OpenCLI |
| `mcp-server/src/index.ts` | **MODIFIED** — Added 6 OpenCLI MCP tools |

## Prerequisites

- Claude Code with Octopus plugin installed
- Node.js >= 20.0.0
- Chrome with Browser Bridge extension (installed via `opencli setup`)
- OpenCLI installed globally (`npm install -g opencli`)

## Supported Platforms (via OpenCLI)

**Social**: Twitter/X, Reddit, Hacker News, Bilibili, 小红书, V2EX, Zhihu  
**Media**: YouTube, Spotify, 网易云音乐  
**Dev**: GitHub (via `gh`), Obsidian, Docker, kubectl  
**Desktop**: Cursor, Antigravity, ChatGPT, Notion, Discord, WeChat  
**Finance**: 雪球, Bloomberg  
**Shopping**: Coupang, 超学习  

## License

- Claude Octopus: [MIT](https://github.com/nyldn/claude-octopus/blob/main/LICENSE)  
- OpenCLI: [Apache-2.0](https://github.com/jackwener/opencli/blob/main/LICENSE)

## Attribution

- [nyldn/claude-octopus](https://github.com/nyldn/claude-octopus) — Multi-tentacled orchestrator for Claude Code
- [jackwener/opencli](https://github.com/jackwener/opencli) — Make Any Website & Tool Your CLI
