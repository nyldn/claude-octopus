# Command and Usage Reference

Complete reference for all 48 Claude Octopus slash commands, 10 CLI tools (`octopus` + `octo-compress`), plus activation rules, provider indicators, and the project-lifecycle features that are triggered by natural language rather than slash commands.

---

## Quick Reference

All slash commands use the `/octo:` namespace. The smart router command is `/octo:auto`, and the plain-language trigger remains `octo ...`.

### Smart Router

| Command | Description |
|---------|-------------|
| `/octo:auto` | Smart router — detects intent and routes to the right workflow |

### System Commands

| Command | Description |
|---------|-------------|
| `/octo:setup` | Check setup status and configure providers (alias: `/octo:sys-setup`) |
| `/octo:doctor` | Environment diagnostics across 9 check categories (includes RTK install + token optimization) |
| `/octo:model-config` | Configure provider model selection per workflow phase |
| `/octo:km` | Toggle Knowledge Work mode |
| `/octo:dev` | Switch to Dev Work mode |

### Double Diamond Workflow

| Command | Phase | Description |
|---------|-------|-------------|
| `/octo:embrace` | All | Full 4-phase Double Diamond workflow |
| `/octo:discover` | Discover | Multi-AI research and exploration |
| `/octo:define` | Define | Requirements clarification and scope |
| `/octo:develop` | Develop | Multi-AI implementation |
| `/octo:deliver` | Deliver | Validation and quality assurance |
| `/octo:plan` | Pre-flight | Strategic plan builder (doesn't execute) |

### Research & Knowledge

| Command | Description |
|---------|-------------|
| `/octo:research` | Deep research with multi-source synthesis |
| `/octo:brainstorm` | Creative thought partner brainstorming session |
| `/octo:debate` | AI Debate Hub — four-way debates (Claude + Gemini + Codex) |
| `/octo:prd` | Write an AI-optimized PRD with 100-point scoring |
| `/octo:prd-score` | Score an existing PRD against the framework |
| `/octo:spec` | NLSpec authoring from multi-AI research |

### Code Quality & Review

| Command | Description |
|---------|-------------|
| `/octo:review` | Enhanced multi-LLM review for escalated code review and PR comment posting |
| `/octo:staged-review` | Two-stage review: spec compliance then code quality |
| `/octo:security` | Enhanced multi-LLM or adversarial security audit with OWASP coverage |
| `/octo:debug` | Systematic debugging with root cause investigation |
| `/octo:tdd` | Test-driven development with red-green-refactor |

### Parallel & Orchestration

| Command | Description |
|---------|-------------|
| `/octo:parallel` | Team of Teams — decompose compound tasks across independent Claude instances |
| `/octo:factory` | Dark Factory Mode — spec-in, software-out autonomous pipeline |
| `/octo:multi` | Force multi-provider parallel execution for any task |
| `/octo:loop` | Iterative execution with conditions until goals are met |
| `/octo:quick` | Quick execution without full workflow overhead |

### Content & Docs

| Command | Description |
|---------|-------------|
| `/octo:docs` | Document delivery with export to PPTX, DOCX, PDF |
| `/octo:deck` | Slide deck generator from briefs or research |
| `/octo:pipeline` | Content analysis pipeline — extract patterns from URLs |
| `/octo:meta-prompt` | Generate optimized prompts using meta-prompting techniques |
| `/octo:extract` | Design system & product reverse-engineering from codebases or live products |
| `/octo:design-ui-ux` | Full UI/UX design workflow with BM25 design intelligence |

### Monitoring & Scheduling

| Command | Description |
|---------|-------------|
| `/octo:sentinel` | GitHub-aware work monitor — triage issues, PRs, and CI failures |
| `/octo:schedule` | Manage scheduled workflow jobs (wizard, dashboard, enable/disable) |
| `/octo:scheduler` | Manage the scheduler daemon (start/stop/status) |

### Safety

| Command | Description |
|---------|-------------|
| `/octo:careful` | Activate destructive command warnings for the session |
| `/octo:freeze` | Restrict file edits to a specific directory boundary |
| `/octo:guard` | Activate both careful mode and freeze mode together |
| `/octo:unfreeze` | Remove freeze mode edit restriction |

### Session & Insights

| Command | Description |
|---------|-------------|
| `/octo:costs` | Show cost breakdown by provider and workflow for the current session |
| `/octo:retro` | Generate engineering retrospectives from git history with trends |
| `/octo:history` | Query past workflow results — filter by workflow type, date, or provider |
| `/octo:resume` | Resume a previous agent by ID — continue an interrupted task |
| `/octo:discipline` | Toggle discipline mode — auto-invoke verification and review checks |

### Admin

| Command | Description |
|---------|-------------|
| `/octo:claw` | OpenClaw instance admin across macOS, Ubuntu/Debian, Docker, OCI, Proxmox |
| `/octo:octo` | [Legacy] Redirects to `/octo:auto` |

### CLI Tools (v9.19.0+)

Plugin executables available as bare commands (CC v2.1.91+). Also usable via full path on older CC versions.

| Command | Description |
|---------|-------------|
| `octopus doctor` | Run diagnostics (same as `/octo:doctor`) |
| `octopus version` | Show plugin version |
| `octopus session` | Show current session info |
| `octopus fleet` | Show provider fleet status |
| `octo-compress` | Pipe verbose output for token savings: `npm install 2>&1 \| octo-compress` |
| `octo-compress json` | Force JSON array/object compression |
| `octo-compress logs` | Force log compression (head+tail) |
| `octo-compress html` | Force HTML tag stripping |
| `octo-compress stats` | Show compression savings for current session |
| `octo-compress config` | Show compression configuration |

### Project Lifecycle (Skill-Based)

These are invoked via natural language or skill triggers — not slash commands.

| Feature | Natural Language | Description |
|---------|-----------------|-------------|
| Status | "show status", "where am I" | Project progress dashboard |
| Resume | "resume", "continue", "pick up where I left off" | Restore context from previous session |
| Ship | "ship", "finalize", "I'm done" | Finalize project with Multi-AI validation |
| Issues | "add issue", "show issues" | Track blockers and bugs across sessions |
| Rollback | "rollback", "revert", "restore checkpoint" | Restore from git checkpoint |

---

## Smart Router

### `/octo:auto`

Single entry point with natural language intent detection. Analyzes your request and routes to the optimal workflow automatically.

**You can invoke the router in two ways:**
- Slash command: `/octo:auto <request>`
- Plain language: `octo <request>`

**Usage:**
```
/octo:auto research OAuth authentication patterns
/octo:auto build user authentication system
/octo:auto validate src/auth.ts
/octo:auto should we use Redis or Memcached?
/octo:auto create a complete e-commerce platform
```

**Routing table:**

| Intent | Keywords | Routes To |
|--------|----------|-----------|
| Research | research, investigate, explore, analyze | `/octo:discover` |
| Build (specific) | build X, create Y, implement Z | `/octo:develop` |
| Build (vague) | build, create, make (no clear target) | `/octo:plan` |
| Validate | validate, review, check, audit, verify | `/octo:review` |
| Debate | should, vs, or, compare, versus, which | `/octo:debate` |
| Specify | spec, specify, requirements, nlspec | `/octo:spec` |
| Parallel | parallel, decompose, work packages, multi-instance | `/octo:parallel` |
| Lifecycle | end-to-end, complete, full, entire, whole | `/octo:embrace` |

**Confidence levels:**
- `>80%` — Auto-routes with notification
- `70–80%` — Shows suggestion, asks for confirmation
- `<70%` — Lists options, asks to clarify

---

## System Commands

### `/octo:setup`

Check setup status and configure AI providers.

**Aliases:** `/octo:sys-setup`

**Usage:**
```
/octo:setup
```

**What it does:**
- Auto-detects installed providers (Codex CLI, Gemini CLI)
- Shows which providers are available and their auth status
- Provides installation instructions for missing providers
- Verifies API keys and authentication

**Example output:**
```
Claude Octopus Setup Status

Providers:
  Codex CLI: ready
  Gemini CLI: ready

You're all set! Try: /octo:auto research OAuth patterns
```

**Troubleshooting:** If you see "Failed to update: Plugin 'octo' not found", run `/octo:setup` for reinstall instructions, or see [issue #17](https://github.com/nyldn/claude-octopus/issues/17).

---

### `/octo:doctor`

Run environment diagnostics across 9 check categories.

**Usage:**
```
/octo:doctor                    # Run all checks
/octo:doctor providers          # Check provider installation only
/octo:doctor auth --verbose     # Detailed auth status
/octo:doctor --json             # Machine-readable output
```

**Check categories:**

| Category | What it checks |
|----------|---------------|
| `providers` | Claude Code version, Codex CLI, Gemini CLI |
| `auth` | Authentication status for each provider |
| `config` | Plugin version, install scope, feature flags |
| `state` | Project state.json, stale results, workspace writable |
| `smoke` | Smoke test cache, model configuration |
| `hooks` | hooks.json validity, hook scripts |
| `scheduler` | Scheduler daemon, jobs, budget gates, kill switches |
| `skills` | Skill files loaded and valid |
| `conflicts` | Conflicting plugin detection |

**Flags:**

| Flag | Description |
|------|-------------|
| `--verbose`, `-v` | Show detailed output for each check |
| `--json` | Output results as JSON |

---

### `/octo:model-config`

Configure which AI models are used across Claude Octopus workflows.

**Usage:**
```
/octo:model-config                          # View current config
/octo:model-config show phases              # Show per-phase routing table
/octo:model-config codex gpt-5.4            # Set Codex model
/octo:model-config codex gpt-5.4  # Fast Spark model
/octo:model-config gemini gemini-3.1-pro-preview  # Set Gemini model
/octo:model-config cost-mode budget         # Use cheaper models
/octo:model-config cost-mode premium        # Use best models
/octo:model-config trace                    # Debug model resolution
/octo:model-config reset                    # Reset to defaults
```

**Cost modes:**

| Mode | Codex | Gemini | Best for |
|------|-------|--------|----------|
| `budget` | gpt-5.4 | gemini-3-flash | High-volume, quick feedback |
| `standard` | gpt-5.4 | gemini-3.1-pro-preview | Default — balanced cost/quality |
| `premium` | gpt-5.4-pro | gemini-3.1-pro-preview | Critical decisions, maximum quality |

**Per-phase routing:** Different models can be configured for Discover, Define, Develop, and Deliver phases. Use `show phases` to view the current routing table.

**Role-based defaults (v9.29+):** `architect`, `strategist`, and `security-reviewer` use Claude Opus 4.7; `code-reviewer` and `implementer` use GPT-5.4; `synthesizer` uses Claude Sonnet 4.6. See [ARCHITECTURE.md — Role → Model Mapping](../docs/ARCHITECTURE.md#role--model-mapping-v929) for rationale. Opt out with `OCTOPUS_LEGACY_ROLES=1`.

---

### `/octo:km`

Toggle between Dev Work mode and Knowledge Work mode.

**Usage:**
```
/octo:km          # Show current status
/octo:km on       # Enable Knowledge Work mode
/octo:km off      # Disable (return to Dev Work mode)
```

**Modes:**

| Mode | Focus | Best For |
|------|-------|----------|
| Dev Work (default) | Code, tests, debugging | Software development |
| Knowledge Work | Research, strategy, UX | Consulting, research, product work |

---

### `/octo:dev`

Shortcut to switch to Dev Work mode.

**Usage:**
```
/octo:dev
```

Equivalent to `/octo:km off`.

---

## Double Diamond Workflow

### `/octo:embrace`

Full Double Diamond workflow — all 4 phases in sequence.

**Usage:**
```
/octo:embrace complete authentication system
/octo:embrace e-commerce platform with payments and inventory
```

**What it does:**
1. **Discover** 🔍 — Multi-AI research: patterns, trade-offs, prior art
2. **Define** 🎯 — Requirements clarification: scope, constraints, acceptance criteria
3. **Develop** 🛠️ — Multi-AI implementation with quality gates (75% threshold)
4. **Deliver** ✅ — Validation, go/no-go recommendation, PR comment posting

**Multi-LLM debate gates** at each phase transition — optional Claude + Codex + Gemini deliberation before moving forward.

Shows visual indicator: 🐙 (all phases)

**Note:** Mandatory compliance means Claude cannot skip this workflow for tasks it judges "too simple." The user controls when to use `/octo:embrace`.

---

### `/octo:discover`

Discovery phase — Multi-AI research and exploration.

**Usage:**
```
/octo:discover OAuth authentication patterns
/octo:discover microservices vs monolith trade-offs
```

**What it does:**
- Parallel research using Codex CLI + Gemini CLI
- Relevance-aware synthesis with quality ranking (v8.49.0+)
- Minority opinion preservation — surfaces dissenting views
- Shows visual indicator: 🐙 🔍

**Natural language triggers:**
- `octo research X`
- `octo explore Y`
- `octo investigate Z`

---

### `/octo:define`

Definition phase — Clarify requirements and scope with multi-AI consensus.

**Usage:**
```
/octo:define requirements for user authentication
/octo:define scope of the payment system refactor
```

**What it does:**
- Multi-AI consensus on problem definition
- Identifies success criteria, constraints, and non-goals
- Optional multi-LLM debate gate before finalizing
- Shows visual indicator: 🐙 🎯

**Natural language triggers:**
- `octo define requirements for X`
- `octo clarify scope of Y`
- `octo scope out Z feature`

---

### `/octo:develop`

Development phase — Multi-AI implementation with quality gates.

**Usage:**
```
/octo:develop user authentication system
/octo:develop REST API for order management
```

**What it does:**
- Generates implementation from multiple AI perspectives
- Context-aware quality injection based on detected subtype:
  - **frontend-ui**: accessibility, self-containment, BM25 design intelligence
  - **cli-tool**: exit codes, help text, argument validation
  - **api-service**: input validation, auth requirements
  - **infra**, **data**, **general**: domain-appropriate criteria
- Applies 75% quality gate threshold
- Shows visual indicator: 🐙 🛠️

**Natural language triggers:**
- `octo build X`
- `octo implement Y`
- `octo create Z`

---

### `/octo:deliver`

Delivery phase — Validation, quality assurance, and PR comment posting.

**Usage:**
```
/octo:deliver authentication implementation
/octo:deliver src/api/
```

**What it does:**
- Multi-AI validation and review
- Reference integrity gate (checks for broken file references)
- Quality scores with go/no-go recommendation
- **Auto-posts review findings as PR comments** when an open PR is detected (v8.44.0+)
- Shows visual indicator: 🐙 ✅

**Natural language triggers:**
- `octo validate X`
- `octo audit Z`

---

### `/octo:plan`

Intelligent plan builder — creates strategic execution plans without executing them.

**Usage:**
```
/octo:plan build a real-time chat system
/octo:plan migrate our monolith to microservices
```

**What it does:**
- Captures comprehensive intent via 5 structured questions (goal, knowledge level, constraints, timeline, success criteria)
- Analyzes requirements and generates a weighted execution strategy
- Saves plan to `.claude/session-plan.md` and intent contract to `.claude/session-intent.md`
- Offers to execute immediately with `/octo:embrace` or save for later

**Aliases:** `build-plan`, `intent`

**When to use:** When you want to think through a complex task before committing to execution. Use `/octo:embrace` to execute a plan.

---

## Research & Knowledge

### `/octo:research`

Deep research with multi-source synthesis and comprehensive analysis.

**Usage:**
```
/octo:research microservices patterns
/octo:research OAuth 2.0 vs API key authentication
```

**What it does:**
- Multi-AI research using Codex, Gemini, and Claude
- Documentation lookup and ecosystem analysis
- Synthesizes findings into actionable, structured insights

---

### `/octo:brainstorm`

Creative thought partner brainstorming session — Solo or Multi-AI Team mode.

**Usage:**
```
/octo:brainstorm
/octo:brainstorm my approach to customer onboarding
```

**Modes:** When invoked, you'll be asked to choose a mode:

| Mode | What happens | Cost |
|------|-------------|------|
| **Solo** | Claude-only thought partner — fast, focused, interactive | Claude Code subscription only |
| **Team** | Multi-AI brainstorm — Codex + Gemini + Claude provide diverse perspectives | Uses external API credits |

**How to toggle multi:** When you run `/octo:brainstorm`, a mode selector appears before the session starts. Select **Team** to activate multi-LLM brainstorming.

**Solo mode:**
- Structured exploration using four breakthrough techniques: Pattern Spotting, Paradox Hunting, Naming the Unnamed, Contrast Creation
- Guided questioning — one question at a time
- Challenges generic claims until insights become specific
- Collaboratively names discovered concepts
- Exports session with breakthroughs summary

**Team mode:**
- Dispatches parallel queries to available providers:
  - 🔴 Codex CLI — Technical feasibility and implementation angles
  - 🟡 Gemini CLI — Lateral thinking and ecosystem connections
  - 🔵 Claude — Synthesis, pattern naming, and moderation
- Provider-attributed results (🔴 🟡 🔵)
- Cross-perspective synthesis: convergence, divergence, and strongest ideas
- Interactive challenge and building on the best ideas
- Multi-perspective breakthroughs export

**Visual indicator (Team mode):**
```
🐙 CLAUDE OCTOPUS ACTIVATED — Multi-AI Brainstorm
🔴 Codex CLI — Technical feasibility and implementation angles
🟡 Gemini CLI — Lateral thinking and ecosystem connections
🔵 Claude — Synthesis, pattern naming, and moderation
```

---

### `/octo:debate`

AI Debate Hub — structured four-way debates between Claude, Gemini, and Codex.

**Usage:**
```
/octo:debate Redis vs Memcached for caching
/octo:debate -r 3 Should we use GraphQL or REST
/octo:debate -d adversarial Review auth.ts security
```

**Options:**

| Flag | Description |
|------|-------------|
| `-r N`, `--rounds N` | Number of debate rounds (default: 2) |
| `-d STYLE`, `--debate-style STYLE` | `quick`, `thorough`, `adversarial`, `collaborative` |

**What it does:**
- Claude, Gemini CLI, and Codex CLI debate the topic
- Claude acts as both participant and moderator
- Anti-sycophancy gate prevents consensus from forming too easily
- Produces synthesis with concrete recommendation

**Natural language triggers:**
- `octo debate X vs Y`
- `run a debate about Z`
- `I want gemini and codex to review X`

---

### `/octo:prd`

Write an AI-optimized PRD using multi-AI orchestration and 100-point scoring framework.

**Usage:**
```
/octo:prd user authentication system
/octo:prd real-time notifications feature
```

**What it does:**
1. Clarification phase — target users, core problem, success criteria, constraints
2. Quick research (2 web searches max)
3. Generates structured PRD with sequential phases, explicit non-goals, FR codes, P0/P1/P2 priorities
4. Scores against 100-point AI-optimization framework
5. Saves to file

---

### `/octo:prd-score`

Score an existing PRD against the 100-point AI-optimization framework.

**Usage:**
```
/octo:prd-score path/to/PRD.md
```

**Scoring categories:**

| Category | Points | What it measures |
|----------|--------|-----------------|
| AI-Specific Optimization | 25 | Sequential phases, explicit non-goals, structured format |
| Traditional PRD Core | 25 | Problem statement, goals, personas, technical specs |
| Implementation Clarity | 30 | Functional requirements, NFRs, architecture |
| Completeness | 20 | Edge cases, error handling, success metrics |

---

### `/octo:spec`

NLSpec authoring — structured specification from multi-AI research.

**Aliases:** `nlspec`, `specification`

**Usage:**
```
/octo:spec user authentication system
/octo:spec real-time chat with presence indicators
```

**What it does:**
- Question-first approach to understand scope
- Multi-AI research (Claude + Gemini + Codex) on the domain
- Generates structured NLSpec: behaviors, actors, constraints, acceptance criteria
- Completeness validation with scoring
- Saves specification file for downstream workflows (e.g., `/octo:factory`)

**When to use:** Starting a new project from scratch, defining requirements before implementation, creating a specification for handoff.

---

## Code Quality & Review

### `/octo:review`

Enhanced multi-LLM review with comprehensive quality assessment and PR comment posting.

**Use Claude-native `/review` for ordinary review requests.** Use `/octo:review` when you want multiple model opinions, provider diversity, or stricter escalation.

**Usage:**
```
/octo:review auth.ts
/octo:review src/components/
/octo:review                    # Review recent changes
```

**What it does:**
- Comprehensive code quality analysis
- Security vulnerability detection
- Architecture review and best practices enforcement
- **Auto-posts findings as PR comment** when an open PR exists on the current branch (v8.44.0+) — asks first in standalone mode, auto-posts during automated workflows

---

### `/octo:staged-review`

Two-stage review pipeline: spec compliance then code quality.

**Aliases:** `two-stage-review`, `full-review`

**Usage:**
```
/octo:staged-review
/octo:staged-review src/auth/
```

**Stages:**
1. **Stage 1 — Spec Compliance**: Validates against intent contract (`.claude/session-intent.md`)
2. **Gate check**: Stage 1 must pass before Stage 2 runs
3. **Stage 2 — Code Quality**: Stub detection and quality review
4. **Combined report**: Unified verdict with PR comment posting when applicable

**When to use:** After completing a feature with a defined spec, before merging. More thorough than `/octo:review`.

---

### `/octo:security`

Enhanced multi-LLM or adversarial security audit with OWASP compliance and vulnerability detection.

**Use Claude-native `/security-review` for ordinary security review requests.** Use `/octo:security` when you want escalated OWASP analysis, provider diversity, or adversarial validation.

**Usage:**
```
/octo:security auth.ts
/octo:security src/api/
```

**What it does:**
- OWASP Top 10 vulnerability scanning
- Authentication and authorization review
- Input validation and injection checks
- Red team analysis (adversarial testing)

---

### `/octo:debug`

Systematic debugging with methodical root cause investigation.

**Usage:**
```
/octo:debug failing test in auth.spec.ts
/octo:debug TypeError in payment processor
```

**What it does:**
1. **Investigate** — Gather evidence, reproduce the issue
2. **Analyze** — Root cause identification
3. **Hypothesize** — Form and rank theories
4. **Implement** — Fix with verification

---

### `/octo:tdd`

Test-driven development with red-green-refactor discipline.

**Usage:**
```
/octo:tdd implement user registration
/octo:tdd add password validation
```

**What it does:**
- **Red**: Write failing test first
- **Green**: Minimal code to make it pass
- **Refactor**: Improve while keeping tests green

---

## Parallel & Orchestration

### `/octo:parallel`

Team of Teams — decompose compound tasks across independent Claude instances.

**Aliases:** `team`, `teams`

**Usage:**
```
/octo:parallel build a full authentication system with OAuth, RBAC, and audit logging
/octo:parallel create CI/CD pipeline with testing, linting, and deployment stages
```

**What it does:**
- Generates a Work Breakdown Structure (WBS) decomposing the task into independent work packages
- Each work package runs as a separate `claude -p` process with its own git worktree (v8.44.0+)
- Each worker gets the full Octopus plugin (Double Diamond, agents, quality gates)
- Parallel execution with staggered launch
- Agents tracked in registry with PR lifecycle management (v8.44.0+)
- Reaction engine auto-handles CI failures and review comments (v8.45.0+)
- Aggregates results into unified output

**When to use:** Compound tasks with 3+ independent components where parallel execution and full plugin capabilities per component are needed.

---

### `/octo:factory`

Dark Factory Mode — spec-in, software-out autonomous pipeline.

**Aliases:** `dark-factory`, `build-from-spec`

**Usage:**
```
/octo:factory --spec path/to/spec.nlspec
```

**What it does:**
1. Asks 3 clarifying questions: spec path, satisfaction target, cost confirmation
2. Parses the NLSpec file
3. Generates test scenarios (Codex)
4. Runs the full embrace workflow
5. Evaluates against holdout test suite (Codex + Gemini blind review)
6. Scores against satisfaction target
7. Repeats if target not met (up to configured limit)
8. Produces final delivery report

**Cost:** ~20–30 agent calls (~$0.50–2.00). Requires confirmation before starting.

**Requires:** A spec file (create one with `/octo:spec`). Works in Claude-only mode if external providers unavailable.

---

### `/octo:multi`

Force multi-provider parallel execution for any task — manual override mode.

**Usage:**
```
/octo:multi analyze the security of this authentication flow
/octo:multi review these architectural trade-offs
```

**What it does:**
- Asks for intent and cost confirmation before proceeding
- Runs the task in parallel across Codex, Gemini, and Claude
- Synthesizes perspectives into a unified response

**Cost:** Uses external API credits (Codex + Gemini). Confirms before running.

**When to use:** High-stakes decisions, cross-checking important work, comparing model perspectives. For most tasks, the router (`/octo:auto` or `octo ...`) or specific workflow commands are better.

---

### `/octo:loop`

Iterative execution with conditions until goals are met.

**Usage:**
```
/octo:loop "run tests and fix issues" --max 5
/octo:loop "optimize performance until < 100ms"
/octo:loop "keep improving until all lint errors are resolved"
```

**What it does:**
- Executes a task iteratively
- Checks exit condition after each iteration
- Stops when condition is met or max iterations reached
- Reports progress and final outcome

---

### `/octo:quick`

Quick execution mode — ad-hoc tasks without full workflow overhead.

**Usage:**
```
/octo:quick fix typo in README
/octo:quick update Next.js to v15
/octo:quick remove console.log statements
/octo:quick add error handling to login function
```

**What it does:**
1. Directly implements the change
2. Creates atomic commit
3. Generates summary

**Skips:** Research, planning, multi-AI validation.

**Cost:** Claude only — no external provider costs.

**When to escalate:** If the task becomes complex, use `/octo:discover` for research or `/octo:embrace` for full workflow.

---

## Content & Docs

### `/octo:docs`

Document delivery with export to PPTX, DOCX, and PDF formats.

**Usage:**
```
/octo:docs create API documentation
/octo:docs export report.md to PPTX
/octo:docs write architecture guide as DOCX
```

**Supported formats:**
- DOCX (Word)
- PPTX (PowerPoint)
- PDF

---

### `/octo:deck`

Slide deck generator from briefs, research, or topic descriptions.

**Usage:**
```
/octo:deck investor pitch for AI-powered logistics startup
/octo:deck quarterly business review for engineering leadership
/octo:deck technical deep-dive on our microservices migration
```

**Pipeline:**
1. **Brief** — Clarify audience, slide count, and tone
2. **Research** — Optional context gathering (or bring your own content)
3. **Outline** — Slide-by-slide structure for your approval
4. **PPTX** — Rendered PowerPoint file

**Tip:** Run `/octo:discover [topic]` first for research-heavy presentations, then pipe the output to `/octo:deck`.

---

### `/octo:pipeline`

Content analysis pipeline — extract patterns and anatomy guides from URLs.

**Usage:**
```
/octo:pipeline https://example.com/great-article
/octo:pipeline https://url1.com https://url2.com https://url3.com
```

**What it does:**
1. Fetches and validates content from URLs
2. Deconstructs patterns: structure, psychology, mechanics
3. Synthesizes findings into a reusable anatomy guide
4. Generates interview questions for content recreation

---

### `/octo:meta-prompt`

Generate optimized prompts using proven meta-prompting techniques.

**Usage:**
```
/octo:meta-prompt
/octo:meta-prompt create a code review checklist
/octo:meta-prompt design a user onboarding flow
```

**What it does:**
- Applies Task Decomposition for complex tasks
- Assigns Specialized Experts for each subtask
- Builds in Iterative Verification steps
- Enforces No Guessing (explicit uncertainty disclaimers)
- Generates a structured prompt with role definition, phases, expert assignments, verification checkpoints, and output format

---

### `/octo:extract`

Design system & product reverse-engineering — extract tokens, components, architecture, and PRDs from codebases or live products.

**Aliases:** `reverse-engineer`, `analyze-codebase`

**Usage:**
```
/octo:extract src/components/
/octo:extract https://example.com
/octo:extract design-system.pdf
```

**What it extracts:**
- Design tokens (colors, typography, spacing, shadows)
- Component inventory and API patterns
- Architecture patterns and data flows
- PRD-style feature documentation

**Supports:** Codebase directories, live URLs (via browser), PDF files (with page selection for large PDFs).

---

### `/octo:design-ui-ux`

Full UI/UX design workflow with BM25 design intelligence and optional Figma integration.

**Aliases:** `design`, `ui-design`, `ux-design`

**Usage:**
```
/octo:design-ui-ux design a dashboard for analytics
/octo:design-ui-ux pick colors for a fintech app
/octo:design-ui-ux create component specs for the checkout flow
/octo:design-ui-ux review this Figma and create dev specs
```

**Modes:**

| Intent | Mode |
|--------|------|
| "design a [product/screen]" | Full 4-phase Double Diamond design workflow |
| "pick colors for X" | Quick BM25 palette search |
| "review this Figma" | Figma context pull + spec generation |
| "create component specs" | Focused component spec generation |

**Tools used:**
- 🔍 BM25 Design Intelligence — Style, palette, typography, and UX pattern databases
- 🔵 Claude (ui-ux-designer persona) — Design synthesis and specification
- 🎨 Figma MCP — Design context when a Figma URL is provided
- 🧩 shadcn MCP — Component suggestions when available

**Multi-LLM adversarial design critique** (v8.43.0+): Between Define and Develop phases, Codex, Gemini, and Claude each review the proposed design direction independently, issues are triaged, and fixes are applied before tokens/components are generated.

---

## Monitoring & Scheduling

### `/octo:sentinel`

GitHub-aware work monitor — triages issues, PRs, and CI failures.

**Usage:**
```
/octo:sentinel              # One-time triage scan
/octo:sentinel --watch      # Continuous monitoring
```

**What it monitors:**

| Source | Filter | Action |
|--------|--------|--------|
| Issues | `octopus` label | Classifies by task type → workflow recommendation |
| PRs | Review requested | Recommends `/octo:review` |
| CI runs | Failed status | Recommends `/octo:debug` |

**What it does:**
- Reads GitHub state (issues, PRs, CI runs)
- Classifies and recommends workflows
- Writes findings to `.octo/sentinel/triage-log.md`
- Fires the reaction engine after triage (v8.45.0+) — auto-forwards CI failures and review comments to agents
- **Never** auto-executes any workflow

**Requirements:**
- `OCTOPUS_SENTINEL_ENABLED=true` must be set
- `gh` CLI installed and authenticated

---

### `/octo:schedule`

Manage scheduled workflow jobs — add, list, enable, disable, remove, view logs.

**Aliases:** `jobs`, `cron`

**Usage:**
```
/octo:schedule                          # Dashboard — show all jobs
/octo:schedule add a daily security scan at 9am
/octo:schedule enable <job-id>
/octo:schedule disable <job-id>
/octo:schedule remove <job-id>
/octo:schedule logs [job-id]
```

**Natural language:** Describe what you want scheduled in plain English. The guided wizard collects schedule, workflow, and budget.

**What you get:**
- Job dashboard with status, last run, next run, daily spend
- Budget gates — jobs stop when daily spend limit is reached
- Kill switches — emergency stop per-job or all-jobs

---

### `/octo:scheduler`

Manage the Claude Octopus scheduled workflow runner daemon.

**Aliases:** `sched`

**Usage:**
```
/octo:scheduler             # Show status (default)
/octo:scheduler start       # Start the daemon
/octo:scheduler stop        # Stop the daemon
/octo:scheduler emergency-stop  # Kill all jobs immediately
```

**What it shows on status:**
- Whether the daemon is running and for how long
- Number of active jobs
- Current daily spend
- Kill switch status

**Note:** Add jobs with `/octo:schedule`, not this command. This command manages the daemon process only.

---

## Admin

### `/octo:claw`

OpenClaw instance administration across five platforms.

**Usage:**
```
/octo:claw                              # Auto-detect platform, run diagnostics
/octo:claw update openclaw              # Update OpenClaw to latest stable
/octo:claw harden my server             # Run security hardening checklist
/octo:claw setup openclaw on proxmox    # Guided installation on Proxmox LXC
/octo:claw check gateway health         # Gateway and channel diagnostics
```

**Supported platforms:**

| Platform | What it manages |
|----------|----------------|
| macOS | Homebrew, launchd, Application Firewall, APFS, FileVault |
| Ubuntu/Debian | apt, systemd, ufw, journalctl, unattended-upgrades |
| Docker | docker compose, container health, volumes, log drivers |
| Oracle OCI | ARM instances, VCN/NSG networking, block volumes, Tailscale |
| Proxmox | VMs (qm), LXC containers (pct), ZFS, vzdump, clustering |

**OpenClaw management:**
- Gateway lifecycle: start, stop, restart, status, health, logs
- Diagnostics: `openclaw doctor`, `openclaw security audit`
- Configuration: channels, models, agents, sessions, skills, plugins
- Updates: channel management (stable/beta/dev), backup, rollback

**Natural language triggers:**
- `octo manage my openclaw server`
- `octo harden my server`
- `octo check server health`

---

### `/octo:octo`

[Legacy] Redirects to `/octo:auto`. Kept for backward compatibility.

**Usage:**
```
/octo:octo research OAuth patterns
```

**Behavior:** Shows a notice that the command has been renamed, then routes to `/octo:auto`.

---

## Safety

### `/octo:careful`

Activate destructive command warnings for the current session.

**Usage:**
```
/octo:careful
```

**What it does:**
- Adds a PreToolUse safety net on Bash commands
- Warns before destructive commands, requiring confirmation
- Session-scoped — resets when the session ends

**Detected patterns:**

| Pattern | Example |
|---------|---------|
| Recursive delete | `rm -rf` (except safe targets: node_modules, dist, .next, build, coverage) |
| Database drop | `DROP TABLE`, `DROP DATABASE`, `TRUNCATE` |
| Force push | `git push --force`, `git push -f` |
| Hard reset | `git reset --hard` |
| Discard changes | `git checkout .`, `git restore .` |
| Container/cluster | `kubectl delete`, `docker rm -f`, `docker system prune` |

**Denial audit log (v9.21.0+, CC v2.1.89+):**

When careful mode is active and Claude Code's auto-mode denies a command, the denial is logged to `~/.claude-octopus/denied-commands.log` with the tool name and reason. Arguments are never logged for security. The log rotates at 100KB. Disable with `OCTO_CAREFUL_MODE=off`.

**Deactivation:** Automatic at session end, or remove the state file manually.

---

### `/octo:freeze`

Restrict Edit and Write operations to a specific directory boundary.

**Usage:**
```
/octo:freeze src/auth
/octo:freeze ./packages/core
/octo:freeze /absolute/path/to/module
```

**What it does:**
- Blocks Edit/Write to files **outside** the specified directory
- Read, Bash, Glob, Grep remain unrestricted (investigation is not blocked)
- Session-scoped

**Deactivation:** `/octo:unfreeze`

---

### `/octo:guard`

Activate both careful mode and freeze mode in a single command.

**Usage:**
```
/octo:guard src/auth
/octo:guard ./packages/core
```

**What it does:**
- Enables destructive command warnings (same as `/octo:careful`)
- Enables edit boundary enforcement (same as `/octo:freeze <dir>`)

**Recommended** for focused work in sensitive codebases.

**Deactivation:** `/octo:unfreeze` removes the edit boundary; careful mode remains active until session end.

---

### `/octo:unfreeze`

Remove the edit boundary set by `/octo:freeze` or `/octo:guard`.

**Usage:**
```
/octo:unfreeze
```

**What it does:**
- Removes directory restriction on Edit/Write operations
- Does **not** deactivate careful mode (destructive command warnings stay active if enabled)

---

## Session & Insights

### Session Auto-Titling (v9.21.0+, CC v2.1.94+)

When you invoke any `/octo:` command, the session is automatically titled "Octopus: /octo:review" (etc.) for easier identification in `/resume`. Only the first `/octo:` command per session sets the title — subsequent commands don't overwrite. If you `/rename` the session, auto-titling is suppressed. Disable with `OCTOPUS_AUTO_TITLE=false`.

---

### `/octo:costs`

Show a cost breakdown by provider and workflow for the current session.

**Usage:**
```
/octo:costs
```

**What it shows:**
- Per-provider token usage (input/output) and estimated cost
- Per-workflow breakdown (which commands consumed what)
- Cumulative session total
- Historical comparison when previous session data exists

**Data sources:** `~/.claude-octopus/usage/`, `~/.claude-octopus/routing.log`

---

### `/octo:retro`

Generate data-driven engineering retrospectives from git history.

**Usage:**
```
/octo:retro              # Last 7 days (default)
/octo:retro 24h          # Last 24 hours
/octo:retro 14d          # Last 14 days
/octo:retro 30d          # Last 30 days
```

**What it does:**
- Mines git history for commit patterns, contributor breakdown, and hotspots
- Identifies AI-assisted commits vs manual commits
- Surfaces session analysis and trends
- Generates a structured retrospective report

---

### `/octo:history`

Query past workflow results from the persistent run store.

**Usage:**
```
/octo:history                    # Last 10 runs
/octo:history 20                 # Last 20 runs
/octo:history discover           # Filter by workflow type
/octo:history 7d                 # Filter by time window
```

**What it shows:**
- Workflow type, timestamp, duration, and provider usage
- Filterable by workflow name, time window, or count
- Requires at least one previous multi-AI workflow run to populate the store

**Data source:** `~/.claude-octopus/runs/run-log.jsonl`

---

### `/octo:resume`

Resume a previously-running Claude agent by ID.

**Usage:**
```
/octo:resume <agent-id>
/octo:resume <agent-id> "fix the failing test in auth.ts"
```

**What it does:**
- Looks up the agent's transcript and continues where it left off
- Optionally accepts a follow-up prompt to redirect the agent
- Falls back to spawning a fresh agent if continuation is not supported

**Requirements:**
- Claude Code v2.1.34+ (`SUPPORTS_CONTINUATION=true`)
- Agent Teams enabled
- Agent must be a Claude agent (Codex/Gemini agents don't support transcripts)

**Find agent IDs:** Check `/octo:sentinel` output or `~/.claude-octopus/results/` for recent result files.

---

### `/octo:discipline`

Toggle discipline mode — automatic verification, brainstorming, and review gates.

**Usage:**
```
/octo:discipline on       # Enable auto-invoke discipline checks
/octo:discipline off      # Disable (manual invoke only)
/octo:discipline status   # Show current state
```

**Gates (when enabled):**

| Gate | Trigger | What it does |
|------|---------|-------------|
| Brainstorm | Before writing any code | Ensures approach has been discussed/planned |
| Verification | Before claiming "done" or committing | Runs actual verification, requires evidence |
| Review | After completing non-trivial changes | Auto-invokes spec compliance + code quality review |
| Response | When receiving review feedback | Verifies feedback against actual code before implementing |
| Investigation | On any bug, error, or test failure | Root cause investigation before proposing fixes |
| Context | At task start | Detects dev vs knowledge work mode |
| Decision | When comparing options | Structured comparison with criteria and scores |
| Intent | Before creative/writing tasks | Locks in goal and audience first |

**Persists across sessions** via `~/.claude-octopus/config/discipline.conf`.

---

## Project Lifecycle (Skill-Based)

These features are triggered by natural language — they are not slash commands. Claude auto-activates them based on context.

### `Status`

Show where you are in the workflow and what to do next.

**Invocation:** Skill-based — triggered by natural language: "show status", "where am I", "what's next", "progress", "what have I been working on"

**Output:**
- Current phase and position
- Roadmap progress with checkmarks
- Active blockers
- Suggested next action

---

### `Resume`

Pick up where you left off from a previous session.

**Invocation:** Skill-based — triggered by: "resume", "continue", "pick up where I left off", "what was I doing", "restore session"

**Behavior:**
1. Reads `.octo/STATE.md` for current position
2. Loads context using adaptive tier
3. Shows restoration summary
4. Suggests next action

---

### `Ship`

Package and finalize completed work for delivery.

**Invocation:** Skill-based — triggered by: "ship", "deliver", "finalize", "I'm done", "complete the project"

**Behavior:**
1. Verifies project is ready (all phases complete)
2. Runs Multi-AI security audit (Codex + Gemini + Claude)
3. Captures lessons learned
4. Archives project state
5. Creates shipped checkpoint

---

### `Issues`

Track blockers, bugs, and gaps across sessions.

**Invocation:** Skill-based — triggered by: "add issue", "show issues", "track this problem", "what issues do we have"

**Subcommands (via natural language):**
- List all open issues
- Add new issue: `add <description>`
- Resolve: `resolve <id>`
- Show details: `show <id>`

**Issue ID format:** `ISS-YYYYMMDD-NNN`

**Severity levels:** critical, high, medium, low

---

### `Rollback`

Roll back to a previous checkpoint via git.

**Invocation:** Skill-based — triggered by: "rollback", "revert", "undo", "go back to", "restore checkpoint"

**Usage:** "rollback to checkpoint X", "list checkpoints", "revert last change"

**Safety:**
- Creates a pre-rollback checkpoint automatically
- Preserves LESSONS.md (never rolled back)
- Requires explicit confirmation before destructive action

---

## Visual Indicators

When Claude Octopus activates external CLIs, you'll see visual indicators:

| Indicator | Meaning | Provider |
|-----------|---------|----------|
| 🐙 | Multi-AI mode active | Multiple providers |
| 🔴 | Codex CLI executing | OpenAI (your OPENAI_API_KEY) |
| 🟡 | Gemini CLI executing | Google (your GEMINI_API_KEY) |
| 🟣 | Perplexity Sonar search | Your PERPLEXITY_API_KEY |
| 🔵 | Claude subagent | Included with Claude Code |

**Rule of thumb:**
- `/octo:*` commands and `octo ...` natural-language requests can activate external providers
- Simple file reads, git commands, shell commands, and small edits stay Claude-only
- `/octo:multi` is the manual override when you want all providers on a task that would normally stay single-model

**Example:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching authentication patterns

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis
```

---

## Natural Language Triggers

Instead of slash commands, you can use natural language with the `octo` prefix:

| You Say | Equivalent Command |
|---------|--------------------|
| `octo research OAuth patterns` | `/octo:discover OAuth patterns` |
| `octo build user auth` | `/octo:develop user auth` |
| `octo review my code` | `/octo:review` |
| `octo debate X vs Y` | `/octo:debate X vs Y` |
| `octo plan a new feature` | `/octo:plan new feature` |
| `octo spec out the chat system` | `/octo:spec chat system` |
| `run this with all providers: review auth.ts` | `/octo:multi "review auth.ts"` |

**Reliable activators:**
- `octo research ...`, `octo discover ...`, `/octo:discover ...`
- `octo define ...`, `octo scope ...`, `/octo:define ...`
- `octo build ...`, `octo implement ...`, `/octo:develop ...`
- `octo review ...`, `octo validate ...`, `/octo:review ...`
- `/octo:multi ...` or "run this with all providers ..." for forced parallel mode

**Usually Claude-only:**
- "read `file.ts`", "show git status", "find all routes", "fix this typo"
- factual questions or small edits that do not benefit from multi-provider orchestration

**Why `octo`?** Common words like "research" or "review" may conflict with Claude's built-in behaviors. The `octo` prefix ensures reliable activation.

**Need a quick shortcut?** The most common wrappers are still `/octo:research`, `/octo:review`, and `/octo:security`; they are regular commands, not a separate doc set.

---

## See Also

- **[Documentation Guide](./README.md)** — Pick the right doc quickly
- **[CLI Reference](./CLI-REFERENCE.md)** — Direct CLI usage (advanced)
- **[README](../README.md)** — Main documentation
