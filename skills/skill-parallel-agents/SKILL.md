---
name: skill-parallel-agents
version: 1.0.0
description: "Orchestrate multiple AI providers (Codex, Gemini, Claude) through a Double Diamond workflow for research, building, review, and adversarial debate. Use when: user says 'research X', 'build X', 'review X', runs /octo:multi, /octo:embrace, or requests multi-provider analysis with 'run with all providers'."
---

# Claude Octopus - Multi-Tentacled Orchestrator

Multi-AI orchestrator using Double Diamond methodology: Discover (probe), Define (grasp), Develop (tangle), Deliver (ink).

## Quick Start

Talk naturally -- no commands needed:
- "Research OAuth authentication patterns" -> probe
- "Build a user authentication system" -> tangle + ink
- "Review this code for security issues" -> ink

CLI usage:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh embrace "Build a user authentication system"  # Full workflow
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh probe "Research auth best practices"          # Discover
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh auto "build user login"                       # Auto-routed
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh grapple "implement password reset API"        # Adversarial
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze "review auth.ts for vulnerabilities"  # Red Team
```

## When NOT to Use This Skill

DO NOT activate for: built-in Claude Code commands (`/plugin`, `/init`, `/help`, `/clear`, `/commit`, `/remember`), simple file operations, git commands, or Claude Code configuration. Use standard tools instead.

## Visual Indicators

| Indicator | Provider | Cost |
|-----------|----------|------|
| Codex CLI | OpenAI (your OPENAI_API_KEY) | ~$0.01-0.05/query |
| Gemini CLI | Google (your GEMINI_API_KEY) | ~$0.01-0.03/query |
| Claude | Claude Code subscription | Included |

External CLIs execute for workflows (probe, grasp, tangle, ink, embrace, grapple, squeeze). Claude subagents handle simple file/git operations at no extra cost.

## Force Multi-Provider Mode

Use `/octo:multi` or say "run with all providers" to force multi-AI analysis even for simple tasks.

**Use for**: High-stakes decisions, comparing model perspectives, tasks where auto-routing underestimates complexity.

**Avoid for**: Tasks that already auto-trigger workflows, simple factual questions, file operations.

## Prerequisites (Automatic Detection)

Run provider detection immediately on activation:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh detect-providers
```

- Both providers missing: Show welcome message, suggest `/octo:setup`, STOP
- Claude Code outdated: Show update instructions, STOP
- One provider available: Proceed immediately
- Both available: Proceed with full multi-provider analysis

Provider cache at `~/.claude-octopus/.provider-cache` is valid for 1 hour.

## Double Diamond Workflow

### Phase 1: PROBE (Discover)
Parallel research: problem space, existing solutions, edge cases, feasibility.

### Phase 2: GRASP (Define)
Consensus building: core problem statement, success criteria, constraints.

### Phase 3: TANGLE (Develop)
Map-reduce with quality gate (75% threshold): task decomposition, parallel execution.

### Phase 4: INK (Deliver)
Validation: quality gate verification, synthesis, final deliverable.

### EMBRACE: All 4 phases sequentially with automatic context passing.

## Crossfire: Adversarial Review

### GRAPPLE
Codex and Gemini each propose solutions, critique each other, synthesis picks winner.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh grapple --principles security "implement JWT auth"
```

### SQUEEZE
Blue Team (Codex) implements, Red Team (Gemini) attacks, then remediation and validation.

### Principles: `general`, `security` (OWASP), `performance` (N+1, caching), `maintainability` (clean code)

## Auto-Routing

| Keywords | Routes To |
|----------|-----------|
| research, explore, investigate | `probe` |
| develop, build, implement | `tangle` + `ink` |
| qa, test, review, validate | `ink` |
| security audit, red team | `squeeze` |
| adversarial, debate | `grapple` |

## Quality Gates

| Score | Status |
|-------|--------|
| >= 90% | PASSED - proceed |
| 75-89% | WARNING - proceed with caution |
| < 75% | FAILED - flags for review |

## Command Reference

| Command | Description |
|---------|-------------|
| `probe <prompt>` | Parallel research with synthesis |
| `grasp <prompt>` | Problem definition consensus |
| `tangle <prompt>` | Map-reduce with quality gates |
| `ink <prompt>` | Validation and delivery |
| `embrace <prompt>` | Full 4-phase workflow |
| `grapple <prompt>` | Adversarial debate |
| `squeeze <prompt>` | Red Team security review |
| `auto <prompt>` | Smart intent-based routing |
| `spawn <agent> <prompt>` | Single agent execution |
| `detect-providers` | Check provider availability |

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `-p, --parallel` | 3 | Max concurrent agents |
| `-t, --timeout` | 300 | Timeout per task (seconds) |
| `--context <file>` | - | Context from previous phase |
| `--provider <name>` | - | Force specific provider |
| `--cost-first` | - | Prefer cheapest provider |
| `--quality-first` | - | Prefer highest-tier provider |

## Agent Selection

| Agent | Model | Best For |
|-------|-------|----------|
| `codex` | gpt-5.3-codex | Complex code, deep refactoring |
| `codex-mini` | gpt-5.4-mini | Quick fixes |
| `gemini` | gemini-3-pro-preview | Deep analysis, 1M context |
| `gemini-fast` | gemini-3-flash-preview | Speed-critical tasks |

## Provider-Aware Routing

Routes by subscription tier: `balanced` (default), `cost-first`, `quality-first`. Config at `~/.claude-octopus/.providers-config`.

## Workspace

```
~/.claude-octopus/
├── results/    # Synthesis, consensus, validation, delivery files
├── logs/       # Execution logs
└── plans/      # Execution plan history
```
