---
name: model-cost-compare
description: "Starter: compare model costs for a described task — maps task shape to the cheapest adequate seat and shows the price spread"
---

# Model Cost Comparison (Starter Pack)

Answer "which model should I use for this, and what will it cost?" with numbers instead of vibes.

## When to use

The user describes a task (bulk refactor, deep review, quick lookup, long-context analysis) and wants the cheapest seat that is still adequate.

## Steps

1. **Classify the task.** Bucket it: mechanical (rename, format), standard coding, hard reasoning (architecture, security review), long-context (>200K tokens input), or web research.
2. **Estimate volume.** Rough input/output token estimate from the described scope (files touched × average size; state the assumption).
3. **Price the roster.** Using the cost table in CLAUDE.md ($/MTok input/output), compute the estimated cost for each plausible seat: Claude Opus 4.8 ($5/$25), Fable 5 ($10/$50, 1M context, opt-in), Codex GPT-5.5 ($5/$30), Perplexity Sonar Pro ($3/$15), and the included-cost seats (agy, copilot, ollama, cursor-agent) at $0.
4. **Recommend one seat.** Pick the cheapest adequate option and defend it in two sentences. Mechanical work goes to included seats; hard reasoning justifies Opus 4.8 at `xhigh` effort; only 1M-context needs justify Fable 5 or the claude-sdk seat.
5. **Show the spread.** A three-row table: recommended seat, one cheaper-but-riskier option, one premium option, each with estimated dollars for this task.

## Guardrails

- Never recommend Fable 5 or fast-mode Opus by default; both are 2x standard Opus cost and are opt-in only.
- If the estimate exceeds $1, say so explicitly before any dispatch happens.
