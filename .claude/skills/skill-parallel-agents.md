---
name: skill-parallel-agents
effort: high
description: Decompose large tasks across parallel agents — use for migrations, multi-file refactors, or batch work
trigger: |
  PRIORITY TRIGGERS (always invoke immediately):
  - "/octo:multi" (explicit command)
  - "run this with all providers", "run with all providers"
  - "I want all three AI models to look at", "use all providers for"
  - "get multiple perspectives on", "force multi-provider analysis"

  AUTOMATICALLY ACTIVATE (without asking user) when the user requests:
  - Research, explore, investigate, or analyze topics (e.g., "octo research OAuth patterns", "octo analyze technical debt", "octo explore different approaches")
  - Build, implement, create, or develop features (e.g., "octo build a login system", "octo implement caching", "octo create a dashboard")
  - Review, validate, test, or check code quality (e.g., "octo review this code", "octo validate the API", "octo check for issues")
  - Adversarial review, debate solutions, or red team security (e.g., "octo debate the design", "red team this auth code", "find security flaws")
  - Full workflows from research to delivery (e.g., "create a complete notification feature")

  DO NOT ask "do you want me to use the plugin?" - JUST USE IT.
  The user installed this plugin to use it automatically!

  NEVER use for:
  - Built-in Claude Code commands (/plugin, /init, /help, /clear, /commit, /remember, etc.)
  - Plugin management or Claude Code configuration
  - Simple file operations, git commands, or basic terminal tasks
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - output_artifact_exists
---

# Claude Octopus - Multi-Tentacled Orchestrator

## MANDATORY COMPLIANCE — DO NOT SKIP

**When this skill is invoked, you MUST dispatch work to multiple providers in parallel. You are PROHIBITED from:**
- Running tasks sequentially with a single model instead of parallel multi-provider dispatch
- Skipping orchestrate.sh and doing the work directly
- Deciding the task is "simple enough" for a single provider
- Substituting serial Claude-only execution for multi-LLM parallel execution

**This skill exists specifically for multi-provider parallel work. If you catch yourself thinking "I'll just do this myself" — STOP.**

---

**Multi-tentacled orchestrator for Claude Code** - using Double Diamond methodology for comprehensive problem exploration, consensus building, and validated delivery.

```
    DISCOVER          DEFINE           DEVELOP          DELIVER
      (probe)         (grasp)          (tangle)          (ink)

    \         /     \         /     \         /     \         /
     \   *   /       \   *   /       \   *   /       \   *   /
      \ * * /         \     /         \ * * /         \     /
       \   /           \   /           \   /           \   /
        \ /             \ /             \ /             \ /

   Diverge then      Converge to      Diverge with     Converge to
    converge          problem          solutions        delivery
```

## Quick Start

> **Note for Claude Code users:** You don't need to run these commands! Just talk naturally to Claude:
> - "Research OAuth authentication patterns"
> - "Build a user authentication system"
> - "Review this code for security issues"
>
> The commands below are for direct CLI usage or automation.

```bash
# Full Double Diamond workflow (all 4 phases)
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh embrace "Build a user authentication system"

# Individual phases
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh probe "Research authentication best practices"
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grasp "Define auth requirements"
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh tangle "Implement auth feature"
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh ink "Validate and deliver auth implementation"

# Crossfire: Adversarial cross-model review
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grapple "implement password reset API"
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grapple --principles security "implement JWT auth"
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh squeeze "review auth.ts for vulnerabilities"

# Smart auto-routing (detects intent automatically)
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "research OAuth patterns"           # -> probe
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "build user login"                  # -> tangle + ink
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "review the auth code"              # -> ink
```

## IMPORTANT: When NOT to Use This Skill

**DO NOT use this skill if the user's request involves:**

1. **Built-in Claude Code commands** - Commands starting with `/` that are part of Claude Code itself:
   - `/plugin` - Plugin management (add, remove, update, list)
   - `/init` - Project initialization
   - `/help` - Help documentation
   - `/clear` - Clear conversation
   - `/commit` - Git commit operations
   - `/remember` - Memory management
   - Any other `/` command that isn't `/parallel-agents` or `/octo:*`

