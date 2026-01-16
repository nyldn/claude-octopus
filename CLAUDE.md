# Claude Octopus - Plugin Usage Guide

Claude Octopus is a **Multi-tentacled orchestrator** plugin for Claude Code that coordinates multiple AI CLIs (Codex, Gemini, Claude) using **Double Diamond methodology**. It provides structured workflows for comprehensive problem solving.

> **For plugin developers**: See [.claude/DEVELOPMENT.md](.claude/DEVELOPMENT.md) for architecture and contribution guidelines.

## Quick Start

```bash
# Initialize workspace
./scripts/orchestrate.sh init

# Pre-flight check (verify all dependencies)
./scripts/orchestrate.sh preflight

# Run setup wizard (configures providers and preferences)
./scripts/orchestrate.sh setup

# Check provider status
./scripts/orchestrate.sh status
```

## Double Diamond Commands

| Command | Phase | Description |
|---------|-------|-------------|
| `probe <prompt>` | Discover | Parallel research with AI synthesis |
| `grasp <prompt>` | Define | Consensus building on problem definition |
| `tangle <prompt>` | Develop | Enhanced map-reduce with quality gates |
| `ink <prompt>` | Deliver | Validation and final delivery |
| `embrace <prompt>` | All 4 | Full Double Diamond workflow |

### Smart Auto-Routing

The `auto` command detects intent and routes to the appropriate workflow:

```bash
./scripts/orchestrate.sh auto "research OAuth patterns"      # -> probe
./scripts/orchestrate.sh auto "build user login"             # -> tangle + ink
./scripts/orchestrate.sh auto "review the auth code"         # -> ink
```

| Keywords | Routes To |
|----------|-----------|
| research, explore, investigate | `probe` |
| develop, dev, build, implement | `tangle` + `ink` |
| qa, test, review, validate | `ink` |
| (other) | Single agent |

## Crossfire: Adversarial Review

### GRAPPLE - Adversarial Debate
Two models propose solutions, then critique each other's work:

```bash
./scripts/orchestrate.sh grapple "implement password reset API"
./scripts/orchestrate.sh grapple --principles security "implement JWT auth"
```

### SQUEEZE - Red Team Security Review
Blue Team implements, Red Team attacks to find vulnerabilities:

```bash
./scripts/orchestrate.sh squeeze "implement user login form"
```

## Provider-Aware Routing

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

## Environment Variables

```bash
OPENAI_API_KEY="sk-..."                      # Required for Codex CLI
GEMINI_API_KEY="AIza..."                     # Required for Gemini CLI
OPENROUTER_API_KEY="sk-or-..."               # Optional: Universal fallback
CLAUDE_OCTOPUS_WORKSPACE="~/.claude-octopus" # Optional workspace override
```

## Quality Gates

The `tangle` phase enforces quality gates:

| Score | Status | Behavior |
|-------|--------|----------|
| >= 90% | PASSED | Proceed to ink |
| 75-89% | WARNING | Proceed with caution |
| < 75% | FAILED | Ink phase flags for review |

## Common Options

| Option | Default | Description |
|--------|---------|-------------|
| `-p, --parallel` | 3 | Max concurrent agents |
| `-t, --timeout` | 300 | Timeout per task (seconds) |
| `-v, --verbose` | false | Verbose logging |
| `-n, --dry-run` | false | Show without executing |
| `--context <file>` | - | Context from previous phase |

## Tasks JSON Format

For complex workflows, define tasks in JSON:

```json
{
  "version": "1.0",
  "project": "my-project",
  "tasks": [
    {
      "id": "task-1",
      "agent": "codex",
      "prompt": "Implement feature X",
      "priority": 1,
      "depends_on": []
    },
    {
      "id": "task-2",
      "agent": "gemini",
      "prompt": "Review task-1 output",
      "priority": 2,
      "depends_on": ["task-1"]
    }
  ],
  "settings": {
    "max_parallel": 3,
    "timeout": 300,
    "retry_on_failure": true
  }
}
```

Run with: `./scripts/orchestrate.sh parallel tasks.json`

## Troubleshooting

### Pre-flight check fails
```bash
./scripts/orchestrate.sh preflight
# Verify: codex CLI, gemini CLI, API keys
```

### Quality gate failures
- Break task into smaller subtasks
- Increase timeout with `-t 600`
- Check logs in `~/.claude-octopus/logs/`

### Reset workspace
```bash
./scripts/orchestrate.sh clean
./scripts/orchestrate.sh init
```
