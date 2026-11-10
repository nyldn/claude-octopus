# Documentation guide

**New here?** Start with the [plugin overview](../.claude-plugin/README.md) for a quick orientation, then come back here for details.

## Commands and workflows

- [COMMAND-REFERENCE.md](./COMMAND-REFERENCE.md) — All 56 slash commands with natural-language triggers
- [REFINEMENT.md](./REFINEMENT.md): `/octo:refine` rubric scoring with Claude and Codex, review-only mode, and budget controls
- [CLAUDE-NATIVE-INTEGRATION.md](./CLAUDE-NATIVE-INTEGRATION.md): Worker advisors, native evals, hook failure policy, subagent controls and dynamic workflow handoffs
- [WORKFLOW-METHODS.md](./WORKFLOW-METHODS.md): Architecture, TDD, debugging, decisions, prototypes, routing previews, and resumable setup
- [ARCHITECTURE.md](./ARCHITECTURE.md) — Provider model mapping, execution contracts, and workflow flow
- [V10-MIGRATION.md](./V10-MIGRATION.md) — V10 compatibility, verification, and rollback guidance
- [AGENTS.md](./AGENTS.md) — 31 persona agents and 10 native agents
- [PLUGIN-ASSEMBLY-STANDARD.md](./PLUGIN-ASSEMBLY-STANDARD.md) — Structural contract for skills, agents, commands, connectors, and validation

## Setup and operations

- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md): Provider diagnostics, plugin uninstall, and retained-data review
- [IDE-INTEGRATION.md](./IDE-INTEGRATION.md) — MCP server setup for VS Code, Cursor, and other IDEs
- [PLUGIN-COMPATIBILITY.md](./PLUGIN-COMPATIBILITY.md) — Claude Code and Codex packaging, invocation, and validation
- [MIGRATING-V11.md](./MIGRATING-V11.md) — Required project roots and stricter routing/review contracts
- [SCHEDULER.md](./SCHEDULER.md) — Scheduled jobs and daemon management
- [KNOWLEDGE-WORKERS.md](./KNOWLEDGE-WORKERS.md) — Research and strategy-oriented personas
- [RESEARCH-EVIDENCE.md](./RESEARCH-EVIDENCE.md) — Resumable runs, source provenance, verification, and safe fetching

## Contributors and maintainers

- [CONTRIBUTING.md](CONTRIBUTING.md): Checkout, source edits, checks and PRs
- [REPOSITORY.md](REPOSITORY.md): Directory ownership, skill sources and generated artifacts
- [Script index](../scripts/README.md): Runtime entry points, helpers, generators and release tools
- [DEVELOPER.md](DEVELOPER.md): Workflow contracts and implementation conventions
- [Test guide](../tests/README.md): Affected, quick, full and live test tiers
- [Release checklist](../RELEASING.md): Versioning, review, CI and publication
- [MAINTAINER-AUTOMATION.md](MAINTAINER-AUTOMATION.md): Proposed queue and release automation

## Provider configuration

Provider-specific configuration is in `config/providers/`:
- `config/providers/codex/CLAUDE.md` — Codex CLI (OpenAI)
- `config/providers/agy/CLAUDE.md` — Antigravity CLI
- `config/providers/claude/CLAUDE.md` — Claude (Anthropic)
- `config/providers/ollama/CLAUDE.md` — Ollama (local LLM)
- `config/providers/copilot/CLAUDE.md` — GitHub Copilot CLI

## Quick start

Run `/octo:setup` in Claude Code. It shows one shared provider-readiness
summary, lets you start with Claude alone or configure one additional provider,
and finishes with a local no-billing verification. Optional developer tools,
model tuning, and automation stay under Advanced setup.

Rerun `/octo:setup` after an interruption to resume
the recorded flow. Setup rechecks readiness and saved preferences before
reporting completion. A changed installation path creates a separate receipt.
See [workflow methods](WORKFLOW-METHODS.md) for the setup contract.

After setup, the three useful entry points are:

- `/octo:auto` — route a task
- `/octo:skill-doctor` — diagnose Octopus skills inside Claude Code
- `/octo:setup` — change setup choices

For shell-level environment diagnostics, run `octopus doctor`.
