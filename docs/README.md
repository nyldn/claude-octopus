# Documentation Guide

**New here?** Start with the [plugin overview](../.claude-plugin/README.md) for a quick orientation, then come back here for details.

## Core References

- [COMMAND-REFERENCE.md](./COMMAND-REFERENCE.md) — All 53 slash commands with natural-language triggers
- [ARCHITECTURE.md](./ARCHITECTURE.md) — Provider model mapping, execution contracts, and workflow flow
- [V10-MIGRATION.md](./V10-MIGRATION.md) — V10 compatibility, verification, and rollback guidance
- [AGENTS.md](./AGENTS.md) — 31 persona agents and 10 native agents
- [PLUGIN-ASSEMBLY-STANDARD.md](./PLUGIN-ASSEMBLY-STANDARD.md) — Structural contract for skills, agents, commands, connectors, and validation

## Setup and Operations

- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md): Provider diagnostics, plugin uninstall, and retained-data review
- [IDE-INTEGRATION.md](./IDE-INTEGRATION.md) — MCP server setup for VS Code, Cursor, and other IDEs
- [PLUGIN-COMPATIBILITY.md](./PLUGIN-COMPATIBILITY.md) — Claude Code and Codex packaging, invocation, and validation
- [MIGRATING-V11.md](./MIGRATING-V11.md) — Required project roots and stricter routing/review contracts
- [SCHEDULER.md](./SCHEDULER.md) — Scheduled jobs and daemon management
- [KNOWLEDGE-WORKERS.md](./KNOWLEDGE-WORKERS.md) — Research and strategy-oriented personas

## Provider Configuration

Provider-specific configuration is in `config/providers/`:
- `config/providers/codex/CLAUDE.md` — Codex CLI (OpenAI)
- `config/providers/agy/CLAUDE.md` — Antigravity CLI
- `config/providers/claude/CLAUDE.md` — Claude (Anthropic)
- `config/providers/ollama/CLAUDE.md` — Ollama (local LLM)
- `config/providers/copilot/CLAUDE.md` — GitHub Copilot CLI

## Quick Start

Run `/octo:setup` in Claude Code. It shows one shared provider-readiness
summary, lets you start with Claude alone or configure one additional provider,
and finishes with a local no-billing verification. Optional developer tools,
model tuning, and automation stay under Advanced setup.

After setup, the three useful entry points are:

- `/octo:auto` — route a task
- `/octo:skill-doctor` — diagnose Octopus skills inside Claude Code
- `/octo:setup` — change setup choices

For shell-level environment diagnostics, run `octopus doctor`.
