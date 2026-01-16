<p align="center">
  <img src="assets/social-preview.jpg" alt="Claude Octopus - Multi-tentacled orchestrator for Claude Code" width="640">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/Double_Diamond-Design_Thinking-orange" alt="Double Diamond">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-4.2.0-blue" alt="Version 4.2.0">
</p>

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

> *An octopus uses its 8 arms in parallel. So does this orchestrator. Coincidence? We think not.* 🐙

<details>
<summary>🐙 Click to meet our mascot</summary>

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

## What's New in 4.2

- **Optimize Command** - Auto-detect and route optimization tasks across 7 domains:
  - ⚡ Performance (speed, latency, memory)
  - 💰 Cost (cloud spend, budget, rightsizing)
  - 🗃️ Database (queries, indexes, slow queries)
  - 📦 Bundle (webpack, tree-shaking, code-splitting)
  - ♿ Accessibility (WCAG, a11y, screen readers)
  - 🔍 SEO (meta tags, structured data, rankings)
  - 🖼️ Images (compression, formats, lazy loading)
- **Shell Completion** - Tab completion for bash, zsh, and fish
  - `eval "$(./orchestrate.sh completion bash)"` - Add to shell profile
  - Completes commands, agents, options, and context-aware suggestions
- **OpenAI Authentication** - Manage Codex CLI auth via OAuth
  - `auth status` - Check authentication status
  - `login` / `logout` - OAuth flow for OpenAI subscription access

<details>
<summary>Previous versions</summary>

### What's New in 4.0

- **Simplified CLI** - Progressive disclosure hides complexity from beginners
  - Simple help by default (3 commands), `help --full` for advanced users
  - Command-specific help: `help auto`, `help research`, etc.
- **Intuitive Aliases** - Clear command names that match the workflow
  - `research` (was: probe), `define` (was: grasp), `develop` (was: tangle), `deliver` (was: ink)
- **Better Error Messages** - "Did you mean?" suggestions and examples
- **Phase Progress** - Shows "Phase 1/4", "Phase 2/4" during execution
- **Curated Agent Personas** - 21 specialized agents (backend-architect, security-auditor, etc.)
- **Ralph-Wiggum Iteration** - Loop until completion with `ralph` command

### What's New in 1.1

- **Conditional Branching** - Decision trees for workflow routing (tentacle paths)
  - `--branch BRANCH` - Force tentacle path: premium|standard|fast
  - `--on-fail ACTION` - Quality gate failure action: auto|retry|escalate|abort
- **Quality Gate Decision Tree** - Intelligent branching on quality outcomes

### What's New in 1.0

- **Double Diamond Workflow** - Structured design thinking process
- **Octopus-Themed Commands** - `probe`, `grasp`, `tangle`, `ink`, `embrace`
- **Smart Auto-Routing** - Intent detection routes to workflows or agents
- **Cost-Aware Routing** - Routes trivial tasks to cheaper models
- **Quality Gates** - 75% success threshold in development phase

</details>

## Why Claude Octopus?

Most Claude Code plugins inject knowledge. **Claude Octopus orchestrates armies.**

| What Others Do | What We Do |
|----------------|------------|
| Inject context via CLAUDE.md | Coordinate multiple AI models in parallel |
| Single-agent execution | 8 agents working simultaneously |
| Hope for the best | Quality gates with 75% consensus threshold |
| One model, one price | Cost-aware routing to cheaper models for simple tasks |
| Ad-hoc workflows | Double Diamond methodology baked in |

### The Architecture Difference

