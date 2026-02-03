<p align="center">
  <img src="assets/social-preview.jpg" alt="Claude Octopus - Multi-tentacled orchestrator for Claude Code" width="640">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/Double_Diamond-Design_Thinking-orange" alt="Double Diamond">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-7.23.0-blue" alt="Version 7.23.0">
  <img src="https://img.shields.io/badge/Claude_Code-v2.1.20+-blueviolet" alt="Requires Claude Code v2.1.20+">
</p>

# Claude Octopus

**Your complete AI engineering platform for Claude Code** - Multi-AI orchestration, 29 specialized expert personas, proven workflows, design system extraction, and 40 battle-tested skills.

> *Transform Claude Code into a full AI engineering team with diverse perspectives, specialized expertise, and structured methodologies.*

---

## What Is Claude Octopus?

Claude Octopus is the **most comprehensive plugin for Claude Code**, combining:

### 🐙 **Multi-AI Orchestration**
Run Codex, Gemini, and Claude **simultaneously** with automatic synthesis - get 3 AI perspectives in the time it takes for 1.

### 🎯 **29 Expert AI Personas**
Access specialized experts: Backend Architect, Frontend Developer, Security Auditor, Cloud Architect, Performance Engineer, UX Researcher, Academic Writer, and 22 more.

### 📋 **Proven Methodologies**
Double Diamond workflows (Discover → Define → Develop → Deliver), Test-Driven Development, systematic debugging, and adversarial security auditing.

### 🎨 **Design System & Product Extraction**
Reverse-engineer design systems and product architectures from codebases or URLs. Extract design tokens, components, APIs, and generate comprehensive documentation.

### ⚡ **40 Specialized Skills**
From multi-AI research to PRD writing, code review to content analysis, debate facilitation to document delivery, design system extraction, and project lifecycle management.

**Bottom line:** Stop juggling multiple AI tools and workflows. Claude Octopus gives you everything in one integrated platform.

---

## Quick Start

### Step 1: Install (30 seconds)

