# Changelog

All notable changes to Claude Octopus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [7.7.0] - 2026-01-19

### Added
- **Standard phase names**: Renamed to Discover/Define/Develop/Deliver (from probe/grasp/tangle/ink aliases)
- **Skill commands**: 12 new skill commands (`/co:debate`, `/co:review`, `/co:research`, `/co:security`, `/co:debug`, `/co:tdd`, `/co:docs`, `/co:embrace`, `/co:discover`, `/co:define`, `/co:develop`, `/co:deliver`)
- **Enhanced workflow skills**: Natural language workflow wrappers for Double Diamond methodology
- **Integrated parallel-agents**: Consolidated parallel-agents functionality into core plugin

### Changed
- Updated documentation to reflect standard phase names
- Improved natural language triggers for all workflows
- Enhanced visual indicators section in parallel-agents skill

### Fixed
- Removed legacy parallel-agents standalone directory

## [7.6.0] - 2025-12-15

### Added
- **Shorter namespace**: Changed from `/claude-octopus:` to `/co:` (60% shorter!)
- **Two-Mode System**: Dev Work mode and Knowledge Work mode
  - `/co:dev` - Switch to Dev Work mode (code, test, debug)
  - `/co:km` - Toggle Knowledge Work mode (research, strategy, UX)
  - Mode-aware debates and document exports
- **Better discoverability**: All commands appear in autocomplete
- **Natural language mode switching**: "Switch to dev mode" or "Switch to knowledge mode"

### Changed
- Skills now accessible as commands via autocomplete
- Improved command organization with shortcuts (`/co:setup`, `/co:update`)
- Natural language triggers remain active alongside command shortcuts

### Documentation
- Added [Migration Guide](docs/MIGRATION-v7.5.md)
- Added [Command Reference](docs/COMMAND-REFERENCE.md)

## [7.4.0] - 2025-11-20

### Added
- **Visual Indicators**: Know which AI is responding
  - 🐙 Parallel Mode (Multiple CLIs orchestrated)
  - 🔴 Codex CLI (OpenAI Codex - your API key)
  - 🟡 Gemini CLI (Google Gemini - your API key)
  - 🔵 Claude Subagent (built-in, no extra cost)
- **Natural Language Workflow Triggers**: No more CLI commands required
  - "research X" → Discover workflow
  - "define requirements for X" → Define workflow
  - "build X" → Develop workflow
  - "review X" → Deliver workflow
- **Hook-based visual indicators**: PreToolUse hooks automatically show indicators
- **Debate skill via natural language**: "run a debate about X" triggers AI Debate Hub

### Changed
- Enhanced parallel-agents.md with visual indicators section
- Improved cost transparency with visual feedback

### Documentation
- Added [Visual Indicators Guide](docs/VISUAL-INDICATORS.md)
- Added [Triggers Guide](docs/TRIGGERS.md)
- Complete cost breakdown by provider

## Earlier Versions

### [7.3.0] - Quality Gates & Consensus
- Added 75% consensus threshold for quality gates
- Enhanced map-reduce with validation in tangle phase
- Improved result synthesis in ink phase

### [7.2.0] - Provider-Aware Routing
- Intelligent routing based on subscription tiers
- Cost optimization strategies (balanced, cost-first, quality-first)
- OpenRouter fallback support (400+ models)
- Provider configuration management

### [7.1.0] - Double Diamond Workflows
- Discover (probe) phase for research
- Define (grasp) phase for consensus building
- Develop (tangle) phase for implementation
- Deliver (ink) phase for validation
- Embrace command for full 4-phase workflow

### [7.0.0] - Initial Release
- Multi-AI orchestration (Codex + Gemini + Claude)
- Crossfire adversarial review (grapple, squeeze)
- AI Debate Hub integration
- Smart auto-routing
- Companion skills (architecture, code review, security audit, etc.)

---

## Version Naming

- **Major versions** (7.x.0): Breaking changes, new core features
- **Minor versions** (x.7.x): New features, enhancements
- **Patch versions** (x.x.7): Bug fixes, documentation updates

[7.7.0]: https://github.com/nyldn/claude-octopus/compare/v7.6.0...v7.7.0
[7.6.0]: https://github.com/nyldn/claude-octopus/compare/v7.4.0...v7.6.0
[7.4.0]: https://github.com/nyldn/claude-octopus/compare/v7.3.0...v7.4.0
