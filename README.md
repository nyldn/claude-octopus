# Claude Octopus

A Claude Code plugin that turns one model into three. Orchestrates Codex, Gemini, and Claude with distinct roles, adversarial review, and consensus gates — so no single model's blind spots slip through.

<p align="center">
  <img src="assets/social-preview.jpg" alt="Claude Octopus" width="640">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-8.30.0-blue" alt="Version 8.30.0">
  <img src="https://img.shields.io/badge/Claude_Code-v2.1.50+-blueviolet" alt="Requires Claude Code v2.1.50+">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

**Three brains, one workflow.** Other multi-AI tools run providers in parallel and hand you three answers. Octopus assigns each model a distinct role — Codex for implementation depth, Gemini for ecosystem breadth, Claude for synthesis — then enforces a 75% consensus gate before anything ships. Disagreements get caught, not ignored.

**Spec in, software out.** Dark Factory mode takes a spec and autonomously runs the full pipeline — research, define, develop, deliver — with holdout testing and satisfaction scoring. You review the output, not every step.

**Methodology, not just machinery.** Built on the Double Diamond framework, every task moves through four structured phases: discover, define, develop, deliver. Quality gates between phases mean sloppy work can't advance. Other orchestrators give you infrastructure to build workflows on — Octopus gives you the workflows.

**31 specialized personas, 39 commands.** Not generic agents. A security-auditor that thinks in OWASP. A backend-architect that designs APIs. A tdd-orchestrator that enforces red-green-refactor. Personas activate automatically based on what you ask — say "audit my API" and the right expert shows up. Don't know the command name? Just say what you need — the smart router figures it out.

**Works with just Claude. Scales to three.** Zero external providers needed to start. You get every persona, every workflow, every skill on day one. Add Codex or Gemini and multi-AI orchestration lights up — parallel research, adversarial debate, cross-model review.

**Full cost transparency.** Visual indicators show exactly which providers are active and whose billing they hit. Smart cost routing picks the cheapest provider that can handle the job. No hidden API calls, no surprise charges.

---

## Recent Updates

| Version | What shipped |
|---------|-------------|
| **8.30** | **Agent continuation** — iterative retries resume where they left off instead of starting over |
| **8.27** | **Context compaction survival** — enforcement rules persist through conversation compression |
| **8.26** | **Worktree isolation** — agents work in isolated git worktrees; 8 new configurable settings |
| **8.25** | **Dark Factory mode** — autonomous spec-to-software pipeline with holdout testing and satisfaction scoring |
| **8.23** | **OpenClaw admin + Doctor diagnostics** — `/octo:claw` for host management, `/octo:doctor` for 9-category health checks |
| **8.22** | **OpenClaw compatibility layer** — MCP server exposes 10 Octopus tools to any MCP-compatible client |
| **8.20** | **Provider intelligence** — Bayesian trust scoring, smart cost routing, capability matching |
| **8.18** | **Sentinel + Team of Teams** — GitHub-aware work monitor, parallel multi-instance orchestration with dependency waves |

[Full changelog](CHANGELOG.md)

---

## Quickstart

**Install from Claude Code:**

```
/plugin marketplace add https://github.com/nyldn/claude-octopus.git
/plugin install claude-octopus@nyldn-plugins
```

**Or from your terminal:**

```bash
claude -p "/plugin marketplace add https://github.com/nyldn/claude-octopus.git"
claude -p "/plugin install claude-octopus@nyldn-plugins"
```

Then run setup:

```
/octo:setup
```

Setup detects installed providers, shows what's missing, and walks you through configuration. You need **zero** external providers to start — Claude is built in. Add Codex or Gemini for multi-AI features.

---

## Top 8 Tentacles

Eight commands — one per arm. Each orchestrates up to three AI providers, applies quality gates, and produces a deliverable.

```bash
/octo:embrace build stripe integration     # Full lifecycle: research → define → develop → deliver
/octo:factory "build a CLI that converts CSV to JSON"  # Autonomous pipeline — spec in, software out
/octo:debate monorepo vs microservices     # Structured three-way AI debate with consensus
/octo:research htmx vs react in 2026       # Multi-source synthesis from three AI providers
/octo:review                                # Code review with security + 4x10 scoring
/octo:tdd create user auth                 # Red-green-refactor with test discipline
/octo:security                              # OWASP vulnerability scan + remediation
/octo:prd mobile checkout redesign          # AI-optimized PRD with 100-point scoring
```

