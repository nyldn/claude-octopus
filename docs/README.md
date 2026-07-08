# Documentation Guide

**New here?** Start with the [plugin overview](../.claude-plugin/README.md) for a quick orientation, then come back here for details.

## Core References

- [COMMAND-REFERENCE.md](./COMMAND-REFERENCE.md) — All 47 slash commands with natural-language triggers
- [ARCHITECTURE.md](./ARCHITECTURE.md) — Provider model mapping, 9-provider architecture, execution flow
- [AGENTS.md](./AGENTS.md) — 32 persona agents and 10 native agents
- [PLUGIN-ASSEMBLY-STANDARD.md](./PLUGIN-ASSEMBLY-STANDARD.md) — Structural contract for skills, agents, commands, connectors, and validation

## Setup and Operations

- [IDE-INTEGRATION.md](./IDE-INTEGRATION.md) — MCP server setup for VS Code, Cursor, and other IDEs
- [SCHEDULER.md](./SCHEDULER.md) — Scheduled jobs and daemon management
- [KNOWLEDGE-WORKERS.md](./KNOWLEDGE-WORKERS.md) — Research and strategy-oriented personas

## Provider Configuration

Provider-specific configuration is in `config/providers/`:
- `config/providers/codex/CLAUDE.md` — Codex CLI (OpenAI)
- `config/providers/agy/CLAUDE.md` — Antigravity CLI (Google seat, replaces Gemini CLI)
- `config/providers/claude/CLAUDE.md` — Claude (Anthropic)
- `config/providers/ollama/CLAUDE.md` — Ollama (local LLM)
- `config/providers/copilot/CLAUDE.md` — GitHub Copilot CLI

## Quick Start

Run `/octo:setup` in Claude Code for guided setup, or `/octo:doctor` to diagnose issues.