2. **Direct tool usage** - Simple file operations, git commands, or terminal tasks
   - Reading/writing files
   - Running git commands
   - Basic bash operations
   - These should use built-in tools directly

3. **Claude Code configuration** - Managing Claude Code itself
   - Changing settings
   - Managing plugins
   - Updating Claude Code

**If the user's request matches any of the above, DO NOT activate this skill. Handle the request using standard Claude Code tools and capabilities instead.**

## Visual Indicators - Know What's Running

Claude Octopus uses **visual indicators** so you always know which AI is responding:

| Indicator | Meaning | Uses |
|-----------|---------|------|
| 🐙 | **Parallel Mode** | Multiple CLIs orchestrated via orchestrate.sh |
| 🔴 | **Codex CLI** | OpenAI Codex (your OPENAI_API_KEY) |
| 🟡 | **Gemini CLI** | Google Gemini (your GEMINI_API_KEY) |
| 🔵 | **Claude Subagent** | Claude Code Task tool (built-in) |

### What Triggers External CLIs vs Subagents

**External CLIs execute when:**
- Using `/parallel-agents` command explicitly
- Using `/debate` command (AI Debate Hub)
- Running orchestrate.sh workflows (probe, grasp, tangle, ink, embrace, grapple, squeeze)
- Knowledge mode deliberation (when Knowledge Mode is ON)
- Natural language that triggers this skill (research, build, review tasks)

**Claude Subagents execute when:**
- Simple file operations (read, write, edit)
- Git commands and bash operations
- Code reading and navigation
- Tasks that don't need multiple perspectives
- Built-in Claude Code capabilities are sufficient

**Why this matters:** External CLIs use your OpenAI/Google API quotas and incur costs. Claude subagents are included with Claude Code at no additional charge.

When you see 🐙 **CLAUDE OCTOPUS ACTIVATED**, external CLI providers (Codex/Gemini) will be invoked for multi-perspective analysis.

---

## Force Multi-Provider Mode

Sometimes you want multi-provider analysis even for simple tasks that wouldn't normally trigger workflows. This is useful when you need comprehensive perspectives on decisions, want to compare how different models think, or when automatic routing underestimates task complexity.

### Explicit Command

Force multi-provider execution using the `/octo:multi` command:

```
/octo:multi "Explain how Redis works"
/octo:multi "What is OAuth?"
/octo:multi "Review this simple function"
/octo:multi "Should we use TypeScript?"
```

### Natural Language Triggers

You can also force multi-provider mode with natural language:

```
"Run this with all providers: What is JWT?"
"I want all three AI models to look at our architecture"
"Get multiple perspectives on this design decision"
"Use all providers for explaining caching strategies"
"Force multi-provider analysis of our API design"
```

### When to Force Parallel Mode

**Use forced parallel mode when:**
- **High-stakes decisions** require comprehensive analysis from multiple models
- **Comparing perspectives** - you want to see how different models approach the same problem
- **Simple questions with depth** - seemingly simple questions that deserve thorough multi-model analysis
- **Learning different approaches** - exploring how each model thinks about a topic
- **Automatic routing underestimates complexity** - task appears simple but has nuance

**Don't force parallel mode when:**
- Task already auto-triggers workflows (`octo research`, `octo build`, `octo review`)
- Simple factual questions Claude can answer reliably
- Cost efficiency is important (see cost awareness below)
- File operations or code navigation (use built-in tools)

### Cost Awareness

Forcing parallel mode uses external CLIs for every task, which incurs API costs:

| Provider | Cost per Query | What It Uses |
|----------|----------------|--------------|
| 🔴 Codex CLI | ~$0.01-0.05 | Your OPENAI_API_KEY |
| 🟡 Gemini CLI | ~$0.01-0.03 | Your GEMINI_API_KEY |
| 🔵 Claude | Included | Claude Code subscription |

**Total cost per forced query: ~$0.02-0.08**

Use forced parallel mode judiciously for tasks where multiple perspectives genuinely add value. For routine work, let automatic routing decide when multi-provider analysis is beneficial.