```
/plugin marketplace add https://github.com/nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

### Step 2: Configure Providers (2-5 minutes)

```
/octo:setup
```

This wizard helps you set up Codex and/or Gemini (you only need ONE). Fully guided, won't duplicate existing installs.

### Step 3: Start Using

**Multi-AI research:**
```
octo research OAuth authentication patterns
```

**Get expert help:**
```
I need a cloud architect to review my AWS infrastructure
```

**Run workflows:**
```
octo build a user authentication system
```

That's it. You now have a complete AI engineering platform.

---

## 🌟 Major Features

### 1. Multi-AI Parallel Execution

**The core capability**: Run multiple AI models simultaneously, then synthesize their perspectives.

**What you get:**
- **3 AIs analyzing in parallel** - Results in 2-5 minutes (vs 6-15 sequential)
- **Diverse viewpoints** - Technical (Codex) + Strategic (Gemini) + Synthesis (Claude)
- **Quality gates** - 75% consensus required (if 2 of 3 disagree, you see the debate)
- **Cost transparency** - See estimates BEFORE execution with provider availability status

**Examples:**
```bash
/octo:embrace [prompt]             # Full Double Diamond workflow (all 4 phases)
/octo:debate Redis vs Memcached             # Structured 3-way debate
/octo:multi analyze this codebase          # Force multi-AI mode (manual override)
/octo:research microservices patterns        # Multi-AI research
/octo:build user authentication system       # Multi-approach implementation
/octo:review this code for security         # Adversarial quality review
```

**Key capabilities:**
- **Auto-detection** - Skills automatically trigger multi-AI when beneficial
- **Manual override** - Use `/octo:multi` to force multi-AI execution for any task
- **Graceful degradation** - Works with 1, 2, or 3 providers (adapts to availability)

---

### 2. 29 Expert AI Personas

Access specialized AI experts trained for specific domains. Use them individually or let Claude Octopus route to the right expert automatically.

#### Software Engineering (11 experts)

- **backend-architect** - Scalable API design, microservices, distributed systems (REST/GraphQL/gRPC)
- **frontend-developer** - React 19, Next.js 15, responsive layouts, state management
- **cloud-architect** - AWS/Azure/GCP, IaC (Terraform/CDK), FinOps cost optimization
- **devops-troubleshooter** - Incident response, Kubernetes debugging, log analysis
- **deployment-engineer** - CI/CD pipelines, GitOps (ArgoCD/Flux), zero-downtime deployments
- **database-architect** - Data layer design, SQL/NoSQL selection, schema modeling
- **security-auditor** - DevSecOps, OWASP compliance, threat modeling, OAuth2/OIDC
- **performance-engineer** - OpenTelemetry, distributed tracing, caching, Core Web Vitals
- **code-reviewer** - AI-powered code analysis, security scanning, production reliability
- **debugger** - Error investigation, test failures, systematic problem-solving
- **incident-responder** - SRE incident management, blameless post-mortems, error budgets

#### Specialized Development (6 experts)

- **ai-engineer** - LLM applications, RAG systems, vector search, agent orchestration
- **typescript-pro** - Advanced types, generics, strict type safety, enterprise patterns
- **python-pro** - Python 3.12+, async, FastAPI, uv/ruff/pydantic ecosystem
- **graphql-architect** - GraphQL federation, performance optimization, real-time systems
- **test-automator** - AI-powered test automation, self-healing tests, CI/CD integration
- **tdd-orchestrator** - Test-driven development discipline, red-green-refactor workflows

#### Documentation & Communication (5 experts)

- **docs-architect** - Technical documentation, architecture guides, long-form manuals
- **product-writer** - AI-optimized PRDs, user stories, acceptance criteria
- **academic-writer** - Research papers, grant proposals, scholarly communication
- **exec-communicator** - Board presentations, C-suite reports, pyramid principle
- **content-analyst** - Content deconstruction, pattern extraction, effectiveness analysis

#### Research & Strategy (4 experts)

- **research-synthesizer** - Literature review, multi-source synthesis, research gaps
- **ux-researcher** - User research, journey mapping, persona creation, usability
- **strategy-analyst** - Market analysis, competitive intelligence, Porter's Five Forces
- **business-analyst** - KPI frameworks, predictive models, strategic recommendations

#### Creative & Design (3 experts)

- **thought-partner** - Creative collaboration, structured questioning, insight discovery
- **mermaid-expert** - Flowcharts, sequence diagrams, ERDs, architecture visualizations
- **context-manager** - AI context engineering, vector databases, knowledge graphs

**How to use personas:**

Personas activate **automatically** based on your request:
```
"I need a security audit of my authentication code"
→ security-auditor persona activates proactively
```

Or invoke explicitly:
```
Use the backend-architect persona to review my API design
```

---

### 3. Double Diamond Workflows

Proven design methodology adapted for AI engineering.

| Phase | Alias | What It Does | Use When | Example |
|-------|-------|--------------|----------|---------|
| **🔍 Discover** | probe | Multi-AI research and exploration | "How do others solve X?" | `octo research OAuth patterns` |
| **🎯 Define** | grasp | Requirements clarification | "What exactly should this do?" | `octo define auth requirements` |
| **🛠️ Develop** | tangle | Multi-approach implementation | "Build me X" | `octo build user login` |
| **✅ Deliver** | ink | Adversarial quality assurance | "Review this code" | `octo review auth code` |
| **🐙 Embrace** | - | Full 4-phase workflow | Complete feature lifecycle | `/octo:embrace authentication` |

**Key benefits:**
- ✅ Prevents scope drift (focused phases)
- ✅ Quality gates between phases (75% consensus required)
- ✅ Task dependency tracking (can't deliver without defining)
- ✅ Session persistence (resume interrupted workflows)

---

### 4. Complete Command Reference

All 30 commands organized by category:

#### Core Workflows
- `/octo:research` - Deep research with multi-source synthesis
- `/octo:discover` - Discovery phase (probe) - Multi-AI research
- `/octo:define` - Definition phase (grasp) - Requirements clarity
- `/octo:develop` - Development phase (tangle) - Implementation
- `/octo:deliver` - Delivery phase (ink) - Quality assurance
- `/octo:embrace` - Full Double Diamond workflow (all 4 phases)

#### Development Disciplines
- `/octo:tdd` - Test-driven development with red-green-refactor
- `/octo:debug` - Systematic debugging with methodical investigation
- `/octo:review` - Expert code review with quality assessment
- `/octo:security` - Security audit with OWASP compliance

#### AI & Decision Support
- `/octo:debate` - Structured three-way AI debates
- `/octo:loop` - Execute tasks iteratively until criteria met
- `/octo:brainstorm` - Creative thought partner session
- `/octo:meta-prompt` - Generate optimized prompts for any task

#### Planning & Documentation
- `/octo:prd` - AI-optimized PRD writing
- `/octo:prd-score` - Score existing PRDs (100-point framework)
- `/octo:docs` - Document delivery (export to PPTX/DOCX/PDF)
- `/octo:plan` - Intelligent plan builder with optimal routing
- `/octo:pipeline` - Content analysis pipeline with pattern extraction
- `/octo:extract` - Design system & product reverse-engineering with comprehensive extraction

#### Workflow & Mode Switching
- `/octo:km` - Switch to Knowledge Work mode (toggle Dev/Knowledge context)
- `/octo:dev` - Switch to Dev Work mode (software development optimization)
- `/octo:multi` - Force multi-provider parallel execution (manual override)

#### Workflow Aliases (same as core but different names)
- `/octo:probe` - Alias for discover/research
- `/octo:grasp` - Alias for define
- `/octo:tangle` - Alias for develop
- `/octo:ink` - Alias for deliver

#### Project Lifecycle (v7.22.01+)
- `/octo:status` - Show project progress dashboard
- `/octo:issues` - Track issues across sessions
- `/octo:rollback` - Restore from checkpoint (git tag)
- `/octo:resume` - Restore context from previous session
- `/octo:ship` - Finalize project with Multi-AI validation

#### System
- `/octo:setup` - Setup wizard for AI provider configuration
- `/octo:sys-setup` - System setup status and configuration instructions

---

### 5. 40 Specialized Skills

Complete skills catalog:

#### Research & Knowledge
- **octopus-research** (`/octo:research`) - Multi-AI research with cost transparency and interactive depth selection
- **skill-debate** (`/octo:debate`) - Structured three-way debates (Claude + Gemini + Codex)
- **skill-thought-partner** (`/octo:brainstorm`) - Creative collaboration with structured questioning
- **skill-meta-prompt** (`/octo:meta-prompt`) - Generate optimized prompts using meta-prompting techniques

#### Code Quality & Security
- **octopus-code-review** (`/octo:review`) - Comprehensive multi-AI code quality analysis
- **octopus-quick-review** - Fast pre-commit checks
- **octopus-security-audit** (`/octo:security`) - OWASP compliance and vulnerability detection
- **skill-security-framing** - Red team security testing and adversarial analysis

#### Development Practices
- **skill-tdd** (`/octo:tdd`) - Test-driven development (red-green-refactor)
- **skill-debug** (`/octo:debug`) - Systematic 4-phase bug investigation
- **skill-verify** - Pre-completion validation ("Iron Law" enforcement)
- **skill-iterative-loop** (`/octo:loop`) - Loop until exit criteria pass
- **skill-task-management** - Todo orchestration and session resumption
- **skill-finish-branch** - Post-implementation: verify → test → merge/PR

#### Architecture & Planning
- **octopus-architecture** - System design and technical decisions
- **skill-prd** (`/octo:prd`) - AI-optimized PRD with 100-point scoring framework
- **skill-writing-plans** - Zero-context implementation plans
- **skill-decision-support** - Present options with trade-offs analysis
- **skill-intent-contract** - Capture user intent with explicit contracts

#### Workflows (Double Diamond)
- **flow-discover** (`/octo:discover`) - Discovery/probe research phase
- **flow-define** (`/octo:define`) - Definition/grasp requirements phase
- **flow-develop** (`/octo:develop`) - Development/tangle implementation phase
- **flow-deliver** (`/octo:deliver`) - Delivery/ink validation phase

#### Content & Documentation
- **skill-doc-delivery** (`/octo:docs`) - Export to DOCX, PPTX, PDF
- **skill-content-pipeline** (`/octo:pipeline`) - URL content analysis and pattern extraction
- **skill-visual-feedback** - Process UI/UX screenshot feedback

#### Mode & Configuration
- **skill-knowledge-work** (`/octo:km`) - Toggle Dev/Knowledge context
- **skill-context-detection** - Auto-detect Dev vs Knowledge mode
- **skill-parallel-agents** - Multi-provider parallel execution
- **sys-configure** (`/octo:setup`) - System configuration and provider setup

#### Specialized Skills
- **skill-audit** - Systematic codebase checking and validation
- **skill-debate-integration** - Debate workflow integration with orchestration
- **skill-extract** (`/octo:extract`) - Design system & product reverse-engineering with comprehensive extraction

#### Project Lifecycle (v7.22.01+)
- **skill-status** (`/octo:status`) - Project progress dashboard with phase tracking
- **skill-issues** (`/octo:issues`) - Cross-session issue tracking and management
- **skill-rollback** (`/octo:rollback`) - Checkpoint recovery using git tags
- **skill-resume** (`/octo:resume`) - Session restoration with context reload
- **skill-ship** (`/octo:ship`) - Multi-AI delivery validation and lessons capture

---

### 6. Validation Gate Pattern (v7.15.0)

**The problem**: Before v7.15.0, workflow skills documented multi-AI execution but Claude would substitute direct research (0% compliance).

**The solution**: Enforcement through mandatory execution steps and validation gates.

**How it works:**
1. **Blocking pre-execution** - Provider check → Visual indicators → Cannot skip
2. **Mandatory Bash tool calls** - orchestrate.sh MUST be invoked (not "should")
3. **Validation gates** - Verify synthesis files exist before proceeding
4. **No-fallback errors** - If orchestrate.sh fails, report error (don't substitute)

**Results:**
- ✅ 100% orchestrate.sh execution (was 0%)
- ✅ 4x faster (3-5 min vs 18 min)
- ✅ 70% token savings (external CLIs handle work)
- ✅ Multi-AI perspectives (vs single)

---

### 7. Interactive Research with Cost Transparency (v7.14.0)

**The improvement**: See costs BEFORE execution, choose depth/focus/format interactively.

**The flow:**
1. **3 clarifying questions** before execution:
   - How deep? (Quick → Moderate → Comprehensive → Deep dive)
   - What focus? (Technical → Best practices → Ecosystem → Trade-offs)
   - What format? (Summary → Report → Table → Recommendations)

2. **Cost banner** showing EXACTLY what will run:
   ```
   🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research

   Provider Availability:
   🔴 Codex CLI: Available ✓
   🟡 Gemini CLI: Available ✓
   🔵 Claude: Available ✓

   Research Parameters:
   📊 Depth: Moderate depth
   🎯 Focus: Trade-offs & comparisons
   📝 Format: Comparison table

   💰 Estimated Cost: $0.02-0.03
   ⏱️  Estimated Time: 2-3 minutes
   ```

3. **You confirm** before it runs (no surprise costs)

---

### 8. Context-Aware Intelligence

Auto-detects whether you're doing **Dev work** or **Knowledge work** and adapts accordingly.

**Dev Context** (default when in code repos):
- Research focuses on: Libraries, patterns, implementation approaches
- Build output: Code, tests, APIs
- Review focus: Security, performance, code quality

**Knowledge Context** (activated with `/octo:km on` or auto-detected):
- Research focuses on: Market data, competitive analysis, strategic frameworks
- Build output: PRDs, presentations, reports, business documents
- Review focus: Clarity, evidence, logical completeness

**Auto-detection triggers:**
- **Dev mode**: Scans for `package.json`, `Cargo.toml`, technical keywords
- **Knowledge mode**: Scans for business terms (market, ROI, stakeholders)

**Manual override**: `/octo:km on` (Knowledge) | `/octo:km off` (Dev) | `/octo:km auto`

---

### 9. Advanced Features

#### PRD Scoring (100-Point Framework)
Score existing PRDs against AI optimization criteria:
```
/octo:prd-score path/to/prd.md
```
Returns detailed breakdown across 10 categories with specific improvement recommendations.

#### Meta-Prompt Generation
Generate optimized prompts for any task:
```
/octo:meta-prompt "I need to analyze user feedback and extract themes"
```
Returns structured prompt with context, objectives, constraints, and expected output format.

#### Content Pipeline
Extract patterns and create anatomy guides from URLs:
```
/octo:pipeline https://example.com/article
```
Analyzes structure, identifies patterns, creates reusable templates.

#### Iterative Loops
Execute tasks repeatedly until conditions met:
```
/octo:loop "run tests and fix issues" --max 5
```
Systematic iteration with progress tracking, stall detection, safety limits.

#### Document Export
Export results to professional formats:
```
/octo:docs export synthesis.md to presentation
```
Supports DOCX, PPTX, PDF with proper formatting.

#### Design System & Product Extraction
Reverse-engineer design systems and product architectures from existing codebases or URLs:
```
/octo:extract ./my-app                                    # Interactive mode with guided questions
/octo:extract ./my-app --mode design --storybook true     # Design system only with Storybook
/octo:extract ./my-app --depth deep --multi-ai force      # Deep analysis with all providers
/octo:extract https://example.com --mode design           # Extract from live website
```

**What gets extracted:**
- **Design Tokens** - Colors, typography, spacing (W3C Design Tokens format)
- **Components** - Props, variants, usage patterns across React/Vue/Svelte
- **Architecture** - Service boundaries, API contracts, data models
- **Features** - Complete feature inventory by domain
- **Documentation** - Auto-generated PRDs, Storybook stories, C4 diagrams

**Output formats:** JSON, CSS, Markdown, CSV with structured evidence and quality reports.

**Performance:** Quick mode (<2 min), Standard (2-5 min), Deep (5-15 min with multi-AI validation).

---

## Project Lifecycle Management

Claude-Octopus includes project-level state management with the `.octo/` directory for tracking progress across sessions.

### Lifecycle Commands

| Command | Description |
|---------|-------------|
| `/octo:embrace` | End-to-end workflow (auto-creates `.octo/` on first run) |
| `/octo:status` | Show project progress dashboard |
| `/octo:resume` | Restore context from previous session |
| `/octo:ship` | Finalize project with Multi-AI validation |
| `/octo:issues` | Track issues across sessions |
| `/octo:rollback` | Restore from checkpoint |

### Project State Directory

When you run `/octo:embrace`, a `.octo/` directory is created:

```
.octo/
├── PROJECT.md      # Vision and requirements
├── ROADMAP.md      # Phase breakdown (Double Diamond)
├── STATE.md        # Current position and history
├── config.json     # Workflow preferences
├── ISSUES.md       # Cross-session issue tracking
└── LESSONS.md      # Lessons learned
```

### Workflow

```
/octo:embrace
    ├── Discover (research) → Updates PROJECT.md
    ├── Define (consensus) → Updates ROADMAP.md
    ├── Develop (build) → Creates checkpoint
    └── Deliver (validate) → Routes to /octo:ship
        │
        ↓
