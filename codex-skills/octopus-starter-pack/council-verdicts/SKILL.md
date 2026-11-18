---
name: council-verdicts
description: "Starter: interpret a council run's verdict artifacts — quorum, dissent, cross-lab validity, and what to do next"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, then bind `OCTO_ROOT` to it in each fresh shell or use the verified absolute helper path. Do not infer it from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$council-verdicts` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


# Council Verdict Interpretation (Starter Pack)

Read a completed council run's artifacts and explain what the verdicts actually mean before anyone acts on them.

## When to use

A `$skill-council` run has finished and the user asks "so what did the council decide?" or pastes a summary.json path.

## Steps

1. **Locate artifacts.** Find the newest council output under `~/.claude-octopus/results/` (look for `summary.json` and per-seat verdict files). If none exist within the session window, say so; never invent a verdict.
2. **Check roster validity.** From `summary.json`, confirm each seat's real provider and model (the agy seat records its resolved model, not `default`). Flag same-lineage panels: two seats backed by the same model family weaken the verdict's independence.
3. **Tally the verdicts.** Report the raw count (APPROVE / REJECT / ABSTAIN / REVISE) and whether quorum was met. A malformed or missing verdict from a seat counts as ABSTAIN, and the SubagentStop gate (`hooks/subagent-stop-gate.sh`) may have flagged it; check the gate's usage log for quality scores.
4. **Surface dissent.** Quote the strongest dissenting argument verbatim. A 2-1 split with a substantive dissent is a weaker mandate than 3-0; say which one this is.
5. **Recommend the action.** Map the tally to a next step: unanimous APPROVE means proceed; majority with dissent means proceed with the dissent's concern as a follow-up item; majority REJECT means do not proceed and list what would change the outcome.

## Guardrails

- Verdicts gate decisions; they do not execute them. Never auto-apply a council outcome to code.
- If seats disagree on facts (not judgment), the run is inconclusive; recommend a re-run with the factual dispute resolved first.
