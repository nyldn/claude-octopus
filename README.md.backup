<p align="center">
  <img src="assets/social-preview.jpg" alt="Claude Octopus - Multi-tentacled orchestrator for Claude Code" width="640">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/Double_Diamond-Design_Thinking-orange" alt="Double Diamond">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-7.4.0-blue" alt="Version 7.4.0">
</p>

# Claude Octopus

**Multi-AI orchestrator for Claude Code** - coordinates Codex, Gemini, and Claude CLIs using Double Diamond methodology.

> *Why have one AI do the work when you can have eight squabble about it productively?* 🐙

## TL;DR

| What It Does | How |
|--------------|-----|
| **Parallel AI execution** | Run multiple AI models simultaneously |
| **Structured workflows** | Double Diamond: Research → Define → Develop → Deliver |
| **Quality gates** | 75% consensus threshold before delivery |
| **Smart routing** | Auto-detects intent and picks the right AI model |
| **Agent discovery** | Find the right tentacle in <1 min (was 5-10 min) |
| **AI Debate Hub** | Structured 3-way debates (Claude + Gemini + Codex) 🆕 |
| **Adversarial review** | AI vs AI debate catches more bugs |
| **Knowledge work** | UX research, strategy, literature review + document export |

**How to use it:**

Just talk to Claude naturally! Claude Octopus automatically activates when you need multi-AI collaboration:

- 💬 "Research OAuth authentication patterns and summarize the best approaches"
- 💬 "Build a user authentication system"
- 💬 "Review this code for security vulnerabilities"
- 💬 "Use adversarial review to critique my implementation"

Claude coordinates multiple AI models behind the scenes to give you comprehensive, validated results.

---

---

## 🙏 Attribution & Open Source Collaboration

### AI Debate Hub Integration

> **Built on the shoulders of giants** 🤝

