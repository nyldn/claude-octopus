<p align="center">
  <img src="assets/social-preview.jpg" alt="Claude Octopus - Multi-tentacled orchestrator for Claude Code" width="640">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/Double_Diamond-Design_Thinking-orange" alt="Double Diamond">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-8.2.0-blue" alt="Version 8.2.0">
  <img src="https://img.shields.io/badge/Claude_Code-v2.1.33+-blueviolet" alt="Requires Claude Code v2.1.33+">
</p>

# Claude Octopus

**Multi-AI orchestration plugin for Claude Code** - Run Codex, Gemini, and Claude simultaneously with 29 expert personas, Double Diamond workflows, and 43 specialized skills.

> *Three AI perspectives in the time it takes for one. Structured workflows that actually get followed.*

---

## Install

Inside Claude Code, run:

```
/plugin marketplace add nyldn/claude-octopus
```

Then install:

```
/plugin install claude-octopus@nyldn-plugins
```

Configure your AI providers:

```
/octo:setup
```

The setup wizard checks what you have, shows what's missing, and walks you through it. You only need **one** external provider (Codex or Gemini) - Claude is built-in.

---

## What It Does

### Multi-AI Orchestration

Run Codex, Gemini, and Claude in parallel. Get three independent analyses synthesized into one result.

```
/octo:research OAuth authentication patterns
/octo:debate Redis vs Memcached for session storage
/octo:review this code for security vulnerabilities
```

Each provider brings a different angle: Codex for implementation depth, Gemini for ecosystem breadth, Claude for synthesis. Results come back in 2-5 minutes with a 75% consensus threshold - if the AIs disagree, you see the debate.

Works with 1, 2, or 3 providers. Degrades gracefully.

### 29 Expert Personas

Specialized AI experts that activate automatically based on your request, or can be invoked explicitly.

**Software Engineering** - backend-architect, frontend-developer, cloud-architect, devops-troubleshooter, deployment-engineer, database-architect, security-auditor, performance-engineer, code-reviewer, debugger, incident-responder

**Specialized Development** - ai-engineer, typescript-pro, python-pro, graphql-architect, test-automator, tdd-orchestrator

**Documentation & Communication** - docs-architect, product-writer, academic-writer, exec-communicator, content-analyst

**Research & Strategy** - research-synthesizer, ux-researcher, strategy-analyst, business-analyst

**Creative & Design** - thought-partner, mermaid-expert, context-manager

Personas activate proactively:
```
"I need a security audit of my auth code"   -> security-auditor
"Review my API design"                       -> backend-architect
"Help me write a research paper"             -> academic-writer
```

### Double Diamond Workflows

Proven design methodology (Discover, Define, Develop, Deliver) adapted for AI engineering.

| Phase | Command | Alias | What Happens |
|-------|---------|-------|--------------|
| Discover | `/octo:discover` | `/octo:probe` | Multi-AI research and exploration |
| Define | `/octo:define` | `/octo:grasp` | Requirements clarification with consensus |
| Develop | `/octo:develop` | `/octo:tangle` | Implementation with quality gates |
| Deliver | `/octo:deliver` | `/octo:ink` | Adversarial review and validation |
| **All 4** | `/octo:embrace` | - | Complete lifecycle in one command |

Each phase has quality gates. Sessions persist across context windows. The `.octo/` directory tracks state, issues, and lessons learned.

### Smart Router

Type naturally and Claude Octopus routes to the right workflow:

```
/octo research microservices patterns      -> discover phase
/octo build user authentication            -> develop phase
/octo review this PR                       -> deliver phase
```

Confidence scoring: >80% auto-routes, 70-80% confirms with you, <70% asks for clarification.

---

## All 32 Commands

### Core Workflows
| Command | Description |
|---------|-------------|
| `/octo:embrace` | Full Double Diamond workflow (all 4 phases) |
| `/octo:discover` | Discovery phase - multi-AI research |
| `/octo:define` | Definition phase - requirements and scope |
| `/octo:develop` | Development phase - implementation with quality gates |
| `/octo:deliver` | Delivery phase - review and validation |
| `/octo:research` | Deep research with multi-source synthesis |

