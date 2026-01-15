# Changelog

All notable changes to Claude Octopus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-15

### Added

#### Double Diamond Methodology
Multi-agent orchestration workflow with octopus-themed commands:
- **probe** - Parallel research from 4 perspectives with AI synthesis (Discover phase)
- **grasp** - Multi-agent consensus building on problem definition (Define phase)
- **tangle** - Enhanced map-reduce with quality gates (Develop phase)
- **ink** - Validation and final deliverable generation (Deliver phase)
- **embrace** - Full 4-phase Double Diamond workflow
- **preflight** - Dependency validation before workflows

#### Intelligent Auto-Routing
Smart task classification routes to appropriate agents:
- **Image generation**: App icons, favicons, diagrams, social media banners, hero images
- **Code review**: Security audits, code analysis, PR reviews
- **Coding**: Implementation, debugging, refactoring
- **Design**: UI/UX analysis, accessibility, component design
- **Research**: Documentation, architecture analysis, best practices
- **Copywriting**: Marketing copy, content generation

#### Nano Banana Prompt Refinement
Intelligent prompt enhancement for image generation:
- Automatic detection of image type (app-icon, social-media, diagram, general)
- Type-specific prompt optimization for better visual results
- Integrated into auto-routing for seamless UX

#### Autonomy Modes
Configurable human oversight levels:
- **autonomous** - Full auto, proceed on failures
- **semi-autonomous** - Pause on quality gate failures (default)
- **supervised** - Human approval after each phase
- **loop-until-approved** - Retry failed tasks until quality gate passes

#### Session Recovery
Resume interrupted workflows:
- Automatic checkpoint after each phase completion
- Session state persisted to JSON
- Resume with `-R` flag from last successful phase

#### Specialized Agent Roles
Role-based agent selection for phases:
- **Architect** - System design and planning (Codex Max)
- **Researcher** - Deep investigation (Gemini Pro)
- **Reviewer** - Code review and validation (Codex Review)
- **Implementer** - Code generation (Codex Max)
- **Synthesizer** - Result aggregation (Gemini Flash)

#### Quality Gates
Configurable quality thresholds:
- Default 75% success threshold (configurable with `-q`)
- Quality gate status: PASSED (>=90%), WARNING (75-89%), FAILED (<75%)
- Loop-until-approved retry logic (up to 3 retries by default)

#### Multi-Agent Orchestration
Core execution patterns:
- **spawn** - Single agent execution
- **fan-out** - Same prompt to all agents
- **map-reduce** - Task decomposition and parallel execution
- **parallel** - JSON-defined task execution

#### Agent Fleet
Premium model defaults (Jan 2026):
- `codex` - GPT-5.1-Codex-Max (premium default)
- `codex-standard` - GPT-5.2-Codex
- `codex-max` - GPT-5.1-Codex-Max
- `codex-mini` - GPT-5.1-Codex-Mini
- `codex-general` - GPT-5.2
- `gemini` - Gemini-3-Pro-Preview
- `gemini-fast` - Gemini-3-Flash-Preview
- `gemini-image` - Gemini-3-Pro-Image-Preview
- `codex-review` - GPT-5.2-Codex (review mode)

#### CLI Options
- `-p, --parallel NUM` - Max parallel agents (default: 3)
- `-t, --timeout SECS` - Timeout per task (default: 300s)
- `-a, --autonomy MODE` - Set autonomy mode
- `-q, --quality NUM` - Quality gate threshold
- `-l, --loop` - Enable loop-until-approved
- `-R, --resume` - Resume interrupted session
- `-v, --verbose` - Verbose output
- `-n, --dry-run` - Show what would be done

#### Documentation
- Comprehensive README with Double Diamond methodology
- Octopus Philosophy section explaining the metaphor
- Troubleshooting guide with witty octopus tips
- ASCII art mascot throughout codebase

### Notes

Initial release as a Claude Code plugin for Design Thinking workflows.
Built with multi-agent orchestration using Codex CLI and Gemini CLI.
