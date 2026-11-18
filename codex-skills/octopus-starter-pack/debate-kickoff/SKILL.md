---
name: debate-kickoff
description: "Starter: frame a decision as a multi-model debate — picks sides, seats providers, and launches /octo:debate with a well-formed motion"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, bind `OCTO_ROOT`, `CODEX_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_ROOT` to the same root, and export all three in each fresh shell before launching child processes. Use the verified absolute helper path when needed. Do not infer the root from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$debate-kickoff` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


# Debate Kickoff (Starter Pack)

Turn a loosely stated decision ("Redis or Memcached?", "monorepo vs polyrepo") into a well-formed multi-model debate.

## When to use

The user has a two-or-more-sided technical decision and wants adversarial perspectives from different model families rather than one model's opinion.

## Steps

1. **Extract the motion.** Restate the user's question as a single debatable proposition (for example: "This project should use Redis over Memcached for session storage"). Confirm silently from context; do not interrogate the user.
2. **Check seats.** Run `${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${OCTO_ROOT:-${HOME}/.claude-octopus/plugin}}}/scripts/helpers/check-providers.sh` and note which providers are available. A debate needs at least two seatable non-Claude providers for cross-lab disagreement; if only Claude is available, say so and offer a single-model pro/con instead.
3. **Assign sides.** Give each available provider an explicit stance (affirmative, negative, or skeptic). Prefer cross-lab pairings (for example Codex affirmative, Antigravity negative) so disagreement is structural, not stylistic.
4. **Launch.** Invoke `$skill-debate` with the motion and the side assignments. Display the standard Octopus banner with provider indicators before dispatch.
5. **Synthesize.** After rounds complete, summarize where the models converged, where they genuinely disagreed, and give one recommendation with the strongest surviving argument.

## Guardrails

- External seats cost money; state the expected cost band from the CLAUDE.md cost table before dispatch.
- Never fabricate a provider's position. If a seat fails, report the failure and continue with the remaining seats.