### Development
| Command | Description |
|---------|-------------|
| `/octo:tdd` | Test-driven development (red-green-refactor) |
| `/octo:debug` | Systematic debugging with methodical investigation |
| `/octo:review` | Expert code review with security analysis |
| `/octo:security` | OWASP compliance and vulnerability detection |
| `/octo:quick` | Fast execution without full workflow overhead |

### AI & Decisions
| Command | Description |
|---------|-------------|
| `/octo:debate` | Structured three-way AI debate |
| `/octo:loop` | Iterate until exit criteria pass |
| `/octo:brainstorm` | Creative thought partner session |
| `/octo:meta-prompt` | Generate optimized prompts |
| `/octo:multi` | Force multi-provider execution (manual override) |

### Planning & Docs
| Command | Description |
|---------|-------------|
| `/octo:prd` | AI-optimized PRD writing |
| `/octo:prd-score` | Score PRDs against 100-point framework |
| `/octo:plan` | Strategic plan builder (doesn't execute) |
| `/octo:docs` | Export to PPTX, DOCX, PDF |
| `/octo:pipeline` | Content analysis and pattern extraction |
| `/octo:extract` | Design system & product reverse-engineering |

### Project Lifecycle
| Command | Description |
|---------|-------------|
| `/octo:status` | Project progress dashboard |
| `/octo:resume` | Restore context from previous session |
| `/octo:ship` | Finalize with multi-AI validation |
| `/octo:issues` | Cross-session issue tracking |
| `/octo:rollback` | Checkpoint recovery (git tags) |

### Mode & Configuration
| Command | Description |
|---------|-------------|
| `/octo:km` | Toggle Knowledge Work mode |
| `/octo:dev` | Switch to Dev Work mode |
| `/octo:model-config` | Configure AI provider models at runtime |
| `/octo:setup` | Provider setup wizard |
| `/octo:sys-setup` | System configuration status |

### Phase Aliases
| Command | Same as |
|---------|---------|
| `/octo:probe` | `/octo:discover` |
| `/octo:grasp` | `/octo:define` |
| `/octo:tangle` | `/octo:develop` |
| `/octo:ink` | `/octo:deliver` |

---

## 43 Skills

Skills are the capabilities that power commands and personas. They activate automatically - you don't need to invoke them directly.

**Workflows** - flow-discover, flow-define, flow-develop, flow-deliver

**Research & Knowledge** - skill-deep-research, skill-debate, skill-debate-integration, skill-thought-partner, skill-meta-prompt, skill-knowledge-work

**Code Quality** - skill-code-review, skill-quick-review, skill-security-audit, skill-adversarial-security, skill-security-framing, skill-audit

**Development** - skill-tdd, skill-debug, skill-verify, skill-validate, skill-iterative-loop, skill-finish-branch, skill-parallel-agents

**Architecture & Planning** - skill-architecture, skill-prd, skill-writing-plans, skill-decision-support, skill-intent-contract

**Content & Docs** - skill-doc-delivery, skill-content-pipeline, skill-visual-feedback

**Project Lifecycle** - skill-status, skill-issues, skill-rollback, skill-resume, skill-resume-enhanced, skill-ship

**Task & Session** - skill-task-management, skill-task-management-v2, skill-quick

**Mode & Config** - skill-context-detection, sys-configure, extract-skill

---

## Design System Extraction

Reverse-engineer design systems and product architectures:

```
/octo:extract ./my-app                                    # Interactive mode
/octo:extract ./my-app --mode design --storybook true     # Design system with Storybook
/octo:extract ./my-app --depth deep --multi-ai force      # Deep analysis, all providers
/octo:extract https://example.com --mode design           # From live website
```

Extracts design tokens (W3C format), components (React/Vue/Svelte), architecture (service boundaries, API contracts), and features. Outputs JSON, CSS, Markdown, CSV.

---

## Project Lifecycle

Track state across sessions with the `.octo/` directory:

```
.octo/
├── PROJECT.md      # Vision and requirements
├── ROADMAP.md      # Phase breakdown
├── STATE.md        # Current position and history
├── config.json     # Workflow preferences
├── ISSUES.md       # Cross-session issue tracking
└── LESSONS.md      # Lessons learned (preserved across rollbacks)
```

Created automatically on first `/octo:embrace`. Use `/octo:status` to check progress, `/octo:resume` to continue where you left off.

---

## Model Configuration

Configure which AI models power each provider:

```
/octo:model-config
```

Supports runtime model selection with 4-tier precedence:
1. Environment variables (`OCTOPUS_CODEX_MODEL`, `OCTOPUS_GEMINI_MODEL`)
2. Runtime overrides
3. Config file settings
4. Built-in defaults

For premium tasks, complexity-based routing automatically upgrades to Opus 4.6.

---

## Cost Transparency

You see cost estimates **before** execution. Interactive research asks 3 questions (depth, focus, format) then shows exactly what will run and how much it costs.

| Scenario | Time | Est. Cost |
|----------|------|-----------|
| Quick research | 1-2 min | $0.01-0.02 |
| Standard research | 2-3 min | $0.02-0.05 |
| Deep dive | 4-5 min | $0.05-0.10 |
| AI debate | 5-10 min | $0.08-0.15 |
| Code review | 3-5 min | $0.04-0.08 |
| Full workflow | 15-25 min | $0.20-0.40 |

Works without external providers too - you still get 29 personas, all workflows, context-aware intelligence, and every skill. Multi-AI features activate only when providers are available.

---

## Context-Aware Intelligence

Auto-detects Dev vs Knowledge work and adapts behavior.

**Dev mode** (default in code repos): research focuses on libraries and patterns, output is code and tests, review checks security and performance.

**Knowledge mode** (`/octo:km on`): research focuses on market data and strategy, output is PRDs and reports, review checks clarity and evidence.

Auto-detection uses file signatures (`package.json` = dev, business keywords = knowledge). Override with `/octo:km on|off|auto`.

---

## FAQ

**Do I need all three AI providers?** No. You need one external provider (Codex or Gemini). Claude is built-in. Both external providers gives maximum diversity.

**Will this break my existing setup?** No. Only activates with `octo` prefix or `/octo:*` commands. Results stored separately in `~/.claude-octopus/`. Uninstall cleanly.

**Can I use it without external AIs?** Yes. You get all 29 personas, structured workflows, context intelligence, task management, and every skill. Multi-AI features simply won't activate.

**How do I update?** Run `/plugin` > Installed > update, or reinstall:
```
/plugin uninstall claude-octopus@nyldn-plugins
/plugin install claude-octopus@nyldn-plugins
```

---

## Documentation

- [Visual Indicators](docs/VISUAL-INDICATORS.md) - Understanding provider status
- [Command Reference](docs/COMMAND-REFERENCE.md) - All commands in detail
- [Architecture](docs/ARCHITECTURE.md) - How it works internally
- [Plugin Architecture](docs/PLUGIN-ARCHITECTURE.md) - Plugin structure
- [Native Integration](docs/NATIVE-INTEGRATION.md) - Claude Code TaskCreate/TaskUpdate
- [Debug Mode](docs/DEBUG_MODE.md) - Troubleshooting workflows
- [Full Changelog](CHANGELOG.md) - Complete version history

---

## Attribution

- **[wolverin0/claude-skills](https://github.com/wolverin0/claude-skills)** - AI Debate Hub for structured three-way debates. MIT License.
- **[obra/superpowers](https://github.com/obra/superpowers)** - Discipline skills (TDD, debugging, verification) patterns. MIT License.
- **[UK Design Council](https://www.designcouncil.org.uk/our-resources/the-double-diamond/)** - Double Diamond methodology.

---

## Contributing

1. [Report Issues](https://github.com/nyldn/claude-octopus/issues)
2. Submit PRs following existing code style
3. Development: `git clone --recursive https://github.com/nyldn/claude-octopus.git && make test`

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

---

## License

MIT - see [LICENSE](LICENSE)

<p align="center">
  <a href="https://github.com/nyldn">nyldn</a> | MIT License | <a href="https://github.com/nyldn/claude-octopus/issues">Report Issues</a>
</p>