/octo:ship → Captures lessons, archives, ships
```

### Session Continuity

- Run `/octo:status` to see where you are
- Run `/octo:resume` to restore context and continue
- Issues persist across sessions in `.octo/ISSUES.md`
- Lessons are never lost (preserved across rollbacks)

---

## Frequently Asked Questions

### Do I need all three AI providers?

**No!** You only need **ONE external provider** (Codex OR Gemini). Claude is built-in.

- Codex only → Uses Codex + Claude
- Gemini only → Uses Gemini + Claude
- Both → Uses all three for maximum diversity

### How much does this cost?

**Recommended: OAuth subscriptions for predictable costs**
- Codex (OpenAI): ~$20-50/month fixed
- Gemini (Google): Fixed pricing or Google Cloud quota

**Alternative: Pay-per-token with API keys**
- Codex: ~$0.01-0.05 per query
- Gemini: ~$0.01-0.03 per query

**You see cost estimates BEFORE execution** (v7.14.0+).

**Typical monthly costs:**
- Light use (5-10 queries/week): $2-5
- Moderate (20-30 queries/week): $8-15
- Heavy (50+ queries/week): $20-40

### Will this break my existing Claude Code setup?

**No.** Fully isolated:
- ✅ Only activates with `octo` prefix or `/octo:*` commands
- ✅ Stores results separately (`~/.claude-octopus/`)
- ✅ Can be uninstalled without affecting other plugins
- ✅ Regular Claude conversations unchanged

### Can I use Claude Octopus without external AIs?

**Yes!** Even without Codex/Gemini, you get:
- ✅ 29 expert personas
- ✅ Structured workflows (Double Diamond)
- ✅ Context-aware intelligence
- ✅ Task management and session tracking
- ✅ All specialized skills

Multi-AI features simply won't activate without external providers.

### Is this actively maintained?

**Yes!**
- Current version: v7.23.0 (February 2026)
- 95%+ test coverage
- Active development: [Recent commits](https://github.com/nyldn/claude-octopus/commits/main)
- Issue tracking: [Report bugs](https://github.com/nyldn/claude-octopus/issues)

---

## Understanding Costs

### Cost Breakdown by Scenario

| Scenario | Duration | Estimated Cost | What You Get |
|----------|----------|----------------|--------------|
| **Simple research** | 1-2 min | $0.01-0.02 | High-level summary from 3 AIs |
| **Standard research** | 2-3 min | $0.02-0.05 | Balanced exploration with synthesis |
| **Deep dive** | 4-5 min | $0.05-0.10 | Exhaustive multi-angle research |
| **AI Debate** | 5-10 min | $0.08-0.15 | 3-5 rounds with rebuttals |
| **Code review** | 3-5 min | $0.04-0.08 | Multi-AI security/quality analysis |
| **Full workflow** | 15-25 min | $0.20-0.40 | Complete 4-phase lifecycle |

### When to Use What

**Use multi-AI orchestration (🐙) when:**
- ✅ High-stakes decisions (architecture, tech stack)
- ✅ Need multiple perspectives (security, design trade-offs)
- ✅ Broad research coverage (comparing 5+ options)
- ✅ Adversarial review (production-critical code)
- ✅ Complex implementations (multiple valid approaches)

**Use Claude only (no 🐙) when:**
- ✅ Simple operations (file edits, basic refactoring)
- ✅ Single perspective adequate
- ✅ Quick fixes (typos, formatting)
- ✅ Cost efficiency priority
- ✅ Already know the answer

---

## Installation & Setup

### Install the Plugin

```
/plugin marketplace add https://github.com/nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

