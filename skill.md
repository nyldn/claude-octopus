---
name: parallel-agents
description: |
  Multi-tentacled orchestrator for Claude Code using Double Diamond methodology.
  Coordinates Codex CLI and Gemini CLI for comprehensive problem solving. Use when you need to:
  - Run full Double Diamond workflow (probe → grasp → tangle → ink)
  - Parallel research from multiple perspectives with AI synthesis
  - Consensus building on problem definitions
  - Quality-gated parallel implementation with validation
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

## Smart Auto-Routing

The `auto` command detects intent keywords and routes to the appropriate workflow:

| Keywords | Routes To | Phases |
|----------|-----------|--------|
| research, explore, investigate, analyze | `probe` | Discover |
| develop, dev, build, implement, create | `tangle` + `ink` | Develop + Deliver |
| qa, test, review, validate, check | `ink` | Deliver (quality focus) |
| (other coding keywords) | `codex` agent | Single agent |
| (other design keywords) | `gemini` agent | Single agent |

**Examples:**
```bash
./scripts/orchestrate.sh auto "research best practices for caching"     # -> probe
./scripts/orchestrate.sh auto "build the caching layer"                 # -> tangle + ink
./scripts/orchestrate.sh auto "review the cache implementation"         # -> ink
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
