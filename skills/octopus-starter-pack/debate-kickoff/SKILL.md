---
name: debate-kickoff
description: "Starter: frame a decision as a multi-model debate — picks sides, seats providers, and launches /octo:debate with a well-formed motion"
---

# Debate Kickoff (Starter Pack)

Turn a loosely stated decision ("Redis or Memcached?", "monorepo vs polyrepo") into a well-formed multi-model debate.

## When to use

The user has a two-or-more-sided technical decision and wants adversarial perspectives from different model families rather than one model's opinion.

## Steps

1. **Extract the motion.** Restate the user's question as a single debatable proposition (for example: "This project should use Redis over Memcached for session storage"). Confirm silently from context; do not interrogate the user.
2. **Check seats.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/helpers/check-providers.sh` and note which providers are available. A debate needs at least two seatable non-Claude providers for cross-lab disagreement; if only Claude is available, say so and offer a single-model pro/con instead.
3. **Assign sides.** Give each available provider an explicit stance (affirmative, negative, or skeptic). Prefer cross-lab pairings (for example Codex affirmative, Antigravity negative) so disagreement is structural, not stylistic.
4. **Launch.** Invoke `/octo:debate` with the motion and the side assignments. Display the standard Octopus banner with provider indicators before dispatch.
5. **Synthesize.** After rounds complete, summarize where the models converged, where they genuinely disagreed, and give one recommendation with the strongest surviving argument.

## Guardrails

- External seats cost money; state the expected cost band from the CLAUDE.md cost table before dispatch.
- Never fabricate a provider's position. If a seat fails, report the failure and continue with the remaining seats.