### Configure Providers

```
/octo:setup
```

Guided 2-minute setup that:
- ✅ Checks existing installations
- ✅ Shows exactly what's missing
- ✅ Walks through CLI installation
- ✅ Helps configure OAuth or API keys
- ✅ Verifies everything works

### Start Using

**Natural language** (with "octo" prefix):
```
octo research microservices patterns
octo build authentication system
octo review this code
```

**Slash commands** (always reliable):
```
/octo:research microservices
/octo:develop authentication
/octo:review code
```

---

## Updating

### Via Plugin UI
1. `/plugin` to open plugin screen
2. Find `claude-octopus@nyldn-plugins` in "Installed"
3. Click update button

### Manual Reinstall
```
/plugin uninstall claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

### Pin to Specific Version
```
/plugin install claude-octopus@nyldn-plugins#<commit-sha>
```

**After updating:** Restart Claude Code to load new version.

---

## Documentation

### User Guides
- **[Visual Indicators Guide](docs/VISUAL-INDICATORS.md)** - Understanding what's running
- **[Triggers Guide](docs/TRIGGERS.md)** - What activates workflows
- **[Command Reference](docs/COMMAND-REFERENCE.md)** - All commands
- **[Sandbox Configuration](docs/SANDBOX-CONFIGURATION.md)** - Mounted filesystem support

### Developer Guides
- **[Architecture Guide](docs/ARCHITECTURE.md)** - Models, providers, execution
- **[Plugin Architecture](docs/PLUGIN-ARCHITECTURE.md)** - How it works
- **[Contributing Guidelines](CONTRIBUTING.md)** - Contribution guide

### Migration Guides
- **[Migration to v7.13.0](MIGRATION-7.13.0.md)** - Task management, sessions, MCP
- **[Full Changelog](CHANGELOG.md)** - Complete version history

---

## 🙏 Attribution & Acknowledgments

Claude Octopus stands on the shoulders of giants:

- **[wolverin0/claude-skills](https://github.com/wolverin0/claude-skills)** - AI Debate Hub enables structured three-way debates. Integrated as git submodule with quality gates, cost tracking, and document export enhancements. MIT License.

- **[obra/superpowers](https://github.com/obra/superpowers)** - Several discipline skills (TDD, debugging, verification) inspired by excellent patterns in this library. The "Iron Law" enforcement approach is particularly valuable. MIT License.

- **Double Diamond** methodology by [UK Design Council](https://www.designcouncil.org.uk/our-resources/the-double-diamond/) - Proven framework for divergent/convergent thinking adapted as Discover/Define/Develop/Deliver.

---

## Contributing

### To Claude-Octopus

1. **Report Issues**: [Open an issue](https://github.com/nyldn/claude-octopus/issues)
2. **Suggest Features**: Share your ideas
3. **Submit PRs**: Follow existing code style
4. **Share Knowledge**: Write about your experience

### Development Setup

```bash
git clone --recursive https://github.com/nyldn/claude-octopus.git
cd claude-octopus
git submodule update --init --recursive

# Run tests
make test
make test-unit
make test-integration
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## License

MIT License - see [LICENSE](LICENSE)

<p align="center">
  <em>🐙 Made with eight tentacles (one for each AI perspective, plus spares) 🐙</em><br/>
  <a href="https://github.com/nyldn">nyldn</a> | MIT License | <a href="https://github.com/nyldn/claude-octopus/issues">Report Issues</a>
</p>