```
┌─────────────────────────────────────────────────────────────────┐
│                      CLAUDE CODE                                 │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐        │
│  │ Other Plugins │  │ Other Plugins │  │ Other Plugins │        │
│  │  (knowledge)  │  │   (hooks)     │  │  (commands)   │        │
│  └───────────────┘  └───────────────┘  └───────────────┘        │
│                              │                                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   CLAUDE OCTOPUS                          │  │
│  │                   (orchestrator)                          │  │
│  └───────────────────────────────────────────────────────────┘  │
│         │              │              │              │          │
└─────────┼──────────────┼──────────────┼──────────────┼──────────┘
          ▼              ▼              ▼              ▼
   ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐
   │  Codex    │  │  Codex    │  │  Gemini   │  │  Gemini   │
   │  (GPT-5)  │  │  (review) │  │  (Pro)    │  │  (Image)  │
   └───────────┘  └───────────┘  └───────────┘  └───────────┘
```

### Why This Matters

| Benefit | How |
|---------|-----|
| **Faster results** | Parallel execution across 8 agents |
| **Better quality** | Multiple perspectives + consensus gates |
| **Lower costs** | Smart routing to appropriate model tiers |
| **Structured thinking** | Double Diamond prevents jumping to solutions |
| **Model diversity** | Best-of-breed: GPT for code, Gemini for analysis |

*An octopus doesn't just have 8 arms - it has neurons in each one. Independent intelligence, coordinated action.*

## Table of Contents