### Visual Indicator

When you force parallel mode, you'll see this banner:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider mode
Force parallel execution

Providers:
🔴 Codex CLI - [Role in this task]
🟡 Gemini CLI - [Role in this task]
🔵 Claude - [Role in this task]
```

Followed by results from each provider marked with their indicators (🔴 🟡 🔵).

---

## Prerequisites Check (Automatic - Fast Detection)

**IMPORTANT:** Once you've determined this skill should activate (user asked to research, build, review, etc.), immediately run the provider detection below. DO NOT ask the user for permission - just check providers and proceed or show welcome message.

### Step 1: Automatic Provider Detection

Silently run this fast detection script (completes in <1 second):

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh detect-providers
```

**IMPORTANT - First Time Setup Detection:**
If the detect-providers command shows BOTH providers are missing (CODEX_STATUS=missing AND GEMINI_STATUS=missing), this is likely a first-time user. Before showing error messages, provide a friendly welcome message:

> "👋 Welcome to Claude Octopus! I see this is your first time using the plugin.
>
> To get started, you need to install **one** AI provider (you don't need both):
>
> **Option 1: OpenAI Codex** (best for code generation)
> ```
> npm install -g @openai/codex
> codex login  # OAuth recommended
> ```
> Or set API key: `export OPENAI_API_KEY="sk-..."`
> Get key from: https://platform.openai.com/api-keys
>
> **Option 2: Google Gemini** (best for analysis)
> ```
> npm install -g @google/gemini-cli
> gemini  # OAuth recommended
> ```
> Or set API key: `export GEMINI_API_KEY="AIza..."`
> Get key from: https://aistudio.google.com/app/apikey
>
> Once you've installed one provider, you can start using Claude Octopus by just talking naturally:
> - 'Research OAuth authentication patterns'
> - 'Build a user authentication system'
> - 'Review this code for security issues'
>
> Need guided setup? Run `/octo:setup`"

After showing this welcome message, STOP and wait for the user to set up a provider. Do not proceed with the original task until at least one provider is configured.

Expected output format:
```
Detecting Claude Code version...

CLAUDE_CODE_VERSION=2.1.9
CLAUDE_CODE_STATUS=ok
CLAUDE_CODE_MINIMUM=2.1.9

✓ Claude Code version: 2.1.9 (meets minimum 2.1.9)

Detecting providers...

CODEX_STATUS=ok
CODEX_AUTH=oauth

GEMINI_STATUS=ok
GEMINI_AUTH=none

Summary:
  ✓ Codex: Installed and authenticated (oauth)
  ⚠ Gemini: Installed but not authenticated
```

### Step 2: Route Based on Detection Results

Parse the output and route accordingly:

**Scenario 0: Claude Code version is outdated (CRITICAL - Check First)**
```
CLAUDE_CODE_VERSION=2.1.8
CLAUDE_CODE_STATUS=outdated
CLAUDE_CODE_MINIMUM=2.1.9
```

**Action:** STOP immediately and show this prominent warning:

> "⚠️ **Claude Code Update Required**
>
> Your current Claude Code version (2.1.8) is outdated. Claude Octopus requires version 2.1.9 or higher for full functionality.
>
> **How to update:**
>
> If installed via npm:
> ```
> npm update -g @anthropic/claude-code
> ```
>
> If installed via Homebrew:
> ```
> brew upgrade claude-code
> ```
>
> If installed via download:
> Visit https://github.com/anthropics/claude-code/releases
>
> **After updating, please restart Claude Code** and then we can proceed with your task."

Do NOT proceed with the task until the user has updated and restarted. The detect-providers output will show this warning prominently.

**Scenario A: Both providers missing**
```
CODEX_STATUS=missing
CODEX_AUTH=none
GEMINI_STATUS=missing
GEMINI_AUTH=none
```

**Action:** STOP and tell the user:

> "Claude Octopus needs at least one AI provider (Codex or Gemini) to work.
>
> You have two options:
>
> **Option 1: Install Codex CLI**
> ```
> npm install -g @openai/codex
> export OPENAI_API_KEY=\"sk-...\"
> ```
> Get API key from: https://platform.openai.com/api-keys
>
> **Option 2: Install Gemini CLI**
> ```
> npm install -g @google/gemini-cli
> gemini  # Run OAuth setup
> ```
>
> After installing one, run `/octo:setup` to verify everything works."

**Scenario B: One provider working, one missing/partial**
```
CODEX_STATUS=ok
CODEX_AUTH=oauth (or api-key)
GEMINI_STATUS=missing (or ok with AUTH=none)
```

**Action:** IMMEDIATELY proceed with the user's task using the available provider. No need to announce setup status - just execute the task. The user doesn't care about which provider you're using, they just want their task done.

**Scenario C: Both providers working**
```
CODEX_STATUS=ok
CODEX_AUTH=oauth
GEMINI_STATUS=ok
GEMINI_AUTH=oauth
```

**Action:** IMMEDIATELY proceed with the user's task using both providers for comprehensive results. No need to announce setup status - just execute the task.

### Step 3: Graceful Degradation

If only ONE provider is available:
- Automatically use that provider
- Tasks that require multiple providers will adapt to use the single provider multiple times
- Quality results are still achievable with one provider

You do NOT need both providers to proceed. One is sufficient for most tasks.

### Step 4: Cache Results (Optional Optimization)

The detect-providers command writes results to `~/.claude-octopus/.provider-cache` with a timestamp. This cache is valid for 1 hour.

If the cache exists and is fresh (<1 hour old), you can skip re-detection.

### Step 5: Execute Task

Only proceed when at least ONE provider is available and authenticated. Multi-provider tasks will automatically adapt to available providers.

**IMPORTANT:** This detection is fast (~1 second) and non-blocking. Always verify provider availability before running octopus commands, but don't require BOTH providers - one is enough!

## Double Diamond Workflow

### Phase 1: PROBE (Discover)
**Diverge then converge on understanding**

Parallel research from 4 perspectives:
- Problem space analysis (constraints, requirements, needs)
- Existing solutions research (what worked, what failed)
- Edge cases exploration (potential challenges)
- Technical feasibility (prerequisites, dependencies)

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh probe "What are the best approaches for real-time notifications?"
```

### Phase 2: GRASP (Define)
**Build consensus on the problem**

Multi-tentacled problem definition:
- Core problem statement
- Success criteria
- Constraints and boundaries

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grasp "Define requirements for notification system" --context probe-synthesis-*.md
```

### Phase 3: TANGLE (Develop)
**Diverge with multiple solutions**

Enhanced map-reduce with validation:
- Task decomposition via LLM
- Parallel execution across agents
- Quality gate (75% success threshold)

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh tangle "Implement notification service" --context grasp-consensus-*.md
```

### Phase 4: INK (Deliver)
**Converge to validated delivery**

Pre-delivery validation:
- Quality gate verification
- Result synthesis
- Final deliverable generation

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh ink "Deliver notification system" --context tangle-validation-*.md
```

### Full Workflow: EMBRACE
Run all 4 phases sequentially with automatic context passing:

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh embrace "Create a complete user dashboard feature"
```

## Crossfire: Adversarial Cross-Model Review

Different models have different blind spots. Crossfire commands force models to critique each other's work, catching more issues than single-model review.

### GRAPPLE - Adversarial Debate

*Two tentacles wrestling until consensus*

Codex and Gemini each propose solutions, then critique each other's work. A synthesis determines the winner.

```
┌─────────────┐     ┌─────────────┐
│   Codex     │     │   Gemini    │
│ (Proposer)  │     │ (Proposer)  │
└──────┬──────┘     └──────┬──────┘
       │                   │
       ▼                   ▼
┌─────────────┐     ┌─────────────┐
│ PROPOSAL A  │ ←─→ │ PROPOSAL B  │
└──────┬──────┘     └──────┬──────┘
       │                   │
       ▼                   ▼
┌─────────────┐     ┌─────────────┐
│  Gemini     │     │   Codex     │
│ (Critic)    │     │  (Critic)   │
└──────┬──────┘     └──────┬──────┘
       │                   │
       └─────────┬─────────┘
                 ▼
       ┌─────────────────┐
       │   SYNTHESIS     │
       │ (Winner + Fix)  │
       └─────────────────┘
```

```bash
# Basic grapple
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grapple "implement password reset API"

# Grapple with security principles
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grapple --principles security "implement JWT authentication"

# Grapple with performance principles
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grapple --principles performance "optimize database queries"
```

### SQUEEZE - Red Team Security Review

*Octopus squeezes prey to test for weaknesses*

Blue Team (Codex) implements secure code. Red Team (Gemini) attacks to find vulnerabilities. Then remediation and validation.

```
Phase 1: Blue Team implements secure solution
Phase 2: Red Team finds vulnerabilities
Phase 3: Remediation fixes all issues
Phase 4: Validation verifies all fixed
```

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh squeeze "implement user login form"
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh squeeze "review auth.ts for vulnerabilities"
```

### Constitutional Principles

Grapple supports domain-specific critique principles:

| Principle | Focus | Use Case |
|-----------|-------|----------|
| `general` | Overall quality | Default for most reviews |
| `security` | OWASP Top 10, secure coding | Auth, payments, user data |
| `performance` | N+1 queries, caching, async | Database, API optimization |
| `maintainability` | Clean code, testability | Refactoring, code reviews |

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grapple --principles security "implement password reset"
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grapple --principles performance "optimize search API"
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grapple --principles maintainability "refactor user service"
```

## Smart Auto-Routing

The `auto` command detects intent keywords and routes to the appropriate workflow:

| Keywords | Routes To | Phases |
|----------|-----------|--------|
| research, explore, investigate, analyze | `probe` | Discover |
| develop, dev, build, implement, create | `tangle` + `ink` | Develop + Deliver |
| qa, test, review, validate, check | `ink` | Deliver (quality focus) |
| security audit, red team, pentest | `squeeze` | Red Team |
| adversarial, cross-model, debate | `grapple` | Debate |
| (other coding keywords) | `codex` agent | Single agent |
| (other design keywords) | `gemini` agent | Single agent |

**Examples:**
```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "research best practices for caching"     # -> probe
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "build the caching layer"                 # -> tangle + ink
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "review the cache implementation"         # -> ink
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "security audit the auth module"          # -> squeeze
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "have both models debate the API design"  # -> grapple
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "fix the cache invalidation bug"          # -> codex
```

## Quality Gates

The `tangle` phase enforces quality gates:

| Score | Status | Behavior |
|-------|--------|----------|
| >= 90% | PASSED | Proceed to ink |
| 75-89% | WARNING | Proceed with caution |
| < 75% | FAILED | Ink phase flags for review |

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

### Crossfire Commands (Adversarial Review)

| Command | Description |
|---------|-------------|
| `grapple <prompt>` | Codex vs Gemini debate until consensus |
| `grapple --principles TYPE <prompt>` | Debate with domain principles (security, performance, maintainability) |
| `squeeze <prompt>` | Red Team security review (Blue Team vs Red Team) |

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

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `-p, --parallel` | 3 | Max concurrent agents |
| `-t, --timeout` | 300 | Timeout per task (seconds) |
| `-v, --verbose` | false | Verbose logging |
| `-n, --dry-run` | false | Show without executing |
| `--context <file>` | - | Context from previous phase |

## Agent Selection (Premium Defaults)

| Agent | Model | Best For |
|-------|-------|----------|
| `codex` | gpt-5.3-codex | Complex code, deep refactoring (premium default) |
| `codex-standard` | gpt-5.2-codex | Standard tier implementation |
| `codex-mini` | gpt-5.4-mini | Quick fixes, simple tasks |
| `gemini` | gemini-3-pro-preview | Deep analysis, 1M context |
| `gemini-fast` | gemini-3-flash-preview | Speed-critical tasks |
| `gemini-image` | gemini-3-pro-image-preview | Image generation |
| `codex-review` | gpt-5.2-codex | Code review mode |
| `openrouter` | Various | Universal fallback (400+ models) |

## Provider-Aware Routing (v4.8)

Claude Octopus now intelligently routes tasks based on your subscription tiers and costs.

### Provider Subscription Tiers

| Provider | Tiers | Monthly Cost | Capabilities |
|----------|-------|--------------|--------------|
| **Codex/OpenAI** | Free, Plus, Pro, API | $0-200 | code, chat, review |
| **Gemini** | Free, Google One, Workspace, API | $0-20 or bundled | code, chat, vision, long-context (2M) |
| **Claude** | Pro, Max 5x, Max 20x, API | $20-200 | code, chat, analysis, long-context |
| **OpenRouter** | Pay-per-use | Variable | 400+ models, routing variants |

### Cost Optimization Strategies

| Strategy | Description |
|----------|-------------|
| `balanced` (default) | Smart mix of cost and quality |
| `cost-first` | Prefer cheapest capable provider |
| `quality-first` | Prefer highest-tier provider |

**Example:** If you have Google Workspace (bundled Gemini Pro), the system prefers Gemini for heavy analysis tasks since it's "free" with your work account.

### Routing CLI Flags

```bash
# Force a specific provider
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh --provider gemini auto "analyze code structure"

# Prefer cheapest option
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh --cost-first auto "research best practices"

# Prefer highest quality
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh --quality-first auto "complex refactoring task"

# OpenRouter routing variants
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh --openrouter-nitro auto "quick task"  # Fastest
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh --openrouter-floor auto "bulk task"   # Cheapest
```

### Configuration

Provider tiers are configured during `setup` or via the providers config file:

```bash
# Run setup wizard (includes provider tier steps)
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh setup

# View current provider status
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh status
```

Configuration file: `~/.claude-octopus/.providers-config`

```yaml
version: "2.0"
providers:
  codex:
    installed: true
    auth_method: "oauth"
    subscription_tier: "plus"    # free|plus|pro|api-only
    cost_tier: "low"             # free|low|medium|high|bundled|pay-per-use

  gemini:
    installed: true
    auth_method: "oauth"
    subscription_tier: "workspace"  # free|google-one|workspace|api-only
    cost_tier: "bundled"

  openrouter:
    enabled: false
    routing_preference: "default"   # default|nitro|floor

cost_optimization:
  strategy: "balanced"  # cost-first|quality-first|balanced
```

### OpenRouter Fallback

OpenRouter provides 400+ models as a universal fallback when Codex/Gemini are unavailable:

```bash
# Set up OpenRouter API key
export OPENROUTER_API_KEY="sk-or-..."

# Re-run setup to configure
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh setup
```

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

## Example Workflows

### Research-First Development
```bash
# 1. Explore the problem space
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh probe "Authentication patterns for microservices"

# 2. Define the approach (with probe context)
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grasp "OAuth2 with JWT for our API" \
  --context ~/.claude-octopus/results/probe-synthesis-*.md

# 3. Implement with validation
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh tangle "Implement OAuth2 authentication"

# 4. Deliver with quality checks
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh ink "Finalize auth implementation"
```

### Quick Build (Auto-Routed)
```bash
# Auto-detects "build" intent -> runs tangle + ink
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "build a rate limiting middleware"
```

### Full Feature Development
```bash
# All 4 phases in one command
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh embrace "Create a user notification system with email and push support"
```

## Best Practices

1. **Start with `embrace`** for new features requiring exploration
2. **Use `probe` alone** when researching before committing to an approach
3. **Use `auto`** for smart routing based on your intent
4. **Chain phases** with `--context` for incremental workflows
5. **Run `preflight`** before long workflows to verify dependencies
6. **Review quality gates** in tangle output before proceeding to ink

## Troubleshooting

### Pre-flight check fails
```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh preflight
# Verify: codex CLI, gemini CLI, OPENAI_API_KEY, GOOGLE_API_KEY
```

### Quality gate failures
Tangle phase requires 75% success rate. If failing:
- Break task into smaller subtasks
- Increase timeout with `-t 600`
- Check individual agent logs in `~/.claude-octopus/logs/`

### Reset workspace
```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh clean
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh init
```
