---
name: parallel-agents
description: |
  Multi-tentacled orchestrator for Claude Code using Double Diamond methodology.
  Coordinates Codex CLI and Gemini CLI for comprehensive problem solving. Use when you need to:
  - Run full Double Diamond workflow (probe → grasp → tangle → ink)
  - Parallel research from multiple perspectives with AI synthesis
  - Consensus building on problem definitions
  - Quality-gated parallel implementation with validation
  - Adversarial cross-model review (grapple: debate, squeeze: red team)
  - Review code from multiple angles using different AI models

  NOT for: Simple sequential tasks, tasks requiring human interaction, debugging sessions
---

# Claude Octopus - Multi-Tentacled Orchestrator

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

```bash
# Full Double Diamond workflow (all 4 phases)
./scripts/orchestrate.sh embrace "Build a user authentication system"

# Individual phases
./scripts/orchestrate.sh probe "Research authentication best practices"
./scripts/orchestrate.sh grasp "Define auth requirements"
./scripts/orchestrate.sh tangle "Implement auth feature"
./scripts/orchestrate.sh ink "Validate and deliver auth implementation"

# Crossfire: Adversarial cross-model review
./scripts/orchestrate.sh grapple "implement password reset API"
./scripts/orchestrate.sh grapple --principles security "implement JWT auth"
./scripts/orchestrate.sh squeeze "review auth.ts for vulnerabilities"

# Smart auto-routing (detects intent automatically)
./scripts/orchestrate.sh auto "research OAuth patterns"           # -> probe
./scripts/orchestrate.sh auto "build user login"                  # -> tangle + ink
./scripts/orchestrate.sh auto "review the auth code"              # -> ink
```

## Double Diamond Workflow

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
./scripts/orchestrate.sh grasp "Define requirements for notification system" --context probe-synthesis-*.md
```

### Phase 3: TANGLE (Develop)
**Diverge with multiple solutions**

Enhanced map-reduce with validation:
- Task decomposition via LLM
- Parallel execution across agents
- Quality gate (75% success threshold)

```bash
./scripts/orchestrate.sh tangle "Implement notification service" --context grasp-consensus-*.md
```

### Phase 4: INK (Deliver)
**Converge to validated delivery**

Pre-delivery validation:
- Quality gate verification
- Result synthesis
- Final deliverable generation

```bash
./scripts/orchestrate.sh ink "Deliver notification system" --context tangle-validation-*.md
```

### Full Workflow: EMBRACE
Run all 4 phases sequentially with automatic context passing:

```bash
./scripts/orchestrate.sh embrace "Create a complete user dashboard feature"
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
./scripts/orchestrate.sh grapple "implement password reset API"

# Grapple with security principles
./scripts/orchestrate.sh grapple --principles security "implement JWT authentication"

# Grapple with performance principles
./scripts/orchestrate.sh grapple --principles performance "optimize database queries"
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
./scripts/orchestrate.sh squeeze "implement user login form"
./scripts/orchestrate.sh squeeze "review auth.ts for vulnerabilities"
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
./scripts/orchestrate.sh grapple --principles security "implement password reset"
./scripts/orchestrate.sh grapple --principles performance "optimize search API"
./scripts/orchestrate.sh grapple --principles maintainability "refactor user service"
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
./scripts/orchestrate.sh auto "research best practices for caching"     # -> probe
./scripts/orchestrate.sh auto "build the caching layer"                 # -> tangle + ink
./scripts/orchestrate.sh auto "review the cache implementation"         # -> ink
./scripts/orchestrate.sh auto "security audit the auth module"          # -> squeeze
./scripts/orchestrate.sh auto "have both models debate the API design"  # -> grapple
./scripts/orchestrate.sh auto "fix the cache invalidation bug"          # -> codex
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
| `codex` | gpt-5.1-codex-max | Complex code, deep refactoring (premium default) |
| `codex-standard` | gpt-5.2-codex | Standard tier implementation |
| `codex-mini` | gpt-5.1-codex-mini | Quick fixes, simple tasks |
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
./scripts/orchestrate.sh --provider gemini auto "analyze code structure"

# Prefer cheapest option
./scripts/orchestrate.sh --cost-first auto "research best practices"

# Prefer highest quality
./scripts/orchestrate.sh --quality-first auto "complex refactoring task"

# OpenRouter routing variants
./scripts/orchestrate.sh --openrouter-nitro auto "quick task"  # Fastest
./scripts/orchestrate.sh --openrouter-floor auto "bulk task"   # Cheapest
```

### Configuration

Provider tiers are configured during `setup` or via the providers config file:

```bash
# Run setup wizard (includes provider tier steps)
./scripts/orchestrate.sh setup

# View current provider status
./scripts/orchestrate.sh status
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
./scripts/orchestrate.sh setup
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
./scripts/orchestrate.sh preflight
# Verify: codex CLI, gemini CLI, OPENAI_API_KEY, GOOGLE_API_KEY
```

### Quality gate failures
Tangle phase requires 75% success rate. If failing:
- Break task into smaller subtasks
- Increase timeout with `-t 600`
- Check individual agent logs in `~/.claude-octopus/logs/`

### Reset workspace
```bash
./scripts/orchestrate.sh clean
./scripts/orchestrate.sh init
```
