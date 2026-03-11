# Documentation Guide

Start here if you are not sure which doc you need.

## Core References

- [COMMAND-REFERENCE.md](./COMMAND-REFERENCE.md) - Primary command guide, natural-language triggers, and visual indicators
- [CLI-REFERENCE.md](./CLI-REFERENCE.md) - Direct `orchestrate.sh` usage for automation and CI
- [AGENTS.md](./AGENTS.md) - Persona and tentacle catalog
- [KNOWLEDGE-WORKERS.md](./KNOWLEDGE-WORKERS.md) - Research and strategy-oriented agents

## Setup and Operations

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Provider model mapping and workflow execution flow
- [IDE-INTEGRATION.md](./IDE-INTEGRATION.md) - IDE and MCP integration
- [SCHEDULER.md](./SCHEDULER.md) - Scheduled jobs and daemon management
- [SANDBOX-CONFIGURATION.md](./SANDBOX-CONFIGURATION.md) - Codex sandbox setup
- [FACTORY-AI.md](./FACTORY-AI.md) - Factory AI compatibility notes
- [CLI-REFERENCE.md](./CLI-REFERENCE.md#execution-modes) - Async mode, tmux visualization, and direct CLI operations
- [CLI-REFERENCE.md](./CLI-REFERENCE.md#debug-mode) - Debug flag behavior and troubleshooting

## Contributor and Internal Docs

- [PLUGIN-ARCHITECTURE.md](./PLUGIN-ARCHITECTURE.md) - Internal plugin structure and extension points
- [INTERACTIVE_QUESTIONS_GUIDE.md](./INTERACTIVE_QUESTIONS_GUIDE.md) - Command authoring guidance
- [architecture/auto-detection-engine.md](./architecture/auto-detection-engine.md) - Detection engine internals
- [RELEASE_AUTOMATION.md](./RELEASE_AUTOMATION.md) - Release process

## Recommended Companion Skills

- `webapp-testing` - UI validation after Octopus generates or refactors app code
- `frontend-design` - Stronger visual design direction for React and Tailwind work
- `skill-creator` - Create your own domain-specific wrappers around Octopus workflows
- `mcp-builder` - Connect Octopus workflows to external APIs and services

These are companion tools for Claude itself, not for the external Codex or Gemini processes spawned by Octopus.

## Specialized Guides

- [NATIVE-INTEGRATION.md](./NATIVE-INTEGRATION.md) - Native task and state integration
- [PDF_PAGE_SELECTION.md](./PDF_PAGE_SELECTION.md) - PDF-specific extraction behavior

## Project Maintenance

- [FEATURE-GAP.md](./FEATURE-GAP.md) - Claude Code feature adoption tracker
- [PLUGIN-ARCHITECTURE.md](./PLUGIN-ARCHITECTURE.md) - Internal structure, extension points, and command-prefix safeguards
- [monthly-agent-review.md](./monthly-agent-review.md) - Monthly review checklist
