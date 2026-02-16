# Claude Octopus

Multi-provider orchestration for Claude Code. Run Codex, Gemini, and Claude in parallel to research, build, review, and debate — with structured workflows that enforce quality gates.

<p align="center">
  <img src="assets/social-preview.jpg" alt="Claude Octopus" width="640">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-8.15.1-blue" alt="Version 8.15.1">
  <img src="https://img.shields.io/badge/Claude_Code-v2.1.34+-blueviolet" alt="Requires Claude Code v2.1.34+">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

---

## Quickstart

**Install** — inside Claude Code or from your terminal:

```bash
/plugin marketplace add https://github.com/nyldn/claude-octopus.git
/plugin install claude-octopus@nyldn-plugins
```

Then run setup:

```
/octo:setup
```

Setup detects installed providers, shows what's missing, and walks you through configuration. You need **zero** external providers to start — Claude is built in. Add Codex or Gemini for multi-AI features.

**Try it now:**

```bash
/octo:research OAuth 2.1 patterns          # Multi-source synthesis
/octo:review                                # Code review with security analysis
/octo:debate monorepo vs microservices      # Three-way AI debate
```

---

## What It Does

Five commands that show the full range:

```bash
/octo:embrace build stripe integration     # Full lifecycle: research -> PRD -> code -> review
/octo:research htmx vs react in 2026       # Triple-perspective synthesis from 3 providers
/octo:tdd create user auth                 # Disciplined red-green-refactor orchestration
/octo:debate monorepo vs microservices     # Formal adversarial debate between AI providers
/octo:deck q3 product strategy             # Brief -> research -> outline gate -> PPTX export
```

Each command orchestrates up to three AI providers, applies quality gates, and produces a deliverable. Here's the full set:

### Core Commands

| Command | What it does |
|---------|-------------|
| `/octo:embrace` | Full 4-phase workflow: discover, define, develop, deliver |
| `/octo:research` | Deep multi-source research with synthesis |
| `/octo:review` | Multi-perspective code review |
| `/octo:tdd` | Test-driven development with red-green-refactor |
| `/octo:debug` | Systematic 4-phase debugging |
| `/octo:security` | OWASP vulnerability scan |
| `/octo:debate` | Structured three-way AI debate |
| `/octo:prd` | AI-optimized PRD with 100-point scoring |
| `/octo:extract` | Reverse-engineer design systems from code or URLs |
| `/octo:deck` | Slide deck generation with outline approval gate |
| `/octo:docs` | Export to PPTX, DOCX, PDF |
| `/octo:schedule` | Scheduled workflow runner with cron, budget gates, kill switches |
| `/octo:brainstorm` | Creative thought partner session |

Don't remember the command name? Just describe what you need:

```
/octo research microservices patterns    -> routes to discover phase
/octo build user authentication          -> routes to develop phase
/octo compare Redis vs DynamoDB          -> routes to debate
```

The smart router parses your intent and selects the right workflow.

[Full command reference (39 commands)](docs/COMMAND-REFERENCE.md)

---

## How It Works

### Three Providers, One Workflow

Claude Octopus coordinates Codex (OpenAI), Gemini (Google), and Claude (Anthropic) across every workflow. Each provider has a distinct role:

| Provider | Role |
|----------|------|
| Codex | Implementation depth — code patterns, technical analysis, architecture |
| Gemini | Ecosystem breadth — alternatives, security review, research synthesis |
| Claude | Orchestration — quality gates, consensus building, final synthesis |

Providers run in parallel for research, sequentially for problem scoping, and adversarially for review. A 75% consensus quality gate prevents questionable work from shipping.

### Double Diamond Phases

Four structured phases adapted from the UK Design Council's methodology:

| Phase | Command | What happens |
|-------|---------|-------------|
| Discover | `/octo:discover` | Multi-AI research and broad exploration |
| Define | `/octo:define` | Requirements clarification with consensus |
| Develop | `/octo:develop` | Implementation with quality gates |
| Deliver | `/octo:deliver` | Adversarial review and go/no-go scoring |

Run phases individually or all four with `/octo:embrace`. Configure autonomy: supervised (approve each phase), semi-autonomous (intervene on failures), or autonomous (run all four).

### 29 Personas

Specialized agents that activate automatically based on your request. When you say "audit my API for vulnerabilities," security-auditor activates. When you say "write a research paper," academic-writer takes over.

Categories: Software Engineering (11), Specialized Development (6), Documentation & Communication (5), Research & Strategy (4), Creative & Design (3).

[Full persona reference](docs/AGENTS.md) | [All 44 skills](docs/COMMAND-REFERENCE.md)

---

## Providers and Cost

### Authentication

| Method | Codex | Gemini | Claude |
|--------|-------|--------|--------|
| OAuth (recommended) | `codex login` — included in ChatGPT subscription | Google account — included in AI subscription | Built into Claude Code |
| API key | `OPENAI_API_KEY` — per-token billing | `GEMINI_API_KEY` — per-token billing | Built into Claude Code |

OAuth users pay nothing beyond their existing subscriptions.

### What Works Without External Providers

Everything except multi-AI features. You get all 29 personas, structured workflows, smart routing, context detection, and every skill. Multi-AI orchestration (parallel analysis, debate, consensus) activates when external providers are configured.

---

## Trust and Safety

**Namespace isolation** — Only `/octo:*` commands and `octo` natural language prefix activate the plugin. Your existing Claude Code setup is untouched.

**Data locations** — Results in `~/.claude-octopus/results/`, logs in `~/.claude-octopus/logs/`, project state in `.octo/`. Nothing hidden.

**No telemetry** — No usage data collected. No phone-home. Fully open source.

**Provider transparency** — Visual indicators (colored dots) show exactly which providers are running and when external APIs are called. You always know what's happening.

**Clean uninstall** — `/plugin uninstall claude-octopus@nyldn-plugins` removes everything. No residual config changes.

---

## FAQ

**Do I need all three AI providers?**
No. One external provider plus Claude gives you multi-AI features. No external providers still gives you personas, workflows, and skills.

**Will this break my existing Claude Code setup?**
No. Activates only with the `octo` prefix. Results stored separately. Uninstalls cleanly.

**What happens if a provider times out?**
The workflow continues with available providers. You'll see the status in the visual indicators.

---

## Documentation

- [Command Reference](docs/COMMAND-REFERENCE.md) — All 39 commands
- [Architecture](docs/ARCHITECTURE.md) — How it works internally
- [Plugin Architecture](docs/PLUGIN-ARCHITECTURE.md) — Plugin structure
- [Agents & Personas](docs/AGENTS.md) — All 29 personas
- [Visual Indicators](docs/VISUAL-INDICATORS.md) — Provider status
- [Debug Mode](docs/DEBUG_MODE.md) — Troubleshooting
- [Changelog](CHANGELOG.md)

---

## Attribution

- **[wolverin0/claude-skills](https://github.com/wolverin0/claude-skills)** — AI Debate Hub. MIT License.
- **[obra/superpowers](https://github.com/obra/superpowers)** — Discipline skills patterns. MIT License.
- **[UK Design Council](https://www.designcouncil.org.uk/our-resources/the-double-diamond/)** — Double Diamond methodology.

---

## Contributing

1. [Report issues](https://github.com/nyldn/claude-octopus/issues)
2. Submit PRs following existing code style
3. `git clone https://github.com/nyldn/claude-octopus.git && make test`

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

---

## License

MIT — see [LICENSE](LICENSE)

<p align="center">
  <a href="https://github.com/nyldn">nyldn</a> | MIT License | <a href="https://github.com/nyldn/claude-octopus/issues">Report Issues</a>
</p>