- [Why Claude Octopus?](#why-claude-octopus)
- [Before You Start](#before-you-start)
- [Quick Start](#quick-start)
- [Double Diamond Methodology](#double-diamond-methodology)
- [Smart Auto-Routing](#smart-auto-routing)
- [Optimization Command](#optimization-command)
- [Shell Completion](#shell-completion)
- [Authentication](#authentication)
- [Quality Gates](#quality-gates)
- [Agent Personas](#agent-personas)
- [Ralph-Wiggum Iteration](#ralph-wiggum-iteration)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Agent Setup & Configuration](#agent-setup--configuration)
- [Available Agents](#available-agents)
- [Command Reference](#command-reference)
- [Example Workflows](#example-workflows)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Before You Start

Claude Octopus orchestrates **multiple AI models** (OpenAI Codex + Google Gemini). You'll need API keys for both:

### Required API Keys

| Provider | Get Your Key | Environment Variable |
|----------|-------------|---------------------|
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) | `OPENAI_API_KEY` |
| Google | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | `GEMINI_API_KEY` |

### Set Up Your Keys

```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export OPENAI_API_KEY="sk-..."
export GEMINI_API_KEY="AIza..."
```

### System Requirements

- **Bash 4.0+** (macOS: `brew install bash`)
- **Codex CLI** - `npm install -g @openai/codex` or [installation guide](https://github.com/openai/codex-cli)
- **Gemini CLI** - `npm install -g @google/gemini-cli` or [installation guide](https://github.com/google-gemini/gemini-cli)
- **Optional:** `jq` for JSON task files, `coreutils` for macOS timeout

## Quick Start

### 1. Install

```bash
# Via Claude Code Plugin Marketplace (recommended)
/plugin marketplace add nyldn/claude-octopus

# Or clone directly
git clone https://github.com/nyldn/claude-octopus.git ~/.claude/plugins/claude-octopus
```

### 2. Verify Setup

```bash
# Check all dependencies are configured
./scripts/orchestrate.sh preflight
```

If preflight fails, run the setup wizard:
```bash
./scripts/orchestrate.sh setup
```

### 3. Try It (Dry Run First)

```bash
# Preview what would happen (no API calls)
./scripts/orchestrate.sh -n auto "build a hello world function"

# If that looks good, run for real
./scripts/orchestrate.sh auto "build a hello world function"
```

### 4. Full Workflow Example

```bash
# Let AI choose the best approach (recommended)
./scripts/orchestrate.sh auto "build user authentication"

# Or run the full 4-phase Double Diamond
./scripts/orchestrate.sh embrace "build user authentication"

# Or run individual phases
./scripts/orchestrate.sh research "authentication best practices"  # Phase 1
./scripts/orchestrate.sh define "auth requirements"                # Phase 2
./scripts/orchestrate.sh develop "implement auth feature"          # Phase 3
./scripts/orchestrate.sh deliver "validate auth implementation"    # Phase 4
```

> **Tip:** Use `help` to learn more: `./scripts/orchestrate.sh help` or `./scripts/orchestrate.sh help auto`

## Double Diamond Methodology

Claude Octopus implements the [Double Diamond](https://www.designcouncil.org.uk/our-resources/framework-for-innovation/) design process, providing structured workflows for each phase:

### Phase 1: PROBE (Discover)
**Diverge then converge on understanding**

Parallel research from 4 perspectives:
- Problem space analysis (constraints, requirements, needs)
- Existing solutions research (what worked, what failed)
- Edge cases exploration (potential challenges)
- Technical feasibility (prerequisites, dependencies)

```bash
./scripts/orchestrate.sh probe "What are the best approaches for real-time notifications?"
```

### Phase 2: GRASP (Define)
**Build consensus on the problem**

Multi-tentacled problem definition:
- Core problem statement
- Success criteria
- Constraints and boundaries

```bash
./scripts/orchestrate.sh grasp "Define requirements for notification system"
```

### Phase 3: TANGLE (Develop)
**Diverge with multiple solutions**

Enhanced map-reduce with validation:
- Task decomposition via LLM
- Parallel execution across agents
- Quality gate (75% success threshold)

```bash
./scripts/orchestrate.sh tangle "Implement notification service"
```

### Phase 4: INK (Deliver)
**Converge to validated delivery**

Pre-delivery validation:
- Quality gate verification
- Result synthesis
- Final deliverable generation

```bash
./scripts/orchestrate.sh ink "Deliver notification system"
```

### Full Workflow: EMBRACE
Run all 4 phases sequentially with automatic context passing:

```bash
./scripts/orchestrate.sh embrace "Create a complete user dashboard feature"
```

## Smart Auto-Routing

The `auto` command detects intent and extends the right tentacle for the job. Eight behaviors, eight arms:

| Tentacle | Behavior | Keywords | Routes To |
|----------|----------|----------|-----------|
| 🔍 **Probe** | Reach out to explore | research, explore, investigate, study, discover | `probe` (Discover) |
| 🤝 **Grasp** | Grip the problem | define, clarify, scope, requirements | `grasp` (Define) |
| 🦑 **Tangle** | Weave solutions | develop, build, implement, construct | `tangle` → `ink` |
| 🖤 **Ink** | Deliver with impact | qa, test, validate, verify, audit, check | `ink` (Deliver) |
| 🎨 **Camouflage** | Adapt to context | design, UI, UX, accessibility, theme, responsive | `gemini` agent |
| 🔎 **Hunt** | Seek vulnerabilities | code review, security audit, find bugs | `codex-review` agent |
| ⚡ **Jet** | Move fast | fix, debug, function, class, refactor | `codex` agent |
| 🖼️ **Squirt** | Create visuals | generate image, icon, logo, diagram, banner | `gemini-image` agent |

*Each tentacle knows its specialty. The octopus routes to the right one automatically.*

**Examples:**
```bash
./scripts/orchestrate.sh auto "research best practices for caching"     # -> 🔍 probe
./scripts/orchestrate.sh auto "build the caching layer"                 # -> 🦑 tangle → ink
./scripts/orchestrate.sh auto "review the cache implementation"         # -> 🖤 ink
./scripts/orchestrate.sh auto "fix the cache invalidation bug"          # -> ⚡ codex
./scripts/orchestrate.sh auto "design a responsive dashboard"           # -> 🎨 gemini
./scripts/orchestrate.sh auto "generate an app icon"                    # -> 🖼️ gemini-image
```

## Optimization Command

The `optimize` command (v4.2) auto-detects the type of optimization needed and routes to specialized agents.

### Supported Domains

| Domain | Keywords | Agent | Focus |
|--------|----------|-------|-------|
| ⚡ Performance | slow, latency, throughput, p99, cpu, memory | `codex` | Bottleneck analysis, profiling, benchmarks |
| 💰 Cost | cost, budget, spend, bill, rightsizing, reserved | `gemini` | Cloud spend, resource optimization |
| 🗃️ Database | query, sql, index, slow queries, postgres, mysql | `codex` | Query optimization, indexing, schema |
| 📦 Bundle | webpack, tree-shake, code-split, minify, vite | `codex` | Bundle size, lazy loading, compression |
| ♿ Accessibility | wcag, a11y, screen reader, aria, contrast | `gemini` | WCAG compliance, keyboard nav, semantics |
| 🔍 SEO | search engine, meta tags, structured data, sitemap | `gemini` | Meta optimization, JSON-LD, Core Web Vitals |
| 🖼️ Images | compress, webp, avif, lazy load, srcset | `gemini` | Format conversion, responsive images, CDN |

### Examples

```bash
# Auto-detect optimization domain
./scripts/orchestrate.sh optimize "My app is slow on mobile"
# -> ⚡ Performance optimization

./scripts/orchestrate.sh optimize "Reduce our AWS bill"
# -> 💰 Cost optimization

./scripts/orchestrate.sh optimize "Fix slow database queries"
# -> 🗃️ Database optimization

./scripts/orchestrate.sh optimize "Make the site accessible"
# -> ♿ Accessibility optimization

./scripts/orchestrate.sh optimize "Improve search rankings"
# -> 🔍 SEO optimization
```

*The octopus knows which tentacle to extend for each optimization task.*

## Shell Completion

Tab completion (v4.2) for bash, zsh, and fish. Completes commands, agents, options, and provides context-aware suggestions.

### Installation

```bash
# Bash - add to ~/.bashrc
eval "$(./scripts/orchestrate.sh completion bash)"

# Zsh - add to ~/.zshrc
eval "$(./scripts/orchestrate.sh completion zsh)"

# Fish - save to completions directory
./scripts/orchestrate.sh completion fish > ~/.config/fish/completions/orchestrate.sh.fish
```

### Features

- **Command completion** - Tab through all available commands
- **Agent completion** - Complete agent names after `spawn`
- **Option completion** - Complete flags with descriptions
- **Context-aware** - Different completions based on command context

```bash
./scripts/orchestrate.sh sp<TAB>           # -> spawn
./scripts/orchestrate.sh spawn co<TAB>     # -> codex, codex-mini, codex-max...
./scripts/orchestrate.sh --ti<TAB>         # -> --tier, --timeout
./scripts/orchestrate.sh auth <TAB>        # -> login, logout, status
```

## Authentication

Manage OpenAI authentication (v4.2) via OAuth or API keys.

### Commands

```bash
# Check current authentication status
./scripts/orchestrate.sh auth status

# Login via OpenAI OAuth (opens browser)
./scripts/orchestrate.sh login

# Logout (clear stored tokens)
./scripts/orchestrate.sh logout
```

### Authentication Methods

| Method | How | Best For |
|--------|-----|----------|
| **OAuth** | `./scripts/orchestrate.sh login` | OpenAI subscription users |
| **API Key** | `export OPENAI_API_KEY="sk-..."` | API access, CI/CD |

The `auth status` command shows both OpenAI and Gemini authentication:

```
╔═══════════════════════════════════════════════════════════╗
║  🔐 Claude Octopus - Authentication Status                ║
╚═══════════════════════════════════════════════════════════╝

  OpenAI:  ✓ Authenticated (OAuth)
  Account: user@example.com

  Gemini:  ✓ Authenticated (API Key)
  Key:     AIza...XyZ
```

## Quality Gates

The `tangle` phase enforces quality gates:

| Score | Status | Behavior |
|-------|--------|----------|
| >= 90% | PASSED | Proceed to ink |
| 75-89% | WARNING | Proceed with caution |
| < 75% | FAILED | Ink phase flags for review |

## Agent Personas

Each agent can adopt a specialized persona with domain expertise. Personas inject role-specific instructions, constraints, and best practices.

| Persona | Expertise | Best For |
|---------|-----------|----------|
| `backend-architect` | API design, microservices, scalability | System design, architecture decisions |
| `security-auditor` | OWASP, vulnerability scanning, threat modeling | Security reviews, penetration testing |
| `frontend-developer` | React, accessibility, responsive design | UI implementation, component design |
| `database-optimizer` | Query optimization, indexing, schema design | Performance tuning, data modeling |
| `devops-engineer` | CI/CD, containers, infrastructure as code | Deployment, automation |
| `test-automator` | Testing strategies, coverage, E2E | Quality assurance, test implementation |
| `code-reviewer` | Code quality, maintainability, patterns | Pull request reviews, refactoring |

```bash
# Personas are automatically selected based on task context
./scripts/orchestrate.sh auto "design a REST API for user management"
# -> Uses backend-architect persona

# Or disable personas for raw agent output
./scripts/orchestrate.sh --no-personas auto "quick fix"
```

*Curated subset from [wshobson/agents](https://github.com/wshobson/agents) - a community collection of 99+ specialized agent personas. We sync and adapt the most CLI-relevant agents for orchestration workflows.*

## Ralph-Wiggum Iteration

Some tasks need multiple passes. The `ralph` command implements a completion-promise loop: the agent keeps iterating until it signals done or hits max iterations.

```bash
# Keep working until the agent says it's complete
./scripts/orchestrate.sh ralph "refactor this module to use async/await"

# Custom iteration limit
./scripts/orchestrate.sh ralph "migrate all tests to vitest" codex 20
```

**How it works:**

1. Agent receives the prompt with iteration context
2. Agent works on the task and outputs progress
3. If output contains `<promise>COMPLETE</promise>`, loop exits
4. Otherwise, agent continues with accumulated context
5. Loop terminates at max iterations (default: 50) if no completion

**Use cases:**
- Large refactoring that needs multiple passes
- Migrations that discover more work as they progress
- Complex debugging that requires iteration
- Any task where "done" is discovered, not predetermined

*Inspired by the [ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) Claude Code plugin pattern.*

## Prerequisites

See [Before You Start](#before-you-start) for the complete setup guide. Quick checklist:

- [ ] OpenAI API key set (`export OPENAI_API_KEY="sk-..."`)
- [ ] Google API key set (`export GEMINI_API_KEY="AIza..."`)
- [ ] Codex CLI installed (`codex --version`)
- [ ] Gemini CLI installed (`gemini --version`)
- [ ] Bash 4.0+ (macOS: `brew install bash`)

Run `./scripts/orchestrate.sh preflight` to verify everything is configured.

## Installation

### Via Plugin Marketplace (Recommended)

In Claude Code, run:

```
/plugin marketplace add nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

To update later:

```
/plugin marketplace update
```

### Automated Installation (via Claude Code)

In a Claude Code session, simply ask:

```
Install the claude-octopus plugin from https://github.com/nyldn/claude-octopus
```

Or run these commands:

```bash
# Clone to Claude plugins directory
git clone https://github.com/nyldn/claude-octopus.git ~/.claude/plugins/claude-octopus

# Make scripts executable
chmod +x ~/.claude/plugins/claude-octopus/scripts/*.sh
chmod +x ~/.claude/plugins/claude-octopus/scripts/*.py

# Initialize workspace
~/.claude/plugins/claude-octopus/scripts/orchestrate.sh init
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nyldn/claude-octopus.git ~/.claude/plugins/claude-octopus
   ```

2. Make scripts executable:
   ```bash
   chmod +x ~/.claude/plugins/claude-octopus/scripts/*.sh
   chmod +x ~/.claude/plugins/claude-octopus/scripts/*.py
   ```

3. (Optional) Add to PATH for easier access:
   ```bash
   echo 'export PATH="$HOME/.claude/plugins/claude-octopus/scripts:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   ```

### Clone Anywhere and Symlink

```bash
# Clone to your preferred location
git clone https://github.com/nyldn/claude-octopus.git ~/git/claude-octopus

# Create symlink in Claude plugins
ln -s ~/git/claude-octopus ~/.claude/plugins/claude-octopus

# Make scripts executable
chmod +x ~/git/claude-octopus/scripts/*.sh
chmod +x ~/git/claude-octopus/scripts/*.py
```

### Keeping Up to Date

To update to the latest version:

```bash
# Navigate to plugin directory
cd ~/.claude/plugins/claude-octopus

# Pull latest changes
git pull origin main
```

Or ask Claude Code:

```
Update the claude-octopus plugin to the latest version
```

To update to a specific version:

```bash
cd ~/.claude/plugins/claude-octopus
git fetch --tags
git checkout v1.0.0  # Replace with desired version
```

## Agent Setup & Configuration

Claude Octopus requires both **Codex CLI** (OpenAI) and **Gemini CLI** (Google) to be installed and configured.

### 1. Codex CLI Setup (OpenAI)

#### Install Codex CLI

```bash
# Install via npm
npm install -g @openai/codex

# Or via Homebrew
brew install openai/tap/codex
```

#### Configure OpenAI API Key

```bash
# Option 1: Environment variable (recommended)
export OPENAI_API_KEY="sk-..."
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrc

# Option 2: Use Codex auth command
codex auth
```

#### Verify Codex Installation

```bash
codex --version
codex exec -m gpt-5.2-codex "echo hello"
```

### 2. Gemini CLI Setup (Google)

#### Install Gemini CLI

```bash
# Install via npm
npm install -g @anthropic/gemini-cli

# Or download from releases
# https://github.com/google-gemini/gemini-cli/releases
```

#### Configure Google API Key

```bash
# Option 1: Environment variable (recommended)
export GEMINI_API_KEY="AIza..."
echo 'export GEMINI_API_KEY="AIza..."' >> ~/.zshrc

# Option 2: Use Gemini auth command
gemini auth login
```

#### Get a Google API Key

1. Go to [Google AI Studio](https://aistudio.google.com/apikey)
2. Click "Create API key"
3. Copy the key and save it securely
4. Set as environment variable (see above)

#### Verify Gemini Installation

```bash
gemini --version
gemini -y -m gemini-3-pro-preview "echo hello"
```

### 3. Pre-flight Check

Verify all dependencies are configured:

```bash
./scripts/orchestrate.sh preflight
```

This checks for:
- Codex CLI installation
- Gemini CLI installation
- OPENAI_API_KEY environment variable
- GEMINI_API_KEY environment variable

### Environment Variables Summary

Add these to your `~/.zshrc` or `~/.bashrc`:

```bash
# OpenAI (for Codex CLI)
export OPENAI_API_KEY="sk-..."

# Google (for Gemini CLI)
export GEMINI_API_KEY="AIza..."

# Optional: Custom workspace location
export CLAUDE_OCTOPUS_WORKSPACE="$HOME/.claude-octopus"
```

## Available Agents

| Agent | Model | Best For |
|-------|-------|----------|
| `codex` | GPT-5.1-Codex-Max | Complex code, deep refactoring (premium default) |
| `codex-standard` | GPT-5.2-Codex | Standard tier implementation |
| `codex-mini` | GPT-5.1-Codex-Mini | Quick fixes, simple tasks (cost-effective) |
| `codex-general` | GPT-5.2 | Non-coding agentic tasks |
| `gemini` | Gemini 3 Pro Preview | Deep analysis, 1M context |
| `gemini-fast` | Gemini 3 Flash Preview | Speed-critical tasks |
| `gemini-image` | Gemini 3 Pro Image Preview | Image generation (up to 4K) |
| `codex-review` | GPT-5.2-Codex | Code review mode |

## Command Reference

### Double Diamond Commands

| Command | Phase | Description |
|---------|-------|-------------|
| `probe <prompt>` | Discover | Parallel research with AI synthesis |
| `grasp <prompt>` | Define | Consensus building on problem definition |
| `tangle <prompt>` | Develop | Enhanced map-reduce with quality gates |
| `ink <prompt>` | Deliver | Validation and final delivery |
| `embrace <prompt>` | All 4 | Full Double Diamond workflow |
| `preflight` | - | Validate all dependencies |

### Classic Orchestration Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize workspace |
| `spawn <agent> <prompt>` | Spawn single agent |
| `auto <prompt>` | Smart routing (Double Diamond or agent) |
| `fan-out <prompt>` | Send to multiple agents |
| `map-reduce <prompt>` | Decompose and parallelize |
| `parallel [tasks.json]` | Execute task file |
| `status` | Show running agents |
| `kill [id\|all]` | Terminate agents |
| `clean` | Reset workspace |
| `aggregate [filter]` | Combine results |

### Optimization Commands (v4.2)

| Command | Description |
|---------|-------------|
| `optimize <prompt>` | Auto-detect and route optimization (performance, cost, a11y, SEO...) |
| `optimise <prompt>` | Alias for optimize |

### Authentication Commands (v4.2)

| Command | Description |
|---------|-------------|
| `auth status` | Check current authentication status |
| `login` | Login to OpenAI via OAuth |
| `logout` | Logout from OpenAI |

### Shell Completion (v4.2)

| Command | Description |
|---------|-------------|
| `completion bash` | Generate bash completion script |
| `completion zsh` | Generate zsh completion script |
| `completion fish` | Generate fish completion script |

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `-p, --parallel` | 3 | Max concurrent agents |
| `-t, --timeout` | 300 | Timeout per task (seconds) |
| `-v, --verbose` | false | Verbose logging |
| `-n, --dry-run` | false | Show without executing |
| `-d, --dir` | `$PWD` | Working directory |
| `--context <file>` | - | Context from previous phase |

## Workspace Structure

```
~/.claude-octopus/
├── results/
│   ├── probe-synthesis-*.md      # Research findings
│   ├── grasp-consensus-*.md      # Problem definitions
│   ├── tangle-validation-*.md    # Quality gate reports
│   └── delivery-*.md             # Final deliverables
├── logs/                         # Execution logs
├── plans/                        # Execution plan history
└── .gitignore
```

Override with: `CLAUDE_OCTOPUS_WORKSPACE=/custom/path`

## Example Workflows

### Research-First Development

```bash
# 1. Explore the problem space
./scripts/orchestrate.sh probe "Authentication patterns for microservices"

# 2. Define the approach (with probe context)
./scripts/orchestrate.sh grasp "OAuth2 with JWT for our API" \
  --context ~/.claude-octopus/results/probe-synthesis-*.md

# 3. Implement with validation
./scripts/orchestrate.sh tangle "Implement OAuth2 authentication"

# 4. Deliver with quality checks
./scripts/orchestrate.sh ink "Finalize auth implementation"
```

### Quick Build (Auto-Routed)

```bash
# Auto-detects "build" intent -> runs tangle + ink
./scripts/orchestrate.sh auto "build a rate limiting middleware"
```

### Full Feature Development

```bash
# All 4 phases in one command
./scripts/orchestrate.sh embrace "Create a user notification system with email and push support"
```

### Security Audit (Probe)

```bash
# Multi-perspective security analysis
./scripts/orchestrate.sh probe "Perform security audit focusing on: authentication, input validation, and SQL injection vulnerabilities"
```

### Large Refactoring (Tangle)

```bash
# Parallel implementation with quality gates
./scripts/orchestrate.sh tangle "Refactor all React class components to functional components with hooks"
```

## Troubleshooting

### Pre-flight check fails

```bash
./scripts/orchestrate.sh preflight
# Verify: codex CLI, gemini CLI, OPENAI_API_KEY, GEMINI_API_KEY
```

### Quality gate failures

Tangle phase requires 75% success rate. If failing:
- Break task into smaller subtasks
- Increase timeout with `-t 600`
- Check individual agent logs in `~/.claude-octopus/logs/`

*Getting 75% of tentacles to agree is actually impressive coordination. Even real octopuses struggle with that.* 🐙

### Agents not responding

```bash
./scripts/orchestrate.sh kill all
./scripts/orchestrate.sh clean
```

*Sometimes tentacles need a rest. A clean reset untangles everything.* 🐙

### Timeout issues

Increase timeout for complex tasks:

```bash
./scripts/orchestrate.sh -t 600 auto "Complex task..."
```

*Even octopuses can't rush perfection. Give those tentacles time to work.* 🐙

### Missing dependencies

```bash
# Install jq for JSON task files
brew install jq

# Install coreutils for gtimeout (macOS)
brew install coreutils
```

### Codex CLI not found

```bash
# Check if installed
which codex

# If not found, install
npm install -g @openai/codex

# Verify API key is set
echo $OPENAI_API_KEY
```

### Gemini CLI not found

```bash
# Check if installed
which gemini

# If not found, install
npm install -g @anthropic/gemini-cli

# Verify API key is set
echo $GEMINI_API_KEY
```

### Reset workspace

```bash
./scripts/orchestrate.sh clean
./scripts/orchestrate.sh init
```

## Python Coordinator (Advanced)

For more sophisticated task coordination with async execution:

```bash
# Initialize
python3 ./scripts/coordinator.py init

# Double Diamond commands
python3 ./scripts/coordinator.py probe "Research prompt"
python3 ./scripts/coordinator.py grasp "Define prompt"
python3 ./scripts/coordinator.py tangle "Develop prompt"
python3 ./scripts/coordinator.py ink "Deliver prompt"
python3 ./scripts/coordinator.py embrace "Full workflow prompt"

# Pre-flight check
python3 ./scripts/coordinator.py preflight

# Classic commands
python3 ./scripts/coordinator.py auto "Your prompt here"
python3 ./scripts/coordinator.py fan-out "Analyze this code"
python3 ./scripts/coordinator.py map-reduce -p 4 -t 600 "Large refactoring task"
```

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## The Octopus Philosophy

🐙 **Why an octopus?**

Real octopuses are nature's parallel processing masters:

| Octopus Trait | Claude Octopus Feature |
|---------------|----------------------|
| 8 independent arms | Multiple agents working in parallel |
| Distributed brain (neurons in each arm) | Intelligence at every endpoint |
| Ink cloud defense | Quality deliverables that make an impression |
| Master of camouflage | Adapts to any task type seamlessly |
| Opens jars, solves puzzles | Opens codebases, solves problems |
| Squeezes through tiny spaces | Fits into any workflow |

*Fun fact: Octopuses have been observed using tools, planning multi-step strategies,
and even escaping from sealed containers. Our orchestrator does the same, but digitally
(and with fewer suction cups).*

## Acknowledgments

**Core Dependencies:**
- [Claude Code](https://claude.ai/code) - Anthropic's CLI for Claude
- [Codex CLI](https://github.com/openai/codex) - OpenAI's coding assistant
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) - Google's Gemini CLI

**Methodology & Patterns:**
- [Double Diamond](https://www.designcouncil.org.uk/our-resources/framework-for-innovation/) - Design Council's framework for innovation
- [ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) - Completion-promise iteration pattern
- [wshobson/agents](https://github.com/wshobson/agents) - Community-curated agent personas and orchestration patterns

---

<p align="center">
  🐙 Made with eight tentacles of love 🐙<br/>
  <i>All arms working in perfect parallel harmony</i><br/>
  <a href="https://github.com/nyldn">nyldn</a>
</p>
