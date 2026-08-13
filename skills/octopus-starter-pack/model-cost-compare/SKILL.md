---
name: model-cost-compare
disable-model-invocation: true
description: "Starter: compare model costs for a described task — maps task shape to the cheapest adequate seat and shows the price spread"
---

# Model Cost Comparison (Starter Pack)

Answer "which model should I use for this, and what will it cost?" with numbers instead of vibes.

## When to use

The user describes a task (bulk refactor, deep review, quick lookup, long-context analysis) and wants the cheapest seat that is still adequate.

## Steps

1. **Classify the task.** Bucket it: mechanical (rename, format), standard coding, hard reasoning (architecture, security review), long-context (>200K tokens input), or web research.
2. **Estimate volume.** Rough input/output token estimate from the described scope (files touched × average size; state the assumption).
3. **Price the roster.** Using the cost table in CLAUDE.md ($/MTok input/output), compute the estimated cost for each plausible seat: Claude Opus 5 ($5/$25), Claude Sonnet 5 ($3/$15), Fable 5 ($10/$50, 1M context, opt-in), Codex GPT-5.6 Sol ($5/$30), Terra ($2.50/$15), Luna ($1/$6), Perplexity Sonar Pro ($3/$15), and the included-cost seats (agy, copilot, ollama, cursor-agent) at $0.
4. **Recommend one seat.** Pick the cheapest adequate option and defend it in two sentences. Mechanical work goes to included or budget seats; hard reasoning justifies Opus 5 at `high` effort; only a bounded judgment-class call (ambiguous architecture, API design, product tradeoffs) justifies Fable 5 at twice the Opus price.
5. **Check risk surfaces.** Regardless of the classification, escalate specifically to Opus 5 when the task touches API or schema contracts, security-sensitive code or CI configuration, release artifacts, user-facing UI, a new module, or a breaking change. Fable 5 remains limited to bounded judgment-class calls and is never the security-audit seat. Cheap-seat agreement never settles a judgment-class decision.
6. **Show the spread.** A three-row table: recommended seat, one cheaper-but-riskier option, one premium option, each with estimated dollars for this task.

## Guardrails

- Never recommend Fable 5 or fast-mode Opus by default; both are 2x standard Opus cost and are opt-in only.
- Never recommend Fable 5 for security audits; its safety classifiers can refuse offensive-security phrasing. Security review goes to Opus 5 (see `skills/blocks/fable5-prompting.md`).
- If the estimate exceeds $1, say so explicitly before any dispatch happens.
