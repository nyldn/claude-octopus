---
command: octo:embrace
description: "Full Double Diamond workflow - Research → Define → Develop → Deliver"
aliases:
  - full-cycle
  - complete-workflow
---

# Embrace - Complete Double Diamond Workflow

Run the **complete 4-phase Double Diamond workflow** from research to delivery.

## Usage

```bash
/octo:embrace        # Full workflow with natural language
```

## What is Embrace?

**Embrace** 🐙 runs all four phases of the Double Diamond methodology in sequence:

1. **Discover** - Multi-perspective research (Codex + Gemini)
2. **Define** - Consensus building on problem/approach
3. **Develop** - Implementation with quality validation
4. **Deliver** - Final quality gates and output

## Natural Language Examples

Just describe what you want to build:

```
"Build a complete user authentication system"
"Create a caching layer from research to delivery"
"Design and implement a payment processing feature"
```

Claude will automatically use the embrace workflow for complex features that need thorough exploration.

## Autonomy Modes

You can configure how much human oversight you want:

- **Supervised** (default) - Approval required after each phase
- **Semi-autonomous** - Approval only when quality gates fail
- **Autonomous** - Runs all 4 phases automatically

Set in `/octo:setup` or use orchestrate.sh flags:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh embrace --autonomy supervised "your prompt"
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh embrace --autonomy autonomous "your prompt"
```

## When to Use Embrace

Use embrace for:
- Complex features requiring research → implementation
- High-stakes projects needing validation
- Features where you want multiple AI perspectives
- When you need structured quality gates

Don't use for:
- Simple bug fixes or edits
- Quick research-only tasks (use discover phase)
- Code review only (use deliver phase)

## Quality Gates

The tangle (develop) phase includes automatic quality validation:
- 75% consensus threshold
- Security checks
- Best practices verification
- Performance considerations

If quality gates fail in semi-autonomous mode, you'll be prompted to review.

## Learn More

- `/octo:discover` - Run just the research phase
- `/octo:define` - Run just the definition phase
- `/octo:develop` - Run just the development phase
- `/octo:deliver` - Run just the delivery/review phase
