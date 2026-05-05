# Copilot Instructions for Claude Octopus

This repository is a Claude Code plugin that orchestrates multiple AI providers
(Codex, Gemini, Claude, Perplexity, OpenRouter, and optionally Ollama) through
structured Double Diamond workflows.

## Key Architecture

- `scripts/orchestrate.sh` — Main orchestration entry point (~5K lines + ~22K in scripts/lib/)
- `scripts/lib/` — Modular libraries (providers, doctor, model-resolver, dispatch)
- `.claude/skills/` — Skill definitions (52 skills)
- `.claude/commands/` — Slash commands (48 commands)
- `.claude/agents/` — Subagent definitions (10 agents)
- `mcp-server/` — MCP server adapter (bridges MCP clients to orchestrate.sh)
- `openclaw/` — OpenClaw extension adapter

## Conventions

- Shell scripts use `set -euo pipefail` and bash 3.x compatibility (no associative arrays)
- Tests are in `tests/unit/` using a custom `test-framework.sh` (test_case/test_pass/test_fail)
- All provider detection is graceful — missing providers are silently skipped
- Version bumps require core release files and public adapter manifests updated together: package.json, .claude-plugin/plugin.json, .claude-plugin/marketplace.json, .codex-plugin/plugin.json, .cursor-plugin/plugin.json, .factory-plugin/plugin.json, .factory-plugin/marketplace.json, README.md, CHANGELOG.md

## Testing

Run the pre-push test suite: `bash tests/run-pre-push.sh`
Run a single test: `bash tests/unit/test-<name>.sh`
