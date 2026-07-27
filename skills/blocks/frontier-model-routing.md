# Frontier Model Routing

Apply this policy whenever a workflow chooses models or authors prompts for
Opus 5, Fable 5, Sonnet 5, or the GPT-5.6 Codex family.

## Default roster

- **Opus 5 is the premium lead.** Use it for ambiguous architecture, planning,
  security reasoning, product tradeoffs, and final judgment. Run at `high`
  effort by default. Raise effort only for a bounded step whose difficulty
  justifies the extra time and cost.
- **GPT-5.6 Sol is the independent coding peer.** Use it for implementation,
  terminal-heavy work, edge-case review, and a second opinion where vendor
  diversity matters. Terra and Luna are balanced and budget alternatives.
- **Sonnet 5 is the standard Claude seat.** Use it for synthesis, routine
  orchestration, and work that benefits from Claude behavior without premium
  Opus cost. Haiku 4.5 is the budget Claude seat.
- **Fable 5 is an opt-in escalation, not a default.** Use it for judgment-class
  work only when the expected gain justifies twice the Opus 5 price. Apply
  `skills/blocks/fable5-prompting.md` and never count Fable plus Opus as
  provider diversity.
- **Other providers need a distinct job.** Use Antigravity or Perplexity for
  research, local/included seats for mechanical work, and specialized models
  only when their capability changes the expected result.

## One owner before a council

Start generic, mergeable work with one capable owner. Add another model when it
has a distinct responsibility: research, implementation, adversarial review,
security review, or final verification. Explicit debate, council, squeeze, and
multi-model commands still fan out because disagreement is their product.

Do not create multiple agents that will make the same edits or answer the same
question merely to increase model count. Anthropic-family agreement is not an
independent cross-provider check.

## Prompt shape

For Opus 5 and Sonnet 5, state the goal, important context, boundaries, and
checkable acceptance criteria. Explain the reason behind unusual constraints.
Avoid duplicated reminders, performative all-caps emphasis, token countdowns,
and instructions to reveal hidden reasoning. Ask for a concise rationale,
evidence, or decision record instead.

Let the harness own permissions, tool access, context limits, and model
selection. A model upgrade must never broaden write authority, skip repository
quality gates, or override an explicit user/config pin.

## Resolution precedence

Existing configuration is authoritative:

1. explicit environment or session override;
2. role/phase route in `providers.json`;
3. cost tier;
4. current-model fallback.

Fresh configurations use Opus 5, Sonnet 5, and GPT-5.6 defaults. Existing
configurations are not silently rewritten to those models.