Claude-octopus integrates **[AI Debate Hub](https://github.com/wolverin0/claude-skills)** by **[wolverin0](https://github.com/wolverin0)** with deep gratitude and proper attribution:

- **Original Repository**: https://github.com/wolverin0/claude-skills
- **Author**: wolverin0
- **License**: MIT
- **Integration Type**: Git submodule (read-only reference)
- **Version**: v4.7

**What it does**: Enables structured three-way debates where Claude, Gemini CLI, and Codex CLI analyze problems from multiple perspectives. Claude actively participates as both a debater and moderator.

**Claude-octopus enhancements**:
- ✅ Session-aware storage (integrates with Claude Code sessions)
- ✅ Quality gates for debate responses (75% threshold)
- ✅ Cost tracking and analytics
- ✅ Document export to PPTX/DOCX/PDF (via document-delivery skill)
- ✅ Knowledge mode deliberation workflow

**Usage**:
```bash
# Basic debate
/debate Should we use Redis or in-memory cache?

# Thorough analysis
/debate -r 3 -d thorough "Review our API architecture"

# Adversarial security review
/debate -r 5 -d adversarial "Review auth.ts for vulnerabilities"

# Knowledge mode deliberation
/claude-octopus:km on
/debate "Should we enter the European market?"
```

**Initialize submodule** (if not auto-initialized):
```bash
git submodule update --init --recursive
```

**Update to latest** from wolverin0:
```bash
git submodule update --remote .dependencies/claude-skills
```

**Contributing**: Generic improvements to the debate functionality should be contributed to [wolverin0/claude-skills](https://github.com/wolverin0/claude-skills) via pull requests. Claude-octopus-specific integrations remain in this repository.

---

## Quick Start

Get started with Claude Octopus in 2 simple steps:

### Step 1: Install the Plugin

Open Claude Code and run these two commands in the chat:

```
/plugin marketplace add nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

The plugin is now installed and automatically enabled.

<details>
<summary>Troubleshooting Installation</summary>

**If `/claude-octopus:setup` shows "Unknown skill" in Step 2:**

1. Verify the plugin is installed:
   ```
   /plugin list
   ```
   Look for `claude-octopus@nyldn-plugins` in the installed plugins list.

2. Try reinstalling:
   ```
   /plugin uninstall claude-octopus
   /plugin marketplace update nyldn-plugins
   /plugin install claude-octopus@nyldn-plugins
   ```

3. Check for errors in debug logs (from terminal):
   ```bash
   tail -100 ~/.claude/debug/*.txt | grep -i "claude-octopus\|error"
   ```

4. Make sure you're on Claude Code v2.1.10 or later (from terminal):
   ```bash
   claude --version
   ```

</details>

### Step 2: Configure Your AI Providers

Run the setup command in Claude Code:
```
/claude-octopus:setup
```

This will:
- Auto-detect what's already installed
- Show you exactly what you need (you only need ONE provider!)
- Give you shell-specific instructions
- Verify your setup when done

**No terminal context switching needed** - Claude guides you through everything!

### Step 3: Start Using It

Just talk to Claude naturally! Claude Octopus automatically activates when you need multi-AI collaboration:

**For research:**
> "Research microservices patterns and compare their trade-offs"

**For development:**
> "Build a REST API for user management with authentication"

**For code review:**
> "Review my authentication code for security issues"

**For adversarial testing:**
> "Use grapple to debate the best approach for session management"

Claude Octopus automatically detects which providers you have and uses them intelligently.

---

## ✨ What's New in v7.2 - Quick Knowledge Mode Toggle

**Instant mode switching for code vs research!** Toggle between Development Mode (code-focused) and Knowledge Work Mode (research, UX, strategy) with a single command.

### 🎯 Quick Toggle
Switch modes instantly in Claude Code:
```
/claude-octopus:km on      # Enable knowledge work mode
/claude-octopus:km off     # Enable development mode
/claude-octopus:km         # Check current status
```

### 💬 Natural Language
Or just tell me:
- "Switch to knowledge mode"
- "Enable research mode"
- "What mode am I in?"

I'll detect and switch automatically! ✨

### 🔧 What Changes
| Aspect | Dev Mode 🔧 | Knowledge Mode 🎓 |
|--------|-------------|-------------------|
| "Review this" | Code review | UX/strategic review |
| "Analyze X" | Technical analysis | Market/user analysis |
| "Research Y" | Technical docs | Academic research |
| Workflows | embrace, probe, tangle | empathize, advise, synthesize |

**Full details:** Run `/claude-octopus:knowledge-mode` or see [CHANGELOG](CHANGELOG.md#720)

<details>
<summary><strong>v7.1 Features (Session-Aware Workflows)</strong></summary>

## ✨ What's New in v7.1 - Session-Aware Workflows

**Claude Code 2.1.10 Integration!** Claude Octopus now organizes work by session for better tracking and isolation.

### 🔗 Session-Aware Results
Results, logs, and plans are now organized per-session:
```
~/.claude-octopus/
├── results/${SESSION_ID}/    # Session-specific results
├── logs/${SESSION_ID}/       # Session-specific logs
└── plans/${SESSION_ID}/      # Session-specific plans
```

### 🚀 Auto-Setup on Init
Run `claude --init` and Claude Octopus automatically:
- Creates session workspace
- Verifies provider availability
- Validates version compatibility

### 📋 plansDirectory Integration
Plans integrate with Claude Code's `plansDirectory` setting for centralized storage.

### 🔄 Enhanced PreToolUse Hooks
Workflow state (phase, quality score, providers) is injected into Claude's context during orchestration.

</details>

<details>
<summary><strong>v6.0 Features (Knowledge Work Mode)</strong></summary>

**Researchers, consultants, and product managers rejoice!** Claude Octopus extends knowledge tentacles beyond code.

### 🎓 Knowledge Work Mode
Toggle between development mode and knowledge work mode:
```bash
./scripts/orchestrate.sh knowledge-toggle
```
**Note:** Now enhanced in v7.2 with `/claude-octopus:km` command for Claude Code!

### 📚 Three New Workflows
| Workflow | Command | Use For |
|----------|---------|---------|
| **Empathize** | `empathize <prompt>` | UX research synthesis, personas, journey maps |
| **Advise** | `advise <prompt>` | Market analysis, strategic frameworks, business cases |
| **Synthesize** | `synthesize <prompt>` | Literature review, research synthesis, gap analysis |

### 🆕 Six New Knowledge Agents
- `ux-researcher` (opus) - User research synthesis and persona development
- `strategy-analyst` (opus) - Strategic frameworks and market intelligence
- `research-synthesizer` (opus) - Literature review and thematic analysis
- `academic-writer` (sonnet) - Research papers and grant proposals
- `exec-communicator` (sonnet) - Executive summaries and board presentations
- `product-writer` (sonnet) - PRDs, user stories, acceptance criteria

[📖 Full Knowledge Workers Guide →](docs/KNOWLEDGE-WORKERS.md)

</details>

<details>
<summary><strong>v5.0 Features (Agent Discovery & Analytics)</strong></summary>

### 🎯 Smart Agent Discovery
- **📚 [Agent Catalog](docs/AGENTS.md)** - 400+ lines documenting all 37 specialized agents
- **🌊 [Visual Decision Trees](docs/agent-decision-tree.md)** - Mermaid flowcharts guide you to the right agent
- **🤖 Keyword-Based Recommendations** - Just describe your need

### 📊 Usage Analytics (Privacy-First)
- **Track what works** - See which agents you use most often
- **Optimize workflows** - Monthly review templates for continuous improvement
- **Command**: `./scripts/orchestrate.sh analytics [days]`

</details>

[📖 Full Changelog →](CHANGELOG.md)

---

## Which Tentacle Do I Need?

Not sure which agent to use? Here are the most common scenarios:

| When You Say... | Claude Octopus Uses... | Why? |
|-----------------|------------------------|------|
| "Research OAuth patterns" | `ai-engineer` | LLM/RAG expertise for research |
| "Design a REST API" | `backend-architect` | Microservices & API design master |
| "Implement with TDD" | `tdd-orchestrator` | Red-green-refactor guru |
| "Review for security" | `security-auditor` | OWASP whisperer |
| "Debug this error" | `debugger` | Stack trace detective |
| "Optimize performance" | `performance-engineer` | Latency hunter |
| "Synthesize user interviews" | `ux-researcher` | Empathy tentacle 🆕 |
| "Market analysis for expansion" | `strategy-analyst` | Framework master 🆕 |
| "Literature review on AI" | `research-synthesizer` | Knowledge weaver 🆕 |

**Or just describe what you need!** Claude Octopus auto-routes to the right tentacle:

> "Build user authentication with OAuth and store sessions in Redis"
> → Routes to: `backend-architect` + `database-architect` working together

> "Analyze competitor pricing strategies and recommend market entry approach" 🆕
> → Routes to: `advise` workflow with `strategy-analyst` + `exec-communicator`

Browse our comprehensive [Agent Catalog](docs/AGENTS.md) with when-to-use guides, anti-patterns, and 400+ lines of examples for all 37 specialized agents!

---

## Companion Skills

Extend Claude Octopus with official Claude Code skills for specific domains:

- 🧪 **Testing:** `webapp-testing` - Playwright automation
- 🛠️ **Customization:** `skill-creator` - Build custom workflows
- 🔌 **Integration:** `mcp-builder` - Connect external APIs
- 🎨 **Design:** `frontend-design`, `artifacts-builder`, `shadcn` - UI/UX tools
- 📄 **Documents:** `docx`, `pdf`, `pptx`, `xlsx` - Office file handling

**How it works:** Skills are available to Claude (the orchestrator), not to spawned agents. Claude coordinates agents and applies skills before/after orchestration.

[📖 See all companion skills and examples →](docs/COMPANION-SKILLS.md)

---

## Workflow Skills

Claude Octopus auto-activates specialized workflows when you use certain phrases:

- 🔍 **Quick Code Review** - "review this code" → 2-5 min multi-agent review with quality gates
- 🔬 **Deep Research** - "research React state management" → 4-perspective parallel analysis
- 🛡️ **Adversarial Security** - "security audit" → Red team attack + blue team defense + remediation

These skills automatically trigger the right Octopus workflow (probe, grasp, tangle, squeeze) based on your request.

[📖 See all workflow skills and examples →](docs/WORKFLOW-SKILLS.md)


## Provider Installation (Reference)

The `/claude-octopus:setup` command auto-detects and guides you through this, but here's the reference if you need it:

**You only need ONE provider to get started** (not both!). Choose based on your preference:

### Option A: OpenAI Codex CLI (Best for code generation)
```bash
npm install -g @openai/codex
codex login  # OAuth recommended
# OR
export OPENAI_API_KEY="sk-..."  # Get from https://platform.openai.com/api-keys
```

### Option B: Google Gemini CLI (Best for analysis)
```bash
npm install -g @google/gemini-cli
gemini  # OAuth recommended
# OR
export GEMINI_API_KEY="AIza..."  # Get from https://aistudio.google.com/app/apikey
```

### Making API Keys Permanent

To make API keys available in every terminal session:

```bash
# For zsh (macOS default)
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrc
source ~/.zshrc

# For bash (Linux default)
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.bashrc
source ~/.bashrc
```

### Check Your Setup

To verify everything is working, run in Claude Code:
```
/claude-octopus:setup
```

Or directly in terminal:
```bash
./scripts/orchestrate.sh detect-providers
```

---

## How It Works

```
     DISCOVER         DEFINE         DEVELOP          DELIVER
     (probe)          (grasp)        (tangle)          (ink)

    \         /     \         /     \         /     \         /
     \   *   /       \   *   /       \   *   /       \   *   /
      \ * * /         \     /         \ * * /         \     /
       \   /           \   /           \   /           \   /
        \ /             \ /             \ /             \ /

   Diverge then      Converge to      Diverge with     Converge to
    converge          problem          solutions        delivery
```

Claude Octopus detects your intent and automatically routes to the right workflow:

| When You Say... | It Routes To |
|-----------------|--------------|
| "Research...", "Explore...", "Investigate..." | **Probe** (Research phase) |
| "Build...", "Implement...", "Create..." | **Tangle + Ink** (Dev + Deliver) |
| "Review...", "Test...", "Validate..." | **Ink** (Quality check) |
| "Security audit...", "Red team..." | **Squeeze** (Security review) |
| "Debate...", "Use adversarial..." | **Grapple** (AI vs AI) |

---

<details>
<summary><strong>🔧 Advanced: Direct CLI Usage</strong></summary>

If you want to run Claude Octopus commands directly (outside of Claude Code):

### Core Commands

| Command | What It Does |
|---------|--------------|
| `auto <prompt>` | Smart routing - picks best workflow automatically |
| `embrace <prompt>` | Full 4-phase Double Diamond workflow |
| `probe <prompt>` | Research phase - parallel exploration |
| `tangle <prompt>` | Development phase - parallel implementation |
| `grapple <prompt>` | Adversarial debate between AI models |
| `squeeze <prompt>` | Red team security review |
| `octopus-configure` | Interactive configuration wizard |
| `preflight` | Verify all dependencies |
| `status` | Show provider status and running agents |

### Examples

```bash
# Smart auto-routing
./scripts/orchestrate.sh auto "build user authentication"

# Full Double Diamond workflow
./scripts/orchestrate.sh embrace "create user dashboard"

# Specific phases
./scripts/orchestrate.sh probe "research OAuth patterns"
./scripts/orchestrate.sh tangle "implement user login"

# Adversarial review
./scripts/orchestrate.sh grapple "implement JWT auth"
./scripts/orchestrate.sh squeeze "review login security"

# Configuration
./scripts/orchestrate.sh octopus-configure
./scripts/orchestrate.sh preflight
./scripts/orchestrate.sh status
```

**Common options:** `-n` (dry-run), `-v` (verbose), `-t 600` (timeout), `--cost-first`, `--quality-first`

</details>

<details>
<summary><strong>🔀 Provider-Aware Routing (v4.8)</strong></summary>

Claude Octopus intelligently routes tasks based on your subscription tiers and costs.

### CLI Flags

```bash
--provider <name>     # Force provider: codex, gemini, claude, openrouter
--cost-first          # Prefer cheapest capable provider
--quality-first       # Prefer highest-tier provider
--openrouter-nitro    # Use fastest OpenRouter routing
--openrouter-floor    # Use cheapest OpenRouter routing
```

### Cost Optimization Strategies

| Strategy | Description |
|----------|-------------|
| `balanced` (default) | Smart mix of cost and quality |
| `cost-first` | Prefer cheapest capable provider |
| `quality-first` | Prefer highest-tier provider |

### Provider Tiers

The configuration wizard sets your subscription tier for each provider:

| Provider | Tiers | Cost Behavior |
|----------|-------|---------------|
| Codex/OpenAI | free, plus, pro, api-only | Routes based on tier |
| Gemini | free, google-one, workspace, api-only | Workspace = bundled (free) |
| Claude | pro, max-5x, max-20x, api-only | Conserves Opus for complex tasks |
| OpenRouter | pay-per-use | 400+ models as fallback |

**Example:** If you have Google Workspace (bundled Gemini), the system prefers Gemini for heavy analysis since it's "free" with your work account.

```bash
# Check current provider status
./scripts/orchestrate.sh status

# Force cost-first routing
./scripts/orchestrate.sh --cost-first auto "research best practices"
```

</details>

<details>
<summary><strong>🎯 Model Selection & Inheritance</strong></summary>

Claude Octopus agents can specify which Claude model to use. Agents inherit the Claude Code session model by default, but can override for specific use cases.

### Model Options

| Model Value | Behavior | When to Use |
|-------------|----------|-------------|
| `inherit` (default) | Uses the Claude Code session model (usually Sonnet) | Most agents - let user control cost/quality |
| `opus` | Forces Claude Opus 4.5 | Complex reasoning, architecture, strategy |
| `sonnet` | Forces Claude Sonnet 4.5 | Balanced tasks, implementation, writing |
| `haiku` | Forces Claude Haiku | Simple, fast tasks (future) |

### Cost Implications

Understanding model costs helps optimize your AI spend:

| Model | Relative Cost | Use For |
|-------|---------------|---------|
| **Opus** | ~15× Sonnet | Strategic analysis, complex architecture, adversarial review |
| **Sonnet** | Baseline | Implementation, code review, documentation |
| **Haiku** | ~0.2× Sonnet | Simple queries, format conversion |

### Agent Model Configuration

Most agents use `model: inherit` to respect your session preferences:

```yaml
# agents/personas/backend-architect.md
---
model: opus    # Complex architecture tasks justify Opus cost
---
```

```yaml
# agents/personas/frontend-developer.md
---
model: inherit  # Let user decide via session model
---
```

**Recommendation**: Leave agents on `inherit` unless the task specifically requires Opus-level reasoning (architecture, strategy, complex debugging).

</details>

<details>
<summary><strong>🤼 Crossfire: Adversarial Review (v4.7)</strong></summary>

Different AI models have different blind spots. Crossfire forces models to critique each other.

### Grapple - Adversarial Debate

```bash
./scripts/orchestrate.sh grapple "implement password reset API"
./scripts/orchestrate.sh grapple --principles security "implement JWT auth"
```

**How it works:**
```
Round 1: Codex proposes → Gemini proposes (parallel)
Round 2: Gemini critiques Codex → Codex critiques Gemini
Round 3: Synthesis determines winner + final implementation
```

### Squeeze - Red Team Security Review

```bash
./scripts/orchestrate.sh squeeze "implement user login form"
```

| Phase | Team | Action |
|-------|------|--------|
| 1 | Blue Team (Codex) | Implements secure solution |
| 2 | Red Team (Gemini) | Finds vulnerabilities |
| 3 | Remediation | Fixes all issues |
| 4 | Validation | Verifies all fixed |

### Constitutional Principles

| Principle | Focus |
|-----------|-------|
| `general` | Overall quality (default) |
| `security` | OWASP Top 10, secure coding |
| `performance` | N+1 queries, caching, async |
| `maintainability` | Clean code, testability |

</details>

<details>
<summary><strong>💎 Double Diamond Methodology</strong></summary>

### Phase 1: PROBE (Discover)
Parallel research from 4 perspectives - problem space, existing solutions, edge cases, technical feasibility.

```bash
./scripts/orchestrate.sh probe "What are the best approaches for real-time notifications?"
```

### Phase 2: GRASP (Define)
Multi-tentacled consensus on problem definition, success criteria, and constraints.

```bash
./scripts/orchestrate.sh grasp "Define requirements for notification system"
```

### Phase 3: TANGLE (Develop)
Enhanced map-reduce with 75% quality gate threshold.

```bash
./scripts/orchestrate.sh tangle "Implement notification service"
```

### Phase 4: INK (Deliver)
Validation and final deliverable generation.

```bash
./scripts/orchestrate.sh ink "Deliver notification system"
```

### Full Workflow

```bash
./scripts/orchestrate.sh embrace "Create a complete user dashboard feature"
```

### Quality Gates

| Score | Status | Behavior |
|-------|--------|----------|
| >= 90% | PASSED | Proceed to ink |
| 75-89% | WARNING | Proceed with caution |
| < 75% | FAILED | Flags for review |

</details>

<details>
<summary><strong>⚡ Smart Auto-Routing</strong></summary>

The `auto` command extends the right tentacle for the job:

| Tentacle | Keywords | Routes To |
|----------|----------|-----------|
| 🔍 Probe | research, explore, investigate | `probe` |
| 🤝 Grasp | define, clarify, scope | `grasp` |
| 🦑 Tangle | develop, build, implement | `tangle` → `ink` |
| 🖤 Ink | qa, test, validate | `ink` |
| 🤼 Grapple | adversarial, debate | `grapple` |
| 🦑 Squeeze | security audit, red team | `squeeze` |
| 🎨 Camouflage | design, UI, UX | `gemini` |
| ⚡ Jet | fix, debug, refactor | `codex` |
| 🖼️ Squirt | generate image, icon | `gemini-image` |

**Examples:**
```bash
./scripts/orchestrate.sh auto "research caching best practices"    # -> probe
./scripts/orchestrate.sh auto "build the caching layer"            # -> tangle + ink
./scripts/orchestrate.sh auto "security audit the auth module"     # -> squeeze
./scripts/orchestrate.sh auto "fix the cache bug"                  # -> codex
```

</details>

<details>
<summary><strong>🛠️ Optimization Command</strong></summary>

Auto-detect optimization domain and route to specialized agents:

| Domain | Keywords | Agent |
|--------|----------|-------|
| ⚡ Performance | slow, latency, cpu | `codex` |
| 💰 Cost | budget, spend, rightsizing | `gemini` |
| 🗃️ Database | query, index, slow queries | `codex` |
| 📦 Bundle | webpack, tree-shake, minify | `codex` |
| ♿ Accessibility | wcag, a11y, aria | `gemini` |
| 🔍 SEO | meta tags, sitemap | `gemini` |
| 🖼️ Images | compress, webp, lazy load | `gemini` |

```bash
./scripts/orchestrate.sh optimize "My app is slow on mobile"
./scripts/orchestrate.sh optimize "Reduce our AWS bill"
./scripts/orchestrate.sh auto "full site audit"  # All domains
```

</details>

<details>
<summary><strong>🔧 Smart Configuration Wizard</strong></summary>

The configuration wizard sets up Claude Octopus based on your use intent and resource tier.

```bash
./scripts/orchestrate.sh octopus-configure
```

### Use Intent (affects persona selection)

| Intent | Default Persona |
|--------|-----------------|
| Backend Development | backend-architect |
| Frontend Development | frontend-architect |
| UX Research | researcher |
| DevOps/Infrastructure | backend-architect |
| Security/Code Review | security-auditor |

### Resource Tier (affects model routing)

| Tier | Plan | Behavior |
|------|------|----------|
| Conservative | Pro/Free | Cheaper models by default |
| Balanced | Max 5x | Smart Opus usage |
| Full Power | Max 20x | Premium models freely |
| Cost-Aware | API Only | Tracks token costs |

```bash
# Reconfigure anytime
./scripts/orchestrate.sh config
```

</details>

<details>
<summary><strong>🔐 Authentication</strong></summary>

### Commands

```bash
./scripts/orchestrate.sh auth status  # Check status
./scripts/orchestrate.sh login        # OAuth login
./scripts/orchestrate.sh logout       # Clear tokens
```

### Methods

| Method | How | Best For |
|--------|-----|----------|
| OAuth | `login` command | Subscription users |
| API Key | Environment variable | API access, CI/CD |

</details>

<details>
<summary><strong>🤖 Available Agents</strong></summary>

| Agent | Model | Best For |
|-------|-------|----------|
| `codex` | GPT-5.1-Codex-Max | Complex code, deep refactoring |
| `codex-standard` | GPT-5.2-Codex | Standard implementation |
| `codex-mini` | GPT-5.1-Codex-Mini | Quick fixes (cost-effective) |
| `gemini` | Gemini 3 Pro | Deep analysis, 1M context |
| `gemini-fast` | Gemini 3 Flash | Speed-critical tasks |
| `gemini-image` | Gemini 3 Pro Image | Image generation |
| `codex-review` | GPT-5.2-Codex | Code review mode |
| `openrouter` | Various | Universal fallback (400+ models) |

</details>

<details>
<summary><strong>📚 Full Command Reference</strong></summary>

### Double Diamond

| Command | Description |
|---------|-------------|
| `probe <prompt>` | Parallel research (Discover) |
| `grasp <prompt>` | Consensus building (Define) |
| `tangle <prompt>` | Quality-gated development (Develop) |
| `ink <prompt>` | Validation and delivery (Deliver) |
| `embrace <prompt>` | Full 4-phase workflow |

### Orchestration

| Command | Description |
|---------|-------------|
| `auto <prompt>` | Smart routing |
| `spawn <agent> <prompt>` | Single agent |
| `fan-out <prompt>` | Multiple agents in parallel |
| `map-reduce <prompt>` | Decompose and parallelize |
| `parallel [tasks.json]` | Execute task file |

### Crossfire

| Command | Description |
|---------|-------------|
| `grapple <prompt>` | Adversarial debate |
| `grapple --principles TYPE` | With domain principles |
| `squeeze <prompt>` | Red team security review |

### Management

| Command | Description |
|---------|-------------|
| `status` | Show running agents |
| `kill [id\|all]` | Terminate agents |
| `clean` | Reset workspace |
| `aggregate [filter]` | Combine results |

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `-p, --parallel` | 3 | Max concurrent agents |
| `-t, --timeout` | 300 | Timeout (seconds) |
| `-v, --verbose` | false | Verbose logging |
| `-n, --dry-run` | false | Preview only |
| `--context <file>` | - | Context from previous phase |
| `--ci` | false | CI mode |

</details>

<details>
<summary><strong>🐛 Troubleshooting</strong></summary>

### Commands not showing after install

If `/claude-octopus:setup` doesn't work after installation:

1. **Verify the plugin is installed:**

   In Claude Code chat:
   ```
   /plugin list
   ```
   Look for `claude-octopus@nyldn-plugins` in the installed plugins list.

2. **Restart Claude Code completely:**
   - Exit fully (Ctrl-C twice or Cmd+Q)
   - Restart: `claude --dangerously-skip-permissions`

3. **Reinstall if needed:**

   In Claude Code chat:
   ```
   /plugin uninstall claude-octopus
   /plugin marketplace update nyldn-plugins
   /plugin install claude-octopus@nyldn-plugins
   ```

4. **Check debug logs for errors (from terminal):**
   ```bash
   tail -100 ~/.claude/debug/*.txt | grep -i "claude-octopus\|error"
   ```

5. **Check Claude Code version (from terminal):**
   ```bash
   claude --version  # Need 2.1.10+
   ```

### Pre-flight fails

```bash
./scripts/orchestrate.sh preflight
# Check: codex CLI, gemini CLI, API keys
```

### Quality gate failures

- Break into smaller subtasks
- Increase timeout: `-t 600`
- Check logs: `~/.claude-octopus/logs/`

### Reset workspace

```bash
./scripts/orchestrate.sh clean
./scripts/orchestrate.sh init
```

### Missing CLIs

```bash
npm install -g @openai/codex
npm install -g @google/gemini-cli
```

</details>

<details>
<summary><strong>📜 What's New</strong></summary>

### v6.0.1 - Knowledge Work Mode ⭐ LATEST

- **Knowledge Work Mode** - Toggle between dev and research modes with `knowledge-toggle`
- **3 New Workflows** - `empathize`, `advise`, `synthesize` for knowledge workers
- **6 New Agents** - UX researcher, strategy analyst, research synthesizer, academic writer, exec communicator, product writer
- **New Use Intents** - Strategy/consulting, academic research, product management
- [Knowledge Workers Guide](docs/KNOWLEDGE-WORKERS.md) - Complete documentation
- Total agents: 37 (up from 31)

### v5.0.0 - Agent Discovery & Analytics

- **90% faster agent discovery** - from 5-10 minutes to <1 minute
- [Agent Catalog](docs/AGENTS.md) - 400+ lines with when/why/examples for all 37 agents
- [Visual Decision Trees](docs/agent-decision-tree.md) - Mermaid flowcharts by phase/task/stack
- Privacy-preserving usage analytics with `analytics` command
- Keyword-based agent recommendations
- Monthly review templates for optimization

### v4.8.0 - Multi-Provider Routing

- Provider scoring algorithm (0-150 scale)
- Cost optimization: `--cost-first`, `--quality-first`
- OpenRouter integration (400+ models)
- Enhanced setup wizard (10 steps)
- Auto-detection of provider tiers

### v4.7.0 - Adversarial Review

- `grapple` - AI vs AI debate
- `squeeze` - Red team security review
- Constitutional principles system
- Auto-routing for security/debate intents

[Full Changelog →](CHANGELOG.md)

</details>

<details>
<summary><strong>⚡ Advanced Features</strong></summary>

### Performance & Visualization

**[Async Task Management & Tmux Visualization](docs/ASYNC-TMUX.md)**
- `--async` - Optimized progress tracking with elapsed time
- `--tmux` - Watch agents work in real-time with split panes
- Visual layouts for multi-agent workflows
- Environment variables for global configuration

### Extended Documentation

- **[Workflow Skills](docs/WORKFLOW-SKILLS.md)** - Deep dive into quick-review, deep-research, and adversarial-security
- **[Companion Skills](docs/COMPANION-SKILLS.md)** - Full catalog of testing, design, and integration skills
- **[Agent Catalog](docs/AGENTS.md)** - Complete guide to all 31 specialized agents
- **[Decision Trees](docs/agent-decision-tree.md)** - Visual flowcharts for agent selection

</details>

<details>
<summary>🐙 Meet the Mascot</summary>

```
                      ___
                  .-'   `'.
                 /         \
                 |         ;
                 |         |           ___.--,
        _.._     |0) ~ (0) |    _.---'`__.-( (_.
 __.--'`_.. '.__.\    '--. \_.-' ,.--'`     `""`
( ,.--'`   ',__ /./;   ;, '.__.'`    __
_`) )  .---.__.' / |   |\   \__..--""  """--.,_
`---' .'.''-._.-'`_./  /\ '.  \ _.-~~~````~~~-._`-.__.'
     | |  .' _.-' |  |  \  \  '.               `~---`
      \ \/ .'     \  \   '. '-._)
       \/ /        \  \    `=.__`~-.
       / /\         `) )    / / `"".`\
 , _.-'.'\ \        / /    ( (     / /
  `--~`   ) )    .-'.'      '.'.  | (
         (/`    ( (`          ) )  '-;
          `      '-;         (-'
```

*"Eight tentacles, infinite possibilities."*

</details>

---

## Testing

### Quick Start
```bash
# Run all tests
make test

# Or using npm
npm test
```

### Test Categories
| Category | Command | Duration | Purpose |
|----------|---------|----------|---------|
| Smoke | `make test-smoke` | <30s | Pre-commit validation |
| Unit | `make test-unit` | 1-2min | Function-level tests |
| Integration | `make test-integration` | 5-10min | Workflow tests |
| E2E | `make test-e2e` | 15-30min | Real execution tests |
| All | `make test-all` | 20-40min | Complete test suite |

### Coverage
- Current coverage: 95%+ function coverage
- Quality gates tested at multiple thresholds
- All Double Diamond workflows validated
- Error recovery and provider failover tested

### For Developers
```bash
# Run specific category
make test-unit

# Verbose output
make test-verbose

# Generate coverage report
make test-coverage

# Clean test artifacts
make clean-tests
```

See [tests/README.md](tests/README.md) for comprehensive testing documentation.

---

## Why Claude Octopus?

| What Others Do | What We Do |
|----------------|------------|
| Single-agent execution | 8 agents working simultaneously |
| Hope for the best | Quality gates with 75% consensus |
| One model, one price | Cost-aware routing to cheaper models |
| Ad-hoc workflows | Double Diamond methodology baked in |
| Single perspective | Adversarial AI-vs-AI review |

---

## Acknowledgments

Claude Octopus stands on the shoulders of giants:

- **[wolverin0/claude-skills](https://github.com/wolverin0/claude-skills)** by **wolverin0** - AI Debate Hub enables structured three-way debates between Claude, Gemini CLI, and Codex CLI. Integrated as a git submodule with claude-octopus enhancements (quality gates, cost tracking, document export). wolverin0's innovative "Claude as participant" design pattern is brilliant—Claude doesn't just orchestrate, it actively debates. This integration demonstrates proper open-source collaboration: clear attribution, hybrid approach (original + enhancement layer), and a path to contribute improvements back upstream. MIT License.

- **[obra/superpowers](https://github.com/obra/superpowers)** by **Jesse Vincent** - Several discipline skills (TDD, systematic debugging, verification, planning, branch finishing) were inspired by the excellent patterns in this Claude Code skills library. The "Iron Law" enforcement approach and anti-rationalization techniques are particularly valuable. MIT License.

- **Double Diamond** methodology by the [UK Design Council](https://www.designcouncil.org.uk/our-resources/the-double-diamond/) - The probe/grasp/tangle/ink workflow structure provides a proven framework for divergent and convergent thinking in design and development.

---

## Contributing

We believe in giving back to the open source community. Here's how you can contribute:

### To Claude-Octopus

1. **Report Issues**: Found a bug? [Open an issue](https://github.com/nyldn/claude-octopus/issues)
2. **Suggest Features**: Have an idea? We'd love to hear it!
3. **Submit PRs**: Improvements welcome—please follow the existing code style
4. **Share Knowledge**: Write about your experience using claude-octopus

### To Upstream Dependencies

When improving claude-octopus, consider whether enhancements benefit the broader community:

**AI Debate Hub (wolverin0/claude-skills)**
- Generic improvements to debate functionality → Submit to [wolverin0/claude-skills](https://github.com/wolverin0/claude-skills)
- Claude-octopus-specific integrations → Keep in this repo
- Examples: Atomic state writes, retry logic, error messages

**Superpowers (obra/superpowers)**
- Improvements to discipline skills → Submit to [obra/superpowers](https://github.com/obra/superpowers)
- Claude-octopus-specific workflows → Keep in this repo

### Contribution Principles

✅ **Do**:
- Maintain clear attribution
- Test thoroughly (95%+ coverage standard)
- Follow existing patterns
- Document your changes
- Consider backward compatibility

❌ **Don't**:
- Break existing workflows
- Remove attribution
- Skip tests
- Introduce unnecessary complexity

### Development Setup

```bash
# Clone with submodules
git clone --recursive https://github.com/nyldn/claude-octopus.git
cd claude-octopus

# Or initialize submodules after cloning
git submodule update --init --recursive

# Run tests
make test

# Run specific test suite
make test-unit
make test-integration
make test-e2e
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## License

MIT License - see [LICENSE](LICENSE)

<p align="center">
  🐙 Made with eight tentacles of love 🐙<br/>
  <a href="https://github.com/nyldn">nyldn</a>
</p>
