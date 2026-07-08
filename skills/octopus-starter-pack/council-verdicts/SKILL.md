---
name: council-verdicts
description: "Starter: interpret a council run's verdict artifacts — quorum, dissent, cross-lab validity, and what to do next"
---

# Council Verdict Interpretation (Starter Pack)

Read a completed council run's artifacts and explain what the verdicts actually mean before anyone acts on them.

## When to use

A `/octo:council` run has finished and the user asks "so what did the council decide?" or pastes a summary.json path.

## Steps

1. **Locate artifacts.** Find the newest council output under `~/.claude-octopus/results/` (look for `summary.json` and per-seat verdict files). If none exist within the session window, say so; never invent a verdict.
2. **Check roster validity.** From `summary.json`, confirm each seat's real provider and model (the agy seat records its resolved model, not `default`). Flag same-lineage panels: two seats backed by the same model family weaken the verdict's independence.
3. **Tally the verdicts.** Report the raw count (APPROVE / REJECT / ABSTAIN / REVISE) and whether quorum was met. A malformed or missing verdict from a seat counts as ABSTAIN, and the SubagentStop gate (`hooks/subagent-stop-gate.sh`) may have flagged it; check the gate's usage log for quality scores.
4. **Surface dissent.** Quote the strongest dissenting argument verbatim. A 2-1 split with a substantive dissent is a weaker mandate than 3-0; say which one this is.
5. **Recommend the action.** Map the tally to a next step: unanimous APPROVE means proceed; majority with dissent means proceed with the dissent's concern as a follow-up item; majority REJECT means do not proceed and list what would change the outcome.

## Guardrails

- Verdicts gate decisions; they do not execute them. Never auto-apply a council outcome to code.
- If seats disagree on facts (not judgment), the run is inconclusive; recommend a re-run with the factual dispute resolved first.