| Command | What it does |
|---------|-------------|
| `/octo:embrace` | Full 4-phase workflow: discover, define, develop, deliver |
| `/octo:factory` | Dark Factory — autonomous spec-to-software pipeline with holdout testing |
| `/octo:debate` | Structured three-way AI debate with consensus scoring |
| `/octo:research` | Deep multi-source research with synthesis |
| `/octo:review` | Multi-perspective code review with 4-dimension scoring |
| `/octo:tdd` | Test-driven development with red-green-refactor |
| `/octo:security` | OWASP vulnerability scan and remediation |
| `/octo:prd` | AI-optimized PRD with 100-point scoring |

Plus 31 more: debug, extract, deck, docs, schedule, parallel, sentinel, brainstorm, claw, doctor, and [the full set](docs/COMMAND-REFERENCE.md).

Don't remember the command name? Just describe what you need:

```
/octo research microservices patterns    -> routes to discover phase
/octo build user authentication          -> routes to develop phase
/octo compare Redis vs DynamoDB          -> routes to debate
```

The smart router parses your intent and selects the right workflow.

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

### 31 Personas

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

Everything except multi-AI features. You get all 31 personas, structured workflows, smart routing, context detection, and every skill. Multi-AI orchestration (parallel analysis, debate, consensus) activates when external providers are configured.

---

## Trust and Safety

**Namespace isolation** — Only `/octo:*` commands and `octo` natural language prefix activate the plugin. Your existing Claude Code setup is untouched.

**Data locations** — Results in `~/.claude-octopus/results/`, logs in `~/.claude-octopus/logs/`, project state in `.octo/`. Nothing hidden.

**No telemetry** — No usage data collected. No phone-home. Fully open source.

**Provider transparency** — Visual indicators (colored dots) show exactly which providers are running and when external APIs are called. You always know what's happening.

**Clean uninstall** — `/plugin uninstall claude-octopus@nyldn-plugins` removes everything. If you see a scope error, add `--scope project`. No residual config changes.

---

## OpenClaw Compatibility

Claude Octopus ships with a compatibility layer for [OpenClaw](https://github.com/openclaw/openclaw), the open-source AI assistant framework. This lets you expose Octopus workflows to messaging platforms (Telegram, Discord, Signal, WhatsApp) without modifying the Claude Code plugin.

### Architecture

```
Claude Code Plugin (unchanged)
  └── .mcp.json ─── MCP Server ─── orchestrate.sh
                                        ↑
OpenClaw Extension ─────────────────────┘
```

Three components, zero changes to the core plugin:

| Component | Location | Purpose |
|-----------|----------|---------|
| MCP Server | `mcp-server/` | Exposes 10 Octopus tools via Model Context Protocol |
| OpenClaw Extension | `openclaw/` | Wraps workflows for OpenClaw's extension API |
| Skill Schema | `mcp-server/src/schema/skill-schema.json` | Universal skill metadata format |

### MCP Server

The MCP server auto-starts when the plugin is enabled (via `.mcp.json`). It exposes:

- `octopus_discover`, `octopus_define`, `octopus_develop`, `octopus_deliver` — Individual phases
- `octopus_embrace` — Full Double Diamond workflow
- `octopus_debate`, `octopus_review`, `octopus_security` — Specialized workflows
- `octopus_list_skills`, `octopus_status` — Introspection

Any MCP-compatible client can connect to the server.

### OpenClaw Extension

Install in an OpenClaw instance from git:

```bash
npm install github:nyldn/claude-octopus#main --prefix openclaw
```

Or clone and link locally:

```bash
cd openclaw && npm install && npm run build
```

The extension registers as an OpenClaw plugin with configurable workflows, autonomy modes, and Claude Code path resolution.

### Build & Validate

```bash
./scripts/build-openclaw.sh          # Regenerate skill registry from frontmatter
./scripts/build-openclaw.sh --check  # CI mode — exits non-zero if out of sync
./tests/validate-openclaw.sh         # 13-check validation suite
```

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
- [Agents & Personas](docs/AGENTS.md) — All 31 personas
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
